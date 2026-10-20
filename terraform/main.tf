data "aws_availability_zones" "available" {
  state = "available"
}

# A conta AWS NÃO é hardcoded: resolve das credenciais que rodam o
# plan/apply — no deploy.yml, os secrets AWS_LAB_* do GitHub.
# sts:GetCallerIdentity é permitido por qualquer credencial válida,
# inclusive a sessão temporária do Academy.
data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"

  # 3 AZ: o topologySpreadConstraints por zona do overlay aws precisa de mais de
  # uma para fazer sentido, e o RDS exige subnet group multi-AZ.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # ID da conta: variável preenchida > credenciais do run. Único dado
  # por-conta do código, e nem precisa virar variável no pipeline.
  account_id = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current.account_id

  # AWS Academy (Learner Lab): sem iam:CreateRole, iam:CreatePolicy nem
  # provider OIDC. Com lab_mode, cluster, nós e controllers usam a
  # LabRole, e nenhum recurso de IAM é criado.
  lab_mode = var.lab_mode

  # ARNs completas, montadas com a conta resolvida. As variáveis
  # *_arn ainda permitem override manual (ex.: LabRole com outro nome).
  lab_role_arn = var.lab_role_arn != "" ? var.lab_role_arn : "arn:aws:iam::${local.account_id}:role/LabRole"

  cluster_creator_arn = var.cluster_creator_arn != null ? var.cluster_creator_arn : (
    local.lab_mode ? "arn:aws:iam::${local.account_id}:role/voclabs" : null
  )
}
