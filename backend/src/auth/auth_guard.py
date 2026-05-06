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
"""Authentication guard: bearer-token verification + JIT user provisioning.

Auth flow on a per-request basis:

1. FastAPI extracts the `Authorization: Bearer <token>` header via
   `OAuth2PasswordBearer`.
2. The token is verified by `OIDCVerifier` (signature, iss, aud, exp,
   email_verified, domain/group allowlist, optional azp pinning).
3. The verified claims are mapped onto the application's `UserModel` and any
   user that does not yet exist in Postgres is JIT-provisioned.
4. Optional `RoleChecker` dependencies enforce per-route RBAC against the
   user's stored roles (admin remains a DB-driven concept; group claims can be
   used to keep DB roles in sync in `UserService`).
"""

from __future__ import annotations

import logging

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

from src.auth.oidc_verifier import (
    OIDCConfigError,
    TokenValidationError,
    VerifiedClaims,
    get_oidc_verifier,
)
from src.users.user_model import UserModel, UserRoleEnum
from src.users.user_service import UserService

logger = logging.getLogger(__name__)

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token", auto_error=False)


async def get_current_user(
    token: str | None = Depends(oauth2_scheme),
    user_service: UserService = Depends(UserService),
) -> UserModel:
    """Dependency that authenticates the caller and returns the app `UserModel`.

    Raises 401 on any token validation failure, 403 when the token is valid
    but the principal is not authorized for the application.
    """
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        verifier = get_oidc_verifier()
    except OIDCConfigError as exc:
        logger.error("OIDC verifier misconfigured: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Authentication is not configured on the server.",
        ) from exc

    try:
        claims: VerifiedClaims = await verifier.verify(token)
    except TokenValidationError as exc:
        logger.warning("Token rejected: %s", exc)
        # Distinguish "valid token but not allowed" -> 403 from
        # "couldn't validate the token" -> 401.
        msg = str(exc).lower()
        if (
            "domain" in msg
            or "group" in msg
            or "azp" in msg
            or "email_verified" in msg
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=str(exc),
            ) from exc
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": 'Bearer error="invalid_token"'},
        ) from exc

    if not claims.email:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Token did not include an email claim; cannot provision user.",
        )

    user_doc = await user_service.create_user_if_not_exists(
        email=claims.email,
        name=claims.name or claims.email,
        picture=claims.picture or "",
    )

    if not user_doc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Could not create or retrieve user profile.",
        )

    if claims.picture and user_doc.picture != claims.picture and user_doc.id:
        logger.info("Updating picture for user: %s", claims.email)
        user_doc.picture = claims.picture
        await user_service.user_repo.update(user_doc.id, {"picture": claims.picture})

    return user_doc


class RoleChecker:
    """Dependency that checks the authenticated user has at least one of the
    allowed roles. Re-uses `get_current_user` so authentication runs first.
    """

    def __init__(self, allowed_roles: list[UserRoleEnum]):
        self.allowed_roles = allowed_roles

    def __call__(self, user: UserModel = Depends(get_current_user)) -> UserModel:
        if not any(role in self.allowed_roles for role in user.roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have sufficient permissions to perform this action.",
            )
        return user
