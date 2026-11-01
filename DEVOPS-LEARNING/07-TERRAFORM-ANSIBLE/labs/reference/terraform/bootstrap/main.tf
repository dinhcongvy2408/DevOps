provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = "shared"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  state_bucket_name  = "${var.project}-tfstate-${local.account_id}"
  backup_bucket_name = "${var.project}-backups-${local.account_id}"
}

# =============================================================================
# 1. Bucket chứa Terraform state của envs/dev (và của chính bootstrap nếu chuyển lên)
# =============================================================================

resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket_name

  # Mất bucket này = mất state = Terraform "quên" toàn bộ hạ tầng đang chạy.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning: lỡ ghi hỏng / xóa state vẫn khôi phục được phiên bản trước.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state-after-90-days"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart-after-7-days"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle cho phiên bản noncurrent chỉ có nghĩa khi versioning đã bật.
  depends_on = [aws_s3_bucket_versioning.tfstate]
}

data "aws_iam_policy_document" "tfstate_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# =============================================================================
# 2. Bucket backup database (tạo tay ở 06-AWS bài 05, dùng cho pg_dump ở v5)
#    Nếu bucket từ v2 vẫn còn: imports.tf đưa nó vào quản lý của Terraform.
#    Nếu đã xóa: xóa file imports.tf, Terraform sẽ tạo mới.
# =============================================================================

resource "aws_s3_bucket" "backups" {
  bucket = local.backup_bucket_name

  # Bucket chứa DỮ LIỆU. Ghi đè tag Env của default_tags: bucket này phục vụ môi trường dev.
  tags = {
    Env = "dev"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Giống hệt 3 rule của 06-AWS bài 05 — nếu khác, plan sau khi import sẽ báo "update in-place".
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-noncurrent-after-30-days"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-multipart-after-7-days"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

data "aws_iam_policy_document" "backups_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.backups]
}
