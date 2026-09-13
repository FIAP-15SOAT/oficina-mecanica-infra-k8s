# ADR 0006: Namespace único compartilhado para todos os recursos da aplicação

## Status

Aceito — 2026-09-07

## Contexto

`terraform/k8s_namespace.tf` cria o namespace `oficina`, com labels `app.kubernetes.io/part-of` e `managed-by: terraform`. API, MailHog, HPA e Datadog são aplicados pelo repositório da API nesse namespace. O Metrics Server provisionado aqui fica em **`kube-system`**, não em `oficina`. Não há separação da aplicação por ambiente ou domínio de negócio.

## Decisão

Manter um **único namespace compartilhado** (`oficina`) para todos os recursos da aplicação neste cluster, em vez de namespaces separados por ambiente ou por domínio funcional.

## Alternativas consideradas

### Um namespace por ambiente (`oficina-staging`, `oficina-prod`)

Isolaria ambientes diferentes dentro do mesmo cluster físico, permitindo testar mudanças em `staging` sem afetar `prod`. Descartada porque o projeto já opera com um único ambiente `prod-simulated` (ver ADR 0001 do `oficina-mecanica-infra-base`) — não há hoje um segundo ambiente rodando simultaneamente que justificasse a separação, e criar um cluster ou namespace adicional só para simular "staging" consumiria crédito de laboratório sem uso funcional real nesta fase do projeto.

### Um namespace por domínio de negócio (ex.: `oficina-auth`, `oficina-work-orders`)

Seguiria um padrão de separação por área de responsabilidade. Descartada porque a API é um **monólito modular**, implantado como um Deployment para seus domínios internos; não há unidade de deploy separada entre módulos como auth e work-orders. A Lambda de autenticação externa é um componente próprio fora do Kubernetes.

## Consequências

### Positivas

- **Configuração mínima**: um namespace só significa menos RBAC, menos `NetworkPolicy` (se algum dia adotadas) e menos superfície de configuração para manter sincronizada.
- **Coerente com a unidade de deploy da API**: o namespace agrupa seus workloads sem inventar deploys por módulo; componentes externos como Lambda e RDS mantêm seus próprios ciclos de vida.

### Negativas / Trade-offs

- **Sem isolamento de RBAC ou de rede por domínio**: qualquer recurso dentro do namespace `oficina` compartilha o mesmo espaço de nomes e, na ausência de `NetworkPolicy` customizada, a mesma superfície de alcance de rede interna — um comprometimento de um componente não fica isolado de outro por fronteira de namespace.
- **Sem separação de ambiente dentro do cluster**: uma mudança aplicada ao namespace único afeta imediatamente o único ambiente existente, sem uma réplica isolada para validar antes — o projeto depende inteiramente do pipeline de CI/CD (fmt/validate/plan antes do apply) como sua rede de segurança, não de isolamento de namespace.

### Riscos aceitos

- **Ausência de ambiente de staging isolado dentro do cluster**: aceito para o escopo e orçamento deste laboratório; uma futura expansão do projeto para múltiplos ambientes deveria reavaliar esta decisão.

## Referências

- `terraform/k8s_namespace.tf` — definição do namespace `oficina`.
- [`oficina-mecanica-api` — Arquitetura](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/docs/architecture.md)
- [`oficina-mecanica-infra-base` › ADR 0001 — Escolha da nuvem e infra base](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base/blob/main/docs/adr/0001-escolha-de-nuvem-e-infra-base.md)
