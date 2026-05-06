#!/bin/sh
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
#
# Render templated nginx.conf and runtime-config.json from environment
# variables, then exec nginx in the foreground.
set -eu

: "${BACKEND_SERVICE_HOST:=cs-backend.creative-studio.svc.cluster.local}"
: "${BACKEND_SERVICE_PORT:=8080}"
: "${OIDC_AUTHORITY:=}"
: "${OIDC_CLIENT_ID:=}"
: "${OIDC_AUDIENCE:=}"
: "${OIDC_SCOPE:=openid profile email}"
: "${OIDC_IDP_DISPLAY_NAME:=Corporate SSO}"
: "${BACKEND_URL_PREFIX:=/api}"

export BACKEND_SERVICE_HOST BACKEND_SERVICE_PORT OIDC_AUTHORITY OIDC_CLIENT_ID OIDC_AUDIENCE OIDC_SCOPE OIDC_IDP_DISPLAY_NAME BACKEND_URL_PREFIX

# Render nginx config with the upstream service host/port.
envsubst '${BACKEND_SERVICE_HOST} ${BACKEND_SERVICE_PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

# Render the runtime-config.json the SPA fetches at boot.
envsubst '${OIDC_AUTHORITY} ${OIDC_CLIENT_ID} ${OIDC_AUDIENCE} ${OIDC_SCOPE} ${OIDC_IDP_DISPLAY_NAME} ${BACKEND_URL_PREFIX}' \
  < /usr/share/nginx/html/assets/runtime-config.template.json \
  > /usr/share/nginx/html/assets/runtime-config.json

exec nginx -g 'daemon off;'
