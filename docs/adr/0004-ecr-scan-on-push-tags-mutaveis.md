# ADR 0004: Amazon ECR por serviço com scan-on-push, tags mutáveis, force_delete e retenção de 20 imagens

## Status

Aceito — 2026-09-07 (atualizado em 2026-10-23 para múltiplos repositórios por serviço e `force_delete = true`)

## Contexto

`terraform/ecr.tf` provisiona os repositórios Amazon ECR dedicados às imagens de container dos quatro microsserviços da Fase 4 (`work-order`, `identity`, `billing` e `inventory`), gerados com `for_each = local.services` no formato `ecr-oficina-mecanica-<contexto>`. Cada repositório reúne varredura automática de vulnerabilidades no push (`scan_on_push = true`), criptografia AES-256, mutabilidade de tag (`image_tag_mutability = "MUTABLE"`), remoção forçada (`force_delete = true`) e uma lifecycle policy mantendo as últimas 20 imagens daquele serviço.

O pipeline de CD de cada microsserviço (`cd.yml`, job `build-push-image`) publica **duas tags por build**: `${ECR_REPOSITORY}:${COMMIT_SHA}`, associada ao commit, e `${ECR_REPOSITORY}:latest`, atualizada a cada build. Uma nova execução do mesmo commit, inclusive via `workflow_dispatch`, pode republicar a tag `COMMIT_SHA`. O deploy referencia a tag por `COMMIT_SHA` no manifesto do `Deployment`. A tag `latest` serve como ponteiro flutuante de conveniência.

Na transição da Fase 3 para a Fase 4, o repositório legado `ecr-oficina-mecanica-app-repo` deixou de fazer parte desta configuração Terraform para que cada bounded context tenha ciclo de vida de imagens independente e para que a destruição automatizada ao final da sessão do laboratório (`terraform destroy`) possa remover os repositórios mesmo quando contêm imagens publicadas.

## Decisão

Configurar os repositórios ECR (`aws_ecr_repository.service` e `aws_ecr_lifecycle_policy.service_lifecycle`) com:

- **Um repositório por contexto (`ecr-oficina-mecanica-<contexto>`) via `for_each = local.services`**: isola o histórico de imagens de `work-order`, `identity`, `billing` e `inventory`.
- **`force_delete = true`**: permite que o `terraform destroy` ao fim da sessão do AWS Academy Learner Lab apague os repositórios mesmo contendo tags publicadas, já que apenas o state no S3 persiste entre sessões e o CD de cada serviço republica a imagem na subida seguinte.
- **`scan_on_push = true`**: toda imagem enviada é varrida automaticamente por vulnerabilidades conhecidas (CVEs) no momento do push, sem exigir um passo manual ou scanner externo.
- **`image_tag_mutability = "MUTABLE"`**: permite que a tag `latest` seja reescrita a cada build — necessário porque o pipeline publica essa tag em **todo** build, e uma política `IMMUTABLE` rejeitaria o segundo push da mesma tag.
- **Lifecycle policy mantendo as últimas 20 imagens por repositório**: imagens além desse número em cada serviço são automaticamente expiradas, controlando o custo de armazenamento sem que builds frequentes de um serviço apaguem imagens de rollback de outro.
- **Criptografia AES-256** em repouso, o padrão gerenciado pela AWS para o ECR.

## Alternativas consideradas

### Preservar o `ecr-oficina-mecanica-app-repo` fora do Terraform com bloco `removed`

Descartada porque deixaria um repositório órfão na conta após o cutover do `work-order` para `ecr-oficina-mecanica-work-order` (contrariando a §14 da especificação), e porque o ambiente e o state do `infra-k8s` são recriados do zero nas sessões do laboratório.

### Repositório ECR único compartilhado com prefixo por serviço na tag

Manteria apenas um repositório ECR para os quatro microsserviços, diferenciando as imagens pela tag (ex.: `work-order-<sha>`, `billing-<sha>`). Descartada porque a regra de ciclo de vida do ECR (`imageCountMoreThan = 20` com `tagStatus = "any"`) opera sobre o total de imagens do repositório: um serviço com deploys mais frequentes expiraria as imagens dos demais serviços, podendo apagar justamente a imagem em execução ou de rollback de outro contexto. Além disso, a cobrança do ECR é por GB armazenado, e não por número de repositórios.

### `force_delete = false` (padrão do recurso)

Impediria a exclusão acidental de repositórios com imagens. Descartada porque a operação em laboratório exige destruir toda a infraestrutura ao final de cada sessão para preservar o orçamento de créditos: sem `force_delete = true`, o `terraform destroy` falha em qualquer repositório que tenha recebido push do CD.

### `image_tag_mutability = "IMMUTABLE"`

Eliminaria por política do ECR o risco de qualquer tag ser reescrita, garantia que a convenção de `COMMIT_SHA` sozinha não oferece. Descartada porque quebraria o pipeline de CD tal como existe hoje: o job `build-push-image` publica `latest` em todo build, e a política rejeitaria tanto a reescrita de `latest` quanto a republicação de uma tag de commit existente.

### Sem lifecycle policy (reter todas as imagens indefinidamente)

Manteria histórico completo de todas as imagens já publicadas, sem risco de expirar uma imagem ainda necessária. Descartada por custo: o armazenamento do ECR é cobrado por volume, e reter indefinidamente todas as imagens cresceria sem limite — manter as últimas 20 por serviço é suficiente para qualquer rollback dentro do ciclo de vida do laboratório.

### `scan_on_push = false`, com scanner de vulnerabilidade externo (ex.: Trivy no CI)

Descartada como substituto do `scan_on_push` nativo do ECR (embora nada impeça as duas coexistirem) porque o scan nativo roda automaticamente em toda imagem publicada, sem exigir manutenção de uma ferramenta adicional no pipeline nem a gestão de sua própria base de CVEs.

## Consequências

### Positivas

- **Ciclo de vida e retenção isolados por serviço**: cada contexto mantém suas próprias 20 imagens mais recentes sem interferir nos outros serviços.
- **Destruição limpa da plataforma**: `force_delete = true` garante que o teardown automatizado encerre sem erro de repositório não vazio.
- **Vulnerabilidades conhecidas detectadas automaticamente** a cada push, sem esforço adicional de pipeline.
- **Expansão orientada por mapa**: adicionar uma chave em `local.services` cria automaticamente o repositório ECR e sua política de ciclo de vida.

### Negativas / Trade-offs

- **Tags podem mudar de digest**: `latest` acompanha novos builds, e uma republicação de `COMMIT_SHA` também pode alterar a imagem obtida pelo deploy.
- **`force_delete = true` remove todas as imagens no destroy**: após recriar o ambiente em nova sessão do laboratório, o workflow de CD de cada microsserviço precisa rodar para republicar sua imagem no ECR recém-criado.
- **Janela de retenção limitada a 20 imagens por serviço**: um rollback para uma versão além das últimas 20 publicadas exigiria rebuildar a partir do commit histórico.

### Riscos mitigados

- **Expiração cruzada de imagens entre microsserviços**: mitigado pela separação de um repositório ECR por bounded context.
- **Falha no teardown da infraestrutura por imagens remanescentes**: mitigado por `force_delete = true`.
- **Deploy de imagem com vulnerabilidade conhecida não detectada**: mitigado pelo scan automático no push.

## Referências

- `terraform/ecr.tf` e `terraform/locals.tf` — configuração dos repositórios ECR por serviço.
- [ADR 0007 — Namespace por serviço e namespace de plataforma](0007-isolamento-por-namespace-e-ecr-por-bounded-context.md)
- [`oficina-mecanica-work-order-service` — CI/CD, build/push e imagem do Deployment](https://github.com/FIAP-15SOAT/oficina-mecanica-work-order-service/blob/main/docs/infra/ci-cd.md)
- [AWS provider — ECR, mutabilidade e filtros de exclusão](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ecr_repository.html.markdown)
