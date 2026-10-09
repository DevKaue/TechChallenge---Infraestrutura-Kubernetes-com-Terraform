# Namespace e Secret da aplicação.
#
# Por que o Terraform cria o NAMESPACE e não o Kustomize (como no overlay
# local): o Secret precisa de um namespace existente, e o Terraform roda ANTES
# do `kubectl apply -k`. Deixar os dois criarem o mesmo objeto daria dois donos
# para o mesmo recurso.
#
# Por que não External Secrets Operator: para UM Secret de QUATRO chaves, o ESO
# custaria um operator no cluster, um CRD, uma role IRSA e um passo manual de
# `kubectl apply` do ClusterSecretStore. O argumento de "não guardar segredo no
# state" também não se aplica — as senhas são geradas aqui, então já estão no
# state de qualquer forma. Se um dia for preciso rotacionar sem `terraform
# apply`, aí o ESO passa a valer o preço.
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

# Fonte única do segredo HS256 dos tokens: a Lambda de CPF (que emite token de
# cliente) lê daqui em runtime, e o deploy da aplicação lê daqui para montar o
# Secret do app e as credenciais jwt dos KongConsumers. Se cada um tivesse o
# seu, o Kong recusaria os tokens de quem estivesse divergente.
resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/${var.project}/${var.environment}/auth/jwt-secret"
  description = "Segredo HS256 compartilhado entre Lambda de autenticação, aplicação e Kong."
  type        = "SecureString"
  value       = random_password.jwt_secret.result
  tags        = local.tags
}

# ATENÇÃO: salt fixo e global do scrypt. Trocar este valor invalida TODAS as
# senhas já gravadas no banco. `random_password` é estável no state, mas um
# ciclo destroy/apply gera outro — ver a seção de dívidas no README.
resource "random_password" "password_salt" {
  length  = 64
  special = false
}

resource "random_password" "webhook_secret" {
  length  = 64
  special = false
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = "techchallenge"

    # Mesmos labels do namespace.yaml do repositório da aplicação: Pod Security
    # Standards por admission control. Um pod sem securityContext é rejeitado.
    labels = {
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "v1.32"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "app.kubernetes.io/part-of"                  = "techchallenge"
    }
  }

  depends_on = [module.eks]
}

# As quatro chaves são exatamente as exigidas pelo validateEnv() da aplicação.
# Faltando qualquer uma, o pod sobe e morre com "Missing required environment
# variables" — falha alta e óbvia.
resource "kubernetes_secret" "app" {
  metadata {
    name      = "techchallenge-secrets"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  type = "Opaque"

  data = {
    # `sslmode=require` é OBRIGATÓRIO no RDS: o Postgres 15 vem com
    # `rds.force_ssl = 1` por padrão e recusa conexão em texto claro com
    # "no pg_hba.conf entry ... no encryption".
    #
    # Sem isto o sintoma é traiçoeiro: o initContainer de migration CONECTA
    # (o engine do Prisma negocia TLS sozinho) e a aplicação NÃO (o
    # @prisma/adapter-pg usa node-postgres, que só usa TLS se mandarem).
    # O Deployment sobe, as migrations aplicam, e o pod fica eternamente
    # 0/1 com readiness em 503.
    #
    # O overlay local não usa isto de propósito: o Postgres do StatefulSet e o
    # dos composes não têm TLS configurado.
    #
    # `no-verify` e não `require`: o node-postgres VALIDA a cadeia com
    # `require`, e a CA da Amazon não está no trust store da imagem
    # (node:alpine) — dá "self-signed certificate in certificate chain".
    #
    # TRADE-OFF ACEITO CONSCIENTEMENTE: `no-verify` cifra o tráfego mas NÃO
    # autentica o servidor, o que em tese permite man-in-the-middle. Aqui o
    # RDS não é publicamente acessível, só aceita conexão do security group
    # dos nós e o tráfego não sai da VPC.
    # O certo é montar o bundle de CAs do RDS num ConfigMap e usar
    # `sslmode=verify-full&sslrootcert=/etc/ssl/rds/global-bundle.pem`.
    #
    # O endpoint, nome, usuário e senha vêm do state do repositório de banco
    # (terraform/remote-state.tf) — este repositório não cria mais o RDS.
    DATABASE_URL   = "postgresql://${data.terraform_remote_state.db.outputs.db_username}:${data.terraform_remote_state.db.outputs.db_password}@${data.terraform_remote_state.db.outputs.db_endpoint}/${data.terraform_remote_state.db.outputs.db_name}?schema=public&sslmode=no-verify"
    JWT_SECRET     = random_password.jwt_secret.result
    PASSWORD_SALT  = random_password.password_salt.result
    WEBHOOK_SECRET = random_password.webhook_secret.result
  }
}
