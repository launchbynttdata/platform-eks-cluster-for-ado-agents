{{/*
Expand the name of the chart.
*/}}
{{- define "ado-agent-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "ado-agent-cluster.fullname" -}}
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
{{- define "ado-agent-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ado-agent-cluster.labels" -}}
helm.sh/chart: {{ include "ado-agent-cluster.chart" . }}
{{ include "ado-agent-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ado-agent-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ado-agent-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Agent pool selector labels
*/}}
{{- define "ado-agent-cluster.agentPoolSelectorLabels" -}}
{{ include "ado-agent-cluster.selectorLabels" .root }}
app.kubernetes.io/component: {{ .poolName }}
{{- end }}

{{/*
Create the name of the service account for an agent pool
*/}}
{{- define "ado-agent-cluster.serviceAccountName" -}}
{{- if .serviceAccount.name }}
{{- .serviceAccount.name }}
{{- else }}
{{- printf "%s-%s" (include "ado-agent-cluster.fullname" .root) .poolName }}
{{- end }}
{{- end }}

{{/*
Generate trigger authentication name for KEDA
*/}}
{{- define "ado-agent-cluster.triggerAuthName" -}}
{{- if .autoscaling.triggerAuthenticationName }}
{{- .autoscaling.triggerAuthenticationName }}
{{- else }}
{{- printf "%s-trigger-auth" .name }}
{{- end }}
{{- end }}

{{/*
Generate deployment name for agent pool
*/}}
{{- define "ado-agent-cluster.deploymentName" -}}
{{- printf "%s-deployment" .name }}
{{- end }}

{{/*
Generate scaled object name for agent pool
*/}}
{{- define "ado-agent-cluster.scaledObjectName" -}}
{{- printf "%s-scaledobject" .name }}
{{- end }}