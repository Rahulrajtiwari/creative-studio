/**
 * Copyright 2025 Google LLC
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

import {Component, OnInit} from '@angular/core';
import {Router, NavigationEnd, Event as NavigationEvent} from '@angular/router';
import {trigger, transition, style, query, animate} from '@angular/animations';
import {AuthService} from './common/services/auth.service';
import {LoadingService} from './common/services/loading.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrl: './app.component.scss',
  animations: [
    trigger('routeAnimations', [
      transition('* <=> *', [
        style({position: 'relative'}),
        query(
          ':enter, :leave',
          [
            style({
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
            }),
          ],
          {optional: true},
        ),
        query(':enter', [style({opacity: 0})], {optional: true}),
        query(':leave', [animate('200ms ease-out', style({opacity: 0}))], {
          optional: true,
        }),
        query(':enter', [animate('300ms ease-in', style({opacity: 1}))], {
          optional: true,
        }),
      ]),
    ]),
  ],
})
export class AppComponent implements OnInit {
  title = 'creative-studio';
  // The header includes <app-workspace-switcher> which fires
  // `GET /api/workspaces` from its ngOnInit. If the header mounts before
  // OIDC `checkAuth()` has finished, that HTTP call races the token
  // exchange and is rejected by the interceptor. To stop that race the
  // header is hidden by default and we only flip it on once we know both
  // (a) the user is authenticated, and (b) the current route is not /login.
  showHeader = false;
  private authReady = false;
  private onAuthRoute = false;

  constructor(
    private router: Router,
    public loadingService: LoadingService,
    private authService: AuthService,
  ) {
    this.router.events.subscribe((event: NavigationEvent) => {
      if (event instanceof NavigationEnd) {
        const urlPath = event.url.split('?')[0];
        this.onAuthRoute =
          urlPath === '/login' ||
          urlPath === '/login/' ||
          urlPath.startsWith('/login') ||
          urlPath.includes('reset-password') ||
          urlPath.includes('support-ticket');
        this.updateHeaderVisibility();
      }
    });
  }

  ngOnInit(): void {
    // Resolve any pending OIDC redirect (Authorization Code response or
    // silent-renew callback) before any guarded route is evaluated.
    this.authService.initialize().subscribe({
      next: session => {
        this.authReady = session.authenticated;
        this.updateHeaderVisibility();
      },
      error: err => {
        console.error('OIDC initialization failed:', err);
        this.authReady = false;
        this.updateHeaderVisibility();
      },
    });
  }

  private updateHeaderVisibility(): void {
    this.showHeader = this.authReady && !this.onAuthRoute;
  }
}
