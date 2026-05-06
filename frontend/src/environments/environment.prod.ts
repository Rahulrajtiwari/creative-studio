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
 * Production build constants. The OIDC values here are placeholders; in
 * production the SPA fetches /assets/runtime-config.json on boot (via the
 * APP_INITIALIZER in app.module.ts) and overrides these so a single image
 * works for every environment.
 */
export const environment = {
  production: true,
  isLocal: false,
  backendURL: '/api',
  EMAIL_REGEX:
    /^(([^<>()[\]\\.,;:\s@"]+(\.[^<>()[\]\\.,;:\s@"]+)*)|(".+"))@((\[\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/,
  ADMIN: 'admin',
  oidc: {
    authority: 'OIDC_AUTHORITY_PLACEHOLDER',
    clientId: 'OIDC_CLIENT_ID_PLACEHOLDER',
    scope: 'openid profile email',
    audience: 'OIDC_AUDIENCE_PLACEHOLDER',
    idpDisplayName: 'Corporate SSO',
  },
};
