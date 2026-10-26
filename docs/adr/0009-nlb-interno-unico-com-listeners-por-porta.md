# ADR 0009: NLB interno com listener por serviço e listener SMTP

## Status

Aceito — 2026-10-23

## Contexto

Na Fase 3, o Network Load Balancer interno (`nlb-oficina-mecanica`, ver [ADR 0003 do API Gateway](https://github.com/FIAP-15SOAT/oficina-mecanica-api-gateway/blob/main/docs/adr/0003-integracao-privada-com-o-eks.md)) possuía apenas um listener TCP na porta `80` encaminhando ao Target Group `tg-oficina-mecanica-work-order` no NodePort `30080`.

Na Fase 4, o API Gateway precisa rotear requisições HTTP para quatro microsserviços distintos (`work-order`, `identity`, `billing` e `inventory`) através do VPC Link, e as funções AWS Lambda na VPC (bem como serviços fora do cluster) precisam enviar e-mails de notificação ao MailHog hospedado no namespace `platform` do cluster EKS.

## Decisão

Manter **um único NLB interno** (`nlb-oficina-mecanica`) e provisionar **múltiplos listeners e target groups orientados pelo mapa `local.services`**, acrescidos de um listener dedicado ao SMTP do MailHog (`terraform/nlb.tf` e `terraform/locals.tf`):

1. **Listeners e Target Groups HTTP por serviço (`for_each = local.services`)**:
   - `work-order`: listener TCP `80` → target group `tg-oficina-mecanica-work-order` (`instance` mode, `preserve_client_ip = false`) → NodePort `30080`
   - `identity`: listener TCP `8081` → target group `tg-oficina-mecanica-identity` (`instance` mode, `preserve_client_ip = false`) → NodePort `30081`
   - `billing`: listener TCP `8082` → target group `tg-oficina-mecanica-billing` (`instance` mode, `preserve_client_ip = false`) → NodePort `30082`
   - `inventory`: listener TCP `8083` → target group `tg-oficina-mecanica-inventory` (`instance` mode, `preserve_client_ip = false`) → NodePort `30083`
   - Todos os quatro Target Groups usam health check HTTP em `/api/health/ready` (`traffic-port`, intervalo de 10s, limiares 2/2, matcher `200-399`), são anexados ao Auto Scaling Group do Node Group via `aws_autoscaling_attachment` e têm sua porta NodePort liberada no Security Group do cluster apenas para o CIDR da VPC (`10.0.0.0/16`).
2. **Listener e Target Group TCP para o SMTP do MailHog**:
   - Listener TCP `1025` → target group `tg-oficina-mecanica-smtp` (`instance` mode, `preserve_client_ip = false`, health check TCP em `traffic-port`) → NodePort `31025` (exposto pelo Service `mailhog-smtp` no namespace `platform`), com regra de entrada correspondente no Security Group do cluster a partir do CIDR da VPC.
3. **Outputs em mapa (`terraform/outputs.tf`)**:
   - Exportar `service_listener_arns`, `service_listener_ports` (`contexto → porta TCP do listener`), `nlb_dns_name` e `smtp_listener_port`.
   - O alias `api_nlb_listener_arn` (`service_listener_arns["work-order"]`) existiu só enquanto o `oficina-mecanica-api-gateway` lia um único listener; saiu quando o Gateway passou a ler os mapas.

## Alternativas consideradas

### Publicar também `ecr_repository_urls` e `service_node_ports` nos outputs

Descartada porque nenhum repositório consome esses outputs via Remote State: os workflows de CD dos microsserviços já recebem o nome do repositório ECR por Variable (`ECR_REPOSITORY`) e o NodePort é fixado no manifesto do Service Kubernetes de cada repositório.

### Um NLB interno separado para cada microsserviço

Criaria quatro (ou cinco, contando o SMTP) Network Load Balancers nas subnets privadas. Descartada por custo, tempo de provisionamento e consumo de IPs privados nas subnets: cada NLB tem cobrança fixa por hora na AWS e leva minutos para provisionar, enquanto múltiplos listeners em um único NLB não têm custo adicional de balanceador e atendem perfeitamente às integrações `AWS_PROXY` do HTTP API Gateway (que referenciam o ARN do listener de destino).

### Ingress Controller (ALB Ingress / NGINX Ingress) com roteamento por path dentro do cluster

Colocaria um proxy L7 dentro do cluster atrás de um único listener `80` do NLB. Descartada porque o HTTP API Gateway já realiza o roteamento por path e método na borda (associando cada rota ao listener correspondente via VPC Link), tornando redundante manter e operar mais um componente L7 (com seus próprios pods e consumo de memória) dentro do cluster de 2 nós.

### Expor o MailHog por um único Service `NodePort` com as portas `1025` e `8025`

Descartada porque um Service do tipo `NodePort` exige alocar um NodePort para todas as portas declaradas nele, o que abriria uma porta aleatória para a interface web HTTP (`8025`) nos nós; separar em um Service `ClusterIP` (`mailhog`, portas `1025` e `8025`) e um Service `NodePort` (`mailhog-smtp`, apenas porta `1025` no NodePort fixo `31025`) expõe exclusivamente o SMTP no NLB.

## Consequências

### Positivas

- **Custo mínimo de balanceamento**: um único NLB interno atende os quatro microsserviços HTTP e o SMTP do MailHog.
- **Isolamento de health check por serviço**: se um microsserviço ainda não foi implantado ou estiver indisponível, apenas o seu Target Group fica sem alvos saudáveis, sem afetar o roteamento dos demais listeners.
- **Compatibilidade retroativa imediata**: o listener `80` preservou o caminho do `work-order` e do Gateway durante a migração para os mapas.

### Negativas / Trade-offs

- **Portas reservadas estaticamente em `local.services`**: cada serviço deve configurar seu Service Kubernetes `NodePort` exatamente com a porta atribuída no mapa (`30080` a `30083`), e o API Gateway consome `service_listener_arns` e `service_listener_ports`.

### Riscos mitigados

- **Exposição desnecessária de portas nos nós**: cada NodePort (`30080`–`30083` e `31025`) é liberado individualmente no Security Group do cluster apenas para o bloco CIDR da VPC.

## Referências

- [ADR 0003 do API Gateway — Integração privada com o EKS via VPC Link e NLB interno](https://github.com/FIAP-15SOAT/oficina-mecanica-api-gateway/blob/main/docs/adr/0003-integracao-privada-com-o-eks.md)
- `terraform/locals.tf`, `terraform/nlb.tf`, `terraform/outputs.tf` e `k8s/platform/mailhog-service.yaml`.
