{{/* vim: set filetype=mustache: */}}

{{- define "cs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cs.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "cs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cs.labels" -}}
helm.sh/chart: {{ include "cs.chart" . }}
app.kubernetes.io/name: {{ include "cs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: creative-studio
environment: {{ .Values.global.environment | quote }}
{{- end -}}

{{- define "cs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Component-aware names */}}
{{- define "cs.backend.fullname" -}}
{{ include "cs.fullname" . }}-backend
{{- end -}}

{{- define "cs.frontend.fullname" -}}
{{ include "cs.fullname" . }}-frontend
{{- end -}}

{{- define "cs.migrations.fullname" -}}
{{ include "cs.fullname" . }}-migrations
{{- end -}}

{{/* Service-account names */}}
{{- define "cs.backend.serviceAccountName" -}}
{{- if .Values.backend.serviceAccount.create -}}
{{ default (printf "%s-backend" (include "cs.fullname" .)) .Values.backend.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.backend.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{- define "cs.frontend.serviceAccountName" -}}
{{- if .Values.frontend.serviceAccount.create -}}
{{ default (printf "%s-frontend" (include "cs.fullname" .)) .Values.frontend.serviceAccount.name }}
{{- else -}}
{{ default "default" .Values.frontend.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/* Resolve effective values (with fall-backs to globals). */}}
{{- define "cs.effective.projectId" -}}
{{- coalesce .Values.backend.config.PROJECT_ID .Values.global.projectId -}}
{{- end -}}

{{- define "cs.effective.location" -}}
{{- coalesce .Values.backend.config.LOCATION .Values.global.region -}}
{{- end -}}

{{- define "cs.effective.appHost" -}}
{{- with .Values.global.appHost -}}{{ . }}{{- end -}}
{{- end -}}

{{- define "cs.effective.trustedHosts" -}}
{{- $h := .Values.global.appHost -}}
{{- $t := .Values.backend.config.TRUSTED_HOSTS -}}
{{- if $t -}}{{ $t }}{{- else -}}{{ $h }}{{- end -}}
{{- end -}}

{{- define "cs.effective.frontendUrl" -}}
{{- printf "https://%s" (include "cs.effective.appHost" .) -}}
{{- end -}}

{{- define "cs.effective.backendHost" -}}
{{- $defaultHost := printf "%s.%s.svc.cluster.local" (include "cs.backend.fullname" .) .Release.Namespace -}}
{{- coalesce .Values.frontend.config.BACKEND_SERVICE_HOST $defaultHost -}}
{{- end -}}

{{/* image refs */}}
{{/*
Build a fully qualified container image reference from a registry, repository
and tag/digest. Accepts any of:
  tag: "1.2.3"                                  -> registry/repo:1.2.3
  tag: "@sha256:abc..."                         -> registry/repo@sha256:abc...
  tag: "sha256:abc..."                          -> registry/repo@sha256:abc...
  tag: "<repo>@sha256:abc..."  (legacy form)    -> registry/repo@sha256:abc...
The legacy "<repo>@sha256:..." form is tolerated because previous values
files were authored that way (the repo prefix in the tag is silently
stripped). New values files should use the bare "@sha256:..." form.
*/}}
{{- define "cs.image.ref" -}}
{{- $reg := required "image.registry is required" .registry -}}
{{- $repo := required "image.repository is required" .repository -}}
{{- $tag := required "image.tag is required" .tag -}}
{{- if contains "@sha256:" $tag -}}
  {{- /* Strip anything before the @sha256: part, leave only the digest */ -}}
  {{- $digest := printf "@sha256:%s" (index (splitList "@sha256:" $tag) 1) -}}
  {{- printf "%s/%s%s" $reg $repo $digest -}}
{{- else if hasPrefix "sha256:" $tag -}}
  {{- printf "%s/%s@%s" $reg $repo $tag -}}
{{- else -}}
  {{- printf "%s/%s:%s" $reg $repo $tag -}}
{{- end -}}
{{- end -}}

{{- define "cs.backend.image" -}}
{{- include "cs.image.ref" (dict "registry" .Values.image.registry "repository" .Values.backend.image.repository "tag" .Values.backend.image.tag) -}}
{{- end -}}

{{- define "cs.frontend.image" -}}
{{- include "cs.image.ref" (dict "registry" .Values.image.registry "repository" .Values.frontend.image.repository "tag" .Values.frontend.image.tag) -}}
{{- end -}}

{{- define "cs.migrations.image" -}}
{{- include "cs.image.ref" (dict "registry" .Values.image.registry "repository" .Values.migrations.image.repository "tag" .Values.migrations.image.tag) -}}
{{- end -}}
