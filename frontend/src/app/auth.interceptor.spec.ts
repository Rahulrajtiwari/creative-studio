/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

import {HttpClient, HTTP_INTERCEPTORS} from '@angular/common/http';
import {
  HttpClientTestingModule,
  HttpTestingController,
} from '@angular/common/http/testing';
import {TestBed} from '@angular/core/testing';
import {of} from 'rxjs';

import {AuthInterceptor} from './auth.interceptor';
import {AuthService} from './common/services/auth.service';
import {RuntimeConfigService} from './runtime-config.service';

describe('AuthInterceptor', () => {
  let http: HttpClient;
  let httpMock: HttpTestingController;
  let authSpy: jasmine.SpyObj<AuthService>;

  function configure(authenticated: boolean, token: string | null) {
    authSpy = jasmine.createSpyObj<AuthService>('AuthService', [
      'initialize',
      'getValidAccessToken$',
      'forceRefresh$',
      'logout',
    ]);
    authSpy.initialize.and.returnValue(
      of({
        authenticated,
        accessToken: token,
        idToken: null,
        expiresAt: null,
      }),
    );
    if (token) {
      authSpy.getValidAccessToken$.and.returnValue(of(token));
    } else {
      authSpy.getValidAccessToken$.and.returnValue(of(''));
    }

    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule],
      providers: [
        {provide: AuthService, useValue: authSpy},
        {
          provide: RuntimeConfigService,
          useValue: {
            config: {
              backendURL: '/api',
              oidc: {
                authority: '',
                clientId: '',
                scope: '',
                audience: '',
                idpDisplayName: '',
              },
            },
          },
        },
        {provide: HTTP_INTERCEPTORS, useClass: AuthInterceptor, multi: true},
      ],
    });

    http = TestBed.inject(HttpClient);
    httpMock = TestBed.inject(HttpTestingController);
  }

  afterEach(() => {
    if (httpMock) {
      httpMock.verify();
    }
  });

  it('passes through requests to non-API URLs without consulting the auth service', () => {
    configure(true, 'tok');
    http.get('/assets/runtime-config.json').subscribe();
    httpMock.expectOne('/assets/runtime-config.json').flush({});
    expect(authSpy.getValidAccessToken$).not.toHaveBeenCalled();
  });

  it('attaches a Bearer token to API requests once the session is authenticated', () => {
    configure(true, 'tok');
    http.get('/api/workspaces').subscribe();
    const req = httpMock.expectOne('/api/workspaces');
    expect(req.request.headers.get('Authorization')).toBe('Bearer tok');
    req.flush([]);
  });

  // Regression: previously a HTTP request fired before checkAuth() resolved
  // (e.g. workspace-switcher's load-on-init while OAuth was still in flight)
  // triggered authService.logout(), which then calls Google's logoff endpoint
  // and redirects the user to /login - the "successful login immediately
  // followed by logout / 'No valid access token' toast" symptom. The
  // interceptor must now silently swallow such requests instead of tearing
  // down the session.
  it('does NOT call authService.logout() when initialize() reports the user is not authenticated', done => {
    configure(false, null);
    http.get('/api/workspaces').subscribe({
      next: () => done.fail('should not have completed with a value'),
      complete: () => {
        expect(authSpy.logout).not.toHaveBeenCalled();
        done();
      },
      error: () => done.fail('should not have errored'),
    });
    httpMock.expectNone('/api/workspaces');
  });

  // Regression: the BFF token-exchange endpoint (POST /api/auth/token) is what
  // *creates* the session, so it can never carry a Bearer token. If the
  // interceptor gated it on initialize() the OIDC library's very first
  // /token call would be swallowed (it fires while the user is still
  // unauthenticated) and login would silently hang on a blank page.
  it('does NOT gate or modify requests to /api/auth/* (pre-auth endpoints)', () => {
    configure(false, null);
    http
      .post('/api/auth/token', 'grant_type=authorization_code&code=abc')
      .subscribe();
    const req = httpMock.expectOne('/api/auth/token');
    expect(req.request.headers.get('Authorization')).toBeNull();
    expect(authSpy.initialize).not.toHaveBeenCalled();
    expect(authSpy.getValidAccessToken$).not.toHaveBeenCalled();
    req.flush({access_token: 'tok'});
  });
});
