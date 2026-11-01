# 03. Terraform state và remote backend

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [02. Terraform cơ bản](02-terraform-basics.md) (provider, resource, `init/plan/apply/destroy`), [AWS 05 — S3](../06-AWS/05-s3.md) (versioning, Block Public Access, bucket policy), [AWS 02 — IAM](../06-AWS/02-iam.md)
> Môi trường: `[WSL]` Ubuntu 24.04 có Terraform ≥ 1.17, Docker Desktop (đã bật WSL Integration), AWS CLI v2 (profile `taskhub`), `jq`
> Phiên bản khi viết: Terraform 1.17.1, provider `kreuzwerker/docker` ~> 4.6, `hashicorp/random` ~> 3.7, `hashicorp/aws` ~> 6.0

> 💰 **Chi phí của bài này:** Phần A chạy hoàn toàn trên máy (Docker) → **0 USD**. Phần B tạo **một S3 bucket** chứa vài file state cỡ KB → **gần như 0 USD**. Bucket này là **bucket state thật của dự án** — được **giữ lại** cho v4. Không tạo EC2, NAT hay public IPv4.

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

- Giải thích **state** là gì, vì sao Terraform cần nó (ánh xạ, metadata, hiệu năng, đồng bộ) và đọc được cấu trúc file `terraform.tfstate`.
- Chứng minh bằng thực nghiệm rằng **state chứa secret ở dạng rõ**, biết `sensitive = true` **không** che được trong state, và dùng **ephemeral** + **write-only argument** (`value_wo`) để secret không bao giờ vào state.
- Cấu hình **S3 backend** với `use_lockfile = true` (khóa bằng file `.tflock`, không cần DynamoDB), nêu đủ quyền IAM cần thiết.
- Giải quyết bài toán "con gà – quả trứng": dựng **bucket state** bằng một root module `bootstrap/` dùng state local, rồi **migrate** state vào S3.
- Đọc thông báo **lock**, biết khi nào được (và không được) dùng `force-unlock`.
- Đổi địa chỉ resource bằng **`moved {}`**, ngừng quản lý bằng **`removed {}`**, nhận quản lý resource có sẵn bằng **`import {}`** — và vì sao các block này tốt hơn lệnh `terraform state mv/rm/import`.
- Phát hiện **drift** bằng `terraform plan -refresh-only`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Kiến thức state dùng tới |
|---|---|
| Hai người cùng `terraform apply` một lúc → hạ tầng hỏng, state lệch | **Locking** trên remote backend |
| Laptop hỏng, mất file `terraform.tfstate` → Terraform "quên" toàn bộ hạ tầng, `apply` lại sẽ tạo trùng | **Remote backend** + **versioning** |
| File state bị commit lên GitHub public, trong đó có mật khẩu database | State **chứa secret** → không commit, mã hóa, hạn chế quyền; dùng **write-only** |
| Đổi tên `aws_instance.web` thành `aws_instance.app` → plan đòi **xóa và tạo lại** EC2 production | **`moved {}`** |
| Bucket backup đã có dữ liệu từ v2, giờ muốn Terraform quản lý mà **không** tạo lại | **`import {}`** (dự án v4 làm đúng việc này) |
| Ai đó sửa Security Group bằng console lúc 2 giờ sáng | **Drift** → `plan -refresh-only` |
| Pipeline CI chạy `plan` trên PR | CI cần đọc state ở chỗ dùng chung (S3), không phải trên laptop của bạn |

Câu hỏi phỏng vấn kinh điển: *"State của Terraform lưu ở đâu, vì sao, và bạn bảo vệ nó thế nào?"* — bài này trả lời trọn vẹn câu đó.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Nhắc lại: Terraform so sánh ba thứ

Ở [bài 02](02-terraform-basics.md) bạn đã chạy `plan` và thấy dấu `+`, `~`, `-`. Để ra được kế hoạch đó, Terraform so sánh:

| Nguồn | Là gì | Ví dụ |
|---|---|---|
| **Configuration** (các file `.tf`) | Trạng thái **mong muốn** | "Phải có container `tf07-state-web` mở cổng 18081" |
| **State** (`terraform.tfstate`) | Trí nhớ của Terraform: **nó đã tạo những gì, ID là gì** | `docker_container.web` ↔ container ID `9a55...` |
| **Thế giới thật** (API của Docker/AWS) | Trạng thái **thực tế** | Container đó còn chạy không? cổng nào? |

Không có state, Terraform không thể biết container `9a55...` là "của nó" hay của người khác — vì Docker/AWS không có khái niệm "resource này thuộc Terraform".

### 3.2. Bốn lý do state tồn tại (theo tài liệu HashiCorp)

| Lý do | Giải thích |
|---|---|
| **Mapping** — ánh xạ ra thế giới thật | Mỗi địa chỉ trong code (`aws_vpc.main`) gắn với đúng một object thật (`vpc-0abc...`) |
| **Metadata** | Lưu danh sách phụ thuộc gần nhất → khi bạn **xóa** resource khỏi code, Terraform vẫn biết thứ tự hủy đúng |
| **Performance** | Cache giá trị thuộc tính → hạ tầng lớn không phải hỏi API cho mọi resource mỗi lần |
| **Syncing** | Cả team phải làm việc trên **cùng một** state → cần remote backend có locking |

### 3.3. Backend là gì

**Backend** quyết định state được **lưu ở đâu** và **khóa thế nào**:

- **Local backend** (mặc định): file `terraform.tfstate` trong thư mục làm việc.
- **Remote backend**: S3, HCP Terraform, Azure Blob, GCS… Dự án `taskhub` dùng **S3** vì đã ở trên AWS và gần như miễn phí.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Bên trong `terraform.tfstate`

State là một file **JSON**. Phần đầu (minh họa, đã rút gọn):

```json
{
  "version": 4,
  "terraform_version": "1.17.1",
  "serial": 7,
  "lineage": "3f1c2a8e-....",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "docker_container",
      "name": "web",
      "provider": "provider[\"registry.terraform.io/kreuzwerker/docker\"]",
      "instances": [
        {
          "attributes": {
            "id": "9a550c0f0163...",
            "name": "tf07-state-web",
            "ports": [{ "internal": 80, "external": 18081, "ip": "0.0.0.0", "protocol": "tcp" }]
          }
        }
      ]
    }
  ]
}
```

| Trường | Ý nghĩa |
|---|---|
| `serial` | Tăng mỗi lần state thay đổi — dùng để phát hiện ghi đè bản cũ lên bản mới |
| `lineage` | ID duy nhất sinh khi state được tạo lần đầu — hai state khác lineage là hai "dòng dõi" khác nhau, Terraform không cho trộn lẫn |
| `mode` | `managed` (resource) hoặc `data` (data source) |
| `type` + `name` | Ghép lại thành **địa chỉ** `docker_container.web` |
| `attributes` | **Toàn bộ** thuộc tính provider trả về — kể cả thứ nhạy cảm |

> ⚠️ **Không bao giờ sửa state bằng tay.** Một dấu phẩy sai là hỏng; sửa `serial` sai là ghi đè mất thay đổi của người khác. Mọi thao tác trên state đều có lệnh hoặc block riêng (mục 4.8–4.10).

### 4.2. 🟥 State chứa secret ở dạng rõ

Tài liệu HashiCorp nói thẳng: secret bạn đưa vào configuration sẽ được **lưu trong state và plan file**; state local là **văn bản thường**.

Hiểu lầm phổ biến: *"Tôi đã đặt `sensitive = true` rồi mà."*

| Cơ chế | Che ở đâu | Có vào state không? |
|---|---|---|
| `sensitive = true` (biến/output) | Chỉ che khi **in ra màn hình** (`plan`, `output`) | **Có**, dạng rõ |
| **Ephemeral** (Terraform ≥ 1.10): `ephemeral "..." {}`, biến `ephemeral = true` | Chỉ tồn tại trong một lần chạy | **Không** — không vào state lẫn plan file |
| **Write-only argument** (Terraform ≥ 1.11), tên thường kết thúc bằng `_wo` | Giá trị chỉ được gửi cho provider lúc apply | **Không** |

Hai tính năng mới đi cùng nhau. Ví dụ dự án v4 dùng (provider `hashicorp/random` ≥ 3.7.0 mới có ephemeral `random_password`):

```hcl
ephemeral "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "postgres_password" {
  name             = "/taskhub/dev/postgres-password"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.db.result
  value_wo_version = 1
}
```

- `value_wo` thay cho `value`: mật khẩu được gửi lên Parameter Store nhưng **không bao giờ** ghi vào state.
- Vì Terraform không lưu giá trị, nó **không thể so sánh** để biết mật khẩu có đổi không. Muốn đổi mật khẩu → **tăng** `value_wo_version` (1 → 2). Đó là lý do mọi write-only argument đi kèm một thuộc tính `..._wo_version`.
- Hệ quả: lần `plan` sau, ephemeral resource sinh **mật khẩu mới** nhưng không gửi đi (version không đổi) → mật khẩu trên AWS giữ nguyên. Nghe lạ nhưng đúng thiết kế.

Dù có write-only, state vẫn chứa nhiều thông tin nhạy cảm khác (ARN, IP, cấu trúc mạng, đôi khi private key của resource tạo key). Nguyên tắc: **coi state là dữ liệu nhạy cảm** — không commit, mã hóa khi lưu, hạn chế ai được đọc.

### 4.3. 🟥 Local backend và giới hạn của nó

Local backend lưu `terraform.tfstate` cạnh code. Khi chạy lệnh ghi, Terraform tạo file khóa `.terraform.tfstate.lock.info` để hai **tiến trình trên cùng máy** không ghi chồng.

| Giới hạn | Hệ quả |
|---|---|
| Chỉ có trên **một máy** | Đồng nghiệp, CI không thấy state → không thể làm việc chung |
| Khóa chỉ có tác dụng **trên máy đó** | Hai người hai máy vẫn ghi chồng được (nếu chép state qua lại) |
| Mất máy = mất state | Terraform "quên" hạ tầng; `apply` lại sẽ cố tạo trùng (lỗi tên đã tồn tại) hoặc tạo bản thứ hai (tốn tiền) |
| Dễ lỡ tay commit | Lộ secret |

`.gitignore` tối thiểu cho mọi repo Terraform:

```gitignore
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
```

`.terraform.lock.hcl` (khóa **phiên bản provider**, khác hoàn toàn khóa state) thì **phải commit**.

### 4.4. 🟥 S3 backend với `use_lockfile`

```hcl
terraform {
  backend "s3" {
    bucket       = "taskhub-tfstate-111122223333"
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

| Tham số | Ý nghĩa |
|---|---|
| `bucket` | Bucket chứa state. **Không dùng biến được** — block `backend` được đọc trước khi biến tồn tại |
| `key` | Đường dẫn object trong bucket. Mỗi root module/môi trường một key riêng |
| `region` | Region của **bucket** (không nhất thiết trùng region tài nguyên) |
| `use_lockfile` | Khóa bằng object `<key>.tflock` trong cùng bucket. Mặc định `false` |
| `encrypt` | Mã hóa phía server cho state và lock file |

**Khóa bằng DynamoDB đã bị deprecate.** Tài liệu S3 backend ghi: DynamoDB-based locking *is deprecated and will be removed in a future minor version*; tham số `dynamodb_table` cũng bị đánh dấu deprecated. Tutorial cũ (2020–2024) hầu hết hướng dẫn tạo bảng DynamoDB — **không làm theo**.

**Quyền IAM tối thiểu** cho người/role chạy Terraform (theo tài liệu S3 backend):

| Đối tượng | Action |
|---|---|
| Bucket `arn:aws:s3:::taskhub-tfstate-...` | `s3:ListBucket` |
| State object `.../envs/dev/terraform.tfstate` | `s3:GetObject`, `s3:PutObject` (không cần `DeleteObject` — Terraform không xóa state) |
| Lock object `.../envs/dev/terraform.tfstate.tflock` | `s3:GetObject`, `s3:PutObject`, **`s3:DeleteObject`** (mở khóa = xóa file khóa) |

Thiếu `s3:DeleteObject` trên lock object là lỗi kinh điển: `apply` chạy xong nhưng **không mở được khóa**, lần sau bị báo đang khóa.

**Versioning** trên bucket state được tài liệu gọi là *highly recommended*: mỗi lần ghi state tạo một phiên bản → state hỏng/bị ghi đè thì lấy lại bản trước.

🟨 **Partial configuration:** thay vì ghi cứng `bucket`/`key` trong code, có thể để trống và truyền lúc init: `terraform init -backend-config=backend.hcl`. Hữu ích khi cùng code chạy cho nhiều tài khoản. Dự án dùng cách ghi thẳng cho dễ đọc.

### 4.5. 🟥 Bài toán con gà – quả trứng: bootstrap

Muốn lưu state vào S3 thì bucket phải **có trước**. Nhưng bucket cũng là hạ tầng — ai tạo nó, và state của **nó** nằm đâu?

Cách phổ biến (dự án dùng cách này):

```text
infra/terraform/
├── bootstrap/      ← root module riêng, CHỈ tạo bucket state
│                     bước 1: chạy với state LOCAL → tạo bucket
│                     bước 2: thêm backend "s3" (key bootstrap/...) → terraform init -migrate-state
└── envs/dev/       ← root module chính, backend "s3" ngay từ đầu (key envs/dev/...)
```

- Bucket bootstrap có `prevent_destroy = true`: lỡ tay `terraform destroy` cũng bị chặn.
- Sau khi migrate, state của bootstrap nằm **trong chính bucket nó tạo**. Hệ quả cần nhớ: muốn xóa bucket này, phải migrate state **về local trước** (mục 9, phần dọn dẹp).
- Lựa chọn khác: tạo bucket bằng tay/CLI rồi chỉ dùng. Đơn giản hơn nhưng bucket không có trong code → không ai review được cấu hình của nó. Tạo bằng Terraform đúng tinh thần IaC hơn.

### 4.6. 🟥 Locking và `force-unlock`

Mọi lệnh có thể **ghi** state (`apply`, `destroy`, `import`, `state mv`…) đều xin khóa trước. Với `use_lockfile`, khóa là object `.tflock`; Terraform dùng ghi có điều kiện của S3 để hai người không cùng tạo được khóa.

Khi khóa đang bị giữ, bạn sẽ thấy (minh họa):

```text
Error: Error acquiring the state lock

Error message: operation error S3: PutObject, https response error StatusCode: 412, ...
Lock Info:
  ID:        b1f0c6c2-7d4e-....
  Path:      taskhub-tfstate-111122223333/envs/dev/terraform.tfstate
  Operation: OperationTypeApply
  Who:       phuong@LEGION
  Version:   1.17.1
  Created:   2027-03-15 08:12:45.123 +0000 UTC
```

Đọc từ dưới lên: **ai** (`Who`), **đang làm gì** (`Operation`), **từ lúc nào** (`Created`). Chín trên mười lần câu trả lời là "chính tôi, ở terminal khác" hoặc "pipeline CI đang chạy" → **chờ**. `-lock-timeout=5m` cho lệnh tự chờ tối đa 5 phút thay vì lỗi ngay.

```bash
terraform force-unlock b1f0c6c2-7d4e-....    # ⚠️
```

⚠️ Tài liệu HashiCorp: *Be very careful with this command* — mở khóa khi người khác đang giữ sẽ tạo ra **nhiều người ghi cùng lúc**. Chỉ dùng để mở **khóa của chính bạn** khi việc tự mở khóa thất bại (ví dụ terminal bị kill giữa chừng, mất mạng lúc apply). Lệnh này không thay đổi hạ tầng, chỉ xóa khóa.

`-lock=false`: tắt khóa hoàn toàn. Không có lý do chính đáng nào để dùng trong dự án này.

### 4.7. 🟨 Chia sẻ dữ liệu giữa các root module

Root module A cần biết `vpc_id` do root module B tạo. Hai cách:

| Cách | Ưu | Nhược |
|---|---|---|
| Data source `terraform_remote_state` (đọc output của state B) | Đơn giản | Người đọc phải có quyền đọc **toàn bộ** state B — thường chứa thông tin nhạy cảm |
| Data source của provider (`data "aws_vpc"` lọc theo tag), hoặc B ghi giá trị vào **SSM Parameter Store** để A đọc | Chỉ lộ đúng thứ cần chia sẻ | Phải thiết kế tag/tên parameter |

Tài liệu HashiCorp khuyến nghị: *When possible, we recommend explicitly publishing data for external consumption to a separate location* thay vì đọc remote state. `taskhub` hiện chỉ có một root module chính nên chưa cần — nhưng đây là câu hỏi hay gặp khi phỏng vấn.

### 4.8. 🟥 Đổi địa chỉ: `moved {}` thay cho `terraform state mv`

Đổi tên resource trong code → Terraform thấy địa chỉ cũ biến mất (xóa) và địa chỉ mới xuất hiện (tạo). Với container thì chỉ mất vài giây; với **database production** thì là thảm họa.

```hcl
moved {
  from = docker_container.web
  to   = docker_container.frontend
}
```

| | `moved {}` (Terraform ≥ 1.1) | `terraform state mv` |
|---|---|---|
| Nằm ở đâu | Trong code → đi qua **Pull Request**, được review | Lệnh gõ tay, sửa state ngay lập tức |
| Ai được hưởng | Mọi state dùng code này (mọi môi trường, mọi đồng nghiệp) khi họ `apply` | Chỉ một state bạn đang trỏ tới |
| Thấy trước | `plan` hiện `has moved to` | Không có plan |

Dùng được cho: đổi tên, chuyển resource vào/ra module (bài 04 dùng rất nhiều), chuyển sang `count`/`for_each`. Tài liệu khuyên **giữ lại** các `moved` block cũ trong module dùng chung — xóa đi thì người chưa kịp apply sẽ bị plan xóa-tạo.

### 4.9. 🟨 Ngừng quản lý: `removed {}` thay cho `terraform state rm`

Muốn Terraform **thôi quản lý** một resource nhưng **không xóa** nó ngoài đời (ví dụ chuyển sang root module khác quản lý):

```hcl
removed {
  from = docker_volume.cache

  lifecycle {
    destroy = false
  }
}
```

Block `removed` có từ Terraform 1.7. Tương tự `moved`: đi qua review, thấy trước bằng plan. Nếu chỉ **xóa resource khỏi code** mà không có block này → Terraform sẽ **hủy** object thật.

### 4.10. 🟥 Nhận quản lý resource có sẵn: `import {}`

```hcl
import {
  to = docker_volume.data
  id = "tf07-state-data"
}

resource "docker_volume" "data" {
  name = "tf07-state-data"
}
```

- `to`: địa chỉ resource trong code (có thể nằm trong module, ví dụ `module.x.aws_s3_bucket.this`).
- `id`: **import ID** — mỗi loại resource một định dạng, xem mục *Import* cuối trang tài liệu của resource đó (volume Docker: tên volume; S3 bucket: tên bucket; EC2: instance ID).
- `import` block có từ Terraform 1.5, hỗ trợ `for_each`. `plan` hiện `will be imported` → review → `apply` mới thực sự ghi vào state.
- Sau khi import thành công, block không còn tác dụng; nhiều team giữ lại làm hồ sơ, nhiều team xóa trong PR kế tiếp — cả hai đều được.
- Mục tiêu sau import: `plan` ra **No changes**. Nếu plan còn đòi sửa/thay → code chưa mô tả đúng object thật, sửa code cho khớp trước khi apply.

**Sinh code tự động:** chỉ viết block `import`, chưa viết `resource`, rồi:

```bash
terraform plan -generate-config-out=generated.tf
```

Terraform đọc object thật và **viết** block `resource` vào `generated.tf`. Tài liệu ghi đây là tính năng **thử nghiệm** (từ 1.5): định dạng có thể đổi, và với resource phức tạp có thể sinh code **không hợp lệ** (hai thuộc tính xung đột) → luôn đọc lại và dọn code sinh ra. File đích **không được tồn tại** sẵn.

Lệnh cũ `terraform import <địa chỉ> <id>` vẫn chạy được nhưng ghi state ngay, không có plan, không qua review — chỉ dùng khi buộc phải.

### 4.11. 🟥 Drift và `-refresh-only`

**Drift** (trôi lệch): thế giới thật khác với state, vì ai đó sửa ngoài Terraform.

| Lệnh | Làm gì |
|---|---|
| `terraform plan` | Mặc định **refresh** (hỏi API) trước, rồi đề xuất đưa thế giới thật về đúng **code** |
| `terraform plan -refresh-only` | Chỉ cho xem **state sẽ thay đổi thế nào** để khớp thế giới thật. Không đề xuất sửa hạ tầng |
| `terraform apply -refresh-only` | **Chấp nhận** thực tế: ghi kết quả refresh vào state, không đụng hạ tầng |

Quy trình khi nghi ngờ drift: `plan -refresh-only` → hiểu **ai sửa gì, vì sao** → quyết định: (a) sửa code cho khớp thực tế (thay đổi đó đúng), hoặc (b) `apply` bình thường để đưa thực tế về code (thay đổi đó sai). Không bao giờ "apply cho xong" mà chưa biết vì sao có drift.

🟦 Break-fix của module này đi sâu vào drift (state lệch, resource bị xóa tay, khóa kẹt).

### 4.12. 🟨 `state pull/push` và khôi phục state

- `terraform state pull > backup.tfstate`: tải state hiện tại về để xem/sao lưu. An toàn.
- ⚠️ `terraform state push file.tfstate`: **ghi đè** state remote. Terraform kiểm tra `lineage` và `serial` để chặn đẩy bản cũ đè bản mới — đừng dùng `-force` để vượt qua.
- Khôi phục từ versioning: tìm phiên bản trước bằng `aws s3api list-object-versions`, tải về bằng `aws s3api get-object --version-id ...`, kiểm tra kỹ, rồi mới cân nhắc `state push`. Đây là thao tác khẩn cấp hiếm gặp — biết là đủ.

---

## 5. Ví dụ thực tế

**Ví dụ 1 — "Tôi chỉ đổi tên cho đẹp".** Một kỹ sư đổi `aws_db_instance.db` thành `aws_db_instance.main` cho thống nhất quy ước, mở PR. Reviewer đọc plan thấy `1 to add, 1 to destroy` trên database production và chặn lại. Sửa: thêm một `moved` block → plan còn `0 to destroy`. Bài học: **luôn đọc dòng `Plan:`**, và đổi địa chỉ luôn đi kèm `moved`.

**Ví dụ 2 — State trên laptop.** Một dự án nhỏ để state local. Người duy nhất biết chạy Terraform nghỉ việc, laptop được format. Người mới `apply` lại → lỗi hàng loạt vì tên bucket, tên role đã tồn tại; một số resource không có ràng buộc tên bị tạo **bản thứ hai** và tính tiền song song. Mất hai ngày `import` lại từng thứ. Remote backend + versioning ngay từ đầu tốn 10 phút.

**Ví dụ 3 — Khóa kẹt sau khi mất mạng.** Wi-Fi rớt giữa lúc `apply`. Lần sau báo `Error acquiring the state lock`, `Who` là chính mình, `Created` cách đây 20 phút, không pipeline nào đang chạy. Đây đúng là trường hợp `force-unlock` được phép — sau đó chạy `plan` ngay để xem lần apply dở dang đã tạo những gì.

---

## 6. Sơ đồ kiến trúc

```text
                       ┌───────────────────────────── S3: taskhub-tfstate-111122223333 ─────────────┐
 [WSL] terraform apply │  versioning ON · Block Public Access · SSE · policy chặn non-TLS            │
        │              │                                                                              │
        │ 1. PutObject │  bootstrap/terraform.tfstate          (state của chính bucket này)           │
        │  (điều kiện) │  envs/dev/terraform.tfstate           ← v4                                   │
        ├─────────────►│  envs/dev/terraform.tfstate.tflock    ← chỉ tồn tại trong lúc có người ghi   │
        │ 2. Get state │                                                                              │
        │◄─────────────│                                                                              │
        │ 3. refresh   └──────────────────────────────────────────────────────────────────────────────┘
        ▼
  API AWS/Docker ──► so sánh code ↔ state ↔ thực tế ──► plan ──► apply ──► 4. PutObject state mới (version mới)
                                                                            5. DeleteObject .tflock (mở khóa)
```

```text
Đổi địa chỉ / quyền quản lý — nên dùng block (đi qua PR, có plan):

  code cũ: docker_container.web ──moved{}──►  docker_container.frontend      (không hủy)
  object có sẵn ngoài Terraform ──import{}──►  docker_volume.data             (nhận quản lý)
  docker_volume.cache ──removed{ destroy = false }──► (thôi quản lý, object vẫn còn)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `terraform state list` | Liệt kê địa chỉ trong state | 🟥 |
| `terraform state show <địa chỉ>` | Xem thuộc tính một resource trong state | 🟥 |
| `terraform show` / `terraform show -json` | Xem toàn bộ state (dạng người đọc / JSON) | 🟥 |
| `terraform plan -refresh-only` | Phát hiện drift | 🟥 |
| `terraform apply -refresh-only` | Chấp nhận drift vào state | 🟨 |
| `terraform plan -generate-config-out=<file>` | Sinh code cho `import` block | 🟨 |
| `terraform init -migrate-state` | Chuyển state sang backend mới | 🟥 |
| `terraform init -reconfigure` | Dùng backend mới **không** chuyển state | 🟨 |
| `terraform force-unlock <LOCK_ID>` ⚠️ | Mở khóa bị kẹt | 🟨 |
| `terraform state pull` | Tải state về stdout | 🟨 |
| `terraform state mv/rm`, `terraform import` | Bản "lệnh" cũ của `moved/removed/import` | 🟦 |
| `aws s3api list-object-versions --bucket B --prefix K` | Xem các phiên bản state | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `terraform state list` và `state show`

```bash
terraform state list
```

```text
docker_container.web
docker_image.nginx
```

```bash
terraform state show docker_container.web
```

```text
# docker_container.web:
resource "docker_container" "web" {
    id       = "9a550c0f0163d39d..."
    image    = "sha256:4f3b..."
    name     = "tf07-state-web"
    ...
    ports {
        external = 18081
        internal = 80
        ip       = "0.0.0.0"
        protocol = "tcp"
    }
}
```

(Đầu ra minh họa — ID, hash trên máy bạn sẽ khác.) `state show` đọc **state**, không hỏi Docker. Nếu container vừa bị xóa tay, lệnh này vẫn hiện như còn — cho tới khi refresh.

### 8.2. `terraform plan -refresh-only`

```text
Note: Objects have changed outside of Terraform

Terraform detected the following changes made outside of Terraform since the
last "terraform apply" which may have affected this plan:

  # docker_container.web has been deleted
  - resource "docker_container" "web" {
      - id   = "9a550c0f0163d39d..." -> null
      - name = "tf07-state-web" -> null
        ...
    }

This is a refresh-only plan, so Terraform will not take any actions to undo
these. If you were expecting these changes then you can apply this plan to
record the updated values in the Terraform state without changing any remote
objects.
```

(Minh họa.) Chú ý câu cuối: refresh-only **không sửa hạ tầng**.

### 8.3. `terraform init -migrate-state`

Sau khi thêm block `backend "s3"` vào thư mục đang có state local:

```bash
terraform init -migrate-state
```

```text
Initializing the backend...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "s3" backend. No existing state was found in the newly
  configured "s3" backend. Do you want to copy this state to the new "s3"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.
```

(Minh họa.) Trả lời `no` = bắt đầu với state **rỗng** → Terraform sẽ coi như chưa tạo gì. Đọc kỹ trước khi gõ.

| Cờ | Khi nào |
|---|---|
| `-migrate-state` | Đổi backend và **mang state theo** |
| `-reconfigure` | Đổi cấu hình backend, **bỏ qua** state cũ (ví dụ trỏ sang bucket khác đã có state đúng) |

### 8.4. `terraform force-unlock`

```bash
terraform force-unlock -force b1f0c6c2-7d4e-....    # ⚠️ -force: không hỏi lại
```

| Phần | Ý nghĩa |
|---|---|
| `LOCK_ID` | Lấy đúng từ dòng `ID:` trong thông báo lỗi |
| `-force` | Bỏ câu hỏi xác nhận. Không dùng cho tới khi bạn đã chắc chắn |

---

## 9. Bài thực hành từng bước

### Phần A — State trên máy với Docker provider (0 USD) `[WSL]`

Chuẩn bị: Docker Desktop đang chạy và `docker ps` trong WSL chạy được (nếu báo `Cannot connect to the Docker daemon`, bật WSL Integration — xem [Docker bài 01](../04-DOCKER/01-vm-vs-container-architecture.md)). Cài `jq` nếu chưa có: `sudo apt install -y jq`.

**A1. Tạo cấu hình ban đầu**

```bash
mkdir -p ~/devops-lab/07-terraform/state-lab && cd ~/devops-lab/07-terraform/state-lab
```

Tạo `main.tf`:

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

resource "docker_image" "nginx" {
  name         = "nginx:1.30-alpine"
  keep_locally = true
}

resource "docker_container" "web" {
  name  = "tf07-state-web"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 18081
  }
}
```

```bash
terraform init
terraform apply        # đọc plan, gõ yes
curl -s -o /dev/null -w '%{http_code}\n' localhost:18081
```

Cổng 18081 bị chiếm → đổi `external` sang số khác.

**A2. Đọc state**

```bash
ls -la                                   # có terraform.tfstate, .terraform/, .terraform.lock.hcl
terraform state list
terraform state show docker_container.web
jq '{version, terraform_version, serial, lineage}' terraform.tfstate
jq -r '.resources[] | "\(.mode) \(.type).\(.name)"' terraform.tfstate
```

❓ Ghi lại `serial`. Chạy `terraform apply` lần nữa (không đổi gì, trả lời `yes` nếu được hỏi hoặc thấy "No changes") rồi xem lại `serial` — có tăng không? Vì sao?

**A3. Thấy khóa local**

1. Terminal 1: `terraform apply -replace=docker_container.web` — **dừng ở câu hỏi** `Enter a value:`, chưa trả lời. (Phải có `-replace`: sau A2 cấu hình không còn thay đổi nào, `terraform apply` trơn in *No changes* rồi thoát luôn, không hỏi gì và không giữ khóa.)
2. Terminal 2 (cùng thư mục): `ls -la .terraform.tfstate.lock.info && cat .terraform.tfstate.lock.info | jq .` rồi `terraform plan`.
3. Ghi lại thông báo lỗi ở terminal 2. Đọc trường `Who`, `Operation`.
4. Terminal 1: gõ `no`. Kiểm tra file `.lock.info` đã biến mất.

Kết quả chạy thật ở terminal 2 (Terraform 1.17.1, 2026-10-31 — `ID`, `Who`, thời gian sẽ khác):

```text
Error: Error acquiring the state lock

Error message: resource temporarily unavailable
Lock Info:
  ID:        b776df9e-8555-f1a0-6d78-3bf8918c9015
  Path:      terraform.tfstate
  Operation: OperationTypeApply
  Who:       phuong@LEGION
  Version:   1.17.1
  Created:   2026-10-31 09:02:24.59410567 +0000 UTC
  Info:
```

**A4. Secret nằm trong state**

Thêm vào `main.tf`:

```hcl
resource "random_password" "demo" {
  length  = 20
  special = false
}

output "demo_password" {
  value     = random_password.demo.result
  sensitive = true
}
```

```bash
terraform apply
terraform output                         # demo_password = <sensitive>
jq -r '.resources[] | select(.type=="random_password") | .instances[0].attributes.result' terraform.tfstate
```

❓ Lệnh `jq` in ra gì? `sensitive = true` đã che ở đâu và **không** che ở đâu?

Giờ thay resource bằng **ephemeral**: xóa block `resource "random_password" "demo"` và `output "demo_password"`, thêm:

```hcl
ephemeral "random_password" "demo" {
  length  = 20
  special = false
}
```

```bash
terraform apply                          # random_password.demo bị destroy khỏi state
grep -c random_password terraform.tfstate || echo "không còn trong state"
```

Ephemeral resource chỉ tồn tại **trong lúc chạy**; ở đây chưa dùng nó vào đâu vì Docker provider không có write-only argument. Ở v4, nó được đưa vào `aws_ssm_parameter.value_wo` (mục 4.2). Xóa block `ephemeral` sau khi quan sát xong.

**A5. Đổi tên bằng `moved`**

Đổi `resource "docker_container" "web"` thành `resource "docker_container" "frontend"` (giữ nguyên `name = "tf07-state-web"`). Chạy `terraform plan` **trước** khi thêm `moved`:

❓ Dòng `Plan:` nói gì? Điều gì sẽ xảy ra với container nếu apply?

Tạo `moved.tf`:

```hcl
moved {
  from = docker_container.web
  to   = docker_container.frontend
}
```

```bash
terraform plan        # mong đợi: "has moved to", Plan: 0 to add, 0 to change, 0 to destroy
terraform apply
terraform state list
```

**A6. Import một volume tạo bằng tay**

```bash
docker volume create tf07-state-data
```

Tạo `import.tf`:

```hcl
import {
  to = docker_volume.data
  id = "tf07-state-data"
}

resource "docker_volume" "data" {
  name = "tf07-state-data"
}
```

```bash
terraform plan        # mong đợi: 1 to import, 0 to add, 0 to change, 0 to destroy
terraform apply
terraform state show docker_volume.data
```

Nếu plan đòi **thay** volume (`forces replacement`) → đọc thuộc tính nào gây ra, chỉnh block `resource` cho khớp object thật rồi plan lại. Không apply khi plan còn đòi destroy.

Thử sinh code tự động với volume thứ hai:

```bash
docker volume create tf07-state-cache
cat >> import.tf <<'EOF'

import {
  to = docker_volume.cache
  id = "tf07-state-cache"
}
EOF
terraform plan -generate-config-out=generated.tf
cat generated.tf
```

Đọc `generated.tf`: những thuộc tính nào Terraform điền? Xóa thuộc tính rỗng/không cần thiết, chạy `terraform plan` lại cho tới khi chỉ còn `1 to import`, rồi `terraform apply`.

**A7. Drift**

```bash
docker rm -f tf07-state-web              # ai đó xóa tay container
terraform state list                     # state vẫn "nhớ" docker_container.frontend
terraform plan -refresh-only             # Terraform phát hiện object đã bị xóa
terraform plan                           # đề xuất tạo lại: 1 to add
terraform apply                          # đưa thực tế về đúng code
curl -s -o /dev/null -w '%{http_code}\n' localhost:18081
```

❓ Nếu ở bước trên bạn chạy `terraform apply -refresh-only` thay vì `apply`, state sẽ ra sao? Container có được tạo lại không?

**A8. Thôi quản lý bằng `removed`**

Xóa block `import` và `resource` của `docker_volume.cache` (trong `import.tf`/`generated.tf`), thêm vào `moved.tf`:

```hcl
removed {
  from = docker_volume.cache

  lifecycle {
    destroy = false
  }
}
```

```bash
terraform plan        # "will no longer be managed by Terraform", 0 to destroy
terraform apply
docker volume ls | grep tf07-state-cache   # volume vẫn còn
```

**A9. Dọn dẹp Phần A**

```bash
terraform destroy                         # xóa container + volume tf07-state-data (image giữ lại: keep_locally)
docker volume rm tf07-state-cache         # volume đã thôi quản lý — tự xóa bằng tay
docker ps -a --filter name=tf07-state     # phải rỗng
docker volume ls --filter name=tf07-state # phải rỗng
```

### Phần B — Bucket state thật của dự án (≈ 0 USD) `[WSL]` `[AWS Console]`

> 💰 Một bucket S3 chứa vài file KB, vài chục request → gần như 0 USD. **Giữ lại** cho v4. Không tạo tài nguyên nào khác.
> Đăng nhập trước: `export AWS_PROFILE=taskhub && aws login` (xem [AWS 06 — AWS CLI](../06-AWS/06-aws-cli.md)), kiểm tra `aws sts get-caller-identity`.

**B1. Viết root module `bootstrap`** trong repo `taskhub`:

```bash
cd ~/projects/taskhub
git switch -c feat/terraform-bootstrap
mkdir -p infra/terraform/bootstrap && cd infra/terraform/bootstrap
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
```

`variables.tf`:

```hcl
variable "project" {
  type    = string
  default = "taskhub"
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "owner" {
  type        = string
  description = "Tên của bạn, dùng cho tag Owner"
}
```

`main.tf`:

```hcl
data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

data "aws_iam_policy_document" "tfstate" {
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
  policy = data.aws_iam_policy_document.tfstate.json

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}
```

`outputs.tf`:

```hcl
output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}
```

`.gitignore` ở thư mục `infra/terraform/` (dùng chung cho mọi root module bên dưới): nội dung như mục 4.3.

❓ Trước khi chạy: giải thích từng resource tương ứng với kiến thức nào ở [AWS 05 — S3](../06-AWS/05-s3.md). Vì sao versioning được bật mà vẫn có lifecycle xóa phiên bản cũ sau 90 ngày?

**B2. Tạo bucket với state local**

```bash
terraform init
terraform fmt -check && terraform validate
terraform plan -var owner=phuong -out=tfplan      # ⚠️ đọc kỹ: chỉ được có resource S3
terraform apply tfplan                            # ⚠️ tạo bucket thật
terraform output -raw state_bucket
```

Kiểm tra bằng CLI (thay tên bucket):

```bash
B=taskhub-tfstate-111122223333
aws s3api get-bucket-versioning --bucket "$B"
aws s3api get-public-access-block --bucket "$B"
aws s3api get-bucket-encryption --bucket "$B"
aws s3api get-bucket-policy --bucket "$B" --query Policy --output text | jq .
```

**B3. Migrate state của chính bootstrap vào bucket**

Tạo `backend.tf` (thay số tài khoản thật — backend không dùng biến được):

```hcl
terraform {
  backend "s3" {
    bucket       = "taskhub-tfstate-111122223333"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

```bash
terraform init -migrate-state                     # trả lời yes khi được hỏi copy state
aws s3 ls "s3://$B/bootstrap/"                    # thấy terraform.tfstate
terraform state list                              # đọc từ S3, vẫn đủ resource
terraform plan -var owner=phuong                  # mong đợi: No changes
```

File `terraform.tfstate` local cũ: đừng xóa ngay. Chuyển nó ra chỗ an toàn ngoài repo (`mv terraform.tfstate ~/tfstate-bootstrap-backup.json`) — sau vài ngày mọi thứ ổn định thì xóa. Nó chứa đúng thông tin như state trên S3.

**B4. Quan sát lock file trên S3**

1. Terminal 1: `terraform apply -var owner=lock-test` — dừng ở câu hỏi `Enter a value:`. (Đổi `owner` để plan có thay đổi tag; với `owner=phuong` plan là *No changes* → `apply` thoát ngay, không hỏi, không giữ khóa. Lát nữa trả lời `no`.)
2. Terminal 2: `aws s3 ls "s3://$B/bootstrap/"` → thấy thêm `terraform.tfstate.tflock`. Rồi `terraform plan -var owner=phuong` → lỗi khóa; đọc `Who`, `Operation`.
3. Terminal 1: gõ `no`. Terminal 2: `aws s3 ls` lại → file `.tflock` đã biến mất.

**B5. Xem phiên bản state**

```bash
aws s3api list-object-versions --bucket "$B" --prefix bootstrap/terraform.tfstate \
  --query 'Versions[].{v:VersionId,latest:IsLatest,at:LastModified,size:Size}' --output table
```

Mỗi lần state đổi sẽ có thêm một phiên bản. Đây là "nút undo" của state.

**B6. Commit**

```bash
cd ~/projects/taskhub
git status                                        # KHÔNG được thấy *.tfstate hay .terraform/
git add infra/terraform/.gitignore infra/terraform/bootstrap
git commit -m "feat(infra): add terraform bootstrap for S3 state bucket"
git push -u origin feat/terraform-bootstrap       # mở PR như mọi thay đổi khác
```

`.terraform.lock.hcl` phải có trong commit.

**Dọn dẹp Phần B**

- **Giữ lại** bucket state — v4 dùng (`key = envs/dev/terraform.tfstate`). Chạy `~/devops-lab/06-aws/find-leftovers.sh`: bucket `taskhub-tfstate-...` sẽ xuất hiện trong danh sách tag `Project=taskhub` — đó là tài nguyên **có chủ đích**.
- ⚠️ Chỉ khi bỏ hẳn dự án mới xóa, theo thứ tự: (1) xóa `backend.tf`, `terraform init -migrate-state` để kéo state về local; (2) bỏ `prevent_destroy`; (3) xóa **mọi phiên bản** object trong bucket (bucket có versioning không xóa được khi còn version — xem lệnh xóa toàn bộ phiên bản ở [AWS 05](../06-AWS/05-s3.md)); (4) `terraform destroy`. Xóa bucket state khi còn root module khác dùng nó = mất state của root module đó.

---

## 10. Kết quả mong đợi

| Bước | Dấu hiệu đúng |
|---|---|
| A2 | `state list` có 2 địa chỉ; `jq` đọc được `serial`, `lineage`. `apply` báo *No changes* nhưng `serial` vẫn tăng 1 — giải thích được vì sao (apply luôn ghi lại state; `plan` thì không) |
| A3 | Terminal 2 báo `Error acquiring the state lock`, có `Operation: OperationTypeApply`; file `.lock.info` biến mất sau khi trả lời `no` |
| A4 | `terraform output` hiện `<sensitive>`, `jq` in ra mật khẩu rõ; sau khi đổi sang ephemeral, `grep` không còn thấy `random_password` |
| A5 | Không có `moved`: `1 to add, 1 to destroy`. Có `moved`: `0 to add, 0 to change, 0 to destroy` và dòng `has moved to` |
| A6 | `1 to import`; sau apply `state show docker_volume.data` có `name = "tf07-state-data"`; `generated.tf` được tạo và chỉnh xong không còn lỗi |
| A7 | `plan -refresh-only` báo `has been deleted`; `plan` báo `1 to add`; sau apply `curl` trả `200` |
| A8 | Plan báo `will no longer be managed`, `0 to destroy`; volume vẫn còn trong `docker volume ls` |
| B2 | `Plan: 6 to add` (bucket, versioning, SSE, public access block, lifecycle, policy — data source không tính); 4 lệnh `get-*` đều trả cấu hình đúng |
| B3 | `aws s3 ls` thấy `bootstrap/terraform.tfstate`; `plan` → `No changes` |
| B4 | `.tflock` xuất hiện khi đang chờ `yes` và biến mất sau `no` |
| B5 | Có ≥ 2 phiên bản object state |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `Error acquiring the state lock` | Lệnh khác đang giữ khóa (terminal khác, CI) | Đọc `Who`/`Created`; chờ hoặc dùng `-lock-timeout=5m`. Chỉ `force-unlock` khóa của chính mình bị kẹt |
| Apply xong nhưng lần sau vẫn báo khóa, `Who` là chính mình | Thiếu `s3:DeleteObject` trên `*.tflock` hoặc tiến trình bị kill giữa chừng | Bổ sung quyền; `force-unlock` một lần |
| `Error: Variables not allowed` trong block `backend` | Dùng `var.*` hoặc `local.*` trong backend | Ghi giá trị cố định, hoặc partial config `-backend-config` |
| `Backend configuration changed` / `Backend initialization required` | Sửa block backend mà chưa init lại | `terraform init -migrate-state` (mang state theo) hoặc `-reconfigure` (không mang) — hiểu rõ trước khi chọn |
| Sau khi migrate, `plan` muốn **tạo lại toàn bộ** | Đã trả lời `no` khi được hỏi copy state, hoặc sai `key`/`bucket` | Kiểm tra `aws s3 ls`; state local cũ vẫn còn → migrate lại đúng. **Không apply** |
| `BucketAlreadyExists` | Tên bucket là toàn cầu và đã có người dùng | Tên có số tài khoản (như bài) gần như không trùng; kiểm tra lại `locals` |
| `Error: Instance cannot be destroyed` khi `destroy` bootstrap | `prevent_destroy = true` đang làm đúng việc | Xem quy trình dọn dẹp ở cuối Phần B |
| Import xong nhưng plan đòi `forces replacement` | Code không khớp object thật | Đọc thuộc tính bị đánh dấu, sửa code cho khớp; không apply khi còn destroy |
| `-generate-config-out` báo file đã tồn tại | File đích phải là file mới | Xóa/đổi tên file cũ |
| `Cannot connect to the Docker daemon` (Phần A) | WSL Integration của Docker Desktop đang tắt | Bật trong Docker Desktop (Settings → Resources → WSL integration) |
| Đổi tên resource → plan `1 to destroy` | Quên `moved` | Thêm `moved {}`; plan lại |

---

## 12. Đọc log và xử lý lỗi

**Bật log chi tiết** khi thông báo lỗi không đủ:

```bash
TF_LOG=DEBUG TF_LOG_PATH=/tmp/tf-debug.log terraform plan
grep -nE 'ERROR|WARN|lock|s3' /tmp/tf-debug.log | tail -40
```

- `TF_LOG`: `TRACE` > `DEBUG` > `INFO` > `WARN` > `ERROR`. `DEBUG` thường đủ.
- `TF_LOG_PATH`: ghi ra file thay vì làm ngập terminal.
- ⚠️ Log `TRACE`/`DEBUG` có thể chứa header request, giá trị thuộc tính → không dán nguyên văn lên mạng; xóa file khi xong.

**Đọc lỗi backend S3** — tìm ba thứ:

1. **Mã HTTP / mã lỗi S3**: `403 AccessDenied` → quyền IAM (kiểm tra bảng ở mục 4.4); `404 NoSuchBucket` → sai tên bucket hoặc sai `region`; `412 PreconditionFailed` khi ghi `.tflock` → có người đang giữ khóa.
2. **Object nào**: `.tflock` hay `terraform.tfstate` — thiếu quyền ở object nào thì sửa đúng statement đó.
3. **Danh tính đang dùng**: `aws sts get-caller-identity` — rất hay gặp trường hợp quên `export AWS_PROFILE=taskhub` hoặc phiên `aws login` hết hạn (`ExpiredToken`).

**Ghi vào nhật ký debug** mỗi lần gặp lỗi khóa hoặc drift: ai giữ khóa, vì sao, bạn đã làm gì — theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Nêu bốn lý do Terraform cần state. Nếu xóa state, chuyện gì xảy ra ở lần `apply` tiếp theo?
2. `serial` và `lineage` trong state dùng để làm gì?
3. Biến có `sensitive = true` có xuất hiện trong state không? Ephemeral resource và write-only argument khác `sensitive` ở điểm nào?
4. Vì sao write-only argument luôn đi kèm một thuộc tính `..._wo_version`? Muốn đổi mật khẩu đã lưu bằng `value_wo`, bạn làm gì?
5. Vì sao không dùng được `var.*` trong block `backend`? Có cách nào tránh ghi cứng không?
6. Liệt kê quyền IAM tối thiểu cho S3 backend có `use_lockfile`. Vì sao lock file cần `s3:DeleteObject` còn state file thì không?
7. Khóa bằng DynamoDB hiện có trạng thái gì theo tài liệu HashiCorp? Bạn sẽ nói gì nếu một tutorial bảo tạo bảng DynamoDB?
8. Giải thích bài toán "con gà – quả trứng" của bucket state và cách dự án giải quyết. Hệ quả của việc state bootstrap nằm trong chính bucket nó tạo là gì?
9. Khi nào được phép dùng `terraform force-unlock`? Rủi ro nếu dùng sai?
10. So sánh `moved {}` với `terraform state mv`. Vì sao block tốt hơn trong làm việc nhóm?
11. Xóa một resource khỏi code và dùng `removed { lifecycle { destroy = false } }` khác nhau thế nào?
12. `import {}` gồm những phần nào? Làm sao biết import ID của một loại resource? Mục tiêu của `plan` sau import là gì?
13. `plan -refresh-only`, `apply -refresh-only` và `apply` thường khác nhau thế nào khi có drift?
14. Vì sao HashiCorp khuyên chia sẻ dữ liệu qua nơi riêng (ví dụ SSM Parameter Store) thay vì `terraform_remote_state`?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Đọc state bằng `jq`.** Với state của Phần A, viết một lệnh `jq` in ra bảng `địa_chỉ → id` cho mọi resource `managed`. Sau đó viết lệnh tương tự dùng `terraform show -json` (không đọc file trực tiếp). Vì sao cách thứ hai tốt hơn khi state nằm trên S3?

**Bài 2 — Chuyển resource vào `for_each` không mất gì.** Trong `state-lab`, thay container đơn `docker_container.frontend` bằng `docker_container.site` dùng `for_each = toset(["blue"])` (container `blue` giữ nguyên tên `tf07-state-web` và cổng). Viết `moved` block để plan ra `0 to destroy`. Địa chỉ đích viết thế nào? Trong shell, cần đặt địa chỉ đó trong dấu nháy gì khi dùng với `terraform state show`?

**Bài 3 — Quyền IAM cho người chỉ được `plan`.** Viết một IAM policy JSON cho role "chỉ được chạy `terraform plan`" trên `envs/dev` của bucket state (đọc state, **được** tạo/xóa lock file vì `plan` cũng khóa — kiểm tra lại điều này trong tài liệu, không được ghi state). Kiểm tra cú pháp bằng Policy Simulator (0 USD), không cần gắn vào ai.

**Bài 4 — Khôi phục state từ phiên bản cũ (giấy bút + lệnh đọc).** Viết runbook từng bước (lệnh cụ thể) cho tình huống: "state `envs/dev` trên S3 bị một script lỗi ghi đè bằng state rỗng 10 phút trước". Chỉ được chạy các lệnh **đọc** (`list-object-versions`, `get-object` ra file tạm) trên bucket bootstrap để thử; phần `state push` chỉ viết ra, không chạy.

**Bài 5 — Drift có chủ đích.** Trong `state-lab`, đổi cổng container bằng cách xóa tay rồi `docker run` lại container cùng tên với cổng 18085. Chạy `plan -refresh-only` và `plan`. Terraform phản ứng thế nào khi một container **cùng tên** nhưng **khác ID** đang tồn tại? Viết một mục nhật ký debug cho sự cố này.

**Bài 6 — So sánh hai cách bootstrap.** Viết một ADR ngắn (theo [mẫu ở README dự án](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr)) so sánh: (a) tạo bucket state bằng Terraform `bootstrap/` + migrate state vào chính nó; (b) tạo bucket bằng AWS CLI và không quản lý bằng code. Có số liệu (thời gian, rủi ro) và hệ quả tiêu cực của lựa chọn bạn chọn.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được state bằng lời của mình và chỉ ra được `serial`, `lineage`, `attributes` trong file thật.
- [ ] Chứng minh được (bằng lệnh `jq`) secret nằm trong state, và nói được ephemeral + `value_wo` giải quyết thế nào.
- [ ] Viết được block `backend "s3"` có `use_lockfile` mà không nhìn bài, kể đủ quyền IAM.
- [ ] Dựng xong bucket state bằng `bootstrap/`, migrate state vào S3, thấy được file `.tflock` xuất hiện/biến mất.
- [ ] Đổi tên, import, thôi quản lý resource bằng block mà plan không có destroy ngoài ý muốn.
- [ ] Phát hiện và xử lý drift theo đúng quy trình "hiểu nguyên nhân trước, quyết định sau".
- [ ] Biết khi nào **không** được dùng `force-unlock`, `state push`, `-lock=false`.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Terraform — Purpose of state](https://developer.hashicorp.com/terraform/language/state/purpose) | Bốn lý do state tồn tại | 2026-10-31 |
| [Terraform — Sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data) | Secret trong state, khuyến nghị bảo vệ | 2026-10-31 |
| [Terraform — Ephemeral values / write-only](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral) | `ephemeral`, write-only argument, ví dụ `random_password` + `password_wo` | 2026-10-31 |
| [HashiCorp blog — Terraform 1.10 ephemeral values](https://hashicorp.com/en/blog/terraform-1-10-improves-handling-secrets-in-state-with-ephemeral-values) | Phiên bản có ephemeral | 2026-10-31 |
| [HashiCorp blog — Terraform 1.11 write-only arguments](https://hashicorp.com/blog/terraform-1-11-ephemeral-values-managed-resources-write-only-arguments) | Phiên bản có write-only | 2026-10-31 |
| [AWS provider — `aws_ssm_parameter` (`value_wo`)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | `value_wo`, `value_wo_version` | 2026-10-31 |
| [terraform-provider-random releases](https://github.com/hashicorp/terraform-provider-random/releases) | Ephemeral `random_password` từ v3.7.0 | 2026-10-31 |
| [Terraform — S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3) | `use_lockfile`, DynamoDB deprecated, quyền IAM, versioning, `encrypt` | 2026-10-31 |
| [Terraform — State locking](https://developer.hashicorp.com/terraform/language/state/locking) | Cảnh báo `force-unlock` | 2026-10-31 |
| [Terraform CLI — `force-unlock`](https://developer.hashicorp.com/terraform/cli/commands/force-unlock) | Cú pháp, `-force` | 2026-10-31 |
| [Terraform — Refactoring với `moved`](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring) | `moved` (≥ 1.1), giữ block cũ | 2026-10-31 |
| [Terraform — `removed` block](https://developer.hashicorp.com/terraform/language/block/removed) | `lifecycle { destroy = false }` | 2026-10-31 |
| [Terraform v1.7 — Removing resources](https://developer.hashicorp.com/terraform/language/v1.7.x/resources/syntax#removing-resources) | `removed` có từ 1.7 | 2026-10-31 |
| [Terraform — `import` block](https://developer.hashicorp.com/terraform/language/block/import) | `to`, `id`, `for_each` | 2026-10-31 |
| [Terraform — Generating configuration](https://developer.hashicorp.com/terraform/language/import/generating-configuration) | `-generate-config-out`, tính thử nghiệm | 2026-10-31 |
| [Terraform — Remote state data source](https://developer.hashicorp.com/terraform/language/state/remote-state-data) | Khuyến nghị chia sẻ dữ liệu qua nơi riêng | 2026-10-31 |
| [Docker provider — `docker_container`](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) · [`docker_volume`](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/volume) | Resource Docker, import ID | 2026-10-31 |
| [AWS 05 — S3](../06-AWS/05-s3.md) | Versioning, BPA, bucket policy, xóa mọi phiên bản | — |
