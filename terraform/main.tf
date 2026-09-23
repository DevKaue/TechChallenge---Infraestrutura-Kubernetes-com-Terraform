data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"

  # 3 AZ: o topologySpreadConstraints por zona do overlay aws precisa de mais de
  # uma para fazer sentido, e o RDS exige subnet group multi-AZ.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
