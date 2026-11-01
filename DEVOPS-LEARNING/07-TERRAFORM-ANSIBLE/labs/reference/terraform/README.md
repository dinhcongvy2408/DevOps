# Bản tham khảo Terraform cho `taskhub` v4

> ⚠️ **Chỉ mở sau khi đã tự viết** (Lab 02, tuần 15–16). File ở đây để **so sánh** với code của bạn, không phải để chép. Phỏng vấn viên sẽ hỏi "vì sao dòng này viết như vậy?" — câu trả lời phải là của bạn.
> Không có account id nào trong code: tên bucket được ghép từ `data.aws_caller_identity` hoặc truyền lúc `terraform init`.

Chép vào repo `taskhub` tại `infra/terraform/` (giữ nguyên cấu trúc thư mục). Dùng trong: [Lab 02](../../lab-02-taskhub-infra-terraform.md) · [Milestone v4](../../../../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) · Ansible đi kèm: [../ansible/](../ansible/)

## Cấu trúc: hai lớp, hai state

```text
infra/terraform/
├── bootstrap/            LỚP BỀN VỮNG — apply 1 lần, KHÔNG BAO GIỜ destroy cùng hạ tầng hằng ngày
│   ├── versions.tf          state lúc đầu LOCAL (bucket chưa có thì không lưu state vào nó được)
│   ├── backend.tf.example   đổi tên thành backend.tf → chuyển state lên s3://…/bootstrap/terraform.tfstate
│   ├── main.tf              bucket state taskhub-tfstate-<acct> + bucket backup taskhub-backups-<acct>
│   ├── imports.tf           import bucket backup tạo tay ở 06-AWS bài 05 (xóa file nếu bucket không còn)
│   ├── variables.tf · outputs.tf
├── modules/
│   ├── network/          VPC, 2 public + 2 private subnet (for_each trên map khóa a/b), IGW, 2 route table — không NAT
│   └── app_server/       SG taskhub-web-sg, role/profile taskhub-ec2-role (+ 2 inline policy), EC2 t3.small
└── envs/
    └── dev/              LỚP TẠM — `terraform destroy` một lệnh là sạch
        ├── versions.tf      backend s3 (partial config) key envs/dev/terraform.tfstate, use_lockfile
        ├── providers.tf     default_tags: Project, Env, Owner, ManagedBy=terraform
        ├── main.tf          gọi 2 module + mật khẩu PostgreSQL (ephemeral + value_wo)
        ├── github-oidc.tf   OIDC provider + role taskhub-github-deploy
        ├── monitoring.tf    log group /taskhub/dev/app (7 ngày), SNS taskhub-alerts, 2 alarm
        ├── ansible-ssm-bucket.tf  bucket trung chuyển của Ansible aws_ssm (force_destroy)
        ├── variables.tf · outputs.tf · terraform.tfvars.example
```

| Lớp | Chứa | Vì sao tách |
|---|---|---|
| `bootstrap/` | Bucket **state** + bucket **backup** — đều `prevent_destroy = true` | Một root module có tài nguyên `prevent_destroy` thì `terraform destroy` của **cả** root đó **báo lỗi và dừng** (không phải "bỏ qua cái được bảo vệ"). Để "xóa một lệnh" hoạt động, thứ không bao giờ được xóa phải sống ở root khác, state khác |
| `envs/dev/` | Mọi thứ còn lại | Dựng/xóa tự do. Tham chiếu bucket backup **theo tên** (`taskhub-backups-<acct>`), không theo resource — hai state không phụ thuộc nhau |

## Thứ tự chạy

```bash
export AWS_PROFILE=taskhub            # đã `aws login` (06-AWS bài 06)
cd ~/projects/taskhub/infra/terraform

# 1. Lớp bền vững (một lần)
cd bootstrap                          # bootstrap chỉ cần một biến: owner
terraform init
terraform plan  -var owner=phuong     # đọc kỹ: 6 resource "will be imported" nếu bucket backup còn
terraform apply -var owner=phuong
mv backend.tf.example backend.tf
terraform init -migrate-state -backend-config="bucket=$(terraform output -raw state_bucket)"
cd ..

# 2. Lớp tạm (mỗi buổi học: apply đầu buổi, destroy cuối buổi)
cd envs/dev
cp terraform.tfvars.example terraform.tfvars   # sửa owner, github_repo, alert_email
terraform init -backend-config="bucket=taskhub-tfstate-$(aws sts get-caller-identity --query Account --output text)"
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

Sau mỗi lần `apply` của `envs/dev`:

| Output | Đưa vào đâu | Vì sao phải cập nhật |
|---|---|---|
| `app_url` | GitHub → Settings → Environments → `production` → variable `APP_URL` | IP public **đổi** mỗi lần tạo lại EC2 → smoke test của workflow `Deploy` gọi sai địa chỉ |
| `deploy_role_arn` | variable `AWS_DEPLOY_ROLE_ARN` (cùng environment) | ARN giữ nguyên tên nhưng role là role mới; kiểm tra lại một lần ở lần dựng đầu |
| `ansible_ssm_bucket` | Không cần chép: inventory Ansible tự ghép tên từ account id | Đối chiếu khi Ansible báo lỗi bucket |
| `instance_id`, `public_ip` | Ghi vào nhật ký buổi học | Debug, `aws ssm start-session --target <instance_id>` |

Rồi chạy Ansible ([Lab 03](../../lab-03-ansible-ssm.md)) để cài Docker và triển khai ứng dụng; bật lại workflow `Deploy` nếu đã tắt ở cuối v3.

## Các quyết định trong code và lý do

| Quyết định | Lý do | Đánh đổi |
|---|---|---|
| Backend **partial configuration** (`bucket` truyền bằng `-backend-config`) | Khối `backend` không nhận biến; ghi cứng tên bucket = ghi cứng account id vào repo public | Lệnh `init` dài hơn — đặt vào Makefile (milestone v4) |
| `use_lockfile = true`, không DynamoDB | Tài liệu Terraform: khóa bằng DynamoDB đã **deprecated**; lock file `.tflock` nằm cạnh state trong cùng bucket | Cần `s3:DeleteObject` trên file `.tflock` |
| Bucket state: versioning + lifecycle noncurrent 90 ngày | Khôi phục được state bị ghi hỏng; không tích phiên bản cũ vô hạn | — |
| Bucket backup ở `bootstrap/`, **import** thay vì tạo mới | Bucket có dữ liệu từ v2; import không xóa/tạo lại gì. `prevent_destroy` + root riêng → `destroy` hằng ngày không đụng tới | Lần plan đầu có thể báo "update in-place" nếu cấu hình tay khác code (ví dụ tag `ManagedBy`) — đọc kỹ rồi mới apply |
| Mật khẩu PostgreSQL: `ephemeral "random_password"` → `value_wo` | Không nằm trong state, plan, repo hay GitHub. Write-only argument cần Terraform ≥ 1.11; ephemeral `random_password` có từ hashicorp/random 3.7.0 | Terraform không bao giờ "biết" mật khẩu → không thể output nó; `deploy.sh` đọc trực tiếp từ Parameter Store (`--with-decryption`) như ở v3 |
| `value_wo_version` | Provider chỉ ghi giá trị mới khi số version đổi → mỗi lần plan sinh mật khẩu ngẫu nhiên khác nhưng **không** đổi mật khẩu thật | Tăng version để xoay vòng mật khẩu **chỉ** khi database cũng được tạo lại (volume `pgdata` giữ mật khẩu cũ) |
| `special = false`, độ dài 32 | Mật khẩu đi vào `.env` và URL JDBC — ký tự `$ # " '` gây lỗi parse khó debug | Entropy vẫn ≈ 190 bit (62 ký tự × 32) |
| AMI qua `data "aws_ssm_parameter"` + `insecure_value` | Không hard-code `ami-xxxx` theo region. `value` luôn bị đánh dấu sensitive → plan khó đọc; AMI ID không phải bí mật | — |
| `ignore_changes = [ami]` | Canonical ra AMI mới → parameter đổi → không có dòng này thì một lần `apply` bất kỳ sẽ **thay máy** (mất database) | Muốn lên AMI mới phải chủ động `terraform apply -replace=module.app_server.aws_instance.app` |
| Không `user_data` | Ubuntu 24.04 có sẵn SSM Agent (snap), `curl`, `python3` — đủ cho Ansible `aws_ssm`. Cài đặt phần mềm là việc của Ansible (idempotent, chạy lại được), không phải của cloud-init (chạy một lần) | Máy vừa tạo chưa chạy ứng dụng cho tới khi chạy playbook |
| Rule SG tách thành `aws_vpc_security_group_ingress_rule`/`egress_rule` | Mỗi rule một resource, plan rõ ràng; `validation` chặn cổng 22 ngay từ lúc plan | Khi tạo SG, Terraform xóa rule egress "allow all" mặc định → phải khai báo lại |
| Module khai báo `version = ">= 6.0"`, root khai báo `"~> 6.0"` | Module đặt **cận dưới**; root (nơi thực sự chạy) chốt phiên bản. `.terraform.lock.hcl` của root được commit | — |
| OIDC provider không có `thumbprint_list` | Tài liệu provider: với GitHub, AWS dùng thư viện root CA của chính AWS, thumbprint không được dùng để xác thực | — |
| `force_destroy = true` **chỉ** cho bucket `ansible-ssm` | Bucket đó chỉ chứa file tạm (lifecycle xóa sau 1 ngày) | Đặt nhầm `force_destroy` cho bucket backup = một lệnh destroy xóa sạch dữ liệu |
| SNS email subscription | Topic bị xóa thì SNS xóa luôn subscription (kể cả chưa xác nhận) | Mỗi lần dựng lại phải bấm link xác nhận trong email một lần nữa |

## Chuyển state của bootstrap lên S3 (vì sao làm)

State local của `bootstrap/` nằm trên laptop: mất laptop (hoặc lỡ `rm`) thì Terraform không còn biết hai bucket kia. Không nguy hiểm tức thì (bucket vẫn còn, `prevent_destroy` vẫn giữ trong code), nhưng muốn sửa bucket lại phải import lại từ đầu. Đưa state lên chính bucket state — key `bootstrap/terraform.tfstate`, tách khỏi `envs/dev/terraform.tfstate` — là cách làm phổ biến. Thứ tự **bắt buộc**: apply với state local trước (bucket phải tồn tại), rồi mới `init -migrate-state`.

## Đã kiểm tra những gì

- Mọi resource type và argument đối chiếu với tài liệu provider AWS v6 / random (link bên dưới) ngày 2026-10-31.
- **Chưa** chạy `terraform validate` / `apply` khi viết — bản kiểm thử `init -backend=false && validate` chạy trong container sau. Lần chạy thật trên AWS đầu tiên là của bạn ở Lab 02: gặp khác biệt thì ghi vào nhật ký debug.

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Terraform — Backend `s3`](https://developer.hashicorp.com/terraform/language/backend/s3) | `use_lockfile`, DynamoDB deprecated, quyền trên `.tflock`, versioning bucket | 2026-10-31 |
| [Terraform — Partial backend configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration) | `-backend-config` | 2026-10-31 |
| [Terraform — Write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only) | `value_wo` + ephemeral, Terraform ≥ 1.11 | 2026-10-31 |
| [Provider AWS — `aws_ssm_parameter`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ssm_parameter.html.markdown) | `value_wo`, `value_wo_version` | 2026-10-31 |
| [Provider AWS — data `aws_ssm_parameter`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/d/ssm_parameter.html.markdown) | `value` luôn sensitive, `insecure_value` | 2026-10-31 |
| [Provider random — ephemeral `random_password`](https://github.com/hashicorp/terraform-provider-random/blob/main/docs/ephemeral-resources/password.md) · [CHANGELOG](https://github.com/hashicorp/terraform-provider-random/blob/main/CHANGELOG.md) | Ephemeral password, có từ 3.7.0; bản mới nhất 3.9.1 | 2026-10-31 |
| [Provider AWS — `aws_iam_openid_connect_provider`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/iam_openid_connect_provider.html.markdown) | `thumbprint_list` tùy chọn, GitHub dùng root CA của AWS | 2026-10-31 |
| [Provider AWS — `aws_instance`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/instance.html.markdown) | `metadata_options`, `root_block_device`, default tags áp cho volume | 2026-10-31 |
| [Provider AWS — `aws_s3_bucket_lifecycle_configuration`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/s3_bucket_lifecycle_configuration.html.markdown) | `filter {}` áp cho mọi object | 2026-10-31 |
| [Provider AWS — `aws_sns_topic_subscription`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/sns_topic_subscription.html.markdown) | Email chưa xác nhận, xóa topic xóa subscription | 2026-10-31 |
| [Provider AWS — `aws_s3_bucket`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/s3_bucket.html.markdown) | `force_destroy` | 2026-10-31 |
