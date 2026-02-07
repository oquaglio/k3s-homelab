{{/*
Common labels for all resources
*/}}
{{- define "flink.labels" -}}
app: {{ .Chart.Name }}
chart: {{ .Chart.Name }}-{{ .Chart.Version }}
release: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for jobmanager
*/}}
{{- define "flink.jobmanagerSelectorLabels" -}}
app: {{ .Chart.Name }}
component: jobmanager
{{- end }}

{{/*
Selector labels for taskmanager
*/}}
{{- define "flink.taskmanagerSelectorLabels" -}}
app: {{ .Chart.Name }}
component: taskmanager
{{- end }}

{{/*
Full name of the release
*/}}
{{- define "flink.fullname" -}}
{{ .Release.Name }}-{{ .Chart.Name }}
{{- end }}
