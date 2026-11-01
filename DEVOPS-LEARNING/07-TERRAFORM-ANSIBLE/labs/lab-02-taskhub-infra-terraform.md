# Lab 02 — Viết lại hạ tầng `taskhub` bằng Terraform

> ⏱️ ~5 giờ (tuần 15: Phần A ~3h · tuần 16: Phần B ~2h) · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [bài 02 — Terraform cơ bản](../02-terraform-basics.md), [Lab 01](lab-01-terraform-local-docker.md); Phần B cần thêm [bài 03 — State & backend](../03-terraform-state-backend.md) và [bài 04 — Module & môi trường](../04-terraform-modules-environments.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (Terraform, AWS CLI v2, `aws login` profile `taskhub`), `[AWS Console]` để đối chiếu
> Dùng trong: milestone [v4 — Terraform + Ansible](../../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) · Tiếp theo: [Lab 03 — Ansible qua SSM](lab-03-ansible-ssm.md)

Ở tuần 11–14 bạn dựng `taskhub` bằng tay (console + lệnh CLI) rồi xóa cũng bằng tay. Lab này mô tả **đúng hạ tầng đó** bằng code Terraform: tuần 15 viết một cấu hình **phẳng** với state cục bộ để thấy từng tài nguyên; tuần 16 tách thành **module**, đưa state lên **S3** và tách riêng lớp dữ liệu không được xóa. Kết thúc lab, cả hạ tầng dựng bằng một lệnh và xóa bằng một lệnh.

## Mục lục

- [0. Trước khi bắt đầu](#0-trước-khi-bắt-đầu)
- [1. Kiến trúc và bảng ánh xạ "tay → Terraform"](#1-kiến-trúc-và-bảng-ánh-xạ-tay--terraform)
- [Phần A — Tuần 15: cấu hình phẳng, state cục bộ](#phần-a--tuần-15-cấu-hình-phẳng-state-cục-bộ)
  - [A1. Khung thư mục và provider](#a1-khung-thư-mục-và-provider)
  - [A2. Mạng: VPC, subnet, IGW, route table](#a2-mạng-vpc-subnet-igw-route-table)
  - [A3. Security Group và IAM role của EC2](#a3-security-group-và-iam-role-của-ec2)
  - [A4. EC2](#a4-ec2)
  - [A5. Mật khẩu database không nằm trong state](#a5-mật-khẩu-database-không-nằm-trong-state)
  - [A6. OIDC, CloudWatch, SNS, outputs](#a6-oidc-cloudwatch-sns-outputs)
  - [A7. Checklist đọc plan](#a7-checklist-đọc-plan)
  - [A8. Vòng xóa – dựng lần 1](#a8-vòng-xóa--dựng-lần-1)
- [Phần B — Tuần 16: lớp bền, module, backend S3](#phần-b--tuần-16-lớp-bền-module-backend-s3)
  - [B1. `bootstrap/`: bucket state và bucket backup](#b1-bootstrap-bucket-state-và-bucket-backup)
  - [B2. Tách module mà không phá hạ tầng: `moved`](#b2-tách-module-mà-không-phá-hạ-tầng-moved)
  - [B3. Chuyển state của `envs/dev` lên S3](#b3-chuyển-state-của-envsdev-lên-s3)
  - [B4. Bucket cho Ansible và outputs cho GitHub](#b4-bucket-cho-ansible-và-outputs-cho-github)
  - [B5. Vòng xóa – dựng lần 2 (một lệnh)](#b5-vòng-xóa--dựng-lần-2-một-lệnh)
- [2. Thử nghiệm bắt buộc](#2-thử-nghiệm-bắt-buộc)
- [3. Kết quả mong đợi](#3-kết-quả-mong-đợi)
- [4. Lỗi thường gặp](#4-lỗi-thường-gặp)
- [5. ⚠️ Dọn dẹp](#5-️-dọn-dẹp)
- [6. Câu hỏi sau lab](#6-câu-hỏi-sau-lab)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 0. Trước khi bắt đầu

### 0.1. 💰 Ước tính chi phí

Đơn giá Singapore (`ap-southeast-1`) đã kiểm tra ngày 2026-10-31 — chi tiết và nguồn ở [06-AWS bài 11](../../06-AWS/11-putting-it-together.md):

| Tài nguyên | Đơn giá | Ghi chú |
|---|---|---|
| EC2 `t3.small` | 0,0264 USD/giờ | Chỉ tính khi **running** |
| Public IPv4 | 0,005 USD/giờ | Tính cả khi không dùng |
| EBS gp3 20 GiB | 0,096 USD/GB-tháng ≈ 1,92 USD/tháng | Tính theo giờ tồn tại, kể cả khi EC2 stop |
| VPC, subnet, IGW, route table, SG, IAM, OIDC | 0 | Không có NAT Gateway |
| CloudWatch: 1 log group, 2 alarm; SNS email | Trong mức miễn phí | Xem bài 10 Module 06 |
| S3: bucket state, bucket backup, bucket Ansible | Vài KB–MB → gần 0 | Request PUT/GET của Terraform rất ít |

| Kịch bản | Ước tính |
|---|---|
| Một buổi học 3 giờ rồi `destroy` | ≈ 0,0264×3 + 0,005×3 + 20×0,096×3/730 ≈ **0,10 USD** |
| Quên `destroy` một tuần | ≈ (0,0264 + 0,005)×168 + 20×0,096×168/730 ≈ **5,7 USD** |

Mọi phí trừ vào credit của Free plan. Quy tắc của module: **cuối mỗi buổi có AWS là `terraform destroy`** — lợi ích lớn nhất của IaC với túi tiền của bạn.

### 0.2. Điều kiện

| Điều kiện | Kiểm tra `[WSL]` | Nếu chưa đạt |
|---|---|---|
| Hạ tầng tay của v2/v3 đã xóa | `~/devops-lab/06-aws/find-leftovers.sh` — chỉ còn bucket `taskhub-backups-<account-id>` | Dọn theo [v3 §11](../../12-PRACTICAL-PROJECT/milestones/v3-cd.md#11-dọn-dẹp). Còn role, OIDC provider, log group… → `apply` báo `EntityAlreadyExists` |
| VPC tay của Lab 01 Module 06 đã xóa | `aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc --query 'Vpcs[].VpcId'` → `[]` | Xóa theo mục "Giữ lại hay dọn dẹp?" của [Lab 01 Module 06](../../06-AWS/labs/lab-01-vpc-by-hand.md) — để không có hai `taskhub-vpc` |
| Terraform ≥ 1.17 | `terraform version` | [Bài 02 §4.1](../02-terraform-basics.md#41--cài-terraform-trên-wsl-ubuntu-2404) |
| Đăng nhập AWS | `export AWS_PROFILE=taskhub && aws sts get-caller-identity` | `aws login --profile taskhub` ([06-AWS bài 06](../../06-AWS/06-aws-cli.md)) |
| Danh sách tài nguyên tay | File `inventory.md` từ [bài 01](../01-iac-concepts.md) | Làm bài tập của bài 01 trước — đó là "đề bài" của lab này |
| Repo `taskhub` sạch, đang ở nhánh mới | `git status`; `git switch -c feat/terraform-infra` | — |

### 0.3. Lộ trình hai tuần

| Tuần | Phần | Kết quả |
|---|---|---|
| 15 | A1–A8 | Một thư mục `infra/terraform/envs/dev`, các file `.tf` phẳng, state **cục bộ** — dựng/xóa được toàn bộ hạ tầng |
| 16 | B1–B5 | Thêm `bootstrap/` (bucket state + bucket backup), tách 2 module `network`/`app_server` bằng `moved`, state lên S3 với `use_lockfile` |

Code hoàn chỉnh để **so sánh sau khi tự viết**: [reference/terraform/](reference/terraform/README.md).

---

## 1. Kiến trúc và bảng ánh xạ "tay → Terraform"

```text
                          ┌──────────── lớp BỀN: infra/terraform/bootstrap (Phần B) ────────────┐
                          │ S3 taskhub-tfstate-<acct>  (state, versioning, prevent_destroy)     │
                          │ S3 taskhub-backups-<acct>  (import từ 06-AWS bài 05, prevent_destroy)│
                          └─────────────────────────────────────────────────────────────────────┘
 ┌──────────────────────── lớp TẠM: infra/terraform/envs/dev — destroy một lệnh ────────────────────────┐
 │ VPC 10.20.0.0/16 ─ IGW ─ public-rt(0.0.0.0/0→IGW) ─ public-a/b      private-rt(local) ─ private-a/b    │
 │                                │                                                                       │
 │                      EC2 taskhub-app (t3.small, Ubuntu 24.04, IMDSv2, gp3 20 GiB)                       │
 │                      SG taskhub-web-sg (80 từ Internet, KHÔNG 22) · role taskhub-ec2-role               │
 │ SSM /taskhub/dev/postgres-password (value_wo)   OIDC GitHub + role taskhub-github-deploy               │
 │ CloudWatch /taskhub/dev/app (7 ngày) · alarm taskhub-cpu-high, taskhub-status-check · SNS taskhub-alerts│
 │ S3 taskhub-ansible-ssm-<acct> (force_destroy — Lab 03)                                                  │
 └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Đối chiếu với `inventory.md` của bạn:

| Tài nguyên tạo tay (Module 06) | Resource Terraform | Phần |
|---|---|---|
| VPC, IGW | `aws_vpc`, `aws_internet_gateway` | A2 |
| 4 subnet | `aws_subnet` (`for_each` trên map khóa `a`/`b`) | A2 |
| 2 route table + gắn subnet | `aws_route_table`, `aws_route_table_association` | A2 |
| SG `taskhub-web-sg` | `aws_security_group` + `aws_vpc_security_group_ingress_rule` / `egress_rule` | A3 |
| Role, policy, instance profile của EC2 | `aws_iam_role`, `aws_iam_role_policy_attachment`, `aws_iam_role_policy` ×2, `aws_iam_instance_profile`, data `aws_iam_policy_document` | A3 |
| EC2 (AMI tra từ SSM public parameter) | data `aws_ssm_parameter` + `aws_instance` | A4 |
| Tham số mật khẩu | `ephemeral "random_password"` + `aws_ssm_parameter` (`value_wo`) | A5 |
| OIDC provider + role deploy | `aws_iam_openid_connect_provider`, `aws_iam_role`, `aws_iam_role_policy` | A6 |
| Log group, 2 alarm, topic + email | `aws_cloudwatch_log_group`, `aws_cloudwatch_metric_alarm` ×2, `aws_sns_topic`, `aws_sns_topic_subscription` | A6 |
| Bucket backup (đã có dữ liệu) | `import {}` + `aws_s3_bucket` và 5 resource con | B1 |
| *(mới)* Bucket state | `aws_s3_bucket` + versioning, public access block, SSE, lifecycle, policy | B1 |
| *(mới)* Bucket trung chuyển của Ansible | `aws_s3_bucket` (`force_destroy = true`) | B4 |

---

## Phần A — Tuần 15: cấu hình phẳng, state cục bộ

Phần A cố ý chưa dùng module, chưa dùng backend S3: mỗi file `.tf` là một nhóm tài nguyên bạn đã từng tạo tay, đọc từ trên xuống là hiểu.

### A1. Khung thư mục và provider

`[WSL]`

```bash
cd ~/projects/taskhub
mkdir -p infra/terraform/envs/dev && cd infra/terraform/envs/dev
```

`versions.tf` — **chưa** có khối `backend` (state nằm ở file `terraform.tfstate` cạnh code):

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}
```

`providers.tf` — `default_tags` gắn tag cho **mọi** tài nguyên, kể cả ổ EBS gốc của EC2:

```hcl
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
```

`variables.tf`: khai báo `project` (mặc định `"taskhub"`), `env` (`"dev"`), `region` (`"ap-southeast-1"`), `owner`, `github_repo`, `alert_email`, `instance_type` (`"t3.small"`), `vpc_cidr`, `public_subnets`, `private_subnets` (kiểu `map(object({ az = string, cidr = string }))`, khóa `a`/`b` — xem A2), `app_subnet_key` (`"a"`) — **mỗi biến có `type` và `description`**; CIDR lấy từ `docs/network-plan.md` của bạn. Giá trị riêng đặt trong `terraform.tfvars` (không commit):

```hcl
owner       = "phuong"
github_repo = "phuong-dev/taskhub"
alert_email = "you@example.com"
```

`.gitignore` của `infra/terraform/` phải có `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfvars` (trừ `*.tfvars.example`), `*.tfplan` — và **không** có `.terraform.lock.hcl`.

```bash
terraform init
ls -a                              # .terraform/  .terraform.lock.hcl
grep -A2 'provider "registry.terraform.io/hashicorp/aws"' .terraform.lock.hcl
```

Đầu ra mẫu (minh họa — phiên bản trên máy bạn có thể mới hơn):

```text
provider "registry.terraform.io/hashicorp/aws" {
  version     = "6.71.0"
  constraints = "~> 6.0"
```

❓ `constraints` và `version` khác nhau thế nào? Vì sao file này phải được commit?

### A2. Mạng: VPC, subnet, IGW, route table

`network.tf` — đặt tên resource `this` cho thứ chỉ có một (như [bài 02 §4.12](../02-terraform-basics.md#412--cùng-ý-tưởng-đổi-sang-aws)), dùng `for_each` trên **map** cho subnet. Biến trong `variables.tf`:

```hcl
variable "public_subnets" {
  description = "Subnet public — khóa là hậu tố tên (taskhub-public-a…), giá trị là AZ và CIDR."
  type = map(object({
    az   = string
    cidr = string
  }))
  default = {
    a = { az = "ap-southeast-1a", cidr = "10.20.1.0/24" }
    b = { az = "ap-southeast-1b", cidr = "10.20.2.0/24" }
  }
}
# private_subnets: cùng kiểu, 10.20.11.0/24 và 10.20.12.0/24
```

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${each.key}" # khóa "a" → taskhub-public-a
    Tier = "public"
  }
}
```

Tự viết tiếp (đối chiếu [06-AWS bài 03](../../06-AWS/03-vpc-networking.md)):

- `aws_subnet.private` — giống trên, `map_public_ip_on_launch = false`, tên `taskhub-private-a/b`.
- `aws_route_table.public` có khối `route { cidr_block = "0.0.0.0/0"  gateway_id = aws_internet_gateway.this.id }`; `aws_route_table.private` **không** có route nào (route `local` AWS tự thêm).
- `aws_route_table_association.public` / `.private` với `for_each = aws_subnet.public` (lặp qua **resource**, cùng khóa `a`/`b`), `subnet_id = each.value.id`.

```bash
terraform fmt
terraform validate
terraform plan -out=tfplan
```

Đầu ra cuối plan (minh họa):

```text
Plan: 12 to add, 0 to change, 0 to destroy.
```

Tự đếm trước khi tin con số: 1 VPC + 1 IGW + 4 subnet + 2 route table + 4 association = 12. Route `0.0.0.0/0` viết **bên trong** route table nên không phải resource riêng. Con số khác 12 → **đừng apply**, tìm xem resource nào thiếu/thừa. Sau khi khớp:

```bash
terraform apply tfplan            # ⚠️ tạo tài nguyên (miễn phí ở bước này)
aws ec2 describe-subnets --filters Name=tag:Project,Values=taskhub \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' \
  --output table
```

> 💡 Vì sao `for_each` trên map mà không phải `count` trên list (như [bài 02](../02-terraform-basics.md) và [bài 04](../04-terraform-modules-environments.md))? Địa chỉ trong state là `aws_subnet.public["a"]`, không phải `[0]`. Với `count`, bỏ AZ **đầu** danh sách làm mọi phần tử sau dịch chỉ số → Terraform đòi **thay thế** subnet còn lại — kéo theo EC2 nằm trong đó. Chạy `terraform state list | grep subnet` để thấy địa chỉ có khóa.

### A3. Security Group và IAM role của EC2

`security.tf`:

```hcl
resource "aws_security_group" "web" {
  name        = "${var.project}-web-sg"
  description = "taskhub web: HTTP from Internet, no SSH (use SSM)"
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.project}-web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "TCP 80 from Internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "All outbound IPv4: apt, GHCR, SSM, CloudWatch"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

❓ Thử bỏ resource `egress_rule` rồi `plan`/`apply`: EC2 ở bước A4 còn đăng ký được với SSM không? (Gợi ý: Terraform **xóa** rule egress "allow all" mặc định khi tạo SG — đọc ghi chú của resource `aws_security_group` trong tài liệu provider.)

`iam-ec2.tf` — viết policy bằng data source `aws_iam_policy_document` thay vì chuỗi JSON: Terraform kiểm tra cú pháp lúc `plan` và chèn biến dễ dàng. Viết lại **đúng** những gì bạn đã có ở Module 06:

| Resource | Nội dung | So với |
|---|---|---|
| `aws_iam_role.ec2` (`taskhub-ec2-role`) | Trust policy: dịch vụ `ec2.amazonaws.com` được `sts:AssumeRole` | `iam/taskhub-ec2-trust.json` (reference-v3 của Module 06) |
| `aws_iam_role_policy_attachment.ssm_core` | `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` | Bài 04 Module 06 |
| `aws_iam_role_policy.ec2_app` (`taskhub-ec2-app`) | `ssm:GetParameter(s)` trên `parameter/taskhub/dev/*`; `logs:CreateLogStream`, `logs:PutLogEvents` trên `log-group:/taskhub/dev/*:*` | `iam/taskhub-ec2-app-policy.json` |
| `aws_iam_role_policy.ec2_s3_backup` (`taskhub-ec2-s3-backup`) | `s3:ListBucket` có điều kiện `s3:prefix = pg-dumps/*`; `s3:PutObject`, `s3:GetObject` trên `pg-dumps/*`; **không** có `DeleteObject` | [Bài 05 S3 Module 06](../../06-AWS/05-s3.md) |
| `aws_iam_instance_profile.ec2` | Cùng tên `taskhub-ec2-role` | Bài 04 Module 06 |

Mẫu một statement (account id lấy từ data source, **không** ghi cứng):

```hcl
data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  backup_bucket_name = "${var.project}-backups-${local.account_id}" # bucket đã có từ 06-AWS bài 05
}

data "aws_iam_policy_document" "ec2_app" {
  statement {
    sid       = "ReadTaskhubParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.region}:${local.account_id}:parameter/${var.project}/${var.env}/*"]
  }
  # statement WriteTaskhubLogs: tự viết
}
```

Kiểm tra JSON Terraform sinh ra **trước khi** apply: `terraform console` → `data.aws_iam_policy_document.ec2_app.json`. So từng dòng với file JSON của Module 06.

### A4. EC2

`ec2.tf`:

```hcl
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.insecure_value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[var.app_subnet_key].id # "a" → taskhub-public-a
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project}-app"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
```

Ba dòng cần giải thích được trước khi apply:

| Dòng | Vì sao |
|---|---|
| `insecure_value` thay vì `value` | Data source `aws_ssm_parameter` luôn đánh dấu `value` là sensitive → plan hiện `(sensitive value)` ở chỗ AMI, khó review. AMI ID không phải bí mật |
| Không có `user_data` | Ubuntu 24.04 có sẵn SSM Agent, `curl`, `python3` — đủ cho Ansible kết nối qua SSM ở [Lab 03](lab-03-ansible-ssm.md). Cài Docker/ứng dụng là việc của Ansible (chạy lại được, idempotent), không phải cloud-init (chạy một lần) |
| `ignore_changes = [ami]` | Canonical phát hành AMI mới thường xuyên → giá trị parameter đổi → không có dòng này, một lần `apply` bất kỳ sẽ **thay máy** và mất database trên ổ gốc. Muốn lên AMI mới thì chủ động `-replace` (thử nghiệm E2) |

```bash
terraform plan -out=tfplan        # đọc kỹ theo checklist A7
terraform apply tfplan            # ⚠️ BẮT ĐẦU TÍNH TIỀN: EC2 + IPv4 + EBS
INSTANCE_ID="$(terraform state show -no-color aws_instance.app | awk '$1=="id"{gsub(/"/,"",$3); print $3}')"
echo "$INSTANCE_ID"               # i-0... (A6 thêm output instance_id — từ đó dùng terraform output -raw)
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[].[InstanceId,PingStatus,PlatformName]' --output table
```

`PingStatus` = `Online` sau vài phút (minh họa — thời gian thực tế khác nhau). Rồi `aws ssm start-session --target "$INSTANCE_ID"` và trong `[EC2]`: `curl -s -o /dev/null -w '%{http_code}\n' http://169.254.169.254/latest/meta-data/` → `401` (IMDSv2 bắt buộc, gọi không có token bị từ chối — minh họa; tài liệu AWS chỉ nói request IMDSv1 sẽ thất bại).

### A5. Mật khẩu database không nằm trong state

Ở v2/v3 bạn tạo tham số bằng `aws ssm put-parameter`. Cách "tự nhiên" với Terraform — `value = var.db_password` — để lại mật khẩu **dạng chữ** trong file state. `sensitive = true` chỉ che màn hình, không che state ([bài 03](../03-terraform-state-backend.md)).

Terraform ≥ 1.11 có **write-only argument**: giá trị được gửi tới AWS nhưng **không bao giờ** ghi vào plan hay state. Kết hợp với **ephemeral resource** (giá trị chỉ sống trong bộ nhớ khi Terraform chạy) — mật khẩu không tồn tại ở bất kỳ file nào trên máy bạn:

`secrets.tf`:

```hcl
variable "postgres_password_version" {
  description = "Tăng số này để ghi một mật khẩu ngẫu nhiên MỚI vào Parameter Store."
  type        = number
  default     = 1
}

ephemeral "random_password" "postgres" {
  length  = 32
  special = false # mật khẩu đi vào .env và URL JDBC: tránh $ # " ' gây lỗi parse
}

resource "aws_ssm_parameter" "postgres_password" {
  name             = "/${var.project}/${var.env}/postgres-password"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.postgres.result
  value_wo_version = var.postgres_password_version
}
```

```bash
terraform apply                   # ⚠️ tạo tham số (tầng Standard, miễn phí)
terraform state show aws_ssm_parameter.postgres_password    # value_wo không có giá trị
grep -c "$(aws ssm get-parameter --name /taskhub/dev/postgres-password \
  --with-decryption --query Parameter.Value --output text)" terraform.tfstate   # 0
aws ssm get-parameter --name /taskhub/dev/postgres-password --with-decryption \
  --query Parameter.Value --output text | tr -d '\n' | wc -c                      # 32
```

Lệnh `grep -c` đếm số lần mật khẩu thật xuất hiện trong state — phải là **0**. (Lệnh giữ mật khẩu trong một đối số `grep` vài mili giây; không in nó ra màn hình.)

Câu hỏi then chốt: mỗi lần `plan`, ephemeral resource sinh một chuỗi **khác** — vậy sao mật khẩu thật không đổi theo? Vì provider chỉ ghi giá trị write-only khi **`value_wo_version` thay đổi** (lần tạo đầu, hoặc khi bạn tăng số). `deploy.sh` trên EC2 vẫn đọc mật khẩu bằng `aws ssm get-parameter --with-decryption` như ở v3 — Terraform không cần, và không thể, biết mật khẩu.

### A6. OIDC, CloudWatch, SNS, outputs

Viết theo đúng thông số đã dùng tay — đây là phần "dịch" thuần túy:

| File | Nội dung | Nguồn thông số |
|---|---|---|
| `github-oidc.tf` | `aws_iam_openid_connect_provider` (url `https://token.actions.githubusercontent.com`, `client_id_list = ["sts.amazonaws.com"]`, **không** cần `thumbprint_list`); role `taskhub-github-deploy` có trust `aud` = `sts.amazonaws.com`, `sub` = `repo:${var.github_repo}:environment:production`; inline policy 4 statement | `iam/taskhub-github-deploy-trust.json`, `-policy.json` (reference-v3 Module 06) |
| `monitoring.tf` | Log group `/taskhub/dev/app` retention 7 ngày; topic `taskhub-alerts` + subscription email; alarm `taskhub-cpu-high` (Average, 300 s, 2/2, > 80) và `taskhub-status-check` (Maximum, 60 s, 2/2, ≥ 1), cả hai `treat_missing_data = "notBreaching"`, `alarm_actions` và `ok_actions` trỏ topic, `dimensions = { InstanceId = aws_instance.app.id }` | [06-AWS bài 10 §8.7](../../06-AWS/10-cloudwatch.md) |
| `outputs.tf` | `instance_id`, `public_ip`, `app_url` (`"http://${aws_instance.app.public_ip}"`), `deploy_role_arn` (Phần B thêm `ansible_ssm_bucket`) | Biến GitHub của v3 |

Điểm dễ sai:

- Điều kiện của role deploy dùng khóa `ssm:resourceTag/Project`, **không phải** `aws:ResourceTag/Project` (ví dụ chính thức trong tài liệu Run Command — đã dùng ở v3).
- Sau `apply`, hộp thư nhận email "AWS Notification - Subscription Confirmation" → bấm xác nhận. Mỗi lần dựng lại từ đầu phải xác nhận lại.
- `terraform output` hiện `app_url`; `terraform output -raw app_url` cho giá trị không có dấu ngoặc kép — dùng trong script.

### A7. Checklist đọc plan

Áp dụng cho **mọi** `plan` từ nay về sau (cũng là checklist review PR hạ tầng):

- [ ] Dòng cuối `Plan: X to add, Y to change, Z to destroy` — Z khác 0 thì dừng lại hỏi "vì sao?".
- [ ] Không có `-/+` (destroy rồi tạo lại) với EC2 hoặc bất kỳ thứ gì chứa dữ liệu. Có → đọc dòng `# forces replacement` ngay dưới thuộc tính gây ra.
- [ ] Tên tài nguyên đúng quy ước (`taskhub-...`), region đúng `ap-southeast-1`.
- [ ] Security Group không có cổng 22, không có `0.0.0.0/0` ngoài cổng 80/443.
- [ ] IAM: không có `"Action": "*"` hay `"Resource": "*"` ngoài các statement đã biết lý do (`ec2:DescribeInstances`, `ssm:GetCommandInvocation`).
- [ ] `tags_all` có đủ `Project`, `Env`, `Owner`, `ManagedBy`.
- [ ] Không có giá trị bí mật nào hiện ra (mật khẩu, token).
- [ ] Apply đúng file plan vừa đọc: `terraform apply tfplan`, không phải `terraform apply` (sinh plan **mới** có thể khác).

### A8. Vòng xóa – dựng lần 1

```bash
time terraform destroy            # ⚠️ xóa toàn bộ — gõ "yes" sau khi đọc danh sách
~/devops-lab/06-aws/find-leftovers.sh
time terraform apply              # dựng lại từ đầu
```

Ghi vào nhật ký: thời gian `destroy`, thời gian `apply`, kết quả `find-leftovers.sh` (sau `destroy` chỉ còn bucket `taskhub-backups-<account-id>`). So sánh với số giờ bạn đã bỏ ra để dựng tay ở tuần 11–13.

**Kết thúc tuần 15:** `terraform destroy`. Commit code (không có state, không có `terraform.tfvars`), mở PR.

---

## Phần B — Tuần 16: lớp bền, module, backend S3

Ba vấn đề của Phần A:

1. State nằm trên laptop — mất laptop là Terraform "quên" toàn bộ hạ tầng; không ai khác (hay CI) làm việc chung được.
2. Bucket backup chứa dữ liệu nhưng không được quản lý bằng code.
3. Mọi thứ trong một thư mục phẳng — không tái sử dụng được cho môi trường khác.

### B1. `bootstrap/`: bucket state và bucket backup

Bài toán con gà – quả trứng: bucket chứa state **không thể** được tạo bởi chính cấu hình dùng nó làm backend. Giải pháp: một root module riêng, `infra/terraform/bootstrap/`, chạy với state cục bộ **một lần**, rồi chuyển state của chính nó lên bucket vừa tạo.

Vì sao bucket backup cũng nằm ở đây chứ không ở `envs/dev`? Cả hai bucket có `lifecycle { prevent_destroy = true }`. Một root module chứa tài nguyên `prevent_destroy` thì `terraform destroy` **cả root đó báo lỗi và dừng** — không phải "xóa phần còn lại, bỏ qua bucket". Muốn `envs/dev` xóa sạch bằng một lệnh, thứ không bao giờ được xóa phải sống ở **root khác, state khác**.

Viết `bootstrap/` (`versions.tf`, `variables.tf` với biến `owner`, `main.tf`, `outputs.tf`):

- Bucket `taskhub-tfstate-<account-id>` (tên ghép từ `data.aws_caller_identity`): versioning, Block Public Access, SSE-S3, lifecycle xóa phiên bản noncurrent sau 90 ngày, bucket policy từ chối request không TLS, `prevent_destroy`.
- Bucket `taskhub-backups-<account-id>` với **đúng** cấu hình ở [06-AWS bài 05](../../06-AWS/05-s3.md): versioning, Block Public Access, SSE-S3, 3 rule lifecycle (`expire-noncurrent-after-30-days`, `abort-incomplete-multipart-after-7-days`, `remove-expired-delete-markers`), policy `DenyInsecureTransport`, `prevent_destroy`.

Bucket backup đã tồn tại → **import** thay vì tạo. `imports.tf`:

```hcl
import {
  to = aws_s3_bucket.backups
  id = local.backup_bucket_name
}

import {
  to = aws_s3_bucket_versioning.backups
  id = local.backup_bucket_name
}

# … tương tự cho aws_s3_bucket_public_access_block, aws_s3_bucket_server_side_encryption_configuration,
#     aws_s3_bucket_lifecycle_configuration, aws_s3_bucket_policy (id đều là tên bucket)
```

```bash
cd ~/projects/taskhub/infra/terraform/bootstrap
terraform init
terraform plan -var owner=phuong
```

Đọc plan (minh họa):

```text
  # aws_s3_bucket.backups will be imported
  # aws_s3_bucket_lifecycle_configuration.backups will be imported
  ...
  # aws_s3_bucket.backups will be updated in-place
      ~ tags     = {
          ~ "ManagedBy" = "manual" -> "terraform"
        }
Plan: 6 to import, 6 to add, 1 to change, 0 to destroy.
```

`6 to add` là bucket state cùng 5 resource đi kèm (versioning, public access block, SSE, lifecycle, policy — data source không được đếm). `to change` chỉ được phép là **tag**. Nếu plan đòi sửa lifecycle hay policy của bucket backup: code của bạn **chưa khớp** cấu hình thật — sửa code cho tới khi plan chỉ còn import + tag, rồi mới apply (thử nghiệm T5 của milestone v4). Bucket đã bị xóa từ trước? Xóa file `imports.tf`, Terraform sẽ tạo mới.

```bash
terraform apply -var owner=phuong          # ⚠️ tạo bucket state, import bucket backup
```

Chuyển state của `bootstrap` lên S3 — key `bootstrap/terraform.tfstate`. Khối `backend` **không nhận biến**, nên tên bucket (chứa account id) truyền lúc `init` bằng `-backend-config` (*partial configuration*) — repo public không chứa account id:

```hcl
# bootstrap/backend.tf — thêm SAU khi bucket đã tồn tại
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

```bash
terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket)"
# "Do you want to copy existing state to the new backend?" → yes
aws s3 ls "s3://$(terraform output -raw state_bucket)/bootstrap/"     # terraform.tfstate
terraform plan -var owner=phuong                                     # No changes.
rm terraform.tfstate terraform.tfstate.backup                         # ⚠️ chỉ sau khi plan "No changes"
```

### B2. Tách module mà không phá hạ tầng: `moved`

Đọc [bài 04](../04-terraform-modules-environments.md) trước bước này. Mục tiêu:

```text
infra/terraform/
├── bootstrap/                (B1)
├── modules/
│   ├── network/              VPC, IGW, subnet, route table, association
│   └── app_server/           SG + rule, IAM role/policy/profile của EC2, data AMI, EC2
└── envs/
    └── dev/                  provider, gọi 2 module, tham số mật khẩu, OIDC, monitoring, outputs
```

Dựng hạ tầng của Phần A trước (`terraform apply` trong `envs/dev`, state vẫn cục bộ). Rồi chuyển code vào module. Nếu chỉ chuyển code, Terraform thấy `aws_vpc.this` **biến mất** và `module.network.aws_vpc.this` **xuất hiện** → plan đòi **xóa VPC cũ và tạo VPC mới** (kéo theo cả EC2). Khối `moved` nói với Terraform: "đây là cùng một tài nguyên, chỉ đổi địa chỉ". `envs/dev/moved.tf`:

```hcl
moved {
  from = aws_vpc.this
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_vpc_security_group_ingress_rule.http
  to   = module.app_server.aws_vpc_security_group_ingress_rule.web["80"]
}

moved {
  from = aws_instance.app
  to   = module.app_server.aws_instance.app
}

# … một khối cho MỖI resource đã chuyển vào module (data source thì không cần)
```

- `moved` cho resource có `for_each` (`aws_subnet.public`) chuyển **cả** tập instance `["a"]`, `["b"]` cùng lúc — khóa giữ nguyên vì module dùng cùng khóa.
- Ở module, rule SG viết bằng `for_each` trên danh sách cổng → địa chỉ đổi từ `...ingress_rule.http` sang `...ingress_rule.web["80"]` — `moved` xử lý được cả việc đổi khóa instance.

```bash
cd ~/projects/taskhub/infra/terraform/envs/dev
terraform init                     # nạp module mới
terraform plan
```

Kết quả **phải** là (minh họa):

```text
  # aws_vpc.this has moved to module.network.aws_vpc.this
  ...
Plan: 0 to add, 0 to change, 0 to destroy.
```

Còn `to add`/`to destroy`? Thiếu khối `moved` cho resource đó, hoặc tên resource trong module khác với `to`. Sửa tới khi `0/0/0`, rồi `terraform apply` (chỉ cập nhật địa chỉ trong state). Danh sách đầy đủ các khối `moved`: [lời giải](../solutions/lab-02-solutions.md).

### B3. Chuyển state của `envs/dev` lên S3

Thêm khối backend (partial configuration) vào `envs/dev/versions.tf`:

```hcl
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
```

```bash
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
terraform init -migrate-state -backend-config="bucket=taskhub-tfstate-${ACCOUNT_ID}"
aws s3 ls "s3://taskhub-tfstate-${ACCOUNT_ID}/envs/dev/"
terraform plan                       # No changes.
rm terraform.tfstate terraform.tfstate.backup   # ⚠️ chỉ sau khi plan "No changes"
```

`use_lockfile = true`: khi `plan`/`apply` chạy, Terraform tạo file `envs/dev/terraform.tfstate.tflock` trong cùng bucket; lệnh thứ hai chạy song song sẽ bị từ chối (thử nghiệm E4). Theo tài liệu backend S3, khóa bằng DynamoDB đã **deprecated** — không dùng.

### B4. Bucket cho Ansible và outputs cho GitHub

Lab 03 dùng connection `amazon.aws.aws_ssm`, cần một bucket S3 làm nơi trung chuyển file. Thêm vào `envs/dev`:

- `aws_s3_bucket.ansible_ssm` tên `taskhub-ansible-ssm-<account-id>`, **`force_destroy = true`** (chỉ chứa file tạm — cho phép `destroy` xóa cả khi còn object), Block Public Access, SSE-S3, lifecycle xóa object sau 1 ngày, policy từ chối non-TLS.
- Output `ansible_ssm_bucket`.

Đặt `force_destroy` cạnh `prevent_destroy` của bucket backup để thấy rõ hai thái cực: bucket tạm thì xóa không cần hỏi, bucket dữ liệu thì không xóa được bằng `destroy` thường.

Sau `apply`, cập nhật biến của environment `production` trên GitHub (`[GitHub]` Settings → Environments → production):

| Biến | Giá trị |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | `terraform output -raw deploy_role_arn` |
| `APP_URL` | `terraform output -raw app_url` — **đổi mỗi lần dựng lại** EC2 |

### B5. Vòng xóa – dựng lần 2 (một lệnh)

```bash
cd ~/projects/taskhub/infra/terraform/envs/dev
time terraform destroy             # ⚠️
~/devops-lab/06-aws/find-leftovers.sh ap-southeast-1
time terraform apply
```

Sau `destroy`, `find-leftovers.sh` chỉ được báo **hai** bucket của `bootstrap` (`taskhub-tfstate-…`, `taskhub-backups-…`) — mã thoát 1 là đúng, vì đó là lớp bền cố ý giữ lại. Thêm bất kỳ thứ gì khác → tài nguyên tạo ngoài Terraform hoặc `destroy` lỗi giữa chừng → điều tra.

Ứng dụng chưa chạy sau `apply` — máy trống, chưa có Docker. [Lab 03](lab-03-ansible-ssm.md) hoàn thành nốt bằng Ansible. Milestone v4 gói hai bước thành `make up` / `make down`.

---

## 2. Thử nghiệm bắt buộc

Ghi **thao tác → quan sát → giải thích** vào nhật ký.

| # | Thao tác | Quan sát | Câu hỏi |
|---|---|---|---|
| E1 | **Drift:** `[AWS Console]` thêm tay rule cổng 22 từ IP của bạn vào `taskhub-web-sg` → `terraform plan` | Plan muốn **xóa** rule đó? Hay không thấy gì? | Vì sao rule tạo ngoài Terraform có thể không hiện trong plan khi dùng resource rule riêng lẻ (`aws_vpc_security_group_ingress_rule`)? Làm sao phát hiện nó? (gợi ý: `aws ec2 describe-security-group-rules`). Xóa tay rule đó sau khi quan sát |
| E2 | **Thay máy có chủ đích:** `terraform plan -replace=module.app_server.aws_instance.app` | `-/+` cho EC2; `public_ip` và `app_url` "known after apply" | Những gì mất khi thay máy? Biến GitHub nào phải cập nhật? Chỉ `plan`, không bắt buộc apply |
| E3 | **`prevent_destroy`:** trong `bootstrap/` chạy `terraform plan -destroy -var owner=phuong` | Lỗi `Instance cannot be destroyed` | Vì sao lỗi xuất hiện ngay ở **plan**, trước khi có gì bị xóa? Tuyệt đối **không** gỡ `prevent_destroy` để "cho chạy được" |
| E4 | **Khóa state:** terminal 1 `terraform apply -var 'owner=lock-test'` (đổi một tag để plan **có** thay đổi — nếu không có thay đổi, `apply` in *No changes* rồi thoát ngay, không hỏi và không giữ khóa); dừng ở câu hỏi yes/no, đừng trả lời. Terminal 2 `terraform plan` | Terminal 2 báo `Error acquiring the state lock` kèm Lock Info (ID, Who, Created). `aws s3 ls s3://taskhub-tfstate-<acct>/envs/dev/` thấy `.tflock` | Khi nào mới được dùng `terraform force-unlock <ID>`? (Chỉ khi chắc chắn không còn tiến trình nào giữ khóa — ví dụ laptop tắt giữa lúc apply.) Trả lời `no` ở terminal 1 |
| E5 | **Xoay mật khẩu:** đổi `postgres_password_version = 2` → `plan` | `~ value_wo_version = 1 -> 2`, giá trị mật khẩu không hiện | Vì sao đổi mật khẩu trong Parameter Store mà **không** tạo lại PostgreSQL thì ứng dụng hỏng? (volume `pgdata` giữ mật khẩu lúc khởi tạo lần đầu.) Đặt lại `1` |
| E6 | **AMI mới:** `aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query Parameter.Value` so với `terraform state show module.app_server.aws_instance.app \| grep ami` | Có thể đã khác nhau (nếu Canonical vừa ra bản mới) mà plan vẫn "No changes" | Đó là tác dụng của `ignore_changes = [ami]`. Đánh đổi là gì? |

---

## 3. Kết quả mong đợi

- `infra/terraform/` có `bootstrap/`, `modules/network/`, `modules/app_server/`, `envs/dev/`; `.terraform.lock.hcl` của `bootstrap` và `envs/dev` đã commit; không có `*.tfstate` hay `terraform.tfvars` trong Git.
- `terraform plan` trong `envs/dev` và `bootstrap` đều `No changes` ngay sau apply.
- State của cả hai root nằm trong `s3://taskhub-tfstate-<acct>/` (`bootstrap/terraform.tfstate`, `envs/dev/terraform.tfstate`).
- Mật khẩu PostgreSQL có trong Parameter Store (32 ký tự) nhưng xuất hiện **0** lần trong state.
- `terraform destroy` của `envs/dev` chạy hết không lỗi; `find-leftovers.sh` chỉ còn 2 bucket của `bootstrap`.
- Có số liệu thời gian một vòng `destroy` + `apply` trong nhật ký.

---

## 4. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Kiểm tra | Cách sửa |
|---|---|---|---|
| `EntityAlreadyExists` (role, instance profile, OIDC provider) / `ResourceAlreadyExistsException` (log group) | Tài nguyên tay của v2/v3 chưa xóa | `aws iam get-role --role-name taskhub-ec2-role`; `aws iam list-open-id-connect-providers` | Xóa theo [v3 §11](../../12-PRACTICAL-PROJECT/milestones/v3-cd.md#11-dọn-dẹp), hoặc import — không đổi tên để "né" |
| `Value (taskhub-ec2-role) for parameter iamInstanceProfile.name is invalid` khi tạo EC2 | IAM nhất quán cuối cùng (eventual consistency): instance profile vừa tạo chưa lan tới EC2 | Chạy lại sau vài chục giây | `terraform apply` lại — Terraform chỉ tạo phần còn thiếu |
| `VcpuLimitExceeded` | Quota vCPU mặc định của tài khoản mới (5 vCPU) đã dùng hết — thường do máy cũ chưa terminate | `aws ec2 describe-instances --filters Name=instance-state-name,Values=running,stopped` | Terminate máy thừa; xem [06-AWS bài 04](../../06-AWS/04-ec2.md) |
| Plan của `bootstrap` báo `Cannot import non-existent remote object` | Bucket backup đã bị xóa | `aws s3api head-bucket --bucket taskhub-backups-<acct>` | Xóa `imports.tf`, để Terraform tạo mới |
| Plan sau import đòi `update in-place` lifecycle/policy của bucket backup | Code chưa khớp cấu hình tay | Đọc diff từng thuộc tính | Sửa code theo cấu hình thật (bài 05 Module 06) cho tới khi chỉ còn tag |
| `Error: Instance cannot be destroyed` khi `destroy` | Root module có tài nguyên `prevent_destroy` — bucket đặt nhầm vào `envs/dev` | `grep -rn prevent_destroy envs/dev` | Đưa bucket dữ liệu về `bootstrap/` (B1) |
| `Error acquiring the state lock` | Có lệnh khác đang chạy, hoặc lần chạy trước bị ngắt (Ctrl+C mạnh, mất mạng) | Đọc Lock Info: Who, Created | Chờ lệnh kia xong. Chỉ `terraform force-unlock <ID>` khi chắc không còn ai giữ khóa |
| `init` báo `Backend configuration changed` / hỏi migrate | Đổi `key`/`bucket` của backend | Đọc kỹ: chép state từ đâu sang đâu? | Trả lời `yes` chỉ khi đúng ý. Sai key → state rỗng → plan đòi tạo lại tất cả |
| `init`: `The "bucket" attribute value must not be empty` hoặc hỏi nhập bucket | Quên `-backend-config="bucket=..."` (partial configuration) | Lệnh `init` vừa gõ | Chạy lại `init` với `-backend-config` |
| Plan sau khi chuyển vào module đòi destroy + add | Thiếu khối `moved` hoặc sai địa chỉ `to` | `terraform state list` so với địa chỉ trong module | Thêm/sửa `moved` tới khi `0 to add, 0 to destroy` |
| `AccessDenied` khi `init` với backend S3 | Profile đăng nhập hết hạn (`aws login` 12 giờ) hoặc sai account | `aws sts get-caller-identity` | `aws login --profile taskhub` |
| Không nhận được email alarm | Chưa xác nhận subscription | `aws sns list-subscriptions-by-topic --topic-arn ...` → `PendingConfirmation` | Bấm link trong email; mỗi lần dựng lại phải xác nhận lại |

---

## 5. ⚠️ Dọn dẹp

Cuối **mỗi** buổi học có AWS:

```bash
cd ~/projects/taskhub/infra/terraform/envs/dev
terraform destroy                                    # ⚠️ xóa EC2, VPC, IAM, OIDC, alarm, bucket ansible-ssm…
~/devops-lab/06-aws/find-leftovers.sh ap-southeast-1
aws ec2 describe-instances --filters Name=tag:Project,Values=taskhub \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' --output text          # rỗng
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].VolumeId' --output text                             # rỗng
aws iam list-open-id-connect-providers --output text                    # không còn GitHub
```

**`terraform destroy` của `envs/dev` cố ý KHÔNG xóa:**

| Còn lại | Vì sao | Chi phí |
|---|---|---|
| Bucket `taskhub-tfstate-<acct>` | Thuộc root `bootstrap/` (state khác), có `prevent_destroy`. Mất bucket này = mất state = lần sau Terraform không biết gì đã tồn tại | Vài KB → gần 0 |
| Bucket `taskhub-backups-<acct>` | Thuộc `bootstrap/`, có `prevent_destroy`; chứa bản backup database (v5) | Theo dung lượng backup — rất nhỏ |
| Biến GitHub `APP_URL` | Không phải tài nguyên AWS | 0 — nhớ cập nhật ở buổi sau |

Dừng hẳn dự án (cuối khóa học hoặc trước khi Free plan kết thúc): destroy `envs/dev`; với `bootstrap`, làm rỗng bucket (cả **mọi phiên bản** — xem lệnh ở [06-AWS bài 05](../../06-AWS/05-s3.md)), tạm bỏ `prevent_destroy` trong một commit ghi rõ lý do, rồi `terraform destroy` — đúng thứ tự ở [milestone v4](../../12-PRACTICAL-PROJECT/milestones/v4-terraform.md). Hai ngày sau kiểm tra lại Billing (chi phí cập nhật trễ).

---

## 6. Câu hỏi sau lab

1. Vì sao bucket state không thể nằm trong cùng root module với hạ tầng nó lưu state? Mô tả trình tự bạn đã làm ở B1 và lý do của từng bước.
2. Đặt bucket backup (có `prevent_destroy`) trong `envs/dev` thì `terraform destroy` chuyện gì xảy ra? Vì sao "xóa `prevent_destroy` cho chạy được" là câu trả lời sai?
3. `moved` khác gì `terraform state mv`? Vì sao `moved` an toàn hơn khi làm việc nhóm?
4. Mật khẩu PostgreSQL đi từ đâu tới đâu trong v4 (từ lúc `terraform apply` tới lúc container `postgres` đọc nó)? Ở những điểm nào nó tồn tại dạng chữ?
5. Vì sao `ignore_changes = [ami]` cần thiết ở đây, và nó làm bạn mất gì?
6. `default_tags` khác gì `tags` trên từng resource? Tag nào thắng khi trùng khóa? (ví dụ `Env` của bucket backup)
7. Cùng một commit, laptop của bạn `plan` sạch nhưng đồng nghiệp lại thấy provider khác phiên bản — file nào ngăn điều này, và nó nằm ở đâu?
8. Nêu ba tài nguyên trong `envs/dev` mà mỗi lần dựng lại sẽ có **giá trị khác** lần trước, và hệ quả của từng cái với CD (workflow `Deploy`).

Lời giải: [solutions/lab-02-solutions.md](../solutions/lab-02-solutions.md).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Terraform — Get Started (AWS)](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) | Tutorial chính thức làm song song tuần 15 | 2026-10-31 |
| [Terraform — Backend `s3`](https://developer.hashicorp.com/terraform/language/backend/s3) | `use_lockfile`, DynamoDB deprecated, quyền trên `.tflock`, versioning | 2026-10-31 |
| [Terraform — Backend partial configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration) | `-backend-config` | 2026-10-31 |
| [Terraform — Import](https://developer.hashicorp.com/terraform/language/import) | Khối `import {}` | 2026-10-31 |
| [Terraform — Refactoring với `moved`](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring) | Đổi địa chỉ resource khi chuyển vào module | 2026-10-31 |
| [Terraform — Write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only) | `value_wo`, ephemeral, Terraform ≥ 1.11 | 2026-10-31 |
| [Provider AWS — `aws_ssm_parameter`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ssm_parameter.html.markdown) | `value_wo`, `value_wo_version` | 2026-10-31 |
| [Provider AWS — data `aws_ssm_parameter`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/d/ssm_parameter.html.markdown) | `insecure_value` | 2026-10-31 |
| [Provider random — ephemeral `random_password`](https://github.com/hashicorp/terraform-provider-random/blob/main/docs/ephemeral-resources/password.md) | Sinh mật khẩu không lưu state (từ 3.7.0) | 2026-10-31 |
| [Provider AWS — `aws_instance`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/instance.html.markdown) | `metadata_options`, `root_block_device`, default tags áp cho volume | 2026-10-31 |
| [Provider AWS — `aws_iam_openid_connect_provider`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/iam_openid_connect_provider.html.markdown) | `thumbprint_list` tùy chọn với GitHub | 2026-10-31 |
| [Provider AWS — `aws_sns_topic_subscription`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/sns_topic_subscription.html.markdown) | Email phải xác nhận; xóa topic xóa subscription | 2026-10-31 |
