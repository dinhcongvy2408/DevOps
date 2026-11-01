# Module 07 — Infrastructure as Code: Terraform + Ansible

> Tuần 15–16 · ~34 giờ · Mức độ: 🟥 Bắt buộc (Terraform) · 🟨 Nên biết (Ansible cơ bản) · Kiến thức cần có trước: [Module 06 — AWS](../06-AWS/README.md), dự án [taskhub v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md) đã xong (và **đã dọn dẹp** theo [v3 §11](../12-PRACTICAL-PROJECT/milestones/v3-cd.md#11-dọn-dẹp))

## Mục lục

- [1. Vì sao DevOps phải biết Infrastructure as Code?](#1-vì-sao-devops-phải-biết-infrastructure-as-code)
- [2. Vì sao Terraform, và Terraform hay OpenTofu?](#2-vì-sao-terraform-và-terraform-hay-opentofu)
- [3. Junior cần biết đến mức nào?](#3-junior-cần-biết-đến-mức-nào)
- [4. Chuẩn bị và cài đặt công cụ](#4-chuẩn-bị-và-cài-đặt-công-cụ)
- [5. An toàn chi phí](#5-an-toàn-chi-phí)
- [6. Thứ tự bài học](#6-thứ-tự-bài-học)
- [7. Lab, break-fix, checkpoint và dự án](#7-lab-break-fix-checkpoint-và-dự-án)
- [8. Quy ước dùng chung trong module](#8-quy-ước-dùng-chung-trong-module)
- [9. IaC trong các module sau](#9-iac-trong-các-module-sau)
- [10. Checklist hoàn thành module](#10-checklist-hoàn-thành-module)
- [11. Nguồn học](#11-nguồn-học)

---

## 1. Vì sao DevOps phải biết Infrastructure as Code?

Ở tuần 11–14, bạn đã dựng `taskhub` trên AWS **bằng tay**: hơn 20 tài nguyên (VPC, 4 subnet, IGW, 2 route table, SG, role, policy, EC2, Parameter Store, OIDC provider, role deploy, log group, 2 alarm, SNS…), từng cái qua console hoặc lệnh CLI chép từ `commands.md`. Rồi ở [v3 §11](../12-PRACTICAL-PROJECT/milestones/v3-cd.md#11-dọn-dẹp) bạn xóa sạch tất cả, cũng bằng tay, theo đúng thứ tự phụ thuộc.

Hãy tự hỏi: nếu ngày mai phải dựng lại y hệt — **mất bao lâu, và có chắc giống hệt không?**

**Infrastructure as Code** (IaC — hạ tầng dưới dạng mã) trả lời câu hỏi đó: hạ tầng được **mô tả trong file văn bản**, nằm trong Git, được review qua Pull Request, và một công cụ biến mô tả thành tài nguyên thật. Dựng lại = một lệnh. Xóa sạch = một lệnh.

| Bạn sẽ làm ở công việc thật | Cần kiến thức của module này |
|---|---|
| "Dựng môi trường staging giống hệt production" | Terraform module + môi trường (bài 04) |
| "Ai đã sửa security group này trên console?" | Drift, `terraform plan` phát hiện thay đổi ngoài code (bài 03, [break-fix](labs/break-fix-01/README.md)) |
| "State bị khóa, không apply được" | Remote state, lock file, `force-unlock` (bài 03) |
| "Review giúp PR hạ tầng này" | Đọc `terraform plan` — biết cái gì bị **xóa và tạo lại** (bài 02) |
| "Cài Docker và cấu hình 10 server giống nhau" | Ansible playbook, role, idempotency (bài 05) |
| "Đưa tài nguyên đang chạy vào Terraform mà không xóa" | `import` block (bài 03) |
| Phỏng vấn: "Terraform state là gì, lưu ở đâu, vì sao không commit lên Git?" | Bài 03 — câu hỏi gần như chắc chắn gặp |

> **Bạn đã có lợi thế.** Đã dựng tay ở Module 06 nghĩa là mỗi `resource` bạn sắp viết đều tương ứng với một thứ bạn từng bấm và từng debug. Người học Terraform mà chưa từng dựng tay thường viết được code nhưng không debug được khi `apply` lỗi.

---

## 2. Vì sao Terraform, và Terraform hay OpenTofu?

| Tiêu chí | Terraform | CloudFormation | Pulumi / AWS CDK |
|---|---|---|---|
| Cloud hỗ trợ | Rất nhiều (AWS, Azure, GCP, GitHub, Docker…) qua **provider** | Chỉ AWS | Nhiều (Pulumi) / chủ yếu AWS (CDK) |
| Ngôn ngữ | HCL — khai báo, dễ đọc khi review | YAML/JSON | Ngôn ngữ lập trình (TypeScript, Python, Java…) |
| Phổ biến trong JD | **Rất phổ biến** — gần như mặc định khi nói "IaC" | Phổ biến ở công ty thuần AWS | Ít hơn |
| Bạn đã gặp | Module này | Break-fix bài [06-AWS](../06-AWS/labs/break-fix-01/README.md) | — |

Bài [01](01-iac-concepts.md) có bảng so sánh đầy đủ hơn, gồm cả Ansible/Chef/Puppet.

**Về giấy phép (đọc để không ngạc nhiên khi gặp chữ "OpenTofu"):**

- Ngày **10/8/2023**, HashiCorp chuyển Terraform (các bản phát hành sau đó) từ giấy phép mã nguồn mở MPL 2.0 sang **Business Source License (BSL) 1.1**. Người dùng cuối vẫn được dùng miễn phí, kể cả cho production; điều bị hạn chế là xây sản phẩm **cạnh tranh** với HashiCorp. Bạn dùng Terraform để học và đi làm là hoàn toàn bình thường.
- Một nhóm công ty (Gruntwork, Spacelift, Harness, env0, Scalr…) đã tạo **OpenTofu** — bản fork mã nguồn mở, do **Linux Foundation** quản lý. OpenTofu tương thích với state file của Terraform tới bản 1.5.x, dùng chung các provider, lệnh là `tofu` thay cho `terraform`.
- Giáo trình dùng **Terraform** vì phổ biến hơn trong tin tuyển dụng và tài liệu. Kiến thức ở đây áp dụng gần như nguyên vẹn cho OpenTofu (khác biệt ở các tính năng mới sau khi tách nhánh).

**Còn Ansible thì sao?** Terraform giỏi **tạo** tài nguyên (máy, mạng, quyền). Nó không được thiết kế để **cấu hình bên trong** máy (cài gói, chép file cấu hình, khởi động service). Ở v2/v3 bạn làm phần đó bằng user data và bằng tay — và gặp giới hạn "thay đổi `compose.yaml` phải sửa tay trên máy" (hệ quả ghi trong ADR-0007 của [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md)). **Ansible** là công cụ cấu hình (configuration management) phổ biến nhất, không cần cài agent trên máy đích. Module này dạy Ansible ở mức đủ dùng cho dự án.

---

## 3. Junior cần biết đến mức nào?

| Chủ đề | Mức cần cho Junior | Có thể học sau |
|---|---|---|
| Khái niệm IaC: khai báo, idempotent, drift, state | 🟥 Giải thích bằng ví dụ của chính dự án | — |
| Terraform: provider, resource, data source, variable, output, locals | 🟥 **Tự viết** hạ tầng `taskhub` | `for_each`/`dynamic` phức tạp |
| Workflow `init` → `plan` → `apply` → `destroy` | 🟥 **Đọc plan**: phân biệt `+`, `~`, `-/+`, `-` | — |
| State, remote backend S3 + `use_lockfile` | 🟥 Giải thích state chứa gì, vì sao không commit, khóa để làm gì | Terraform Cloud/HCP, workspace phức tạp |
| Drift, `import`, `terraform state` | 🟥 Phát hiện và xử lý drift ([break-fix](labs/break-fix-01/README.md)) | `moved` block, tách/gộp state |
| Module, môi trường dev/prod | 🟥 Viết module `network` và `app_server`, root module `envs/dev` | Module registry riêng, Terragrunt |
| Secret trong IaC | 🟥 Biết state có thể chứa secret; dùng **write-only argument** | Vault |
| Kiểm tra code: `fmt`, `validate`, tflint, quét cấu hình | 🟨 Chạy trong CI trên PR | Policy as code (OPA, Sentinel) |
| Ansible: inventory, playbook, module, idempotency | 🟨 Viết playbook cài Docker + triển khai `taskhub` | Ansible Tower/AWX, viết module riêng |
| Ansible: role, template, handler, biến | 🟨 Đọc và sửa role có sẵn | Molecule (test role) |
| Packer, Pulumi, CDK, Chef, Puppet | 🟦 Biết là gì, khi nào dùng | Học khi công việc cần |

**Quy tắc vàng của module:** sau tuần 16, bạn dựng **toàn bộ** hạ tầng `taskhub` từ con số 0 bằng `terraform apply` + `ansible-playbook`, và xóa sạch bằng `terraform destroy` — rồi chứng minh bằng [`find-leftovers.sh`](../06-AWS/06-aws-cli.md) rằng không còn gì sót.

---

## 4. Chuẩn bị và cài đặt công cụ

**Kiểm tra trước khi học:**

| Cần có | Kiểm tra | Nếu chưa có |
|---|---|---|
| Hạ tầng tay của v2/v3 **đã xóa** | `~/devops-lab/06-aws/find-leftovers.sh` báo sạch (trừ bucket backup nếu bạn giữ lại) | [v3 §11](../12-PRACTICAL-PROJECT/milestones/v3-cd.md#11-dọn-dẹp) |
| AWS CLI v2 đăng nhập được | `aws sts get-caller-identity --profile taskhub` | [AWS bài 06](../06-AWS/06-aws-cli.md) |
| Docker chạy được **trong WSL** | `docker info` trong WSL không báo `Cannot connect to the Docker daemon` | Bật WSL integration — xem bảng lỗi ở [Docker bài 01](../04-DOCKER/01-vm-vs-container-architecture.md) |
| Git, repo `taskhub` ở `~/projects/taskhub` | `git -C ~/projects/taskhub status` | [Git bài ôn tập](../03-GIT/00-git-quick-review.md) |

> **Môi trường của bạn:** WSL **Ubuntu 24.04** (Python 3.12). Các module trước có chỗ ghi 22.04 — đó là thông tin cũ; lệnh trong module này viết cho 24.04.

**Công cụ cài mới trong module** (mỗi công cụ được cài **trong bài dùng đến nó**, kèm giải thích từng lệnh):

| Công cụ | Dùng để | Cách cài (tóm tắt) | Bài cài |
|---|---|---|---|
| Terraform CLI (`~> 1.17`) | Dựng/xóa hạ tầng | Kho apt chính thức của HashiCorp (thêm GPG key → thêm repo → `apt install terraform`) | [Bài 02](02-terraform-basics.md) |
| `pipx` + Ansible (ansible-core 2.21) | Cấu hình server | `sudo apt install pipx` → `pipx install --include-deps ansible` → `pipx inject ansible boto3 botocore` | [Bài 05](05-ansible-fundamentals.md) |
| Collection `amazon.aws`, `community.docker` | Inventory EC2, kết nối qua SSM / Docker | `ansible-galaxy collection install -r requirements.yml` (phiên bản được ghim) | [Bài 05](05-ansible-fundamentals.md) |
| `session-manager-plugin` | Ansible (và `aws ssm start-session`) kết nối EC2 qua SSM, không cần SSH | Gói `.deb` theo tài liệu AWS | [Lab 03](labs/lab-03-ansible-ssm.md) |
| 🟨 tflint | Lint code Terraform | Theo hướng dẫn của dự án tflint | [Bài 04](04-terraform-modules-environments.md) |

Thư mục làm việc cho bài tập ngoài repo:

```bash
mkdir -p ~/devops-lab/07-iac && cd ~/devops-lab/07-iac
```

**Nhãn môi trường dùng trong module:**

| Nhãn | Nghĩa |
|---|---|
| `[WSL]` | Terminal Ubuntu trên laptop — Terraform, Ansible, AWS CLI chạy ở đây |
| `[Container]` | Bên trong một container lab (máy đích của Ansible ở bài 05) |
| `[AWS Console]` | Giao diện web console.aws.amazon.com |
| `[EC2]` | Bên trong máy EC2 (qua SSM Session Manager) |
| `[GitHub]` | Giao diện web github.com |
| `[Runner]` | Bên trong workflow GitHub Actions |

---

## 5. An toàn chi phí

> ⚠️ Terraform làm việc **tạo** tài nguyên dễ đến mức nguy hiểm: một lệnh `apply` có thể tạo 30 tài nguyên trong 2 phút. Cũng chính nó làm việc **xóa** dễ như vậy — hãy tận dụng.

| Nguyên tắc | Chi tiết |
|---|---|
| **Học local trước, AWS sau** | Bài 02 và [Lab 01](labs/lab-01-terraform-local-docker.md) dùng provider Docker trên laptop — **0 USD**. Bài 05 dùng container local làm máy đích Ansible — **0 USD**. [Break-fix](labs/break-fix-01/README.md) chạy hoàn toàn local |
| **`terraform destroy` khi dừng học** | Kết thúc mỗi buổi có AWS: `terraform -chdir=infra/terraform/envs/dev destroy`. Hôm sau `apply` lại — 5–10 phút. Đây là lợi ích lớn nhất của IaC đối với túi tiền của bạn |
| **Đọc plan trước khi gõ `yes`** | Dòng cuối `Plan: X to add, Y to change, Z to destroy` — Z khác 0 mà bạn không chờ đợi → **dừng lại** |
| **Không bao giờ `-auto-approve`** khi làm với AWS ở module này | Thói quen tốt: luôn nhìn plan bằng mắt |
| Bucket state và bucket backup cần được bảo vệ khỏi `destroy` | Bucket state tạo ở thư mục `bootstrap/` riêng (không nằm trong root module `envs/dev`); bucket backup chứa dữ liệu — bảo vệ bằng `lifecycle { prevent_destroy = true }` ([bài 03](03-terraform-state-backend.md)). Cả hai gần như 0 USD khi ít dữ liệu |
| Sau `destroy` | Chạy `~/devops-lab/06-aws/find-leftovers.sh` — Terraform chỉ xóa thứ **nó quản lý**; thứ bạn tạo tay vẫn còn |
| Ai chạy lệnh AWS | **Chỉ bạn.** Mọi lệnh tạo/xóa tài nguyên tính phí được đánh dấu ⚠️ |

Cùng hạ tầng như v3, nên chi phí khi đang chạy giống [v3 §3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md#3-chi-phí). Khác biệt: bạn có thể **xóa hẳn** thay vì chỉ stop (không còn tiền EBS và IPv4 khi không học).

---

## 6. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 01 | [Khái niệm Infrastructure as Code](01-iac-concepts.md) — khai báo vs mệnh lệnh, idempotent, drift, công cụ nào cho việc gì | 15 | 2h | 🟥 |
| 02 | [Terraform cơ bản](02-terraform-basics.md) — cài đặt, provider, resource, data source, variable, output, workflow | 15 | 5h | 🟥 |
| — | [Lab 01 — Terraform với Docker trên laptop](labs/lab-01-terraform-local-docker.md) + tutorial chính thức *Get Started — AWS* | 15 | 3h | 🟥 |
| 03 | [State và remote backend](03-terraform-state-backend.md) — state, S3 + `use_lockfile`, drift, `import` | 15–16 | 4h | 🟥 |
| — | [Lab 02 — Viết lại hạ tầng taskhub bằng Terraform](labs/lab-02-taskhub-infra-terraform.md) | 15–16 | 5h | 🟥 |
| 04 | [Module và môi trường](04-terraform-modules-environments.md) — module, dev/prod, kiểm tra code trong CI | 16 | 3h | 🟥 |
| 05 | [Ansible cơ bản](05-ansible-fundamentals.md) — inventory, playbook, module, idempotency, role | 16 | 4h | 🟨 |
| — | [Lab 03 — Ansible cấu hình EC2 qua SSM](labs/lab-03-ansible-ssm.md) | 16 | 3h | 🟨 |

Lời giải câu hỏi và bài tập: thư mục [solutions/](solutions/) — **chỉ mở sau khi đã tự làm**. Thuật ngữ: [glossary.md](glossary.md). Code tham khảo (Terraform + Ansible hoàn chỉnh cho `taskhub`): [labs/reference/](labs/reference/README.md) — ⚠️ chỉ mở sau khi đã tự viết.

---

## 7. Lab, break-fix, checkpoint và dự án

| Hạng mục | Tuần | Mô tả |
|---|---|---|
| [Lab 01 — Terraform với Docker](labs/lab-01-terraform-local-docker.md) | 15 | **Lab bắt buộc, 0 USD:** network, volume, container nginx do Terraform quản lý; thay đổi, đọc plan, destroy |
| [Lab 02 — Hạ tầng taskhub bằng Terraform](labs/lab-02-taskhub-infra-terraform.md) | 15–16 | **Lab bắt buộc:** VPC + SG + EC2 + IAM của dự án viết bằng Terraform; dựng/xóa toàn bộ bằng 1 lệnh |
| [Lab 03 — Ansible qua SSM](labs/lab-03-ansible-ssm.md) | 16 | **Lab bắt buộc:** playbook cài Docker và triển khai `taskhub` lên EC2 — không mở port 22 |
| [Break-fix Terraform #1](labs/break-fix-01/README.md) | 16 | State drift: hạ tầng bị sửa ngoài code — tìm, hiểu, đưa về đúng. Chạy local, **0 USD** |
| [Checkpoint Giai đoạn 7](checkpoint.md) | 16 | Lý thuyết + thực hành mới + break-fix, không dùng AI |
| [Dự án: taskhub v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) | 15–16 | Toàn bộ hạ tầng AWS bằng Terraform (state trên S3), server cấu hình bằng Ansible; release `v0.6.0` |

---

## 8. Quy ước dùng chung trong module

| Thành phần | Giá trị |
|---|---|
| Terraform | `required_version = "~> 1.17"` (bản mới nhất khi viết: 1.17.1, 28/10/2026). **Commit** `.terraform.lock.hcl`, **không commit** `*.tfstate`, `.terraform/`, `*.tfvars` chứa giá trị riêng |
| Provider | `hashicorp/aws ~> 6.0` · `kreuzwerker/docker ~> 4.6` (lab local) · `hashicorp/random`, `hashicorp/local` |
| Tag mặc định | `default_tags` trong provider AWS: `Project=taskhub`, `Env=dev`, `Owner=<tên bạn>`, `ManagedBy=terraform` |
| Tên tài nguyên | Giữ nguyên như Module 06: `taskhub-vpc`, `taskhub-public-a/b`, `taskhub-private-a/b`, `taskhub-web-sg`, `taskhub-app`, `taskhub-ec2-role`… |
| Cấu trúc code | `infra/terraform/bootstrap/` (tạo bucket state) · `infra/terraform/modules/{network,app_server}` · `infra/terraform/envs/dev/` (root module) · `infra/ansible/` |
| State | S3 bucket `taskhub-tfstate-<account-id>` (versioning, Block Public Access, mã hóa), key `envs/dev/terraform.tfstate`, `use_lockfile = true` — **không** dùng DynamoDB (đã deprecated) |
| Biến chính | `project = "taskhub"`, `env = "dev"`, `region = "ap-southeast-1"`, `owner`, `github_repo`, `alert_email`, `instance_type = "t3.small"`, `vpc_cidr = "10.20.0.0/16"` |
| Output chính | `instance_id`, `public_ip`, `app_url`, `deploy_role_arn`, `ansible_ssm_bucket` |
| Secret | Mật khẩu PostgreSQL vào Parameter Store bằng **write-only argument** `value_wo` (Terraform ≥ 1.11) — **không bao giờ** nằm trong state |
| Ansible | ansible-core 2.21 (cài bằng pipx), collection ghim trong `requirements.yml`, inventory động `amazon.aws.aws_ec2` (lọc tag `Project=taskhub`), kết nối `amazon.aws.aws_ssm` qua bucket `taskhub-ansible-ssm-<account-id>` |
| Lab local | Tên tài nguyên Docker tiền tố `tf07-` (Terraform), `ans07-` (Ansible) |
| Phát hành | v4 → `v0.6.0` |
| Số tài khoản trong ví dụ | `111122223333` · GitHub user mẫu `phuong-dev` |

---

## 9. IaC trong các module sau

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| `terraform apply`/`destroy` toàn bộ hạ tầng | Mọi buổi học AWS từ nay: dựng đầu buổi, xóa cuối buổi |
| Module `app_server`, Ansible role `taskhub` | Thêm Prometheus, Grafana, Loki, Alloy vào cùng máy (Module 08, v5) |
| Bucket S3 do Terraform quản lý | Backup `pg_dump` tự động + diễn tập restore (Module 08, v5) |
| Khai báo, desired state, reconcile | Kubernetes manifest và Helm chart — cùng triết lý (Module 09, v6) |
| Quét cấu hình IaC (`trivy config`), secret trong state | Rà soát bảo mật DevSecOps (Module 10) |
| Kiểm tra Terraform trong CI | Mở rộng pipeline khi đi làm (plan trên PR qua OIDC 🟦) |

---

## 10. Checklist hoàn thành module

- [ ] 🟥 Giải thích được khai báo vs mệnh lệnh, idempotency, desired state, drift bằng ví dụ của `taskhub`.
- [ ] 🟥 Phân biệt được Terraform (tạo hạ tầng) và Ansible (cấu hình bên trong máy); biết OpenTofu là gì.
- [ ] 🟥 Cài Terraform từ kho apt chính thức; viết được provider, resource, data source, variable, output, locals.
- [ ] 🟥 Đọc plan: chỉ ra tài nguyên nào bị **thay thế** (`-/+`) và vì sao.
- [ ] 🟥 Giải thích state chứa gì, vì sao không commit, vì sao cần khóa; dựng backend S3 với `use_lockfile`.
- [ ] 🟥 Phát hiện và xử lý drift ([break-fix](labs/break-fix-01/README.md)); dùng được `import` block.
- [ ] 🟥 Viết module `network` + `app_server` và root module `envs/dev`.
- [ ] 🟥 Mật khẩu database **không** có trong state (kiểm chứng bằng `terraform state pull | grep`).
- [ ] 🟨 Viết playbook Ansible idempotent: chạy lần 2 báo `changed=0`.
- [ ] 🟨 Ansible kết nối EC2 qua SSM — không mở port 22.
- [ ] 🟥 Dựng toàn bộ `taskhub` từ 0 và xóa sạch, `find-leftovers.sh` xác nhận.
- [ ] 🟥 Đạt [Checkpoint Giai đoạn 7](checkpoint.md) và hoàn thành [taskhub v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md).

---

## 11. Nguồn học

| Vai trò | Nguồn | Ghi chú | Kiểm tra ngày |
|---|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt, gắn với dự án `taskhub` | — |
| Chính | [Terraform Documentation](https://developer.hashicorp.com/terraform/docs) | Ngôn ngữ, CLI, backend | 2026-10-31 |
| Chính | [Terraform — Install](https://developer.hashicorp.com/terraform/install) | Kho apt chính thức cho Ubuntu | 2026-10-31 |
| Chính | [Terraform tutorials — Get Started (AWS)](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) | Tutorial chính thức, làm trong tuần 15 | 2026-10-31 |
| Chính | [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) | `use_lockfile`; DynamoDB locking đã deprecated | 2026-10-31 |
| Chính | [AWS provider documentation (Terraform Registry)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) | Tra từng resource | 2026-10-31 |
| Chính | [Ansible Documentation](https://docs.ansible.com/) | Cài đặt, playbook, module, collection | 2026-10-31 |
| Bối cảnh | [HashiCorp adopts the Business Source License](https://www.hashicorp.com/en/blog/hashicorp-adopts-business-source-license) | Thay đổi giấy phép 10/8/2023 | 2026-10-31 |
| Bối cảnh | [OpenTofu FAQ](https://opentofu.org/faq/) | Fork của Terraform, Linux Foundation | 2026-10-31 |

Thuật ngữ của module: [glossary.md](glossary.md).
