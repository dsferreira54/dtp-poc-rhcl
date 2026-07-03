# dtp-poc-rhcl

Repositório de referência para a **DTP** montar e validar o ambiente de **Proof of Concept (PoC)** com **Red Hat Connectivity Link (RHCL)** em OpenShift.

Este projeto não é um produto final — serve como ponto de partida e modelo de implantação GitOps que a equipe DTP pode adaptar às necessidades, domínios e políticas do próprio cluster.

## Objetivo

Demonstrar uma stack completa de conectividade e governança de APIs em OpenShift, incluindo:

- Entrada de tráfego com **Gateway API** (Istio e Envoy)
- Políticas de conectividade com **RHCL** (operador Kuadrant)
- Autenticação com **Red Hat Build of Keycloak (RHBK)**
- Observabilidade com **Grafana** e dashboards pré-configurados
- Aplicações de exemplo para exercitar rotas, OIDC e rate limiting

A ideia é que a DTP use este repositório como **referência arquitetural e operacional** ao construir o ambiente de PoC dela, ajustando valores, domínios, pools de IP e integrações conforme o contexto local.

## Pré-requisitos

- Cluster **OpenShift** com acesso de administrador (`oc`)
- **OpenShift GitOps** (Argo CD) já instalado e operacional no cluster
- Conectividade com o **Red Hat Operator Catalog** (`redhat-operators`)
- Rede de máquinas (`machineNetwork`) com IPs disponíveis para **MetalLB** (quando habilitado)

## Estrutura do repositório

```
dtp-poc-rhcl/
└── chart/                 # Helm chart implantado pelo Argo CD
    ├── Chart.yaml
    ├── values.yaml        # Valores padrão (domínios, versões, MetalLB, etc.)
    ├── files/dashboards/  # Dashboards Grafana (Grafana Operator)
    └── templates/
        ├── 1-metallb/           # Operador e pool de IPs MetalLB
        ├── 2-istio/               # Service Mesh (Istio, Kiali, OSSM Console)
        ├── 3-gateway-api/         # Gateways Istio e Envoy (Gateway API)
        ├── 4-rhcl/                # RHCL/Kuadrant e plugin do console
        ├── 5-monitoring/          # Monitoramento e Grafana
        ├── 6-rhbk/                # Keycloak (RHBK), Postgres e realm
        └── 7-example-apps/        # Apps de exemplo e ferramentas de troubleshooting
```

Os templates usam **sync waves** do Argo CD para garantir a ordem de instalação entre operadores, CRs e workloads.

> **Nota:** o arquivo `deploy.sh` presente no repositório é de **uso exclusivo de David Ferreira** para bootstrap do ambiente de referência. **A DTP não deve utilizá-lo.** A implantação no cluster da DTP deve ser feita criando manualmente a **Application** do Argo CD, conforme a seção abaixo.

## Componentes implantados

| Camada | Componentes |
|--------|-------------|
| Rede / LB | MetalLB (opcional via `metallb.enabled`) |
| Service mesh | Istio, Istio CNI, Kiali, OSSM Console |
| Gateway | Gateway API com controladores Istio e Envoy |
| Conectividade | RHCL (Kuadrant), plugin no console OpenShift |
| Identidade | RHBK (Keycloak), PostgreSQL, import de realm |
| Observabilidade | User Workload Monitoring, Grafana Operator, dashboards |
| Exemplos | Hello World (HTTPRoute, OIDC, RateLimit), app externa, netshoot |

## Deploy (DTP)

A DTP deve criar a **Application** do Argo CD manualmente, apontando para o repositório (fork, mirror ou clone interno) e sobrescrevendo via `helm.parameters` os valores do `chart/values.yaml` conforme o ambiente.

Os parâmetros mais comuns a ajustar:

| Parâmetro Helm | Descrição |
|----------------|-----------|
| `gwapiDomain` | Domínio base para recursos Gateway API |
| `ingressDomain` | Domínio de ingress do cluster OpenShift |
| `rhclVersion` | Versão do RHCL/Kuadrant |
| `metallb.enabled` | Habilitar ou desabilitar MetalLB (`true` / `false`) |
| `metallb.ipAddressPool.addresses[0]` | Faixa de IPs para o pool MetalLB |
| `monitoring.userWorkload.enabled` | User Workload Monitoring |
| `monitoring.rhclMetrics.enabled` | Métricas RHCL no monitoramento |

Qualquer outro valor definido em `chart/values.yaml` também pode ser sobrescrito com a mesma convenção de nome (ex.: `namespaces.rhbk`, `namespaces.exampleApps`).

### Application de referência

Substitua os placeholders (`<...>`) pelos valores do ambiente da DTP antes de aplicar:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dtp-poc-rhcl
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: <URL_DO_REPOSITORIO_DA_DTP>
    targetRevision: <BRANCH_OU_TAG>
    path: chart
    helm:
      parameters:
        - name: gwapiDomain
          value: "<DOMINIO_GWAPI>"
        - name: ingressDomain
          value: "<DOMINIO_INGRESS>"
        - name: rhclVersion
          value: "1.4.1"
        - name: metallb.enabled
          value: "false"
        - name: metallb.ipAddressPool.addresses[0]
          value: "<FAIXA_DE_IPS_METALLB>"
        - name: monitoring.userWorkload.enabled
          value: "false"
        - name: monitoring.rhclMetrics.enabled
          value: "true"
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ApplyOutOfSyncOnly=true
```

Exemplo com valores preenchidos:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dtp-poc-rhcl
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/dtp-org/dtp-poc-rhcl
    targetRevision: main
    path: chart
    helm:
      parameters:
        - name: gwapiDomain
          value: "gwapi.ocp.dtp.example.com"
        - name: ingressDomain
          value: "apps.ocp.dtp.example.com"
        - name: rhclVersion
          value: "1.4.1"
        - name: metallb.enabled
          value: "false"
        - name: metallb.ipAddressPool.addresses[0]
          value: "192.168.1.240-192.168.1.250"
  destination:
    server: https://kubernetes.default.svc
    namespace: dtp-poc-rhcl
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
```

Aplique a Application no cluster:

```bash
oc apply -f application.yaml
```

### Acompanhar a sincronização

```bash
oc get application dtp-poc-rhcl -n openshift-gitops
oc get pods -A | grep -E 'istio|kuadrant|keycloak|grafana|metallb'
```

## Personalização para o ambiente DTP

Ao adaptar este repositório para o PoC da DTP, considere:

- **Fork ou mirror** — manter uma cópia sob controle da DTP e apontar a Application Argo CD para o repositório interno
- **Domínios e certificados** — alinhar `gwapiDomain` e `ingressDomain` com DNS e TLS do ambiente
- **MetalLB** — validar a faixa de IPs na rede do cluster; desabilitar com `metallb.enabled: false` se outro mecanismo de LoadBalancer for usado
- **RHBK / realm** — revisar credenciais, realm import e integração OIDC das apps de exemplo
- **Dashboards** — os JSON em `chart/files/dashboards/` podem ser estendidos para métricas específicas da DTP

## Observações

- Este repositório foi pensado para **ambientes de PoC**, não para produção direta
- Secrets, senhas padrão e permissões devem ser revisados antes de qualquer uso além de laboratório
- A ordem de instalação e as versões dos operadores refletem o cenário de referência; ajuste conforme a versão do OpenShift e o catálogo disponível no cluster da DTP

## Licença e suporte

Material de referência interno para a PoC da DTP. Para dúvidas sobre RHCL, consulte a documentação oficial da Red Hat e o time de arquitetura responsável pelo PoC.
