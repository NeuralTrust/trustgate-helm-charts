{{/*
Expand the name of the chart.
*/}}
{{- define "trustgate.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "trustgate.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "trustgate.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "trustgate.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "trustgate.selectorLabels" -}}
app.kubernetes.io/name: {{ include "trustgate.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "trustgate.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "trustgate.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Redis host
*/}}
{{- define "trustgate.redis.host" -}}
{{- printf "%s-redis" (include "trustgate.fullname" .) }}
{{- end }}

{{/*
Redis secret name
*/}}
{{- define "trustgate.redis.secretName" -}}
{{- printf "%s-redis" (include "trustgate.fullname" .) }}
{{- end }}

{{/*
PostgreSQL host
*/}}
{{- define "trustgate.postgresql.host" -}}
{{- printf "%s-postgresql" (include "trustgate.fullname" .) }}
{{- end }}

{{/*
PostgreSQL secret name
*/}}
{{- define "trustgate.postgresql.secretName" -}}
{{- printf "%s-postgresql" (include "trustgate.fullname" .) }}
{{- end }}

{{/*
Control Plane labels
*/}}
{{- define "trustgate.controlPlane.labels" -}}
{{ include "trustgate.labels" . }}
app.kubernetes.io/component: control-plane
{{- end }}

{{/*
Data Plane labels
*/}}
{{- define "trustgate.dataPlane.labels" -}}
{{ include "trustgate.labels" . }}
app.kubernetes.io/component: data-plane
{{- end }}

{{/*
Firewall labels
*/}}
{{- define "trustgate.firewall.labels" -}}
{{ include "trustgate.labels" . }}
app.kubernetes.io/component: firewall
{{- end }}

{{/*
Common labels for moderation
*/}}
{{- define "trustgate.moderation.labels" -}}
{{ include "trustgate.labels" . }}
app.kubernetes.io/component: moderation
{{- end }}

{{/*
Selector labels for moderation
*/}}
{{- define "trustgate.moderation.selectorLabels" -}}
{{ include "trustgate.selectorLabels" . }}
app.kubernetes.io/component: moderation
{{- end }}

{{/*
Create the name of the service account to use for moderation
*/}}
{{- define "trustgate.moderation.serviceAccountName" -}}
{{- if .Values.moderation.serviceAccount.create }}
{{- default (printf "%s-moderation" (include "trustgate.fullname" .)) .Values.moderation.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.moderation.serviceAccount.name }}
{{- end }}
{{- end }} 