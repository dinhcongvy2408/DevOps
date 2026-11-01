# bootstrap/ — tài nguyên SỐNG LÂU của taskhub: bucket state + bucket backup.
# Chạy MỘT lần (hoặc rất hiếm), không bao giờ `destroy` cùng hạ tầng hằng ngày.
#
# State của thư mục này để LOCAL lúc đầu: bucket state chưa tồn tại thì không thể lưu state
# vào nó ("con gà – quả trứng"). Sau lần apply đầu, chuyển state lên chính bucket vừa tạo,
# key bootstrap/terraform.tfstate — xem backend.tf.example.

terraform {
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
