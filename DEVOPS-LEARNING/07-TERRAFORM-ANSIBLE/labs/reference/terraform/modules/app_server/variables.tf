variable "name_prefix" {
  description = "Tiền tố tên tài nguyên, ví dụ \"taskhub\" → taskhub-app, taskhub-web-sg, taskhub-ec2-role."
  type        = string
}

variable "region" {
  description = "Region — dùng để dựng ARN trong IAM policy."
  type        = string
}

variable "vpc_id" {
  description = "VPC chứa Security Group."
  type        = string
}

variable "subnet_id" {
  description = "Subnet PUBLIC đặt EC2 (cần đường ra Internet cho apt, GHCR, SSM, CloudWatch)."
  type        = string
}

variable "instance_type" {
  description = "Loại EC2. t3.small = 2 vCPU, 2 GiB — vừa đủ cho Spring Boot + PostgreSQL + nginx."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Dung lượng ổ gốc gp3 (GiB)."
  type        = number
  default     = 20
}

variable "ami_ssm_parameter" {
  description = "SSM public parameter do Canonical công bố, trỏ tới AMI Ubuntu 24.04 mới nhất."
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "ingress_ports" {
  description = "Cổng TCP mở từ Internet. KHÔNG thêm 22 — vào máy bằng SSM Session Manager."
  type        = list(number)
  default     = [80]

  validation {
    condition     = !contains(var.ingress_ports, 22)
    error_message = "Không mở port 22 ra Internet. Dùng SSM Session Manager."
  }
}

variable "parameter_path_prefix" {
  description = "Tiền tố Parameter Store EC2 được đọc, ví dụ \"/taskhub/dev\"."
  type        = string
}

variable "log_group_prefix" {
  description = "Tiền tố log group EC2 được ghi, ví dụ \"/taskhub/dev\"."
  type        = string
}

variable "backup_bucket_name" {
  description = "Bucket backup (tạo ở bootstrap/). EC2 chỉ được đọc/ghi prefix pg-dumps/."
  type        = string
}
