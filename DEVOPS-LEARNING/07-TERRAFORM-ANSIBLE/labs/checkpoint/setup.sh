#!/usr/bin/env bash
# Checkpoint GĐ 7 — Phần C (break-fix): Terraform + Ansible trên container cục bộ. Chi phí 0 USD.
# Tạo ~/devops-lab/07-terraform/ck07 rồi mô phỏng thay đổi của "đồng nghiệp".
# KHÔNG đọc file này trước khi nộp bài.
#
# Cần: terraform, ansible-playbook (+ collection community.docker), docker trong WSL, curl.
# Biến môi trường tùy chọn: CK07_PORT (mặc định 8280) nếu cổng đã bị chiếm.

set -euo pipefail

BASE="${HOME}/devops-lab/07-terraform"
DIR="${BASE}/ck07"
STATE_DIR="${BASE}/.ck07"
PORT="${CK07_PORT:-8280}"

die() { echo "❌ $*" >&2; exit 1; }

for cmd in terraform ansible-playbook ansible-galaxy docker curl; do
  command -v "$cmd" > /dev/null 2>&1 || die "Thiếu lệnh '$cmd' (cài theo bài 02 và bài 05 của Module 07)."
done
docker info > /dev/null 2>&1 || die "Không nói chuyện được với Docker trong WSL (bật WSL integration — Module 04, bài 01)."
ansible-galaxy collection list community.docker 2> /dev/null | grep -q community.docker \
  || die "Chưa có collection community.docker: ansible-galaxy collection install community.docker"

[[ -e "$DIR" ]] && die "$DIR đã tồn tại — xem mục Dọn dẹp của Phần C trong checkpoint.md."
[[ -e "$STATE_DIR" ]] && die "$STATE_DIR đã tồn tại — xem mục Dọn dẹp của Phần C trong checkpoint.md."
[[ -n "$(docker ps -aq --filter 'name=^ck07-')" ]] && die "Đã có container 'ck07-*' — xóa trước (mục Dọn dẹp)."
docker network inspect ck07-net > /dev/null 2>&1 && die "Network 'ck07-net' đã tồn tại — xóa trước (mục Dọn dẹp)."

mkdir -p "$DIR/templates" "$STATE_DIR"
cd "$DIR"

# ---------- Terraform: 3 node ubuntu, node "web" publish cổng ----------
cat > versions.tf <<'EOF'
terraform {
  required_version = "~> 1.17"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}
EOF

cat > variables.tf <<EOF
variable "services" {
  description = "Danh sách node của hệ thống ck07"
  type        = list(string)
  default     = ["api", "worker", "web"]
}

variable "web_port" {
  description = "Cổng trên máy host trỏ vào cổng 8080 của node web"
  type        = number
  default     = ${PORT}
}
EOF

cat > main.tf <<'EOF'
resource "docker_image" "ubuntu" {
  name         = "ubuntu:24.04"
  keep_locally = true
}

resource "docker_network" "ck07" {
  name = "ck07-net"
}

resource "docker_container" "node" {
  count = length(var.services)

  name     = "ck07-${var.services[count.index]}"
  image    = docker_image.ubuntu.image_id
  command  = ["sleep", "infinity"]
  hostname = var.services[count.index]

  networks_advanced {
    name = docker_network.ck07.name
  }

  dynamic "ports" {
    for_each = var.services[count.index] == "web" ? [1] : []
    content {
      internal = 8080
      external = var.web_port
      ip       = "127.0.0.1"
    }
  }
}

resource "random_password" "db" {
  length  = 20
  special = false
}
EOF

echo "▶ Dựng trạng thái ban đầu (tải provider + image, 1–3 phút)..."
terraform init -input=false > "$STATE_DIR/init.log" 2>&1 \
  || { cat "$STATE_DIR/init.log" >&2; die "terraform init thất bại."; }
terraform apply -auto-approve -input=false > "$STATE_DIR/apply.log" 2>&1 \
  || { tail -n 30 "$STATE_DIR/apply.log" >&2; die "terraform apply thất bại (cổng $PORT bị chiếm? đặt CK07_PORT rồi dọn dẹp và chạy lại)."; }

# "Sprint trước": node web đã có nginx phục vụ ở cổng 80 bên trong container.
echo "▶ Cài nginx sẵn trên ck07-web như sprint trước (cần Internet, ~1 phút)..."
docker exec ck07-web sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq python3 nginx > /dev/null && nginx' \
  > "$STATE_DIR/web-bootstrap.log" 2>&1 \
  || { tail -n 20 "$STATE_DIR/web-bootstrap.log" >&2; die "Không cài được nginx trong ck07-web (kiểm tra Internet)."; }

docker inspect -f '{{.Id}}' ck07-worker > "$STATE_DIR/worker.id"
docker inspect -f '{{.Id}}' ck07-web > "$STATE_DIR/web.id"
echo "$PORT" > "$STATE_DIR/port"

# ---------- Ansible ----------
cat > ansible.cfg <<'EOF'
[defaults]
inventory = inventory.ini
host_key_checking = False
retry_files_enabled = False
EOF

cat > inventory.ini <<'EOF'
[web]
ck07-web

[workers]
ck07-worker

[all:vars]
ansible_connection=community.docker.docker
ansible_python_interpreter=/usr/bin/python3
EOF

cat > site.yml <<'EOF'
---
- name: Bootstrap Python trên mọi node
  hosts: all
  gather_facts: false
  tasks:
    - name: Cài python3 nếu chưa có
      ansible.builtin.raw: >-
        test -x /usr/bin/python3 && echo PRESENT ||
        (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 > /dev/null && echo INSTALLED)
      register: py_bootstrap
      changed_when: "'INSTALLED' in py_bootstrap.stdout"

- name: Cấu hình web server
  hosts: webservers
  vars:
    nginx_port: 8080
  tasks:
    - name: Cài nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Trang chủ
      ansible.builtin.copy:
        dest: /var/www/html/index.html
        content: "<h1>ck07 OK from {{ inventory_hostname }}</h1>\n"
        mode: "0644"

    - name: Cấu hình site (đổi cổng theo nginx_port)
      ansible.builtin.template:
        src: templates/site.conf.j2
        dest: /etc/nginx/sites-available/default
        mode: "0644"

    - name: Hardening — ẩn phiên bản nginx
      ansible.builtin.shell: echo "server_tokens off;" >> /etc/nginx/conf.d/hardening.conf

    - name: Khởi động nginx nếu chưa chạy
      ansible.builtin.command: nginx
      args:
        creates: /run/nginx.pid

  handlers:
    - name: Reload nginx
      ansible.builtin.shell: nginx -t && nginx -s reload
EOF

cat > templates/site.conf.j2 <<'EOF'
# Quản lý bởi Ansible — sửa tay sẽ bị ghi đè
server {
    listen {{ nginx_port }} default_server;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

# ---------- Thay đổi của "đồng nghiệp" ----------
sed -i 's/default     = \["api", "worker", "web"\]/default     = ["worker", "web"] # api đã ngừng dùng từ sprint này/' variables.tf

cat > outputs.tf <<'EOF'
output "web_url" {
  value = "http://127.0.0.1:${var.web_port}"
}

# Thêm cho tiện debug — anh em cần mật khẩu DB thì lấy ở đây
output "db_password" {
  value = random_password.db.result
}
EOF

cat <<MSG

✅ Môi trường Phần C đã sẵn sàng tại: $DIR
   Đọc 4 ticket trong checkpoint.md (Phần C) rồi bắt đầu:
     cd $DIR
     terraform plan
     ansible-playbook site.yml
   Kiểm tra tiến độ: bash <đường-dẫn-tới>/verify.sh
MSG
