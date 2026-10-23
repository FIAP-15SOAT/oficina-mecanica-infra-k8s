# ADR 0008: Dois nós `t3.medium` fixos no Node Group

## Status

Aceito — 2026-10-23 (substitui [ADR 0001](0001-suporte-a-hpa-e-dimensionamento-do-node-group.md))

## Contexto

Na Fase 3 (ADR 0001), o cluster EKS operava com apenas **1 nó `t3.medium`** (`node_desired_size = node_min_size = node_max_size = 1`), que pelo limite do VPC CNI (`3 ENIs × (6 IPs − 1) + 2`) suporta no máximo **17 pods**. Esse teto comportava os pods de sistema (`aws-node`, `kube-proxy`, `coredns`, `metrics-server`), o Datadog Agent, o MailHog e uma única API (`work-order`).

Na Fase 4, o cluster passa a hospedar simultaneamente quatro microsserviços (`work-order`, `identity`, `billing` e `inventory`), seus respectivos Jobs de migração Prisma/SQL no momento do deploy, o DaemonSet do Datadog Agent (1 pod por nó), o MailHog e os componentes de sistema em `kube-system`. Somados, esses workloads ultrapassam com facilidade o limite de 17 pods e os 4 GiB de RAM de uma única instância `t3.medium`, além de deixar o HPA sem folga para escalar réplicas sob carga.

## Decisão

Manter o Metrics Server instalado via Helm (`k8s_metrics_server.tf`) e dimensionar o Node Group gerenciado do EKS (`aws_eks_node_group.eks_node_group`) com **2 nós `t3.medium` fixos** (`node_desired_size = 2`, `node_min_size = 2`, `node_max_size = 2`):

- Capacidade combinada de **34 pods** (`2 × 17` IPs secundários nas ENIs do VPC CNI), **4 vCPUs** e **8 GiB de memória RAM**.
- Distribuição dos nós nas duas subnets privadas (`10.0.10.0/24` e `10.0.11.0/24`), provendo folga para os pods de sistema, 2 réplicas do DaemonSet do Datadog Agent, MailHog, os 4 serviços de domínio, Jobs transitórios de migração e escalonamento horizontal pelo HPA.

## Alternativas consideradas

### Manter 1 nó `t3.medium`

Descartada porque o limite de 17 pods por instância `t3.medium` no VPC CNI seria atingido ou excedido assim que os quatro microsserviços, o Datadog Agent, o MailHog, os pods de `kube-system` e os Jobs de migração coexistissem, deixando novos pods presos em `Pending` (`Too many pods`).

### Usar 1 nó `t3.large` (2 vCPUs, 8 GiB RAM, até 35 pods)

Embora uma única instância `t3.large` amplie o limite de IPs por ENI (`3 × (12 − 1) + 2 = 35 pods`) e tenha a mesma memória total (8 GiB), ela oferece metade da capacidade de vCPU agregada em comparação a dois `t3.medium` (2 vCPUs contra 4 vCPUs no total) e concentra todos os serviços em uma única instância EC2 e uma única zona de disponibilidade pelo mesmo custo por hora.

### Usar Cluster Autoscaler com `min_size = 1` e `max_size = 3`

Descartada porque o Cluster Autoscaler exige permissões IAM de `autoscaling:SetDesiredCapacity` e `autoscaling:TerminateInstanceInAutoScalingGroup` associadas via IRSA ou política dedicada, recursos cuja criação/configuração de trust policy é bloqueada pelas restrições da conta AWS Academy Learner Lab.

## Consequências

### Positivas

- **Capacidade de pods e recursos duplicada (34 pods, 4 vCPUs, 8 GiB RAM)**: comporta com folga os quatro microsserviços, Jobs de migração e componentes de plataforma sem esbarrar no teto de IPs por ENI do VPC CNI.
- **Previsibilidade operacional**: sem dependência de Cluster Autoscaler, toda a capacidade do cluster já está pronta desde o término do `terraform apply`.

### Negativas / Trade-offs

- **Dobro do consumo horário de EC2 para os nós do EKS** em relação à Fase 3 (duas instâncias `t3.medium` em vez de uma), mitigado pelo desligamento/destruição do ambiente ao término de cada sessão de laboratório.
- **Mais 1 pod de DaemonSet por nó adicionado**: `aws-node`, `kube-proxy` e `datadog-agent` rodam em cada nó (consumindo 3 slots de pod do segundo nó), restando ainda 14 slots líquidos adicionais.

### Riscos mitigados

- **Falha de agendamento (`Pending` por exaustão de IPs ou memória) no deploy simultâneo dos 4 serviços**: mitigado pela ampliação para 34 slots de pods e 8 GiB de RAM.

## Referências

- [ADR 0001 — Suporte ao HPA da API e dimensionamento do Node Group (substituído)](0001-suporte-a-hpa-e-dimensionamento-do-node-group.md)
- [ADR 0010 — Credenciais AWS dos pods pela `LabRole` como role do nó](0010-launch-template-com-imdsv2-e-labrole-nos-nos.md)
- `terraform/eks.tf`, `terraform/variables.tf` e `terraform/terraform.tfvars`.
