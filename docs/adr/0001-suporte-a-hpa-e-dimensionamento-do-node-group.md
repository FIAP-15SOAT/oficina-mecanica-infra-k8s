# ADR 0001: Suporte ao HPA da API e dimensionamento do Node Group em função dele

## Status

Aceito — 2026-09-07

## Contexto

A API (`oficina-mecanica-api`) aplica um [Horizontal Pod Autoscaler](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/k8s/05-api-hpa.yaml) com `minReplicas: 1`, `maxReplicas: 5`, CPU alvo 70% e memória alvo 80%. Essas métricas dependem do **Metrics Server** provisionado por este repositório (`k8s_metrics_server.tf`) quando `enable_metrics_server=true`, o default atual. O HPA e o Deployment pertencem ao CD da API.

Além de instalar o Metrics Server, o HPA impõe uma restrição sobre **como dimensionar o node group**: capacidade de CPU/memória e limite de pods/IPs precisam ser considerados juntos. No modelo de IP secundário do VPC CNI considerado nesta decisão, a fórmula `(nº de ENIs × (IPs por ENI − 1)) + 2` resulta nos valores abaixo; configurações como prefix delegation podem alterar esse limite:

- `t3.small` → 3 ENIs × (4 IPs − 1) + 2 = **11 pods por node**
- `t3.medium` → 3 ENIs × (6 IPs − 1) + 2 = **17 pods por node**

Com o node group fixado em **1 node** (`node_desired_size = node_min_size = node_max_size = 1`, restrição de orçamento do laboratório AWS Academy — ver ADR 0001 do `oficina-mecanica-infra-base`), um único `t3.small` (11 pods) já não comporta simultaneamente: os workloads de sistema do próprio EKS (`kube-proxy`, `aws-node`, `coredns`), o Metrics Server, o DaemonSet de um agente de observabilidade, **e** as até 5 réplicas que o HPA da API pode criar num pico de carga.

## Decisão

1. Instalar o **Metrics Server** neste repositório via Helm (`k8s_metrics_server.tf`, chart oficial, namespace `kube-system`, `atomic = true`), como pré-requisito de infraestrutura para o HPA da API funcionar — sem ele, o HPA não tem de onde ler métricas de CPU/memória e não escala.
2. Dimensionar o **tipo de instância do node group** como `t3.medium` (17 pods por node) em vez de `t3.small` (11 pods por node), especificamente para garantir capacidade de pods suficiente para acomodar o `maxReplicas: 5` do HPA da API somado aos workloads de sistema e ao DaemonSet de observabilidade — mesmo operando com um único node (`node_desired_size = 1`), restrição de custo do laboratório que não deixa margem para compensar a escolha de instância pequena com mais nodes.

## Alternativas consideradas

### Manter `node_instance_type = t3.small`

Era a configuração anterior. Descartada pelo limite de pods/IPs considerado para os workloads de sistema, Metrics Server, observabilidade e até cinco réplicas da API. O default atual em `variables.tf` é `t3.medium`; esse valor não comprova por si só que CPU, memória ou IPs disponíveis comportem qualquer carga.

### Aumentar `node_max_size` (mais nodes) em vez de trocar o tipo de instância

Escalar horizontalmente o node group (permitir 2+ nodes) resolveria a capacidade de pods sem trocar o tipo de instância. Descartada por custo: cada node adicional no laboratório AWS Academy consome uma fração maior do crédito disponível do que o incremento de `t3.small` para `t3.medium` na mesma contagem de nodes — trocar o tipo de instância, mantendo o node group fixo em 1, foi a opção mais barata para o mesmo ganho de capacidade de pods.

### Cluster Autoscaler (escalar nodes automaticamente, em vez de HPA escalar só pods)

Adicionaria uma camada de autoscaling de infraestrutura (nodes) complementar ao HPA (pods). Descartada nesta entrega: exigiria uma role IAM com permissões de `autoscaling` que a conta AWS Academy não permite criar (apenas roles pré-existentes do laboratório podem ser usadas), inviabilizando o componente no ambiente atual.

## Consequências

### Positivas

- **Pré-requisito do HPA sob IaC**: Metrics Server fornece a fonte de métricas quando habilitado e pronto. O tipo do node amplia a capacidade considerada, mas a operação do HPA e a suficiência de recursos exigem validação com o cluster/workloads; não são garantidas pela configuração isolada.
- **Decisão de dimensionamento auditável**: o cálculo de capacidade de pods (fórmula do VPC CNI) está documentado como comentário na própria variável Terraform (`node_instance_type`), então uma futura mudança no `maxReplicas` do HPA da API tem um lugar claro para verificar se o node group ainda comporta o novo teto.

### Negativas / Trade-offs

- **Custo por hora de `t3.medium` superior ao de `t3.small`**, consumindo mais crédito de laboratório — aceito porque a alternativa (`t3.small`) deixava o HPA sem capacidade real de escalar.
- **Acoplamento entre dois repositórios**: uma mudança no `maxReplicas` do HPA (`oficina-mecanica-api`) pode invalidar silenciosamente o dimensionamento do node group aqui, já que os dois valores não são validados automaticamente um contra o outro — depende de revisão manual ao alterar qualquer um dos lados.
- **Ainda sem margem para múltiplos DaemonSets adicionais**: o cálculo já considera o DaemonSet de observabilidade atual; adicionar outro DaemonSet exigiria refazer a conta e possivelmente rever o tipo de instância novamente.
- **Sem scaling automático de nodes ou redundância de workloads**: desired/min/max são 1 e não há Cluster Autoscaler. O HPA escala pods dentro dessa capacidade, mesmo que o node group possa usar subnets de duas AZs.

### Riscos mitigados

- **Pods do HPA presos em `Pending` por falta de capacidade de IP no node**, justamente durante picos de carga — mitigado pelo dimensionamento de `t3.medium` com margem calculada para o `maxReplicas: 5` atual mais os workloads de sistema.
- **HPA sem fonte de métricas**: mitigado pela instalação do Metrics Server como parte da infraestrutura provisionada por este repositório, não deixada como pré-requisito manual.

## Referências

- [`oficina-mecanica-api` — Kubernetes e HPA](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/docs/infra/kubernetes.md)
- [`oficina-mecanica-api` › k8s/05-api-hpa.yaml](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/k8s/05-api-hpa.yaml)
- [`oficina-mecanica-infra-base` › ADR 0001 — Escolha da nuvem e infra base (restrição de orçamento e node group fixo em 1)](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base/blob/main/docs/adr/0001-escolha-de-nuvem-e-infra-base.md)
- `terraform/variables.tf` (comentário de `node_instance_type` com o cálculo de capacidade do VPC CNI), `terraform/k8s_metrics_server.tf`.
