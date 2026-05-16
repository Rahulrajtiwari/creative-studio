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

import {GalleryService} from './gallery.service';
import {WorkspaceStateService} from '../services/workspace/workspace-state.service';
import {environment} from '../../environments/environment';

const SEARCH_URL = `${environment.backendURL}/gallery/search`;
// Slightly longer than the 50ms debounce in the reactive pipeline.
const PAST_DEBOUNCE_MS = 80;

describe('GalleryService — workspaceId race-condition guard', () => {
  let service: GalleryService;
  let httpMock: HttpTestingController;
  let workspaceState: WorkspaceStateService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule],
      providers: [GalleryService, WorkspaceStateService],
    });
    service = TestBed.inject(GalleryService);
    httpMock = TestBed.inject(HttpTestingController);
    workspaceState = TestBed.inject(WorkspaceStateService);
  });

  afterEach(() => {
    httpMock.verify();
    service.ngOnDestroy();
  });

  // Regression: previously the reactive pipeline only guarded against
  // `!filters` and let `workspaceId` be null/undefined through. On gallery
  // page mount, ngOnInit calls setFilters() while GET /api/workspaces is
  // still in flight, so the BehaviorSubject-seeded `activeWorkspaceId$ =
  // null` was paired with the new filters, the request fired with no
  // workspace_id, and the backend (which strictly requires it for
  // non-admin users) returned 400 - freezing the gallery in a "loading
  // forever" state with the workspace switcher half-rendered.
  it('does NOT fire /gallery/search when setFilters() runs before activeWorkspaceId is set', done => {
    service.setFilters({limit: 40} as any);
    setTimeout(() => {
      const reqs = httpMock.match(SEARCH_URL);
      expect(reqs.length).toBe(0);
      done();
    }, PAST_DEBOUNCE_MS);
  });

  it('fires /gallery/search once activeWorkspaceId$ emits, with the workspaceId in the body', done => {
    service.setFilters({limit: 40} as any);
    setTimeout(() => {
      // Still no request because workspaceId is null.
      expect(httpMock.match(SEARCH_URL).length).toBe(0);
      workspaceState.setActiveWorkspaceId(7);
      setTimeout(() => {
        const reqs = httpMock.match(SEARCH_URL);
        expect(reqs.length).toBe(1);
        expect(reqs[0].request.method).toBe('POST');
        expect(reqs[0].request.body.workspaceId).toBe(7);
        reqs[0].flush({data: [], totalPages: 1});
        done();
      }, PAST_DEBOUNCE_MS);
    }, PAST_DEBOUNCE_MS);
  });

  it('fires /gallery/search when activeWorkspaceId is already set before setFilters()', done => {
    workspaceState.setActiveWorkspaceId(3);
    service.setFilters({limit: 40} as any);
    setTimeout(() => {
      const reqs = httpMock.match(SEARCH_URL);
      expect(reqs.length).toBe(1);
      expect(reqs[0].request.body.workspaceId).toBe(3);
      reqs[0].flush({data: [], totalPages: 1});
      done();
    }, PAST_DEBOUNCE_MS);
  });

  // Regression: loadGallery() is the pagination entry point. It used to
  // read getActiveWorkspaceId() synchronously and fire fetchImages() with
  // `workspaceId: undefined` when nothing was selected yet. Same 400 risk
  // as the reactive pipeline above - just triggered by a scroll instead
  // of a page mount.
  it('loadGallery() is a no-op when there is no active workspaceId', () => {
    service.loadGallery();
    const reqs = httpMock.match(SEARCH_URL);
    expect(reqs.length).toBe(0);
  });

  it('loadGallery() issues the request when activeWorkspaceId is set', () => {
    workspaceState.setActiveWorkspaceId(11);
    service.loadGallery();
    const reqs = httpMock.match(SEARCH_URL);
    expect(reqs.length).toBe(1);
    expect(reqs[0].request.body.workspaceId).toBe(11);
    reqs[0].flush({data: [], totalPages: 1});
  });
});
