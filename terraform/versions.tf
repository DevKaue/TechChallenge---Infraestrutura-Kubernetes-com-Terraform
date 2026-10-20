terraform {
  # `~> 1.16` casa com o ci.yml (1.16.5) e com a versão fixada nos workspaces do
  # HCP Terraform. Um `>=` aberto deixaria o plan local e o do TFC rodarem em
  # minors diferentes.
  required_version = "~> 1.16"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    helm   = { source = "hashicorp/helm", version = "~> 2.17" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }

  cloud {
    organization = "tech-challenge-infra"

    workspaces {
      tags = ["techchallenge-infra"]
    }
  }
}
