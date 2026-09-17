# Deploy pelo GitHub Actions sem chave estática: o Actions troca seu token OIDC
# por credenciais temporárias da AWS. Nada de AWS_SECRET_ACCESS_KEY em secret de
# repositório — ainda mais num repo público.

locals {
  github_enabled = var.github_repository != ""
}

data "tls_certificate" "github" {
  count = local.github_enabled ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.github_enabled ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = local.tags
}

data "aws_iam_policy_document" "github_assume" {
  count = local.github_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrito a este repositório. Sem esta condição, QUALQUER repo do GitHub
    # poderia assumir a role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count = local.github_enabled ? 1 : 0

  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume[0].json

  tags = local.tags
}

# Permissões do pipeline. Este repositório roda `terraform apply` no CI, que
# cria VPC, IAM, EKS, addons e escreve no bucket de state — ou seja, exige
# permissão ampla. `github_deploy_policy_arns` permite trocar AdministratorAccess
# por uma policy sob medida numa conta real.
#
# A autorização DENTRO do cluster (namespace/Secret via provider kubernetes) vem
# do access entry logo abaixo, não do IAM.
resource "aws_iam_role_policy_attachment" "github_deploy" {
  for_each = local.github_enabled ? toset(var.github_deploy_policy_arns) : toset([])

  role       = aws_iam_role.github_deploy[0].name
  policy_arn = each.value
}

# Acesso do pipeline DENTRO do cluster. Admin porque o `terraform apply` cria o
# namespace e o Secret da aplicação via provider kubernetes. Reduzir isso
# exigiria enumerar cada verbo — dívida consciente, anotada no README.
resource "aws_eks_access_entry" "github_deploy" {
  count = local.github_enabled ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_deploy" {
  count = local.github_enabled ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_deploy[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
