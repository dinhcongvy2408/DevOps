terraform {
  required_version = "~> 1.17" # write-only argument (value_wo) cần Terraform >= 1.11

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9" # ephemeral "random_password" có từ 3.7.0
    }
  }

  # Partial configuration: bucket (chứa account id) truyền lúc init, không ghi vào repo:
  #   terraform init -backend-config="bucket=taskhub-tfstate-$(aws sts get-caller-identity --query Account --output text)"
  # use_lockfile: khóa state bằng file envs/dev/terraform.tfstate.tflock trong cùng bucket
  # (DynamoDB locking đã deprecated).
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
