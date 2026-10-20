provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# O provider `kubernetes` do Terraform foi removido junto com os recursos
# kubernetes_namespace/kubernetes_secret: o namespace e o Secret da aplicação
# são criados pelo overlay Kustomize do repositório da app, dono único deles.
#
# O Helm autentica via `aws eks get-token`, não por token de data source: token
# de data source expira em 15 min e quebra applies longos no meio. Precisa do
# AWS CLI onde o Terraform roda; o runner ubuntu-latest do GitHub Actions já
# traz.
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
