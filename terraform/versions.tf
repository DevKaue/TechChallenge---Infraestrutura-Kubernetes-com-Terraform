terraform {
  # `~> 1.10` e não `>= 1.9`: `use_lockfile` no backend S3 exige 1.10+, e um
  # `>=` aberto aceitaria um futuro 2.x com breaking changes.
  required_version = "~> 1.10"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.90" }
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
    tls        = { source = "hashicorp/tls", version = "~> 4.0" }
  }

  # O bucket precisa existir ANTES do primeiro init (chicken-and-egg do backend).
  # Criação, uma vez só — ver terraform/README.md:
  #   aws s3api create-bucket --bucket techchallenge-fiap-v1 --region us-east-1
  #   aws s3api put-bucket-versioning --bucket techchallenge-fiap-v1 \
  #     --versioning-configuration Status=Enabled
  #
  # Backend NÃO aceita variáveis — region e bucket são literais por imposição do
  # Terraform, não por descuido.
  backend "s3" {
    bucket       = "techchallenge-fiap-v1"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # locking nativo do S3 (1.10+), sem DynamoDB
  }
}
