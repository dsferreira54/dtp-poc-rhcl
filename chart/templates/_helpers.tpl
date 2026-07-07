{{/*
URLs OIDC para IAM externo — .Values.rhbk.<app>.externalIam

enabled: false → endpoints do Keycloak embarcado (realm rhcl); parameters ignorados.
enabled: true  → authorizationEndpoint, tokenEndpoint e issuerURL vão para os AuthPolicies.
  No bloco jwt o CRD aceita só issuerUrl OU jwksUrl: usa issuerURL dos parameters;
  jwksURL só entra se issuerURL estiver vazio (IAM sem URL de issuer).

Usage: include "rhcl.externalIam.issuerURL" (dict "root" . "app" "helloWorldApp")
*/}}
{{- define "rhcl.externalIam.issuerURL" -}}
{{- $root := .root -}}
{{- $app := .app -}}
{{- $appCfg := default dict (index $root.Values.rhbk $app) -}}
{{- $iam := default dict $appCfg.externalIam -}}
{{- $params := default dict $iam.parameters -}}
{{- if and $iam.enabled $params.issuerURL -}}
{{- $params.issuerURL -}}
{{- else -}}
https://{{ $root.Values.namespaces.rhbk }}.{{ $root.Values.ingressDomain }}/realms/rhcl
{{- end -}}
{{- end -}}

{{- define "rhcl.externalIam.authorizationEndpoint" -}}
{{- $root := .root -}}
{{- $app := .app -}}
{{- $appCfg := default dict (index $root.Values.rhbk $app) -}}
{{- $iam := default dict $appCfg.externalIam -}}
{{- $params := default dict $iam.parameters -}}
{{- if and $iam.enabled $params.authorizationEndpoint -}}
{{- $params.authorizationEndpoint -}}
{{- else -}}
https://{{ $root.Values.namespaces.rhbk }}.{{ $root.Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/auth
{{- end -}}
{{- end -}}

{{- define "rhcl.externalIam.tokenEndpoint" -}}
{{- $root := .root -}}
{{- $app := .app -}}
{{- $appCfg := default dict (index $root.Values.rhbk $app) -}}
{{- $iam := default dict $appCfg.externalIam -}}
{{- $params := default dict $iam.parameters -}}
{{- if and $iam.enabled $params.tokenEndpoint -}}
{{- $params.tokenEndpoint -}}
{{- else -}}
https://{{ $root.Values.namespaces.rhbk }}.{{ $root.Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/token
{{- end -}}
{{- end -}}

{{- define "rhcl.externalIam.jwksURL" -}}
{{- $app := .app -}}
{{- $root := .root -}}
{{- $appCfg := default dict (index $root.Values.rhbk $app) -}}
{{- $iam := default dict $appCfg.externalIam -}}
{{- $params := default dict $iam.parameters -}}
{{- if and $iam.enabled $params.jwksURL (not $params.issuerURL) -}}
{{- $params.jwksURL -}}
{{- end -}}
{{- end -}}

{{- define "rhcl.externalIam.authRedirectURL" -}}
{{- $root := .root -}}
{{- $app := .app -}}
{{- $clientId := index $root.Values.rhbk $app "clientId" -}}
{{- $host := .host | default (printf "hello-world-app.%s" $root.Values.gwapiDomain) -}}
{{- include "rhcl.externalIam.authorizationEndpoint" (dict "root" $root "app" $app) -}}?client_id={{ $clientId }}&redirect_uri=http%3A%2F%2F{{ $host }}%2Fauth%2Fcallback&response_type=code&scope=openid
{{- end -}}
