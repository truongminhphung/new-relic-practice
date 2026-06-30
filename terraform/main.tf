provider "aws" {
  region = var.aws_region
}

locals {
  name = "etl-job"

  tags = {
    Project   = "practice-new-relic"
    ManagedBy = "terraform"
  }
}
