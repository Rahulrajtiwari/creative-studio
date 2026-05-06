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
"""Run pending Alembic migrations under a Postgres advisory lock.

The lock guarantees that even if N pods come up simultaneously only one
process actually executes the migration. The asyncpg connection used to hold
the lock is opened directly against the cloud-sql-proxy sidecar (or the local
postgres in docker-compose).
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys

import asyncpg

from src.config.config_service import config_service

logger = logging.getLogger(__name__)

MIGRATION_LOCK_ID = 42


async def _open_lock_connection() -> asyncpg.Connection:
    user = config_service.DB_USER
    password = config_service.DB_PASS
    host = config_service.DB_HOST
    port = int(config_service.DB_PORT)
    name = config_service.DB_NAME

    kwargs = {
        "user": user,
        "host": host,
        "port": port,
        "database": name,
    }
    if not config_service.DB_USE_IAM_AUTH and password:
        kwargs["password"] = password

    return await asyncpg.connect(**kwargs)


async def run_pending_migrations() -> None:
    logger.info("Attempting to run pending database migrations...")

    conn: asyncpg.Connection | None = None
    try:
        conn = await _open_lock_connection()

        logger.info("Acquiring advisory lock for migrations...")
        await conn.execute("SELECT pg_advisory_lock($1)", MIGRATION_LOCK_ID)
        logger.info("Advisory lock acquired.")

        alembic_cmd = os.path.join(os.path.dirname(sys.executable), "alembic")

        logger.info("Running '%s upgrade head'...", alembic_cmd)
        process = await asyncio.create_subprocess_exec(
            alembic_cmd,
            "upgrade",
            "head",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )

        stdout, stderr = await process.communicate()

        if process.returncode == 0:
            full_output = (stdout.decode() if stdout else "") + (
                stderr.decode() if stderr else ""
            )
            if "Running upgrade" in full_output:
                logger.info("Migrations applied successfully.")
                logger.info("Alembic Output:\n%s", full_output.strip())
            else:
                logger.info("Database is already up to date. No pending migrations.")
                logger.debug("Alembic Output:\n%s", full_output.strip())
        else:
            logger.error("Migrations failed.")
            if stdout:
                logger.info("Alembic Output:\n%s", stdout.decode().strip())
            if stderr:
                logger.error("Alembic Error:\n%s", stderr.decode().strip())
            raise RuntimeError("Database migrations failed.")

    except Exception as exc:
        logger.error("Error during migration process: %s", exc)
        raise
    finally:
        if conn is not None:
            try:
                logger.info("Releasing advisory lock...")
                await conn.execute(
                    "SELECT pg_advisory_unlock($1)", MIGRATION_LOCK_ID
                )
                await conn.close()
            except asyncpg.PostgresError as exc:
                logger.error(
                    "Error releasing lock or closing connection: %s", exc
                )
