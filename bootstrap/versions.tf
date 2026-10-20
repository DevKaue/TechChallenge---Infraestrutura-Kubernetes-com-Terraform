terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.90" }
  }

  # O state do bootstrap mora no PRÓPRIO bucket que ele cria, numa key só dele.
  #
  # Configuração parcial: o bucket entra por -backend-config, porque o nome tem
  # o ID da conta e backend não aceita variável nem data source. O primeiro
  # apply, antes de o bucket existir, roda com state local e depois migra para
  # cá (README, seção "State remoto").
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
