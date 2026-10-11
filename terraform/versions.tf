terraform {
  # `~> 1.10` e não `>=`: o state do HCP Terraform e as tags key-only do bloco
  # `cloud` exigem 1.10+, e um range aberto aceitaria um futuro 2.x com breaking
  # changes.
  required_version = "~> 1.10"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    helm   = { source = "hashicorp/helm", version = "~> 2.17" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }

  # HCP Terraform (Terraform Cloud) substitui o backend S3: o state passa a
  # viver nos workspaces do TFC. `cloud` é mutuamente exclusivo com `backend`.
  #
  # Um workspace por ambiente, casados por tag: crie no TFC os workspaces
  # `techchallenge-infra-prod` e `techchallenge-infra-staging` com a tag
  # `techchallenge-infra`, e defina a variável `environment` (prod/staging) em
  # cada um. Para rodar pelo CLI, exporte TF_WORKSPACE com o nome do workspace
  # (o valor precisa estar contido nas tags).
  #
  # O `organization` NÃO aceita variável: substitua REPLACE_ORG pelo slug da
  # organização no app.terraform.io.
  #
  # MIGRAÇÃO do state S3 existente (UMA vez, por workspace — ver README):
  #   terraform login
  #   $env:TF_WORKSPACE = "techchallenge-infra-prod"
  #   terraform init -migrate-state
  cloud {
    organization = "TechChallenge-FIAP"

    workspaces {
      tags = ["techchallenge-infra"]
    }
  }
}
