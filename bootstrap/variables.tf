variable "region" {
  description = "Região do bucket. Precisa bater com o `region` do backend de todos os repositórios que guardam state nele."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Prefixo do nome do bucket (<project>-tfstate-<conta>) e valor da tag Project."
  type        = string
  default     = "techchallenge"
}

variable "noncurrent_version_retention_days" {
  description = "Dias que uma versão antiga de state fica guardada antes de expirar. É a janela para desfazer um state corrompido."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 7
    error_message = "noncurrent_version_retention_days precisa ser pelo menos 7: menos que isso não dá tempo de perceber um state corrompido."
  }
}
