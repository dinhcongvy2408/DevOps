variable "region" {
  description = "Region chứa bucket state và bucket backup."
  type        = string
  default     = "ap-southeast-1"
}

variable "project" {
  description = "Tiền tố tên tài nguyên và giá trị tag Project."
  type        = string
  default     = "taskhub"
}

variable "owner" {
  description = "Giá trị tag Owner (tên của bạn, không dấu)."
  type        = string
}
