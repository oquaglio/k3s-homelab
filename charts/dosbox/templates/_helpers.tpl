{{/*
Common labels for all resources
*/}}
{{- define "dosbox.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "dosbox.selectorLabels" -}}
app: {{ .Chart.Name }}
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "dosbox.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
