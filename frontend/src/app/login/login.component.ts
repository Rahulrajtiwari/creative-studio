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
  AfterViewInit,
  Component,
  ElementRef,
  Inject,
  OnInit,
  PLATFORM_ID,
  ViewChild,
} from '@angular/core';
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
export class LoginComponent implements OnInit, AfterViewInit {
  loader = false;
  errorMessage = '';
  isBrowser: boolean;
  // Default to "Google" so the card matches the reference UI out of the box.
  // Overridden at runtime by `OIDC_IDP_DISPLAY_NAME` -> runtime-config.json.
  idpDisplayName = 'Google';

  @ViewChild('bgVideo') bgVideoRef?: ElementRef<HTMLVideoElement>;

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
      this.runtimeConfig.config.oidc.idpDisplayName || 'Google';

    // If the user is already authenticated (e.g. they refreshed the page or
    // came back from a silent renew) bounce them straight to home.
    if (this.isBrowser && this.authService.isLoggedIn()) {
      void this.router.navigate([HOME_ROUTE]);
    }
  }

  ngAfterViewInit(): void {
    // The inline `oncanplay`/`onloadedmetadata` handlers we used to have on
    // the <video> tag are blocked by our strict CSP (`script-src 'self'`,
    // no `unsafe-inline`). Trigger playback from the component instead so
    // the background video starts on every browser, including ones that
    // gate autoplay until a `muted` attribute is observed after metadata
    // arrives.
    if (!this.isBrowser) return;
    const video = this.bgVideoRef?.nativeElement;
    if (!video) return;
    video.muted = true;
    const playAttempt = video.play();
    if (playAttempt && typeof playAttempt.catch === 'function') {
      playAttempt.catch(err => {
        // Most browsers happily honour autoplay+muted; if a corporate policy
        // blocks it the static fallback colour is still shown.
        console.warn('Login background video autoplay was blocked.', err);
      });
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
