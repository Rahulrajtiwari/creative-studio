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
import {Component, Inject, OnInit, PLATFORM_ID} from '@angular/core';
import {MatSnackBar} from '@angular/material/snack-bar';
import {Router} from '@angular/router';

import {RuntimeConfigService} from '../runtime-config.service';
import {AuthService} from '../common/services/auth.service';
import {handleErrorSnackbar} from '../utils/handleMessageSnackbar';

const HOME_ROUTE = '/';

@Component({
  selector: 'app-login',
  templateUrl: './login.component.html',
  styleUrls: ['./login.component.scss'],
})
export class LoginComponent implements OnInit {
  loader = false;
  errorMessage = '';
  isBrowser: boolean;
  idpDisplayName = 'Corporate SSO';

  constructor(
    private authService: AuthService,
    private router: Router,
    private snackBar: MatSnackBar,
    private runtimeConfig: RuntimeConfigService,
    @Inject(PLATFORM_ID) platformId: object,
  ) {
    this.isBrowser = isPlatformBrowser(platformId);
  }

  ngOnInit(): void {
    this.idpDisplayName =
      this.runtimeConfig.config.oidc.idpDisplayName || 'Corporate SSO';

    // If the user is already authenticated (e.g. they refreshed the page or
    // came back from a silent renew) bounce them straight to home.
    if (this.isBrowser && this.authService.isLoggedIn()) {
      void this.router.navigate([HOME_ROUTE]);
    }
  }

  loginWithSso(): void {
    this.loader = true;
    try {
      this.authService.login();
    } catch (err: unknown) {
      this.loader = false;
      console.error('Login error:', err);
      handleErrorSnackbar(this.snackBar, err, 'Login Error');
    }
  }
}
