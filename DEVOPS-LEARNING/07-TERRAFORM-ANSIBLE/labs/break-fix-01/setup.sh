#!/usr/bin/env bash
# Break-fix Terraform #1 — "Terraform đòi phá hạ tầng đang chạy"
# Tạo ~/devops-lab/07-terraform/bf07: một hệ thống nhỏ chạy bằng Docker do Terraform quản lý,
# rồi mô phỏng những gì "đồng nghiệp" đã làm với nó trong lúc bạn nghỉ phép.
#
# Chi phí: 0 USD — chỉ dùng Docker trên máy bạn (provider kreuzwerker/docker).
# Chạy trong [WSL], Docker Desktop đang chạy và đã bật WSL integration.
#
# Biến môi trường tùy chọn (khi cổng mặc định đã bị chiếm):
#   BF07_PORT_A (8091)  BF07_PORT_B (8092)  BF07_PORT_HOTFIX (8093)

set -euo pipefail

BASE="${HOME}/devops-lab/07-terraform"
DIR="${BASE}/bf07"
STATE_DIR="${BASE}/.bf07"          # thông tin cho verify.sh và dọn dẹp — đừng sửa
PORT_A="${BF07_PORT_A:-8091}"
PORT_B="${BF07_PORT_B:-8092}"
PORT_HOTFIX="${BF07_PORT_HOTFIX:-8093}"

die() { echo "❌ $*" >&2; exit 1; }

# ---------- Kiểm tra điều kiện ----------
for cmd in terraform docker curl setsid; do
  command -v "$cmd" > /dev/null 2>&1 || die "Thiếu lệnh '$cmd'. Cài theo bài 02 của Module 07 rồi chạy lại."
done

docker info > /dev/null 2>&1 \
  || die "Không nói chuyện được với Docker. Docker Desktop đã chạy và đã bật WSL integration cho distro này chưa? (Module 04, bài 01 — mục lỗi thường gặp)"

[[ -e "$DIR" ]] && die "$DIR đã tồn tại. Muốn làm lại từ đầu: xem mục 'Dọn dẹp' trong README rồi chạy lại."
[[ -e "$STATE_DIR" ]] && die "$STATE_DIR đã tồn tại (lần chạy trước chưa dọn). Xem mục 'Dọn dẹp' trong README."

if [[ -n "$(docker ps -aq --filter 'name=^bf07-')" ]]; then
  die "Đã có container tên bắt đầu bằng 'bf07-'. Xóa chúng trước (xem mục 'Dọn dẹp')."
fi
docker network inspect bf07-net > /dev/null 2>&1 && die "Network 'bf07-net' đã tồn tại. Xóa trước (xem mục 'Dọn dẹp')."
for v in bf07-shared bf07-backup; do
  docker volume inspect "$v" > /dev/null 2>&1 && die "Volume '$v' đã tồn tại. Xóa trước (xem mục 'Dọn dẹp')."
done

mkdir -p "$DIR/generated" "$STATE_DIR"
cd "$DIR"

# ---------- Mã Terraform ban đầu (trạng thái khỏe mạnh) ----------
cat > versions.tf <<'EOF'
terraform {
  required_version = "~> 1.17"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
EOF

cat > providers.tf <<'EOF'
provider "docker" {
  host = "unix:///var/run/docker.sock"
}
EOF

cat > variables.tf <<EOF
variable "port_a" {
  description = "Cổng trên máy host cho bf07-web-a"
  type        = number
  default     = ${PORT_A}
}

variable "port_b" {
  description = "Cổng trên máy host cho bf07-web-b"
  type        = number
  default     = ${PORT_B}
}
EOF

cat > main.tf <<'EOF'
resource "docker_image" "nginx" {
  name         = "nginx:1.30-alpine"
  keep_locally = true # destroy không xóa image khỏi máy
}

resource "docker_network" "bf07" {
  name = "bf07-net"
}

resource "docker_volume" "shared" {
  name = "bf07-shared"
}

# Volume dành cho script backup (sẽ dùng ở sprint sau) — hiện chưa container nào gắn vào.
resource "docker_volume" "backup" {
  name = "bf07-backup"
}

resource "local_file" "index" {
  filename = "${path.module}/generated/index.html"
  content  = "<h1>bf07 OK</h1>\n"
}

resource "docker_container" "web_a" {
  name    = "bf07-web-a"
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.port_a
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.bf07.name
  }

  volumes {
    volume_name    = docker_volume.shared.name
    container_path = "/data"
  }

  upload {
    file    = "/usr/share/nginx/html/index.html"
    content = local_file.index.content
  }
}

resource "docker_container" "web_b" {
  name    = "bf07-web-b"
  image   = docker_image.nginx.image_id
  restart = "unless-stopped"

  ports {
    internal = 80
    external = var.port_b
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.bf07.name
  }

  volumes {
    volume_name    = docker_volume.shared.name
    container_path = "/data"
  }

  upload {
    file    = "/usr/share/nginx/html/index.html"
    content = local_file.index.content
  }
}
EOF

cat > outputs.tf <<'EOF'
output "url_a" {
  value = "http://127.0.0.1:${var.port_a}"
}

output "url_b" {
  value = "http://127.0.0.1:${var.port_b}"
}

output "web_a_id" {
  value = docker_container.web_a.id
}
EOF

echo "▶ Dựng trạng thái ban đầu bằng Terraform (lần đầu sẽ tải provider, mất 1–2 phút)..."
terraform init -input=false > "$STATE_DIR/init.log" 2>&1 \
  || { cat "$STATE_DIR/init.log" >&2; die "terraform init thất bại — đọc log ở trên."; }
terraform apply -auto-approve -input=false > "$STATE_DIR/apply.log" 2>&1 \
  || { tail -n 30 "$STATE_DIR/apply.log" >&2; die "terraform apply thất bại — thường do cổng $PORT_A/$PORT_B đã bị chiếm (đặt BF07_PORT_A/BF07_PORT_B rồi dọn dẹp và chạy lại)."; }

for p in "$PORT_A" "$PORT_B"; do
  ok=0
  for _ in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:${p}/" 2> /dev/null | grep -q "bf07 OK"; then ok=1; break; fi
    sleep 1
  done
  [[ "$ok" -eq 1 ]] || die "Trạng thái ban đầu không trả lời trên cổng $p — kiểm tra 'docker ps' rồi báo lại."
done

# Ghi lại ID ban đầu của bf07-web-a để verify.sh biết container này có bị tạo lại hay không.
docker inspect -f '{{.Id}}' bf07-web-a > "$STATE_DIR/web-a.id"
printf '%s\n%s\n%s\n' "$PORT_A" "$PORT_B" "$PORT_HOTFIX" > "$STATE_DIR/ports"

# ---------- Mô phỏng "một tuần vắng mặt" ----------
# (Không đọc phần dưới nếu bạn muốn tự điều tra — mọi thứ đều tìm ra được bằng công cụ thường ngày.)
terraform state rm docker_network.bf07 > /dev/null 2>&1
docker volume rm bf07-backup > /dev/null
docker rm -f bf07-web-b > /dev/null
docker run -d --name bf07-web-b --network bf07-net --restart unless-stopped \
  -p "127.0.0.1:${PORT_HOTFIX}:80" nginx:1.30-alpine > /dev/null
sed -i 's/web_a/web_primary/g' main.tf outputs.tf

# Một lệnh `terraform apply` bị bỏ quên ở câu hỏi yes/no: nó giữ khóa state cho tới khi kết thúc.
# stdin là `sleep` nên không bao giờ nhận được "yes" — không có gì bị apply.
# (Đã thử `terraform console`: với Terraform 1.17.1 console KHÔNG giữ khóa local state.)
nohup setsid bash -c 'sleep 86400 | terraform apply -input=true' > /dev/null 2>&1 &
echo "$!" > "$STATE_DIR/holder.pid"
for _ in $(seq 1 15); do
  [[ -e .terraform.tfstate.lock.info ]] && break
  sleep 1
done

sed -i 's/version = "~> 4.6"/version = "= 4.5.0" # ghim theo production/' versions.tf

cat <<MSG

✅ Môi trường bf07 đã sẵn sàng tại: $DIR

Bối cảnh: bạn vừa đi phép một tuần về. Hệ thống bf07 (2 web nginx sau cổng $PORT_A và $PORT_B)
do Terraform quản lý. Trong tuần, vài đồng nghiệp đã "xử lý nhanh" vài việc. Trưởng nhóm nhờ bạn:
"Chạy terraform plan cho chắc trước khi mình merge thay đổi tiếp theo."

Bắt đầu:
  cd $DIR
  terraform plan

Đọc README của bài để biết luật chơi. Kiểm tra tiến độ bất kỳ lúc nào:
  bash <đường-dẫn-tới>/verify.sh
MSG
