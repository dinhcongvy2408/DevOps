# Module chỉ khai báo provider cần dùng và phiên bản TỐI THIỂU.
# Root module (envs/dev) mới là nơi chốt phiên bản cụ thể (~> 6.0) và cấu hình provider.

terraform {
  # Phiên bản Terraform TỐI THIỂU module cần (tflint: terraform_required_version).
  # Root module mới chốt dải hẹp (~> 1.17).
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
