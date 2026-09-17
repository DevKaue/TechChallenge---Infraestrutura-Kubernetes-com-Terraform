# O banco gerenciado (RDS) vive em OUTRO repositório/state. Aqui apenas
# consumimos seus outputs para montar o DATABASE_URL do Secret.
#
# Ordem de apply: repositório de banco PRIMEIRO, este depois. Sem o state do
# banco publicado no S3, o plan/apply daqui falha ao ler os outputs.
#
# Contrato de outputs que o repositório de banco precisa expor:
#   db_endpoint  → host:porta do RDS
#   db_name      → nome do banco
#   db_username  → usuário master
#   db_password  → senha master (sensível)
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_state_bucket
    key    = var.db_state_key
    region = var.db_state_region
  }
}
