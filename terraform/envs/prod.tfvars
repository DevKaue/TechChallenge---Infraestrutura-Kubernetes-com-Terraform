# Produção. Lido pelo deploy.yml no push em `main` (`-var-file=envs/prod.tfvars`),
# junto com a key k8s/prod/terraform.tfstate do backend.
#
# Versionado de propósito: nada aqui é segredo, e mudar a versão do Kubernetes
# ou a rede de produção precisa aparecer no diff do PR.

environment = "prod"

# Em suporte padrão até 03/2027. Antes de trocar, confira as versões em suporte
# padrão (fora dele o control plane custa ~6x):
#   aws eks describe-cluster-versions --region us-east-1
kubernetes_version = "1.35"

vpc_cidr = "10.0.0.0/16"

node_group_size = {
  min     = 2
  max     = 4
  desired = 2
}
