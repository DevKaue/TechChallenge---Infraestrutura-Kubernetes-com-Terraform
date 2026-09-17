variable "region" {
  # ATENÇÃO: o backend S3 (versions.tf) tem a região como literal, porque bloco
  # `backend` não aceita variável. Trocar aqui NÃO troca a do backend — os dois
  # precisam mudar juntos, senão o state fica numa região e a infra em outra.
  description = "Região da AWS. Precisa bater com a região do backend em versions.tf."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo de nome para todos os recursos."
  type        = string
  default     = "techchallenge"
}

variable "environment" {
  description = "Ambiente lógico (prod, staging)."
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR da VPC. Vira o ipBlock da NetworkPolicy do overlay aws consumido pelo repositório da aplicação."
  type        = string
  default     = "10.0.0.0/16"

  # Sem isto, um valor inválido só estoura lá dentro do cidrsubnet() do vpc.tf,
  # com uma mensagem que não menciona esta variável. O /20 exige prefixo <= /20.
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr precisa ser um CIDR válido com prefixo /20 ou menor (ex.: 10.0.0.0/16)."
  }
}

variable "kubernetes_version" {
  description = "Versão do control plane do EKS."
  type        = string
  default     = "1.32"
}

variable "node_instance_types" {
  # c7i-flex.large e NÃO t3.medium: contas no plano AWS Free Tier bloqueiam o
  # lançamento de tipos fora da faixa gratuita, com o erro
  # "InvalidParameterCombination - not eligible for Free Tier" — que só aparece
  # DEPOIS de criar o cluster, na hora de subir o node group.
  # Mesmos 2 vCPU / 4 GiB do t3.medium, e disponível nas 3 AZs de us-east-1.
  # Evite os t4g.*: são ARM (Graviton) e a imagem é buildada para amd64.
  # Numa conta em plano pago, t3.medium volta a ser a escolha natural.
  description = "Tipos de instância do managed node group. Precisa ser free-tier-eligible se a conta estiver no plano gratuito."
  type        = list(string)
  default     = ["c7i-flex.large"]
}

variable "node_group_size" {
  description = "Tamanho do managed node group. min >= 2 para o HPA ter onde espalhar."
  type = object({
    min     = number
    max     = number
    desired = number
  })
  default = {
    min     = 2
    max     = 4
    desired = 2
  }

  # Incoerência aqui passa no plan e só falha na API da AWS, depois de ~10 min
  # de apply — com o cluster já criado e cobrando.
  validation {
    condition = (
      var.node_group_size.min <= var.node_group_size.desired &&
      var.node_group_size.desired <= var.node_group_size.max &&
      var.node_group_size.min >= 1
    )
    error_message = "node_group_size precisa satisfazer 1 <= min <= desired <= max."
  }
}

variable "db_state_bucket" {
  description = "Bucket S3 que guarda o state do repositório de banco de dados gerenciado."
  type        = string
  default     = "techchallenge-fiap-v1"
}

variable "db_state_key" {
  description = "Key do state do repositório de banco de dados. Um key por ambiente."
  type        = string
  default     = "db/prod/terraform.tfstate"
}

variable "db_state_region" {
  description = "Região do bucket de state do repositório de banco de dados."
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "owner/repo autorizado a assumir a role de deploy via OIDC. Vazio desliga o recurso."
  type        = string
  default     = "DevKaue/TechChallenge---Infraestrutura-Kubernetes-com-Terraform"
}

variable "github_deploy_policy_arns" {
  description = "Policies anexadas à role de deploy do CI. O apply do Terraform cria VPC, IAM, EKS e escreve no state S3, o que exige permissão ampla. Restrinja numa conta real."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

variable "cluster_admin_arns" {
  description = "ARNs de IAM com acesso admin ao cluster. Vazio = só quem criou."
  type        = list(string)
  default     = []
}

variable "cluster_readonly_arns" {
  description = "ARNs de IAM que recebem acesso somente-leitura ao namespace techchallenge (via grupo RBAC techchallenge:readonly)."
  type        = list(string)
  default     = []
}
