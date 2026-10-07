{{- define "export-service.env" -}}
{{- range $k, $v := .Values.env }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
- name: DOWNLOAD_MODE
  value: {{ include "export-service.downloadMode" . | quote }}
- name: EXPORT_ENABLED_TENANTS
  value: {{ join "," .Values.exports.enabledTenants | quote }}
- name: DB_HOST
  value: {{ .Values.database.host | quote }}
- name: DB_NAME
  value: {{ .Values.database.name | quote }}
- name: DB_USER
  value: {{ .Values.database.user | quote }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-secrets
      key: DB_PASSWORD
- name: SENTRY_DSN
  valueFrom:
    secretKeyRef:
      name: {{ .Release.Name }}-secrets
      key: SENTRY_DSN
{{- end }}

{{- define "export-service.egress" -}}
- to:
    {{- range .Values.networkPolicy.egressToNamespaces }}
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: {{ . }}
    {{- end }}
{{- with .Values.networkPolicy.egressCidrs }}
- to:
    {{- range . }}
    - ipBlock:
        cidr: {{ . }}
    {{- end }}
  ports:
    - port: 5432
{{- end }}
{{- end }}


{{- define "export-service.downloadMode" -}}
{{- $mode := .Values.download.mode -}}
{{- if not (has $mode (list "stream" "presigned")) -}}
{{- fail (printf "download.mode must be stream or presigned, not %q" $mode) -}}
{{- end -}}
{{- if eq $mode "presigned" -}}
{{- $_ := required "download.issoApprovalRef is required for presigned downloads (review A4)" .Values.download.issoApprovalRef -}}
{{- end -}}
{{- $mode -}}
{{- end }}
