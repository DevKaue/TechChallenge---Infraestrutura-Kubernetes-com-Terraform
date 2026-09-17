# Copie para terraform.tfvars (gitignored) e ajuste.
# Nenhuma senha aqui: as chaves do Secret da aplicação são geradas por
# random_password. A senha do banco vem do state do repositório de banco.

region      = "us-east-1"
project     = "techchallenge"
environment = "prod"

# Precisa não colidir com a rede de casa/escritório se um dia houver VPN.
vpc_cidr = "10.0.0.0/16"

kubernetes_version = "1.32"

# c7i-flex.large é free-tier-eligible; t3.medium falha em contas no Free Tier.
# A API (3 réplicas), o ALB controller e o metrics-server cabem em 2 nós.
node_instance_types = ["c7i-flex.large"]
node_group_size = {
  min     = 2
  max     = 4
  desired = 2
}

# State do repositório de banco de dados (outputs db_endpoint, db_name,
# db_username, db_password). Um key por ambiente.
db_state_bucket = "techchallenge-fiap-v1"
db_state_key    = "db/prod/terraform.tfstate"
db_state_region = "us-east-1"

# Repositório autorizado a assumir a role de deploy via OIDC. Vazio desliga.
github_repository = "DevKaue/TechChallenge---Infraestrutura-Kubernetes-com-Terraform"

# Policies da role de deploy do CI. O apply exige permissão ampla.
github_deploy_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]

# ARNs de IAM que também devem ser admin do cluster (além de quem roda o apply).
cluster_admin_arns = []

# ARNs de IAM com leitura no namespace (pods, logs, HPA) e SEM acesso a Secrets.
# Ex.: ["arn:aws:iam::123456789012:role/dev"]
cluster_readonly_arns = []
