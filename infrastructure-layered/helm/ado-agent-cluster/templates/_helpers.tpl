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
Generate scaled job name for agent pool
*/}}
{{- define "ado-agent-cluster.scaledJobName" -}}
{{- printf "%s-scaledjob" .name }}
{{- end }}

{{/*
Generate placeholder registration job name for agent pool
*/}}
{{- define "ado-agent-cluster.placeholderJobName" -}}
{{- printf "%s-placeholder" .name }}
{{- end }}

{{/*
Generate placeholder ADO agent name for agent pool
*/}}
{{- define "ado-agent-cluster.placeholderAgentName" -}}
{{- if .autoscaling.templateAgentName }}
{{- .autoscaling.templateAgentName }}
{{- else }}
{{- printf "%s-keda-template" .name }}
{{- end }}
{{- end }}

{{/*
ADO KEDA proxy names and image reference
*/}}
{{- define "ado-agent-cluster.kedaProxyName" -}}
{{- default "ado-keda-proxy" .Values.adoKedaProxy.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ado-agent-cluster.kedaProxyImage" -}}
{{- if .Values.adoKedaProxy.image.digest }}
{{- printf "%s@%s" .Values.adoKedaProxy.image.repository .Values.adoKedaProxy.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.adoKedaProxy.image.repository .Values.adoKedaProxy.image.tag }}
{{- end }}
{{- end }}

{{- define "ado-agent-cluster.kedaProxyURL" -}}
{{- printf "http://%s.%s.svc.cluster.local:%v/%s" (include "ado-agent-cluster.kedaProxyName" .) .Values.global.namespace .Values.adoKedaProxy.service.port .Values.auth.adoOrg }}
{{- end }}
