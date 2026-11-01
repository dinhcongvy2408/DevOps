# Module `app_server`

Máy chủ ứng dụng `taskhub`: Security Group `<prefix>-web-sg` (chỉ HTTP, **không** port 22), IAM role + instance profile `<prefix>-ec2-role` (AmazonSSMManagedInstanceCore + inline `<prefix>-ec2-app` + inline `<prefix>-ec2-s3-backup`), một EC2 Ubuntu 24.04 (IMDSv2 bắt buộc, hop limit 1, gp3 mã hóa). Không có user data — Ansible cấu hình máy.

## Input

| Biến | Kiểu | Bắt buộc | Mặc định / ví dụ |
|---|---|---|---|
| `name_prefix` | string | ✅ | `"taskhub"` |
| `region` | string | ✅ | `"ap-southeast-1"` (dựng ARN trong policy) |
| `vpc_id` | string | ✅ | `module.network.vpc_id` |
| `subnet_id` | string | ✅ | subnet **public** (cần đường ra Internet) |
| `parameter_path_prefix` | string | ✅ | `"/taskhub/dev"` — EC2 đọc được `/taskhub/dev/*` |
| `log_group_prefix` | string | ✅ | `"/taskhub/dev"` — EC2 ghi được log group `/taskhub/dev/*` |
| `backup_bucket_name` | string | ✅ | `"taskhub-backups-<account-id>"` — chỉ prefix `pg-dumps/`, không có quyền xóa |
| `instance_type` | string | | `"t3.small"` |
| `root_volume_size` | number | | `20` |
| `ami_ssm_parameter` | string | | SSM public parameter Ubuntu 24.04 amd64 gp3 của Canonical |
| `ingress_ports` | list(number) | | `[80]` — `validation` từ chối `22` |

## Output

| Output | Mô tả |
|---|---|
| `instance_id` | ID của EC2 |
| `public_ip` | IPv4 public (đổi khi stop/start hoặc tạo lại máy) |
| `security_group_id` | ID của Security Group |
| `role_name` | Tên IAM role của EC2 |

`lifecycle { ignore_changes = [ami] }`: AMI mới của Canonical không tự thay máy. Lên AMI mới: `terraform apply -replace=module.app_server.aws_instance.app`.
