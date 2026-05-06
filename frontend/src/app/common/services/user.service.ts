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
import {HttpClient} from '@angular/common/http';
import {Injectable, PLATFORM_ID, inject} from '@angular/core';
import {Observable} from 'rxjs';

import {RuntimeConfigService} from '../../runtime-config.service';
import {UserModel} from '../models/user.model';

interface BadgeInfoRequest {
  email: string;
  [key: string]: unknown;
}

const USER_DETAILS_KEY = 'USER_DETAILS';

@Injectable({providedIn: 'root'})
export class UserService {
  private platformId = inject(PLATFORM_ID);
  private http = inject(HttpClient);
  private runtimeConfig = inject(RuntimeConfigService);

  private get apiBase(): string {
    return this.runtimeConfig.config.backendURL;
  }

  /** Fetch a user profile from the backend. */
  get(uid: string): Observable<UserModel> {
    return this.http.get<UserModel>(`${this.apiBase}/users/${uid}`);
  }

  /** Soft-delete a user via the backend. Hard delete is admin-only. */
  delete(uid: string): Observable<void> {
    return this.http.delete<void>(`${this.apiBase}/users/${uid}`);
  }

  getUserDetails(): UserModel | null {
    if (!isPlatformBrowser(this.platformId)) return null;
    const raw = localStorage.getItem(USER_DETAILS_KEY);
    if (!raw) {
      return {
        name: '',
        email: '',
        picture: '',
        roles: [],
      } as unknown as UserModel;
    }
    try {
      return JSON.parse(raw) as UserModel;
    } catch {
      return null;
    }
  }

  getUserBadges(userEmail: string): Observable<unknown> {
    return this.http.post<unknown>(`${this.apiBase}/badge-info`, {
      email: userEmail,
    });
  }

  updateBadgeInfo(reqObj: BadgeInfoRequest): Observable<unknown> {
    return this.http.post<unknown>(
      `${this.apiBase}/badge-confetti-status`,
      reqObj,
    );
  }
}
