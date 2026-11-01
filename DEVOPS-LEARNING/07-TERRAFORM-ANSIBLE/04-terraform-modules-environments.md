# 04. Terraform module, môi trường và chất lượng code

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [02. Terraform cơ bản](02-terraform-basics.md), [03. State và remote backend](03-terraform-state-backend.md) (`moved {}`), [AWS 03 — VPC](../06-AWS/03-vpc-networking.md)
> Môi trường: `[WSL]` Ubuntu 24.04 có Terraform ≥ 1.17, AWS CLI v2 (profile `taskhub`), Docker Desktop (đã bật WSL Integration — để chạy tflint/trivy bằng container)
> Phiên bản khi viết: Terraform 1.17.1, `hashicorp/aws` ~> 6.0, tflint v0.65.0 + ruleset AWS 0.50.0, Trivy 0.76.1

> 💰 **Chi phí của bài này:** lab dựng một VPC tập dượt gồm VPC, 4 subnet, Internet Gateway, route table — **các tài nguyên này không tính phí** (không EC2, không NAT, không public IPv4). → **0 USD**. Cuối lab **xóa hết** bằng `terraform destroy`. `terraform test` dùng provider **giả lập**, không tạo gì trên AWS.

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc log và xử lý lỗi](#12-đọc-log-và-xử-lý-lỗi)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Phân biệt **root module** và **child module**; viết một module có **input** (variable), **output**, kiểm tra đầu vào bằng `validation`.
- Gọi module từ **đường dẫn local**, **Terraform Registry** (có `version`) và **Git** (ghim `?ref=`); giải thích vì sao phải ghim phiên bản.
- Áp dụng các nguyên tắc thiết kế module: nhỏ, một trách nhiệm, **không có block `provider`** bên trong module con.
- Tách code phẳng thành module **không phá hủy** tài nguyên nào nhờ `moved {}` — plan ra `0 to destroy`.
- Tổ chức nhiều môi trường bằng **thư mục riêng** (`envs/dev`, `envs/prod`) và giải thích vì sao không dùng CLI workspaces cho việc này.
- Dùng `tfvars`, `default_tags`, quy ước đặt tên; nắm thứ tự ưu tiên của biến.
- Kiểm tra chất lượng code bằng `terraform fmt`, `validate`, **tflint** (+ ruleset AWS), **`trivy config`**, và viết một **`terraform test`** với provider giả lập.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Kiến thức dùng tới |
|---|---|
| Copy-paste 300 dòng VPC cho dev, staging, prod → sửa một chỗ quên hai chỗ | **Module** dùng lại, mỗi môi trường chỉ khác **input** |
| "Dev chạy được, prod lỗi" vì hai môi trường lệch cấu hình theo thời gian | Cùng một module, khác `tfvars` — sự khác biệt hiện rõ trong code |
| Một lần `terraform destroy` nhầm thư mục xóa luôn production | Mỗi môi trường **một thư mục, một state key, (thường) một tài khoản** |
| Refactor code cho gọn mà plan đòi xóa VPC đang chạy | `moved {}` khi chuyển resource vào module |
| Reviewer phải đọc 50 dòng diff chỉ vì sai thụt lề | `terraform fmt -check` trong CI |
| `instance_type = "t3.smal"` — plan vẫn qua, apply mới lỗi | **tflint** + ruleset AWS bắt lỗi trước |
| Bucket vô tình public, SG mở `0.0.0.0/0` cổng 22 | **`trivy config`** quét cấu hình sai (misconfiguration) |
| Module dùng chung bị sửa làm hỏng logic subnet mà không ai biết | **`terraform test`** chạy trên mỗi PR |

Ở dự án v4, toàn bộ hạ tầng `taskhub` được tổ chức thành `modules/network`, `modules/app_server` và `envs/dev` — bài này dạy đúng cấu trúc đó.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Mọi thư mục Terraform đều là một module

- **Module** = một thư mục chứa file `.tf`. Không cần khai báo gì đặc biệt.
- **Root module** = thư mục bạn đứng khi chạy `terraform plan/apply`. Nó có state, có backend, có block `provider`.
- **Child module** = module được root (hoặc module khác) gọi bằng block `module`. Không có state riêng — tài nguyên của nó nằm trong state của root, với địa chỉ có tiền tố `module.<tên>.`.

```text
envs/dev/                  ← root module (state: envs/dev/terraform.tfstate)
└── module "network"  ───►  modules/network/   ← child module
                              aws_vpc.this  →  địa chỉ trong state: module.network.aws_vpc.this
```

### 3.2. Module giống hàm trong Java

| Java | Terraform module |
|---|---|
| Tham số của hàm | `variable` |
| Giá trị trả về | `output` |
| Biến cục bộ | `locals` |
| Thân hàm | Các `resource`, `data` |
| Gọi hàm | Block `module "x" { source = ..., <tham số> = ... }` |
| Kiểm tra tham số đầu vào (`Objects.requireNonNull`) | Block `validation` trong `variable` |

Như hàm tốt: một module tốt **làm một việc**, nhận ít tham số có ý nghĩa, trả về đúng thứ người gọi cần.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cấu trúc file chuẩn của một module

```text
modules/network/
├── versions.tf      # required_version + required_providers (KHÔNG có block provider)
├── variables.tf     # input
├── main.tf          # resource
├── outputs.tf       # output
├── README.md        # mô tả input/output, ví dụ gọi
└── tests/
    └── network.tftest.hcl
```

Tên file chỉ là quy ước — Terraform đọc mọi file `.tf` trong thư mục như một khối. Nhưng quy ước giúp người khác tìm đúng chỗ ngay.

### 4.2. 🟥 Gọi module và đọc output

```hcl
module "network" {
  source = "../../modules/network"

  name     = "taskhub"
  vpc_cidr = "10.20.0.0/16"
  # ...
}

output "vpc_id" {
  value = module.network.vpc_id
}
```

- `source` bắt buộc. Thay đổi `source` → phải chạy lại `terraform init` (tài liệu ghi rõ: *You must run `terraform init` after modifying the `source` argument*).
- Mọi argument khác trong block là **input** của module (trừ meta-argument `count`, `for_each`, `depends_on`, `providers`, `version`).
- Output của module con đọc bằng `module.<tên>.<output>`. Root module muốn in ra màn hình thì phải khai báo `output` riêng.

### 4.3. 🟥 Ba loại `source` và chuyện ghim phiên bản

| Loại | Ví dụ | Ghim phiên bản bằng |
|---|---|---|
| **Local** | `source = "../../modules/network"` | Không cần — cùng repo, cùng commit |
| **Registry** | `source = "terraform-aws-modules/vpc/aws"` | `version = "~> 6.7"` (chỉ dùng được với registry) |
| **Git** | `source = "git::https://github.com/org/infra-modules.git//modules/vpc?ref=v1.2.0"` | `?ref=` = tag (hoặc SHA commit để tuyệt đối bất biến) |

- `//modules/vpc` trong Git source = thư mục con trong repo.
- Không ghim = mỗi lần `init` có thể kéo về code khác → plan hôm nay khác hôm qua dù bạn không sửa gì. Cùng lý do bạn ghim SHA cho action ở [CI/CD 04](../05-CICD/04-secrets-environments.md).
- `~> 6.7` = "≥ 6.7 và < 7.0" — nhận bản vá/tính năng mới, chặn bản **major** (có thể phá vỡ tương thích).

### 4.4. 🟥 Nguyên tắc thiết kế module

1. **Một trách nhiệm.** `network` lo VPC/subnet/route; `app_server` lo SG/IAM/EC2. Không làm module "taskhub-tất-cả".
2. **Không có block `provider` trong module con.** Tài liệu HashiCorp: *A module intended to be called by one or more other modules must not contain any `provider` blocks.* Module con chỉ khai `required_providers`; cấu hình provider (region, `default_tags`, credentials) đến từ root. Module chứa `provider` riêng (gọi là *legacy module*) **không dùng được** với `count`, `for_each`, `depends_on`.
3. **Input có kiểu và có kiểm tra.** Dùng `type = map(object({...}))` thay vì `any`; thêm `validation` để lỗi được báo **lúc plan** với thông điệp dễ hiểu.
4. **Output vừa đủ.** Xuất ID/ARN mà module khác cần; không xuất mọi thứ "cho chắc".
5. **Không bọc một resource duy nhất** chỉ để đổi tên tham số — module như vậy thêm một lớp phải đọc mà không thêm giá trị.
6. **Đừng hardcode** tên môi trường, region, số tài khoản trong module — nhận qua input hoặc data source.

### 4.5. 🟨 Module công khai trên Registry: dùng hay tự viết?

Module `terraform-aws-modules/vpc/aws` (bản mới nhất khi viết: v6.7.3) được dùng rất rộng rãi.

| Dùng module công khai | Tự viết |
|---|---|
| Nhanh, nhiều tính năng (NAT, IPv6, flow logs, endpoint…) | Hiểu từng resource — **mục tiêu chính khi đang học** |
| Hàng trăm biến, phải đọc kỹ mặc định (ví dụ có bật NAT Gateway không — tiền theo giờ) | Ít dòng, chỉ đúng thứ dự án cần |
| Cập nhật major có thể đổi hành vi | Bạn chịu trách nhiệm bảo trì |

Lựa chọn của giáo trình: **tự viết** `modules/network` (khoảng 80 dòng) để bạn giải thích được mọi dòng khi phỏng vấn. Sau đó, đọc mã nguồn module công khai để so sánh (bài tập 4). Khi đi làm, nhiều team dùng module công khai — kỹ năng cần có là **đọc hiểu và ghim phiên bản** nó.

### 4.6. 🟥 Refactor vào module mà không phá hủy

Khi chuyển `aws_vpc.main` (code phẳng) thành `aws_vpc.this` bên trong `module.network`, địa chỉ đổi từ `aws_vpc.main` sang `module.network.aws_vpc.this`. Không có gì báo cho Terraform biết hai địa chỉ là một → plan **xóa VPC cũ, tạo VPC mới**.

```hcl
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_subnet.public_a
  to   = module.network.aws_subnet.public["a"]
}
```

- Khóa `for_each` nằm trong ngoặc vuông, kèm nháy kép: `["a"]`.
- Viết **một `moved` cho mỗi resource**, kể cả route, association. Thiếu một cái → plan có đúng một cặp destroy/create → bạn biết ngay còn thiếu cái nào.
- **Quy tắc vàng:** refactor đúng là refactor mà plan ra `0 to add, 0 to change, 0 to destroy`. Có bất kỳ con số nào khác 0 → dừng lại, tìm nguyên nhân.

### 4.7. 🟥 Nhiều môi trường: thư mục riêng hay workspaces?

**Cách 1 — Mỗi môi trường một thư mục (dự án chọn):**

```text
infra/terraform/
├── modules/network/          ← code dùng chung
├── modules/app_server/
└── envs/
    ├── dev/                  ← backend key envs/dev/terraform.tfstate, terraform.tfvars của dev
    └── prod/                 ← backend key envs/prod/... (thường ở TÀI KHOẢN AWS KHÁC)
```

**Cách 2 — CLI workspaces** (`terraform workspace new prod`): cùng một thư mục, mỗi workspace một state.

Tài liệu HashiCorp về CLI workspaces giải thích vì sao cách 2 không hợp để tách môi trường thật: backend của mỗi môi trường *often has different credentials and access controls*, mà *CLI workspaces within a working directory use the same backend, so they are not a suitable isolation mechanism for this scenario*.

| Tiêu chí | Thư mục riêng | CLI workspaces |
|---|---|---|
| Nhìn code biết đang ở môi trường nào | Có — `cd envs/prod` | Phải gõ `terraform workspace show` |
| Backend / tài khoản / quyền riêng | Có | Không — chung backend |
| Prod khác dev về cấu trúc (thêm ALB, Multi-AZ) | Dễ — root module prod gọi thêm module | Phải rải `count = terraform.workspace == "prod" ? 1 : 0` khắp nơi |
| Rủi ro nhầm | Thấp | Quên `workspace select` → apply nhầm môi trường |
| Lặp code | Một ít (file gọi module ở mỗi env) | Ít |

Workspaces vẫn có chỗ dùng: tạo bản sao **tạm thời** cùng cấu hình (ví dụ môi trường thử cho một nhánh). `taskhub` chỉ có `envs/dev` thật; `envs/prod` chỉ tồn tại dưới dạng khung trong lab để bạn thấy cấu trúc — **không** apply (gấp đôi chi phí).

### 4.8. 🟥 `tfvars` và thứ tự ưu tiên của biến

```hcl
# envs/dev/terraform.tfvars  (tự động được nạp)
owner         = "phuong"
instance_type = "t3.small"
alert_email   = "you@example.com"
```

Thứ tự ưu tiên (cao → thấp) theo tài liệu Terraform:

1. `-var` và `-var-file` trên dòng lệnh (theo thứ tự xuất hiện)
2. `*.auto.tfvars` / `*.auto.tfvars.json` (theo thứ tự tên file)
3. `terraform.tfvars.json`
4. `terraform.tfvars`
5. Biến môi trường `TF_VAR_<tên>`
6. Giá trị `default` trong block `variable`

Lưu ý thực tế:

- `terraform.tfvars` chứa giá trị **không bí mật** của môi trường → commit được. Thứ bí mật → không để trong tfvars; dùng ephemeral/write-only ([bài 03](03-terraform-state-backend.md)) hoặc `TF_VAR_...` lúc chạy (và nhớ: biến thường kể cả `sensitive` vẫn vào state; thêm `ephemeral = true` mới không vào).
- `TF_VAR_` đứng **dưới** `terraform.tfvars`: đặt `TF_VAR_instance_type` mà tfvars cũng có `instance_type` thì tfvars thắng — lỗi "tôi đã export biến rồi mà không ăn" kinh điển.

### 4.9. 🟥 `default_tags` và đặt tên

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

- Mọi resource hỗ trợ tag tự nhận 4 tag này — không phải lặp lại ở từng resource, không bao giờ quên tag `Project` (thứ mà `find-leftovers.sh` và Cost Explorer dựa vào).
- Tag riêng của từng resource (thường là `Name`) vẫn khai báo trong resource; hai bộ tag được gộp (thuộc tính `tags_all`).
- Quy ước tên dự án (như Module 06): `taskhub-vpc`, `taskhub-public-a`… Module nhận `name` làm tiền tố để dùng lại được cho dự án khác.

### 4.10. 🟥 Bộ công cụ kiểm tra chất lượng

| Công cụ | Bắt được gì | Cần AWS? |
|---|---|---|
| `terraform fmt -check -recursive` | Sai định dạng (thụt lề, căn `=`) | Không |
| `terraform validate` (sau `init -backend=false`) | Cú pháp, tham chiếu sai, thiếu argument bắt buộc, sai kiểu | Không |
| **tflint** + ruleset AWS | Lỗi **riêng của provider** mà `validate` không biết: `instance_type` không tồn tại, quy ước đặt tên, biến khai mà không dùng… | Không (chế độ mặc định) |
| **`trivy config`** | **Cấu hình sai về bảo mật**: bucket không mã hóa, SG mở `0.0.0.0/0`, VPC không bật flow logs, EC2 không bắt buộc IMDSv2… | Không |
| `terraform test` | **Logic** của module có đúng ý đồ không (số subnet, CIDR, route…) | Không, nếu dùng provider giả lập |
| `terraform plan` | Thay đổi thật sẽ xảy ra | Có |

**tflint.** README của ruleset AWS minh họa bằng `instance_type = "t1.2xlarge"`: `validate` và `plan` không bắt được vì đó là chuỗi hợp lệ về cú pháp — chỉ tới `apply` AWS mới từ chối. Cấu hình `.tflint.hcl`:

```hcl
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```

`tflint --init` tải plugin; `tflint --recursive` chạy cho mọi thư mục con.

**trivy config.** Cùng công cụ Trivy bạn dùng quét image ở [Docker 07](../04-DOCKER/07-docker-security.md), nhưng chế độ quét **IaC**: `trivy config <thư mục>`, lọc mức độ bằng `--severity HIGH,CRITICAL`. Mỗi phát hiện có mã kiểm tra và link giải thích. Không phải phát hiện nào cũng phải sửa: subnet public **cố ý** tự gán public IP là đúng thiết kế của `taskhub` — ghi lý do chấp nhận rủi ro, đừng tắt cảnh báo mà không giải thích.

**🟨 `terraform test`.** Có từ Terraform 1.6; file kết thúc bằng `.tftest.hcl`. Mặc định mỗi `run` dùng `command = apply` và **tạo hạ tầng thật** rồi hủy khi xong. Với `mock_provider` (Terraform ≥ 1.7), provider được giả lập: không gọi API, thuộc tính tính toán được sinh ngẫu nhiên (chuỗi 8 ký tự, số 0, bool false…). Nhờ vậy test logic module **không tốn tiền, không cần đăng nhập AWS**.

```hcl
mock_provider "aws" {}

run "subnets_are_created" {
  command = apply   # an toàn vì provider đã bị giả lập

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Phải có đúng 2 public subnet"
  }
}
```

`expect_failures = [var.vpc_cidr]` trong một `run` dùng để test rằng `validation` **từ chối** đầu vào sai.

**🟦 pre-commit.** Dự án `pre-commit-terraform` cung cấp hook `terraform_fmt`, `terraform_validate`, `terraform_tflint`, `terraform_trivy` chạy mỗi lần `git commit`. Hữu ích khi đi làm; giáo trình đưa kiểm tra vào CI thay vì hook trên máy.

### 4.11. 🟨 Terraform trong CI

Ở v4, workflow `infra.yml` chạy trên mỗi PR có thay đổi `infra/**`:

```text
fmt -check  →  init -backend=false + validate  →  tflint  →  trivy config  →  terraform test (mock)
```

Không cần credential AWS nào: mọi bước trên chạy được offline với provider. Chưa làm ở v4:

- 🟦 **`plan` trong CI** qua OIDC với role chỉ đọc + đọc state, đăng kết quả plan vào PR.
- 🟦 **`apply` tự động** khi merge. Rủi ro cao nếu chưa có review plan và môi trường bảo vệ — apply từ máy bạn, có đọc plan, là đủ cho dự án cá nhân.

---

## 5. Ví dụ thực tế

**Ví dụ 1 — Ba bản copy.** Một team có `dev/`, `staging/`, `prod/`, mỗi thư mục 400 dòng gần giống nhau. Ai đó sửa NACL ở dev và staging, quên prod. Sáu tháng sau, sự cố chỉ xảy ra ở prod và không ai hiểu vì sao "code giống nhau". Sau khi gom vào module, ba thư mục chỉ còn ~30 dòng gọi module + tfvars; mọi khác biệt nằm gọn trong tfvars và được review.

**Ví dụ 2 — Refactor suýt mất VPC.** Một kỹ sư tách code vào module, quên `moved` cho route table association. Plan: `4 to add, 4 to destroy`. Vì CI in plan vào PR và quy ước "refactor phải 0 destroy", reviewer chặn lại. Thêm 4 `moved` → `0 to destroy`.

**Ví dụ 3 — Module công khai và cái giá ẩn.** Một người mới dùng module VPC công khai với cấu hình ví dụ copy từ README, trong đó bật NAT Gateway cho từng AZ. Hóa đơn tháng đó có thêm khoản NAT Gateway cho mỗi AZ. Bài học: dùng module công khai thì phải **đọc từng biến** mình truyền vào và mặc định của những biến không truyền.

---

## 6. Sơ đồ kiến trúc

```text
infra/terraform/
│
├── modules/                         ← "thư viện" — không có provider, không có backend
│   ├── network/   (input: name, vpc_cidr, public_subnets, private_subnets)
│   │              (output: vpc_id, public_subnet_ids, private_subnet_ids)
│   └── app_server/ (v4)
│
└── envs/
    ├── dev/   ─── provider "aws" + default_tags (Env=dev)
    │          ─── backend s3 key=envs/dev/terraform.tfstate
    │          ─── module "network"    { source = "../../modules/network", ...dev values }
    │          ─── module "app_server" { vpc_id = module.network.vpc_id, ... }
    │          ─── terraform.tfvars (dev)
    │
    └── prod/  ─── (khung) cùng module, khác tfvars, khác backend key / tài khoản
```

```text
Kiểm tra chất lượng trên mỗi PR (không cần AWS):

 git push ──► fmt -check ──► validate ──► tflint (+aws) ──► trivy config ──► terraform test (mock)
                │ lỗi định dạng   │ lỗi cú pháp   │ lỗi provider    │ cấu hình bảo mật   │ logic module
                ▼                 ▼               ▼                 ▼                    ▼
                                     PR đỏ → sửa trước khi ai đó chạy plan/apply
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `terraform init` | Tải provider **và module** (bắt buộc chạy lại khi đổi `source`) | 🟥 |
| `terraform get -update` | Cập nhật module (không đụng backend) | 🟨 |
| `terraform fmt -recursive` / `-check` | Định dạng / kiểm tra định dạng | 🟥 |
| `terraform init -backend=false` + `terraform validate` | Kiểm tra cú pháp không cần state | 🟥 |
| `terraform plan -var-file=prod.tfvars` | Plan với file biến chỉ định | 🟥 |
| `terraform state list \| grep module.network` | Xem tài nguyên trong một module | 🟥 |
| `terraform test` | Chạy file `*.tftest.hcl` | 🟨 |
| `terraform workspace list/show` | Biết workspace đang dùng (để chắc chắn là `default`) | 🟨 |
| `docker run ... ghcr.io/terraform-linters/tflint:v0.65.0` | tflint bằng container | 🟥 |
| `docker run ... aquasec/trivy:0.76.1 config .` | Quét IaC bằng container | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. Plan sau khi refactor có `moved`

```text
  # aws_vpc.main has moved to module.network.aws_vpc.this
    resource "aws_vpc" "this" {
        id                   = "vpc-0a1b2c3d4e5f67890"
        tags                 = {
            "Name" = "tf07-vpc"
        }
        # (14 unchanged attributes hidden)
    }

  # aws_subnet.public_a has moved to module.network.aws_subnet.public["a"]
    ...

Plan: 0 to add, 0 to change, 0 to destroy.
```

(Minh họa.) Mỗi resource được di chuyển có một dòng `has moved to` và **không** có dấu `+`/`-`.

### 8.2. tflint bằng container

```bash
docker run --rm -v "$(pwd)":/data -t --entrypoint /bin/sh \
  ghcr.io/terraform-linters/tflint:v0.65.0 \
  -c "tflint --init && tflint --recursive"
```

| Phần | Ý nghĩa |
|---|---|
| `-v "$(pwd)":/data` | Image làm việc ở `/data`; mount thư mục hiện tại vào đó |
| `--entrypoint /bin/sh ... -c "..."` | Chạy hai lệnh trong một container: `--init` (tải plugin theo `.tflint.hcl`) rồi quét. Cách này lấy từ README của tflint |
| `:v0.65.0` | Ghim phiên bản (bản mới nhất khi viết, đã kiểm tra tồn tại trên ghcr.io) |
| `--recursive` | Quét mọi thư mục con có file `.tf` |

Đầu ra minh họa khi có lỗi:

```text
1 issue(s) found:

Error: "t3.smal" is an invalid value as instance_type (aws_instance_invalid_type)

  on main.tf line 12:
  12:   instance_type = "t3.smal"
```

### 8.3. Trivy quét IaC

```bash
docker run --rm -v "$(pwd)":/src:ro aquasec/trivy:0.76.1 \
  config --severity HIGH,CRITICAL /src
```

| Phần | Ý nghĩa |
|---|---|
| `:ro` | Mount chỉ đọc — Trivy không cần ghi gì vào code |
| `config` | Chế độ quét cấu hình IaC (Terraform, CloudFormation, Dockerfile, Kubernetes…) |
| `--severity HIGH,CRITICAL` | Chỉ hiện mức cao — bỏ cờ này để thấy hết |

Mỗi phát hiện có: mã kiểm tra, mức độ, mô tả, **file:dòng**, link giải thích cách sửa. Đầu ra cụ thể phụ thuộc phiên bản bộ kiểm tra — đọc và ghi lại thay vì học thuộc.

### 8.4. `terraform test`

```bash
cd modules/network
terraform init
terraform test
```

```text
tests/network.tftest.hcl... in progress
  run "public_and_private_subnets"... pass
  run "invalid_cidr_rejected"... pass
tests/network.tftest.hcl... tearing down
tests/network.tftest.hcl... pass

Success! 2 passed, 0 failed.
```

(Minh họa.) Chạy trong thư mục **module**, không phải `envs/dev` — test kiểm tra module độc lập.

---

## 9. Bài thực hành từng bước

> 💰 0 USD: VPC, subnet, Internet Gateway, route table không tính phí. **Không** thêm EC2/NAT/Elastic IP vào lab này. Xóa hết ở bước cuối.
> Lab làm trong thư mục tập dượt **ngoài** repo `taskhub` để không đụng v4: `~/devops-lab/07-terraform/refactor-lab/`. Dùng CIDR `10.30.0.0/16` (khác `10.20.0.0/16` của dự án) và tiền tố tên `tf07`.
> Đăng nhập: `export AWS_PROFILE=taskhub && aws login`; kiểm tra `aws sts get-caller-identity`.

### Bước 1 — Code phẳng (trước refactor) `[WSL]`

```bash
mkdir -p ~/devops-lab/07-terraform/refactor-lab/envs/dev
cd ~/devops-lab/07-terraform/refactor-lab/envs/dev
```

`providers.tf`:

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"

  default_tags {
    tags = {
      Project   = "taskhub"
      Env       = "lab"
      Owner     = "phuong"
      ManagedBy = "terraform"
      Lab       = "tf07-refactor"
    }
  }
}
```

`main.tf` — 13 resource viết phẳng, đúng như người mới thường viết:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "tf07-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "tf07-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = "ap-southeast-1a"
  cidr_block              = "10.30.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "tf07-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = "ap-southeast-1b"
  cidr_block              = "10.30.2.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "tf07-public-b" }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = "ap-southeast-1a"
  cidr_block              = "10.30.11.0/24"
  map_public_ip_on_launch = false
  tags                    = { Name = "tf07-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = "ap-southeast-1b"
  cidr_block              = "10.30.12.0/24"
  map_public_ip_on_launch = false
  tags                    = { Name = "tf07-private-b" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "tf07-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "tf07-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
```

```bash
terraform init
terraform plan -out=tfplan        # mong đợi: Plan: 13 to add — chỉ VPC/subnet/IGW/route
terraform apply tfplan            # ⚠️ tạo tài nguyên thật (0 USD)
terraform state list | wc -l      # 13
```

State lab này để **local** (đây là lab tập dượt); v4 mới dùng S3 backend.

❓ Đếm số chỗ lặp lại gần giống nhau trong `main.tf`. Nếu thêm AZ thứ ba, bạn phải sửa bao nhiêu chỗ?

### Bước 2 — Viết `modules/network`

```bash
mkdir -p ~/devops-lab/07-terraform/refactor-lab/modules/network/tests
cd ~/devops-lab/07-terraform/refactor-lab/modules/network
```

`versions.tf`:

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

`variables.tf`:

```hcl
variable "name" {
  type        = string
  description = "Tiền tố tên cho mọi resource, ví dụ taskhub"
}

variable "vpc_cidr" {
  type        = string
  description = "Dải CIDR của VPC, ví dụ 10.20.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr phải là một dải CIDR IPv4 hợp lệ, ví dụ 10.20.0.0/16."
  }
}

variable "public_subnets" {
  type = map(object({
    az   = string
    cidr = string
  }))
  description = "Khóa là hậu tố tên (a, b…), giá trị là AZ và CIDR của public subnet"
}

variable "private_subnets" {
  type = map(object({
    az   = string
    cidr = string
  }))
  description = "Như public_subnets, cho private subnet (không có route ra Internet)"
  default     = {}
}
```

`main.tf`:

```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name}-private-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
```

`outputs.tf`:

```hcl
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Map hậu tố → subnet ID"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.private : k => s.id }
}
```

❓ Vì sao `for_each` trên `aws_route_table_association.public` lặp qua `aws_subnet.public` (resource) thay vì `var.public_subnets` (biến)? (Gợi ý: khóa giống nhau, nhưng giá trị nào có sẵn `id`?)

❓ Vì sao dùng `map` có khóa `a`/`b` thay vì `list` với `count`? Điều gì xảy ra với `count` khi bạn xóa phần tử **đầu** danh sách?

### Bước 3 — Gọi module từ `envs/dev` và viết `moved`

Trong `envs/dev`, **thay toàn bộ** nội dung `main.tf` bằng:

```hcl
module "network" {
  source = "../../modules/network"

  name     = "tf07"
  vpc_cidr = "10.30.0.0/16"

  public_subnets = {
    a = { az = "ap-southeast-1a", cidr = "10.30.1.0/24" }
    b = { az = "ap-southeast-1b", cidr = "10.30.2.0/24" }
  }

  private_subnets = {
    a = { az = "ap-southeast-1a", cidr = "10.30.11.0/24" }
    b = { az = "ap-southeast-1b", cidr = "10.30.12.0/24" }
  }
}

output "vpc_id" {
  value = module.network.vpc_id
}
```

Chạy plan **trước** khi viết `moved` (đây là thí nghiệm, không apply):

```bash
terraform init          # bắt buộc: vừa thêm module mới
terraform plan          # ❓ ghi lại dòng Plan:
```

Tạo `moved.tf`:

```hcl
moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.this
}

moved {
  from = aws_subnet.public_a
  to   = module.network.aws_subnet.public["a"]
}

moved {
  from = aws_subnet.public_b
  to   = module.network.aws_subnet.public["b"]
}

moved {
  from = aws_subnet.private_a
  to   = module.network.aws_subnet.private["a"]
}

moved {
  from = aws_subnet.private_b
  to   = module.network.aws_subnet.private["b"]
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route.public_internet
  to   = module.network.aws_route.public_internet
}

moved {
  from = aws_route_table_association.public_a
  to   = module.network.aws_route_table_association.public["a"]
}

moved {
  from = aws_route_table_association.public_b
  to   = module.network.aws_route_table_association.public["b"]
}

moved {
  from = aws_route_table.private
  to   = module.network.aws_route_table.private
}

moved {
  from = aws_route_table_association.private_a
  to   = module.network.aws_route_table_association.private["a"]
}

moved {
  from = aws_route_table_association.private_b
  to   = module.network.aws_route_table_association.private["b"]
}
```

```bash
terraform plan -out=tfplan      # BẮT BUỘC: Plan: 0 to add, 0 to change, 0 to destroy
terraform apply tfplan
terraform state list            # mọi địa chỉ giờ bắt đầu bằng module.network.
```

Plan có bất kỳ `to destroy` nào → **không apply**. Đọc resource nào bị destroy, kiểm tra `moved` tương ứng (sai tên, sai khóa, thiếu block).

### Bước 4 — Thí nghiệm: thiếu một `moved`

Comment (thêm `#` ở đầu mỗi dòng) block `moved` của `aws_route_table_association.private_b`. Chạy `terraform plan` (không apply). Ghi lại: có bao nhiêu add/destroy, là resource nào? Bỏ comment, plan lại về 0.

### Bước 5 — Kiểm tra chất lượng `[WSL]`

Tại thư mục gốc lab (`~/devops-lab/07-terraform/refactor-lab`):

```bash
cd ~/devops-lab/07-terraform/refactor-lab
terraform fmt -check -recursive && echo "fmt OK"
```

Tạo `.tflint.hcl` ở thư mục gốc lab (nội dung như mục 4.10), rồi:

```bash
docker run --rm -v "$(pwd)":/data -t --entrypoint /bin/sh \
  ghcr.io/terraform-linters/tflint:v0.65.0 \
  -c "tflint --init && tflint --recursive"
```

Thử lỗi: tạm thêm vào `envs/dev/main.tf` một biến không dùng (`variable "unused" { type = string }`) → chạy tflint lại → đọc cảnh báo → xóa biến.

```bash
docker run --rm -v "$(pwd)":/src:ro aquasec/trivy:0.76.1 config /src
```

❓ Ghi lại các phát hiện của Trivy vào `week16/trivy-network.md`: mã kiểm tra, mức độ, resource. Với mỗi phát hiện, quyết định **sửa** hay **chấp nhận có lý do** (ví dụ public subnet tự gán public IP là cố ý; VPC flow logs tốn phí lưu log — chấp nhận ở môi trường lab, ghi lại).

### Bước 6 — `terraform test` với provider giả lập `[WSL]`

Tạo `modules/network/tests/network.tftest.hcl`:

```hcl
mock_provider "aws" {}

variables {
  name     = "test"
  vpc_cidr = "10.99.0.0/16"

  public_subnets = {
    a = { az = "ap-southeast-1a", cidr = "10.99.1.0/24" }
    b = { az = "ap-southeast-1b", cidr = "10.99.2.0/24" }
  }

  private_subnets = {
    a = { az = "ap-southeast-1a", cidr = "10.99.11.0/24" }
  }
}

run "public_and_private_subnets" {
  command = apply # an toàn: provider aws là mock, không gọi API thật

  assert {
    condition     = aws_vpc.this.cidr_block == "10.99.0.0/16"
    error_message = "CIDR của VPC phải lấy đúng từ var.vpc_cidr"
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 1
    error_message = "Số subnet phải khớp với input"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch == false])
    error_message = "Private subnet không được tự gán public IP"
  }

  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "Public route table phải có route ra Internet"
  }

  assert {
    condition     = length(aws_route_table_association.private) == length(aws_subnet.private)
    error_message = "Mỗi private subnet phải gắn với private route table"
  }
}

run "invalid_cidr_rejected" {
  command = plan

  variables {
    vpc_cidr = "10.99.0.0/33"
  }

  expect_failures = [var.vpc_cidr]
}
```

```bash
cd ~/devops-lab/07-terraform/refactor-lab/modules/network
terraform init
terraform test
```

Thử phá: đổi `map_public_ip_on_launch = false` thành `true` trong `aws_subnet.private` của module → `terraform test` phải **fail** ở assert thứ ba. Hoàn tác.

⚠️ Nếu xóa dòng `mock_provider "aws" {}`, `command = apply` sẽ tạo VPC **thật** (rồi tự hủy cuối test). Không nguy hiểm về tiền với VPC, nhưng đó không phải điều bạn muốn — luôn kiểm tra dòng `mock_provider` trước khi chạy.

### Bước 7 — Khung `envs/prod` (chỉ đọc, KHÔNG apply)

```bash
mkdir -p ~/devops-lab/07-terraform/refactor-lab/envs/prod
```

Viết `envs/prod/main.tf` gọi cùng module với CIDR `10.40.0.0/16` và 2 AZ, `providers.tf` với `Env = "prod"`. Chạy `terraform init && terraform validate` (không plan, không apply). Viết vào `week16/envs.md`: trong một công ty thật, `envs/prod` sẽ khác `envs/dev` ở những điểm nào (backend key, tài khoản AWS, người được apply, tfvars)?

### Bước 8 — Dọn dẹp

```bash
cd ~/devops-lab/07-terraform/refactor-lab/envs/dev
terraform destroy                  # ⚠️ đọc plan: Plan: 0 to add, 0 to change, 13 to destroy
terraform state list               # rỗng
~/devops-lab/06-aws/find-leftovers.sh
aws ec2 describe-vpcs --filters Name=tag:Lab,Values=tf07-refactor --query 'Vpcs[].VpcId'   # []
```

Giữ lại thư mục `refactor-lab` (code) để làm bài tập; chỉ hạ tầng bị xóa.

---

## 10. Kết quả mong đợi

| Bước | Dấu hiệu đúng |
|---|---|
| 1 | `Plan: 13 to add`; `state list` đếm được 13 |
| 3 (chưa có `moved`) | `Plan: 13 to add, 0 to change, 13 to destroy` |
| 3 (có `moved`) | 13 dòng `has moved to`; `Plan: 0 to add, 0 to change, 0 to destroy`; sau apply mọi địa chỉ có tiền tố `module.network.` |
| 4 | `1 to add, 1 to destroy` — đúng `module.network.aws_route_table_association.private["b"]` / `aws_route_table_association.private_b` |
| 5 | `fmt OK`; tflint không lỗi (hoặc chỉ cảnh báo bạn giải thích được); biến `unused` bị báo; Trivy liệt kê phát hiện và bạn ghi quyết định cho từng cái |
| 6 | `Success! 2 passed, 0 failed.`; khi phá module, assert thứ ba fail với đúng `error_message` |
| 7 | `validate` báo `Success! The configuration is valid.` |
| 8 | `13 to destroy`; `describe-vpcs` trả `[]` |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `Module not installed` / `Module source has changed` | Thêm hoặc đổi `source` mà chưa `init` | `terraform init` |
| Plan sau refactor có destroy | Thiếu/sai `moved` (sai tên, sai khóa `["a"]`) | So từng dòng destroy với `moved.tf` |
| `Error: Moved object still exists` | Địa chỉ `from` vẫn còn được khai báo trong code | Xóa resource cũ khỏi code — `moved` chỉ dùng khi địa chỉ cũ **không còn** |
| `Unsupported argument` khi gọi module | Tên input sai hoặc module không có `variable` đó | Đọc `variables.tf` của module |
| `Invalid value for variable` kèm thông điệp tiếng Việt của bạn | `validation` đang làm đúng việc | Sửa giá trị truyền vào |
| `Module ... cannot be used with for_each because it contains a nested provider configuration` | Module con có block `provider` | Chuyển cấu hình provider lên root |
| `version` báo lỗi với module local/Git | `version` chỉ dùng cho module từ registry | Git: dùng `?ref=`; local: bỏ `version` |
| tflint báo `Failed to install a plugin` / rate limit GitHub | `tflint --init` tải plugin từ GitHub API | Chạy lại sau ít phút; đặt biến `GITHUB_TOKEN` (token chỉ đọc) cho container nếu bị giới hạn thường xuyên — kiểm tra hướng dẫn plugin của tflint |
| `terraform test` báo cần credential AWS | Thiếu `mock_provider "aws" {}` | Thêm block mock; kiểm tra đang đứng đúng thư mục module |
| Export `TF_VAR_instance_type` mà không có tác dụng | `terraform.tfvars` có cùng biến và ưu tiên cao hơn | Xem thứ tự ưu tiên ở mục 4.8 |
| `docker: permission denied` / không kết nối được daemon | Docker Desktop WSL Integration tắt | Bật WSL Integration |

---

## 12. Đọc log và xử lý lỗi

**Đọc plan theo thứ tự này** (mọi lần, không chỉ khi refactor):

1. Dòng **`Plan: X to add, Y to change, Z to destroy`** ở cuối — có khớp kỳ vọng không?
2. Tìm `must be replaced` / `forces replacement` — thuộc tính nào gây thay thế?
3. Tìm `has moved to` — đủ số resource bạn định di chuyển chưa?
4. Với `~ update in-place`, đọc **giá trị cũ → mới** của từng thuộc tính.

**Lỗi khi gọi module** luôn chỉ ra file và dòng **ở nơi gọi** và/hoặc **trong module**:

```text
Error: Invalid value for variable

  on main.tf line 4, in module "network":
   4:   vpc_cidr = "10.30.0.0/33"
    ├────────────────
    │ var.vpc_cidr is "10.30.0.0/33"

vpc_cidr phải là một dải CIDR IPv4 hợp lệ, ví dụ 10.20.0.0/16.

This was checked by the validation rule at ../../modules/network/variables.tf:9,3-13.
```

(Minh họa.) Dòng cuối cho biết **luật nào** từ chối — mở đúng file đó.

**Lỗi trong `terraform test`**: thông báo gồm tên `run`, `error_message` của assert fail, và giá trị thực tế. Đây là lý do `error_message` phải mô tả **ý đồ** ("Private subnet không được tự gán public IP"), không phải "assert failed".

**Phát hiện của Trivy/tflint**: đọc mã kiểm tra → mở link → quyết định sửa hay chấp nhận. Ghi mọi quyết định "chấp nhận" kèm lý do — đó là hồ sơ cho câu hỏi phỏng vấn "bạn xử lý kết quả quét bảo mật thế nào?".

---

## 13. Câu hỏi kiểm tra kiến thức

1. Root module và child module khác nhau thế nào? Tài nguyên của child module nằm trong state nào, với địa chỉ ra sao?
2. So sánh module với hàm trong Java: variable, output, locals, validation tương ứng với gì?
3. Kể ba loại `source`. Loại nào dùng được `version`? Ghim phiên bản module Git bằng cách nào?
4. Vì sao module con không được chứa block `provider`? Hệ quả kỹ thuật nếu vi phạm là gì?
5. Bạn đổi `source` của một module. Lệnh nào phải chạy trước `plan`?
6. Khi chuyển code phẳng vào module, vì sao plan đòi destroy? Viết `moved` cho `aws_subnet.public_a` → phần tử khóa `a` của `aws_subnet.public` trong `module.network`.
7. Vì sao dùng `for_each` với map tốt hơn `count` với list cho subnet?
8. Nêu hai lý do HashiCorp không khuyên dùng CLI workspaces để tách dev/prod. Workspaces còn hợp với trường hợp nào?
9. Sắp xếp theo thứ tự ưu tiên: `TF_VAR_x`, `terraform.tfvars`, `-var x=...`, `default`, `a.auto.tfvars`.
10. `default_tags` giải quyết vấn đề gì? Tag `Name` nên đặt ở đâu?
11. `terraform validate` và tflint khác nhau ở điểm nào? Cho một ví dụ lỗi chỉ tflint bắt được.
12. `trivy config` báo "subnet tự gán public IP". Bạn xử lý thế nào với `taskhub`?
13. `terraform test` mặc định có tạo hạ tầng thật không? `mock_provider` thay đổi điều gì? `expect_failures` dùng để làm gì?
14. Liệt kê các bước kiểm tra Terraform chạy được trong CI **không cần** credential AWS.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Thêm AZ thứ ba.** Thêm subnet `c` (public và private, AZ `ap-southeast-1c`) vào lab chỉ bằng cách sửa `envs/dev/main.tf`. Plan phải ra đúng những resource mới nào? Không apply cũng được — nhưng giải thích từng dòng `+`. So sánh với số chỗ phải sửa ở code phẳng (Bước 1).

**Bài 2 — Validation chặt hơn.** Thêm `validation` cho `public_subnets`: mọi CIDR subnet phải **nằm trong** `vpc_cidr`. Gợi ý: so sánh `cidrhost(sub, 0)` với dải của VPC — hoặc tìm hàm phù hợp trong tài liệu hàm của Terraform. Viết thêm một `run` dùng `expect_failures` chứng minh luật hoạt động. (Lưu ý: validation tham chiếu biến khác chỉ được hỗ trợ từ một phiên bản Terraform nhất định — tự kiểm tra trong tài liệu.)

**Bài 3 — Output cho module tiếp theo.** Module `app_server` ở v4 cần: VPC ID, **một** public subnet ID để đặt EC2, và danh sách private subnet ID (cho RDS ở lab tuần 14). Thiết kế output của `network` cho đủ, và viết block `module "app_server"` (chỉ phần gọi, chưa cần module thật) dùng các output đó.

**Bài 4 — Đọc module công khai.** Mở mã nguồn `terraform-aws-modules/vpc/aws` phiên bản 6.7.3 trên GitHub/Registry. Tìm: (a) biến bật NAT Gateway và giá trị mặc định của nó; (b) cách module đặt tên subnet; (c) module có block `provider` không. Viết nửa trang so sánh với module tự viết của bạn: bạn sẽ dùng cái nào cho `taskhub`, cái nào ở công ty có 20 VPC?

**Bài 5 — Tách môi trường bằng tfvars.** Biến `envs/dev` thành dạng nhận mọi giá trị qua biến (`variables.tf`) và `terraform.tfvars`. Tạo thêm `test.tfvars` với CIDR `10.31.0.0/16` và chạy `terraform plan -var-file=test.tfvars` (không apply). Vì sao plan đòi **thay thế** VPC? Rút ra kết luận: vì sao dev và prod nên là hai **thư mục** (hai state), không phải hai file tfvars trên **cùng** state?

**Bài 6 — Pipeline kiểm tra.** Viết (chưa cần chạy) workflow GitHub Actions `infra.yml` cho repo `taskhub`: chạy khi PR thay đổi `infra/**`, gồm `fmt -check`, `init -backend=false` + `validate` cho từng thư mục `envs/*`, tflint, `trivy config`, `terraform test` cho từng module. Áp dụng mọi quy tắc của [Module 05](../05-CICD/README.md): `permissions` tối thiểu, `ubuntu-24.04`, `timeout-minutes`, action ghim SHA (dùng `git ls-remote` để lấy SHA thật cho action cài Terraform bạn chọn). Kiểm tra bằng actionlint.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được root/child module, địa chỉ `module.x.resource.y` trong state.
- [ ] Viết được một module có input có kiểu, `validation`, output — không có block `provider`.
- [ ] Refactor code phẳng vào module với plan `0 to destroy` ngay lần đầu (hoặc tự tìm ra `moved` bị thiếu).
- [ ] Trình bày được vì sao chọn thư mục riêng cho mỗi môi trường, kèm trích dẫn lý do từ tài liệu.
- [ ] Nhớ thứ tự ưu tiên biến, giải thích được lỗi "đã export `TF_VAR_` mà không ăn".
- [ ] Chạy được fmt, validate, tflint, trivy config bằng container; xử lý từng phát hiện có lý do.
- [ ] Viết được `terraform test` với `mock_provider`, có một `run` dùng `expect_failures`.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Terraform — Module blocks (syntax)](https://developer.hashicorp.com/terraform/language/modules/syntax) | `source`, `version` chỉ cho registry, Git `?ref=`, `init` sau khi đổi source | 2026-10-31 |
| [Terraform — Providers within modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers) | Module con không có `provider`; legacy module không dùng được `count`/`for_each`/`depends_on` | 2026-10-31 |
| [Terraform — Refactoring (`moved`)](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring) | `moved` vào module, giữ block cũ | 2026-10-31 |
| [Terraform — CLI workspaces](https://developer.hashicorp.com/terraform/cli/workspaces) | Workspaces không hợp để tách môi trường cần credential/quyền riêng | 2026-10-31 |
| [Terraform — Input variables](https://developer.hashicorp.com/terraform/language/values/variables) | Thứ tự ưu tiên biến, `ephemeral = true` | 2026-10-31 |
| [Terraform — Tests](https://developer.hashicorp.com/terraform/language/tests) | `.tftest.hcl`, `command = apply` mặc định, tạo hạ tầng thật (≥ 1.6) | 2026-10-31 |
| [Terraform — Test mocking](https://developer.hashicorp.com/terraform/language/tests/mocking) | `mock_provider`, giá trị sinh tự động (≥ 1.7) | 2026-10-31 |
| [terraform-aws-modules/terraform-aws-vpc releases](https://github.com/terraform-aws-modules/terraform-aws-vpc/releases) | Module VPC công khai, v6.7.3 | 2026-10-31 |
| [TFLint README](https://github.com/terraform-linters/tflint) | Image `ghcr.io/terraform-linters/tflint`, `--init`, `--recursive`, cấu hình plugin | 2026-10-31 |
| [TFLint releases](https://github.com/terraform-linters/tflint/releases) | v0.65.0 | 2026-10-31 |
| [tflint-ruleset-aws](https://github.com/terraform-linters/tflint-ruleset-aws) | Plugin AWS 0.50.0, ví dụ `instance_type` sai | 2026-10-31 |
| [Trivy — Misconfiguration scanning](https://trivy.dev/latest/docs/scanner/misconfiguration/) | `trivy config`, `--severity` | 2026-10-31 |
| [Docker Hub — aquasec/trivy:0.76.1](https://hub.docker.com/r/aquasec/trivy/tags) | Tag 0.76.1 tồn tại | 2026-10-31 |
| [pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform) | Hook `terraform_fmt`, `terraform_tflint`, `terraform_trivy` | 2026-10-31 |
