{{/*
Common labels for all resources
*/}}
{{- define "pgadmin.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pgadmin.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "pgadmin.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
