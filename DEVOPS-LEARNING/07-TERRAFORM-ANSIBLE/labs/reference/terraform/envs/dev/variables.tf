variable "project" {
  description = "Tên dự án: tiền tố tên tài nguyên và tag Project."
  type        = string
  default     = "taskhub"
}

variable "env" {
  description = "Tên môi trường: tag Env và một phần đường dẫn Parameter Store / log group."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Region triển khai."
  type        = string
  default     = "ap-southeast-1"
}

variable "owner" {
  description = "Giá trị tag Owner (tên của bạn, không dấu)."
  type        = string
}

variable "github_repo" {
  description = "Repo GitHub được phép deploy, dạng <user>/<repo> — dùng trong điều kiện sub của OIDC."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repo))
    error_message = "github_repo phải có dạng <user>/<repo>, ví dụ phuong-dev/taskhub."
  }
}

variable "alert_email" {
  description = "Email nhận cảnh báo từ SNS (phải bấm link xác nhận trong email)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email không giống một địa chỉ email."
  }
}

variable "instance_type" {
  description = "Loại EC2."
  type        = string
  default     = "t3.small"
}

variable "vpc_cidr" {
  description = "CIDR của VPC — lấy từ docs/network-plan.md."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnets" {
  description = "Subnet public — khóa là hậu tố tên (taskhub-public-a…), giá trị là AZ và CIDR (docs/network-plan.md)."
  type = map(object({
    az   = string
    cidr = string
  }))
  default = {
    a = { az = "ap-southeast-1a", cidr = "10.20.1.0/24" }
    b = { az = "ap-southeast-1b", cidr = "10.20.2.0/24" }
  }
}

variable "private_subnets" {
  description = "Subnet private (dự phòng cho RDS) — cùng cấu trúc với public_subnets."
  type = map(object({
    az   = string
    cidr = string
  }))
  default = {
    a = { az = "ap-southeast-1a", cidr = "10.20.11.0/24" }
    b = { az = "ap-southeast-1b", cidr = "10.20.12.0/24" }
  }
}

variable "app_subnet_key" {
  description = "Khóa của subnet public đặt EC2 (một khóa trong public_subnets)."
  type        = string
  default     = "a"

  validation {
    condition     = contains(keys(var.public_subnets), var.app_subnet_key)
    error_message = "app_subnet_key phải là một khóa có trong public_subnets (ví dụ \"a\")."
  }
}

variable "postgres_password_version" {
  description = "Tăng số này (1 → 2) để Terraform ghi một mật khẩu ngẫu nhiên MỚI vào Parameter Store."
  type        = number
  default     = 1
}
