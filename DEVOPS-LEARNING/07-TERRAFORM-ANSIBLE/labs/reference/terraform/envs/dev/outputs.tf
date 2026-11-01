output "instance_id" {
  description = "ID của EC2 taskhub-app."
  value       = module.app_server.instance_id
}

output "public_ip" {
  description = "IPv4 public của EC2 — đổi sau mỗi lần destroy/apply hoặc stop/start."
  value       = module.app_server.public_ip
}

output "app_url" {
  description = "Giá trị cho GitHub variable APP_URL (environment production)."
  value       = "http://${module.app_server.public_ip}"
}

output "deploy_role_arn" {
  description = "Giá trị cho GitHub variable AWS_DEPLOY_ROLE_ARN (environment production)."
  value       = aws_iam_role.github_deploy.arn
}

output "ansible_ssm_bucket" {
  description = "Bucket trung chuyển cho Ansible connection aws_ssm (group_vars của Lab 03)."
  value       = aws_s3_bucket.ansible_ssm.bucket
}
