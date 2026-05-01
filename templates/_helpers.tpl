{{/*
Expand the name of the chart.
*/}}
{{- define "cruduserchart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cruduserchart.fullname" -}}
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
{{- define "cruduserchart.chart" -}}
{{- printf "%s-%s" (trimSuffix "chart" .Chart.Name) .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cruduserchart.labels" -}}
app: {{ include "cruduserchart.chart" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cruduserchart.selectorLabels" -}}
app: {{ include "cruduserchart.chart" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "cruduserchart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cruduserchart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
