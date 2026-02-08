{{/*
Common labels for all resources
*/}}
{{- define "pg-backup.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pg-backup.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "pg-backup.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
