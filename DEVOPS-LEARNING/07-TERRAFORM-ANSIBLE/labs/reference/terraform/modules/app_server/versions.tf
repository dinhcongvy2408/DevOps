terraform {
  # Phiên bản TỐI THIỂU (tflint: terraform_required_version). Root module chốt ~> 1.17.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
