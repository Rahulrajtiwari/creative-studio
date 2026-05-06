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

import {Injectable, PLATFORM_ID, inject} from '@angular/core';
import {isPlatformBrowser} from '@angular/common';
import {firstValueFrom} from 'rxjs';
import {HttpClient} from '@angular/common/http';
import {environment} from '../environments/environment';

export interface RuntimeOidcConfig {
  authority: string;
  clientId: string;
  scope: string;
  audience: string;
  idpDisplayName: string;
}

export interface RuntimeConfig {
  backendURL: string;
  oidc: RuntimeOidcConfig;
}

const DEFAULTS: RuntimeConfig = {
  backendURL: environment.backendURL,
  oidc: {
    authority: environment.oidc.authority,
    clientId: environment.oidc.clientId,
    scope: environment.oidc.scope,
    audience: environment.oidc.audience,
    idpDisplayName: environment.oidc.idpDisplayName,
  },
};

/**
 * Loads /assets/runtime-config.json at app startup and exposes the result
 * synchronously. nginx `envsubst` writes that file from container env vars
 * on container start so a single immutable image works across dev/qat/prd
 * without rebuilding the SPA.
 */
@Injectable({providedIn: 'root'})
export class RuntimeConfigService {
  private platformId = inject(PLATFORM_ID);
  private http = inject(HttpClient);
  private resolvedConfig: RuntimeConfig = DEFAULTS;

  async load(): Promise<RuntimeConfig> {
    if (!isPlatformBrowser(this.platformId)) {
      this.resolvedConfig = DEFAULTS;
      return this.resolvedConfig;
    }

    try {
      const remote = await firstValueFrom(
        this.http.get<RuntimeConfig>('/assets/runtime-config.json'),
      );
      this.resolvedConfig = {
        backendURL: remote?.backendURL ?? DEFAULTS.backendURL,
        oidc: {
          authority: remote?.oidc?.authority ?? DEFAULTS.oidc.authority,
          clientId: remote?.oidc?.clientId ?? DEFAULTS.oidc.clientId,
          scope: remote?.oidc?.scope ?? DEFAULTS.oidc.scope,
          audience: remote?.oidc?.audience ?? DEFAULTS.oidc.audience,
          idpDisplayName:
            remote?.oidc?.idpDisplayName ?? DEFAULTS.oidc.idpDisplayName,
        },
      };
    } catch (err) {
      console.warn(
        'runtime-config.json unavailable; falling back to environment defaults.',
        err,
      );
      this.resolvedConfig = DEFAULTS;
    }
    return this.resolvedConfig;
  }

  get config(): RuntimeConfig {
    return this.resolvedConfig;
  }
}
