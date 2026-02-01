{{/*
Common labels for all resources
*/}}
{{- define "kafka.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kafka.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "kafka.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
