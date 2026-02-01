{{/*
Common labels for all resources
*/}}
{{- define "spark.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for master
*/}}
{{- define "spark.masterSelectorLabels" -}}
app: {{ .Chart.Name }}
component: master
{{- end }}

{{/*
Selector labels for worker
*/}}
{{- define "spark.workerSelectorLabels" -}}
app: {{ .Chart.Name }}
component: worker
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "spark.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
