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

import {HttpClientTestingModule} from '@angular/common/http/testing';
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
});
