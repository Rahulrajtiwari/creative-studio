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
import {RouterTestingModule} from '@angular/router/testing';
import {OidcSecurityService} from 'angular-auth-oidc-client';
import {of} from 'rxjs';

import {AuthService} from './auth.service';
import {RuntimeConfigService} from '../../runtime-config.service';
import {UserService} from './user.service';

describe('AuthService (OIDC)', () => {
  let oidcSpy: jasmine.SpyObj<OidcSecurityService>;
  let userServiceSpy: jasmine.SpyObj<UserService>;
  let runtime: Partial<RuntimeConfigService>;

  beforeEach(() => {
    oidcSpy = jasmine.createSpyObj<OidcSecurityService>('OidcSecurityService', [
      'authorize',
      'logoff',
      'checkAuth',
      'getAccessToken',
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
    oidcSpy.logoff.and.returnValue(of(null));

    userServiceSpy = jasmine.createSpyObj<UserService>('UserService', [
      'getUserDetails',
    ]);

    runtime = {
      config: {
        backendURL: '/api',
        oidc: {
          authority: 'https://idp.example.com',
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
      ],
    });
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

  it('getValidAccessToken$ resolves to the OIDC access token', done => {
    const svc = TestBed.inject(AuthService);
    svc.getValidAccessToken$().subscribe(token => {
      expect(token).toBe('access-token');
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
