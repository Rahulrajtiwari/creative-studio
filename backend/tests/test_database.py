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
"""Tests for the simplified asyncpg-only database module."""

from unittest.mock import patch

import pytest

from src.config.config_service import config_service
from src.database import WorkerDatabase, _build_async_url, cleanup_connector, get_db


def test_build_url_with_password():
    with (
        patch.object(config_service, "DB_USE_IAM_AUTH", False),
        patch.object(config_service, "DB_USER", "u"),
        patch.object(config_service, "DB_PASS", "p"),
        patch.object(config_service, "DB_HOST", "h"),
        patch.object(config_service, "DB_PORT", "5432"),
        patch.object(config_service, "DB_NAME", "d"),
    ):
        assert _build_async_url() == "postgresql+asyncpg://u:p@h:5432/d"


def test_build_url_iam_omits_password():
    with (
        patch.object(config_service, "DB_USE_IAM_AUTH", True),
        patch.object(config_service, "DB_USER", "u@iam"),
        patch.object(config_service, "DB_PASS", "ignored"),
        patch.object(config_service, "DB_HOST", "127.0.0.1"),
        patch.object(config_service, "DB_PORT", "5432"),
        patch.object(config_service, "DB_NAME", "d"),
    ):
        assert _build_async_url() == "postgresql+asyncpg://u@iam@127.0.0.1:5432/d"


def test_build_url_empty_password_omits_password():
    with (
        patch.object(config_service, "DB_USE_IAM_AUTH", False),
        patch.object(config_service, "DB_USER", "u"),
        patch.object(config_service, "DB_PASS", ""),
        patch.object(config_service, "DB_HOST", "h"),
        patch.object(config_service, "DB_PORT", "5432"),
        patch.object(config_service, "DB_NAME", "d"),
    ):
        assert _build_async_url() == "postgresql+asyncpg://u@h:5432/d"


@pytest.mark.anyio
async def test_cleanup_connector_disposes_engine():
    with patch("src.database.engine.dispose") as mock_dispose:
        mock_dispose.return_value = None
        await cleanup_connector()
        mock_dispose.assert_awaited_once()


@pytest.mark.anyio
async def test_worker_database_creates_and_disposes_engine():
    fake_engine = type(
        "FE",
        (),
        {"dispose": (lambda self: None)},
    )

    with (
        patch("src.database.create_async_engine") as mock_create_engine,
        patch("src.database.async_sessionmaker") as mock_sessionmaker_cls,
    ):
        mock_engine = mock_create_engine.return_value
        mock_engine.dispose = type(fake_engine).dispose.__get__(mock_engine)

        mock_sessionmaker_cls.return_value = "sessionmaker"

        async with WorkerDatabase() as sm:
            assert sm == "sessionmaker"

        mock_create_engine.assert_called_once()


def test_get_db_returns_async_generator():
    gen = get_db()
    assert gen is not None
