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

# --- Build stage ----------------------------------------------------------
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev

COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

# --- Runtime stage --------------------------------------------------------
FROM python:3.12-slim-bookworm AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/app/.venv/bin:$PATH"

# Install only the runtime libraries the app needs (ffmpeg for media ops, ca-certs for TLS).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg ca-certificates tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Non-root user.
RUN groupadd --system --gid 10001 appgroup \
    && useradd --system --uid 10001 --gid appgroup --shell /usr/sbin/nologin --create-home appuser

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /app /app

USER appuser:appgroup
EXPOSE 8080

# Single-process uvicorn; Kubernetes scales by replicas, not by gunicorn workers.
# Tini ensures proper signal handling for graceful shutdown.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--proxy-headers", \
     "--forwarded-allow-ips", "*", \
     "--timeout-keep-alive", "75", \
     "--access-log", \
     "--log-level", "info"]
