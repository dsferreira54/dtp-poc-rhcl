{{/*
Keycloak realm base URL (OIDC issuer default for this PoC).
*/}}
{{- define "rhcl.keycloak.oidcBaseUrl" -}}
https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl
{{- end -}}

{{/*
OIDC issuer URL — externalIAM.parameters.issuer when enabled, else Keycloak realm.
*/}}
{{- define "rhcl.oidc.issuerUrl" -}}
{{- if .Values.externalIAM.enabled -}}
{{ .Values.externalIAM.parameters.issuer }}
{{- else -}}
{{- include "rhcl.keycloak.oidcBaseUrl" . -}}
{{- end -}}
{{- end -}}

{{/*
JWKS URL — externalIAM.parameters.jwks when enabled.
AuthPolicy jwt block accepts jwksUrl OR issuerUrl, not both.
*/}}
{{- define "rhcl.oidc.jwksUrl" -}}
{{- if .Values.externalIAM.enabled -}}
{{ .Values.externalIAM.parameters.jwks }}
{{- else -}}
{{- include "rhcl.keycloak.oidcBaseUrl" . -}}/protocol/openid-connect/certs
{{- end -}}
{{- end -}}

{{/*
Authorization endpoint — externalIAM.parameters.authorize when enabled, else Keycloak /auth.
*/}}
{{- define "rhcl.oidc.authorizeUrl" -}}
{{- if .Values.externalIAM.enabled -}}
{{ .Values.externalIAM.parameters.authorize }}
{{- else -}}
{{- include "rhcl.keycloak.oidcBaseUrl" . -}}/protocol/openid-connect/auth
{{- end -}}
{{- end -}}

{{/*
Token endpoint — externalIAM.parameters.accessToken when enabled, else Keycloak /token.
*/}}
{{- define "rhcl.oidc.accessTokenUrl" -}}
{{- if .Values.externalIAM.enabled -}}
{{ .Values.externalIAM.parameters.accessToken }}
{{- else -}}
{{- include "rhcl.keycloak.oidcBaseUrl" . -}}/protocol/openid-connect/token
{{- end -}}
{{- end -}}

{{/*
Full browser redirect to start login (authorization code flow).
*/}}
{{- define "rhcl.oidc.loginRedirectUrl" -}}
{{- $authorize := include "rhcl.oidc.authorizeUrl" . -}}
{{- printf "%s?client_id=%s&redirect_uri=http%%3A%%2F%%2Fhello-world-app.%s%%2Fauth%%2Fcallback&response_type=code&scope=openid" $authorize .Values.rhbk.helloWorldApp.clientId .Values.gwapiDomain -}}
{{- end -}}
