variable "name" {
  description = "Tiền tố tên tài nguyên, ví dụ \"taskhub\" → taskhub-vpc, taskhub-public-a."
  type        = string
}

variable "vpc_cidr" {
  description = "Dải CIDR của VPC (lấy từ docs/network-plan.md của bạn)."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr phải là CIDR hợp lệ, ví dụ 10.20.0.0/16."
  }
}

variable "public_subnets" {
  description = "Subnet public. Khóa là hậu tố tên (a, b…) → taskhub-public-a; giá trị là AZ và CIDR."
  type = map(object({
    az   = string
    cidr = string
  }))

  validation {
    condition     = alltrue([for s in values(var.public_subnets) : can(cidrhost(s.cidr, 0))])
    error_message = "Mỗi public subnet phải có cidr hợp lệ, ví dụ 10.20.1.0/24."
  }
}

variable "private_subnets" {
  description = "Như public_subnets, cho subnet private (không có route ra Internet)."
  type = map(object({
    az   = string
    cidr = string
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.private_subnets) : can(cidrhost(s.cidr, 0))])
    error_message = "Mỗi private subnet phải có cidr hợp lệ, ví dụ 10.20.11.0/24."
  }
}
