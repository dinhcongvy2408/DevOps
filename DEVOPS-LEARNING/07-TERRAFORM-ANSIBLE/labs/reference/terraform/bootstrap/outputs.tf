output "state_bucket" {
  description = "Tên bucket chứa Terraform state — chép vào backend \"s3\" của envs/dev/versions.tf."
  value       = aws_s3_bucket.tfstate.bucket
}

output "backup_bucket" {
  description = "Tên bucket backup database (envs/dev cấp quyền ghi prefix pg-dumps/ cho EC2)."
  value       = aws_s3_bucket.backups.bucket
}

output "init_command_envs_dev" {
  description = "Lệnh init cho envs/dev (backend partial configuration: bucket truyền lúc init)."
  value       = "terraform -chdir=../envs/dev init -backend-config=\"bucket=${aws_s3_bucket.tfstate.bucket}\""
}
