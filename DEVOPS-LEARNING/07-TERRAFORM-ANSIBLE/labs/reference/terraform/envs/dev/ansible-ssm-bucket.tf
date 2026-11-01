# Bucket trung chuyển file cho Ansible connection amazon.aws.aws_ssm (Lab 03):
# Ansible tải file lên đây, EC2 tải về bằng presigned URL (curl). Chỉ chứa file tạm.

resource "aws_s3_bucket" "ansible_ssm" {
  bucket = "${local.name_prefix}-ansible-ssm-${local.account_id}"

  # Chỉ có file tạm → cho phép `terraform destroy` xóa cả bucket còn object.
  # (Ngược hẳn với bucket backup ở bootstrap/ — prevent_destroy.)
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    id     = "expire-transfer-files-after-1-day"
    status = "Enabled"

    filter {}

    expiration {
      days = 1
    }
  }

  rule {
    id     = "abort-incomplete-multipart-after-1-day"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "ansible_ssm_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.ansible_ssm.arn, "${aws_s3_bucket.ansible_ssm.arn}/*"]

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

resource "aws_s3_bucket_policy" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id
  policy = data.aws_iam_policy_document.ansible_ssm_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.ansible_ssm]
}
