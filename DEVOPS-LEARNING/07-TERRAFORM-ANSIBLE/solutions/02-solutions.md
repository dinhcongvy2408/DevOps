# Lời giải — 02. Terraform cơ bản

> Chỉ mở sau khi đã tự làm. Bài: [02-terraform-basics.md](../02-terraform-basics.md)

## Mục lục

- [Thí nghiệm mục 9](#thí-nghiệm-mục-9)
- [Câu hỏi kiểm tra kiến thức (mục 13)](#câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Bài tập tự làm (mục 14)](#bài-tập-tự-làm-mục-14)

---

## Thí nghiệm mục 9

**Bước 1.** Plan có 1 dòng `+` (`local_file.hello`). Không có `<=` vì cấu hình không có data source nào.

**Bước 2.** (a) An — `-var` ưu tiên cao nhất. (b) Bình — chỉ có `TF_VAR_who`. (c) **Chi** — `terraform.tfvars` (ưu tiên 4) thắng `TF_VAR_` (ưu tiên 5). (d) Dũng — `-var` thắng tất cả. Đổi `content` → `-/+` với `# forces replacement`: `local_file` không có thao tác "sửa nội dung tại chỗ" trong schema, mọi thay đổi `content` đều là xóa rồi tạo lại file.

**Bước 3.** Cả hai lần đều đề xuất `+` tạo lại. Bước refresh của provider `local` đọc file thật, so checksum với giá trị đã lưu; khác hoặc không tìm thấy file → coi như resource đã mất khỏi thực tế → plan tạo lại. Nếu máy bạn ra kết quả khác (ví dụ `-/+` cho trường hợp sửa file), ghi lại phiên bản provider và kết quả — hành vi phát hiện drift là của từng provider.

**Bước 4.** `by_count`: `count-0` không đổi; `count-1` bị thay (`banana` → `cherry`, `-/+`); `count-2` bị xóa. `by_each`: chỉ `each-banana.txt` bị xóa; `apple`, `cherry` giữ nguyên vì địa chỉ của chúng là `by_each["apple"]`, `by_each["cherry"]` — không phụ thuộc vị trí trong list.

**Bước 5.** Trong output của `terraform graph` có cạnh dạng `"output.path" -> "local_file.hello"` (tên node có thể có tiền tố như `[root]` tùy phiên bản) — output phụ thuộc resource.

**Bước 6.** Mảng `resources` rỗng. File state vẫn còn vì nó còn chứa metadata (`version`, `terraform_version`, `serial`, `lineage`…). `serial` tăng sau mỗi lần ghi state; `lineage` là định danh duy nhất của "dòng đời" state này — bài 03 dùng lại hai trường này.

---

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Provider là plugin dịch resource trong HCL thành lời gọi API của một nền tảng. Terraform core chỉ biết đọc cấu hình, tính đồ thị, so sánh state và gọi provider qua gRPC. Tách như vậy để core không phải biết hàng nghìn API khác nhau, và mỗi nền tảng tự phát hành provider theo nhịp riêng.

**2.** Resource: Terraform tạo/sửa/xóa và ghi vào state (ví dụ `aws_instance.app`, `aws_security_group.web`). Data source: chỉ đọc thứ đã có (ví dụ `data.aws_ssm_parameter.ubuntu_ami` lấy ID AMI Ubuntu 24.04, `data.aws_caller_identity.current` lấy account ID để đặt tên bucket `taskhub-backups-<account-id>`).

**3.** `~> 4.6` = `>= 4.6, < 5.0` (4.6.0, 4.7.3, 4.99…). `~> 4.6.0` = `>= 4.6.0, < 4.7.0` (chỉ bản vá của 4.6).

**4.** Lock file ghi phiên bản và hash provider đã chọn → mọi máy/CI dùng đúng bản đó. Commit lock file. Không commit `.terraform/` (provider tải về, tạo lại bằng `init`) và **không bao giờ** commit `terraform.tfstate` (có thể chứa dữ liệu nhạy cảm, và state cục bộ không chia sẻ an toàn được — bài 03).

**5.** Từ cao xuống thấp: `-var`/`-var-file` (theo thứ tự viết) → `*.auto.tfvars` (theo thứ tự tên) → `terraform.tfvars.json` → `terraform.tfvars` → `TF_VAR_` → `default`. `terraform.tfvars` thắng `TF_VAR_x`.

**6.** Không. `sensitive` chỉ ẩn giá trị khỏi output CLI; giá trị **vẫn lưu trong state**. `ephemeral` (1.10+) không ghi vào state lẫn file plan, nhưng chỉ dùng được ở nơi "tạm thời" như write-only argument (`value_wo`), provider configuration, hay resource/output ephemeral khác.

**7.** `count` đặt danh tính theo **vị trí**; xóa phần tử giữa làm các phần tử sau trượt index → Terraform hiểu là đổi cấu hình của các index đó (thay thế) và xóa index cuối. `for_each` đặt danh tính theo **key**; xóa key nào thì chỉ resource đó bị xóa. Ví dụ subnet `a, b, c` bằng `count`: bỏ `b` → subnet `c` (index 2 → 1) bị thay thế → mọi EC2 trong subnet `c` bị ảnh hưởng.

**8.** Khi có phụ thuộc thật mà code không thể hiện bằng tham chiếu — ví dụ user data của EC2 cần policy đã gắn xong vào role, trong khi `aws_instance` chỉ tham chiếu instance profile. Dùng tràn lan làm đồ thị kém chính xác (Terraform phải coi giá trị phụ thuộc là "chưa biết" lâu hơn), plan chậm và khó đọc, và che giấu thiết kế.

**9.** `-/+` = destroy rồi create — thay thế. Tìm dòng thuộc tính có chú thích `# forces replacement` trong chi tiết của resource đó.

**10.** Đảm bảo thứ được apply **chính xác** là thứ đã được đọc/duyệt; nếu state hoặc thực tế đã đổi, apply từ chối (plan cũ). Dùng trong CI: job plan lưu file, người duyệt, job apply dùng đúng file. File plan **nhạy cảm**: chứa toàn bộ cấu hình và giá trị biến.

**11.** Chặn mọi plan muốn xóa resource đó (kể cả `terraform destroy` và thay thế `-/+`). **Không** chặn khi bạn xóa cả block resource khỏi code (lúc đó không còn `lifecycle` nào để đọc), không chặn xóa bằng tay trên console/CLI.

**12.** Bản mới được tạo **trước** khi bản cũ bị xóa → hai bản cùng tồn tại trong chốc lát. Resource yêu cầu tên duy nhất (SG trong cùng VPC, IAM role, bucket S3…) sẽ lỗi trùng tên. Cách xử lý thường gặp: dùng `name_prefix` thay vì `name`.

**13.** (1) Drift: ai đó xóa/dừng/sửa container ngoài Terraform. (2) Một thuộc tính phụ thuộc giá trị thay đổi theo thời gian (ví dụ `docker_image` với tag trỏ sang image mới, AMI mới qua data source). (3) Perpetual diff: giá trị trong code khác dạng giá trị API trả về. Ngoài ra: đổi phiên bản provider có thay đổi schema.

**14.** Thành công và **có thay đổi** (thực tế lệch code, hoặc code mới chưa apply). Dùng trong CI/cron để phát hiện drift: exit 2 → gửi cảnh báo.

**15.** Theo chuỗi credential của AWS SDK: biến môi trường, profile trong `~/.aws/config`/`credentials` (`AWS_PROFILE`), credential của container/instance (IAM role)… Giáo trình không dùng `AWS_ACCESS_KEY_ID` vì đó là access key **dài hạn**: lộ một lần (commit nhầm, log, máy bị nhiễm mã độc) là lộ cho tới khi bạn phát hiện và xóa. `aws login` cấp credential tạm thời, tự hết hạn.

---

## Bài tập tự làm (mục 14)

### Bài 1 — Đọc schema

```hcl
resource "docker_image" "nginx" {
  name         = "nginx:1.30-alpine"
  keep_locally = true
}

resource "docker_container" "ex1" {
  name    = "tf07-ex1"
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"
  env     = ["TZ=Asia/Ho_Chi_Minh"]

  ports {
    internal = 80
    external = 8090
    ip       = "127.0.0.1"
  }
}
```

Điểm hay sai: `env` là **set chuỗi** dạng `KEY=VALUE`, không phải map; `ip` mặc định `0.0.0.0` nếu bỏ qua (mở cho mọi interface); `image` nhận **ID** image (`image_id`), không phải tên.

### Bài 2 — Biến có kiểm tra

```hcl
variable "env" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env chỉ nhận dev hoặc prod."
  }
}

locals {
  instance_type = var.env == "prod" ? "t3.small" : "t3.micro"
}

output "instance_type" {
  value = local.instance_type
}
```

`terraform console -var env=prod` → `local.instance_type` = `"t3.small"`. `terraform plan -var env=staging` → `Error: Invalid value for variable` kèm `env chỉ nhận dev hoặc prod.`

### Bài 3 — `count` → `for_each` không phá gì

Xóa `by_count`, thêm `by_each2` với `for_each = toset(var.fruits_list)` và **cùng** `filename = "${path.module}/count-${index(var.fruits_list, each.key)}.txt"` để nội dung/tên file giữ nguyên, rồi khai báo cho Terraform biết địa chỉ cũ ↔ mới:

```hcl
moved {
  from = local_file.by_count[0]
  to   = local_file.by_each2["apple"]
}
moved {
  from = local_file.by_count[1]
  to   = local_file.by_each2["banana"]
}
moved {
  from = local_file.by_count[2]
  to   = local_file.by_each2["cherry"]
}
```

Plan đạt yêu cầu khi chỉ có các dòng `has moved to` và `Plan: 0 to add, 0 to change, 0 to destroy.` Nếu tên file đổi theo key mới (ví dụ `each-apple.txt`), `local_file` vẫn bị thay — `moved` chỉ đổi **địa chỉ trong state**, không làm thuộc tính "forces replacement" biến mất.

### Bài 4 — Đọc plan

1 resource bị thay thế (`aws_instance.app`), do **hai** thuộc tính: `ami` (AMI mới — thường do data source lấy bản mới nhất) và `user_data` đổi nội dung. Hậu quả: EC2 cũ bị terminate → mọi dữ liệu trên ổ gốc (kể cả volume PostgreSQL nếu nằm trên ổ gốc!) mất, **public IP đổi** (`known after apply`) → DNS/`APP_URL` sai, ứng dụng ngừng phục vụ từ lúc máy cũ tắt tới khi máy mới cài xong. Cân nhắc: `ignore_changes = [ami]` để chủ động đổi AMI; tách dữ liệu ra EBS riêng hoặc có backup/restore (v5); Elastic IP hoặc DNS.

### Bài 5 — `check-drift.sh`

```bash
#!/usr/bin/env bash
# Kiểm tra drift: chạy được từ cron. Không dùng -e vì exit 2 của terraform plan là "thành công có thay đổi",
# -e sẽ làm script dừng ngay tại đó trước khi kịp phân loại.
set -uo pipefail

dir="${1:-$HOME/devops-lab/07-terraform/lab-01}"
cd "$dir" || { echo "ERROR: không vào được $dir"; exit 1; }

terraform plan -detailed-exitcode -input=false -no-color > /tmp/drift-plan.txt 2>&1
rc=$?

case "$rc" in
  0) echo "OK: không lệch" ;;
  2) echo "DRIFT: có thay đổi"; grep -E '^\s+# .* (must be|will be)' /tmp/drift-plan.txt ;;
  *) echo "ERROR: terraform plan lỗi (exit $rc)"; tail -20 /tmp/drift-plan.txt ;;
esac
exit "$rc"
```

`-input=false`: không bao giờ hỏi nhập biến (cron không có bàn phím). `-no-color`: log không lẫn mã màu.

### Bài 6 — Dịch sang AWS trên giấy

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
}

variable "public_subnets" {
  type = map(string)
  default = {
    a = "10.20.1.0/24"
    b = "10.20.2.0/24"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "taskhub-vpc" }
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = "ap-southeast-1${each.key}"
  map_public_ip_on_launch = true
  tags                    = { Name = "taskhub-public-${each.key}" }
}

resource "aws_security_group" "web" {
  name   = "taskhub-web-sg"
  vpc_id = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
```

`terraform validate` chạy được **không cần** credential: validate chỉ kiểm tra cấu hình, không cấu hình provider và không gọi API. `terraform plan` thì cần credential (phải đọc thực tế). Chú ý: chưa có IGW/route table → subnet này **chưa thật sự public** dù `map_public_ip_on_launch = true` — đúng bài học "public là do route table" ở [AWS 03](../../06-AWS/03-vpc-networking.md). Lab-02 viết đầy đủ.
