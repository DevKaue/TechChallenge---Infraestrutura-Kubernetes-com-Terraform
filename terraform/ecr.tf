resource "aws_ecr_repository" "api" {
  # `-api` para bater com o nome da imagem no Kustomize (techchallenge-api) e
  # com o que o CI publica. Nome divergente aqui vira variável errada no GitHub.
  name = "${var.project}-api"

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
