provider "aws" {
  region = var.region

  # Sem tag Environment: o bucket é um só para staging e prod, e para os 4
  # repositórios. Os ambientes se separam pela key do state, não pelo bucket.
  default_tags {
    tags = local.tags
  }
}

# A conta vem das credenciais do run, não do código: nenhum ID de conta fica no
# repositório, e cada conta do AWS Academy ganha o próprio bucket.
data "aws_caller_identity" "current" {}

locals {
  # Nome de bucket é global na AWS. O ID da conta no sufixo evita colidir com o
  # bucket de outra conta (o techchallenge-fiap-v1 antigo é exatamente isso).
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Component = "tfstate"
  }
}

# Guarda o state de TODOS os repositórios (k8s/, db/, lambda/ e bootstrap/).
#
# Por que AWS CLI e não `aws_s3_bucket`: toda leitura do recurso aws_s3_bucket
# chama s3:GetBucketObjectLockConfiguration, que a SCP da organização do AWS
# Academy nega explicitamente ("explicit deny in a service control policy").
# O apply cria o bucket e falha logo em seguida; o recurso fica tainted e nenhum
# plan seguinte consegue ler o bucket. Testado com o provider 5.100 e o 6.x: o
# mesmo erro. As APIs de CONFIGURAÇÃO do bucket (versioning, encryption, policy,
# lifecycle...) são liberadas, então tudo abaixo continua no provider.
#
# Efeito colateral bom: o bucket em si não fica no state, então nenhum
# `terraform destroy` consegue apagá-lo junto com o state dos 4 repositórios.
# Para remover de verdade: esvaziar e `aws s3api delete-bucket`, de propósito.
resource "terraform_data" "state_bucket" {
  input = local.bucket_name

  # Idempotente: só cria se o bucket ainda não existir (re-run e conta já
  # bootstrapada não falham). A região us-east-1 não aceita LocationConstraint.
  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set -eu
      if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
        echo "bucket $BUCKET já existe"
      elif [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
      else
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
          --create-bucket-configuration "LocationConstraint=$REGION"
      fi
      aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "$TAGS"
    EOT

    environment = {
      BUCKET = local.bucket_name
      REGION = var.region
      TAGS = jsonencode({
        TagSet = [for k, v in local.tags : { Key = k, Value = v }]
      })
    }
  }
}

# Versionamento: cada apply grava uma versão nova do state. Um state corrompido
# ou sobrescrito volta pela versão anterior, sem recriar nada na AWS.
resource "aws_s3_bucket_versioning" "state" {
  bucket = terraform_data.state_bucket.output

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256), e não KMS com chave própria: o state já fica privado pelo
# bloqueio de acesso público e pela policy; a CMK custaria ~US$1/mês sem mudar
# quem consegue ler (no lab, quem tem a credencial lê com ou sem CMK).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = terraform_data.state_bucket.output

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# O state guarda o segredo JWT e a senha do banco em texto claro. Nada aqui pode
# ficar público, nem por engano numa ACL ou policy futura.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = terraform_data.state_bucket.output

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs desligadas: o acesso é decidido só por IAM e pela policy abaixo.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = terraform_data.state_bucket.output

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Sem expiração, cada apply dos 4 repositórios deixaria uma versão de state para
# sempre. As versões antigas ficam pela janela configurada e depois expiram.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = terraform_data.state_bucket.output

  rule {
    id     = "expira-versoes-antigas-de-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # A regra de versões antigas só faz sentido com o versionamento já ligado.
  depends_on = [aws_s3_bucket_versioning.state]
}

# Recusa qualquer acesso sem TLS: o state trafega com segredos dentro.
data "aws_iam_policy_document" "state" {
  statement {
    sid     = "NegaAcessoSemTLS"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = terraform_data.state_bucket.output
  policy = data.aws_iam_policy_document.state.json

  # Com block_public_policy ligado antes, a AWS valida esta policy contra o
  # bloqueio; aplicada antes dele, a ordem fica indefinida entre os dois.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
