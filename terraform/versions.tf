terraform {
  # `~> 1.16` casa com o ci.yml e o deploy.yml (1.16.5). Um `>=` aberto deixaria
  # o plan local e o do pipeline rodarem em minors diferentes.
  required_version = "~> 1.16"

  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.90" }
    helm   = { source = "hashicorp/helm", version = "~> 2.17" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
  }

  # State no bucket do bootstrap (bootstrap/), compartilhado com o banco e a
  # Lambda. Configuração parcial, porque backend não aceita variável:
  #   - bucket: tem o ID da conta no nome, e ID de conta não entra no código;
  #   - key: k8s/<env>/terraform.tfstate. Este root module serve staging e prod,
  #     então a key vem do MESMO valor que escolhe o envs/<env>.tfvars no
  #     deploy.yml. Um valor só para os dois é o que impede o plan de staging
  #     rodar contra o state de prod.
  #   terraform init -backend-config="bucket=$TF_STATE_BUCKET" \
  #                  -backend-config="key=k8s/prod/terraform.tfstate"
  backend "s3" {
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
