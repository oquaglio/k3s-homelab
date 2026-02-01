{{/*
Common labels for all resources
*/}}
{{- define "postgresql.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "postgresql.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "postgresql.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
