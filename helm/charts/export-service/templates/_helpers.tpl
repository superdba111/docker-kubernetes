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
      name: {{ .Release.Name }}-db
      key: DB_PASSWORD
{{- end }}
