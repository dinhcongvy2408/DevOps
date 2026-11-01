# Milestone v4 — Hạ tầng bằng Terraform, cài đặt máy chủ bằng Ansible (tuần 15–16)

> Mức độ: 🟥 Bắt buộc (Makefile, plan trong CI là 🟦 tùy chọn) · Kiến thức cần có trước: milestone [v3 — CD](v3-cd.md) (release `v0.5.0`, đã **dọn dẹp** theo [v3 §11](v3-cd.md#11-dọn-dẹp)), [Module 07 — Terraform & Ansible](../../07-TERRAFORM-ANSIBLE/README.md)
> Môi trường: `[WSL]` (terraform, ansible, aws, session-manager-plugin), `[AWS Console]` (chỉ để **xem** và làm thử nghiệm drift), `[GitHub]`, `[Runner]`, `[EC2]`
> Đây là **việc cần nộp + tiêu chí chấp nhận**. Kiến thức nền: [bài 01 — IaC](../../07-TERRAFORM-ANSIBLE/01-iac-concepts.md), [bài 02 — Terraform cơ bản](../../07-TERRAFORM-ANSIBLE/02-terraform-basics.md), [bài 03 — State & backend](../../07-TERRAFORM-ANSIBLE/03-terraform-state-backend.md), [bài 04 — Module & môi trường](../../07-TERRAFORM-ANSIBLE/04-terraform-modules-environments.md), [bài 05 — Ansible](../../07-TERRAFORM-ANSIBLE/05-ansible-fundamentals.md). Các bước làm chi tiết: [Lab 02 — Hạ tầng taskhub bằng Terraform](../../07-TERRAFORM-ANSIBLE/labs/lab-02-taskhub-infra-terraform.md) (tuần 15) và [Lab 03 — Ansible qua SSM](../../07-TERRAFORM-ANSIBLE/labs/lab-03-ansible-ssm.md) (tuần 16).

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc v4](#2-kiến-trúc-v4)
- [3. Chi phí và chiến lược stop/destroy](#3-chi-phí-và-chiến-lược-stopdestroy)
- [4. Điểm xuất phát](#4-điểm-xuất-phát)
- [5. File phải có trong repo](#5-file-phải-có-trong-repo)
- [6. Yêu cầu chất lượng](#6-yêu-cầu-chất-lượng)
- [7. Thử nghiệm bắt buộc](#7-thử-nghiệm-bắt-buộc)
- [8. Xử lý sự cố thường gặp](#8-xử-lý-sự-cố-thường-gặp)
- [9. Câu hỏi tự kiểm](#9-câu-hỏi-tự-kiểm)
- [10. Definition of Done và release v0.6.0](#10-definition-of-done-và-release-v060)
- [11. Dọn dẹp](#11-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

Ở v2–v3 bạn dựng hạ tầng bằng tay và ghi lệnh vào `infra/aws-manual/commands.md`. Từ v4, **hạ tầng là code**:

```text
make up   = terraform apply  →  ansible-playbook site.yml  →  app chạy đúng tag
make down = terraform destroy (chỉ phần tính tiền) → chỉ còn state + backup trên S3
```

Cụ thể:

1. **Mọi tài nguyên AWS của dự án** (VPC, subnet, IGW, route table, SG, IAM role/policy, EC2, OIDC provider + role deploy, log group, alarm, SNS, tham số mật khẩu, bucket) được mô tả bằng **Terraform** và có tag `ManagedBy=terraform`. Không còn tài nguyên `ManagedBy=manual` nào (trừ Budget và user admin).
2. **State** nằm trên S3 (bucket có versioning, chặn public, chỉ cho TLS), **khóa bằng `use_lockfile`** — không DynamoDB.
3. **Ansible** cài Docker và đưa `compose.yaml`, `compose.aws.yaml`, cấu hình nginx, `deploy.sh` lên máy **qua SSM** (không SSH, không port 22). Giới hạn "đổi compose phải làm tay" của v3 biến mất.
4. Dựng lại toàn bộ từ con số 0 tới app trả `UP` trong **< 30 phút**, và **chạy lại không đổi gì**: `terraform plan` → *No changes*, Ansible lần 2 → `changed=0`.
5. **Mật khẩu database không bao giờ nằm trong state** (đối số write-only `value_wo`).
6. PR chạm `infra/**` được kiểm tra tự động (`fmt`, `validate`, tflint, `trivy config`) — **không cần** quyền AWS.

Vì sao quan trọng: "Hạ tầng của bạn dựng lại được không? Mất bao lâu?" là câu hỏi phân biệt người *đã dùng* AWS và người *vận hành được* AWS. Với v4, câu trả lời là một con số đo thật.

---

## 2. Kiến trúc v4

```text
 [WSL] repo taskhub
   infra/terraform/bootstrap  ── state cục bộ → migrate lên S3 ──► S3 taskhub-tfstate-<account-id>
   (lớp BỀN: chạy 1 lần)          tạo:  • bucket state  (versioning, BPA, SSE-S3, chỉ TLS, prevent_destroy)
                                        • import bucket backup taskhub-backups-<account-id> (từ bài S3, prevent_destroy)
                                                                  │  key bootstrap/terraform.tfstate
   infra/terraform/envs/dev   ── backend "s3" (use_lockfile) ─────┤  key envs/dev/terraform.tfstate
   (lớp DỰNG/XÓA hằng ngày)       gọi module:                     │  (+ envs/dev/terraform.tfstate.tflock khi đang chạy)
     ├─ module network     → VPC 10.20.0.0/16 · 2 public + 2 private subnet · IGW · route table (không NAT)
     ├─ module app_server  → SG taskhub-web-sg (80) · role/profile taskhub-ec2-role (+ taskhub-ec2-app, taskhub-ec2-s3-backup)
     │                       · EC2 taskhub-app t3.small Ubuntu 24.04 (AMI từ tham số SSM), IMDSv2 hop 1, gp3 20 GiB mã hóa
     └─ tài nguyên ở root  → OIDC provider GitHub + role taskhub-github-deploy · log group /taskhub/dev/app (7 ngày)
                             · alarm taskhub-cpu-high, taskhub-status-check → SNS taskhub-alerts
                             · /taskhub/dev/postgres-password (SecureString, value_wo — không vào state)
                             · bucket taskhub-ansible-ssm-<account-id> (file tạm của Ansible, tự xóa sau 1 ngày)
   outputs: instance_id · public_ip · app_url · deploy_role_arn · ansible_ssm_bucket

 [WSL] infra/ansible
   inventory/aws_ec2.yml (amazon.aws.aws_ec2: tag Project=taskhub, running)
   ansible-playbook playbooks/site.yml ──connection amazon.aws.aws_ssm──► SSM ──► EC2 taskhub-app
        role docker  → Docker Engine + compose plugin từ apt repo chính thức
        role taskhub → /opt/taskhub: compose.yaml, compose.aws.yaml, docker/nginx/default.conf, scripts/deploy.sh → deploy.sh <tag>
        (file đi qua bucket taskhub-ansible-ssm-…: Ansible tải lên, EC2 tải về bằng presigned URL)

 [GitHub] CI · Release (v1) · Deploy (v3 — bật lại, dùng role ARN mới) · infra.yml (MỚI: kiểm tra code hạ tầng)
```

**Vì sao tách hai lớp `bootstrap` và `envs/dev`?** Bucket state và bucket backup chứa **dữ liệu không dựng lại được**. Chúng có `prevent_destroy = true` — nếu nằm chung với EC2 trong `envs/dev` thì `terraform destroy` sẽ **báo lỗi và dừng**, và bạn sẽ bị cám dỗ xóa `prevent_destroy` để "cho chạy được". Tách ra: `envs/dev` xóa sạch bằng **một lệnh**, lớp bền không bao giờ bị đụng tới. Đây cũng là câu trả lời cho bài toán con gà – quả trứng: bucket state không thể được tạo bởi chính cấu hình dùng nó làm backend ([bài 03](../../07-TERRAFORM-ANSIBLE/03-terraform-state-backend.md)).

| Lớp | Root module | State ở đâu | Bao lâu chạy một lần | Lệnh xóa |
|---|---|---|---|---|
| Bền | `infra/terraform/bootstrap` | Đầu tiên: file cục bộ → sau khi tạo bucket: migrate lên S3 key `bootstrap/terraform.tfstate` | Một lần (và khi đổi chính sách bucket) | Không xóa trong suốt khóa học |
| Dựng/xóa | `infra/terraform/envs/dev` | S3 key `envs/dev/terraform.tfstate`, `use_lockfile = true` | Mỗi buổi học | `terraform destroy` |

> Nếu [bản tham khảo](../../07-TERRAFORM-ANSIBLE/labs/reference/README.md) của module đặt bucket backup ở chỗ khác, hãy so sánh hai cách và ghi lựa chọn của bạn vào ADR-0008 — điều kiện bắt buộc chỉ có một: **`terraform destroy` ở `envs/dev` không được làm mất (hay bị chặn bởi) bucket backup**.

---

## 3. Chi phí và chiến lược stop/destroy

Chi phí **khi đang chạy** giống hệt v3 — Terraform không làm hạ tầng đắt hơn. Số liệu ap-southeast-1 lấy từ [AWS bài 11 — Ghép thành hệ thống](../../06-AWS/11-putting-it-together.md) (giá kiểm tra 2026-10-31):

| Khoản | Đơn giá | Khi nào tính | Ghi chú v4 |
|---|---|---|---|
| EC2 `t3.small` | ≈ 0,0264 USD/giờ | Khi running | Mất hẳn sau `terraform destroy` |
| EBS gp3 20 GiB | ≈ 0,096 USD/GB-tháng (≈ 1,9 USD/tháng) | **Luôn**, kể cả khi stop | Mất hẳn sau destroy — đây là khoản `stop` không tiết kiệm được |
| Public IPv4 | 0,005 USD/giờ | Khi running | |
| CloudWatch Logs, 2 alarm, SNS | Như [v3 §3](v3-cd.md#3-chi-phí) | | Log group bị destroy cùng `envs/dev` → log cũ mất (ghi vào ADR) |
| S3 state (`taskhub-tfstate-…`) | ≈ 0,025 USD/GB-tháng + request | Luôn | Vài chục KB × số phiên bản → **gần 0** |
| S3 `taskhub-ansible-ssm-…` | như trên | | Lifecycle xóa sau 1 ngày → gần 0 |
| S3 backup | như trên | Luôn | Không đổi so với bài S3 |
| VPC, IAM, OIDC, Parameter Store Standard | 0 | | |

Chạy 24/7 ≈ **25 USD/tháng** (bài AWS 11) — credit Free plan không đủ cho 6 tháng. v4 cho bạn cách rẻ nhất:

| Cách kết thúc buổi học | Còn trả tiền | Dữ liệu database | Thời gian bắt đầu buổi sau |
|---|---|---|---|
| Để chạy | Mọi thứ | Còn | 0 |
| Stop EC2 (như v2–v3) | EBS (~1,9 USD/tháng) | Còn | ~2 phút + cập nhật `APP_URL` |
| ⚠️ **`terraform destroy` ở `envs/dev`** (mặc định từ v4) | Chỉ S3 (≈ 0) | **Mất** (chưa có backup — v5 giải quyết) | Thời gian T1 (mục tiêu < 30 phút) |

Ở tuần 15–16 dữ liệu chỉ là dữ liệu thử → **destroy sau mỗi buổi** là mặc định. Ghi số giờ chạy và số dư credit vào `docs/cost.md` như các phiên bản trước.

---

## 4. Điểm xuất phát

Trạng thái sau [v3 §11](v3-cd.md#11-dọn-dẹp) — kiểm tra **trước khi** viết dòng Terraform đầu tiên:

| Tài nguyên | Trạng thái mong đợi | Kiểm tra | Nếu khác |
|---|---|---|---|
| EC2, SG, `taskhub-ec2-role`, OIDC provider, `taskhub-github-deploy`, log group, alarm, SNS, tham số mật khẩu | **Đã xóa** | `~/devops-lab/06-aws/find-leftovers.sh` ([AWS bài 06](../../06-AWS/06-aws-cli.md)) | Xóa nốt theo v3 §11 — nếu không, `terraform apply` sẽ lỗi *EntityAlreadyExists* / *already exists* |
| VPC `taskhub-vpc` của Lab 01 | Xóa (khuyến nghị) | `aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc` | Xóa theo Lab 01, hoặc 🟦 import vào Terraform (bài tập khó, không bắt buộc) |
| Bucket `taskhub-backups-<account-id>` | **Còn** (bài S3 dặn giữ cho v5) | `aws s3api get-bucket-versioning --bucket taskhub-backups-<account-id>` | Nếu đã xóa: để `bootstrap` **tạo mới** thay vì import |
| Workflow `Deploy` trên GitHub | **Disabled** | Tab Actions | Disable cho tới T9 |
| Budget, user `phuong-admin` | Còn, quản lý tay | — | Không đưa vào Terraform (tài khoản, không phải dự án) |

---

## 5. File phải có trong repo

```text
taskhub/
├── infra/
│   ├── aws-manual/                  # (v2–v3) GIỮ làm tư liệu đối chiếu; thêm dòng đầu README: "không còn dùng từ v4"
│   ├── terraform/
│   │   ├── .tflint.hcl              # MỚI — bật plugin tflint-ruleset-aws (ghim phiên bản)
│   │   ├── bootstrap/               # MỚI — versions.tf, main.tf (bucket state + import bucket backup), outputs.tf, backend.tf (thêm SAU khi bucket có)
│   │   ├── modules/
│   │   │   ├── network/             # MỚI — main.tf, variables.tf, outputs.tf, README.md (input/output)
│   │   │   └── app_server/          # MỚI — như trên; KHÔNG có khối provider
│   │   └── envs/dev/                # MỚI — versions.tf (required_version ~> 1.17, aws ~> 6.0), backend.tf, providers.tf (default_tags),
│   │                                #       main.tf, variables.tf, outputs.tf, terraform.tfvars.example, .terraform.lock.hcl
│   └── ansible/                     # MỚI
│       ├── ansible.cfg
│       ├── requirements.yml         # amazon.aws, community.docker — ghim phiên bản
│       ├── inventory/aws_ec2.yml
│       ├── inventory/group_vars/all.yml  # cạnh inventory, Ansible mới đọc; taskhub_image_tag, bucket SSM, region — KHÔNG có secret
│       ├── playbooks/site.yml
│       └── roles/{docker,taskhub}/
├── .github/workflows/infra.yml      # MỚI — fmt -check · init -backend=false + validate · tflint · trivy config
├── Makefile                         # 🟦 MỚI — up / down / plan / lint
├── .gitignore                       # CẬP NHẬT — .terraform/, *.tfstate, *.tfstate.*, *.tfvars (giữ *.tfvars.example), crash.log
├── docs/
│   ├── architecture.md              # CẬP NHẬT — sơ đồ v4 (hai lớp state, luồng Ansible qua SSM)
│   ├── runbooks/rebuild-from-scratch.md   # MỚI — từ laptop sạch tới app UP; có số phút đo thật (T1)
│   ├── adr/0008-terraform-s3-backend-use-lockfile.md   # MỚI
│   ├── adr/0009-ansible-over-ssm-instead-of-ssh.md     # MỚI
│   ├── cost.md                      # CẬP NHẬT — so sánh stop vs destroy bằng số thật
│   └── experiments/v4-tests.md      # MỚI — kết quả T1–T10
└── README.md                        # CẬP NHẬT — mục "Infrastructure": yêu cầu công cụ, make up/down, outputs, cảnh báo chi phí
```

**Bản tham khảo:** [07-TERRAFORM-ANSIBLE/labs/reference/](../../07-TERRAFORM-ANSIBLE/labs/reference/README.md) (thư mục `terraform/` và `ansible/`). ⚠️ Chỉ mở sau khi bạn đã tự viết và `terraform plan` của bạn đã chạy (đúng hay sai). Chép code Terraform mà không hiểu từng resource là cách nhanh nhất để tạo ra hạ tầng bạn không xóa được.

### 5.1. `infra.yml` — những gì phải có

| Phần | Yêu cầu |
|---|---|
| Trigger | `pull_request` với `paths: ['infra/**', '.github/workflows/infra.yml']`; thêm `push` lên `main` cùng `paths` |
| Required check? | **Không** đặt làm required check — workflow có `paths` sẽ không chạy trên PR không chạm `infra/`, và required check sẽ treo ở *Expected* ([CI/CD bài 02](../../05-CICD/02-github-actions-basics.md)) |
| Quyền | `permissions: contents: read` — **không** `id-token`, **không** secret AWS |
| Terraform | `hashicorp/setup-terraform` (v4.x, ghim SHA) với phiên bản khớp `required_version`; `terraform fmt -check -recursive infra/terraform`; với mỗi root (`bootstrap`, `envs/dev`): `terraform init -backend=false` rồi `terraform validate` |
| tflint | `terraform-linters/setup-tflint` (v6.x, ghim SHA); `tflint --init` rồi `tflint --recursive` |
| IaC scan | `trivy config infra/terraform` (cách chạy Trivy giống job `image` của v1); lỗi HIGH/CRITICAL làm job đỏ; ngoại lệ ghi trong `infra/terraform/.trivyignore` **kèm lý do và ngày hết hạn**, truyền bằng `--ignorefile` (Trivy chỉ tự đọc file ở thư mục làm việc). Code tham khảo chạy thử: không có file ignore thì đỏ với 1 CRITICAL + 6 HIGH, toàn là phát hiện "đúng thiết kế" phải giải thích |
| Ansible 🟨 | `ansible-lint` trên `infra/ansible` |
| Chung | `runs-on: ubuntu-24.04`, `timeout-minutes`, mọi action ghim SHA kèm ghi chú phiên bản (Q2 của [v1](v1-ci.md)) |

🟦 `plan` trong CI (role OIDC **chỉ đọc** riêng cho `pull_request`, in plan vào PR) — chỉ làm khi đã xong mọi thứ khác; ghi rủi ro vào ADR-0008.

### 5.2. Hai ADR

- **ADR-0008 — Terraform + S3 backend với `use_lockfile`.** Lựa chọn: CloudFormation · Terraform state cục bộ · Terraform + S3 + DynamoDB · **Terraform + S3 `use_lockfile`** · OpenTofu. Hệ quả phải có: bài toán bootstrap (bucket state tạo bằng state cục bộ rồi migrate), DynamoDB lock đã bị đánh dấu deprecated trong tài liệu backend S3, giấy phép BSL của Terraform và lựa chọn OpenTofu, ai được đọc state (state chứa ID, ARN, IP — nhưng **không** mật khẩu nhờ `value_wo`), cách tách lớp bền / lớp dựng-xóa.
- **ADR-0009 — Ansible qua SSM thay vì SSH.** Lựa chọn: SSH + mở port 22 tạm thời từ IP của bạn · bastion · **`amazon.aws.aws_ssm`** · user data làm hết · `ansible-pull` chạy trên máy. Hệ quả phải có: cần `session-manager-plugin` trên máy điều khiển, cần bucket S3 trung gian cho file, chậm hơn SSH, phụ thuộc đường ra Internet của EC2 (như v3 T10), không port nào mở vào.

---

## 6. Yêu cầu chất lượng

| # | Yêu cầu | Vì sao | Học ở |
|---|---|---|---|
| Q1 | **Không secret trong state**: tham số `/taskhub/dev/postgres-password` dùng `value_wo` + `value_wo_version`; giá trị sinh bởi tài nguyên/biến *ephemeral* hoặc biến `sensitive`, không có trong `*.tf`, `*.tfvars` hay Git. `terraform state pull \| grep -i -c password` chỉ được thấy **tên** tham số | State là file JSON đọc được bởi bất kỳ ai có quyền đọc bucket; `sensitive = true` chỉ che **output trên màn hình**, không che state | [Bài 03](../../07-TERRAFORM-ANSIBLE/03-terraform-state-backend.md), [Write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only) |
| Q2 | Bucket state: versioning **bật**, Block Public Access 4/4, SSE-S3, bucket policy **từ chối** request không TLS (`aws:SecureTransport = false`), `prevent_destroy = true` | Versioning là "nút undo" khi state hỏng; tài liệu backend S3 khuyến nghị rõ | [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3), [AWS bài 05](../../06-AWS/05-s3.md) |
| Q3 | Backend `envs/dev`: `use_lockfile = true`, `encrypt = true`, **không** `dynamodb_table` | Khóa state ngăn hai `apply` cùng lúc ghi đè nhau | Bài 03 |
| Q4 | `.terraform.lock.hcl` của mỗi root được **commit**; `required_version = "~> 1.17"`; provider ghim (`aws ~> 6.0`, …); collection Ansible ghim trong `requirements.yml` | Cùng một commit → cùng phiên bản provider trên laptop, CI và máy người khác | [Bài 02](../../07-TERRAFORM-ANSIBLE/02-terraform-basics.md) |
| Q5 | **Idempotent**: ngay sau `apply`, `terraform plan -detailed-exitcode` trả **0** (*No changes*); Ansible chạy lần 2 → `changed=0` | Code mô tả **trạng thái mong muốn**; còn thay đổi ở lần 2 nghĩa là code không phản ánh đúng thực tế | [Bài 01](../../07-TERRAFORM-ANSIBLE/01-iac-concepts.md), [bài 05](../../07-TERRAFORM-ANSIBLE/05-ansible-fundamentals.md) |
| Q6 | `default_tags` trong khối provider (`Project`, `Env`, `Owner`, `ManagedBy=terraform`); Tag Editor không có tài nguyên `Project=taskhub` nào thiếu tag | Tìm, tính tiền, dọn được — như Q10 của v2 | Bài 02 |
| Q7 | **Không account ID cứng** trong code: dùng `data "aws_caller_identity"`, `data "aws_region"`; tên bucket ghép từ account ID | Code chạy được ở tài khoản khác (của người phỏng vấn, của công ty) không cần sửa | Bài 02 |
| Q8 | Module **không có khối `provider`**, có `variables.tf`/`outputs.tf` có `description` và kiểu; mọi biến có `type`; biến bí mật có `sensitive = true` | Module không cấu hình provider thì gọi được với provider/region khác | [Bài 04](../../07-TERRAFORM-ANSIBLE/04-terraform-modules-environments.md) |
| Q9 | Giữ nguyên các ràng buộc bảo mật của v2–v3: SG chỉ TCP 80, IMDSv2 `required` + hop limit 1, EBS mã hóa, trust policy `sub` chính xác `repo:<user>/taskhub:environment:production`, role deploy giới hạn theo document + tag | Tự động hóa không được làm yếu bảo mật; `trivy config` phải xanh | [v3 Q2–Q3](v3-cd.md#6-yêu-cầu-chất-lượng) |
| Q10 | AMI lấy bằng `data "aws_ssm_parameter"` từ tham số Canonical; `lifecycle { ignore_changes = [ami] }` **hoặc** chấp nhận thay máy khi AMI mới — chọn và giải thích trong ADR | Không có xử lý này, mỗi lần Canonical ra AMI mới `plan` sẽ đòi **thay** EC2 → vi phạm Q5 vào một ngày bất kỳ | Bài 02 |
| Q11 | Ansible: không dùng `shell`/`command` khi có module tương ứng; mỗi task `shell`/`command` còn lại có `changed_when`/`creates`; không secret trong `group_vars` (mật khẩu vẫn do `deploy.sh` lấy từ Parameter Store) | Đây chính là điều kiện để đạt `changed=0` ở Q5 | Bài 05 |
| Q12 | Không còn port 22: Ansible chạy qua `amazon.aws.aws_ssm`; SG không có rule 22 | ADR-0009 | [Lab 03](../../07-TERRAFORM-ANSIBLE/labs/lab-03-ansible-ssm.md) |
| Q13 | `infra.yml` đạt mục 5.1; `terraform fmt -check -recursive` sạch; tflint và `trivy config` không lỗi chưa giải thích | Lỗi hạ tầng bắt ở PR rẻ hơn bắt ở `apply` | [CI/CD bài 02](../../05-CICD/02-github-actions-basics.md) |
| Q14 | `.gitignore` chặn `*.tfstate*`, `.terraform/`, `*.tfvars` (giữ `*.tfvars.example`); `git log --all -p \| grep -c '"serial"'` ra 0 (chưa từng commit state) | State bị commit = lộ toàn bộ hạ tầng vào lịch sử Git vĩnh viễn | Bài 03 |

**Kiểm tra nhanh** `[WSL]` trong repo:

```bash
git ls-files | grep -E '\.tfstate|\.terraform/' ; echo "↑ phải rỗng"
git ls-files | grep -c 'terraform.lock.hcl'                         # ≥ 2 (bootstrap, envs/dev)
grep -rn 'provider "aws"' infra/terraform/modules ; echo "↑ phải rỗng"
grep -rnE '[0-9]{12}' infra/terraform --include='*.tf' ; echo "↑ phải rỗng (không account ID cứng)"
grep -rn 'dynamodb_table' infra/terraform ; echo "↑ phải rỗng"
terraform -chdir=infra/terraform/envs/dev plan -detailed-exitcode >/dev/null; echo "exit=$? (0 = No changes)"
```

---

## 7. Thử nghiệm bắt buộc

Ghi **thao tác → quan sát (lệnh + output rút gọn) → giải thích** vào `docs/experiments/v4-tests.md`.

| # | Thử nghiệm | Cách làm | Kết quả mong đợi — bạn phải giải thích được |
|---|---|---|---|
| T1 | **Dựng lại từ con số 0, bấm giờ** | Từ trạng thái đã `destroy`: bấm giờ → `terraform apply` → `ansible-playbook playbooks/site.yml` → cập nhật biến GitHub (T9) → `curl $APP_URL/actuator/health` | `{"status":"UP"}`. Ghi thời gian từng chặng (apply, chờ SSM Agent online, Ansible, pull image). Mục tiêu **< 30 phút**. Chặng nào lâu nhất, vì sao? Ghi vào `rebuild-from-scratch.md` |
| T2 | **Idempotency** | Ngay sau T1: `terraform plan -detailed-exitcode`; chạy lại playbook | Exit `0` / *No changes*; Ansible `changed=0`. Nếu không: tìm resource/task gây "thay đổi ma" và sửa (Q10, Q11) |
| T3 | **Drift bằng tay** | `[AWS Console]` thêm rule TCP 22 từ IP của bạn vào `taskhub-web-sg`, và sửa tag `Owner` của EC2 → `terraform plan -refresh-only` → `terraform plan` → `terraform apply` | `-refresh-only` chỉ **báo** thực tế đã lệch khỏi state; `plan` thường đề xuất **đưa về đúng code** (xóa rule 22, sửa tag). Khác nhau giữa "cập nhật state cho khớp thực tế" và "cập nhật thực tế cho khớp code" là gì? Ai/cái gì phát hiện drift nếu bạn không chạy plan? ([bài 03](../../07-TERRAFORM-ANSIBLE/03-terraform-state-backend.md), [Break-fix #1](../../07-TERRAFORM-ANSIBLE/labs/break-fix-01/README.md)) |
| T4 | **Khóa state** | Hai terminal cùng ở `envs/dev`: terminal A `terraform apply` (dừng ở câu hỏi *yes*); terminal B `terraform plan` | B lỗi *Error acquiring the state lock* (minh họa), có Lock ID, người giữ, thời điểm. Trong lúc A chờ: `aws s3 ls s3://taskhub-tfstate-<account-id>/envs/dev/` thấy file `.tflock`. Trả lời *no* ở A → file biến mất. Khi nào mới được dùng `terraform force-unlock`, và vì sao không bao giờ dùng khi chưa chắc không ai đang chạy? |
| T5 | **Import bucket backup** | Ở `bootstrap`: khối `import { to = aws_s3_bucket.backups  id = "taskhub-backups-<account-id>" }` (+ các tài nguyên con: versioning, lifecycle, public access block, policy) → `terraform plan` | Plan ghi *will be imported*, **không** *will be created*. Lần đầu plan có thể đòi **sửa** thuộc tính (vì code chưa khớp cấu hình tay) — chỉnh code cho tới khi plan chỉ còn import, không đổi gì. Vì sao không được để `apply` "sửa" lifecycle của một bucket đang chứa dữ liệu khi chưa hiểu diff? |
| T6 | **Đổi `instance_type`: sửa tại chỗ hay thay máy?** | Đổi `t3.small` → `t3.micro` → `terraform plan` (**chưa apply**); rồi thử đổi `user_data` (thêm một dòng comment) → `plan` | `instance_type`: `~ update in-place` — theo tài liệu provider AWS, đổi trường này làm EC2 **stop rồi start** (IP public đổi, có downtime, dữ liệu trên EBS còn). `user_data`: mặc định cũng stop/start, nhưng nếu đặt `user_data_replace_on_change = true` thì `-/+ replace` (máy mới, **mất** dữ liệu). Đọc ký hiệu `~`, `-/+`, `+/-` trong plan. Hoàn tác thay đổi |
| T7 | **Ansible check mode** | Sửa một dòng trong `docker/nginx/default.conf` (vd thêm header) → `ansible-playbook site.yml --check --diff` → rồi chạy thật | `--check` in diff, **không** đổi gì trên máy (kiểm chứng bằng `curl -I`); chạy thật → `changed` đúng các task liên quan + handler **restart** container nginx (không phải reload: `copy` thay file bằng inode mới, bind mount một file trong container vẫn giữ inode cũ — xem thí nghiệm G3 của [Lab 03](../../07-TERRAFORM-ANSIBLE/labs/lab-03-ansible-ssm.md)). So với v3: thay đổi compose/nginx giờ đi qua Git + Ansible, không qua Session Manager |
| T8 | **Mật khẩu không có trong state** | `terraform state pull > /tmp/s.json; grep -o 'value_wo[^,]*' /tmp/s.json; grep -c '<một phần mật khẩu thật>' /tmp/s.json; rm /tmp/s.json` (mật khẩu thật đọc bằng `aws ssm get-parameter --with-decryption` — đừng in ra màn hình chia sẻ) | `value_wo` là `null`, số lần xuất hiện mật khẩu = 0. So với `value` thường: state sẽ chứa nguyên văn. Vì sao `sensitive = true` không đủ? |
| T9 | **CD end-to-end với hạ tầng mới** | Cập nhật biến environment `production`: `AWS_DEPLOY_ROLE_ARN` = `terraform output -raw deploy_role_arn`, `APP_URL` = `terraform output -raw app_url` → **Enable** workflow `Deploy` → merge một PR nhỏ → Approve → rồi rollback bằng `workflow_dispatch` về `v0.5.0` | Deploy xanh với role do Terraform tạo (trust policy sinh từ code khớp đúng `sub`). Rollback < 5 phút như [v3 T5](v3-cd.md#7-thử-nghiệm-bắt-buộc). Biến nào phải cập nhật mỗi lần rebuild, và làm sao bớt bước tay này (🟦 `gh variable set --env production`)? |
| T10 | **`destroy` sạch và lớp bền còn nguyên** | `terraform destroy` ở `envs/dev` → `find-leftovers.sh` → `aws s3 ls` | Chỉ còn 3 bucket (`tfstate`, `backups`, và `ansible-ssm` **không còn** nếu bạn để nó trong `envs/dev` với `force_destroy`). Không còn EC2/EBS/IPv4/log group. Nếu destroy kẹt (vd *DependencyViolation*), đọc tài nguyên nào giữ tài nguyên nào |

---

## 8. Xử lý sự cố thường gặp

Thông báo dưới đây là minh họa — tìm **ý chính** in đậm. Bảng lỗi chi tiết ở các lab của [Module 07](../../07-TERRAFORM-ANSIBLE/README.md).

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra | Cách sửa |
|---|---|---|---|
| `terraform init`: **Failed to get existing workspaces / AccessDenied** từ S3 | `aws login` hết phiên; sai `AWS_PROFILE`; bucket/region trong `backend.tf` sai | `aws sts get-caller-identity`; `aws s3 ls s3://taskhub-tfstate-<account-id>` | Đăng nhập lại; sửa backend → `terraform init -reconfigure` |
| `init` đòi **migrate state** bất ngờ | Đổi cấu hình backend (bucket/key) | Đọc kỹ câu hỏi — đang chuyển state từ đâu sang đâu? | Chỉ trả lời *yes* khi chắc chắn; sai key = tạo state rỗng mới → `apply` đòi tạo lại mọi thứ |
| **Error acquiring the state lock** | Một lệnh khác đang chạy; hoặc lệnh trước bị kill (Ctrl+C hai lần, mất mạng) để lại `.tflock` | Lock Info: Who, Created; có terminal/CI nào đang chạy? | Chờ. Chỉ khi **chắc** không ai chạy: `terraform force-unlock <LOCK_ID>` (T4) |
| `apply`: **EntityAlreadyExists** / *BucketAlreadyOwnedByYou* / *already exists* | Tài nguyên tay từ v2–v3 chưa xóa | `find-leftovers.sh`; Tag Editor `ManagedBy=manual` | Xóa tay (v3 §11) **hoặc** import (T5) — không tạo tên khác để "né" |
| `destroy`: **Instance cannot be destroyed** … `prevent_destroy` | Bucket có `prevent_destroy` nằm trong `envs/dev` | Bucket thuộc root nào? | Chuyển sang lớp bền (mục 2), **không** xóa `prevent_destroy` cho tiện |
| `plan` luôn đòi **thay EC2** dù không sửa gì | AMI từ tham số SSM đã ra bản mới | Dòng `ami` trong plan có `# forces replacement` | Q10 |
| `plan` sau apply vẫn **~ update** tag/rule | Tag trùng giữa `default_tags` và `tags` của resource; rule SG khai báo hai kiểu (inline + resource riêng) | Thuộc tính nào lặp lại trong plan | Chọn một kiểu khai báo, sửa cho Q5 |
| `apply` tạo tham số mật khẩu lỗi **value_wo … requires Terraform 1.11** | Terraform cũ trên máy hoặc CI | `terraform version` | Cập nhật Terraform; `required_version` sẽ báo sớm hơn nếu đặt đúng |
| Ansible: **UNREACHABLE** … `session-manager-plugin` not found | Chưa cài plugin trên WSL | `session-manager-plugin --version` | Cài theo tài liệu AWS ([Lab 03](../../07-TERRAFORM-ANSIBLE/labs/lab-03-ansible-ssm.md)) |
| Ansible: lỗi **S3 / bucket** khi copy file | Thiếu cấu hình bucket của `aws_ssm` hoặc bucket ở region khác; bucket bị destroy | `inventory/group_vars/all.yml` (đặt sai chỗ → Ansible bỏ qua biến và quay về SSH); `terraform output ansible_ssm_bucket` | Trỏ đúng bucket/region |
| Ansible: inventory **rỗng** | `aws_ec2` lọc sai tag/region; instance chưa `running`; thiếu `boto3` trong môi trường pipx | `ansible-inventory -i inventory/aws_ec2.yml --graph` | Sửa filter; `pipx inject ansible boto3 botocore` |
| Ansible: task treo rất lâu ngay sau `apply` | SSM Agent chưa online | `aws ssm describe-instance-information` | Chờ (vài phút sau khi máy boot) — ghi thời gian vào T1 |
| `infra.yml` đỏ ở `validate`: **Module not installed** | Quên `terraform init -backend=false` trước `validate` | Log bước | Thêm bước init |
| Deploy (T9) đỏ: **Not authorized to perform sts:AssumeRoleWithWebIdentity** | `AWS_DEPLOY_ROLE_ARN` còn ARN cũ; `sub` trong trust policy sinh sai (biến `github_repo`) | `terraform output deploy_role_arn`; `aws iam get-role ... AssumeRolePolicyDocument` | Cập nhật biến GitHub; sửa biến Terraform |

Ghi mọi lỗi vào `troubleshooting-journal.md` theo [mẫu](../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 9. Câu hỏi tự kiểm

1. State của Terraform chứa gì, và nếu mất file state (không có versioning) thì chuyện gì xảy ra với lần `apply` kế tiếp?
2. `use_lockfile` khóa bằng cách nào? Vì sao tài liệu S3 backend yêu cầu thêm `s3:DeleteObject` cho file `.tflock` nhưng không cho file state?
3. Vì sao bucket state không thể được tạo bởi chính cấu hình dùng nó làm backend? Bạn giải bài toán đó thế nào?
4. `sensitive = true`, `ephemeral`, `value_wo` — mỗi cái bảo vệ giá trị khỏi **chỗ nào** (màn hình, plan, state)?
5. Khác nhau giữa `terraform plan -refresh-only`, `terraform plan` và `terraform apply -refresh-only`.
6. Ranh giới Terraform ↔ Ansible ↔ `deploy.sh` trong dự án: mỗi công cụ chịu trách nhiệm phần nào, và vì sao không để Terraform cài Docker bằng user data cho xong?
7. Ansible qua SSM: file đi từ laptop tới EC2 bằng đường nào? Bucket trung gian cần quyền gì, và vì sao nó tự xóa file sau 1 ngày?
8. Một đồng nghiệp sửa SG bằng Console lúc 2 giờ sáng để "chữa cháy". Sáng hôm sau bạn chạy `apply` cho một thay đổi khác. Chuyện gì xảy ra với sửa đổi của họ? Quy trình nào ngăn tình huống này?
9. Vì sao `infra.yml` không được đặt làm required check, trong khi `build-test` của CI thì có?

---

## 10. Definition of Done và release v0.6.0

- [ ] `bootstrap` đã chạy: bucket state đạt Q2, bucket backup đã **import** (T5) hoặc tạo mới; state của `bootstrap` đã migrate lên S3.
- [ ] `envs/dev` dựng toàn bộ tài nguyên ở mục 2 bằng một `terraform apply`; không còn tài nguyên `ManagedBy=manual` của dự án (Tag Editor).
- [ ] Ansible cài Docker + triển khai app qua SSM; chạy lần 2 `changed=0`.
- [ ] Đạt Q1–Q14; các lệnh kiểm tra nhanh ở mục 6 ra đúng kết quả.
- [ ] `infra.yml` đã chạy xanh trên một PR chạm `infra/**`; mọi action ghim SHA.
- [ ] Hoàn thành T1–T10, ghi trong `docs/experiments/v4-tests.md`; T1 có số phút thật (< 30).
- [ ] Workflow `Deploy` đã bật lại và một lần deploy + một lần rollback thành công với role do Terraform tạo (T9).
- [ ] `docs/runbooks/rebuild-from-scratch.md`: một người có laptop sạch (đã cài công cụ) làm theo được; `docs/architecture.md` có sơ đồ v4; ADR-0008, ADR-0009 đã merge; `docs/cost.md` có so sánh stop vs destroy.
- [ ] README có mục **"Infrastructure"**: công cụ + phiên bản, `make up` / `make down` (hoặc các lệnh tương đương), outputs, cảnh báo chi phí và dữ liệu sẽ mất khi destroy.
- [ ] Code vào `main` qua PR (ví dụ `feat/terraform-ansible`), CI + `infra.yml` xanh.
- [ ] **Release `v0.6.0`**: sau khi CI trên `main` xanh, `git tag -a v0.6.0 -m "v4: hạ tầng bằng Terraform, cài đặt bằng Ansible"` → `git push origin v0.6.0` (workflow `Release` gắn `:v0.6.0`) → triển khai `v0.6.0` (Deploy `workflow_dispatch`, hoặc `ansible-playbook site.yml -e taskhub_image_tag=v0.6.0`) → `curl $APP_URL/actuator/health` = `UP`.
- [ ] Cuối buổi: `terraform destroy` ở `envs/dev` (T10).
- [ ] Kiểm tra bản thân: [Checkpoint Module 07](../../07-TERRAFORM-ANSIBLE/checkpoint.md) (tuần 16).

➡️ Tiếp theo: [**v5 — Observability + backup**](v5-observability-backup.md) (tuần 17–18): Prometheus, Grafana, Loki + Alloy, alert; backup `pg_dump` lên chính bucket `taskhub-backups-<account-id>` mà v4 vừa đưa vào Terraform, và diễn tập restore.

---

## 11. Dọn dẹp

| Khi nào | Làm gì | Kiểm tra |
|---|---|---|
| **Cuối mỗi buổi** (tuần 15–16 trở đi) | ⚠️ `terraform -chdir=infra/terraform/envs/dev destroy` — đọc danh sách trước khi gõ `yes`: **không** được có bucket state/backup | `~/devops-lab/06-aws/find-leftovers.sh` → chỉ còn các bucket của lớp bền |
| Đầu buổi sau | `make up` (hoặc apply + playbook) → cập nhật `APP_URL`/`AWS_DEPLOY_ROLE_ARN` nếu đổi | `curl $APP_URL/actuator/health` |
| Giữa chừng, không muốn destroy | Stop EC2 — **nhưng** biết rằng lần `plan` sau vẫn *No changes* (trạng thái running/stopped không do code quản lý, trừ khi bạn khai báo) | `plan -detailed-exitcode` |
| Dừng hẳn dự án | Destroy `envs/dev`; với lớp bền: làm rỗng bucket (mọi **phiên bản**), tạm bỏ `prevent_destroy` trong một commit có lý do, rồi destroy `bootstrap` — xem [AWS bài 05](../../06-AWS/05-s3.md) cho lệnh xóa mọi phiên bản | `aws s3 ls`; Billing |

Không xóa bucket backup trước v5 — v5 dùng nó.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Terraform — S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) | `use_lockfile`, DynamoDB lock deprecated, quyền `s3:DeleteObject` cho `.tflock`, khuyến nghị versioning | 2026-10-31 |
| [Terraform — Write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/write-only) | `value_wo`, `*_wo_version`, không lưu vào state | 2026-10-31 |
| [AWS provider — `aws_ssm_parameter`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | `value_wo` + `value_wo_version`, cần Terraform ≥ 1.11 | 2026-10-31 |
| [AWS provider — `aws_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | Đổi `instance_type`/`user_data` → stop/start; `user_data_replace_on_change` → thay máy | 2026-10-31 |
| [Terraform — Import](https://developer.hashicorp.com/terraform/language/import) | Khối `import {}` | 2026-10-31 |
| [Terraform — Refresh-only mode (tutorial)](https://developer.hashicorp.com/terraform/tutorials/state/refresh) | Phát hiện drift | 2026-10-31 |
| [Terraform — `plan` command](https://developer.hashicorp.com/terraform/cli/commands/plan) | `-refresh-only`, `-detailed-exitcode` | 2026-10-31 |
| [Terraform — `lifecycle` meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle) | `prevent_destroy`, `ignore_changes` | 2026-10-31 |
| [Terraform — `force-unlock`](https://developer.hashicorp.com/terraform/cli/commands/force-unlock) | Gỡ khóa state | 2026-10-31 |
| [hashicorp/terraform releases](https://github.com/hashicorp/terraform/releases) | Terraform 1.17.1 (2026-10-28) | 2026-10-31 |
| [Ansible — `amazon.aws.aws_ssm` connection](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ssm_connection.html) | Bucket S3 trung gian, `session-manager-plugin` | 2026-10-31 |
| [AWS — Install the Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) | Cài plugin trên WSL | 2026-10-31 |
| [Trivy — Misconfiguration scanning](https://trivy.dev/latest/docs/scanner/misconfiguration/) | `trivy config` quét Terraform | 2026-10-31 |
| [terraform-linters/setup-tflint](https://github.com/terraform-linters/setup-tflint) | Action tflint (v6.3.2) | 2026-10-31 |
| [hashicorp/setup-terraform](https://github.com/hashicorp/setup-terraform) | Action cài Terraform (v4.0.1) | 2026-10-31 |
