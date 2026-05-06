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
import {Injectable, PLATFORM_ID, inject} from '@angular/core';
import {
  ActivatedRouteSnapshot,
  CanActivate,
  Router,
  RouterStateSnapshot,
  UrlTree,
} from '@angular/router';
import {Observable} from 'rxjs';
import {map, take} from 'rxjs/operators';

import {AuthService} from './auth.service';
import {UserService} from './user.service';
import {UserRolesEnum} from '../models/user.model';

const LOGIN_ROUTE = '/login';

@Injectable({providedIn: 'root'})
export class AuthGuardService implements CanActivate {
  private platformId = inject(PLATFORM_ID);
  private authService = inject(AuthService);
  private userService = inject(UserService);
  private router = inject(Router);

  canActivate(
    route: ActivatedRouteSnapshot,
    _state: RouterStateSnapshot,
  ):
    | Observable<boolean | UrlTree>
    | Promise<boolean | UrlTree>
    | boolean
    | UrlTree {
    if (!isPlatformBrowser(this.platformId)) {
      // Server-side: allow shell to render, the browser will re-evaluate.
      return true;
    }

    return this.authService.initialize().pipe(
      take(1),
      map(session => {
        if (!session.authenticated) {
          void this.router.navigate([LOGIN_ROUTE]);
          return false;
        }
        const requiredRoles = route.data?.['requiredRoles'] as
          | UserRolesEnum[]
          | undefined;
        if (requiredRoles && requiredRoles.length > 0) {
          const userDetails = this.userService.getUserDetails();
          const userRoles = userDetails?.roles || [];
          const hasRole = requiredRoles.some(role =>
            userRoles.includes(role),
          );
          if (!hasRole) {
            void this.router.navigate(['/']);
            return false;
          }
        }
        return true;
      }),
    );
  }
}
