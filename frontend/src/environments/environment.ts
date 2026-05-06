/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Default environment file. The same image runs across dev/qat/prd; the
 * actual values are loaded at runtime from /assets/runtime-config.json
 * (rendered into the container by nginx envsubst). The fields below are
 * fallbacks used during local `ng serve`.
 */
export const environment = {
  production: false,
  isLocal: true,
  backendURL: '/api',
  EMAIL_REGEX:
    /^(([^<>()[\]\\.,;:\s@"]+(\.[^<>()[\]\\.,;:\s@"]+)*)|(".+"))@((\[\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/,
  ADMIN: 'admin',
  oidc: {
    authority: 'https://login.microsoftonline.com/REPLACE_TENANT_ID/v2.0',
    clientId: 'REPLACE_SPA_CLIENT_ID',
    scope: 'openid profile email',
    audience: 'api://creative-studio',
    idpDisplayName: 'Corporate SSO',
  },
};
