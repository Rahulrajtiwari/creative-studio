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
"""Generic OIDC ID token / access token verifier.

Validates JWTs issued by any compliant OpenID Connect provider (Okta, Entra
ID, Ping, etc.) by:

1. Discovering the issuer's JWKS endpoint via /.well-known/openid-configuration.
2. Caching JWKs in memory keyed by `kid` (with TTL + on-miss refresh).
3. Verifying signature, `iss`, `aud`, `exp`, `nbf`, and required custom claims.

The verifier does not depend on Firebase Admin or Google's `verify_oauth2_token`.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Any

import httpx
import jwt
from jwt import InvalidTokenError, PyJWKClient, PyJWKClientError

logger = logging.getLogger(__name__)


@dataclass
class VerifiedClaims:
    """Subset of validated claims the rest of the app cares about."""

    subject: str
    email: str | None
    email_verified: bool
    name: str | None
    picture: str | None
    groups: list[str] = field(default_factory=list)
    raw: dict[str, Any] = field(default_factory=dict)


class OIDCConfigError(RuntimeError):
    """Raised when the verifier is misconfigured (missing issuer / audience)."""


class TokenValidationError(Exception):
    """Wraps any token validation failure with a stable string message."""


class OIDCVerifier:
    """Async-friendly OIDC JWT verifier.

    The verifier is process-singleton-friendly: a single instance can be used
    across an entire FastAPI app because PyJWKClient performs its own JWKS
    cache and we add a soft TTL on top of that cache.
    """

    def __init__(
        self,
        *,
        issuer: str,
        audiences: list[str],
        allowed_email_domains: list[str] | None = None,
        allowed_groups_claim: str = "groups",
        allowed_groups: list[str] | None = None,
        authorized_party: str | None = None,
        jwks_cache_ttl_sec: int = 3600,
        signing_algorithms: list[str] | None = None,
        require_email_verified: bool = True,
        leeway_sec: int = 30,
        http_timeout_sec: float = 5.0,
    ) -> None:
        if not issuer:
            raise OIDCConfigError("OIDC_ISSUER is required.")
        if not audiences:
            raise OIDCConfigError("OIDC_AUDIENCES must contain at least one audience.")

        self._issuer = issuer.rstrip("/")
        self._audiences = audiences
        self._allowed_email_domains = {
            d.lower().lstrip("@").strip() for d in (allowed_email_domains or []) if d.strip()
        }
        self._allowed_groups_claim = allowed_groups_claim
        self._allowed_groups = {g for g in (allowed_groups or []) if g}
        self._authorized_party = authorized_party or None
        self._jwks_cache_ttl_sec = jwks_cache_ttl_sec
        self._signing_algorithms = signing_algorithms or ["RS256", "RS384", "RS512", "ES256", "ES384"]
        self._require_email_verified = require_email_verified
        self._leeway_sec = leeway_sec
        self._http_timeout_sec = http_timeout_sec

        self._jwks_client: PyJWKClient | None = None
        self._jwks_url: str | None = None
        self._discovery_expires_at: float = 0.0
        self._lock = asyncio.Lock()

    # -------------------------------------------------------------------------
    # Discovery + JWKS
    # -------------------------------------------------------------------------
    async def _ensure_jwks_client(self) -> PyJWKClient:
        now = time.monotonic()
        if self._jwks_client is not None and now < self._discovery_expires_at:
            return self._jwks_client

        async with self._lock:
            now = time.monotonic()
            if self._jwks_client is not None and now < self._discovery_expires_at:
                return self._jwks_client

            discovery_url = f"{self._issuer}/.well-known/openid-configuration"
            logger.info("Fetching OIDC discovery document from %s", discovery_url)

            try:
                async with httpx.AsyncClient(timeout=self._http_timeout_sec) as client:
                    resp = await client.get(discovery_url)
                    resp.raise_for_status()
                    discovery = resp.json()
            except httpx.HTTPError as exc:
                raise TokenValidationError(
                    f"Failed to fetch OIDC discovery document: {exc}"
                ) from exc

            jwks_uri = discovery.get("jwks_uri")
            issuer_in_doc = discovery.get("issuer", "").rstrip("/")
            if not jwks_uri:
                raise OIDCConfigError("OIDC discovery document is missing jwks_uri.")
            if issuer_in_doc and issuer_in_doc != self._issuer:
                logger.warning(
                    "OIDC issuer mismatch: configured=%s, document=%s. Trusting the configured value.",
                    self._issuer,
                    issuer_in_doc,
                )

            self._jwks_url = jwks_uri
            # PyJWKClient maintains its own LRU + lifespan cache; we just
            # bound the discovery refresh by jwks_cache_ttl_sec.
            self._jwks_client = PyJWKClient(
                jwks_uri,
                cache_keys=True,
                lifespan=self._jwks_cache_ttl_sec,
                timeout=self._http_timeout_sec,
            )
            self._discovery_expires_at = now + self._jwks_cache_ttl_sec
            return self._jwks_client

    async def _signing_key_for(self, token: str):
        client = await self._ensure_jwks_client()
        # PyJWKClient.get_signing_key_from_jwt does network I/O on miss; run it
        # in a thread to avoid blocking the event loop.
        try:
            return await asyncio.to_thread(client.get_signing_key_from_jwt, token)
        except PyJWKClientError as exc:
            # Handle key rotation: invalidate and retry exactly once.
            logger.warning("JWKS key miss (%s); refreshing JWKS once before failing.", exc)
            self._jwks_client = None
            self._discovery_expires_at = 0.0
            client = await self._ensure_jwks_client()
            return await asyncio.to_thread(client.get_signing_key_from_jwt, token)

    # -------------------------------------------------------------------------
    # Verification
    # -------------------------------------------------------------------------
    async def verify(self, token: str) -> VerifiedClaims:
        """Validate signature + standard + custom claims on `token`."""
        if not token:
            raise TokenValidationError("Empty bearer token.")

        # Reject obviously-untrustworthy alg=none / HMAC tokens up front so we
        # never even look at the JWKS for them.
        try:
            unverified_header = jwt.get_unverified_header(token)
        except InvalidTokenError as exc:
            raise TokenValidationError(f"Malformed JWT header: {exc}") from exc

        alg = unverified_header.get("alg")
        if not alg or alg.lower() == "none" or alg.upper().startswith("HS"):
            raise TokenValidationError(f"Unsupported JWT alg: {alg!r}")
        if alg not in self._signing_algorithms:
            raise TokenValidationError(
                f"JWT alg {alg!r} not in allowlist {self._signing_algorithms!r}"
            )

        signing_key = await self._signing_key_for(token)

        try:
            decoded: dict[str, Any] = await asyncio.to_thread(
                jwt.decode,
                token,
                signing_key.key,
                algorithms=self._signing_algorithms,
                audience=self._audiences,
                issuer=self._issuer,
                leeway=self._leeway_sec,
                options={
                    "require": ["exp", "iat", "iss", "aud", "sub"],
                    "verify_aud": True,
                    "verify_iss": True,
                    "verify_exp": True,
                    "verify_nbf": True,
                },
            )
        except InvalidTokenError as exc:
            raise TokenValidationError(f"Invalid token: {exc}") from exc

        # Optional: pin the authorized party (azp claim) to a specific client.
        if self._authorized_party:
            azp = decoded.get("azp")
            if azp != self._authorized_party:
                raise TokenValidationError(
                    f"azp mismatch (expected {self._authorized_party!r}, got {azp!r})"
                )

        email = decoded.get("email")
        email_verified = bool(decoded.get("email_verified", False))

        if self._require_email_verified and email and not email_verified:
            raise TokenValidationError("email_verified=false in token.")

        if self._allowed_email_domains and email:
            domain = email.split("@", 1)[-1].lower()
            if domain not in self._allowed_email_domains:
                raise TokenValidationError(
                    f"Email domain {domain!r} not in allowlist."
                )

        groups_raw = decoded.get(self._allowed_groups_claim)
        groups: list[str]
        if isinstance(groups_raw, list):
            groups = [str(g) for g in groups_raw]
        elif isinstance(groups_raw, str):
            groups = [groups_raw]
        else:
            groups = []

        if self._allowed_groups and not (set(groups) & self._allowed_groups):
            raise TokenValidationError(
                "User is not a member of any allowed group."
            )

        return VerifiedClaims(
            subject=str(decoded.get("sub")),
            email=email,
            email_verified=email_verified,
            name=decoded.get("name") or decoded.get("preferred_username"),
            picture=decoded.get("picture"),
            groups=groups,
            raw=decoded,
        )

    async def health_check(self) -> bool:
        """Lightweight readiness check: discovery doc fetchable + JWKS reachable."""
        try:
            await self._ensure_jwks_client()
            return True
        except Exception:
            logger.exception("OIDC verifier health check failed.")
            return False


_singleton: OIDCVerifier | None = None


def get_oidc_verifier() -> OIDCVerifier:
    """Return a process-wide singleton verifier configured from ConfigService."""
    global _singleton
    if _singleton is not None:
        return _singleton

    # Lazy import to avoid a circular dependency between auth and config.
    from src.config.config_service import config_service

    _singleton = OIDCVerifier(
        issuer=config_service.OIDC_ISSUER,
        audiences=list(config_service.OIDC_AUDIENCES_LIST),
        allowed_email_domains=list(config_service.OIDC_ALLOWED_EMAIL_DOMAINS_LIST),
        allowed_groups_claim=config_service.OIDC_ALLOWED_GROUPS_CLAIM,
        allowed_groups=list(config_service.OIDC_ALLOWED_GROUPS_LIST),
        authorized_party=config_service.OIDC_AUTHORIZED_PARTY or None,
        jwks_cache_ttl_sec=config_service.JWKS_CACHE_TTL_SEC,
        require_email_verified=config_service.OIDC_REQUIRE_EMAIL_VERIFIED,
    )
    return _singleton


def reset_oidc_verifier_for_tests() -> None:
    global _singleton
    _singleton = None
