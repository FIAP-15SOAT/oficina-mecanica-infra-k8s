# ADR 0002: Amazon EKS como distribuição gerenciada de Kubernetes

## Status

Aceito — 2026-09-07

## Contexto

O projeto precisa rodar Kubernetes na AWS (`terraform/eks.tf` provisiona `aws_eks_cluster` e um `aws_eks_node_group` gerenciado). A decisão é distinta de escolher AWS ou adotar Kubernetes: define como operar o cluster, ccomo um serviço gerenciado (EKS) ou como um cluster self-managed sobre instâncias EC2. A [documentação Kubernetes da API](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/docs/infra/kubernetes.md) explica os workloads consumidores.

## Decisão

Usar o **Amazon EKS** como distribuição gerenciada de Kubernetes, com o control plane operado pela AWS e um **Managed Node Group** (`aws_eks_node_group`) para os nós — em vez de um cluster self-managed instalado via `kubeadm` sobre instâncias EC2 provisionadas manualmente.

## Alternativas consideradas

### Cluster self-managed via `kubeadm` sobre EC2

Daria controle total sobre a versão exata do Kubernetes, os componentes do control plane e a topologia de rede interna do cluster, sem depender do roadmap de versões suportadas pela AWS. Descartada porque exigiria operar manualmente o control plane (etcd, API server, scheduler, controller manager) — incluindo upgrades de versão, backup do etcd e recuperação de desastre — todo o trabalho operacional que o EKS resolve nativamente. Para um projeto acadêmico com orçamento e tempo de laboratório limitados (ver ADR 0001 do `oficina-mecanica-infra-base`), esse esforço operacional não se justifica frente ao ganho de controle.

### `kops` ou `kubespray` (ferramentas de bootstrap de cluster self-managed)

Automatizariam parte do trabalho manual do `kubeadm`, tornando o self-managed mais viável operacionalmente. Descartadas pelo mesmo motivo fundamental: mesmo automatizado, o control plane ainda seria operado (patches de segurança, upgrades, disponibilidade do etcd) pelo próprio time, não pela AWS — o ganho de controle sobre a versão exata do Kubernetes não compensa o esforço operacional recorrente, especialmente considerando que a conta AWS Academy já teria dificuldade em prover as permissões IAM necessárias para esse nível de automação.

## Consequências

### Positivas

- **Operação do control plane delegada à AWS**: infraestrutura de disponibilidade e armazenamento do etcd são gerenciados pelo serviço; o time ainda escolhe a versão declarada e coordena upgrades e compatibilidade dos workloads.
- **Managed Node Group simplifica o ciclo de vida dos nós**: substituição de nós, integração com Auto Scaling Groups gerenciados pela AWS e rollout de novas AMIs seguem um fluxo padronizado, sem scripts próprios de bootstrap de nó.
- **Integração nativa com outros serviços AWS** (IAM para autenticação via `aws-iam-authenticator`/token, ECR, CloudWatch Logs) sem configuração adicional de plugins de terceiros.

### Negativas / Trade-offs

- **Custo do control plane gerenciado**: o EKS cobra uma taxa fixa por hora pelo control plane, independentemente do tamanho do cluster — um custo que um cluster self-managed sobre EC2 puro não teria isoladamente (ainda que trocado pelo esforço operacional).
- **Menos controle sobre a versão exata e a configuração interna do control plane**: o projeto fica limitado às versões de Kubernetes que a AWS suporta para EKS e ao cronograma de disponibilidade delas, não podendo customizar livremente flags do `kube-apiserver` ou do `scheduler`.
- **Vínculo a um único provedor de nuvem para a camada de orquestração**: migrar para outro provedor exigiria trocar a camada de gerenciamento do control plane, não apenas realocar workloads.

### Riscos mitigados

- **Indisponibilidade do control plane por falha operacional do próprio time** (ex.: erro humano num upgrade de etcd): mitigado por delegar essa operação inteiramente à AWS.

## Referências

- `terraform/eks.tf` — definição do `aws_eks_cluster` e do `aws_eks_node_group`.
- [ADR 0001 — Suporte ao HPA da API e dimensionamento do Node Group](0001-suporte-a-hpa-e-dimensionamento-do-node-group.md)
- [`oficina-mecanica-infra-base` › ADR 0001 — Escolha da nuvem](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base/blob/main/docs/adr/0001-escolha-de-nuvem-e-infra-base.md)
