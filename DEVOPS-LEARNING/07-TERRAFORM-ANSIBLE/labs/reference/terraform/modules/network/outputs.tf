output "vpc_id" {
  description = "ID của VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR của VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Map hậu tố → ID subnet public, ví dụ { a = \"subnet-…\", b = \"subnet-…\" }."
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  description = "Map hậu tố → ID subnet private."
  value       = { for k, s in aws_subnet.private : k => s.id }
}
