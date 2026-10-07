{{- define "export-service.env" -}}
{{- range $k, $v := .Values.env }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
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
