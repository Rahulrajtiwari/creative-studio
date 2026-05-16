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
  HttpClientTestingModule,
  HttpTestingController,
} from '@angular/common/http/testing';
import {TestBed} from '@angular/core/testing';
import {Router} from '@angular/router';
import {RouterTestingModule} from '@angular/router/testing';
import {OidcSecurityService} from 'angular-auth-oidc-client';
import {of, throwError} from 'rxjs';

import {AuthService} from './auth.service';
import {RuntimeConfigService} from '../../runtime-config.service';
import {UserService} from './user.service';

describe('AuthService (OIDC)', () => {
  let oidcSpy: jasmine.SpyObj<OidcSecurityService>;
  let userServiceSpy: jasmine.SpyObj<UserService>;
  let runtime: Partial<RuntimeConfigService>;
  let routerSpy: jasmine.SpyObj<Router>;

  function configureModule(authority: string = 'https://idp.example.com'): void {
    runtime = {
      config: {
        backendURL: '/api',
        oidc: {
          authority,
          clientId: 'client',
          scope: 'openid profile email',
          audience: 'api',
          idpDisplayName: 'Test',
        },
      },
    };

    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule, RouterTestingModule],
      providers: [
        AuthService,
        {provide: OidcSecurityService, useValue: oidcSpy},
        {provide: UserService, useValue: userServiceSpy},
        {provide: RuntimeConfigService, useValue: runtime},
        {provide: Router, useValue: routerSpy},
      ],
    });
  }

  beforeEach(() => {
    oidcSpy = jasmine.createSpyObj<OidcSecurityService>('OidcSecurityService', [
      'authorize',
      'logoff',
      'checkAuth',
      'getAccessToken',
      'getIdToken',
      'forceRefreshSession',
    ]);
    oidcSpy.checkAuth.and.returnValue(
      of({
        isAuthenticated: true,
        userData: {},
        accessToken: 'access-token',
        idToken: 'id-token',
        configId: 'main',
        errorMessage: '',
      } as any),
    );
    oidcSpy.getAccessToken.and.returnValue(of('access-token'));
    oidcSpy.getIdToken.and.returnValue(of('id-token'));
    oidcSpy.logoff.and.returnValue(of(null));

    userServiceSpy = jasmine.createSpyObj<UserService>('UserService', [
      'getUserDetails',
    ]);

    routerSpy = jasmine.createSpyObj<Router>('Router', ['navigate']);
    routerSpy.navigate.and.resolveTo(true);

    configureModule();
  });

  it('login() delegates to OidcSecurityService.authorize()', () => {
    const svc = TestBed.inject(AuthService);
    svc.login();
    expect(oidcSpy.authorize).toHaveBeenCalled();
  });

  it('logout() clears local user details and calls OIDC logoff()', () => {
    localStorage.setItem('USER_DETAILS', '{"email":"x"}');
    const svc = TestBed.inject(AuthService);
    svc.logout();
    expect(oidcSpy.logoff).toHaveBeenCalled();
    expect(localStorage.getItem('USER_DETAILS')).toBeNull();
  });

  // Regression: previously logout() only routed to /login from the `error`
  // handler of oidc.logoff().subscribe(). Google does NOT implement the
  // OIDC end_session_endpoint, so for Google logoff() succeeds locally
  // with no redirect - the `next` callback fires, the `error` handler
  // does NOT, and we never navigated. The logout button looked
  // completely dead from the user's perspective. We must navigate to
  // /login on EVERY termination path.
  it('logout() navigates to /login on successful oidc.logoff()', done => {
    const svc = TestBed.inject(AuthService);
    svc.logout();
    // finalize() is microtask-scheduled by RxJS; wait one tick.
    setTimeout(() => {
      expect(routerSpy.navigate).toHaveBeenCalledWith(['/login']);
      done();
    }, 0);
  });

  it('logout() navigates to /login even when oidc.logoff() errors', done => {
    oidcSpy.logoff.and.returnValue(throwError(() => new Error('boom')));
    const svc = TestBed.inject(AuthService);
    svc.logout();
    setTimeout(() => {
      expect(routerSpy.navigate).toHaveBeenCalledWith(['/login']);
      done();
    }, 0);
  });

  // Defense-in-depth: for the Google authority, the access token still
  // grants API access for ~1h after a "logout" unless we explicitly tell
  // Google to revoke it. Without revocation, clicking "Login" again would
  // silently re-sign the user in (Google's cookie session is still alive).
  // logout() must POST the access_token to
  // https://oauth2.googleapis.com/revoke on the way out.
  it('logout() revokes the access token at Google for the Google authority', () => {
    TestBed.resetTestingModule();
    configureModule('https://accounts.google.com');
    const svc = TestBed.inject(AuthService);
    const httpMock = TestBed.inject(HttpTestingController);

    // Prime an access token onto the session by running initialize() and
    // flushing the resulting /users/me sync.
    svc.initialize().subscribe();
    httpMock
      .match(r => r.url.endsWith('/users/me'))
      .forEach(r =>
        r.flush({name: 'X', email: 'x@example.com', picture: '', roles: []}),
      );

    svc.logout();

    const revokeReq = httpMock.expectOne(
      'https://oauth2.googleapis.com/revoke',
    );
    expect(revokeReq.request.method).toBe('POST');
    expect(revokeReq.request.body).toContain('token=access-token');
    expect(revokeReq.request.headers.get('Content-Type')).toBe(
      'application/x-www-form-urlencoded',
    );
    revokeReq.flush({});
  });

  it('logout() does NOT call Google revocation for a non-Google authority', () => {
    const svc = TestBed.inject(AuthService);
    const httpMock = TestBed.inject(HttpTestingController);

    svc.initialize().subscribe();
    httpMock
      .match(r => r.url.endsWith('/users/me'))
      .forEach(r =>
        r.flush({name: 'X', email: 'x@example.com', picture: '', roles: []}),
      );

    svc.logout();

    const revokeAttempts = httpMock.match(
      'https://oauth2.googleapis.com/revoke',
    );
    expect(revokeAttempts.length).toBe(0);
  });

  // Regression: previously this resolved to the OAuth access_token
  // ("ya29..." for Google). The backend's OIDCVerifier (PyJWT) cannot
  // decode opaque access tokens; every /api/* call returned 401, the
  // interceptor tried silent refresh, refresh failed (Google doesn't
  // support iframe renewal), and the user was kicked back to /login
  // seconds after a successful sign-in. The method must now resolve to
  // the OIDC id_token (a JWT) which the backend can validate.
  it('getValidAccessToken$ resolves to the OIDC id_token (JWT), not the access_token', done => {
    const svc = TestBed.inject(AuthService);
    svc.getValidAccessToken$().subscribe(token => {
      expect(token).toBe('id-token');
      expect(oidcSpy.getIdToken).toHaveBeenCalled();
      expect(oidcSpy.getAccessToken).not.toHaveBeenCalled();
      done();
    });
  });

  it('getValidAccessToken$ errors if no id_token is available', done => {
    oidcSpy.getIdToken.and.returnValue(of(''));
    const svc = TestBed.inject(AuthService);
    svc.getValidAccessToken$().subscribe({
      next: () => done.fail('should not have emitted a token'),
      error: err => {
        expect(err.message).toContain('No valid ID token');
        done();
      },
    });
  });

  // Regression: forceRefresh$ used to delegate unconditionally to
  // OidcSecurityService.forceRefreshSession(). For the Google IdP that
  // call is impossible to satisfy (the PKCE SPA flow issues no
  // refresh_token, iframe-based renewal is blocked by X-Frame-Options),
  // so the library would burn ~30s through three internal timeout
  // retries before failing - 30s during which the user's UI was
  // unresponsive. We must short-circuit for Google.
  it('forceRefresh$ fails fast for the Google authority without calling forceRefreshSession', done => {
    TestBed.resetTestingModule();
    configureModule('https://accounts.google.com');
    const svc = TestBed.inject(AuthService);
    svc.forceRefresh$().subscribe({
      next: () => done.fail('should not have emitted a token'),
      error: err => {
        expect(err.message).toContain('not supported for the Google IdP');
        expect(oidcSpy.forceRefreshSession).not.toHaveBeenCalled();
        done();
      },
    });
  });

  it('forceRefresh$ still delegates to forceRefreshSession for non-Google IdPs', done => {
    oidcSpy.forceRefreshSession.and.returnValue(
      of({
        isAuthenticated: true,
        userData: {},
        accessToken: 'refreshed-access-token',
        idToken: 'refreshed-id-token',
        configId: 'main',
        errorMessage: '',
      } as any),
    );
    const svc = TestBed.inject(AuthService);
    svc.forceRefresh$().subscribe(token => {
      expect(token).toBe('refreshed-access-token');
      expect(oidcSpy.forceRefreshSession).toHaveBeenCalled();
      done();
    });
  });

  // Regression: previously AppComponent.ngOnInit and the AuthGuard each
  // called initialize() separately. Each call invoked OidcSecurityService
  // .checkAuth(), which in turn consumed the `?code=...` authorization-code
  // response. Calling it twice meant Google's /token endpoint received the
  // same code twice; the second exchange returned 400 invalid_grant and the
  // library cleared the session - giving the user the "logged in for a
  // millisecond then bounced back to /login" symptom. initialize() must
  // multicast the result of a single checkAuth() to every caller.
  it('initialize() only calls OidcSecurityService.checkAuth() once even when subscribed multiple times', done => {
    const svc = TestBed.inject(AuthService);
    const httpMock = TestBed.inject(HttpTestingController);
    let resolved = 0;
    const onSession = () => {
      resolved++;
      if (resolved === 2) {
        expect(oidcSpy.checkAuth).toHaveBeenCalledTimes(1);
        done();
      }
    };
    svc.initialize().subscribe(onSession);
    svc.initialize().subscribe(onSession);
    // Flush the one /users/me sync triggered by the single checkAuth() run.
    const reqs = httpMock.match(r => r.url.endsWith('/users/me'));
    expect(reqs.length).toBe(1);
    reqs.forEach(r =>
      r.flush({name: 'X', email: 'x@example.com', picture: '', roles: []}),
    );
  });

  it('initialize() can be re-run after logout (cache is invalidated)', done => {
    const svc = TestBed.inject(AuthService);
    const httpMock = TestBed.inject(HttpTestingController);

    svc.initialize().subscribe(() => {
      svc.logout();
      svc.initialize().subscribe(() => {
        expect(oidcSpy.checkAuth).toHaveBeenCalledTimes(2);
        done();
      });
      const after = httpMock.match(r => r.url.endsWith('/users/me'));
      after.forEach(r =>
        r.flush({name: 'X', email: 'x@example.com', picture: '', roles: []}),
      );
    });

    const first = httpMock.match(r => r.url.endsWith('/users/me'));
    first.forEach(r =>
      r.flush({name: 'X', email: 'x@example.com', picture: '', roles: []}),
    );
  });
});
