# Copie para terraform.tfvars (gitignored) e ajuste.
# Nenhuma senha aqui: para o RDS, elas são geradas e vão para o Secrets Manager
# no repositório techchallenge-infra-db.

region      = "us-east-1"
project     = "techchallenge"
environment = "prod"

# Precisa não colidir com a rede de casa/escritório se um dia houver VPN.
vpc_cidr = "10.0.0.0/16"

kubernetes_version = "1.32"

# t3.medium x2 comporta a API (3 réplicas), o ALB controller e o ESO.
node_instance_types = ["t3.medium"]
node_group_size = {
  min     = 2
  max     = 4
  desired = 2
}

# Vazio desliga cada role de deploy por OIDC. Cada repo assume só a sua.
github_repository        = "Jean-Carlo-Torres/techchallenge-infra-k8s"
github_app_repository    = "Jean-Carlo-Torres/techchallenge-app"
github_lambda_repository = "Jean-Carlo-Torres/techchallenge-lambda"

# ARNs de IAM que também devem ser admin do cluster (além de quem roda o apply).
cluster_admin_arns = []

# ARNs de IAM com leitura no namespace (pods, logs, HPA) e SEM acesso a Secrets.
# Ex.: ["arn:aws:iam::123456789012:role/dev"]
cluster_readonly_arns = []
