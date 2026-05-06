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

from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from src.auth.auth_guard import RoleChecker, get_current_user
from src.auth.oidc_verifier import (
    TokenValidationError,
    VerifiedClaims,
    reset_oidc_verifier_for_tests,
)
from src.users.user_model import UserModel, UserRoleEnum


@pytest.fixture(autouse=True)
def _reset_verifier_singleton():
    reset_oidc_verifier_for_tests()
    yield
    reset_oidc_verifier_for_tests()


@pytest.fixture(name="mock_user_service")
def fixture_mock_user_service():
    service = AsyncMock()
    service.create_user_if_not_exists.return_value = UserModel(
        id=1,
        email="test@example.com",
        roles=["user"],
        name="Test User",
    )
    return service


def _claims(**overrides) -> VerifiedClaims:
    base = {
        "subject": "user-123",
        "email": "test@example.com",
        "email_verified": True,
        "name": "Test User",
        "picture": "http://example.com/pic.jpg",
        "groups": [],
        "raw": {},
    }
    base.update(overrides)
    return VerifiedClaims(**base)


class TestGetCurrentUser:
    @pytest.mark.anyio
    @patch("src.auth.auth_guard.get_oidc_verifier")
    async def test_success(self, mock_get_verifier, mock_user_service):
        verifier = AsyncMock()
        verifier.verify.return_value = _claims()
        mock_get_verifier.return_value = verifier

        user = await get_current_user(
            token="valid_token",
            user_service=mock_user_service,
        )

        assert user.email == "test@example.com"
        mock_user_service.create_user_if_not_exists.assert_awaited_once_with(
            email="test@example.com",
            name="Test User",
            picture="http://example.com/pic.jpg",
        )

    @pytest.mark.anyio
    async def test_missing_token_returns_401(self, mock_user_service):
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(token=None, user_service=mock_user_service)
        assert exc_info.value.status_code == 401

    @pytest.mark.anyio
    @patch("src.auth.auth_guard.get_oidc_verifier")
    async def test_invalid_signature_returns_401(
        self, mock_get_verifier, mock_user_service
    ):
        verifier = AsyncMock()
        verifier.verify.side_effect = TokenValidationError("Invalid token: bad sig")
        mock_get_verifier.return_value = verifier

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(
                token="bad_token", user_service=mock_user_service
            )
        assert exc_info.value.status_code == 401

    @pytest.mark.anyio
    @patch("src.auth.auth_guard.get_oidc_verifier")
    async def test_disallowed_domain_returns_403(
        self, mock_get_verifier, mock_user_service
    ):
        verifier = AsyncMock()
        verifier.verify.side_effect = TokenValidationError(
            "Email domain 'forbidden.com' not in allowlist."
        )
        mock_get_verifier.return_value = verifier

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(
                token="valid_token", user_service=mock_user_service
            )
        assert exc_info.value.status_code == 403

    @pytest.mark.anyio
    @patch("src.auth.auth_guard.get_oidc_verifier")
    async def test_missing_email_returns_403(
        self, mock_get_verifier, mock_user_service
    ):
        verifier = AsyncMock()
        verifier.verify.return_value = _claims(email=None)
        mock_get_verifier.return_value = verifier

        with pytest.raises(HTTPException) as exc_info:
            await get_current_user(
                token="valid_token", user_service=mock_user_service
            )
        assert exc_info.value.status_code == 403


class TestRoleChecker:
    def test_role_checker_authorized(self):
        checker = RoleChecker(allowed_roles=[UserRoleEnum.ADMIN])
        user = UserModel(
            id=1,
            email="admin@example.com",
            roles=["admin"],
            name="Admin User",
        )
        assert checker(user=user) is user

    def test_role_checker_forbidden(self):
        checker = RoleChecker(allowed_roles=[UserRoleEnum.ADMIN])
        user = UserModel(
            id=1,
            email="user@example.com",
            roles=["user"],
            name="Regular User",
        )
        with pytest.raises(HTTPException) as exc_info:
            checker(user=user)
        assert exc_info.value.status_code == 403
