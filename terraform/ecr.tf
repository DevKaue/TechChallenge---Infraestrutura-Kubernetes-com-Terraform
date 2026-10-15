resource "aws_ecr_repository" "api" {
  # Um repositório por ambiente (techchallenge-staging-api, techchallenge-prod-api):
  # staging e prod dividem a conta AWS, e um nome fixo faria o segundo apply falhar
  # com RepositoryAlreadyExistsException.
  #
  # O nome da imagem no Kustomize (techchallenge-api) NÃO precisa bater com este
  # nome: o CI deve apontar a imagem para o output `ecr_url` do ambiente, por
  # exemplo `kustomize edit set image techchallenge-api=<ecr_url>:<sha>`. O nome do
  # repositório vira a variable ECR_REPOSITORY do GitHub Environment (output
  # `ecr_repository_name`).
  name = "${local.name}-api"

  # Tag imutável: o CI publica por $GIT_SHA. Sem isto alguém pode repontar uma
  # tag já implantada e o rollback deixa de ser determinístico.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Permite `terraform destroy` com imagens dentro. Em produção real seria false.
  force_delete = true

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantém as 10 imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
