output "cluster_name" {
  description = "Nome do cluster EKS. Use em: aws eks update-kubeconfig --name ..."
  value       = module.eks.cluster_name
}

output "region" {
  description = "Região da AWS."
  value       = var.region
}

output "ecr_url" {
  description = "URL do repositório ECR. Destino do docker push do repositório da aplicação."
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_repository_name" {
  description = "Nome do repositório ECR. Vira a variable ECR_REPOSITORY no GitHub."
  value       = aws_ecr_repository.api.name
}

output "vpc_cidr" {
  description = "CIDR da VPC. Substitui o placeholder 10.0.0.0/16 nas NetworkPolicies do overlay aws do repositório da aplicação."
  value       = module.vpc.vpc_cidr_block
}

output "vpc_id" {
  description = "ID da VPC. Consumido pelos repositórios de banco e da aplicação."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Subnets privadas. O RDS do repositório de banco usa para o subnet group."
  value       = module.vpc.private_subnets
}

output "node_security_group_id" {
  description = "Security group dos nós do EKS. O RDS do repositório de banco libera o ingress 5432 a partir dele."
  value       = module.eks.node_security_group_id
}

output "github_deploy_role_arn" {
  description = "ARN a configurar como AWS_DEPLOY_ROLE nos secrets do repositório GitHub."
  value       = local.github_enabled ? aws_iam_role.github_deploy[0].arn : null
}

output "kubeconfig_command" {
  description = "Comando pronto para apontar o kubectl para este cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
