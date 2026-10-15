# Variáveis do root module. No HCP Terraform a MAIORIA disto vive como variável
# do workspace (ver README); este arquivo serve para runs locais:
#   terraform plan -var-file=terraform.tfvars
# Copie para terraform.tfvars (gitignored) e ajuste.

region      = "us-east-1"
project     = "techchallenge"
environment = "prod" # no TFC: prod no workspace de produção, staging no de homologação

# Precisa não colidir com a rede de casa/escritório se um dia houver VPN.
vpc_cidr = "10.0.0.0/16"

kubernetes_version = "1.32"

# AWS Academy: t3.medium é a escolha do lab. Numa conta paga, o default
# c7i-flex.large também serve (2 vCPU / 4 GiB, free-tier-eligible). Evite os
# t4g.*: são ARM (Graviton) e a imagem é buildada para amd64.
node_instance_types = ["t3.medium"]
node_group_size = {
  min     = 2
  max     = 4
  desired = 2
}

# AWS Academy (Learner Lab): a conta não permite criar roles de IAM.
# lab_mode = true (default) faz cluster, nós e controllers usarem a
# LabRole (sem IRSA e sem as roles OIDC do GitHub). No TFC, deixe o
# default ou defina como variável do workspace.
lab_mode = true

# ID da conta (12 dígitos). Opcional: vazio resolve sozinho pelas
# credenciais do run (data.aws_caller_identity) — nada de específico
# por conta no código nem no workspace. Descomente para fixar:
# aws_account_id = "997726080598"

# Overrides manuais, só se LabRole/voclabs tiverem outro nome:
# lab_role_arn        = "arn:aws:iam::<conta>:role/LabRole"
# cluster_creator_arn = "arn:aws:iam::<conta>:role/voclabs"

# Fora do Academy (conta paga), descomente e preencha para habilitar as roles de
# deploy por OIDC da aplicação e da Lambda. Ignoradas quando lab_mode está
# ligado (local.lab_mode).
# github_app_repository    = "owner/techchallenge-app"
# github_lambda_repository = "owner/techchallenge-lambda"

# ARNs de IAM que também devem ser admin do cluster (além de quem roda o apply).
cluster_admin_arns = []

# ARNs de IAM com leitura no namespace (pods, logs, HPA) e SEM acesso a Secrets.
# Ex.: ["arn:aws:iam::123456789012:role/dev"]
cluster_readonly_arns = []
