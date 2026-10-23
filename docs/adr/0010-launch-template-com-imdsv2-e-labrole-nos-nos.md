# ADR 0010: Credenciais AWS dos pods pela `LabRole` como role do nó com Launch Template IMDSv2

## Status

Aceito — 2026-10-23

## Contexto

Na Fase 3, o Node Group do EKS utilizava uma role específica de nó (`LabEksNodeRole`, parametrizada por conta na variável de repositório `EKS_NODE_ROLE_NAME`), suficiente para o kubelet e o VPC CNI registrarem o nó no cluster, mas **sem permissões de aplicação** para publicar ou consumir mensagens no Amazon SNS e no Amazon SQS. Além disso, sem um Launch Template explícito, a configuração padrão do IMDSv2 na AMI otimizada do EKS utiliza `http_put_response_hop_limit = 1`, o que faz com que pacotes de requisição de token originados de dentro de um pod (que sofrem decremento de TTL ao atravessar a interface de rede virtual do container para o host) sejam descartados pelo serviço de metadados da instância (`169.254.169.254`).

Na Fase 4, os quatro microsserviços no EKS publicam eventos de domínio no SNS e consomem filas SQS da coreografia Saga. No AWS Academy Learner Lab, não é permitido criar novas roles IAM, editar políticas de confiança (trust policies) para habilitar **IRSA (IAM Roles for Service Accounts)** nem configurar **EKS Pod Identity**. Tampouco são permitidas credenciais AWS estáticas (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) em ConfigMaps, Secrets ou variáveis dos serviços.

## Decisão

1. **Usar a role pré-existente `LabRole` (`data "aws_iam_role" "lab_role" { name = "LabRole" }`) como `node_role_arn` do Node Group**, removendo a variável de role de nó do Terraform e a variável de repositório `EKS_NODE_ROLE_NAME` (já que `LabRole` possui nome fixo em todas as contas do AWS Academy e inclui permissões para EKS worker node, ECR, SNS e SQS).
2. **Provisionar um Launch Template (`aws_launch_template.eks_nodes`) para o Node Group** com:
   - `metadata_options` exigindo IMDSv2 (`http_endpoint = "enabled"`, `http_tokens = "required"`) e **`http_put_response_hop_limit = 2`**, permitindo que os containers dos pods alcancem o IMDS do nó (2 saltos: container → nó → IMDS) e obtenham credenciais temporárias renovadas automaticamente pela cadeia padrão do AWS SDK v3;
   - `instance_type = var.node_instance_type` declarado exclusivamente no Launch Template (removendo `instance_types` do recurso `aws_eks_node_group`, pois a API do EKS não aceita ambos simultaneamente);
   - `vpc_security_group_ids` contendo explicitamente **os dois Security Groups**: o Security Group gerenciado do cluster (`aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id`) e o Security Group de identidade dos nós exportado pelo `infra-base` (`data.terraform_remote_state.aws_base.outputs.eks_nodes_security_group_id`).

## Alternativas consideradas

### IRSA (IAM Roles for Service Accounts) ou EKS Pod Identity

Seria o padrão de produção recomendado na AWS para conceder menor privilégio por ServiceAccount de cada microsserviço. Descartada porque o AWS Academy Learner Lab bloqueia `iam:CreateOpenIDConnectProvider`, `iam:CreateRole`, `iam:UpdateAssumeRolePolicy` e a associação de Pod Identity para `pods.eks.amazonaws.com`.

### Manter `LabEksNodeRole` nos nós

Descartada porque a política anexada à `LabEksNodeRole` pelo laboratório concede apenas as políticas gerenciadas de worker node do EKS (`AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`), negando chamadas `sns:Publish`, `sqs:ReceiveMessage`, `sqs:SendMessage` e `sqs:DeleteMessage` feitas pelos pods.

### Injetar credenciais de sessão do laboratório (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`) em Kubernetes Secrets

Descartada como solução primária porque credenciais de sessão copiadas do painel do AWS Academy são chaves estáticas atreladas à sessão humana que expiram ou exigem reexecução dos pipelines de CD dos quatro microsserviços a cada reinício do laboratório, além de expor tokens de sessão em Secrets do cluster. A obtenção via IMDSv2 + `LabRole` renova as credenciais automaticamente na instância EC2 sem nenhuma chave estática nos pods.

## Consequências

### Positivas

- **Zero credenciais AWS estáticas nos serviços**: os pods utilizam o default credential provider chain do AWS SDK v3 via IMDSv2 sem nenhuma variável `AWS_ACCESS_KEY_ID` ou Secret AWS.
- **Menos configuração manual por conta do laboratório**: como `LabRole` tem nome constante em toda conta do AWS Academy, a variável `EKS_NODE_ROLE_NAME` deixa de existir no GitHub Actions e no Terraform.
- **Identidade de rede dos nós garantida desde o boot**: o Launch Template anexa o Security Group de identidade dos nós junto ao Security Group do cluster.

### Negativas / Trade-offs

- **Compartilhamento da mesma role IAM (`LabRole`) entre todos os pods do cluster**: na ausência de IRSA/Pod Identity no laboratório, todos os containers que alcançam o IMDS herdam as permissões amplas da `LabRole`.
- **Obrigatoriedade de listar o Security Group do cluster no Launch Template**: ao definir `vpc_security_group_ids` no Launch Template, o EKS deixa de anexar o Security Group do cluster automaticamente; por isso os dois Security Groups devem permanecer declarados juntos no template.

### Riscos mitigados

- **Bloqueio de chamadas ao IMDSv2 a partir de containers (`hop_limit = 1`)**: mitigado pela configuração explícita de `http_put_response_hop_limit = 2` no Launch Template.
- **Quebra de comunicação entre plano de controle e nós ou falha nos NodePorts do NLB**: mitigado pela inclusão explícita de `cluster_security_group_id` em `vpc_security_group_ids`.

## Referências

- `terraform/eks.tf` e `terraform/variables.tf`.
- [`oficina-mecanica-infra-base` › ADR 0004 — Security group de identidade dos nós do EKS](https://github.com/FIAP-15SOAT/oficina-mecanica-infra-base/blob/main/docs/adr/0004-security-group-de-identidade-dos-nos-do-eks.md)
- [ADR 0008 — Dois nós `t3.medium` fixos no Node Group](0008-escalonamento-do-node-group-para-2-nos-t3-medium.md)
