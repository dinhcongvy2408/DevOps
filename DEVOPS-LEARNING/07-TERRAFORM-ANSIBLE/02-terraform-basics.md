# 02. Terraform cơ bản

> ⏱️ ~5 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. IaC là gì](01-iac-concepts.md), [Docker 04 — Volume, network](../04-DOCKER/04-volumes-networks-env.md), [AWS 03 — VPC](../06-AWS/03-vpc-networking.md), [AWS 04 — EC2](../06-AWS/04-ec2.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL Integration) · `[AWS Console]` chỉ để đối chiếu · Phiên bản khi viết: Terraform **1.17.1**, provider `kreuzwerker/docker` **4.6.0**, `hashicorp/local` **2.9.1**, `hashicorp/aws` **6.71.0** (kiểm tra 2026-10-31)

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ luồng hoạt động](#6-sơ-đồ-luồng-hoạt-động)
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

- Cài Terraform trên WSL từ kho apt chính thức của HashiCorp và kiểm tra đúng phiên bản.
- Đọc và viết **HCL**: block, argument, expression, tham chiếu giữa các resource.
- Giải thích **provider**, **resource**, **data source**, **variable**, **output**, **locals** và vai trò của file `.terraform.lock.hcl`.
- Chọn đúng giữa `count` và `for_each`, biết khi nào cần `depends_on` và các tùy chọn `lifecycle`.
- Chạy vòng làm việc `init → fmt → validate → plan → apply → destroy` và **đọc plan** chính xác: `+`, `-`, `~`, `-/+`, `<=`.
- Dùng `terraform console`, `terraform state list/show`, `terraform graph` để hiểu chuyện gì đang diễn ra.
- Dịch cùng một ý tưởng từ provider Docker (miễn phí, chạy trên máy) sang provider AWS.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần |
|---|---|
| "Dựng lại môi trường dev giống hệt tuần trước" | Hạ tầng mô tả bằng code → `terraform apply` ra đúng kết quả, không phụ thuộc trí nhớ |
| Ai đó sửa Security Group bằng tay trên console | `terraform plan` chỉ ra **drift** (lệch giữa code và thực tế) |
| Review thay đổi hạ tầng trong Pull Request | Đọc **plan**: thay đổi này sửa tại chỗ hay **xóa rồi tạo lại** EC2? |
| Hết giờ học, tắt toàn bộ AWS cho khỏi tốn credit | `terraform destroy` — một lệnh, không sót tài nguyên |
| Phỏng vấn: "`count` và `for_each` khác gì?", "State là gì?" | Hiểu bản chất, không chỉ nhớ cú pháp |

Ở v2/v3 bạn đã dựng VPC, SG, IAM, EC2 bằng tay — rất nhiều lần bấm, rất dễ quên một bước. Terraform biến toàn bộ danh sách đó thành file văn bản nằm trong Git: review được, lặp lại được, xóa được.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Terraform làm gì, nói ngắn gọn

**Terraform** đọc các file `.tf` mô tả **trạng thái mong muốn** (desired state), so sánh với **state** (bản ghi những gì nó đã tạo) và với **thực tế** (gọi API để đọc), rồi tính ra danh sách thao tác cần làm để thực tế khớp với mong muốn. Đây là cách làm **khai báo** (declarative) đã học ở [bài 01](01-iac-concepts.md): bạn nói *cái gì*, Terraform tự tính *làm thế nào*.

Terraform không tự biết AWS hay Docker. Nó dùng **provider** — plugin dịch "resource `aws_instance`" thành lời gọi API EC2, "resource `docker_container`" thành lời gọi Docker API.

### 3.2. Năm khái niệm cốt lõi

| Khái niệm | Nghĩa tiếng Việt | Ví dụ |
|---|---|---|
| **Provider** | Trình cung cấp | `kreuzwerker/docker`, `hashicorp/aws` |
| **Resource** | Tài nguyên được quản lý | `docker_container.web`, `aws_instance.app` — Terraform tạo/sửa/xóa |
| **Data source** | Nguồn dữ liệu chỉ đọc | `data.aws_ssm_parameter.ubuntu_ami` — đọc thông tin có sẵn, **không** tạo gì |
| **State** | Trạng thái đã ghi nhận | File `terraform.tfstate`: resource trong code ↔ ID thật bên ngoài |
| **Plan** | Kế hoạch | Danh sách thay đổi Terraform **sẽ** làm — đọc trước khi `apply` |

### 3.3. Ôn lại: nối với kiến thức cũ

| Đã học | Gặp lại trong Terraform |
|---|---|
| `docker network create`, `docker run -p -v` ([Docker 04](../04-DOCKER/04-volumes-networks-env.md)) | Resource `docker_network`, `docker_container` với block `ports`, `volumes` |
| Compose file mô tả trạng thái mong muốn ([Docker 05](../04-DOCKER/05-docker-compose.md)) | Cùng tư tưởng khai báo, nhưng Terraform có **state** và quản lý được cả hạ tầng cloud |
| Tag `Project=taskhub` ([AWS 00](../06-AWS/00-aws-account-setup-cost-safety.md)) | `default_tags` trong provider AWS — gắn tag cho mọi resource |
| AMI Ubuntu qua SSM public parameter ([AWS 04](../06-AWS/04-ec2.md)) | `data "aws_ssm_parameter"` |
| Biến môi trường, exit code ([Linux 06](../01-LINUX/06-bash-scripting.md)) | `TF_VAR_name`, `terraform plan -detailed-exitcode` |

> 📌 **Giấy phép:** từ bản 1.6 (8/2023), Terraform dùng giấy phép **BSL 1.1** thay cho MPL. Cộng đồng tạo bản fork mã nguồn mở **OpenTofu** (thuộc Linux Foundation), cú pháp gần như giống hệt. Học Terraform thì dùng được OpenTofu và ngược lại. Giáo trình dùng Terraform vì phổ biến hơn trong tin tuyển dụng; chi tiết so sánh ở [bài 01](01-iac-concepts.md).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cài Terraform trên WSL Ubuntu 24.04

Dùng kho apt chính thức của HashiCorp (theo trang [Install Terraform](https://developer.hashicorp.com/terraform/install)). Cài qua kho apt nghĩa là `apt upgrade` sẽ cập nhật Terraform cùng các gói khác.

`[WSL]`

```bash
# Công cụ cần cho bước thêm kho (thường đã có sẵn)
sudo apt update && sudo apt install -y gnupg wget lsb-release

# 1. Tải khóa ký của HashiCorp, chuyển sang định dạng apt đọc được
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 2. Thêm kho, chỉ tin các gói ký bằng khóa trên
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# 3. Cài
sudo apt update && sudo apt install -y terraform

terraform version
```

```text
Terraform v1.17.1
on linux_amd64
```

(Minh họa — khi bạn cài, phiên bản có thể mới hơn. Code trong giáo trình đòi `~> 1.17`, nghĩa là mọi bản 1.x từ 1.17 trở lên đều chạy được.)

Bật gợi ý lệnh bằng phím Tab (ghi thêm vài dòng vào `~/.bashrc`, mở terminal mới để có hiệu lực):

```bash
terraform -install-autocomplete
```

> ⚠️ Đừng tải file nhị phân từ trang lạ hay blog. Kho apt có chữ ký GPG — `apt` từ chối gói không khớp khóa. Đây là cùng nguyên tắc với kho Docker ở [Docker 01](../04-DOCKER/01-vm-vs-container-architecture.md).

### 4.2. 🟥 HCL: block, argument, expression

Terraform dùng ngôn ngữ **HCL** (HashiCorp Configuration Language). Mọi thứ là **block**:

```hcl
resource "docker_container" "web" {   # <loại block> "<kiểu resource>" "<tên cục bộ>" {
  name  = "tf07-web"                  # argument = expression
  image = docker_image.nginx.image_id # tham chiếu: <kiểu>.<tên>.<thuộc tính>

  ports {                             # block lồng nhau (nested block)
    internal = 80
    external = 8081
  }
}
```

| Thành phần | Ý nghĩa |
|---|---|
| `resource` | Loại block. Các loại khác: `terraform`, `provider`, `variable`, `output`, `locals`, `data`, `module` |
| `"docker_container"` | **Kiểu** resource — tiền tố `docker_` cho biết provider nào xử lý |
| `"web"` | **Tên cục bộ** — chỉ có ý nghĩa trong code. Địa chỉ đầy đủ: `docker_container.web` |
| `name = "tf07-web"` | Tên **thật** của container trên Docker — khác tên cục bộ |
| `docker_image.nginx.image_id` | Tham chiếu tới thuộc tính của resource khác → Terraform tự hiểu phải tạo image **trước** container |

Kiểu dữ liệu: `string`, `number`, `bool`, `list(...)`, `set(...)`, `map(...)`, `object({...})`, `tuple([...])`.

Một số expression hay dùng:

```hcl
"${var.project}-web"                      # nội suy chuỗi (string interpolation)
var.env == "prod" ? "t3.small" : "t3.micro" # toán tử điều kiện
[for s in var.subnets : s.cidr]           # biểu thức for → list
{ for k, v in var.sites : k => v.port }   # biểu thức for → map
upper("abc"), length(var.list), merge(a, b), cidrsubnet("10.20.0.0/16", 8, 1)  # hàm có sẵn
```

Thử ngay bằng `terraform console` (mục 8).

Terraform đọc **mọi file `.tf` trong thư mục hiện tại** như một khối duy nhất — tên file chỉ để con người dễ tìm. Quy ước phổ biến:

| File | Chứa |
|---|---|
| `versions.tf` | Block `terraform {}`: phiên bản Terraform, provider |
| `main.tf` | Resource, data source |
| `variables.tf` | Block `variable` |
| `outputs.tf` | Block `output` |
| `terraform.tfvars` | Giá trị cho biến (không phải code) |

### 4.3. 🟥 Provider, registry và ràng buộc phiên bản

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"   # <namespace>/<tên> trên registry.terraform.io
      version = "~> 4.6"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock" # socket Docker trong WSL
}
```

Toán tử phiên bản:

| Viết | Nghĩa | Ví dụ khớp |
|---|---|---|
| `= 4.6.0` | Đúng bản này | chỉ 4.6.0 |
| `>= 4.6` | Từ 4.6 trở lên | 4.6, 5.0, 9.9… (nguy hiểm: nhận cả bản major mới có thể phá vỡ) |
| `~> 4.6` | Từ 4.6, **dưới 5.0** | 4.6, 4.7, 4.99 |
| `~> 4.6.0` | Từ 4.6.0, **dưới 4.7** | 4.6.0, 4.6.5 |
| `>= 1.17, < 2.0` | Kết hợp | |

`~>` ("pessimistic constraint") là lựa chọn phổ biến: nhận bản vá và tính năng mới, chặn bản major — đúng tinh thần **SemVer** ở [Git 05](../03-GIT/05-tags-releases-versioning.md).

**`.terraform.lock.hcl`** — `terraform init` ghi lại **đúng phiên bản và hash** của provider đã tải. Lần sau, máy khác hay CI chạy `init` sẽ dùng **đúng bản đó** dù registry đã có bản mới hơn. Giống `package-lock.json`, hay việc ghim SHA action ở [CI/CD 04](../05-CICD/04-secrets-environments.md).

| File/thư mục | Commit vào Git? | Vì sao |
|---|---|---|
| `.terraform.lock.hcl` | ✅ **Có** | Mọi người, mọi máy dùng cùng phiên bản provider |
| `.terraform/` | ❌ Không | Provider đã tải (hàng chục–hàng trăm MB), tạo lại bằng `init` |
| `terraform.tfstate`, `*.tfstate.backup` | ❌ **Không bao giờ** | Có thể chứa dữ liệu nhạy cảm; dùng remote backend ([bài 03](03-terraform-state-backend.md)) |
| `*.tfplan` | ❌ Không | Chứa toàn bộ cấu hình và giá trị biến |
| `terraform.tfvars` | Tùy | Không chứa secret thì commit được |

Nâng phiên bản provider có chủ đích: `terraform init -upgrade` → xem diff của `.terraform.lock.hcl` trong PR.

### 4.4. 🟥 Resource và data source

**Resource** = thứ Terraform **sở hữu**: tạo, sửa, xóa.

**Data source** = thứ Terraform chỉ **đọc**: đã tồn tại, do ai đó khác quản lý.

```hcl
# Docker: đọc thông tin một network có sẵn (ví dụ network "bridge" mặc định)
data "docker_network" "bridge" {
  name = "bridge"
}

# AWS: đọc ID AMI Ubuntu 24.04 mới nhất mà Canonical công bố
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "app" {
  ami           = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type = "t3.small"
}
```

Data source dùng tiền tố `data.` khi tham chiếu. Trong plan, data source được đọc hiện với ký hiệu `<=`.

> 💡 Vì sao tốt hơn ghi cứng `ami = "ami-0abc..."`? ID AMI khác nhau theo region và đổi mỗi lần Canonical vá lỗi. Data source luôn lấy bản mới nhất. Mặt trái: AMI đổi → `aws_instance` bị **thay thế** ở lần `apply` sau (xem `ignore_changes` ở mục 4.9).

### 4.5. 🟥 Variable, output, locals

**Variable** — tham số đầu vào của cấu hình:

```hcl
variable "base_port" {
  description = "Cổng đầu tiên publish ra host"
  type        = number
  default     = 8081

  validation {
    condition     = var.base_port >= 1024 && var.base_port <= 65000
    error_message = "base_port phải trong khoảng 1024–65000 (không dùng cổng đặc quyền)."
  }
}

variable "db_password" {
  type      = string
  sensitive = true   # ẩn khỏi output của CLI — NHƯNG vẫn nằm trong state
}
```

Cách truyền giá trị, theo tài liệu Terraform, **ưu tiên từ cao xuống thấp**:

| Ưu tiên | Nguồn | Ví dụ |
|---|---|---|
| 1 (cao nhất) | `-var` / `-var-file` trên dòng lệnh (theo thứ tự viết) | `terraform plan -var base_port=9090` |
| 2 | `*.auto.tfvars` (theo thứ tự tên file) | `dev.auto.tfvars` |
| 3 | `terraform.tfvars.json` | |
| 4 | `terraform.tfvars` | `base_port = 9090` |
| 5 | Biến môi trường `TF_VAR_<tên>` | `export TF_VAR_base_port=9090` |
| 6 (thấp nhất) | `default` trong block `variable` | |

Không có giá trị từ nguồn nào và không có `default` → Terraform hỏi bạn khi chạy (không dùng được trong CI).

**`sensitive` không có nghĩa là bí mật tuyệt đối.** Tài liệu Terraform ghi rõ: Terraform **vẫn lưu giá trị biến sensitive trong state**. `sensitive` chỉ ẩn khỏi màn hình.

🟨 **`ephemeral = true`** (Terraform 1.10+): giá trị **không** được ghi vào state và file plan. Đổi lại, nó chỉ được dùng ở những chỗ "tạm thời" — ví dụ **write-only argument** như `value_wo` của `aws_ssm_parameter`. Đây là cách v4 đưa mật khẩu PostgreSQL vào Parameter Store mà **không** để lại dấu vết trong state ([bài 03](03-terraform-state-backend.md) giải thích kỹ vì sao state là tài sản nhạy cảm).

**Output** — giá trị in ra sau `apply`, và là "đầu ra" để module khác hoặc script dùng:

```hcl
output "urls" {
  description = "URL của từng site"
  value       = { for k, c in docker_container.web : k => "http://localhost:${c.ports[0].external}" }
}
```

```bash
terraform output              # mọi output
terraform output -json urls   # dạng JSON — dùng trong script với jq
terraform output -raw app_url # chuỗi thuần, không có dấu nháy
```

**Locals** — biến nội bộ, tránh lặp lại biểu thức:

```hcl
locals {
  name_prefix = "${var.project}-${var.env}"   # "taskhub-dev"
  common_labels = {
    project = var.project
    managed = "terraform"
  }
}
# dùng: local.name_prefix  (chú ý: khai báo "locals", tham chiếu "local.")
```

| | `variable` | `locals` |
|---|---|---|
| Ai đặt giá trị? | Người chạy Terraform (tfvars, `-var`, env) | Chính code |
| Dùng khi | Thứ thay đổi theo môi trường | Biểu thức tính toán, đặt tên chung |

### 4.6. 🟥 `count` và `for_each`

Cả hai tạo **nhiều bản** của một resource. Khác biệt nằm ở **cách đặt tên từng bản** trong state.

```hcl
# count: bản sao được đánh số 0, 1, 2…
variable "names" { default = ["blue", "green", "red"] }

resource "docker_container" "c" {
  count = length(var.names)
  name  = "tf07-${var.names[count.index]}"
  image = docker_image.nginx.image_id
}
# Địa chỉ: docker_container.c[0], c[1], c[2]
```

```hcl
# for_each: bản sao được đặt tên theo KEY
variable "sites" {
  default = {
    blue  = { port = 8081 }
    green = { port = 8082 }
    red   = { port = 8083 }
  }
}

resource "docker_container" "s" {
  for_each = var.sites
  name     = "tf07-${each.key}"
  image    = docker_image.nginx.image_id
  ports {
    internal = 80
    external = each.value.port
  }
}
# Địa chỉ: docker_container.s["blue"], s["green"], s["red"]
```

**Thí nghiệm tư duy — xóa phần tử ở giữa:**

| | Trước | Xóa `"green"` | Terraform làm gì |
|---|---|---|---|
| `count` | `c[0]=blue`, `c[1]=green`, `c[2]=red` | list còn `["blue","red"]` → `c[1]` giờ là `red`, `c[2]` thừa | **Sửa/thay thế `c[1]`** từ green → red, **xóa `c[2]`** (container red cũ). Container `red` bị phá đi tạo lại vô cớ |
| `for_each` | `s["blue"]`, `s["green"]`, `s["red"]` | map còn `blue`, `red` | **Chỉ xóa `s["green"]`**. Hai cái còn lại không bị đụng |

Với một nhóm EC2 hay subnet thật, "phá đi tạo lại vô cớ" là sự cố. Quy tắc:

- `for_each` với **map hoặc set chuỗi** — khi các bản sao có danh tính riêng (subnet `public-a`, `public-b`; site `blue`, `green`).
- `count` — khi các bản sao giống hệt và chỉ cần **số lượng**, hoặc để bật/tắt một resource: `count = var.enable_alarm ? 1 : 0`.

⚠️ Key của `for_each` phải **biết được lúc plan** — không dùng thuộc tính chỉ có sau khi tạo (như ID) làm key.

### 4.7. 🟥 Phụ thuộc: ngầm định và `depends_on`

Terraform xây **đồ thị phụ thuộc** (dependency graph) từ các tham chiếu:

```hcl
resource "docker_container" "web" {
  image = docker_image.nginx.image_id   # tham chiếu → container phụ thuộc image
  networks_advanced {
    name = docker_network.this.name     # tham chiếu → phụ thuộc network
  }
}
```

Nhờ vậy Terraform tự biết: tạo network và image trước, container sau; khi `destroy` thì ngược lại. Những resource không phụ thuộc nhau được tạo **song song** (mặc định 10 thao tác cùng lúc, đổi bằng `-parallelism=N`).

`depends_on` chỉ dùng khi phụ thuộc **không thể hiện qua tham chiếu**:

```hcl
resource "aws_instance" "app" {
  # ...
  iam_instance_profile = aws_iam_instance_profile.app.name
  # User data gọi SSM Parameter Store lúc boot — cần policy đã gắn vào role,
  # nhưng code không tham chiếu tới policy attachment nào:
  depends_on = [aws_iam_role_policy_attachment.ssm_core]
}
```

Lạm dụng `depends_on` làm plan kém chính xác và chậm hơn. Ưu tiên tham chiếu trực tiếp.

### 4.8. 🟥 Vòng làm việc: init → fmt → validate → plan → apply → destroy

| Lệnh | Làm gì | Gọi API thật? | Thay đổi gì? |
|---|---|---|---|
| `terraform init` | Tải provider, module; cấu hình backend; tạo/đọc `.terraform.lock.hcl` | Registry | Thư mục `.terraform/` |
| `terraform fmt` | Định dạng code theo chuẩn (2 dấu cách, căn `=`) | Không | File `.tf` |
| `terraform validate` | Kiểm tra cú pháp, kiểu, tham chiếu | Không | Không |
| `terraform plan` | Đọc thực tế + state, tính thay đổi | **Có (chỉ đọc)** | Không (trừ khi `-out`) |
| `terraform apply` | Plan + hỏi xác nhận + thực hiện | **Có (ghi)** | Hạ tầng thật + state |
| `terraform destroy` | Xóa mọi thứ trong state | **Có (xóa)** | Hạ tầng thật + state |

**Đọc plan** — ký hiệu ở đầu mỗi resource:

| Ký hiệu | Nghĩa | Mức độ chú ý |
|---|---|---|
| `+` | create — tạo mới | Bình thường |
| `~` | update in-place — sửa tại chỗ, resource vẫn là nó | Bình thường |
| `-/+` | destroy rồi create — **thay thế** | ⚠️ **Đọc kỹ**: EC2 bị thay = mất dữ liệu trên ổ, đổi IP; database bị thay = **mất dữ liệu** |
| `+/-` | create rồi destroy (khi có `create_before_destroy`) | Thay thế nhưng giảm gián đoạn |
| `-` | destroy — xóa | ⚠️ Đọc kỹ |
| `<=` | read — đọc data source | Thông tin |

Cuối plan luôn có dòng tổng kết:

```text
Plan: 2 to add, 1 to change, 1 to destroy.
```

Trong phần chi tiết của một resource bị thay thế, Terraform đánh dấu **thuộc tính nào gây ra việc thay thế** bằng chú thích `# forces replacement`. Đó là dòng bạn cần tìm đầu tiên.

**Plan lưu ra file** (dùng trong CI và khi muốn chắc chắn "apply đúng cái đã duyệt"):

```bash
terraform plan -out=plan.tfplan     # lưu kế hoạch
terraform show plan.tfplan          # xem lại
terraform apply plan.tfplan         # áp dụng ĐÚNG kế hoạch đó, không hỏi lại
```

Nếu thực tế hoặc state thay đổi sau khi lưu plan, `apply plan.tfplan` từ chối chạy (plan đã cũ — "stale"). Theo tài liệu, file plan chứa toàn bộ cấu hình và giá trị biến → coi là **nhạy cảm**.

### 4.9. 🟨 `lifecycle`: điều chỉnh cách Terraform thay đổi resource

```hcl
resource "docker_volume" "data" {
  name = "tf07-data"
  lifecycle {
    prevent_destroy = true   # plan nào định xóa resource này → BÁO LỖI, dừng
  }
}

resource "aws_instance" "app" {
  # ...
  lifecycle {
    create_before_destroy = true   # khi phải thay: tạo bản mới trước, xóa bản cũ sau
    ignore_changes        = [ami]  # AMI mới ra cũng không thay máy; muốn đổi thì chủ động
  }
}
```

| Tùy chọn | Dùng khi | Bẫy |
|---|---|---|
| `prevent_destroy` | Database, bucket chứa backup, state bucket | Chặn cả `terraform destroy` — muốn xóa thật phải sửa code trước. Không bảo vệ khi bạn **xóa block resource** khỏi code |
| `create_before_destroy` | Muốn thay thế không gián đoạn | Hai bản tồn tại cùng lúc → tên phải không trùng (nhiều resource yêu cầu tên duy nhất) |
| `ignore_changes` | Thuộc tính bị hệ thống khác thay đổi hợp lệ, hoặc không muốn thay thế vì giá trị trôi | Che giấu drift — dùng có chủ đích, ghi chú lý do |

Với `docker_container`, phần lớn thuộc tính buộc tạo lại container (Docker không cho sửa cấu hình container đang tồn tại). Theo schema provider 4.6: `image`, `ports`, `volumes`, `labels`, `name` → **thay thế**; `restart`, `memory`, `cpu_shares` → **sửa tại chỗ**. Bạn sẽ quan sát cả hai trong lab.

### 4.10. 🟥 State: cái nhìn đầu tiên

Sau `apply`, thư mục có file `terraform.tfstate` (JSON). Nó ghi: resource `docker_container.web["blue"]` trong code ↔ container ID `3f2a…` trên Docker, cùng mọi thuộc tính đã biết.

```bash
terraform state list                              # liệt kê địa chỉ resource trong state
terraform state show 'docker_container.web["blue"]'  # thuộc tính của một resource
```

Ba thứ Terraform so sánh khi `plan`:

```text
   CODE (.tf)            STATE (tfstate)           THỰC TẾ (Docker/AWS API)
 mong muốn là gì    ←→   lần trước đã tạo gì   ←→   bây giờ đang có gì
```

Mặc định `plan` **làm mới** (refresh) state bằng cách đọc thực tế trước, rồi mới so với code. Nếu có ai xóa container bằng tay, plan sẽ đề xuất tạo lại (`+`). Nếu có ai sửa thứ Terraform quản lý, plan đề xuất đưa về như code. Đó là **drift** — chủ đề chính của [bài 03](03-terraform-state-backend.md) và break-fix của module.

⚠️ **Không sửa tay file `terraform.tfstate`.** Dùng các lệnh `terraform state ...` và `import`/`removed` (bài 03).

### 4.11. 🟨 `terraform console` và `terraform graph`

`terraform console` — REPL để thử expression với biến và state thật:

```text
> var.base_port + 1
8082
> cidrsubnet("10.20.0.0/16", 8, 11)
"10.20.11.0/24"
> { for k, v in var.sites : k => v.port_offset }
{
  "blue" = 0
  "green" = 1
}
```

`terraform graph` in đồ thị phụ thuộc dạng DOT. Không cần cài Graphviz để học: đọc văn bản là đủ thấy cạnh `A -> B`. Có Graphviz (`sudo apt install graphviz`) thì `terraform graph | dot -Tsvg > graph.svg`.

### 4.12. 🟥 Cùng ý tưởng, đổi sang AWS

| Docker (lab) | AWS (lab-02 và v4) |
|---|---|
| `provider "docker" { host = "unix:///var/run/docker.sock" }` | `provider "aws" { region = "ap-southeast-1" default_tags { tags = {...} } }` |
| `docker_network` | `aws_vpc`, `aws_subnet` |
| `docker_container` với `ports` | `aws_instance` + `aws_security_group` |
| `docker_volume` | `aws_ebs_volume` / ổ gốc của EC2 |
| `docker_image` | `data "aws_ssm_parameter"` cho AMI |
| `local_file` sinh file cấu hình | `user_data` sinh bởi `templatefile()` |
| Socket Docker = "credential" | Credential AWS (mục dưới) |

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
      Env       = "dev"
      Owner     = "phuong"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_security_group" "web" {
  name        = "taskhub-web-sg"
  description = "HTTP from anywhere"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
```

(Ví dụ minh họa — `aws_vpc.this` được viết đầy đủ ở lab-02. Provider AWS khuyến nghị resource riêng `aws_vpc_security_group_ingress_rule` thay cho block `ingress` lồng trong SG.)

**Terraform lấy credential AWS từ đâu?** Provider AWS đọc theo chuỗi giống AWS CLI: biến môi trường → profile trong `~/.aws/config` (biến `AWS_PROFILE`) → … Giáo trình **không** dùng access key dài hạn ([AWS 06](../06-AWS/06-aws-cli.md)):

```bash
aws login --profile taskhub        # đăng nhập trình duyệt, credential tạm thời
export AWS_PROFILE=taskhub
terraform plan
```

Nếu provider báo không tìm thấy credential với profile kiểu `aws login` (công cụ dùng SDK cũ chưa hỗ trợ — tài liệu `aws login` có nêu trường hợp này), tạo profile trung gian trong `~/.aws/config`:

```ini
[profile taskhub-tf]
region = ap-southeast-1
credential_process = aws configure export-credentials --profile taskhub --format process
```

rồi `export AWS_PROFILE=taskhub-tf`. CLI sẽ cấp credential tạm thời mỗi khi Terraform cần. (Giáo trình chưa kiểm chứng trên máy thật provider 6.x có đọc trực tiếp profile `aws login` hay không — ghi lại kết quả của bạn vào nhật ký.)

### 4.13. Gặp lại ở đâu

| Kiến thức bài này | Gặp lại |
|---|---|
| Plan, `-/+`, `forces replacement` | Review PR hạ tầng (lab-02, v4), workflow `infra.yml` |
| State, refresh, drift | [Bài 03](03-terraform-state-backend.md), break-fix Terraform #1 |
| Variable, output, `for_each` | Module `network`, `app_server` ([bài 04](04-terraform-modules-environments.md)) |
| `ephemeral`, `sensitive` | Mật khẩu PostgreSQL trong Parameter Store (v4) |
| `lifecycle.prevent_destroy` | Bucket state, bucket backup (bài 03, v4) |
| Output `-json` / `-raw` | Ansible đọc IP/instance ID ([bài 05](05-ansible-fundamentals.md)), cập nhật biến GitHub `APP_URL` |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Chỉ đổi tên Security Group thôi mà"

Một bạn đổi `name = "web-sg"` thành `name = "taskhub-web-sg"` cho đẹp, mở PR, CI báo plan:

```text
  # aws_security_group.web must be replaced
-/+ resource "aws_security_group" "web" {
      ~ name = "web-sg" -> "taskhub-web-sg" # forces replacement
```

Tên SG không sửa được trên AWS → phải thay. SG mới có ID mới → EC2 đang gắn SG cũ cũng bị cập nhật, và nếu có SG khác tham chiếu SG này thì cả chuỗi thay đổi. Người review đọc được `-/+` và `forces replacement` sẽ hỏi: "Có đáng không?" Đó chính là giá trị của việc đọc plan.

### Ví dụ 2: `count` và subnet

Một team tạo 3 subnet bằng `count` từ list `["a", "b", "c"]`. Một ngày muốn bỏ AZ `b`. Plan đề xuất **thay thế** subnet `c` (vì nó trượt từ index 2 về 1) — mà subnet `c` đang chứa database. Viết lại bằng `for_each` với key là tên AZ thì chỉ subnet `b` bị xóa. Chuyển từ `count` sang `for_each` trên hạ tầng đang chạy cần khối `moved` (bài 04) — rẻ hơn rất nhiều nếu chọn đúng từ đầu.

### Ví dụ 3: "Trên máy anh plan sạch, trên CI lại đòi đổi"

Nguyên nhân thường gặp: máy anh chưa `init -upgrade` nên dùng provider cũ, còn ai đó đã commit `.terraform.lock.hcl` mới; hoặc ngược lại, `.terraform.lock.hcl` **không được commit** nên mỗi nơi tải một phiên bản khác. Cách phòng: commit lock file, nâng provider có chủ đích qua PR.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Terraform nói chuyện với ai

```text
 ┌──────────────── [WSL] thư mục lab-01 ─────────────────┐
 │  *.tf  ──►  terraform (core)  ──►  terraform.tfstate  │
 │                 │   ▲                                 │
 │       gRPC      ▼   │                                 │
 │    provider docker (tải về .terraform/providers/)     │
 └─────────────────┼─────────────────────────────────────┘
                   │ Docker API qua unix:///var/run/docker.sock
                   ▼
            Docker Desktop (Engine)
            ├── network  tf07-net
            ├── volume   tf07-logs
            └── container tf07-web-blue, tf07-web-green

 Với AWS: provider aws gọi HTTPS tới API EC2/VPC/IAM… bằng credential tạm thời.
```

### 6.2. Một lần `terraform apply`

```text
 đọc *.tf ──► đọc state ──► REFRESH: hỏi API "thực tế giờ ra sao?"
     ──► so sánh: code ↔ state đã làm mới ──► PLAN (+ ~ -/+ -)
     ──► hỏi "Enter a value: yes" ──► gọi API theo thứ tự đồ thị (song song khi được)
     ──► ghi kết quả vào state sau MỖI resource ──► in outputs
```

Vì state được ghi sau từng resource, nếu `apply` lỗi giữa chừng, những gì đã tạo vẫn nằm trong state — chạy lại `apply` sẽ tiếp tục, không tạo trùng.

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích |
|---|---|
| `terraform version` | Phiên bản Terraform và provider đã tải |
| `terraform init` / `init -upgrade` | Chuẩn bị thư mục / nâng provider trong giới hạn ràng buộc |
| `terraform fmt -recursive` / `fmt -check` | Định dạng / kiểm tra định dạng (CI) |
| `terraform validate` | Kiểm tra cú pháp và tham chiếu |
| `terraform plan` / `plan -out=plan.tfplan` | Xem thay đổi / lưu kế hoạch |
| `terraform plan -var 'base_port=9090'` | Truyền biến |
| `terraform plan -detailed-exitcode` | Exit 0 = không đổi, 1 = lỗi, 2 = có thay đổi (dùng trong script/CI) |
| `terraform plan -refresh-only` | Chỉ xem state lệch thực tế ra sao, không đề xuất đổi theo code |
| `terraform plan -replace='ADDRESS'` | Buộc thay thế một resource |
| `terraform apply` / `apply plan.tfplan` / `apply -auto-approve` | Áp dụng (⚠️ `-auto-approve` bỏ bước xác nhận) |
| `terraform destroy` | ⚠️ Xóa mọi resource trong state |
| `terraform output [-json\|-raw] [tên]` | Đọc output |
| `terraform state list` / `state show ADDRESS` | Xem state |
| `terraform console` | Thử expression |
| `terraform graph` | Đồ thị phụ thuộc |
| `terraform providers` | Cây provider cấu hình cần |

---

## 8. Giải thích câu lệnh và tham số

### `terraform init`

```bash
terraform init
```

```text
Initializing the backend...
Initializing provider plugins...
- Finding kreuzwerker/docker versions matching "~> 4.6"...
- Finding hashicorp/local versions matching "~> 2.9"...
- Installing kreuzwerker/docker v4.6.0...
- Installed kreuzwerker/docker v4.6.0 (self-signed, key ID ...)
- Installing hashicorp/local v2.9.1...
- Installed hashicorp/local v2.9.1 (signed by HashiCorp)
Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

(Minh họa.) Đọc: ràng buộc `~> 4.6` → chọn 4.6.0; provider của bên thứ ba ký bằng khóa riêng ("self-signed"), provider của HashiCorp ký bằng khóa HashiCorp. Chính Terraform nhắc bạn commit lock file.

Chạy lại `init` khi: lần đầu vào thư mục, thêm/đổi provider hoặc module, đổi cấu hình backend. Chạy `init` thừa không hại gì.

### `terraform plan -out=plan.tfplan`

| Phần | Ý nghĩa |
|---|---|
| `plan` | Tính thay đổi, không thay đổi gì |
| `-out=plan.tfplan` | Lưu kế hoạch nhị phân vào file |
| `-var 'k=v'` | Gán biến (lặp lại được) |
| `-var-file=dev.tfvars` | Đọc biến từ file |
| `-target=ADDRESS` | 🟨 Chỉ plan một phần đồ thị — **chỉ dùng khi khẩn cấp**, tài liệu Terraform cảnh báo không dùng thường xuyên |

### `terraform apply`

```text
Plan: 6 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

Chỉ đúng chữ `yes` mới được chấp nhận — `y` hay `Yes` đều bị coi là từ chối. Đây là "chốt an toàn" cuối cùng; `-auto-approve` bỏ chốt này, chỉ dùng trong CI có plan đã được duyệt hoặc lab dùng một lần.

### `terraform state show`

```bash
terraform state show 'docker_container.web["blue"]'
```

Dấu nháy đơn bao ngoài là **bắt buộc** trong bash: không có chúng, bash sẽ xử lý `[` `"` theo cách của nó và Terraform nhận sai địa chỉ.

### `terraform plan -detailed-exitcode`

```bash
terraform plan -detailed-exitcode > /dev/null; echo "exit=$?"
```

| Exit | Nghĩa |
|---|---|
| 0 | Thành công, **không** có thay đổi — thực tế khớp code |
| 1 | Lỗi |
| 2 | Thành công, **có** thay đổi |

Dùng để viết script "kiểm tra drift hằng đêm" (bài tập 5).

---

## 9. Bài thực hành từng bước

Thực hành chính của bài nằm trong [Lab 01 — Terraform quản lý Docker trên máy](labs/lab-01-terraform-local-docker.md) (miễn phí). Phần dưới đây là các thí nghiệm nhỏ để làm quen **trước** lab, mỗi thí nghiệm 5–10 phút, trong một thư mục riêng.

`[WSL]`

```bash
mkdir -p ~/devops-lab/07-terraform/warmup && cd ~/devops-lab/07-terraform/warmup
docker info --format '{{.ServerVersion}}'   # phải in ra phiên bản; lỗi socket → bật WSL Integration
```

### Bước 1 — Cấu hình nhỏ nhất: một file

Tạo `main.tf`:

```hcl
terraform {
  required_version = "~> 1.17"
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

variable "who" {
  type    = string
  default = "phuong"
}

resource "local_file" "hello" {
  filename        = "${path.module}/hello.txt"
  content         = "Xin chào ${var.who}, đây là file do Terraform tạo.\n"
  file_permission = "0644"
}

output "path" {
  value = local_file.hello.filename
}
```

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply      # gõ yes
cat hello.txt
terraform state list
```

❓ Plan có mấy dòng `+`? Vì sao không có `<=`?

### Bước 2 — Biến và thứ tự ưu tiên

```bash
terraform plan -var 'who=An'                 # (a)
export TF_VAR_who='Bình'; terraform plan     # (b)
echo 'who = "Chi"' > terraform.tfvars
terraform plan                               # (c) TF_VAR_who vẫn đang đặt!
terraform plan -var 'who=Dũng'               # (d)
unset TF_VAR_who; rm terraform.tfvars
```

❓ Ở (c), plan dùng `Bình` hay `Chi`? Đối chiếu với bảng ưu tiên ở mục 4.5.

❓ Thay đổi `content` cho ra ký hiệu nào: `~` hay `-/+`? Tìm dòng `# forces replacement`.

### Bước 3 — Drift đầu tiên

```bash
terraform apply -auto-approve      # đưa về đúng code
echo "sửa tay" >> hello.txt
terraform plan
rm hello.txt
terraform plan
```

❓ Hai lần plan khác nhau thế nào? Terraform biết file bị sửa/xóa bằng cách nào?

### Bước 4 — `count` vs `for_each` trên `local_file`

Thêm vào `main.tf`:

```hcl
variable "fruits_list" {
  type    = list(string)
  default = ["apple", "banana", "cherry"]
}

resource "local_file" "by_count" {
  count    = length(var.fruits_list)
  filename = "${path.module}/count-${count.index}.txt"
  content  = "${var.fruits_list[count.index]}\n"
}

resource "local_file" "by_each" {
  for_each = toset(var.fruits_list)
  filename = "${path.module}/each-${each.key}.txt"
  content  = "${each.key}\n"
}
```

```bash
terraform apply -auto-approve
terraform state list
terraform plan -var 'fruits_list=["apple","cherry"]'
```

❓ Plan đụng tới bao nhiêu resource `by_count`, bao nhiêu `by_each`? Viết vào nhật ký vì sao.

### Bước 5 — Console và graph

```bash
terraform console
```

Thử: `var.who`, `upper(var.who)`, `length(var.fruits_list)`, `local_file.hello.content`, `cidrsubnet("10.20.0.0/16", 8, 2)`, `{ for f in var.fruits_list : f => length(f) }`. Thoát bằng `exit` hoặc Ctrl+D.

```bash
terraform graph | head -30
```

❓ Tìm cạnh nối `output.path` với `local_file.hello`.

### Bước 6 — Dọn dẹp

```bash
terraform destroy      # gõ yes
ls                     # chỉ còn main.tf, .terraform/, .terraform.lock.hcl, terraform.tfstate*
```

❓ Sau destroy, `terraform.tfstate` vẫn còn. Mở ra xem: mảng `resources` chứa gì?

---

## 10. Kết quả mong đợi

- `terraform version` in `Terraform v1.17.x` (hoặc mới hơn trong dòng 1.x).
- Bước 1: plan `1 to add`; sau apply có `hello.txt` và state liệt kê `local_file.hello`.
- Bước 2: (a) An; (b) Bình; (c) **Chi** (`terraform.tfvars` ưu tiên cao hơn `TF_VAR_`); (d) Dũng. Đổi `content` của `local_file` → **`-/+`** với `# forces replacement` (provider `local` không sửa file tại chỗ).
- Bước 3: **cả hai** lần plan đều đề xuất tạo lại `+ local_file.hello`. Provider `local` khi refresh so checksum file thật với checksum đã lưu; khác (bị sửa) hay không còn file (bị xóa) đều được coi là "resource không còn" → tạo lại. Terraform biết nhờ bước **refresh** đọc lại file thật. Cách phát hiện drift là việc của **từng provider** — provider AWS so từng thuộc tính và thường đề xuất `~` sửa tại chỗ. (Nếu máy bạn cho kết quả khác, ghi lại — đó là dữ liệu thật đáng tin hơn giáo trình.)
- Bước 4: `by_count` → `count-1.txt` bị thay nội dung (banana → cherry), `count-2.txt` bị xóa; `by_each` → chỉ `each-banana.txt` bị xóa.
- Bước 6: `terraform state list` rỗng; mảng `resources` trong state rỗng.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `Error: Inconsistent dependency lock file` | Đổi `required_providers` mà chưa `init` lại | `terraform init` (thêm `-upgrade` nếu muốn bản mới hơn trong ràng buộc) |
| `Error: Failed to query available provider packages` | Không ra được Internet / gõ sai `source` | Kiểm tra `curl -I https://registry.terraform.io`; sửa `source = "kreuzwerker/docker"` |
| `Error: Unsupported Terraform Core version` | Máy cài bản cũ hơn `required_version` | `sudo apt update && sudo apt install terraform` |
| `Cannot connect to the Docker daemon at unix:///var/run/docker.sock` | Docker Desktop tắt hoặc **chưa bật WSL Integration** | Docker Desktop → Settings → Resources → WSL integration → bật Ubuntu ([Docker 01](../04-DOCKER/01-vm-vs-container-architecture.md)) |
| `Error: Reference to undeclared resource` | Gõ sai tên cục bộ, hoặc quên `data.` khi tham chiếu data source | Đối chiếu `terraform state list` / tên block |
| `Error: Invalid for_each argument ... known only after apply` | Key `for_each` phụ thuộc thuộc tính chỉ biết sau khi tạo | Dùng key tĩnh (tên, từ biến) |
| `Error: Instance cannot be destroyed` | `prevent_destroy = true` | Có chủ đích → bỏ `prevent_destroy` trong code rồi mới destroy |
| `bind: address already in use` khi tạo container | Cổng host đã bị chiếm (máy bạn: 8000 đang bận) | Đổi biến cổng; `sudo ss -ltnp \| grep <cổng>` |
| Plan luôn thấy thay đổi dù không sửa gì ("perpetual diff") | Giá trị trong code khác dạng API trả về (ví dụ chữ hoa/thường, thứ tự) | Viết đúng dạng API trả về; cân nhắc `ignore_changes` có ghi chú |
| `No valid credential sources found` (AWS) | Chưa `aws login` / chưa `export AWS_PROFILE` / profile `aws login` chưa được SDK hỗ trợ | Mục 4.12 — profile `credential_process` |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Đọc thông báo lỗi của Terraform

Terraform in lỗi có cấu trúc — đọc theo thứ tự: **dòng `Error:`** (loại lỗi) → **`on <file> line <n>`** (vị trí) → **khối code trích dẫn** → **giải thích**.

```text
│ Error: Unsupported argument
│
│   on main.tf line 21, in resource "docker_container" "web":
│   21:   port = 8081
│
│ An argument named "port" is not expected here.
```

(Minh họa.) Sửa: tra schema resource trên registry — tham số đúng là block `ports { internal = 80, external = 8081 }`.

Với lỗi từ provider (API trả về lỗi), phần cuối thường chứa **thông báo gốc của Docker/AWS** — đó mới là nguyên nhân thật:

```text
│ Error: Unable to create container: Error response from daemon: driver failed programming
│ external connectivity on endpoint tf07-web-blue: Bind for 127.0.0.1:8081 failed: port is already allocated
```

### 12.2. Log chi tiết: `TF_LOG`

```bash
TF_LOG=DEBUG TF_LOG_PATH=./tf-debug.log terraform plan
grep -n -i 'error\|HTTP/' tf-debug.log | head
```

| Mức | Dùng khi |
|---|---|
| `ERROR`, `WARN`, `INFO` | Ít chi tiết |
| `DEBUG` | Thấy request/response tới API (đủ để debug lỗi quyền, lỗi API) |
| `TRACE` | Rất nhiều — chỉ khi báo lỗi cho provider |
| `TF_LOG_PROVIDER=DEBUG` | Chỉ log của provider |

⚠️ Log `DEBUG` có thể chứa header xác thực và dữ liệu nhạy cảm. Không dán log lên issue/chat công khai khi chưa đọc kỹ; xóa file log khi xong.

### 12.3. Quy trình khi `apply` lỗi giữa chừng

1. **Đọc lỗi**, đừng chạy lại ngay.
2. `terraform state list` — resource nào đã vào state?
3. `terraform plan` — Terraform định làm gì tiếp?
4. Sửa nguyên nhân (code, quyền, cổng bận…), rồi `apply` lại — Terraform tiếp tục từ chỗ dừng.
5. Ghi vào `troubleshooting-journal.md`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Provider là gì? Vì sao Terraform core không tự biết cách tạo EC2?
2. Resource và data source khác nhau thế nào? Cho một ví dụ mỗi loại trong `taskhub`.
3. `version = "~> 4.6"` nhận những phiên bản nào? `~> 4.6.0` thì sao?
4. `.terraform.lock.hcl` để làm gì? Có commit không? Còn `.terraform/` và `terraform.tfstate`?
5. Liệt kê 6 nguồn giá trị biến theo thứ tự ưu tiên. `TF_VAR_x` và `terraform.tfvars` cùng đặt thì cái nào thắng?
6. `sensitive = true` có giữ biến khỏi state không? `ephemeral = true` khác gì?
7. Vì sao `for_each` với map thường an toàn hơn `count` khi các bản sao có danh tính riêng? Giải thích bằng ví dụ xóa phần tử giữa.
8. Khi nào cần `depends_on`? Vì sao không nên dùng tràn lan?
9. Ký hiệu `-/+` trong plan nghĩa là gì? Tìm nguyên nhân ở đâu trong plan?
10. `terraform plan -out=x` rồi `apply x` có lợi gì so với `apply` trực tiếp? File `x` có nhạy cảm không?
11. `prevent_destroy` chặn được gì và **không** chặn được gì?
12. `create_before_destroy` có rủi ro gì với resource có tên duy nhất?
13. Plan thấy container cần tạo lại dù bạn không sửa code. Ba khả năng?
14. `-detailed-exitcode` trả về 2 nghĩa là gì? Dùng vào việc gì?
15. Terraform lấy credential AWS từ đâu? Vì sao giáo trình không dùng `AWS_ACCESS_KEY_ID`?

---

## 14. Bài tập tự làm

**Bài 1 — Đọc schema.** Không nhìn lab, dùng tài liệu provider `kreuzwerker/docker` trên registry để viết resource `docker_container` chạy `nginx:1.30-alpine`, publish cổng 8090 **chỉ trên 127.0.0.1**, restart `unless-stopped`, có biến môi trường `TZ=Asia/Ho_Chi_Minh`. Kiểm tra bằng `validate` và `plan`.

**Bài 2 — Biến có kiểm tra.** Viết biến `env` chỉ nhận `dev` hoặc `prod` (dùng `validation` + `contains`), và local `instance_type` = `t3.small` nếu `prod`, `t3.micro` nếu `dev`. Chứng minh bằng `terraform console` và bằng một lần plan với `-var env=staging` (phải báo lỗi rõ ràng).

**Bài 3 — Chuyển `count` sang `for_each` mà không phá gì.** Từ Bước 4 (đã apply `by_count` với 3 phần tử), viết lại thành `for_each` sao cho plan **không** xóa/tạo lại file nào. Gợi ý: tìm hiểu block `moved` trong tài liệu Terraform (sẽ học kỹ ở bài 04).

**Bài 4 — Đọc plan của người khác.** Cho đoạn plan sau, trả lời: có bao nhiêu resource bị thay thế, vì sao, và hậu quả với người dùng là gì?

```text
  # aws_instance.app must be replaced
-/+ resource "aws_instance" "app" {
      ~ ami                          = "ami-0aaa1111" -> "ami-0bbb2222" # forces replacement
      ~ public_ip                    = "13.250.10.20" -> (known after apply)
        tags                         = { "Name" = "taskhub-app" }
      ~ user_data                    = "9f2c..." -> "1d7e..." # forces replacement
    }
Plan: 1 to add, 0 to change, 1 to destroy.
```

**Bài 5 — Script kiểm tra drift.** Viết `check-drift.sh` chạy `terraform plan -detailed-exitcode` trong thư mục lab, in `OK: không lệch`, `DRIFT: có thay đổi` hoặc `ERROR` theo exit code, và trả về đúng exit code cho cron. Dùng `set -uo pipefail` (vì sao **không** dùng `-e` ở đây?).

**Bài 6 — Dịch sang AWS trên giấy.** Viết (không apply) file `.tf` mô tả: VPC `10.20.0.0/16`, 2 subnet public bằng `for_each` trên map `{ a = "10.20.1.0/24", b = "10.20.2.0/24" }` với AZ tương ứng `ap-southeast-1a/b`, một SG mở cổng 80. Chạy `terraform init` rồi `terraform validate` (không cần credential để validate — kiểm tra điều này). Lưu ý: provider AWS tải về khá nặng (hàng trăm MB) — dùng chung thư mục cho lab-02 sau này.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Cài được Terraform từ kho apt chính thức và giải thích từng lệnh cài.
- [ ] Giải thích được provider, resource, data source, state, plan bằng lời của mình.
- [ ] Biết commit gì, không commit gì (lock file, `.terraform/`, state, plan).
- [ ] Nói đúng thứ tự ưu tiên của biến và chứng minh được bằng thí nghiệm.
- [ ] Chọn đúng `count`/`for_each` và giải thích hậu quả khi xóa phần tử giữa.
- [ ] Đọc plan: phân biệt `+`, `~`, `-/+`, `-`, `<=`; tìm được `# forces replacement`.
- [ ] Biết `sensitive` không giữ giá trị khỏi state; biết `ephemeral` dùng để làm gì.
- [ ] Đọc được thông báo lỗi Terraform: loại lỗi, file:dòng, lỗi gốc của API.
- [ ] Hoàn thành [Lab 01](labs/lab-01-terraform-local-docker.md).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Install Terraform](https://developer.hashicorp.com/terraform/install) | Lệnh cài qua kho apt HashiCorp | 2026-10-31 |
| [Terraform releases (GitHub)](https://github.com/hashicorp/terraform/releases) | Phiên bản 1.17.1 (28/10/2026) | 2026-10-31 |
| [Input variables](https://developer.hashicorp.com/terraform/language/values/variables) | Validation, `sensitive` vẫn lưu trong state, `ephemeral`, thứ tự ưu tiên | 2026-10-31 |
| [Ephemeral resources & write-only arguments](https://developer.hashicorp.com/terraform/language/manage-sensitive-data/ephemeral) | Giá trị không lưu vào state/plan | 2026-10-31 |
| [`terraform plan`](https://developer.hashicorp.com/terraform/cli/commands/plan) | Ký hiệu plan, `-out`, `-refresh-only`, `-replace`, `-detailed-exitcode` | 2026-10-31 |
| [Provider `kreuzwerker/docker` — docs (GitHub)](https://github.com/kreuzwerker/terraform-provider-docker/tree/master/docs) | `docker_container`, `docker_image`, `docker_network`, `docker_volume`; schema ForceNew | 2026-10-31 |
| [Provider docker releases](https://github.com/kreuzwerker/terraform-provider-docker/releases) | Bản 4.6.0 | 2026-10-31 |
| [Provider `hashicorp/local` releases](https://github.com/hashicorp/terraform-provider-local/releases) | Bản 2.9.1 | 2026-10-31 |
| [Provider AWS releases](https://github.com/hashicorp/terraform-provider-aws/releases) | Bản 6.71.0 | 2026-10-31 |
| [`aws_ssm_parameter` — `value_wo`](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/ssm_parameter.html.markdown) | Write-only argument, Terraform ≥ 1.11 | 2026-10-31 |
| [Login for AWS local development (`aws login`)](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html) | Credential tạm thời, công cụ cũ dùng `credential_process` | 2026-10-31 |
| [Terraform tutorials — Get Started AWS](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) | Bộ hướng dẫn chính thức dùng ở lab-01 phần B | 2026-10-31 |
