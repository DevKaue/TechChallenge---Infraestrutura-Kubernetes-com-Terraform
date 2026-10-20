output "bucket_name" {
  description = "Bucket de state dos 4 repositórios. Vira a variável TF_STATE_BUCKET do GitHub, passada em `terraform init -backend-config=\"bucket=...\"`."
  value       = aws_s3_bucket.state.bucket
}

output "region" {
  description = "Região do bucket. É o `region` do backend em todos os repositórios."
  value       = var.region
}
