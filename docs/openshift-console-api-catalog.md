# API Catalog do Red Hat Connectivity Link na console do OpenShift

Este guia explica, em linguagem simples, o que é a funcionalidade de **API Catalog / API Key Management** do RHCL, como ela funciona e quais passos seguir para implementá-la. O exemplo usa a API de demonstração **external-app** deste repositório.

> **Nota:** esta funcionalidade é *Technology Preview* no RHCL 1.4. Consulte a [documentação oficial](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.4/html/developing_apis_with_the_web_console/rhcl-api-management).

---

## O que essa feature faz?

Imagine que sua empresa tem várias APIs internas no OpenShift e outros times precisam consumi-las. Hoje, isso costuma virar e-mail pedindo credencial, planilha de keys ou processo manual.

O **API Catalog** resolve isso oferecendo um “catálogo de APIs” dentro da console do OpenShift (menu **Connectivity Link**):

- **Quem publica a API** (API owner) registra a API no catálogo, define como ela aparece e escolhe se o acesso é automático ou precisa de aprovação.
- **Quem consome a API** (API consumer) encontra a API no catálogo, solicita uma API key e, após aprovação, usa a credencial para chamar a API.
- **O gateway** (via `AuthPolicy`) só deixa passar quem apresentar uma key válida e aprovada.

Em resumo: **descoberta + solicitação + aprovação + autenticação**, tudo integrado à console e ao cluster.

---

## Como funciona (visão geral)

Existem três papéis principais:

| Papel | O que faz | Onde atua na console |
|-------|-----------|----------------------|
| **API owner** | Publica a API, configura aprovação, aprova ou rejeita pedidos | Connectivity Link → **API Products** e **API Key Approvals** |
| **API consumer** | Descobre APIs, solicita key, recupera credencial aprovada | Connectivity Link API Catalog → **My API Keys** |
| **Todos** | Podem navegar o catálogo para descobrir APIs | Connectivity Link → **API Products** |

### Fluxo simplificado

```
1. Owner expõe a API (HTTPRoute) e protege com AuthPolicy (API key)
2. Owner publica a API como APIProduct no catálogo
3. Consumer solicita acesso (cria APIKey no namespace dele)
4. Controller cria APIKeyRequest no namespace do owner (recurso sombra — não editar manualmente)
5. Owner aprova via console ou APIKeyApproval
6. Controller ativa a key; Consumer chama a API com o header correto
7. AuthPolicy valida a key no gateway
```

### Recursos Kubernetes envolvidos

| Recurso | Quem cria | Para quê |
|---------|-----------|------------|
| `HTTPRoute` | Owner / plataforma | Roteia tráfego da API |
| `AuthPolicy` | Owner / plataforma | Exige API key nas requisições |
| `PlanPolicy` | Owner / plataforma | Define tiers/planos (ex.: limites de uso) |
| `APIProduct` | Owner | Publica a API no catálogo |
| `Secret` + `APIKey` | Consumer | Consumer guarda a key e solicita acesso |
| `APIKeyRequest` | **Controller** (automático) | Pedido visível para o owner aprovar |
| `APIKeyApproval` | Owner / admin | Aprova ou rejeita o pedido |

**Importante:** não crie nem edite `APIKeyRequest` manualmente.

---

## Pré-requisitos

Antes de configurar o API Catalog, o cluster precisa ter:

1. **OpenShift 4.20+** (requisito da feature na console)
2. **Red Hat Connectivity Link (RHCL) 1.4** instalado (`rhcl-operator`)
3. **Plugin da console** do Connectivity Link habilitado
4. **Gateway API** com um `Gateway` e `HTTPRoute` apontando para sua API
5. **Developer Portal habilitado** no CR `Kuadrant`:

   ```yaml
   spec:
     components:
       developerPortal:
         enabled: true
   ```

   Sem isso, o controller que processa `APIKey` e `APIKeyRequest` **não sobe** e o fluxo de catálogo não funciona.

6. **RBAC** com as roles pré-definidas do RHCL:
   - `api-owner` — no namespace do owner
   - `api-consumer` — no namespace de cada time consumidor
   - `api-catalog-browser` — leitura do catálogo (cluster-wide)
   - `api-admin` — administração cluster-wide (opcional)

Documentação oficial: [API management](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.4/html/developing_apis_with_the_web_console/rhcl-api-management)

---

## Passo a passo de implementação

O exemplo deste repositório usa:

- **API owner:** namespace `example-apps` (API `external-app`)
- **API consumer:** namespace `external-app-consumers`
- **Hostname:** `external-app.<gwapiDomain>` (ex.: `external-app.gwapi.ocp.acme.com`)

Os manifestos de referência estão em:

- `chart/templates/7-example-apps/2-external-app/external-app-api-catalog.yaml`
- `chart/templates/4-rhcl/rhcl.yaml` (Developer Portal)

### Passo 1 — Expor a API (HTTPRoute)

A API precisa estar acessível via Gateway API. No PoC, o `HTTPRoute` `external-app` roteia tráfego para um backend externo (`httpbin.org`).

Sem rota, não há produto para publicar.

**Exemplo — API in-cluster (padrão):**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: minha-api
  namespace: example-apps
spec:
  parentRefs:
    - name: main-gateway
      namespace: istio-ingress
  hostnames:
    - minha-api.gwapi.ocp.acme.com
  rules:
    - backendRefs:
        - name: minha-api-service
          port: 8080
```

**Exemplo — external-app (backend externo via Istio mesh):**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: external-app
  namespace: example-apps
spec:
  parentRefs:
    - name: main-gateway
      namespace: istio-ingress
  hostnames:
    - external-app.gwapi.ocp.acme.com
  rules:
    - filters:
        - type: URLRewrite
          urlRewrite:
            hostname: httpbin.org
      backendRefs:
        - group: networking.istio.io
          kind: Hostname
          name: httpbin.org
          port: 443
```

```bash
oc apply -f httproute.yaml
```

### Passo 2 — Proteger a API com AuthPolicy (API key)

Crie um `AuthPolicy` apontando para o `HTTPRoute`. Ele define **como** a key deve ser enviada e **quais secrets** o gateway aceita.

Pontos-chave:

- O seletor de labels (`matchLabels.app`) deve corresponder ao **nome do `APIProduct`** (no PoC: `app: external-app`)
- Use `allNamespaces: true` para que keys aprovadas pelo controller (criadas em `kuadrant-system`) sejam reconhecidas
- No PoC, o header exigido é: `Authorization: APIKEY <sua-key>`

**Exemplo:**

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: external-app
  namespace: example-apps
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: external-app
  rules:
    authentication:
      api-key-users:
        apiKey:
          allNamespaces: true
          selector:
            matchLabels:
              app: external-app   # deve bater com o nome do APIProduct
        credentials:
          authorizationHeader:
            prefix: APIKEY
```

```bash
oc apply -f authpolicy.yaml
oc get authpolicy external-app -n example-apps   # status Enforced = OK
```

### Passo 3 — Definir planos com PlanPolicy (opcional, mas recomendado)

O `PlanPolicy` define tiers (ex.: `default`, `gold`, `silver`) com limites de uso. Quando o consumer solicita uma key, ele escolhe um **planTier** — esse tier precisa existir no `PlanPolicy` ligado ao mesmo `HTTPRoute`.

No PoC há um único tier `default` com limite de 1000 requisições/dia.

**Exemplo:**

```yaml
apiVersion: extensions.kuadrant.io/v1alpha1
kind: PlanPolicy
metadata:
  name: external-app
  namespace: example-apps
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: external-app
  plans:
    - tier: default
      predicate: |
        has(auth.identity) && auth.identity.metadata.annotations["secret.kuadrant.io/plan-id"] == "default"
      limits:
        daily: 1000
```

```bash
oc apply -f planpolicy.yaml
```

### Passo 4 — Publicar no catálogo (APIProduct)

Crie o `APIProduct` referenciando o `HTTPRoute`:

- `displayName` — nome amigável no catálogo
- `publishStatus: Published` — torna visível no catálogo
- `approvalMode: manual` — exige aprovação do owner (use `automatic` para aprovação imediata)
- `documentation`, `contact`, `tags` — ajudam o consumer a se orientar sozinho

Também é possível criar o produto pela console: **Connectivity Link → API Products → Create**.

**Exemplo:**

```yaml
apiVersion: devportal.kuadrant.io/v1alpha1
kind: APIProduct
metadata:
  name: external-app          # nome usado no matchLabels.app do AuthPolicy
  namespace: example-apps
spec:
  displayName: External App API
  description: |
    API de demonstração exposta via Connectivity Link.
    Requer API key para acesso.
  version: v1
  approvalMode: manual
  publishStatus: Published
  tags:
    - external
    - example
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: external-app
  contact:
    team: Platform Team
    email: platform@example.com
  documentation:
    docsURL: https://httpbin.org/
```

```bash
oc apply -f apiproduct.yaml
oc get apiproduct external-app -n example-apps   # deve mostrar status Ready
```

### Passo 5 — Configurar permissões (RBAC)

Separe namespaces de owner e consumer:

| Namespace | Role binding | ClusterRole |
|-----------|--------------|-------------|
| `example-apps` | `api-owner` | publicar API, ver pedidos, aprovar |
| `external-app-consumers` | `api-consumer` | criar `APIKey` e `Secret` |

Cada time consumidor deve ter **seu próprio namespace** com binding `api-consumer`. Keys e secrets ficam isolados por time.

**Exemplo:**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: external-app-consumers
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-owner-example-apps
  namespace: example-apps
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: api-owner
subjects:
  - kind: Group
    name: meu-time-api-owner        # substituir pelo grupo LDAP/OAuth do owner
    apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-consumer-external-app-consumers
  namespace: external-app-consumers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: api-consumer
subjects:
  - kind: Group
    name: meu-time-consumidor       # substituir pelo grupo LDAP/OAuth do consumer
    apiGroup: rbac.authorization.k8s.io
```

```bash
oc apply -f rbac.yaml
```

### Passo 6 — Consumer solicita acesso

O consumidor (via console ou YAML):

1. Cria um `Secret` no namespace dele com a chave `api_key`
2. Cria um `APIKey` referenciando o `APIProduct` e o `Secret`

Na console: **Connectivity Link API Catalog → My API Keys → Request**.

O controller cria automaticamente um `APIKeyRequest` no namespace do owner. O pedido fica **Pending** se `approvalMode` for `manual`.

**Exemplo:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minha-api-key
  namespace: external-app-consumers
type: Opaque
stringData:
  api_key: minha-chave-secreta-aqui    # valor escolhido pelo consumer
---
apiVersion: devportal.kuadrant.io/v1alpha1
kind: APIKey
metadata:
  name: pedido-time-mobile
  namespace: external-app-consumers
spec:
  apiProductRef:
    name: external-app
    namespace: example-apps            # namespace do owner
  planTier: default                    # deve existir no PlanPolicy
  secretRef:
    name: minha-api-key
  requestedBy:
    userId: joao.silva
    email: joao.silva@empresa.com
  useCase: Integração do app mobile com a API external-app
```

```bash
oc apply -f apikey-request.yaml -n external-app-consumers
oc get apikey -n external-app-consumers          # condition Pending = aguardando aprovação
oc get apikeyrequest -n example-apps             # recurso sombra criado pelo controller
```

### Passo 7 — Owner aprova ou rejeita

Via console: **Connectivity Link API Catalog → API Key Approvals**.

Ou via YAML (`APIKeyApproval`), referenciando o `APIKeyRequest` pelo nome (obtido com `oc get apikeyrequest -n example-apps`).

Após aprovação, o controller:

- Atualiza o status do `APIKey` para **Approved**
- Cria o secret de enforcement em `kuadrant-system` (inacessível ao consumer)
- A key passa a ser aceita pelo `AuthPolicy`

**Exemplo — aprovar:**

```yaml
apiVersion: devportal.kuadrant.io/v1alpha1
kind: APIKeyApproval
metadata:
  name: aprovar-pedido-time-mobile
  namespace: example-apps
spec:
  apiKeyRequestRef:
    name: external-app-consumers-pedido-time-mobile-a1b2c3d4   # nome do APIKeyRequest
  approved: true
  reviewedBy: maria.admin@empresa.com
  reviewedAt: "2026-07-03T12:00:00Z"
  reason: ValidUseCase
  message: Aprovado para integração do app mobile
```

**Exemplo — rejeitar:**

```yaml
apiVersion: devportal.kuadrant.io/v1alpha1
kind: APIKeyApproval
metadata:
  name: rejeitar-pedido-time-mobile
  namespace: example-apps
spec:
  apiKeyRequestRef:
    name: external-app-consumers-pedido-time-mobile-a1b2c3d4
  approved: false
  reviewedBy: maria.admin@empresa.com
  reviewedAt: "2026-07-03T12:00:00Z"
  reason: InsufficientInformation
  message: Descreva melhor o caso de uso antes de solicitar novamente
```

```bash
oc apply -f apikey-approval.yaml
oc get apikey pedido-time-mobile -n external-app-consumers   # condition Approved = OK
```

### Passo 8 — Validar com curl

Com port-forward ou acesso ao gateway:

```bash
# Sem key → 401
curl -H "Host: external-app.gwapi.ocp.acme.com" \
  http://<gateway>/get

# Com key aprovada → 200
curl -H "Host: external-app.gwapi.ocp.acme.com" \
  -H "Authorization: APIKEY <sua-key-aprovada>" \
  http://<gateway>/get
```

No PoC local, use `./access.sh` para configurar `/etc/hosts` e port-forward do gateway.

---

## O que cada namespace faz neste PoC

| Namespace | Função |
|-----------|--------|
| `example-apps` | Dono da API: `HTTPRoute`, `AuthPolicy`, `PlanPolicy`, `APIProduct`, aprovações |
| `external-app-consumers` | Time consumidor: `Secret` e `APIKey` de quem quer usar a API |
| `kuadrant-system` | Operador RHCL, Authorino, developer-portal-controller, secrets de enforcement |

O namespace `external-app-consumers` **não roda a aplicação** — ele só representa “outro time pedindo acesso”.

---

## Usando pela console do OpenShift

### Para quem publica (API owner)

1. Acesse **Connectivity Link → API Products**
2. Confirme que sua API aparece (ou crie/edite o `APIProduct`)
3. Em pedidos pendentes, vá em **Connectivity Link API Catalog → API Key Approvals**
4. Revise use case, tier e aprove ou rejeite

### Para quem consome (API consumer)

1. Navegue o catálogo em **Connectivity Link → API Products**
2. Vá em **Connectivity Link API Catalog → My API Keys**
3. Solicite acesso à API desejada, informando tier e use case
4. Aguarde aprovação (se manual)
5. Recupere a key na mesma tela (**Show API Key**)
6. Use no header `Authorization: APIKEY <key>` nas chamadas à API

---

## Checklist de aceite

- [ ] API aparece publicada no Connectivity Link API Catalog
- [ ] Chamada sem key retorna **401**
- [ ] Consumer consegue solicitar key (`APIKey` em Pending)
- [ ] Owner vê o pedido em API Key Approvals
- [ ] Após aprovação, chamada com key retorna **200**
- [ ] Header de autenticação corresponde ao configurado no `AuthPolicy` (no PoC: `APIKEY`)

---

## Referências neste repositório

| Arquivo | Conteúdo |
|---------|----------|
| `chart/templates/4-rhcl/rhcl.yaml` | RHCL + Developer Portal habilitado |
| `chart/templates/7-example-apps/2-external-app/external-app.yaml` | HTTPRoute da API |
| `chart/templates/7-example-apps/2-external-app/external-app-api-catalog.yaml` | AuthPolicy, PlanPolicy, APIProduct, RBAC |
| `chart/values.yaml` | Namespaces e domínios configuráveis |
| `access.sh` | Acesso local via port-forward |

## Referências oficiais Red Hat

- [API management (console)](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.4/html/developing_apis_with_the_web_console/rhcl-api-management)
- [Gateway policies (AuthPolicy)](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.4/html/deploying_red_hat_connectivity_link/rhcl-config-deploy-gateway-policies)
