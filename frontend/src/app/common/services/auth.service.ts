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

import {isPlatformBrowser} from '@angular/common';
import {
  HttpClient,
  HttpErrorResponse,
  HttpHeaders,
} from '@angular/common/http';
import {Injectable, PLATFORM_ID, inject} from '@angular/core';
import {Router} from '@angular/router';
import {OidcSecurityService} from 'angular-auth-oidc-client';
import {Observable, firstValueFrom, of, throwError} from 'rxjs';
import {
  catchError,
  finalize,
  map,
  shareReplay,
  switchMap,
  take,
  tap,
} from 'rxjs/operators';

import {RuntimeConfigService} from '../../runtime-config.service';
import {UserModel, UserRolesEnum} from '../models/user.model';
import {UserService} from '../services/user.service';

const USER_DETAILS = 'USER_DETAILS';
const LOGIN_ROUTE = '/login';

interface OidcSessionState {
  authenticated: boolean;
  accessToken: string | null;
  idToken: string | null;
  expiresAt: number | null;
}

@Injectable({providedIn: 'root'})
export class AuthService {
  private platformId = inject(PLATFORM_ID);
  private oidc = inject(OidcSecurityService);
  private router = inject(Router);
  private http = inject(HttpClient);
  private userService = inject(UserService);
  private runtimeConfig = inject(RuntimeConfigService);

  private session: OidcSessionState = {
    authenticated: false,
    accessToken: null,
    idToken: null,
    expiresAt: null,
  };

  /**
   * Memoised initialize() pipeline. `OidcSecurityService.checkAuth()` consumes
   * the `?code=...` authorization-code response from the URL exactly once;
   * calling it twice with the same code makes Google's /token endpoint return
   * `400 invalid_grant` on the second attempt, which the OIDC library then
   * treats as a session error and clears the just-established session. Because
   * both AppComponent and the AuthGuard subscribe to initialize() during the
   * very first navigation after the IdP redirect, we MUST share a single
   * underlying checkAuth() across every subscriber for the lifetime of the
   * app.
   */
  private initialize$: Observable<OidcSessionState> | null = null;

  /**
   * Resolve the OIDC session state on app start. Should be called from the
   * AppComponent to ensure the silent-renew callback / login response is
   * processed before any guarded route is evaluated.
   */
  initialize(): Observable<OidcSessionState> {
    if (!isPlatformBrowser(this.platformId)) {
      return of(this.session);
    }

    if (this.initialize$) {
      return this.initialize$;
    }

    this.initialize$ = this.oidc.checkAuth().pipe(
      switchMap(({isAuthenticated, accessToken, idToken}) => {
        this.session = {
          authenticated: isAuthenticated,
          accessToken: accessToken ?? null,
          idToken: idToken ?? null,
          expiresAt: this.decodeExpiry(idToken ?? accessToken),
        };

        if (!isAuthenticated) {
          return of(this.session);
        }
        // Sync the user profile with the backend on every successful auth.
        return this.syncUserWithBackend$(idToken || accessToken).pipe(
          map(() => this.session),
          // If the /users/me sync itself fails we still consider the OIDC
          // session valid; the user can retry the failed call. Crucially we
          // do NOT propagate the error and force a logout here.
          catchError(err => {
            console.warn('User profile sync failed after login:', err);
            return of(this.session);
          }),
        );
      }),
      shareReplay({bufferSize: 1, refCount: false}),
    );
    return this.initialize$;
  }

  /** Begin the OIDC Authorization Code + PKCE flow. */
  login(): void {
    if (!isPlatformBrowser(this.platformId)) return;
    this.oidc.authorize();
  }

  /** Trigger the OIDC end-session flow and clear local state. */
  logout(_route: string = LOGIN_ROUTE): void {
    if (!isPlatformBrowser(this.platformId)) return;

    // Snapshot the access token BEFORE we clear local state so we can
    // (best-effort) revoke it at Google's revocation endpoint below.
    const tokenToRevoke = this.session.accessToken;

    this.session = {
      authenticated: false,
      accessToken: null,
      idToken: null,
      expiresAt: null,
    };
    // Invalidate the cached initialize() so the next login re-runs checkAuth().
    this.initialize$ = null;
    localStorage.removeItem(USER_DETAILS);

    // For Google, the access_token still grants API access until it expires
    // (~1h) and the user's session at accounts.google.com is also still
    // alive. Revoke the token so a subsequent /login click re-prompts the
    // user instead of silently re-signing them in. Fire-and-forget: we do
    // not block navigation on the result.
    this.revokeUpstreamTokenBestEffort(tokenToRevoke);

    // angular-auth-oidc-client's logoff() clears its own local storage and,
    // when the IdP advertises an end_session_endpoint, redirects there.
    // Google does NOT implement OIDC end_session_endpoint, so for Google
    // logoff() resolves locally with NO redirect - meaning the user stays
    // on whatever page they were on and the logout button looks broken.
    // Use finalize() to guarantee we navigate to /login on every
    // termination path (next, error, complete) regardless of the IdP.
    this.oidc
      .logoff()
      .pipe(
        finalize(() => {
          void this.router.navigate([LOGIN_ROUTE]);
        }),
      )
      .subscribe({
        error: err => console.error('OIDC logoff error', err),
      });
  }

  isLoggedIn(): boolean {
    if (!isPlatformBrowser(this.platformId)) return false;
    if (!this.session.authenticated) return false;
    if (this.session.expiresAt && this.session.expiresAt < Date.now()) {
      return false;
    }
    return true;
  }

  isUserAdmin(): boolean {
    if (!isPlatformBrowser(this.platformId)) return false;
    return (
      this.userService
        .getUserDetails()
        ?.roles?.includes(UserRolesEnum.ADMIN) || false
    );
  }

  isUserWorkflows(): boolean {
    if (!isPlatformBrowser(this.platformId)) return false;
    return (
      this.userService
        .getUserDetails()
        ?.roles?.includes(UserRolesEnum.WORKFLOWS) || false
    );
  }

  /**
   * Returns a fresh bearer token for backend `/api/*` calls.
   *
   * IMPORTANT: we deliberately return the OIDC **id_token** (a JWT), NOT the
   * OAuth access_token. Reason: Google's access tokens are OPAQUE strings
   * ("ya29...") that cannot be validated as JWTs. Our backend's
   * `OIDCVerifier` (backend/src/auth/oidc_verifier.py) uses PyJWT to decode
   * and validate the bearer (signature, iss, aud, exp). Sending the opaque
   * access_token would make every `/api/*` call return 401, the interceptor
   * would attempt a silent refresh that always fails on Google, and the
   * user would be auto-logged-out within seconds of login.
   *
   * The id_token is also a JWT issued by Google with the same signing key,
   * with `iss=https://accounts.google.com`, `aud=<our clientId>`, and a
   * 1-hour expiry. It is what `OIDCVerifier` is configured to accept.
   *
   * NB: the method name is kept as `getValidAccessToken$` for backward
   * compatibility with existing callers (AuthInterceptor, tests). The
   * payload it returns is conceptually a bearer credential for the
   * application backend, not the OIDC "access_token" per se.
   */
  getValidAccessToken$(): Observable<string> {
    if (!isPlatformBrowser(this.platformId)) {
      return of('');
    }
    return this.oidc.getIdToken().pipe(
      take(1),
      switchMap(token => {
        if (token) {
          this.session.idToken = token;
          return of(token);
        }
        // Empty token => session expired or never logged in.
        return throwError(
          () =>
            new Error('No valid ID token; user must re-authenticate.'),
        );
      }),
    );
  }

  /**
   * Attempt a silent token refresh; used by the interceptor on 401s.
   *
   * For Google ("Web application" OAuth client type) silent renewal is
   * IMPOSSIBLE in this SPA: the PKCE flow does not issue a refresh_token,
   * and iframe-based renewal is blocked by Google's `X-Frame-Options`. If
   * we let angular-auth-oidc-client try anyway it loops through 3 internal
   * timeout retries (~30 seconds of dead time) before failing - that's
   * 30 seconds of an unresponsive UI before the user is finally redirected
   * to /login. We short-circuit that here: when the configured authority
   * is Google, fail fast.
   */
  forceRefresh$(): Observable<string> {
    const authority = this.runtimeConfig.config.oidc?.authority || '';
    const isGoogle = /(^https:\/\/)?accounts\.google\.com\/?$/.test(authority);
    if (isGoogle) {
      return throwError(
        () =>
          new Error(
            'Silent renewal is not supported for the Google IdP; user must re-authenticate.',
          ),
      );
    }
    return this.oidc.forceRefreshSession().pipe(
      switchMap(({accessToken}) => {
        if (!accessToken) {
          return throwError(() => new Error('Silent renew returned no token.'));
        }
        this.session.accessToken = accessToken;
        return of(accessToken);
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /**
   * Best-effort revoke of an upstream OAuth access token at logout time.
   *
   * Currently implemented for Google only (the most common authority). For
   * other IdPs (Auth0, Okta, Keycloak…) revocation is a no-op because their
   * revocation endpoints are not standardized in the well-known discovery
   * doc that the OIDC library has loaded, and adding per-IdP support is out
   * of scope. The OIDC library's own logoff() already handles RP-Initiated
   * Logout when end_session_endpoint is present.
   *
   * Failures are swallowed and only logged; we never block the user's
   * navigation to /login on the revocation result.
   */
  private revokeUpstreamTokenBestEffort(token: string | null): void {
    if (!token) return;
    const authority = this.runtimeConfig.config.oidc?.authority || '';
    const isGoogle = /(^https:\/\/)?accounts\.google\.com\/?$/.test(authority);
    if (!isGoogle) return;

    // Google's revocation endpoint accepts a urlencoded `token` parameter
    // in either the query string or the body. We use the body form to keep
    // the URL clean and so the token never appears in any access log.
    const body = new URLSearchParams();
    body.set('token', token);
    const headers = new HttpHeaders().set(
      'Content-Type',
      'application/x-www-form-urlencoded',
    );
    this.http
      .post('https://oauth2.googleapis.com/revoke', body.toString(), {headers})
      .subscribe({
        error: err =>
          console.warn(
            'Upstream token revocation failed (non-fatal):',
            err?.message || err,
          ),
      });
  }

  private decodeExpiry(token: string | null): number | null {
    if (!token) return null;
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      return typeof payload.exp === 'number' ? payload.exp * 1000 : null;
    } catch {
      return null;
    }
  }

  private syncUserWithBackend$(token: string | null): Observable<UserModel> {
    if (!token) {
      return throwError(
        () => new Error('Cannot sync user without an OIDC token.'),
      );
    }
    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    const url = `${this.runtimeConfig.config.backendURL}/users/me`;
    return this.http.get<UserModel>(url, {headers}).pipe(
      tap((userDetails: UserModel) => {
        localStorage.setItem(USER_DETAILS, JSON.stringify(userDetails));
      }),
      catchError((error: HttpErrorResponse) => {
        console.error('Failed to sync user with backend', error);
        return throwError(
          () =>
            new Error(
              error?.error?.detail ||
                'Could not synchronize user profile with the server.',
            ),
        );
      }),
    );
  }

  /** Convenience accessor used by some legacy callers. */
  async syncUser(): Promise<void> {
    const token = await firstValueFrom(this.oidc.getAccessToken());
    await firstValueFrom(this.syncUserWithBackend$(token || null));
  }
}
