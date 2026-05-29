{{- define "app.commonLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/part-of: opensre-observability
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
meta.helm.sh/release-name: {{ .root.Release.Name }}
meta.helm.sh/release-namespace: {{ .root.Release.Namespace }}
{{- end -}}

{{- define "app.dsn" -}}
postgres://{{ .Values.postgres.user }}:{{ .Values.postgres.password }}@postgres:5432/{{ .Values.postgres.database }}?sslmode=disable
{{- end -}}
