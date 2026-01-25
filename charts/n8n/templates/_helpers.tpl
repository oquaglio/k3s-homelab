{{/*
Common labels for all resources
*/}}
{{- define "n8n.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "n8n.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "n8n.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
