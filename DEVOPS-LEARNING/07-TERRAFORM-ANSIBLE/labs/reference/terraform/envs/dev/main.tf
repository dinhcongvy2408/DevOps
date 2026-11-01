# Root module của môi trường dev. Mọi thứ ở đây xóa được bằng MỘT lệnh `terraform destroy`.
# Bucket state và bucket backup KHÔNG ở đây — chúng thuộc lớp bền vững bootstrap/.

data "aws_caller_identity" "current" {}

locals {
  name_prefix = var.project
  account_id  = data.aws_caller_identity.current.account_id
  path_prefix = "/${var.project}/${var.env}" # /taskhub/dev

  # Bucket backup do bootstrap/ quản lý. Tham chiếu theo TÊN (quy ước đặt tên),
  # không theo resource — hai lớp có state riêng, không phụ thuộc vòng đời của nhau.
  backup_bucket_name = "${var.project}-backups-${local.account_id}"
}

module "network" {
  source = "../../modules/network"

  name            = local.name_prefix
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

module "app_server" {
  source = "../../modules/app_server"

  name_prefix           = local.name_prefix
  region                = var.region
  vpc_id                = module.network.vpc_id
  subnet_id             = module.network.public_subnet_ids[var.app_subnet_key]
  instance_type         = var.instance_type
  parameter_path_prefix = local.path_prefix
  log_group_prefix      = local.path_prefix
  backup_bucket_name    = local.backup_bucket_name
}

# -----------------------------------------------------------------------------
# Mật khẩu PostgreSQL trong Parameter Store — KHÔNG BAO GIỜ nằm trong state hay plan
# -----------------------------------------------------------------------------

# Ephemeral resource: giá trị chỉ tồn tại trong bộ nhớ khi Terraform chạy, không ghi ra file nào.
# special = false: mật khẩu nằm trong .env và URL JDBC — tránh ký tự $, #, ", ' gây lỗi parse.
ephemeral "random_password" "postgres" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "postgres_password" {
  name        = "${local.path_prefix}/postgres-password"
  description = "Mat khau PostgreSQL cua taskhub - deploy.sh doc bang get-parameter --with-decryption"
  type        = "SecureString" # mã hóa bằng KMS key mặc định aws/ssm

  # Write-only: Terraform gửi giá trị cho AWS nhưng không lưu vào state.
  # Provider chỉ ghi giá trị mới khi value_wo_version thay đổi (lần tạo đầu tiên, hoặc khi bạn tăng số).
  value_wo         = ephemeral.random_password.postgres.result
  value_wo_version = var.postgres_password_version
}
