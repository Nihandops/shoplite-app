{{/* Common labels. Usage: include "shoplite.labels" (dict "root" . "component" "web") */}}
{{- define "shoplite.labels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/part-of: shoplite
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
app.kubernetes.io/version: {{ .root.Values.image.tag | quote }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
shoplite/environment: {{ .root.Values.environment }}
{{- end -}}

{{- define "shoplite.selector" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/* Image reference for our own images. Usage: include "shoplite.image" (dict "root" . "repo" .Values.web.repository) */}}
{{- define "shoplite.image" -}}
{{- if .root.Values.image.registry -}}
{{ printf "%s/%s:%s" .root.Values.image.registry .repo .root.Values.image.tag }}
{{- else -}}
{{ printf "%s:%s" .repo .root.Values.image.tag }}
{{- end -}}
{{- end -}}

{{/* Env shared by catalog-api and order-worker */}}
{{- define "shoplite.appEnv" -}}
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.db.existingSecret }}
      key: username
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.db.existingSecret }}
      key: password
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "k8s.namespace.name={{ .Release.Namespace }},k8s.pod.name=$(POD_NAME)"
{{- end -}}
