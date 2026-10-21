# Contrato de descoberta: o que os outros repositórios precisam saber sobre o
# cluster sai por um path previsível do SSM, no mesmo padrão do repositório de
# banco (/techchallenge/<env>/db/*). Ninguém lê o state deste repositório, que
# guarda o segredo JWT em texto claro.

# Security group dos nós do EKS, para o repositório de banco liberar a 5432 a
# partir dele.
#
# Por que publicar aqui, e não anexar o SG de cliente do banco aos nós: a ordem
# de criação é cluster → banco (o banco descobre a VPC deste repositório). Para
# anexar o SG do banco, este apply precisaria de algo que só existe depois dele.
# Invertendo, cada lado conhece só o que já existe quando roda.
#
# Os pods herdam o SG do nó: com o VPC CNI, o IP do pod é um IP secundário da
# ENI do nó. Liberar o SG dos nós no RDS libera os pods da aplicação.
resource "aws_ssm_parameter" "node_security_group_id" {
  name        = "/${var.project}/${var.environment}/eks/node-sg-id"
  description = "Security group dos nós do EKS de ${var.environment}. O RDS libera a 5432 a partir dele."
  type        = "String"
  value       = module.eks.node_security_group_id
  tags        = local.tags
}
