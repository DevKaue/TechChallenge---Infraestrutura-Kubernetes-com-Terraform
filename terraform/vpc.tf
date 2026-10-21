module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 por subnet: espaço de sobra para os IPs de pod do VPC CNI, que consome
  # um IP da subnet POR POD — não por nó.
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway = true
  # Um NAT em vez de três: ~US$ 32/mês contra ~US$ 96. O trade-off é real — se
  # a AZ do NAT cair, os nós das outras perdem saída para a internet. Aceitável
  # aqui, inaceitável em produção de verdade.
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # SEM estas tags o AWS Load Balancer Controller não descobre as subnets e o
  # Ingress sobe sem ADDRESS, sem nada indicando a causa.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}
