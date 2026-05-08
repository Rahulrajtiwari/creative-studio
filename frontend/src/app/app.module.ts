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

import {ClipboardModule} from '@angular/cdk/clipboard';
import {DragDropModule} from '@angular/cdk/drag-drop';
import {ScrollingModule} from '@angular/cdk/scrolling';
import {NgOptimizedImage} from '@angular/common';
import {
  HTTP_INTERCEPTORS,
  provideHttpClient,
  withInterceptorsFromDi,
} from '@angular/common/http';
import {HttpClient} from '@angular/common/http';
import {APP_INITIALIZER, Injector, NgModule} from '@angular/core';
import {FormsModule, ReactiveFormsModule} from '@angular/forms';
import {Observable, of} from 'rxjs';
import {catchError, map} from 'rxjs/operators';
import {MatButtonModule} from '@angular/material/button';
import {MatButtonToggleModule} from '@angular/material/button-toggle';
import {MatCardModule} from '@angular/material/card';
import {MatChipsModule} from '@angular/material/chips';
import {MatCheckboxModule} from '@angular/material/checkbox';
import {MatNativeDateModule} from '@angular/material/core';
import {MatDatepickerModule} from '@angular/material/datepicker';
import {MatDialogModule} from '@angular/material/dialog';
import {MatDividerModule} from '@angular/material/divider';
import {MatExpansionModule} from '@angular/material/expansion';
import {MatFormFieldModule} from '@angular/material/form-field';
import {MatIconModule} from '@angular/material/icon';
import {MatInputModule} from '@angular/material/input';
import {MatMenuModule} from '@angular/material/menu';
import {MatPaginatorModule} from '@angular/material/paginator';
import {MatProgressBarModule} from '@angular/material/progress-bar';
import {MatProgressSpinnerModule} from '@angular/material/progress-spinner';
import {MatRadioModule} from '@angular/material/radio';
import {MatSelectModule} from '@angular/material/select';
import {MatSliderModule} from '@angular/material/slider';
import {MatSlideToggleModule} from '@angular/material/slide-toggle';
import {MatStepperModule} from '@angular/material/stepper';
import {MatTableModule} from '@angular/material/table';
import {MatTabsModule} from '@angular/material/tabs';
import {MatToolbarModule} from '@angular/material/toolbar';
import {MatTooltipModule} from '@angular/material/tooltip';
import {BrowserModule, provideClientHydration} from '@angular/platform-browser';
import {BrowserAnimationsModule} from '@angular/platform-browser/animations';
import {
  LogLevel,
  OpenIdConfiguration,
  StsConfigHttpLoader,
  StsConfigLoader,
  provideAuth,
} from 'angular-auth-oidc-client';
import {ImageCropperComponent} from 'ngx-image-cropper';

import {setAppInjector} from './app-injector';
import {AppRoutingModule} from './app-routing.module';
import {AppComponent} from './app.component';
import {AudioComponent} from './audio/audio.component';
import {AuthInterceptor} from './auth.interceptor';
import {AssignTagsDialogComponent} from './common/components/assign-tags-dialog/assign-tags-dialog.component';
import {FlowPromptBoxComponent} from './common/components/flow-prompt-box/flow-prompt-box.component';
import {ImageCropperDialogComponent} from './common/components/image-cropper-dialog/image-cropper-dialog.component';
import {ImageSelectorComponent} from './common/components/image-selector/image-selector.component';
import {MediaLightboxComponent} from './common/components/media-lightbox/media-lightbox.component';
import {NotificationContainerComponent} from './common/components/notification-container/notification-container.component';
import {SourceAssetGalleryComponent} from './common/components/source-asset-gallery/source-asset-gallery.component';
import {SharedModule} from './common/shared.module';
import {AddVoiceDialogComponent} from './components/add-voice-dialog/add-voice-dialog.component';
import {FooterComponent} from './footer/footer.component';
import {FunTemplatesComponent} from './fun-templates/fun-templates.component';
import {MediaDetailComponent} from './gallery/media-detail/media-detail.component';
import {MediaGalleryComponent} from './gallery/media-gallery/media-gallery.component';
import {HeaderComponent} from './header/header.component';
import {HomeComponent} from './home/home.component';
import {LoginComponent} from './login/login.component';
import {RuntimeConfigService} from './runtime-config.service';
import {UpscaleComponent} from './upscale/upscale.component';
import {VideoComponent} from './video/video.component';
import {VtoComponent} from './vto/vto.component';
import {WorkbenchComponent} from './workbench/workbench.component';
import {BatchExecutionModalComponent} from './workflows/execution-history/batch-execution-modal/batch-execution-modal.component';
import {ExecutionDetailsModalComponent} from './workflows/execution-history/execution-details-modal/execution-details-modal.component';
import {ExecutionHistoryComponent} from './workflows/execution-history/execution-history.component';
import {StepExecutionDetailsComponent} from './workflows/shared/step-execution-details/step-execution-details.component';
import {AddStepModalComponent} from './workflows/workflow-editor/add-step-modal/add-step-modal.component';
import {RunWorkflowModalComponent} from './workflows/workflow-editor/run-workflow-modal/run-workflow-modal.component';
import {StepInputFieldComponent} from './workflows/workflow-editor/step-components/generic-step/components/step-input-field/step-input-field.component';
import {StepMediaInputComponent} from './workflows/workflow-editor/step-components/generic-step/components/step-media-input/step-media-input.component';
import {GenericStepComponent} from './workflows/workflow-editor/step-components/generic-step/generic-step.component';
import {WorkflowEditorComponent} from './workflows/workflow-editor/workflow-editor.component';
import {WorkflowListComponent} from './workflows/workflow-list/workflow-list.component';
import {WorkflowStatusPipe} from './workflows/workflow-status.pipe';

/**
 * APP_INITIALIZER that fetches /assets/runtime-config.json before any other
 * service is constructed. The OIDC client config is built from the loaded
 * runtime config so the same image works in every environment.
 */
function initializeRuntimeConfig(
  runtime: RuntimeConfigService,
): () => Promise<void> {
  return () => runtime.load().then(() => undefined);
}

/**
 * Factory used by `angular-auth-oidc-client` to obtain its configuration
 * asynchronously. It pulls the same runtime-config.json that the rest of the
 * SPA reads from, so the SPA, the OIDC client, and the backend always agree
 * on the issuer/audience.
 */
function oidcConfigLoaderFactory(http: HttpClient): StsConfigLoader {
  const origin =
    typeof window !== 'undefined' ? window.location.origin : 'http://localhost:4200';

  const config$: Observable<OpenIdConfiguration> = http
    .get<{
      backendURL: string;
      oidc: {
        authority: string;
        clientId: string;
        scope: string;
        audience: string;
        idpDisplayName: string;
      };
    }>('/assets/runtime-config.json')
    .pipe(
      map((remote: any) => ({
        authority: remote?.oidc?.authority,
        redirectUrl: `${origin}/`,
        postLogoutRedirectUri: `${origin}/login`,
        clientId: remote?.oidc?.clientId,
        scope: remote?.oidc?.scope || 'openid profile email',
        responseType: 'code',
        silentRenew: true,
        useRefreshToken: true,
        renewTimeBeforeTokenExpiresInSeconds: 60,
        ignoreNonceAfterRefresh: true,
        customParamsAuthRequest: remote?.oidc?.audience
          ? {audience: remote.oidc.audience}
          : undefined,
        secureRoutes: ['/api/'],
        logLevel: LogLevel.Warn,
        historyCleanupOff: false,
      })),
      catchError(() =>
        of<OpenIdConfiguration>({
          authority: '',
          redirectUrl: `${origin}/`,
          postLogoutRedirectUri: `${origin}/login`,
          clientId: '',
          scope: 'openid profile email',
          responseType: 'code',
          silentRenew: false,
          logLevel: LogLevel.Warn,
        }),
      ),
    );

  return new StsConfigHttpLoader(config$);
}

@NgModule({
  declarations: [
    AppComponent,
    HeaderComponent,
    FooterComponent,
    HomeComponent,
    LoginComponent,
    FunTemplatesComponent,
    VideoComponent,
    MediaGalleryComponent,
    AssignTagsDialogComponent,
    MediaDetailComponent,
    MediaLightboxComponent,
    VtoComponent,
    ImageSelectorComponent,
    SourceAssetGalleryComponent,
    ImageCropperDialogComponent,
    WorkbenchComponent,
    AudioComponent,
    AddVoiceDialogComponent,
    WorkflowListComponent,
    WorkflowEditorComponent,
    AddStepModalComponent,
    GenericStepComponent,
    StepInputFieldComponent,
    StepMediaInputComponent,
    RunWorkflowModalComponent,
    ExecutionHistoryComponent,
    ExecutionDetailsModalComponent,
    StepExecutionDetailsComponent,
    BatchExecutionModalComponent,
    UpscaleComponent,
  ],
  imports: [
    BrowserModule,
    AppRoutingModule,
    NgOptimizedImage,
    MatTooltipModule,
    MatToolbarModule,
    MatDividerModule,
    MatButtonModule,
    MatChipsModule,
    MatDatepickerModule,
    MatNativeDateModule,
    MatRadioModule,
    MatIconModule,
    MatStepperModule,
    MatFormFieldModule,
    MatInputModule,
    ReactiveFormsModule,
    BrowserAnimationsModule,
    MatSelectModule,
    MatProgressSpinnerModule,
    MatMenuModule,
    MatCheckboxModule,
    MatCardModule,
    MatTableModule,
    FormsModule,
    ScrollingModule,
    MatProgressBarModule,
    MatExpansionModule,
    MatTabsModule,
    MatDialogModule,
    SharedModule,
    MatSlideToggleModule,
    MatButtonToggleModule,
    ImageCropperComponent,
    MatSliderModule,
    NotificationContainerComponent,
    FlowPromptBoxComponent,
    DragDropModule,
    MatPaginatorModule,
    ClipboardModule,
    WorkflowStatusPipe,
  ],
  providers: [
    provideClientHydration(),
    provideHttpClient(withInterceptorsFromDi()),
    {
      provide: APP_INITIALIZER,
      useFactory: initializeRuntimeConfig,
      deps: [RuntimeConfigService],
      multi: true,
    },
    provideAuth({
      loader: {
        provide: StsConfigLoader,
        useFactory: oidcConfigLoaderFactory,
        deps: [HttpClient],
      },
    }),
    {provide: HTTP_INTERCEPTORS, useClass: AuthInterceptor, multi: true},
  ],
  bootstrap: [AppComponent],
})
export class AppModule {
  constructor(injector: Injector) {
    setAppInjector(injector);
  }
}
