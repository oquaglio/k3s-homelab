{{/*
Common labels for all resources
*/}}
{{- define "stock-analyzer.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "stock-analyzer.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "stock-analyzer.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
