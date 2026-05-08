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

# --- Build stage --------------------------------------------------------------
FROM node:20-bookworm-slim AS builder

WORKDIR /app

# Install only what package.json declares to keep the layer cached.
COPY package*.json ./
RUN npm ci --no-audit --no-fund --ignore-scripts

# Then copy the rest of the source.
COPY . .

# Production build: hashed assets, AOT, no source maps.
ARG NG_CONFIGURATION=production
# Increase Node memory limit to avoid Out-Of-Memory errors during Angular build
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN npm run build -- --configuration=${NG_CONFIGURATION}

# --- Runtime stage ------------------------------------------------------------
# nginx-unprivileged exposes the same image as nginx:1.27-alpine but configured
# to run as UID 101 by default, which is what we want under the restricted
# Pod Security profile.
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

# Copy compiled SPA + assets.
COPY --from=builder --chown=nginx:nginx /app/dist/creative-studio/browser /usr/share/nginx/html

# Templated nginx config (envsubst-rendered at container start).
COPY --chown=nginx:nginx nginx.conf /etc/nginx/templates/default.conf.template

# Entrypoint that runs envsubst then nginx.
COPY --chown=nginx:nginx docker-entrypoint.sh /docker-entrypoint.sh

USER root
RUN apk add --no-cache gettext tini \
    && chmod +x /docker-entrypoint.sh \
    && rm -f /etc/nginx/conf.d/default.conf
USER nginx

EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
