# Homologação. Lido pelo deploy.yml no push em `develop`
# (`-var-file=envs/staging.tfvars`), junto com a key k8s/staging/terraform.tfstate
# do backend. Só roda com a variável STAGING_ENABLED=true no repositório: o
# staging dobra o custo (EKS, NAT, NLB) e sobe só quando for usado.

environment = "staging"

# Mesma versão de prod: homologação existe para testar o que vai para produção.
kubernetes_version = "1.35"

# Faixa diferente de prod: se um dia houver peering ou VPN entre as duas VPCs,
# CIDRs iguais impedem a rota.
vpc_cidr = "10.1.0.0/16"

node_group_size = {
  min     = 2
  max     = 2
  desired = 2
}
