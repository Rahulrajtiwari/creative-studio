# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Tests for the /api/auth/token BFF proxy."""

from __future__ import annotations

from contextlib import contextmanager
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

from main import app
from src.auth import auth_controller
from src.config.config_service import config_service

CLIENT_ID = "test-client.apps.googleusercontent.com"
CLIENT_SECRET = "GOCSPX-supersecret"
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
ISSUER = "https://accounts.google.com"


@pytest.fixture(autouse=True)
def _reset_discovery_cache():
    auth_controller._reset_discovery_cache_for_tests()
    yield
    auth_controller._reset_discovery_cache_for_tests()


@pytest.fixture(name="configured")
def fixture_configured(monkeypatch):
    """Configure ConfigService with an issuer + client_id + client_secret."""
    monkeypatch.setattr(config_service, "OIDC_ISSUER", ISSUER)
    monkeypatch.setattr(config_service, "OIDC_CLIENT_ID", CLIENT_ID)
    monkeypatch.setattr(config_service, "OIDC_CLIENT_SECRET", CLIENT_SECRET)


@pytest.fixture(name="client")
def fixture_client():
    return TestClient(app)


@contextmanager
def _mock_httpx(*, discovery: dict | None = None, token: tuple[int, dict] | None = None):
    """Patch httpx.AsyncClient to return canned discovery + token responses.

    The auth controller creates a fresh AsyncClient for each call, so we
    return a context-manager-shaped MagicMock that records every outbound
    call against `recorded_calls`.
    """
    recorded_calls: list[dict] = []

    discovery_response = MagicMock(spec=httpx.Response)
    discovery_response.json.return_value = discovery or {"token_endpoint": TOKEN_ENDPOINT}
    discovery_response.raise_for_status = MagicMock()
    discovery_response.status_code = 200

    token_status, token_body = token or (200, {"access_token": "abc", "token_type": "Bearer"})
    token_response = MagicMock(spec=httpx.Response)
    token_response.json.return_value = token_body
    token_response.status_code = token_status

    get_mock = AsyncMock(return_value=discovery_response)
    post_mock = AsyncMock(return_value=token_response)

    async def _record_get(url, *args, **kwargs):
        recorded_calls.append({"method": "GET", "url": url, "kwargs": kwargs})
        return await get_mock(url, *args, **kwargs)

    async def _record_post(url, *args, **kwargs):
        recorded_calls.append({"method": "POST", "url": url, "kwargs": kwargs})
        return await post_mock(url, *args, **kwargs)

    class _AsyncClientCM:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            inner = MagicMock()
            inner.get = _record_get
            inner.post = _record_post
            return inner

        async def __aexit__(self, exc_type, exc, tb):
            return False

    with patch.object(auth_controller.httpx, "AsyncClient", _AsyncClientCM):
        yield recorded_calls


def test_rejects_when_secret_missing(client, monkeypatch):
    monkeypatch.setattr(config_service, "OIDC_CLIENT_SECRET", "")
    monkeypatch.setattr(config_service, "OIDC_ISSUER", ISSUER)
    resp = client.post(
        "/api/auth/token",
        data={"grant_type": "authorization_code", "client_id": CLIENT_ID},
    )
    assert resp.status_code == 503
    assert "OIDC_CLIENT_SECRET" in resp.json()["detail"]


def test_rejects_unknown_grant_type(client, configured):
    resp = client.post(
        "/api/auth/token",
        data={"grant_type": "password", "client_id": CLIENT_ID},
    )
    assert resp.status_code == 400
    assert "grant_type" in resp.json()["detail"]


def test_rejects_unknown_client_id(client, configured):
    resp = client.post(
        "/api/auth/token",
        data={"grant_type": "authorization_code", "client_id": "evil-client"},
    )
    assert resp.status_code == 400
    assert "client_id" in resp.json()["detail"]


def test_forwards_authorization_code_with_secret(client, configured):
    with _mock_httpx() as calls:
        resp = client.post(
            "/api/auth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": CLIENT_ID,
                "code": "auth-code-xyz",
                "code_verifier": "pkce-verifier-1234",
                "redirect_uri": "https://app.example.com/",
            },
        )
    assert resp.status_code == 200
    assert resp.json() == {"access_token": "abc", "token_type": "Bearer"}

    # 1 discovery GET + 1 token POST.
    methods = [c["method"] for c in calls]
    assert methods == ["GET", "POST"]
    assert calls[0]["url"] == f"{ISSUER}/.well-known/openid-configuration"
    assert calls[1]["url"] == TOKEN_ENDPOINT

    posted = calls[1]["kwargs"]["data"]
    assert posted["grant_type"] == "authorization_code"
    assert posted["client_id"] == CLIENT_ID
    assert posted["code"] == "auth-code-xyz"
    assert posted["code_verifier"] == "pkce-verifier-1234"
    assert posted["redirect_uri"] == "https://app.example.com/"
    # The crucial assertion: the secret was added server-side.
    assert posted["client_secret"] == CLIENT_SECRET


def test_strips_client_supplied_secret(client, configured):
    """A malicious caller cannot override the server's client_secret."""
    with _mock_httpx() as calls:
        resp = client.post(
            "/api/auth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": CLIENT_ID,
                "code": "code",
                "client_secret": "ATTACKER-SUPPLIED",
            },
        )
    assert resp.status_code == 200
    posted = calls[1]["kwargs"]["data"]
    assert posted["client_secret"] == CLIENT_SECRET


def test_caches_discovery_across_calls(client, configured):
    with _mock_httpx() as calls:
        for _ in range(3):
            client.post(
                "/api/auth/token",
                data={
                    "grant_type": "authorization_code",
                    "client_id": CLIENT_ID,
                    "code": "c",
                },
            )
    # Discovery should fire exactly once; the next two requests reuse it.
    assert sum(1 for c in calls if c["method"] == "GET") == 1
    assert sum(1 for c in calls if c["method"] == "POST") == 3


def test_propagates_upstream_4xx(client, configured):
    with _mock_httpx(
        token=(400, {"error": "invalid_grant", "error_description": "code expired"})
    ):
        resp = client.post(
            "/api/auth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": CLIENT_ID,
                "code": "expired",
            },
        )
    assert resp.status_code == 400
    assert resp.json() == {
        "error": "invalid_grant",
        "error_description": "code expired",
    }


def test_502_when_discovery_doc_lacks_token_endpoint(client, configured):
    with _mock_httpx(discovery={"issuer": ISSUER}):  # no token_endpoint
        resp = client.post(
            "/api/auth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": CLIENT_ID,
                "code": "c",
            },
        )
    assert resp.status_code == 502
    assert "token_endpoint" in resp.json()["detail"]


def test_502_when_token_endpoint_is_not_https(client, configured):
    with _mock_httpx(discovery={"token_endpoint": "http://evil.example/token"}):
        resp = client.post(
            "/api/auth/token",
            data={
                "grant_type": "authorization_code",
                "client_id": CLIENT_ID,
                "code": "c",
            },
        )
    assert resp.status_code == 502
    assert "HTTPS" in resp.json()["detail"]


def test_refresh_token_grant_is_allowed(client, configured):
    with _mock_httpx(
        token=(200, {"access_token": "new", "token_type": "Bearer"})
    ) as calls:
        resp = client.post(
            "/api/auth/token",
            data={
                "grant_type": "refresh_token",
                "client_id": CLIENT_ID,
                "refresh_token": "rt-1",
            },
        )
    assert resp.status_code == 200
    posted = calls[1]["kwargs"]["data"]
    assert posted["grant_type"] == "refresh_token"
    assert posted["refresh_token"] == "rt-1"
    assert posted["client_secret"] == CLIENT_SECRET
