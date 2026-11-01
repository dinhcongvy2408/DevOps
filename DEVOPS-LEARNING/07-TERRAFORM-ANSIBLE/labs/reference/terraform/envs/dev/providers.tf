provider "aws" {
  region = var.region

  # Gắn vào MỌI tài nguyên provider này tạo (kể cả ổ EBS gốc của EC2).
  # find-leftovers.sh và Cost Explorer dựa vào các tag này.
  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
