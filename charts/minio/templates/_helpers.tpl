{{/*
Common labels for all resources
*/}}
{{- define "minio.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "minio.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "minio.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
