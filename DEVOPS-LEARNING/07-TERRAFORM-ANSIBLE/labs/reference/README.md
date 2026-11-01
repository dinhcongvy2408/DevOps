# Bản tham khảo hạ tầng `taskhub` v4 — Terraform + Ansible

> ⚠️ **Chỉ mở sau khi đã tự viết.** Mục tiêu của tuần 15–16 là bạn tự viết được từng dòng và giải thích được vì sao. Code ở đây dùng để **so sánh** với code của bạn.

| Thư mục | Chép vào repo `taskhub` tại | Viết ở | Dùng trong |
|---|---|---|---|
| [terraform/](terraform/README.md) | `infra/terraform/` | [Lab 02](../lab-02-taskhub-infra-terraform.md), bài [03](../../03-terraform-state-backend.md) và [04](../../04-terraform-modules-environments.md) | [Milestone v4](../../../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) |
| [ansible/](ansible/README.md) | `infra/ansible/` | [Lab 03](../lab-03-ansible-ssm.md), bài [05](../../05-ansible-fundamentals.md) | [Milestone v4](../../../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) |

## Ai làm gì

```text
                 terraform (bootstrap — 1 lần, không destroy)
                   └─ bucket state taskhub-tfstate-<acct>  ·  bucket backup taskhub-backups-<acct>
                 terraform (envs/dev — dựng/xóa một lệnh)
                   └─ VPC, subnet, IGW, SG · IAM role EC2 + OIDC deploy role · EC2 t3.small
                      log group, SNS, alarm · tham số mật khẩu (value_wo) · bucket trung chuyển Ansible
                                  │ output: instance_id, public_ip, app_url, deploy_role_arn, ansible_ssm_bucket
                                  ▼
                 ansible (qua SSM, không mở cổng 22)
                   └─ role docker: Docker Engine + compose plugin từ repo apt chính thức
                   └─ role taskhub: /opt/taskhub, compose*.yaml, nginx conf, deploy.sh → chạy deploy.sh <tag>
                                  │
                                  ▼
                 GitHub Actions Deploy (v3) — cập nhật AWS_DEPLOY_ROLE_ARN, APP_URL từ output rồi bật lại
```

| Ranh giới | Terraform | Ansible |
|---|---|---|
| Tạo/xóa **tài nguyên cloud** (có API AWS) | ✅ | ❌ |
| Cấu hình **bên trong** máy (gói, file, service) | ❌ (không dùng user data trong v4) | ✅ |
| Đổi **phiên bản app** | ❌ | Lần đầu (`deploy.sh`); sau đó là workflow Deploy |

## Các quyết định trong code và lý do

| Quyết định | Lý do | Học ở |
|---|---|---|
| Hai tầng `bootstrap` và `envs/dev`, hai state | Root có `prevent_destroy` thì `terraform destroy` cả root báo lỗi. Thứ không bao giờ được xóa (state, backup) phải sống ở root khác | Bài 03, Lab 02 |
| Backend S3 `use_lockfile = true`, partial config | Khóa bằng file `.tflock` trên S3 (DynamoDB đã deprecated); tên bucket chứa account ID nên truyền lúc `init`, không ghi vào repo | Bài 03 |
| Mật khẩu: `ephemeral "random_password"` → `value_wo` | Không bao giờ nằm trong state hay plan; `deploy.sh` vẫn đọc từ Parameter Store như v2/v3 | Bài 03 |
| Subnet bằng `for_each` theo map khóa `a`/`b` | Thêm/bớt một AZ không làm dịch chỉ số và thay thế subnet khác (lỗi `count` ở checkpoint) | Bài 02, 04 |
| Không ghi cứng account ID | `data.aws_caller_identity` — code chạy được trên tài khoản bất kỳ | Lab 02 |
| `default_tags` ở provider | Mọi tài nguyên có `Project`, `Env`, `Owner`, `ManagedBy=terraform` để lọc chi phí và tìm tài nguyên sót | Bài 04 |
| EC2: IMDSv2 bắt buộc, hop limit 1, không user data, SG chặn cổng 22 bằng validation | Container không lấy được credential của role; cấu hình máy do Ansible làm | [AWS 04](../../../06-AWS/04-ec2.md) |
| Ansible kết nối `amazon.aws.aws_ssm` | Không mở cổng 22; file chuyển qua bucket trung chuyển (tắt versioning vì file tạm có thể chứa dữ liệu nhạy cảm) | Lab 03 |
| `inventory/group_vars/all.yml` | Ansible chỉ đọc `group_vars/` cạnh inventory hoặc cạnh playbook — đặt sai chỗ thì biến kết nối bị bỏ qua và Ansible quay về SSH | Lab 03 |
| Handler **restart** container nginx (không reload) | `copy` thay file bằng inode mới; bind mount một file vẫn trỏ inode cũ | Lab 03 (thí nghiệm G3) |
| [terraform/.trivyignore](terraform/.trivyignore): 4 phát hiện chấp nhận, mỗi cái có lý do + hạn `exp:` | `trivy config` báo 1 CRITICAL + 6 HIGH cho code này — tất cả là đánh đổi có chủ ý (public subnet, egress, không CMK, SNS không mã hóa vì CloudWatch alarm không dùng được key AWS managed). Không giải thích được thì không được bỏ qua | Bài 04 |
| Phiên bản ghim: Terraform `~> 1.17`, AWS provider `~> 6.0`, `amazon.aws` 12.0.0, `community.docker` 5.4.0, commit `.terraform.lock.hcl` | Build lặp lại được; nâng cấp có chủ đích | Bài 02, 05 |

> Interface của module `network` trong bản này giống module bạn refactor ở lab bài 04. Bài 04 dùng tiền tố `tf07` và VPC `10.30.0.0/16` để luyện tập riêng; bản này là cấu hình thật của dự án (`taskhub`, `10.20.0.0/16`).
