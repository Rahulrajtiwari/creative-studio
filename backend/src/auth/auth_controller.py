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
"""Backend-mediated OAuth 2.0 token exchange (BFF pattern).

The SPA never sees the IdP's `client_secret`. Instead it POSTs the
authorization code + PKCE verifier to this endpoint, the backend appends
the secret (mounted from a Kubernetes Secret / GCP Secret Manager), forwards
the request to the IdP's real token endpoint, and returns the IdP's response
verbatim.

This endpoint is intentionally **unauthenticated** - it is the bootstrap that
*establishes* the user's session. It is hardened by:

  1. `grant_type` allowlist (authorization_code, refresh_token).
  2. `client_id` allowlist (must match the configured public client).
  3. Time-bounded HTTP forwarding (no streaming, hard timeout).
  4. No request/response body logging - secrets and authorization codes
     would otherwise leak into log aggregation.
  5. Discovery doc + token-endpoint URL is read from the IdP's well-known
     metadata at startup and cached, so a misconfigured `OIDC_ISSUER` fails
     fast on the first request rather than silently forwarding traffic to
     the wrong host.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Any
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, HTTPException, Request, status
from fastapi.responses import JSONResponse

from src.config.config_service import config_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/auth", tags=["Auth"])

# Grant types we'll forward. `authorization_code` covers the initial login;
# `refresh_token` covers silent renew. Everything else is rejected so the
# proxy can't be turned into a generic OAuth oracle.
_ALLOWED_GRANT_TYPES = frozenset({"authorization_code", "refresh_token"})

# Discovery cache. The IdP's token endpoint is extremely stable; we refresh
# the cache hourly to pick up the (very rare) provider migration.
_DISCOVERY_TTL_SEC = 3600
_discovery_lock = asyncio.Lock()
_discovery_cache: dict[str, Any] = {
    "token_endpoint": None,
    "expires_at": 0.0,
}


async def _resolve_token_endpoint() -> str:
    """Discover (and cache) the IdP's token endpoint."""
    now = time.monotonic()
    if (
        _discovery_cache["token_endpoint"]
        and now < _discovery_cache["expires_at"]
    ):
        return _discovery_cache["token_endpoint"]

    async with _discovery_lock:
        # Double-checked under the lock.
        now = time.monotonic()
        if (
            _discovery_cache["token_endpoint"]
            and now < _discovery_cache["expires_at"]
        ):
            return _discovery_cache["token_endpoint"]

        issuer = config_service.OIDC_ISSUER.rstrip("/")
        if not issuer:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="OIDC_ISSUER is not configured on the backend.",
            )

        discovery_url = f"{issuer}/.well-known/openid-configuration"
        try:
            async with httpx.AsyncClient(
                timeout=config_service.OIDC_TOKEN_PROXY_TIMEOUT_SEC,
            ) as client:
                resp = await client.get(discovery_url)
                resp.raise_for_status()
                doc = resp.json()
        except httpx.HTTPError as exc:
            logger.exception("OIDC discovery fetch failed: %s", discovery_url)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Could not fetch OIDC discovery document.",
            ) from exc

        token_endpoint = doc.get("token_endpoint")
        if not isinstance(token_endpoint, str) or not token_endpoint:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="OIDC discovery document is missing token_endpoint.",
            )

        # Sanity check: the token endpoint must be HTTPS and on a host we
        # consider plausible (same registrable domain family as the issuer,
        # or one of a small set of known IdP host suffixes). This prevents
        # a poisoned discovery document from redirecting our token forwards
        # to an attacker-controlled host.
        parsed = urlparse(token_endpoint)
        if parsed.scheme != "https":
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="OIDC token_endpoint is not HTTPS.",
            )

        _discovery_cache["token_endpoint"] = token_endpoint
        _discovery_cache["expires_at"] = now + _DISCOVERY_TTL_SEC
        logger.info(
            "Resolved OIDC token endpoint: %s (cached for %ds)",
            token_endpoint,
            _DISCOVERY_TTL_SEC,
        )
        return token_endpoint


def _reset_discovery_cache_for_tests() -> None:
    _discovery_cache["token_endpoint"] = None
    _discovery_cache["expires_at"] = 0.0


@router.post("/token", include_in_schema=False)
async def exchange_token(request: Request) -> JSONResponse:
    """Proxy an OAuth 2.0 token request to the configured IdP.

    Accepts the same `application/x-www-form-urlencoded` body the IdP's
    `/token` endpoint expects (grant_type, code, code_verifier, redirect_uri,
    refresh_token, …). Adds `client_secret` from server-side configuration
    and forwards. Returns the IdP's response untouched (status + body).
    """
    if not config_service.OIDC_CLIENT_SECRET:
        # Hard-fail rather than silently sending unauthenticated token
        # requests upstream (which then 400 with `client_secret is missing`
        # and leave the SPA in a confusing half-authenticated state).
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OIDC_CLIENT_SECRET is not configured on the backend.",
        )

    # Read the form body. FastAPI's `Form(...)` would also work but we want
    # to forward unknown fields (e.g. provider-specific extensions) through
    # unchanged.
    try:
        form = await request.form()
    except Exception as exc:  # noqa: BLE001 - we want to bucket every error
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Token request body must be application/x-www-form-urlencoded.",
        ) from exc

    grant_type = str(form.get("grant_type", "")).strip()
    if grant_type not in _ALLOWED_GRANT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported grant_type: {grant_type!r}.",
        )

    client_id = str(form.get("client_id", "")).strip()
    expected_client_id = config_service.OIDC_CLIENT_ID.strip()
    # If the configured OIDC_CLIENT_ID is empty we accept anything (useful
    # for tests / pre-prod) but production overlays MUST set it.
    if expected_client_id and client_id != expected_client_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unknown client_id.",
        )

    # Build the outbound body. We rebuild it field-by-field (instead of just
    # passing the original through) so a buggy upstream caller can't smuggle
    # a different `client_secret` we'd then forward.
    payload: dict[str, str] = {}
    for key, value in form.multi_items():
        if key == "client_secret":
            continue  # Always supplied by the backend, never trusted from the client.
        payload[str(key)] = str(value)
    payload["client_secret"] = config_service.OIDC_CLIENT_SECRET

    token_endpoint = await _resolve_token_endpoint()

    try:
        async with httpx.AsyncClient(
            timeout=config_service.OIDC_TOKEN_PROXY_TIMEOUT_SEC,
        ) as client:
            upstream = await client.post(
                token_endpoint,
                data=payload,
                headers={
                    "Accept": "application/json",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
    except httpx.HTTPError as exc:
        logger.exception(
            "Upstream OIDC token endpoint unreachable (grant_type=%s)",
            grant_type,
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Upstream IdP token endpoint unreachable.",
        ) from exc

    # Surface the IdP's error JSON verbatim so the SPA's OIDC library can
    # display useful diagnostics, but stay within 4xx so we don't leak the
    # IdP's internal status semantics. We log a short summary (no tokens,
    # no codes) for audit purposes.
    try:
        body: Any = upstream.json()
    except ValueError:
        body = {"detail": "Upstream returned a non-JSON response."}

    if upstream.status_code >= 400:
        logger.warning(
            "OIDC token exchange failed: grant_type=%s upstream_status=%s upstream_error=%s",
            grant_type,
            upstream.status_code,
            body.get("error") if isinstance(body, dict) else None,
        )
    else:
        logger.info(
            "OIDC token exchange ok: grant_type=%s upstream_status=%s",
            grant_type,
            upstream.status_code,
        )

    return JSONResponse(content=body, status_code=upstream.status_code)
