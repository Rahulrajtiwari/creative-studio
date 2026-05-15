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
import {catchError, map, shareReplay, switchMap, take, tap} from 'rxjs/operators';

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
    this.session = {
      authenticated: false,
      accessToken: null,
      idToken: null,
      expiresAt: null,
    };
    // Invalidate the cached initialize() so the next login re-runs checkAuth().
    this.initialize$ = null;
    localStorage.removeItem(USER_DETAILS);
    this.oidc.logoff().subscribe({
      error: err => {
        console.error('OIDC logoff error', err);
        void this.router.navigate([LOGIN_ROUTE]);
      },
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
   * Returns a fresh access token, performing a silent refresh if necessary.
   * Used by the AuthInterceptor to attach Authorization headers.
   */
  getValidAccessToken$(): Observable<string> {
    if (!isPlatformBrowser(this.platformId)) {
      return of('');
    }
    return this.oidc.getAccessToken().pipe(
      take(1),
      switchMap(token => {
        if (token) {
          this.session.accessToken = token;
          return of(token);
        }
        // Empty token => session expired or never logged in.
        return throwError(
          () => new Error('No valid access token; user must re-authenticate.'),
        );
      }),
    );
  }

  /** Force a silent token refresh; used by the interceptor on 401s. */
  forceRefresh$(): Observable<string> {
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
