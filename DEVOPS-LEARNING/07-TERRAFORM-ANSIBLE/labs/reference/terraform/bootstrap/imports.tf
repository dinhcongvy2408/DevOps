# Đưa bucket backup tạo tay ở 06-AWS bài 05 vào quản lý của Terraform — KHÔNG tạo lại,
# không mất object nào. Mỗi cấu hình con của bucket là một resource riêng nên cần import riêng.
#
# ⚠️ Chỉ giữ file này nếu bucket taskhub-backups-<account-id> VẪN CÒN
#    (kiểm tra: aws s3api head-bucket --bucket taskhub-backups-<account-id>).
#    Bucket đã bị xóa → xóa file này trước khi plan, nếu không plan báo lỗi
#    "Cannot import non-existent remote object".
#
# Sau khi `terraform apply` import thành công, các block này không còn tác dụng gì nữa —
# có thể xóa file (hoặc giữ làm tài liệu: import đã xong thì Terraform bỏ qua).

import {
  to = aws_s3_bucket.backups
  id = local.backup_bucket_name
}

import {
  to = aws_s3_bucket_versioning.backups
  id = local.backup_bucket_name
}

import {
  to = aws_s3_bucket_public_access_block.backups
  id = local.backup_bucket_name
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.backups
  id = local.backup_bucket_name
}

import {
  to = aws_s3_bucket_lifecycle_configuration.backups
  id = local.backup_bucket_name
}

import {
  to = aws_s3_bucket_policy.backups
  id = local.backup_bucket_name
}
