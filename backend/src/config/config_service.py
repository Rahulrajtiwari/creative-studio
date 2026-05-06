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
"""Application configuration loaded from environment variables.

In production (GKE) every value comes from ConfigMaps and Secrets mounted as
env vars on the pod. The optional .env file path is kept for local docker
compose only.
"""

from __future__ import annotations

from typing import Any

import google.auth
from google.auth.exceptions import DefaultCredentialsError
from pydantic import Field, computed_field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class ConfigService(BaseSettings):
    model_config = SettingsConfigDict(
        case_sensitive=True,
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # ------------------------------------------------------------------
    # Core project settings
    # ------------------------------------------------------------------
    PROJECT_ID: str = ""
    LOCATION: str = "global"
    ENVIRONMENT: str = "development"
    FRONTEND_URL: str = "http://localhost:4200"
    BACKEND_URL: str = "http://localhost:8080"
    LOG_LEVEL: str = "INFO"
    INIT_VERTEX: bool = True

    # When the backend sits behind the same internal Ingress as the SPA the
    # browser uses same-origin requests, so CORS can be locked down.
    BEHIND_INGRESS: bool = False
    TRUSTED_HOSTS: str = "*"  # Comma-separated list consumed by TrustedHostMiddleware

    # ------------------------------------------------------------------
    # OIDC (replaces Firebase Auth + Identity Platform)
    # ------------------------------------------------------------------
    OIDC_ISSUER: str = ""
    OIDC_AUDIENCES: str = Field(
        default="",
        description="Comma-separated list of accepted JWT audiences.",
    )
    OIDC_ALLOWED_EMAIL_DOMAINS: str = Field(
        default="",
        description="Optional comma-separated email domain allowlist.",
    )
    OIDC_ALLOWED_GROUPS_CLAIM: str = "groups"
    OIDC_ALLOWED_GROUPS: str = Field(
        default="",
        description="Optional comma-separated group allowlist; the user must be a member of at least one.",
    )
    OIDC_AUTHORIZED_PARTY: str = ""
    OIDC_REQUIRE_EMAIL_VERIFIED: bool = True
    JWKS_CACHE_TTL_SEC: int = 3600

    # ------------------------------------------------------------------
    # Storage
    # ------------------------------------------------------------------
    GENMEDIA_BUCKET: str = ""
    SIGNING_SA_EMAIL: str = ""

    # ------------------------------------------------------------------
    # Gemini / Imagen / Veo / Lyria / VTO
    # ------------------------------------------------------------------
    GEMINI_MODEL_ID: str = "gemini-2.5-pro"
    GEMINI_AUDIO_ANALYSIS_MODEL_ID: str = "gemini-2.5-pro"
    VEO_MODEL_ID: str = "veo-2.0-generate-001"
    VTO_MODEL_ID: str = "virtual-try-on-001"
    LYRIA_MODEL_VERSION: str = "lyria-002"
    LYRIA_PROJECT_ID: str = ""
    MODEL_IMAGEN_PRODUCT_RECONTEXT: str = "imagen-product-recontext-preview-06-30"
    IMAGEN_GENERATED_SUBFOLDER: str = "generated_images"
    IMAGEN_EDITED_SUBFOLDER: str = "edited_images"
    IMAGEN_RECONTEXT_SUBFOLDER: str = "recontext_images"

    # ------------------------------------------------------------------
    # Database (Cloud SQL via Auth Proxy sidecar in GKE)
    # ------------------------------------------------------------------
    INSTANCE_CONNECTION_NAME: str = ""
    DB_USER: str = "studio_user"
    DB_PASS: str = ""  # Empty => use IAM auth via the proxy sidecar.
    DB_NAME: str = "creative_studio"
    USE_CLOUD_SQL_AUTH_PROXY: bool = True
    DB_HOST: str = "127.0.0.1"
    DB_PORT: str = "5432"
    DB_USE_IAM_AUTH: bool = False  # Set true when password is empty and proxy is launched with --auto-iam-authn.

    # ------------------------------------------------------------------
    # Email / admin
    # ------------------------------------------------------------------
    SENDER_EMAIL: str = ""
    ADMIN_USER_EMAIL: str = "system"

    # ------------------------------------------------------------------
    # Workflows
    # ------------------------------------------------------------------
    WORKFLOWS_LOCATION: str = "us-central1"
    WORKFLOWS_EXECUTOR_URL: str = "http://localhost:8080"
    BACKEND_SERVICE_ACCOUNT_EMAIL: str = ""

    # ------------------------------------------------------------------
    # Validators
    # ------------------------------------------------------------------
    @model_validator(mode="before")
    @classmethod
    def get_default_project_id(cls, values: Any) -> Any:
        if not values.get("PROJECT_ID"):
            try:
                _, project_id = google.auth.default()
                if project_id:
                    values["PROJECT_ID"] = project_id
            except DefaultCredentialsError:
                pass
        return values

    @model_validator(mode="after")
    def set_dependent_defaults(self) -> "ConfigService":
        if not self.PROJECT_ID:
            raise ValueError(
                "PROJECT_ID could not be determined. Please set it via environment variable.",
            )

        if not self.GENMEDIA_BUCKET:
            self.GENMEDIA_BUCKET = f"{self.PROJECT_ID}-assets"

        if self.ENVIRONMENT == "production":
            if not self.OIDC_ISSUER:
                raise ValueError("OIDC_ISSUER is required in production.")
            if not self.OIDC_AUDIENCES_LIST:
                raise ValueError("OIDC_AUDIENCES must contain at least one audience in production.")

        return self

    # ------------------------------------------------------------------
    # Computed convenience properties
    # ------------------------------------------------------------------
    @computed_field
    @property
    def OIDC_AUDIENCES_LIST(self) -> set[str]:
        return {a.strip() for a in self.OIDC_AUDIENCES.split(",") if a.strip()}

    @computed_field
    @property
    def OIDC_ALLOWED_EMAIL_DOMAINS_LIST(self) -> set[str]:
        return {
            d.strip().lower().lstrip("@")
            for d in self.OIDC_ALLOWED_EMAIL_DOMAINS.split(",")
            if d.strip()
        }

    @computed_field
    @property
    def OIDC_ALLOWED_GROUPS_LIST(self) -> set[str]:
        return {g.strip() for g in self.OIDC_ALLOWED_GROUPS.split(",") if g.strip()}

    @computed_field
    @property
    def TRUSTED_HOSTS_LIST(self) -> list[str]:
        items = [h.strip() for h in self.TRUSTED_HOSTS.split(",") if h.strip()]
        return items or ["*"]

    @computed_field
    @property
    def VIDEO_BUCKET(self) -> str:
        return f"{self.GENMEDIA_BUCKET}/videos"

    @computed_field
    @property
    def IMAGE_BUCKET(self) -> str:
        return f"{self.GENMEDIA_BUCKET}/images"


config_service = ConfigService()
