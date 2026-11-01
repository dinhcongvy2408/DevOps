# Máy chủ ứng dụng taskhub: Security Group + IAM role cho EC2 + một EC2 Ubuntu 24.04.
# Terraform chỉ dựng "cái máy". Cài Docker, chép compose, chạy deploy.sh là việc của Ansible.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------------------------------
# AMI: tra qua SSM public parameter của Canonical (không hard-code ami-xxxx theo region)
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "ubuntu_ami" {
  name = var.ami_ssm_parameter
}

# -----------------------------------------------------------------------------
# Security Group: chỉ HTTP từ Internet, không có SSH
# -----------------------------------------------------------------------------

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web-sg"
  description = "taskhub web: HTTP from Internet, no SSH (use SSM)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-web-sg"
  }
}

# Mỗi rule một resource: thêm/bớt cổng không làm Terraform viết lại cả Security Group.
resource "aws_vpc_security_group_ingress_rule" "web" {
  for_each = toset([for p in var.ingress_ports : tostring(p)])

  security_group_id = aws_security_group.web.id
  description       = "TCP ${each.value} from Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
}

# Terraform XÓA rule egress mặc định "allow all" khi tạo SG, nên phải khai báo lại.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound IPv4: apt, GHCR, SSM, CloudWatch"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# -----------------------------------------------------------------------------
# IAM: role taskhub-ec2-role (giống hệt bản tạo tay ở 06-AWS bài 02/04/05)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    sid     = "Ec2CanAssumeThisRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# SSM Agent đăng ký với Systems Manager → Session Manager, Run Command (deploy), Ansible aws_ssm.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_app" {
  statement {
    sid       = "ReadTaskhubParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter${var.parameter_path_prefix}/*"]
  }

  # Docker daemon (log driver awslogs) dùng quyền này. Log group do Terraform tạo sẵn
  # nên KHÔNG cấp logs:CreateLogGroup.
  statement {
    sid       = "WriteTaskhubLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${local.account_id}:log-group:${var.log_group_prefix}/*:*"]
  }
}

resource "aws_iam_role_policy" "ec2_app" {
  name   = "${var.name_prefix}-ec2-app"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_app.json
}

data "aws_iam_policy_document" "ec2_s3_backup" {
  statement {
    sid       = "ListOnlyPgDumpsPrefix"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.backup_bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["pg-dumps/*"]
    }
  }

  # Không có DeleteObject: máy bị chiếm vẫn không xóa được bản backup.
  statement {
    sid       = "ReadWritePgDumps"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["arn:aws:s3:::${var.backup_bucket_name}/pg-dumps/*"]
  }
}

resource "aws_iam_role_policy" "ec2_s3_backup" {
  name   = "${var.name_prefix}-ec2-s3-backup"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_s3_backup.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-ec2-role"
  role = aws_iam_role.ec2.name
}

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------

resource "aws_instance" "app" {
  # insecure_value: AMI ID không phải bí mật; dùng `value` thì plan hiện "(sensitive value)".
  ami                    = data.aws_ssm_parameter.ubuntu_ami.insecure_value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Không có user_data: Ubuntu 24.04 đã có SSM Agent (snap), curl và python3 —
  # đủ để Ansible (connection aws_ssm) vào máy và cài phần còn lại.

  # IMDSv2 bắt buộc; hop limit 1 → container (thêm một bước mạng qua bridge) không lấy được
  # token IMDS, tức không mượn được quyền của instance role. Docker daemon trên host vẫn dùng được.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.name_prefix}-app-root"
    }
  }

  tags = {
    Name = "${var.name_prefix}-app"
  }

  lifecycle {
    # Canonical phát hành AMI mới thường xuyên → parameter đổi giá trị → không có dòng này,
    # một lần `apply` bình thường sẽ THAY THẾ máy (mất database trên ổ gốc).
    # Muốn lên AMI mới thì chủ động: terraform apply -replace=module.app_server.aws_instance.app
    ignore_changes = [ami]
  }
}
