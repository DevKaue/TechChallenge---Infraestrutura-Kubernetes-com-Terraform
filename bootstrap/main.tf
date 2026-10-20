provider "aws" {
  region = var.region

  # Sem tag Environment: o bucket é um só para staging e prod, e para os 4
  # repositórios. Os ambientes se separam pela key do state, não pelo bucket.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "tfstate"
    }
  }
}

# A conta vem das credenciais do run, não do código: nenhum ID de conta fica no
# repositório, e cada conta do AWS Academy ganha o próprio bucket.
data "aws_caller_identity" "current" {}

locals {
  # Nome de bucket é global na AWS. O ID da conta no sufixo evita colidir com o
  # bucket de outra conta (o techchallenge-fiap-v1 antigo é exatamente isso).
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# Guarda o state de TODOS os repositórios (k8s/, db/, lambda/ e bootstrap/).
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Um `destroy` aqui apagaria o state dos 4 repositórios de uma vez, e a infra
  # continuaria na AWS sem nada que a gerencie. Para remover de propósito, tire
  # o prevent_destroy num PR, onde o motivo fica registrado.
  lifecycle {
    prevent_destroy = true
  }
}

# Versionamento: cada apply grava uma versão nova do state. Um state corrompido
# ou sobrescrito volta pela versão anterior, sem recriar nada na AWS.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256), e não KMS com chave própria: o state já fica privado pelo
# bloqueio de acesso público e pela policy; a CMK custaria ~US$1/mês sem mudar
# quem consegue ler (no lab, quem tem a credencial lê com ou sem CMK).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# O state guarda o segredo JWT e a senha do banco em texto claro. Nada aqui pode
# ficar público, nem por engano numa ACL ou policy futura.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs desligadas: o acesso é decidido só por IAM e pela policy abaixo.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Sem expiração, cada apply dos 4 repositórios deixaria uma versão de state para
# sempre. As versões antigas ficam pela janela configurada e depois expiram.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

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
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  # Com block_public_policy ligado antes, a AWS valida esta policy contra o
  # bloqueio; aplicada antes dele, a ordem fica indefinida entre os dois.
  depends_on = [aws_s3_bucket_public_access_block.state]
}
