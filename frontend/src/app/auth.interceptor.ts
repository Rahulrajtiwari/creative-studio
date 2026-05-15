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
import {EMPTY, Observable, throwError} from 'rxjs';
import {catchError, switchMap, take} from 'rxjs/operators';

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

    // 1) Wait for the OIDC checkAuth() round trip to settle. Without this,
    //    any HTTP call fired while the app is still processing the
    //    `?code=...` callback (e.g. the workspace-switcher's load-on-init
    //    request) races the token exchange, finds no token, and was
    //    incorrectly being treated as "session lost" - which then triggered
    //    a full OIDC logout. After this gate, we know the session state for
    //    real.
    return this.authService.initialize().pipe(
      take(1),
      switchMap(session => {
        if (!session.authenticated) {
          // The user genuinely isn't logged in. Don't trigger another
          // OIDC logoff() round-trip from here - just suppress the call so
          // the route guard can quietly redirect to /login on the next
          // navigation. Returning EMPTY avoids spamming the user with
          // a snackbar for every component that fired an HTTP request
          // before noticing there is no session.
          return EMPTY;
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
                        'AuthInterceptor: silent refresh failed; redirecting to login.',
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
            // Token retrieval itself failed AFTER initialize() said the
            // user was authenticated - the OIDC session has actually been
            // dropped (e.g. expired and silent renew failed). Swallow the
            // error quietly here; the route guard will see the changed
            // session on the next navigation and route the user to /login.
            // Crucially we do NOT call authService.logout() any more,
            // because firing the OIDC logoff endpoint from a background
            // HTTP failure was what gave the user the "click anywhere ->
            // log me out" symptom.
            if (!(error instanceof HttpErrorResponse)) {
              return EMPTY;
            }
            return throwError(() => error);
          }),
        );
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
