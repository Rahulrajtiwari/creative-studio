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
"""Database configuration and session management.

In the production GKE topology each backend pod runs the
`cloud-sql-proxy` Auth Proxy as a sidecar container that listens on
`127.0.0.1:5432` (configurable). The application opens regular asyncpg TCP
connections to that loopback address; password vs IAM authentication is the
sidecar's responsibility.

Locally (docker-compose) the same configuration works against a vanilla
postgres container - just point DB_HOST at the postgres service.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from src.config.config_service import config_service


class Base(DeclarativeBase):
    """SQLAlchemy declarative base."""


def _build_async_url() -> str:
    """Construct the SQLAlchemy URL.

    When ``DB_USE_IAM_AUTH`` is true the password is omitted from the URL;
    the Cloud SQL Auth Proxy sidecar must be running with
    ``--auto-iam-authn`` so it injects short-lived IAM tokens.
    """
    user = config_service.DB_USER
    password = config_service.DB_PASS
    host = config_service.DB_HOST
    port = config_service.DB_PORT
    name = config_service.DB_NAME

    if config_service.DB_USE_IAM_AUTH or not password:
        return f"postgresql+asyncpg://{user}@{host}:{port}/{name}"
    return f"postgresql+asyncpg://{user}:{password}@{host}:{port}/{name}"


def _create_engine_for_loop():
    """Create an AsyncEngine sized for production GKE pods."""
    return create_async_engine(
        _build_async_url(),
        echo=config_service.LOG_LEVEL == "DEBUG",
        pool_pre_ping=True,
        pool_size=10,
        max_overflow=10,
        pool_timeout=30,
        pool_recycle=1800,
    )


engine = _create_engine_for_loop()

async_session_local = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency that yields a request-scoped session."""
    async with async_session_local() as session:
        yield session


async def cleanup_connector() -> None:
    """Compatibility shim retained for callers that previously needed it."""
    await engine.dispose()


class WorkerDatabase:
    """Per-worker session factory used by background-task threads.

    Each worker creates its own engine on the worker's event loop to avoid
    cross-loop sharing, and disposes of it on exit.
    """

    def __init__(self) -> None:
        self.engine = None
        self.sessionmaker: async_sessionmaker[AsyncSession] | None = None

    async def __aenter__(self) -> async_sessionmaker[AsyncSession]:
        self.engine = create_async_engine(
            _build_async_url(),
            echo=config_service.LOG_LEVEL == "DEBUG",
            pool_pre_ping=True,
            pool_size=2,
            max_overflow=2,
            pool_timeout=30,
            pool_recycle=1800,
        )
        self.sessionmaker = async_sessionmaker(
            bind=self.engine,
            class_=AsyncSession,
            expire_on_commit=False,
            autoflush=False,
        )
        return self.sessionmaker

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        if self.engine is not None:
            await self.engine.dispose()
