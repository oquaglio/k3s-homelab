{{/*
Common labels for all resources
*/}}
{{- define "kafka-ui.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kafka-ui.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "kafka-ui.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
