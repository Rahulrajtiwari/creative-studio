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

import {ComponentFixture, TestBed} from '@angular/core/testing';
import {NoopAnimationsModule} from '@angular/platform-browser/animations';
import {RouterTestingModule} from '@angular/router/testing';
import {MatCardModule} from '@angular/material/card';
import {MatProgressSpinnerModule} from '@angular/material/progress-spinner';
import {MatSnackBarModule} from '@angular/material/snack-bar';
import {MatButtonModule} from '@angular/material/button';

import {AuthService} from '../common/services/auth.service';
import {LoginComponent} from './login.component';
import {RuntimeConfigService} from '../runtime-config.service';

describe('LoginComponent', () => {
  let fixture: ComponentFixture<LoginComponent>;
  let component: LoginComponent;
  let authSpy: jasmine.SpyObj<AuthService>;

  beforeEach(async () => {
    authSpy = jasmine.createSpyObj<AuthService>('AuthService', [
      'login',
      'isLoggedIn',
    ]);
    authSpy.isLoggedIn.and.returnValue(false);

    const runtimeConfigStub: Partial<RuntimeConfigService> = {
      config: {
        backendURL: '/api',
        oidc: {
          authority: 'https://idp.example.com',
          clientId: 'client',
          scope: 'openid profile email',
          audience: 'api',
          idpDisplayName: 'Test SSO',
        },
      },
    };

    await TestBed.configureTestingModule({
      imports: [
        NoopAnimationsModule,
        RouterTestingModule,
        MatCardModule,
        MatProgressSpinnerModule,
        MatSnackBarModule,
        MatButtonModule,
      ],
      declarations: [LoginComponent],
      providers: [
        {provide: AuthService, useValue: authSpy},
        {provide: RuntimeConfigService, useValue: runtimeConfigStub},
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(LoginComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('renders the configured IdP display name in the SSO button', () => {
    const button = fixture.nativeElement.querySelector('button.login-btn');
    expect(button).toBeTruthy();
    expect(button!.textContent).toContain('Test SSO');
  });

  it('triggers AuthService.login() on click', () => {
    component.loginWithSso();
    expect(authSpy.login).toHaveBeenCalled();
  });
});
