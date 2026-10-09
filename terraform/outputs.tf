output "cluster_name" {
  description = "Nome do cluster EKS. Use em: aws eks update-kubeconfig --name ..."
  value       = module.eks.cluster_name
}

output "region" {
  description = "Região da AWS."
  value       = var.region
}

output "ecr_url" {
  description = "URL do repositório ECR. Destino do docker push e do kustomize edit set image."
  value       = aws_ecr_repository.api.repository_url
}

output "ecr_repository_name" {
  description = "Nome do repositório ECR. Vira a variable ECR_REPOSITORY no GitHub."
  value       = aws_ecr_repository.api.name
}

output "vpc_cidr" {
  description = "CIDR da VPC. Substitui o placeholder 10.0.0.0/16 nas NetworkPolicies do overlay aws."
  value       = module.vpc.vpc_cidr_block
}

output "vpc_id" {
  description = "ID da VPC. Consumido pelo terraform_remote_state do repositório techchallenge-infra-db."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas. Consumido pelo terraform_remote_state do repositório techchallenge-infra-db."
  value       = module.vpc.private_subnets
}

output "node_security_group_id" {
  description = "ID do security group dos nós EKS. Autoriza (na ponta do RDS) a porta 5432 vinda dos nós. Consumido pelo repositório techchallenge-infra-db."
  value       = module.eks.node_security_group_id
}

output "github_app_deploy_role_arn" {
  description = "ARN a configurar como AWS_DEPLOY_ROLE nos secrets do repositório techchallenge-app."
  value       = local.github_app_role_enabled ? aws_iam_role.github_app_deploy[0].arn : null
}

output "github_terraform_k8s_role_arn" {
  description = "ARN a configurar como AWS_DEPLOY_ROLE nos secrets deste repositório (techchallenge-infra-k8s)."
  value       = local.github_k8s_role_enabled ? aws_iam_role.github_terraform_k8s[0].arn : null
}

output "github_lambda_deploy_role_arn" {
  description = "ARN a configurar como AWS_DEPLOY_ROLE nos secrets do repositório techchallenge-lambda."
  value       = local.github_lambda_role_enabled ? aws_iam_role.github_lambda_deploy[0].arn : null
}

output "auth_lambda_name" {
  description = "Nome que a Lambda de autenticação precisa ter. O Kong só tem permissão para invocar esta função."
  value       = local.auth_lambda_name
}

output "jwt_secret_ssm_path" {
  description = "Parâmetro SSM do segredo JWT. Vira JWT_SECRET_SSM_PATH na Lambda e é lido pelo deploy da aplicação."
  value       = aws_ssm_parameter.jwt_secret.name
}

output "kong_proxy_hostname_command" {
  description = "Comando para obter o DNS do NLB do Kong (endereço público da API)."
  value       = "kubectl -n ${local.kong_namespace} get svc kong-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "kong_manager_command" {
  description = "Port-forward do Kong Manager (só leitura em DB-less) e da Admin API que ele consome."
  value       = "kubectl -n ${local.kong_namespace} port-forward deploy/kong-gateway 8002:8002 8001:8001"
}

output "kubeconfig_command" {
  description = "Comando pronto para apontar o kubectl para este cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
