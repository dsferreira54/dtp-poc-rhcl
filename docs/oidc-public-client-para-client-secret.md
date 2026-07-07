# Como mudamos o login da app: de “sem senha” para “com senha”

Guia simples das alterações feitas no PoC **dtp-poc-rhcl**.  
Se você não é especialista em OIDC, comece pelo **Resumo** abaixo.

---

## Como ler os YAMLs neste guia

Cada bloco mostra o **objeto YAML completo** (não um recorte solto).  
As linhas que mudaram vêm marcadas com `# ← ...` no final:

| Marca | Significado |
|-------|-------------|
| `# ← NOVO` | Linha ou bloco que não existia antes |
| `# ← MUDOU` | Linha que existia com outro valor |
| `# ← REMOVIDO` | Objeto inteiro que saiu do projeto |

---

## Resumo (leia isto primeiro)

**O que tínhamos:** a app `hello-world-app` pedia login no Keycloak usando um modo “aberto” — só o **nome da aplicação** (`client_id`), **sem senha secreta**.

**O que queríamos:** o Keycloak passar a exigir também uma **senha secreta** (`client secret`) — como um app “fechado”, mais restrito.

**O problema:** não bastou marcar isso no Keycloak. A ferramenta automática de login do RHCL (`OIDCPolicy`) **não sabe enviar essa senha**. Tínhamos que **trocar a ferramenta automática por configuração manual**.

**Em uma frase:** mudamos **4 arquivos** — cadastro da senha no Keycloak, cofre da senha no gateway, e substituímos 1 bloco YAML grande por 3 blocos menores.

| O quê | Antes | Depois |
|-------|-------|--------|
| Senha no Keycloak | Não tinha | Tem (`client secret`) |
| Ferramenta de login | 1 arquivo `OIDCPolicy` (automático) | 3 recursos escritos à mão |
| Onde fica a senha | — | 2 “cofres” (Secrets) no cluster |
| App em si (Hello World) | Igual | Igual — **nada mudou na aplicação** |

---

## Analogia rápida

| Modo | Como funciona no dia a dia |
|------|----------------------------|
| **Public client** (antes) | Entrar num prédio só dizendo *“sou o João”* — sem crachá secreto |
| **Confidential client** (depois) | Entrar dizendo *“sou o João”* **e** mostrando um **crachá com senha** que só o porteiro (gateway) guarda |

A senha **nunca** vai para o navegador do usuário. Fica guardada no cluster, no gateway.

---

## Por que não deu só para mudar uma linha no Keycloak?

1. No Keycloak, trocamos `publicClient: true` → `false` e adicionamos a senha.
2. Com isso, o Keycloak passa a **recusar** quem tentar completar o login **sem** apresentar a senha.
3. A configuração antiga (`OIDCPolicy`) fazia o login **sem** enviar senha — e **não tem opção** para colocar senha.
4. Se tentássemos “consertar na mão”, o sistema **desfazia** a correção sozinho.

**Conclusão:** tivemos que **apagar** o `OIDCPolicy` e **escrever** as regras de login manualmente (AuthPolicies).

---

## Mudança 1 — Anotar nome e senha num lugar só

**Arquivo:** `chart/values.yaml`  
**Em português:** centraliza o nome e a senha da app para os outros arquivos referenciarem.

### Antes — arquivo completo

```yaml
gwapiDomain: gwapi.ocp.acme.com
ingressDomain: apps.ocp.acme.com
rhclVersion: 1.4.1
namespaces:
  exampleApps: example-apps
  externalAppConsumers: external-app-consumers
  rhbk: rhbk
monitoring:
  userWorkload:
    enabled: true
  rhclMetrics:
    enabled: true
metallb:
  enabled: true
  ipAddressPool:
    addresses:
      - 192.168.1.240-192.168.1.250
ingress:
  selfSigned:
    enabled: false
    jobNamespace: ingress-selfsigned
    secretNamespace: openshift-ingress
    secretName: cert-manager-ingress-cert
    certificateName: cert-manager-ingress-cert
    routerNamespace: openshift-ingress
    routerDeployment: router-default
    validityDays: 90
htpasswd:
  enabled: false
  jobNamespace: ingress-selfsigned
  username: demo
  passwordHash: "$2y$05$LafNcbjVdORYJGDqvQ99x.KJKiI9jz7sMEuz9lpAHMCK868d3cnaK"
  secretName: htpasswd-demo
  identityProviderName: htpasswd-demo
  clusterAdminBindingName: htpasswd-demo-cluster-admin
authorino:
  trustIngressCA:
    enabled: false
    ingressSecretNamespace: openshift-ingress
    ingressSecretName: router-certs-default
```

### Depois — arquivo completo (linhas destacadas)

```yaml
gwapiDomain: gwapi.ocp.acme.com
ingressDomain: apps.ocp.acme.com
rhclVersion: 1.4.1
namespaces:
  exampleApps: example-apps
  externalAppConsumers: external-app-consumers
  rhbk: rhbk
rhbk:                              # ← NOVO bloco inteiro
  helloWorldApp:                   # ← NOVO
    clientId: hello-world-app      # ← NOVO
    clientSecret: hello-world-app-secret  # ← NOVO
monitoring:
  userWorkload:
    enabled: true
  rhclMetrics:
    enabled: true
metallb:
  enabled: true
  ipAddressPool:
    addresses:
      - 192.168.1.240-192.168.1.250
ingress:
  selfSigned:
    enabled: false
    jobNamespace: ingress-selfsigned
    secretNamespace: openshift-ingress
    secretName: cert-manager-ingress-cert
    certificateName: cert-manager-ingress-cert
    routerNamespace: openshift-ingress
    routerDeployment: router-default
    validityDays: 90
htpasswd:
  enabled: false
  jobNamespace: ingress-selfsigned
  username: demo
  passwordHash: "$2y$05$LafNcbjVdORYJGDqvQ99x.KJKiI9jz7sMEuz9lpAHMCK868d3cnaK"
  secretName: htpasswd-demo
  identityProviderName: htpasswd-demo
  clusterAdminBindingName: htpasswd-demo-cluster-admin
authorino:
  trustIngressCA:
    enabled: false
    ingressSecretNamespace: openshift-ingress
    ingressSecretName: router-certs-default
```

**O que você precisa fazer:** definir um valor real para `clientSecret` em produção (não use o exemplo em ambiente real).

---

## Mudança 2 — Keycloak passa a exigir senha

**Arquivo:** `chart/templates/6-rhbk/3-realm-import.yaml`  
**Em português:** o cadastro da aplicação no Keycloak deixa de ser “aberto” e ganha senha, guardada num cofre separado.

### Antes — arquivo completo

```yaml
---
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: rhcl-realm
  namespace: {{ .Values.namespaces.rhbk }}
  annotations:
    argocd.argoproj.io/sync-wave: "25"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  keycloakCRName: keycloak
  realm:
    realm: rhcl
    enabled: true
    displayName: "RHCL PoC"
    sslRequired: none
    clients:
      - clientId: hello-world-app
        name: "Hello World App"
        enabled: true
        protocol: openid-connect
        publicClient: true
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        fullScopeAllowed: true
        redirectUris:
          - "*"
        webOrigins:
          - "*"
    users:
      - username: demo
        enabled: true
        emailVerified: true
        email: demo@example.com
        firstName: Demo
        lastName: User
        credentials:
          - type: password
            value: demo123
            temporary: false
```

### Depois — arquivo completo (linhas destacadas)

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: hello-world-app-keycloak-client
  namespace: {{ .Values.namespaces.rhbk }}
  annotations:
    argocd.argoproj.io/sync-wave: "24"
type: Opaque
stringData:
  clientSecret: {{ .Values.rhbk.helloWorldApp.clientSecret | quote }}
---
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: rhcl-realm
  namespace: {{ .Values.namespaces.rhbk }}
  annotations:
    argocd.argoproj.io/sync-wave: "25"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  keycloakCRName: keycloak
  placeholders:                    # ← NOVO bloco inteiro
    HELLO_WORLD_APP_CLIENT_SECRET:
      secret:
        name: hello-world-app-keycloak-client
        key: clientSecret
  realm:
    realm: rhcl
    enabled: true
    displayName: "RHCL PoC"
    sslRequired: none
    clients:
      - clientId: {{ .Values.rhbk.helloWorldApp.clientId | quote }}  # ← MUDOU (era fixo: hello-world-app)
        name: "Hello World App"
        enabled: true
        protocol: openid-connect
        publicClient: false        # ← MUDOU (era: true)
        secret: $(HELLO_WORLD_APP_CLIENT_SECRET)  # ← NOVO
        standardFlowEnabled: true
        directAccessGrantsEnabled: false
        fullScopeAllowed: true
        redirectUris:
          - http://hello-world-app.{{ .Values.gwapiDomain }}/auth/callback  # ← MUDOU (era: "*")
        webOrigins:
          - http://hello-world-app.{{ .Values.gwapiDomain }}  # ← MUDOU (era: "*")
    users:
      - username: demo
        enabled: true
        emailVerified: true
        email: demo@example.com
        firstName: Demo
        lastName: User
        credentials:
          - type: password
            value: demo123
            temporary: false
```

| O que mudou | Antes | Depois |
|-------------|-------|--------|
| Precisa de senha? | Não | Sim |
| Endereços aceitos | Qualquer (`*`) | Só o callback da app |
| Cofre da senha | Não existia | Secret novo no topo do arquivo |

> **Importante:** se o Keycloak **já estava rodando** com a config antiga, este arquivo sozinho **não atualiza** o cadastro. É preciso ajustar o client no console/API do Keycloak também.

---

## Mudança 3 — Cofre da senha para o gateway

**Arquivo novo:** `chart/templates/7-example-apps/1-hello-world-app/hello-world-oidc-secret.yaml`  
**Em português:** o gateway (Authorino) precisa da senha para falar com o Keycloak. Criamos um cofre **só para ele**.

### Antes

Arquivo **não existia** — o login automático não usava senha.

### Depois — arquivo completo (tudo é novo)

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: hello-world-app-oidc-client
  namespace: kuadrant-system        # ← NOVO — tem que ser kuadrant-system, não example-apps
  annotations:
    argocd.argoproj.io/sync-wave: "29"
type: Opaque
stringData:
  clientSecret: {{ .Values.rhbk.helloWorldApp.clientSecret | quote }}
  basicAuth: {{ printf "%s:%s" .Values.rhbk.helloWorldApp.clientId .Values.rhbk.helloWorldApp.clientSecret | b64enc | quote }}  # ← NOVO — senha formatada para HTTP Basic
```

**Detalhe fácil de errar:** o cofre **não pode** ficar no namespace da app (`example-apps`). Tem que ficar em `kuadrant-system`.

---

## Mudança 4 — Trocar o login automático pelo manual

**Arquivo:** `chart/templates/7-example-apps/1-hello-world-app/hello-world-app.yaml`  
**Em português:** removemos o “botão mágico” (`OIDCPolicy`) e colocamos as regras explicitamente.

> **Nota:** Deployment, Service, HTTPRoute principal e RateLimitPolicy **não mudaram**. Só a parte de autenticação.

### O que saiu — objeto completo removido

```yaml
---
apiVersion: extensions.kuadrant.io/v1alpha1
kind: OIDCPolicy                        # ← REMOVIDO — inteiro
metadata:
  name: hello-world-app
  namespace: {{ .Values.namespaces.exampleApps }}
  annotations:
    argocd.argoproj.io/sync-wave: "30"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: hello-world-app
  provider:
    issuerURL: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl
    clientID: hello-world-app
    authorizationEndpoint: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/auth
    tokenEndpoint: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/token
    redirectURI: http://hello-world-app.{{ .Values.gwapiDomain }}/auth/callback
  auth:
    tokenSource:
      cookie:
        name: jwt
```

Esse único objeto gerava, por baixo dos panos, a rota de callback e as regras de login — mas **sem suporte a client secret**.

### O que entrou — 3 objetos completos novos

**① Rota de retorno do login** (`HTTPRoute` callback):

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute                         # ← NOVO objeto inteiro
metadata:
  name: hello-world-app-callback
  namespace: {{ .Values.namespaces.exampleApps }}
  annotations:
    argocd.argoproj.io/sync-wave: "29"
spec:
  parentRefs:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: main-gateway
    namespace: istio-ingress
  hostnames:
  - hello-world-app.{{ .Values.gwapiDomain }}
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /auth/callback
```

**② Regra “usuário não logado → vai pro Keycloak”** (`AuthPolicy` da app):

```yaml
---
apiVersion: kuadrant.io/v1
kind: AuthPolicy                        # ← NOVO objeto inteiro
metadata:
  name: hello-world-app
  namespace: {{ .Values.namespaces.exampleApps }}
  annotations:
    argocd.argoproj.io/sync-wave: "30"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: hello-world-app
  overrides:
    strategy: merge
    rules:
      authentication:
        oidc:
          credentials:
            cookie:
              name: jwt
          jwt:
            issuerUrl: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl
          priority: 0
      response:
        unauthenticated:
          code: 302
          headers:
            location:
              value: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/auth?client_id={{ .Values.rhbk.helloWorldApp.clientId }}&redirect_uri=http%3A%2F%2Fhello-world-app.{{ .Values.gwapiDomain }}%2Fauth%2Fcallback&response_type=code&scope=openid
            set-cookie:
              expression: |
                "target=" + request.path + "; domain=hello-world-app.{{ .Values.gwapiDomain }}; HttpOnly; SameSite=Lax; Path=/; Max-Age=3600"
```

**③ Regra “voltou do Keycloak → pega o token COM senha”** (`AuthPolicy` callback) — **a parte mais importante**:

```yaml
---
apiVersion: kuadrant.io/v1
kind: AuthPolicy                        # ← NOVO objeto inteiro
metadata:
  name: hello-world-app-callback
  namespace: {{ .Values.namespaces.exampleApps }}
  annotations:
    argocd.argoproj.io/sync-wave: "30"
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: hello-world-app-callback
  overrides:
    strategy: merge
    rules:
      metadata:
        token:
          priority: 0
          when:
          - predicate: request.query.split("&").map(entry, entry.split("=")).filter(pair, pair[0] == "code").map(pair, pair[1]).size() > 0
          http:
            url: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/token
            method: POST
            contentType: application/x-www-form-urlencoded
            sharedSecretRef:          # ← NOVO — lê senha do cofre kuadrant-system
              name: hello-world-app-oidc-client
              key: basicAuth
            credentials:
              authorizationHeader:    # ← NOVO — envia senha no cabeçalho HTTP Basic
                prefix: "Basic "
            body:
              expression: |
                "code=" + request.query.split("&").map(entry, entry.split("=")).filter(pair, pair[0] == "code").map(pair, pair[1])[0] + "&grant_type=authorization_code&redirect_uri=http%3A%2F%2Fhello-world-app.{{ .Values.gwapiDomain }}%2Fauth%2Fcallback&client_id={{ .Values.rhbk.helloWorldApp.clientId }}"
      authorization:
        location:
          priority: 1
          opa:
            allValues: true
            rego: |
              cookies := { name: value | raw_cookies := input.request.headers.cookie; cookie_parts := split(raw_cookies, ";"); part := cookie_parts[_]; kv := split(trim(part, " "), "="); count(kv) == 2; name := trim(kv[0], " "); value := trim(kv[1], " ")}
              location := concat("", ["http://hello-world-app.{{ .Values.gwapiDomain }}", cookies.target]) { input.auth.metadata.token.id_token; cookies.target }
              location := "http://hello-world-app.{{ .Values.gwapiDomain }}" { input.auth.metadata.token.id_token; not cookies.target }
              location := "https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/auth?client_id={{ .Values.rhbk.helloWorldApp.clientId }}&redirect_uri=http%3A%2F%2Fhello-world-app.{{ .Values.gwapiDomain }}%2Fauth%2Fcallback&response_type=code&scope=openid" { not input.auth.metadata.token.id_token }
              allow = true
        deny:
          priority: 2
          opa:
            rego: allow = false
      response:
        unauthorized:
          code: 302
          headers:
            location:
              expression: auth.authorization.location.location
            set-cookie:
              expression: |
                "jwt=" + auth.metadata.token.id_token + "; domain=hello-world-app.{{ .Values.gwapiDomain }}; HttpOnly; SameSite=Lax; Path=/; Max-Age=3600"
```

### Comparação direta do que importa

| Etapa do login | Antes (automático) | Depois (manual) |
|----------------|-------------------|-----------------|
| Usuário abre a app | Redireciona pro Keycloak | Igual |
| Volta do Keycloak | Gateway pede token **sem senha** | Gateway pede token **com senha** (`sharedSecretRef` + `Basic`) |
| Quantos YAMLs você mantém | 1 (`OIDCPolicy`) | 3 (rota + 2 regras) |

---

## O que faz cada campo dos 3 YAMLs de login?

Cada bloco abaixo é o **YAML completo** do objeto. O comentário `# ← …` ao final de cada linha explica o que aquele campo faz (equivalente à seta no HTML).

Os três objetos rodam em sequência: ① abre a rota de retorno → ② protege a app → ③ completa o login com senha.

### ① HTTPRoute hello-world-app-callback

**Papel:** Abre /auth/callback — retorno do Keycloak.

```yaml
---  # ← Separador entre documentos YAML no mesmo arquivo.
apiVersion: gateway.networking.k8s.io/v1  # ← Versão da API Gateway — define uma rota HTTP no cluster.
kind: HTTPRoute  # ← Tipo do recurso: rota HTTP (URL) no gateway.
metadata:  # ← Início dos metadados (nome, namespace, anotações).
  name: hello-world-app-callback  # ← Nome desta rota — referenciado pelo AuthPolicy ③.
  namespace: {{ .Values.namespaces.exampleApps }}  # ← Namespace onde o objeto é criado (example-apps).
  annotations:  # ← Anotações extras (Argo CD, etc.).
    argocd.argoproj.io/sync-wave: "29"  # ← Ordem de deploy: 29 — antes das AuthPolicies (30).
spec:  # ← Início da especificação (comportamento da rota).
  parentRefs:  # ← Lista de Gateways que vão receber esta rota.
  - group: gateway.networking.k8s.io  # ← API group do Gateway pai.
    kind: Gateway  # ← Tipo do recurso pai: Gateway.
    name: main-gateway  # ← Nome do Gateway: main-gateway.
    namespace: istio-ingress  # ← Namespace do Gateway: istio-ingress.
  hostnames:  # ← Hostnames que esta rota atende.
  - hello-world-app.{{ .Values.gwapiDomain }}  # ← Domínio da app — mesmo host da Hello World.
  rules:  # ← Regras de roteamento (URLs aceitas).
  - matches:  # ← Condições de match — quando esta rota vale.
    - path:  # ← Match por caminho da URL.
        type: PathPrefix  # ← Tipo PathPrefix — casa prefixo do path.
        value: /auth/callback  # ← Só /auth/callback — exatamente o redirect_uri do OAuth.
```

### ② AuthPolicy hello-world-app

**Papel:** Protege a rota principal. Sem cookie jwt → Keycloak.

```yaml
---  # ← Separador YAML.
apiVersion: kuadrant.io/v1  # ← API do Kuadrant — regras de autenticação no gateway.
kind: AuthPolicy  # ← Recurso AuthPolicy — login escrito manualmente.
metadata:  # ← Metadados do objeto.
  name: hello-world-app  # ← Nome — mesmo da app; aplica na rota principal.
  namespace: {{ .Values.namespaces.exampleApps }}  # ← Namespace da app.
  annotations:  # ← Anotações Argo CD.
    argocd.argoproj.io/sync-wave: "30"  # ← Sync-wave 30 — depois da HTTPRoute callback.
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true  # ← Ignora dry-run se CRD ainda não existir no cluster.
spec:  # ← Especificação da política.
  targetRef:  # ← Referência ao recurso protegido.
    group: gateway.networking.k8s.io  # ← Group da HTTPRoute alvo.
    kind: HTTPRoute  # ← Tipo: HTTPRoute.
    name: hello-world-app  # ← Rota hello-world-app — tráfego normal da app (/).
  overrides:  # ← Como aplicar regras sobre as existentes.
    strategy: merge  # ← merge — junta sem apagar regras do gateway.
    rules:  # ← Bloco de regras Authorino.
      authentication:  # ← Seção de autenticação.
        oidc:  # ← Modo OIDC — validar login OpenID Connect.
          credentials:  # ← Onde buscar credenciais do usuário.
            cookie:  # ← Credencial via cookie HTTP.
              name: jwt  # ← Nome do cookie: jwt — prova de que logou.
          jwt:  # ← Validação JWT.
            issuerUrl: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl  # ← Emissor (Keycloak realm rhcl) — valida assinatura do token.
          priority: 0  # ← Prioridade 0 — roda primeiro neste bloco.
      response:  # ← O que fazer na resposta HTTP.
        unauthenticated:  # ← Quando o usuário NÃO está autenticado.
          code: 302  # ← HTTP 302 — redirect para outra URL.
          headers:  # ← Cabeçalhos da resposta de redirect.
            location:  # ← Header Location — para onde mandar o browser.
              value: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/auth?client_id={{ .Values.rhbk.helloWorldApp.clientId }}&redirect_uri=http%3A%2F%2Fhello-world-app.{{ .Values.gwapiDomain }}%2Fauth%2Fcallback&response_type=code&scope=openid  # ← URL de login Keycloak: client_id, redirect_uri, code, openid.
            set-cookie:  # ← Cookie auxiliar no redirect.
              expression: |  # ← Início de expressão multilinha (CEL).
                "target=" + request.path + "; domain=hello-world-app.{{ .Values.gwapiDomain }}; HttpOnly; SameSite=Lax; Path=/; Max-Age=3600"  # ← Grava target=<path> — lembra página original para voltar depois do login.
```

### ③ AuthPolicy hello-world-app-callback

**Papel:** Troca code por token com client secret; grava cookie jwt.

```yaml
---  # ← Separador YAML.
apiVersion: kuadrant.io/v1  # ← API Kuadrant v1.
kind: AuthPolicy  # ← AuthPolicy — regras manuais de auth.
metadata:  # ← Metadados.
  name: hello-world-app-callback  # ← Nome ligado à rota callback.
  namespace: {{ .Values.namespaces.exampleApps }}  # ← Namespace example-apps.
  annotations:  # ← Anotações.
    argocd.argoproj.io/sync-wave: "30"  # ← Sync-wave 30.
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true  # ← Skip dry-run se CRD ausente.
spec:  # ← Spec da política.
  targetRef:  # ← Aplica só na rota callback.
    group: gateway.networking.k8s.io  # ← Group HTTPRoute.
    kind: HTTPRoute  # ← Tipo HTTPRoute.
    name: hello-world-app-callback  # ← Rota hello-world-app-callback (/auth/callback).
  overrides:  # ← Overrides.
    strategy: merge  # ← Estratégia merge.
    rules:  # ← Regras Authorino.
      metadata:  # ← Busca metadados extras (chamada HTTP ao Keycloak).
        token:  # ← Regra token — troca authorization code por tokens.
          priority: 0  # ← Prioridade 0 — primeira etapa.
          when:  # ← Condição: só roda se…
          - predicate: request.query.split("&").map(entry, entry.split("=")).filter(pair, pair[0] == "code").map(pair, pair[1]).size() > 0  # ← …a URL tiver parâmetro code= (retorno OAuth OK).
          http:  # ← Chamada HTTP feita pelo gateway.
            url: https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/token  # ← Endpoint /token do Keycloak.
            method: POST  # ← POST — obrigatório no OAuth.
            contentType: application/x-www-form-urlencoded  # ← Corpo em form-urlencoded.
            sharedSecretRef:  # ← Referência ao Secret com a senha — kuadrant-system.
              name: hello-world-app-oidc-client  # ← Nome do Secret hello-world-app-oidc-client.
              key: basicAuth  # ← Chave basicAuth (clientId:secret em Base64).
            credentials:  # ← Como enviar credenciais na requisição.
              authorizationHeader:  # ← Header Authorization.
                prefix: "Basic "  # ← Prefixo Basic — aqui entra o client secret.
            body:  # ← Corpo do POST.
              expression: |  # ← Expressão CEL montando o form.
                "code=" + request.query.split("&").map(entry, entry.split("=")).filter(pair, pair[0] == "code").map(pair, pair[1])[0] + "&grant_type=authorization_code&redirect_uri=http%3A%2F%2Fhello-world-app.{{ .Values.gwapiDomain }}%2Fauth%2Fcallback&client_id={{ .Values.rhbk.helloWorldApp.clientId }}"  # ← Envia code, grant_type, redirect_uri e client_id ao Keycloak.
      authorization:  # ← Seção de autorização (decidir redirect).
        location:  # ← Regra location — calcula URL final.
          priority: 1  # ← Prioridade 1 — depois do token.
          opa:  # ← Motor OPA/Rego.
            allValues: true  # ← Retorna todos os valores calculados.
            rego: |  # ← Início do script Rego multilinha.
              cookies := { name: value | raw_cookies := input.request.headers.cookie; cookie_parts := split(raw_cookies, ";"); part := cookie_parts[_]; kv := split(trim(part, " "), "="); count(kv) == 2; name := trim(kv[0], " "); value := trim(kv[1], " ")}  # ← Parse dos cookies da requisição.
              location := concat("", ["http://hello-world-app.{{ .Values.gwapiDomain }}", cookies.target]) { input.auth.metadata.token.id_token; cookies.target }  # ← Se tem token + cookie target → volta à URL original.
              location := "http://hello-world-app.{{ .Values.gwapiDomain }}" { input.auth.metadata.token.id_token; not cookies.target }  # ← Se tem token sem target → vai à raiz da app.
              location := "https://{{ .Values.namespaces.rhbk }}.{{ .Values.ingressDomain }}/realms/rhcl/protocol/openid-connect/auth?client_id={{ .Values.rhbk.helloWorldApp.clientId }}&redirect_uri=http%3A%2F%2Fhello-world-app.{{ .Values.gwapiDomain }}%2Fauth%2Fcallback&response_type=code&scope=openid" { not input.auth.metadata.token.id_token }  # ← Se não tem token → manda de volta ao login Keycloak.
              allow = true  # ← Permite a regra (allow).
        deny:  # ← Regra de negação (fallback).
          priority: 2  # ← Prioridade 2.
          opa:  # ← OPA deny.
            rego: allow = false  # ← allow = false — força fluxo via response.unauthorized.
      response:  # ← Resposta HTTP ao browser.
        unauthorized:  # ← Dispara nesta fase (inclui sucesso com redirect).
          code: 302  # ← Redirect 302.
          headers:  # ← Headers.
            location:  # ← Location dinâmico.
              expression: auth.authorization.location.location  # ← Usa URL calculada pelo Rego acima.
            set-cookie:  # ← Cookie de sessão.
              expression: |  # ← Expressão do Set-Cookie.
                "jwt=" + auth.metadata.token.id_token + "; domain=hello-world-app.{{ .Values.gwapiDomain }}; HttpOnly; SameSite=Lax; Path=/; Max-Age=3600"  # ← Grava jwt=<id_token> — lido pelo AuthPolicy ② nas próximas visitas.
```

**Como se conectam:** o ② redireciona ao Keycloak com `redirect_uri=…/auth/callback`. O ① garante que essa URL existe. O ③ recebe o `code`, chama `/token` com `Authorization: Basic` (client secret) e grava o cookie `jwt`. Na próxima visita, o ② vê o cookie e libera a app.

---

## Ordem sugerida para fazer a mudança

1. Colocar `clientId` e `clientSecret` no `values.yaml`
2. Criar o arquivo do cofre do gateway (`hello-world-oidc-secret.yaml`)
3. Atualizar o Keycloak (`3-realm-import.yaml`)
4. No `hello-world-app.yaml`: **apagar** `OIDCPolicy`, **colar** os 3 recursos novos
5. Aplicar no cluster (Argo CD / Helm)
6. Se o Keycloak já existia: ajustar o client na mão
7. Testar: abrir a app no browser e logar com `demo` / `demo123`

---

## Como conferir se deu certo

- [ ] Não existe mais `OIDCPolicy` no cluster
- [ ] Existe Secret em `kuadrant-system` e em `rhbk`
- [ ] Abrir a app manda pro Keycloak
- [ ] Depois do login, a Hello World aparece

---

## Ver exatamente o que mudou no git

Para quem quiser o diff técnico completo:

```bash
git diff HEAD -- chart/values.yaml \
  chart/templates/6-rhbk/3-realm-import.yaml \
  chart/templates/7-example-apps/1-hello-world-app/
```

---

## Glossário mínimo

| Termo | Significado simples |
|-------|---------------------|
| **Public client** | Login só com nome da app, sem senha secreta |
| **Client secret** | Senha da aplicação perante o Keycloak |
| **OIDCPolicy** | Atalho automático de login do RHCL (não suporta senha na v1.4.1) |
| **AuthPolicy** | Regra de login escrita manualmente |
| **Secret** | Cofre de senhas no Kubernetes |
