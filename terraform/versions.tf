terraform {
  required_version = "1.16.5"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    helm   = { source = "hashicorp/helm", version = "~> 2.17" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }

  cloud {
    organization = "tech-challenge-fiap-5546"

    workspaces {
      name = "tech-challenge-fiap"
    }
  }
}
