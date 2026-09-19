{{- define "app.name" -}}{{ .Release.Name }}{{- end -}}
{{- define "app.labels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: argocd
{{- end -}}
