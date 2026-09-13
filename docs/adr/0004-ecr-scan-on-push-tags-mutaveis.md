# ADR 0004: Amazon ECR com scan-on-push, tags mutáveis e retenção de 20 imagens

## Status

Aceito — 2026-09-07

## Contexto

`terraform/ecr.tf` provisiona um repositório Amazon ECR dedicado às imagens de container da API (`oficina-mecanica-api`), com quatro configurações que juntas formam uma política de gestão de imagens: varredura automática de vulnerabilidades no push (`scan_on_push = true`), criptografia AES-256, mutabilidade de tag (`image_tag_mutability = "MUTABLE"`) e uma lifecycle policy mantendo as últimas 20 imagens.

O pipeline de CD do `oficina-mecanica-api` (`cd.yml`, job `build-push-image`) publica **duas tags por build**: `${ECR_REPOSITORY}:${COMMIT_SHA}`, associada ao commit, e `${ECR_REPOSITORY}:latest`, atualizada a cada build. Uma nova execução do mesmo commit, inclusive via `workflow_dispatch`, pode republicar a tag `COMMIT_SHA`. O deploy (`Render deployment manifest with immutable image`, nome atual do passo em `cd.yml`) usa a tag por `COMMIT_SHA` no manifesto do `Deployment`; esse nome de passo não impõe imutabilidade no ECR. A tag `latest` serve como ponteiro flutuante de conveniência e não é usada pelos manifests Kubernetes atuais.

## Decisão

Configurar o repositório ECR com:

- **`scan_on_push = true`**: toda imagem enviada é varrida automaticamente por vulnerabilidades conhecidas (CVEs) no momento do push, sem exigir um passo manual ou scanner externo.
- **`image_tag_mutability = "MUTABLE"`**: permite que a tag `latest` seja reescrita a cada build — necessário porque o pipeline publica essa tag em **todo** build, e uma política `IMMUTABLE` rejeitaria o segundo push da mesma tag, quebrando o pipeline no build seguinte ao primeiro. O deploy referencia a tag de `COMMIT_SHA`, em vez de `latest`, para identificar o commit. Essa é uma convenção de rastreabilidade: uma nova execução do mesmo commit pode reescrever sua tag, pois a política permite alterar todas as tags.
- **Lifecycle policy mantendo as últimas 20 imagens**: imagens além desse número são automaticamente expiradas, controlando o custo de armazenamento sem intervenção manual.
- **Criptografia AES-256** em repouso, o padrão gerenciado pela AWS para o ECR.

## Alternativas consideradas

### `image_tag_mutability = "IMMUTABLE"`

Eliminaria por política do ECR o risco de qualquer tag ser reescrita, garantia que a convenção de `COMMIT_SHA` sozinha não oferece. Descartada porque quebraria o pipeline de CD tal como existe hoje: o job `build-push-image` publica `latest` em todo build (`cd.yml`, passo `Build and Push Image`), e a política rejeitaria tanto a reescrita de `latest` quanto a republicação de uma tag de commit existente. Sua adoção exigiria rever a publicação dessas tags. A opção com exclusões para tags móveis está descrita nos trade-offs abaixo; nenhuma delas está configurada neste módulo.

### Sem lifecycle policy (reter todas as imagens indefinidamente)

Manteria histórico completo de todas as imagens já publicadas, sem risco de expirar uma imagem ainda necessária. Descartada por custo: o armazenamento do ECR é cobrado por volume, e reter indefinidamente todas as imagens de um pipeline que builda a cada push cresceria sem limite — manter as últimas 20 é suficiente para qualquer rollback razoável dentro do ciclo de vida do laboratório, a um custo previsível.

### `scan_on_push = false`, com scanner de vulnerabilidade externo (ex.: Trivy no CI)

Já existe uma etapa de SAST no [pipeline do `oficina-mecanica-api`](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/docs/infra/ci-cd.md); um scanner externo dedicado a imagem poderia rodar ali. Descartada como substituto do `scan_on_push` nativo do ECR (embora nada impeça as duas coexistirem) porque o scan nativo roda automaticamente em toda imagem publicada, sem exigir manutenção de uma ferramenta adicional no pipeline nem a gestão de sua própria base de CVEs.

## Consequências

### Positivas

- **Vulnerabilidades conhecidas detectadas automaticamente** a cada push, sem esforço adicional de pipeline.
- **Custo de armazenamento controlado** pela lifecycle policy, sem exigir limpeza manual periódica do repositório.
- **Deploy rastreável ao commit**: o manifesto do `Deployment` referencia a tag de `COMMIT_SHA`, não `latest`. Isso identifica o código de origem, mas não garante o mesmo conteúdo em uma republicação; reprodutibilidade da imagem exigiria também preservar ou fixar seu digest.

### Negativas / Trade-offs

- **Tags podem mudar de digest**: `latest` acompanha novos builds, e uma republicação de `COMMIT_SHA` também pode alterar a imagem obtida pelo deploy. Fixar a tag no manifesto não equivale a fixar seu digest.
- **A política adotada permite reescrever todas as tags**, inclusive `COMMIT_SHA`. O ECR/provider atual oferece `IMMUTABLE_WITH_EXCLUSION` e filtros para tags como `latest`; essa opção não está configurada neste módulo. O estado vigente permanece MUTABLE, sem alteração de política nesta revisão.
- **Janela de retenção limitada a 20 imagens**: um rollback para uma versão muito antiga (além das últimas 20 publicadas) não seria possível sem rebuildar a imagem a partir do código-fonte histórico.

### Riscos mitigados

- **Deploy de imagem com vulnerabilidade conhecida não detectada**: mitigado pelo scan automático no push.
- **Custo de armazenamento crescendo sem limite**: mitigado pela lifecycle policy de 20 imagens.

## Referências

- `terraform/ecr.tf` — configuração do repositório ECR.
- [`oficina-mecanica-api` — CI/CD, build/push e imagem do Deployment](https://github.com/FIAP-15SOAT/oficina-mecanica-api/blob/main/docs/infra/ci-cd.md)
- [AWS provider — ECR, mutabilidade e filtros de exclusão](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ecr_repository.html.markdown)
