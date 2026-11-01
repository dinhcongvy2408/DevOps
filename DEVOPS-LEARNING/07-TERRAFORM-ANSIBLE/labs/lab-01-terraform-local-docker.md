# Lab 01 — Terraform quản lý Docker trên máy (và Get Started AWS)

> ⏱️ Phần A ~2 giờ (0 USD) · Phần B ~1,5 giờ (AWS, vài cent) · Tuần 15 · Mức độ: 🟥 Bắt buộc
> Kiến thức cần có trước: [02. Terraform cơ bản](../02-terraform-basics.md) (ít nhất mục 1–8), [Docker 04](../../04-DOCKER/04-volumes-networks-env.md), [AWS 06 — AWS CLI](../../06-AWS/06-aws-cli.md) (cho phần B)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (đã bật WSL Integration) · Terraform 1.17.x · provider `kreuzwerker/docker` 4.6, `hashicorp/local` 2.9 (kiểm tra 2026-10-31)

## Mục lục

- [Mục tiêu](#mục-tiêu)
- [Phần A — Terraform quản lý Docker (0 USD)](#phần-a--terraform-quản-lý-docker-0-usd)
  - [A0. Kiểm tra môi trường](#a0-kiểm-tra-môi-trường)
  - [A1. Tạo các file cấu hình](#a1-tạo-các-file-cấu-hình)
  - [A2. init, fmt, validate, plan, apply](#a2-init-fmt-validate-plan-apply)
  - [A3. Kiểm tra kết quả bằng công cụ Docker](#a3-kiểm-tra-kết-quả-bằng-công-cụ-docker)
  - [A4. Thí nghiệm: sửa tại chỗ hay thay thế?](#a4-thí-nghiệm-sửa-tại-chỗ-hay-thay-thế)
  - [A5. Thí nghiệm: drift — ai đó sửa bằng tay](#a5-thí-nghiệm-drift--ai-đó-sửa-bằng-tay)
  - [A6. Thí nghiệm: prevent_destroy](#a6-thí-nghiệm-prevent_destroy)
  - [A7. Dọn dẹp](#a7-dọn-dẹp)
- [Phần B — Terraform Get Started AWS (chính thức)](#phần-b--terraform-get-started-aws-chính-thức)
- [Các lỗi thường gặp](#các-lỗi-thường-gặp)
- [Tiêu chí hoàn thành](#tiêu-chí-hoàn-thành)
- [Câu hỏi sau lab](#câu-hỏi-sau-lab)

---

## Mục tiêu

- Viết một cấu hình Terraform hoàn chỉnh (versions, variables, main, outputs) và giải thích từng dòng.
- Dùng `for_each` tạo nhiều container có danh tính riêng.
- Sinh file cấu hình bằng `local_file` và gắn vào container.
- Phân biệt bằng **quan sát thật** khi nào thay đổi là `~` (sửa tại chỗ) và khi nào là `-/+` (thay thế).
- Thấy drift xảy ra thế nào và Terraform phản ứng ra sao.
- Làm bộ hướng dẫn chính thức của HashiCorp trên AWS, đã điều chỉnh cho tài khoản Free plan của bạn.

**Lời giải:** [solutions/lab-01-solutions.md](../solutions/lab-01-solutions.md) — chỉ mở sau khi tự làm.

---

## Phần A — Terraform quản lý Docker (0 USD)

Mọi tài nguyên của phần A có tiền tố `tf07-` để dễ nhận ra và dễ dọn.

```text
                         [WSL] ~/devops-lab/07-terraform/lab-01/
  terraform ──► provider docker ──► Docker Desktop
                                     ├── network  tf07-net
                                     ├── volume   tf07-logs  (log của cả 2 site)
                                     ├── container tf07-web-blue   127.0.0.1:8081 → 80
                                     └── container tf07-web-green  127.0.0.1:8082 → 80
            provider local ──► generated/blue/{default.conf,html/index.html}
                               generated/green/{default.conf,html/index.html}
```

### A0. Kiểm tra môi trường

`[WSL]`

```bash
terraform version                              # Terraform v1.17.x
docker info --format '{{.ServerVersion}}'      # phải in ra phiên bản Docker
sudo ss -ltn | grep -E ':(8081|8082)\b' || echo "8081, 8082 đang trống"
```

Nếu `docker info` báo `Cannot connect to the Docker daemon at unix:///var/run/docker.sock`: bật **Docker Desktop → Settings → Resources → WSL integration → Ubuntu → Apply & restart**. Nếu 8081/8082 bận: dùng cặp cổng khác qua biến `base_port` ở bước A2.

```bash
mkdir -p ~/devops-lab/07-terraform/lab-01 && cd ~/devops-lab/07-terraform/lab-01
```

### A1. Tạo các file cấu hình

**`versions.tf`** — phiên bản Terraform, provider và cấu hình provider:

```hcl
terraform {
  required_version = "~> 1.17"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}
```

**`variables.tf`**:

```hcl
variable "project" {
  description = "Tiền tố tên mọi tài nguyên"
  type        = string
  default     = "tf07"
}

variable "base_port" {
  description = "Cổng host của site đầu tiên; site sau = base_port + port_offset"
  type        = number
  default     = 8081

  validation {
    condition     = var.base_port >= 1024 && var.base_port <= 65000
    error_message = "base_port phải trong khoảng 1024–65000."
  }
}

variable "sites" {
  description = "Mỗi key là một site (một container)"
  type = map(object({
    port_offset = number
    message     = string
  }))
  default = {
    blue = {
      port_offset = 0
      message     = "Xin chào từ site BLUE"
    }
    green = {
      port_offset = 1
      message     = "Xin chào từ site GREEN"
    }
  }
}

variable "restart_policy" {
  description = "Restart policy của container"
  type        = string
  default     = "unless-stopped"

  validation {
    condition     = contains(["no", "on-failure", "always", "unless-stopped"], var.restart_policy)
    error_message = "restart_policy phải là no, on-failure, always hoặc unless-stopped."
  }
}
```

**`main.tf`**:

```hcl
locals {
  # Cổng thật của từng site, tính một lần dùng nhiều nơi
  ports = { for name, site in var.sites : name => var.base_port + site.port_offset }
}

resource "docker_network" "this" {
  name = "${var.project}-net"
}

resource "docker_volume" "logs" {
  name = "${var.project}-logs"
}

resource "docker_image" "nginx" {
  name         = "nginx:1.30-alpine"
  keep_locally = true # destroy không xóa image khỏi máy (các lab khác còn dùng)
}

# Cấu hình nginx riêng cho từng site: log ghi vào volume chung, mỗi site một file
resource "local_file" "conf" {
  for_each = var.sites

  filename        = "${path.module}/generated/${each.key}/default.conf"
  file_permission = "0644"
  content         = <<-EOT
    server {
      listen 80;
      access_log /var/log/tf07/${each.key}.access.log;

      location = /healthz {
        default_type text/plain;
        return 200 "ok ${each.key}\n";
      }

      location / {
        root  /usr/share/nginx/html;
        index index.html;
      }
    }
  EOT
}

resource "local_file" "page" {
  for_each = var.sites

  filename        = "${path.module}/generated/${each.key}/html/index.html"
  file_permission = "0644"
  content         = <<-EOT
    <!doctype html>
    <meta charset="utf-8">
    <h1>${each.value.message}</h1>
    <p>site=${each.key} · cổng host=${local.ports[each.key]}</p>
  EOT
}

resource "docker_container" "web" {
  for_each = var.sites

  name    = "${var.project}-web-${each.key}"
  image   = docker_image.nginx.image_id
  restart = var.restart_policy

  ports {
    internal = 80
    external = local.ports[each.key]
    ip       = "127.0.0.1" # chỉ máy mình truy cập được
  }

  networks_advanced {
    name    = docker_network.this.name
    aliases = [each.key] # trong network tf07-net, container gọi nhau bằng "blue", "green"
  }

  # Gắn MỘT FILE cấu hình. Khi file bị tạo lại, container cũ vẫn giữ inode cũ
  # → dùng label chứa hash nội dung để buộc tạo lại container khi cấu hình đổi.
  volumes {
    host_path      = abspath(local_file.conf[each.key].filename)
    container_path = "/etc/nginx/conf.d/default.conf"
    read_only      = true
  }

  # Gắn cả THƯ MỤC html: file bên trong đổi thì container thấy ngay.
  volumes {
    host_path      = abspath(dirname(local_file.page[each.key].filename))
    container_path = "/usr/share/nginx/html"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.logs.name
    container_path = "/var/log/tf07"
  }

  labels {
    label = "tf07.conf-sha1"
    value = sha1(local_file.conf[each.key].content)
  }
}
```

**`outputs.tf`**:

```hcl
output "urls" {
  description = "URL của từng site"
  value       = { for name, port in local.ports : name => "http://127.0.0.1:${port}" }
}

output "container_ids" {
  description = "ID container theo site"
  value       = { for name, c in docker_container.web : name => c.id }
}

output "network_name" {
  value = docker_network.this.name
}
```

Trước khi chạy, tự trả lời (ghi vào nhật ký):

1. Terraform sẽ tạo bao nhiêu resource? Liệt kê địa chỉ (`docker_container.web["blue"]`…).
2. Thứ tự tạo bắt buộc là gì? Những gì có thể tạo song song?
3. Vì sao `abspath(...)`? (Gợi ý: Docker cần đường dẫn tuyệt đối cho bind mount.)

### A2. init, fmt, validate, plan, apply

```bash
terraform init
terraform fmt          # in tên file nào được định dạng lại; không in gì = đã chuẩn
terraform validate
terraform plan -out=plan.tfplan
```

Đọc plan trước khi apply:

- Dòng `Plan: N to add, 0 to change, 0 to destroy.` — N có khớp câu trả lời 1 không?
- Container có `id = (known after apply)` — vì sao Terraform chưa biết?
- Tìm `labels` trong plan: giá trị hash đã biết hay `(known after apply)`?

```bash
terraform apply plan.tfplan
terraform output
```

> Nếu cổng 8081/8082 bận: `terraform plan -var 'base_port=9081' -out=plan.tfplan`, rồi `apply plan.tfplan`. Nhớ dùng cùng `-var` cho mọi lệnh sau, hoặc ghi `base_port = 9081` vào `terraform.tfvars`.

### A3. Kiểm tra kết quả bằng công cụ Docker

Terraform nói đã tạo — **tự kiểm chứng** bằng công cụ khác, đừng tin mỗi output của nó:

```bash
docker ps --filter name=tf07- --format 'table {{.Names}}\t{{.Ports}}\t{{.Status}}'
curl -s http://127.0.0.1:8081/ | grep h1
curl -s http://127.0.0.1:8082/healthz
docker network inspect tf07-net --format '{{range .Containers}}{{.Name}} {{end}}'

# Hai container gọi nhau bằng alias trong network:
docker exec tf07-web-blue wget -qO- http://green/healthz

# Log của cả hai site nằm trong CÙNG một volume:
docker run --rm -v tf07-logs:/logs alpine:3.20 ls -l /logs

terraform state list
terraform state show 'docker_container.web["green"]' | grep -E 'name|restart|external'
```

### A4. Thí nghiệm: sửa tại chỗ hay thay thế?

Với **mỗi** thay đổi dưới đây: sửa → `terraform plan` → ghi lại **ký hiệu** (`~` hay `-/+`) và **dòng `# forces replacement`** (nếu có) vào bảng trong nhật ký → `terraform apply` → kiểm tra bằng `docker ps` (cột CREATED cho biết container có mới không).

| # | Thay đổi | Dự đoán của bạn | Ký hiệu thật | Container mới? |
|---|---|---|---|---|
| T1 | `-var 'restart_policy=always'` | | | |
| T2 | Sửa `message` của `green` trong `variables.tf` | | | |
| T3 | Thêm dòng `add_header X-Site ${each.key};` vào khối `location /` trong `local_file.conf` | | | |
| T4 | `-var 'base_port=8091'` (hoặc +10 so với cổng bạn đang dùng) | | | |
| T5 | Thêm site thứ ba `red = { port_offset = 2, message = "RED" }` | | | |
| T6 | Xóa site `blue` khỏi map | | | |

Sau T2, chạy `curl -s http://127.0.0.1:8082/` **trước** khi apply và **sau** khi apply — trang đổi lúc nào?

Sau T3, chạy `curl -sI http://127.0.0.1:8081/ | grep -i x-site`.

🧪 **Thí nghiệm phụ (hiểu vì sao có `labels`):** xóa tạm block `labels { ... }`, apply. Rồi đổi nội dung `conf` (ví dụ `ok` → `OK`), apply, và `curl -s http://127.0.0.1:8081/healthz`. Nginx trả nội dung cũ hay mới? Chạy `docker exec tf07-web-blue cat /etc/nginx/conf.d/default.conf`. Giải thích bằng khái niệm **inode** ([Linux 01](../../01-LINUX/01-linux-architecture-filesystem.md)). Khôi phục block `labels` rồi apply lại.

Trả lại trạng thái chuẩn sau thí nghiệm (bỏ `red`, khôi phục `blue`, cổng 8081, restart `unless-stopped`) và apply.

### A5. Thí nghiệm: drift — ai đó sửa bằng tay

**D1 — Container bị xóa tay:**

```bash
docker rm -f tf07-web-green
terraform plan
```

❓ Ký hiệu gì cho `docker_container.web["green"]`? Chạy `terraform plan -refresh-only` — khác gì?

```bash
terraform apply -auto-approve     # Terraform tạo lại container
```

**D2 — Container bị dừng tay:**

```bash
docker stop tf07-web-blue
terraform plan
```

❓ Plan đề xuất gì? Đọc mô tả thuộc tính `must_run` trong tài liệu provider để giải thích. Apply rồi kiểm tra `docker ps`.

**D3 — Thứ Terraform KHÔNG quản lý:**

```bash
docker run -d --name tf07-intruder --network tf07-net nginx:1.30-alpine
terraform plan
```

❓ Plan có nhắc tới `tf07-intruder` không? Vì sao? Điều này nói gì về giới hạn của Terraform? (Gợi ý: Terraform chỉ biết thứ có trong **state**.)

❓ Trong lúc `tf07-intruder` còn nối vào `tf07-net`, nếu chạy `terraform destroy` thì bước xóa network sẽ ra sao? (Gợi ý: Docker từ chối xóa network còn container đang nối.) Muốn kiểm chứng thì cứ chạy `terraform destroy`, đọc lỗi, rồi `terraform apply` để dựng lại — Terraform tạo lại phần đã xóa.

> Lỗi Terraform in ra **không** nói thẳng nguyên nhân: provider chờ network biến mất trong 30 giây rồi báo `Error: timeout while waiting for state to become 'removed' (last state: 'pending', timeout: 30s)` (chạy thật với provider 4.6, 2026-10-31). Muốn biết **vì sao**, hỏi thẳng công cụ bên dưới: `docker network rm tf07-net` → `Error response from daemon: error while removing network: network tf07-net id … has active endpoints`. Đây là kỹ năng debug quan trọng: thông báo của lớp trên (Terraform) thường chung chung, lớp dưới (Docker/AWS API) mới nói rõ.

Xóa kẻ lạ: `docker rm -f tf07-intruder`, rồi `terraform plan` phải báo `No changes` (hoặc chỉ đề xuất dựng lại phần bạn vừa destroy).

### A6. Thí nghiệm: `prevent_destroy`

Thêm vào `docker_volume.logs`:

```hcl
  lifecycle {
    prevent_destroy = true
  }
```

```bash
terraform plan -destroy
```

❓ Thông báo lỗi nói gì? Vì sao đây là tính năng **tốt** cho volume chứa log/dữ liệu?

Xóa block `lifecycle` (để bước A7 dọn được), `terraform plan` phải báo `No changes`.

### A7. Dọn dẹp

```bash
terraform destroy          # đọc plan: N to destroy, gõ yes
docker ps -a --filter name=tf07-       # rỗng
docker network ls --filter name=tf07-  # rỗng
docker volume ls --filter name=tf07-   # rỗng
docker image ls nginx:1.30-alpine      # vẫn còn — vì keep_locally = true
terraform state list                   # rỗng
```

Giữ lại thư mục `lab-01` (code) để làm bài tập. Có thể xóa `generated/`, `plan.tfplan`.

---

## Phần B — Terraform Get Started AWS (chính thức)

Làm theo bộ hướng dẫn chính thức [Get Started – AWS](https://developer.hashicorp.com/terraform/tutorials/aws-get-started) của HashiCorp, các bài **Create infrastructure → Manage infrastructure → Destroy infrastructure**. Bỏ qua bài cuối *Collaborate using HCP Terraform* (cần tài khoản HCP; giáo trình dùng S3 backend ở [bài 03](../03-terraform-state-backend.md)).

### ⚠️ Ước tính chi phí

| Tài nguyên | Đơn giá Singapore (kiểm tra 2026-10-31) | Trong lab |
|---|---|---|
| EC2 `t3.micro` | 0,0132 USD/giờ | ≤ 1 giờ |
| Public IPv4 | 0,005 USD/giờ | ≤ 1 giờ |
| EBS gốc (vài GB gp3) | rất nhỏ theo giờ | ≤ 1 giờ |
| **Tổng** | | **dưới 0,05 USD** (trừ vào credit Free plan) |

Đặt hẹn giờ 60 phút. Hết giờ mà chưa xong: `terraform destroy` trước, làm tiếp sau.

### B1. Ba điều chỉnh bắt buộc so với hướng dẫn gốc

Hướng dẫn gốc (kiểm tra 2026-10-31) dùng region `us-west-2`, instance `t2.micro` và xác thực bằng `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. Với tài khoản của bạn:

| Hướng dẫn gốc | Bạn dùng | Lý do |
|---|---|---|
| `region = "us-west-2"` | `region = "ap-southeast-1"` | Mọi thứ của giáo trình ở Singapore; `find-leftovers.sh` quét đúng chỗ |
| `instance_type = "t2.micro"` | `instance_type = "t3.micro"` | Tài khoản tạo sau 15/7/2025: `t2.micro` **không** nằm trong danh sách Free Tier eligible ([AWS 04](../../06-AWS/04-ec2.md)) |
| Biến môi trường access key | `aws login --profile taskhub` + `export AWS_PROFILE=taskhub` | Không tạo access key dài hạn ([AWS 06](../../06-AWS/06-aws-cli.md)). Nếu provider báo không thấy credential → profile `credential_process` ở [bài 02 mục 4.12](../02-terraform-basics.md#412--cùng-ý-tưởng-đổi-sang-aws) |

Thêm `default_tags` vào block `provider "aws"` để `find-leftovers.sh` nhận ra:

```hcl
provider "aws" {
  region = "ap-southeast-1"
  default_tags {
    tags = {
      Project   = "taskhub"
      Env       = "lab"
      Owner     = "phuong"
      ManagedBy = "terraform"
      Lab       = "tf07-getstarted"
    }
  }
}
```

> Hướng dẫn gốc không chỉ định VPC → EC2 vào **default VPC**. Nếu bạn đã xóa default VPC ở Module 06, `apply` sẽ lỗi kiểu "no default VPC". Cách xử lý: tạo lại default VPC (`aws ec2 create-default-vpc`) hoặc thêm `subnet_id` trỏ tới `taskhub-public-a` (lấy bằng data source `aws_subnet` lọc theo tag Name — tự tra tài liệu).

### B2. Làm bài và ghi nhật ký

`[WSL]`

```bash
mkdir -p ~/devops-lab/07-terraform/getstarted-aws && cd ~/devops-lab/07-terraform/getstarted-aws
aws login --profile taskhub
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws sts get-caller-identity --query Arn --output text   # phải là phuong-admin, KHÔNG phải root
```

Trong lúc làm, ghi vào nhật ký:

- Sau `apply`: instance ID, đối chiếu bằng `aws ec2 describe-instances --filters Name=tag:Lab,Values=tf07-getstarted --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType]' --output table`.
- Ở bài *Manage infrastructure*: mỗi thay đổi cho ký hiệu plan gì? Thay đổi nào **thay thế** EC2? Dòng nào ghi `# forces replacement`?
- Hướng dẫn gốc dùng `data "aws_ami"` lọc theo owner Canonical. So sánh với cách dùng SSM public parameter ở [bài 02 mục 4.4](../02-terraform-basics.md#44--resource-và-data-source): ưu nhược điểm?

### B3. Dọn dẹp và kiểm tra (bắt buộc)

```bash
terraform destroy                      # gõ yes; đợi "Destroy complete!"
terraform state list                   # rỗng
~/devops-lab/06-aws/find-leftovers.sh ap-southeast-1
echo "exit=$?"                         # 0 = sạch
```

`find-leftovers.sh` được viết ở [AWS 06](../../06-AWS/06-aws-cli.md). Nếu chưa có script, kiểm tra tối thiểu:

```bash
aws ec2 describe-instances --filters Name=tag:Lab,Values=tf07-getstarted \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output table   # chỉ được thấy terminated
aws ec2 describe-addresses --query 'Addresses[].PublicIp' --output text          # rỗng
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text  # rỗng
```

---

## Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `Cannot connect to the Docker daemon at unix:///var/run/docker.sock` | WSL Integration tắt | Bật trong Docker Desktop (A0) |
| `Bind for 127.0.0.1:8081 failed: port is already allocated` | Cổng bận | `-var 'base_port=9081'`; tìm process: `sudo ss -ltnp \| grep 8081` |
| `invalid mount config ... bind source path does not exist` | `host_path` không tuyệt đối hoặc file chưa được tạo | Dùng `abspath()`; container phải tham chiếu `local_file` (để tạo file trước) — đừng ghi đường dẫn tay |
| Sửa `default.conf` nhưng nginx vẫn phục vụ cấu hình cũ | Bind mount một **file**: file mới có inode mới, container giữ inode cũ | Giữ block `labels` chứa hash → container được tạo lại |
| `nginx: [emerg] ...` và container restart liên tục | Cú pháp nginx sai trong `local_file.conf` | `docker logs tf07-web-blue`; sửa nội dung, apply |
| `Error: Unsupported argument` | Sai tên tham số so với schema provider | Đối chiếu tài liệu provider 4.6 |
| Phần B: `UnauthorizedOperation` / `No valid credential sources found` | Chưa `aws login`, sai profile, hoặc SDK chưa hỗ trợ profile `aws login` | `aws sts get-caller-identity`; profile `credential_process` |
| Phần B: lỗi báo instance type không được phép / không thuộc Free Tier (chữ chính xác tùy lúc — minh họa) | Dùng `t2.micro` trên tài khoản mới | Đổi `t3.micro`; kiểm tra danh sách bằng `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true` |
| Phần B: `VcpuLimitExceeded` | Máy v2/v3 đang chạy + quota 5 vCPU | Dừng máy kia trong lúc lab ([AWS 04](../../06-AWS/04-ec2.md)) |

---

## Tiêu chí hoàn thành

- [ ] Phần A: 4 file `.tf` tự gõ, giải thích được từng dòng; `terraform fmt -check` không báo gì.
- [ ] Bảng T1–T6 điền đủ: dự đoán, ký hiệu thật, container có mới không — và **giải thích** mỗi dòng bằng schema provider.
- [ ] Giải thích được thí nghiệm phụ (inode) và vai trò của `labels`.
- [ ] D1–D3: mô tả được Terraform phát hiện và **không** phát hiện được gì.
- [ ] A7: `docker ps -a`, network, volume không còn gì `tf07-`.
- [ ] Phần B: hoàn thành Create/Manage/Destroy ở `ap-southeast-1` với `t3.micro`, không dùng access key; `find-leftovers.sh` trả `exit=0`.
- [ ] Nhật ký có ít nhất một lỗi gặp phải + cách đọc lỗi + cách sửa.

---

## Câu hỏi sau lab

1. Vì sao đổi `restart_policy` không tạo lại container, còn đổi cổng thì có?
2. Đổi `message` của `green` ảnh hưởng tới bao nhiêu resource? Vì sao container không bị tạo lại mà trang vẫn đổi?
3. T6 (xóa `blue`) — nếu bạn dùng `count` thay vì `for_each`, plan sẽ khác thế nào?
4. Ở D3, Terraform không thấy `tf07-intruder`. Trên AWS, điều tương tự là gì, và bạn phát hiện bằng cách nào? (Gợi ý: tag, `find-leftovers.sh`, AWS Config.)
5. `keep_locally = true` của `docker_image` bảo vệ điều gì? Có trường hợp nào bạn muốn `false`?
6. Phần B: Terraform lưu state ở đâu? Nếu laptop hỏng giữa chừng trước khi `destroy`, bạn xóa EC2 bằng cách nào? (Đây là lý do của [bài 03](../03-terraform-state-backend.md).)
