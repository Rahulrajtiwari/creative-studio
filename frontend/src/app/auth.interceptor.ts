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

import {
  HttpErrorResponse,
  HttpEvent,
  HttpHandler,
  HttpInterceptor,
  HttpRequest,
} from '@angular/common/http';
import {Injectable, inject} from '@angular/core';
import {Observable, throwError} from 'rxjs';
import {catchError, switchMap} from 'rxjs/operators';

import {AuthService} from './common/services/auth.service';
import {RuntimeConfigService} from './runtime-config.service';

@Injectable()
export class AuthInterceptor implements HttpInterceptor {
  private authService = inject(AuthService);
  private runtimeConfig = inject(RuntimeConfigService);

  intercept(
    request: HttpRequest<unknown>,
    next: HttpHandler,
  ): Observable<HttpEvent<unknown>> {
    if (!this.shouldAttachToken(request.url)) {
      return next.handle(request);
    }

    return this.authService.getValidAccessToken$().pipe(
      switchMap(token =>
        next.handle(this.withBearer(request, token)).pipe(
          catchError((error: HttpErrorResponse) => {
            // On 401 attempt a single silent refresh + retry.
            if (error.status === 401) {
              return this.authService.forceRefresh$().pipe(
                switchMap(refreshed =>
                  next.handle(this.withBearer(request, refreshed)),
                ),
                catchError((refreshError: unknown) => {
                  console.warn(
                    'AuthInterceptor: silent refresh failed; logging out.',
                    refreshError,
                  );
                  this.authService.logout();
                  return throwError(() => refreshError);
                }),
              );
            }
            return throwError(() => error);
          }),
        ),
      ),
      catchError((error: unknown) => {
        // Token retrieval itself failed - user is no longer authenticated.
        if (!(error instanceof HttpErrorResponse)) {
          this.authService.logout();
        }
        return throwError(() => error);
      }),
    );
  }

  private shouldAttachToken(url: string): boolean {
    // Only attach to backend API calls. The runtime config and static assets
    // must remain unauthenticated.
    if (url.startsWith('/assets/')) return false;
    const apiBase = this.runtimeConfig.config.backendURL;
    if (url.startsWith(apiBase)) return true;
    if (url.startsWith('/api/')) return true;
    return false;
  }

  private withBearer(
    request: HttpRequest<unknown>,
    token: string,
  ): HttpRequest<unknown> {
    return request.clone({
      setHeaders: {Authorization: `Bearer ${token}`},
    });
  }
}
