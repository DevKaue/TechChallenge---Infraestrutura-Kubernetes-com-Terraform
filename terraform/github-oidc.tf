# Roles de deploy pelo GitHub Actions SEM chave estática: o Actions troca seu
# token OIDC por credenciais temporárias da AWS. Nada de AWS_ACCESS_KEY_ID em
# secret de repositório.
#
# UM ROLE POR REPOSITÓRIO, cada um restrito à condição `repo:<owner>/<repo>:*`.
# Sem essa condição QUALQUER repo do GitHub poderia assumir a role.
#
# O provider OIDC é UMA VEZ por conta e fica neste repo, porque é ele (o
# primeiro da ordem de criação) que guarda o thumbprint. O infra-db NÃO recria o
# provider: usa `data "aws_iam_openid_connect_provider"` deste mesmo provider.

# AWS Academy (local.lab_mode): nada deste arquivo é criado — a conta não
# permite provider OIDC nem roles. Os pipelines usam as credenciais temporárias
# do lab (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY e AWS_SESSION_TOKEN): no
# workspace do Terraform Cloud e nos secrets do GitHub do repositório do app.
locals {
  github_k8s_role_enabled    = !local.lab_mode && var.github_repository != ""
  github_app_role_enabled    = !local.lab_mode && var.github_app_repository != ""
  github_lambda_role_enabled = !local.lab_mode && var.github_lambda_repository != ""

  oidc_enabled = local.github_k8s_role_enabled || local.github_app_role_enabled || local.github_lambda_role_enabled
}

data "tls_certificate" "github" {
  count = local.oidc_enabled ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = local.oidc_enabled ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = local.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Terraform DESTE repositório (techchallenge-infra-k8s)
#    Executa `terraform apply` do cluster (VPC, EKS, ECR, ALB Controller,
#    addons). Precisa de permissão ampla de rede/compute/IAM.
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "assume_k8s" {
  count = local.github_k8s_role_enabled ? 1 : 0

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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_terraform_k8s" {
  count = local.github_k8s_role_enabled ? 1 : 0

  name               = "${local.name}-github-terraform-k8s"
  assume_role_policy = data.aws_iam_policy_document.assume_k8s[0].json

  tags = local.tags
}

# Deploy do cluster exige permissão ampla de rede/compute/IAM. Em produção
# real, restringe por recurso — aqui a prioridade é o fluxo funcionar e o
# princípio "só este repo assume" estar garantido pelo OIDC.
data "aws_iam_policy_document" "github_terraform_k8s" {
  count = local.github_k8s_role_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks:*",
      "ecr:*",
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "kms:DescribeKey",
      "logs:DescribeLogGroups",
      "logs:CreateLogGroup",
      "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }

  # Parâmetros SSM só sob o prefixo do projeto (secrets.tf). DescribeParameters
  # não aceita restrição por recurso, por isso fica num statement à parte.
  statement {
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_terraform_k8s" {
  count = local.github_k8s_role_enabled ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.github_terraform_k8s[0].id
  policy = data.aws_iam_policy_document.github_terraform_k8s[0].json
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. Deploy da APLICAÇÃO (repo techchallenge-app)
#    Push no ECR e `kubectl apply -k` no cluster. A autorização DENTRO do
#    cluster vem do access entry abaixo (IAM autentica, RBAC/ClusterAdmin
#    autoriza). É a role que o app repo configura como AWS_DEPLOY_ROLE.
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "assume_app" {
  count = local.github_app_role_enabled ? 1 : 0

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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_app_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_app_deploy" {
  count = local.github_app_role_enabled ? 1 : 0

  name               = "${local.name}-github-app-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume_app[0].json

  tags = local.tags
}

data "aws_iam_policy_document" "github_app_deploy" {
  count = local.github_app_role_enabled ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }

  # Lê o DATABASE_URL que o repo infra-db grava no Secrets Manager, para montar
  # o .env.secret do overlay no deploy.
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.region}:*:secret:${local.name}/rds*"]
  }

  # Lê o segredo JWT compartilhado (secrets.tf) para montar o Secret do app e as
  # credenciais jwt dos KongConsumers.
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.jwt_secret.arn]
  }
}

resource "aws_iam_role_policy" "github_app_deploy" {
  count = local.github_app_role_enabled ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.github_app_deploy[0].id
  policy = data.aws_iam_policy_document.github_app_deploy[0].json
}

resource "aws_eks_access_entry" "github_app_deploy" {
  count = local.github_app_role_enabled ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_app_deploy[0].arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_app_deploy" {
  count = local.github_app_role_enabled ? 1 : 0

  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_app_deploy[0].arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Deploy da LAMBDA (repo techchallenge-lambda)
#    `sam deploy` = CloudFormation que cria função, role e VPC config. Sem API
#    Gateway da AWS: quem expõe a Lambda é o Kong (kong.tf), via plugin
#    aws-lambda. A role é assumida pelo repo DONO da lambda.
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "assume_lambda" {
  count = local.github_lambda_role_enabled ? 1 : 0

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

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_lambda_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_lambda_deploy" {
  count = local.github_lambda_role_enabled ? 1 : 0

  name               = "${local.name}-github-lambda-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda[0].json

  tags = local.tags
}

data "aws_iam_policy_document" "github_lambda_deploy" {
  count = local.github_lambda_role_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "cloudformation:CreateChangeSet",
      "cloudformation:DescribeChangeSet",
      "cloudformation:DescribeStacks",
      "cloudformation:ExecuteChangeSet",
      "cloudformation:GetTemplate",
      "cloudformation:ListStackResources",
      "cloudformation:CreateStack",
      "cloudformation:UpdateStack",
      "cloudformation:DeleteStack",
      "lambda:*",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "s3:CreateBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "iam:PassRole",
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "secretsmanager:GetSecretValue",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_lambda_deploy" {
  count = local.github_lambda_role_enabled ? 1 : 0

  name   = "deploy"
  role   = aws_iam_role.github_lambda_deploy[0].id
  policy = data.aws_iam_policy_document.github_lambda_deploy[0].json
}