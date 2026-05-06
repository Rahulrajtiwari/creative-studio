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

# --- Setup logging globally before any other import that might log ---
from src.config.logger_config import setup_logging

setup_logging()

import logging
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from sqlalchemy import text

from src.admin.admin_controller import router as admin_router
from src.audios.audio_controller import router as audio_router
from src.brand_guidelines.brand_guideline_controller import (
    router as brand_guideline_router,
)
from src.common import events  # noqa: F401  Register SQLAlchemy event listeners
from src.config.config_service import config_service
from src.database import async_session_local
from src.galleries.gallery_controller import router as gallery_router
from src.generation_options.generation_options_controller import (
    router as generation_options_router,
)
from src.images.imagen_controller import router as imagen_router
from src.media_templates.media_templates_controller import (
    router as media_template_router,
)
from src.multimodal.gemini_controller import router as gemini_router
from src.source_assets.source_asset_controller import (
    router as source_asset_router,
)
from src.tags.tags_controller import router as tags_router
from src.users.user_controller import router as user_router
from src.videos.veo_controller import router as video_router
from src.workbench.router import router as workbench_router
from src.workflows.workflow_controller import router as workflow_router
from src.workflows_executor.workflows_executor_controller import (
    router as workflows_executor_router,
)
from src.workspaces.workspace_controller import router as workspace_router

logger = logging.getLogger(__name__)


def configure_cors(app: FastAPI) -> None:
    """Configure CORS middleware.

    When the app is served behind the same Internal HTTPS Load Balancer as the
    frontend (production GKE topology), browser requests are same-origin and
    we keep the allow-list empty. For local dev / development the SPA might
    be served on a different port, so we mirror FRONTEND_URL.
    """
    if config_service.BEHIND_INGRESS:
        allowed_origins: list[str] = []
    elif config_service.ENVIRONMENT == "production":
        if not config_service.FRONTEND_URL:
            raise ValueError("FRONTEND_URL must be set in production.")
        allowed_origins = [config_service.FRONTEND_URL]
    elif config_service.ENVIRONMENT in {"development", "test", "local"}:
        # Local docker-compose dev: keep permissive CORS.
        allowed_origins = ["*"]
    else:
        raise ValueError(
            f"Invalid ENVIRONMENT: {config_service.ENVIRONMENT!r}."
        )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=bool(allowed_origins) and "*" not in allowed_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )


def configure_security_middleware(app: FastAPI) -> None:
    """TrustedHostMiddleware + GZipMiddleware (production-grade defaults)."""
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=config_service.TRUSTED_HOSTS_LIST,
    )
    app.add_middleware(GZipMiddleware, minimum_size=1024)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up Creative Studio API...")

    # Run database migrations on startup. If they fail we refuse to come up
    # so the readiness probe stays red.
    try:
        from src.database_migrations import run_pending_migrations

        await run_pending_migrations()
    except Exception:
        logger.exception("Failed to run database migrations during startup.")
        raise

    # Warm the OIDC verifier so the first request doesn't pay the discovery
    # round-trip latency.
    try:
        from src.auth.oidc_verifier import get_oidc_verifier

        verifier = get_oidc_verifier()
        await verifier.health_check()
    except Exception:
        # Don't block startup if the IdP is briefly unreachable; the readiness
        # probe will keep the pod out of rotation until JWKS is fetchable.
        logger.exception("OIDC verifier warm-up failed; continuing startup.")

    logger.info("Creating ThreadPoolExecutor (max_workers=4)...")
    app.state.executor = ThreadPoolExecutor(max_workers=4)

    yield

    logger.info("Shutting down Creative Studio API...")
    app.state.executor.shutdown(wait=True)


app = FastAPI(
    lifespan=lifespan,
    title="Creative Studio API",
    description=(
        "GenMedia Creative Studio: a Vertex AI-backed content generation "
        "service (Imagen, Veo, Lyria, Chirp, Gemini). Strictly private; "
        "only reachable through the corporate-network Internal HTTPS Load "
        "Balancer."
    ),
    docs_url=None if config_service.ENVIRONMENT == "production" else "/docs",
    redoc_url=None if config_service.ENVIRONMENT == "production" else "/redoc",
    openapi_url=None if config_service.ENVIRONMENT == "production" else "/openapi.json",
)

configure_security_middleware(app)
configure_cors(app)


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.error(
        "Unhandled exception for request %s %s: %s",
        request.method,
        request.url,
        exc,
        exc_info=True,
    )
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={"detail": "An internal server error occurred."},
    )


# -----------------------------------------------------------------------------
# Health endpoints (consumed by Kubernetes probes and the ILB health check).
# -----------------------------------------------------------------------------
@app.get("/healthz", tags=["Health Check"], include_in_schema=False)
async def healthz() -> PlainTextResponse:
    """Liveness probe: always 200 if the process is up."""
    return PlainTextResponse("ok")


@app.get("/readyz", tags=["Health Check"], include_in_schema=False)
async def readyz() -> JSONResponse:
    """Readiness probe: DB reachable + OIDC JWKS fetchable."""
    db_ok = False
    oidc_ok = False
    try:
        async with async_session_local() as session:
            await session.execute(text("SELECT 1"))
            db_ok = True
    except Exception:
        logger.exception("/readyz: DB check failed.")

    try:
        from src.auth.oidc_verifier import get_oidc_verifier

        oidc_ok = await get_oidc_verifier().health_check()
    except Exception:
        logger.exception("/readyz: OIDC check failed.")

    payload = {"db": db_ok, "oidc": oidc_ok}
    code = status.HTTP_200_OK if (db_ok and oidc_ok) else status.HTTP_503_SERVICE_UNAVAILABLE
    return JSONResponse(content=payload, status_code=code)


@app.get("/", tags=["Health Check"])
async def root() -> str:
    return "You are calling Creative Studio Backend"


@app.get("/api/version", tags=["Health Check"])
def version() -> str:
    return "v0.0.1"


# -----------------------------------------------------------------------------
# Routers
# -----------------------------------------------------------------------------
app.include_router(imagen_router)
app.include_router(admin_router)
app.include_router(audio_router)
app.include_router(video_router)
app.include_router(gallery_router)
app.include_router(gemini_router)
app.include_router(user_router)
app.include_router(generation_options_router)
app.include_router(media_template_router)
app.include_router(source_asset_router)
app.include_router(tags_router)
app.include_router(workspace_router)
app.include_router(brand_guideline_router)
app.include_router(workflow_router)
app.include_router(workflows_executor_router)
app.include_router(workbench_router)
