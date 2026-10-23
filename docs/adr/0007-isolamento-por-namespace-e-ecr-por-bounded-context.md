# ADR 0007: Namespace por serviço e namespace de plataforma

## Status

Aceito — 2026-10-23 (substitui [ADR 0006](0006-namespace-unico-compartilhado.md))

## Contexto

Na Fase 3 (ADR 0006), a solução contava com uma única aplicação (`work-order`) rodando no cluster EKS, e todos os manifests — Deployment da API, HPA, MailHog e Datadog Agent — compartilhavam o namespace `oficina`, sendo aplicados pelo pipeline de CD da própria API.

Na Fase 4, o sistema é decomposto em quatro microsserviços independentes (`work-order`, `identity`, `billing` e `inventory`), cada um com seu próprio repositório, pipeline de CD, ConfigMap, Secret de credenciais de banco e Job de migração. Manter todos os serviços e componentes compartilhados em um único namespace misturaria Secrets de bancos distintos no mesmo escopo e manteria componentes de plataforma (Datadog Agent e MailHog) acoplados ao deploy de um serviço específico.

## Decisão

Substituir o namespace único por **isolamento por namespace gerado a partir do mapa `local.services`** (`terraform/locals.tf` e `terraform/k8s_namespace.tf`), além de um **namespace dedicado `platform`** para os componentes compartilhados do cluster:

1. **Namespaces de serviço (`work-order`, `identity`, `billing`, `inventory`)**: criados via `for_each` a partir das chaves de `local.services`, todos com as labels `app.kubernetes.io/part-of = oficina-mecanica` e `managed-by = terraform`. O namespace legado `oficina` é mantido temporariamente em `local.namespaces` apenas durante a transição até a migração do `work-order` (C-12).
2. **Namespace `platform` e manifests versionados (`k8s/platform/`)**: o Datadog Agent (`DaemonSet`, `ServiceAccount`, `ClusterRole`, `ClusterRoleBinding` e `Service` `datadog-agent` na porta OTLP HTTP `4318`, com imagem fixada em `gcr.io/datadoghq/agent:7.83.1`) e o MailHog (`Deployment` com imagem fixada em `mailhog/mailhog:v1.0.1`, `Service` ClusterIP `mailhog` nas portas `1025`/`8025` e `Service` NodePort `mailhog-smtp` no NodePort `31025`) passam a pertencer a este repositório e rodar no namespace `platform`.
3. **Aplicação pelo CD da plataforma (`platform-apply`)**: um job dedicado no `.github/workflows/cd.yml`, executado após o `terraform apply`, valida o secret `DD_API_KEY`, cria/atualiza o Secret `datadog-secret` no namespace `platform` via stdin (`kubectl create secret generic ... --dry-run=client -o yaml | kubectl apply -f -`) sem gravar a chave em arquivo, artifact ou state do Terraform, aplica `k8s/platform/` e aguarda o rollout do DaemonSet e do Deployment.

## Alternativas consideradas

### Manter um único namespace compartilhado (`oficina`) para os quatro serviços

Descartada porque os quatro microsserviços passariam a compartilhar o mesmo escopo de nomes para ConfigMaps, Secrets e Services, permitindo que um pod de um bounded context lesse acidentalmente o Secret de banco de dados de outro contexto e dificultando a identificação de recursos por domínio.

### Implantar o Datadog Agent via Helm chart oficial

Descartada porque o chart oficial habilita por padrão recursos adicionais (como o Cluster Agent e mutating webhooks) que exigem permissões e componentes extras desnecessários para a topologia de 2 nós do laboratório, enquanto o manifesto enxuto validado na Fase 3 já entrega coleta OTLP HTTP (`4318`), APM e logs em containerd com consumo mínimo de memória e CPU.

### Declarar Datadog Agent e MailHog como recursos Terraform (`kubernetes_manifest` ou recursos tipados)

Descartada porque `kubernetes_manifest` exige conectividade com a API do cluster já durante o `terraform plan` (que falha quando o cluster ainda não existe no bootstrap de uma sessão nova), e converter o DaemonSet completo com RBAC e volumes para blocos HCL tornaria a manutenção mais verbosa do que manifests YAML padrão aplicados pelo `kubectl` no job `platform-apply`.

### Manter Datadog Agent e MailHog no CD do `work-order-service`

Descartada porque ambos são componentes de plataforma compartilhados pelos quatro microsserviços e pelas funções Lambda: acoplá-los ao pipeline de um único serviço impediria que `identity`, `billing` e `inventory` emitissem telemetria ou utilizassem SMTP antes do deploy do `work-order`.

## Consequências

### Positivas

- **Isolamento de escopo por bounded context**: cada serviço gerencia seus próprios Secrets, ConfigMaps, Deployments, Services e Jobs de migração dentro do seu namespace (`work-order`, `identity`, `billing`, `inventory`).
- **Dono único para observabilidade e SMTP**: o `infra-k8s` provisiona e garante a saúde do Datadog Agent (`http://datadog-agent.platform.svc.cluster.local:4318`) e do MailHog antes do deploy de qualquer microsserviço.
- **`DD_API_KEY` fora do state do Terraform e do repositório**: a chave do Datadog é injetada exclusivamente em memória via stdin pelo runner do CD com máscara nos logs.

### Negativas / Trade-offs

- **Dois passos no pipeline de CD do `infra-k8s`**: o workflow de CD executa primeiro o job `terraform-k8s-base` e em seguida o job `platform-apply` com `kubectl`.
- **Coexistência temporária do namespace `oficina`**: mantido até que a alteração C-12 conclua a migração dos manifests do `work-order` para o namespace `work-order`.

### Riscos mitigados

- **Vazamento de `DD_API_KEY` em arquivo `.tfstate` no S3 ou artefato de CI/CD**: mitigado pela criação do `datadog-secret` diretamente via pipe no `kubectl apply -f -` e pela validação prévia que falha explicitamente caso o secret não esteja configurado.
- **Conflito de dois DaemonSets do Datadog Agent nos mesmos nós**: mitigado pela desativação de `ENABLE_TELEMETRY_COLLECTION` no repositório do `work-order` ao ativar o Agent no namespace `platform`.

## Referências

- [ADR 0006 — Namespace único compartilhado (substituído)](0006-namespace-unico-compartilhado.md)
- `terraform/locals.tf`, `terraform/k8s_namespace.tf`, `k8s/platform/` e `.github/workflows/cd.yml`.
