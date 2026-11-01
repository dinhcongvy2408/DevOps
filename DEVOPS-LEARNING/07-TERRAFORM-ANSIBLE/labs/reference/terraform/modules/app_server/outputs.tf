output "instance_id" {
  description = "ID của EC2 taskhub-app."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "IPv4 public tự cấp — ĐỔI mỗi lần stop/start hoặc tạo lại máy."
  value       = aws_instance.app.public_ip
}

output "security_group_id" {
  description = "ID của taskhub-web-sg."
  value       = aws_security_group.web.id
}

output "role_name" {
  description = "Tên IAM role của EC2."
  value       = aws_iam_role.ec2.name
}
