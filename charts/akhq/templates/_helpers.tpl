{{/*
Common labels for all resources
*/}}
{{- define "akhq.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "akhq.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "akhq.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
