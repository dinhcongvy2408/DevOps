# Lời giải — Checkpoint Giai đoạn 7 (Terraform & Ansible)

> Đề bài: [checkpoint.md](../checkpoint.md). Chỉ mở sau khi đã commit bài làm.
> Output trong file này là **minh họa** — câu chữ chính xác phụ thuộc phiên bản Terraform/Ansible; tìm **ý chính**.

## Mục lục

- [Phần A — Đáp án](#phần-a--đáp-án)
- [Phần B — Lời giải tham khảo](#phần-b--lời-giải-tham-khảo)
- [Phần C — Từng ticket](#phần-c--từng-ticket)
- [Mẫu nhật ký](#mẫu-nhật-ký)

---

## Phần A — Đáp án

Chấm theo **ý**, không theo câu chữ. Mỗi câu liệt kê các ý bắt buộc.

**1. State, lock file.** State là ánh xạ giữa **địa chỉ trong code** (`aws_instance.app`) và **ID thật** (`i-0abc…`), kèm thuộc tính đã biết và phụ thuộc. Không có state, Terraform không biết tài nguyên nào là "của mình" (AWS có hàng nghìn tài nguyên, không có nhãn nào đáng tin tuyệt đối), không biết thứ tự xóa, không tính được diff hiệu quả. Không commit state vì: chứa giá trị nhạy cảm dạng chữ thường (mật khẩu, khóa…), hai người cùng sửa sẽ ghi đè nhau, Git không có khóa. Lock file **phải** commit để mọi máy và CI dùng **đúng** phiên bản provider (và checksum) đã test — giống `package-lock.json`.

**2. Ký hiệu plan.** `+` tạo · `-` xóa · `~` sửa tại chỗ · `-/+` xóa rồi tạo (mặc định) · `+/-` tạo rồi mới xóa (`create_before_destroy`) · `<=` đọc data source. `# forces replacement` đánh dấu thuộc tính không sửa tại chỗ được — đổi nó buộc thay tài nguyên. Ví dụ: đổi `ami` (hoặc `user_data` khi dùng `user_data_replace_on_change`, hoặc subnet) của `aws_instance` → EC2 bị thay → mất ổ gốc (dữ liệu PostgreSQL trong volume Docker trên ổ đó!), đổi public IP → `APP_URL` sai, cần chạy lại Ansible.

**3. Locking.** Ngăn **hai lần chạy cùng ghi state** (hai người apply cùng lúc, hoặc CI và người) → state hỏng/mất tài nguyên. S3 + `use_lockfile = true`: khóa là object `<key>.tflock` cạnh file state trong cùng bucket (cần quyền Get/Put/DeleteObject trên nó). `force-unlock` **chỉ** khi chắc chắn lần chạy giữ khóa đã chết (job CI bị hủy, máy mất mạng giữa chừng) và đó là khóa của mình/team đã xác nhận. **Không bao giờ** khi một người/job khác có thể vẫn đang chạy — sẽ có hai người cùng ghi.

**4. Drift.** Hạ tầng thật khác với code/state. Nguyên nhân: sửa trên console (mở cổng SG "tạm"), script/công cụ khác đụng vào (dọn dẹp tự động, Ansible tạo tài nguyên), AWS tự đổi (instance bị retire, IP thay khi stop/start), `state rm`/sửa state. `plan -refresh-only` chỉ cho thấy **thực tế đã đổi gì so với state** và đề xuất cập nhật state theo thực tế — không đề xuất sửa hạ tầng. Dùng khi điều tra sự cố, trước khi apply sau thời gian dài không chạy, hoặc trong job phát hiện drift định kỳ.

**5. import / moved / state rm** *(bắt buộc)*.

| | Code | State | Hạ tầng | Tình huống |
|---|---|---|---|---|
| `import {}` | thêm block (và resource tương ứng) | **thêm** tài nguyên có sẵn vào state | không đổi | Bucket S3 backup tạo tay ở v2 cần Terraform quản lý ở v4 mà không mất dữ liệu |
| `moved {}` | thêm block | **đổi địa chỉ** của tài nguyên trong state | không đổi | Đổi tên resource, chuyển vào module, đổi `count` → `for_each` |
| `terraform state rm` | không (là lệnh CLI) | **xóa** địa chỉ khỏi state | không đổi — tài nguyên vẫn sống nhưng không ai quản lý | Chuyển một tài nguyên sang state/dự án khác quản lý; bỏ quản lý thứ không nên do Terraform giữ |

Ý then chốt: `import`/`moved` là **code**, đi qua PR và plan, cả team thấy; `state rm` (và `state mv`) sửa thẳng state, không để lại dấu vết trong code.

**6. count vs for_each.** `count` đánh địa chỉ theo **số thứ tự** (`node[0]`, `node[1]`); `for_each` theo **khóa** (`node["web"]`). Xóa phần tử đầu list → mọi phần tử sau dịch chỉ số → `node[0]` giờ mang cấu hình của phần tử thứ hai… → Terraform thấy thuộc tính đổi (tên, cổng) → sửa/thay hàng loạt tài nguyên không liên quan, xóa cái cuối. `for_each` theo khóa ổn định nên chỉ đúng phần tử bị bỏ mới bị xóa. Dùng `count` cho "0 hay 1 cái" (bật/tắt), `for_each` cho tập có danh tính.

**7. Module.** Một thư mục `.tf` được gọi như hàm: nhận `variable` (những gì thay đổi giữa các nơi dùng: CIDR, instance type, tên, tags), trả `output` (ID, ARN, IP mà module khác cần). Không đặt `provider`/`backend` trong module con: module phải tái sử dụng được ở nhiều region/tài khoản/môi trường — root module quyết định cấu hình đó; module có provider riêng còn gây khó khi xóa module. v4: `envs/dev/main.tf` gọi `module "network"` (trả VPC ID, subnet IDs) rồi truyền vào `module "app_server"` (SG, IAM role, EC2), root module giữ backend S3, provider với `default_tags`, và các tài nguyên dùng chung (OIDC, CloudWatch, SSM parameter).

**8. Secret** *(bắt buộc)*. v4 tạo tham số SecureString `/taskhub/dev/postgres-password` bằng `value_wo` + `value_wo_version` (write-only, cần Terraform ≥ 1.11): giá trị chỉ gửi lên AWS lúc apply, **không bao giờ** ghi vào state hay plan; đổi `value_wo_version` để Terraform gửi giá trị mới. `sensitive = true` chỉ **che khi hiển thị** (plan, output) — giá trị vẫn nằm nguyên trong state dạng chữ thường, ai đọc được state/bucket state là đọc được mật khẩu. Ephemeral (biến/resource ephemeral) cho phép giá trị chỉ tồn tại trong một lần chạy, không lưu vào state/plan — kết hợp với write-only để secret đi từ nguồn tới AWS mà không để lại dấu vết trong Terraform.

**9. Remote state S3.** Local state: chỉ một máy có, mất laptop là mất state, không khóa khi làm nhiều người/CI, không versioning. Bucket state: **versioning** (khôi phục state cũ khi bị ghi hỏng/xóa nhầm), **Block Public Access** (state chứa thông tin nhạy cảm), **mã hóa** (SSE-S3 mặc định + `encrypt = true`), **policy từ chối non-TLS** (`aws:SecureTransport = false` → Deny), hạn chế IAM ai đọc/ghi được. "Con gà và quả trứng": bucket state không thể nằm trong state mà nó chứa → tạo bằng thư mục `bootstrap/` dùng **local state** (hoặc tạo tay), chạy một lần, rồi mọi thứ khác dùng backend S3.

**10. Idempotent** *(bắt buộc)*. Chạy một lần hay nhiều lần cho **cùng kết quả**, lần sau không đổi gì nếu hệ thống đã đúng. `shell: echo >> file` mỗi lần **thêm** một dòng — trạng thái cuối phụ thuộc số lần chạy; Ansible cũng không biết nó có thay đổi gì không nên luôn báo `changed`. `copy`/`lineinfile`/`template` mô tả **trạng thái mong muốn**, so sánh với hiện tại và chỉ sửa khi khác. Chứng minh: chạy playbook hai lần liên tiếp, lần hai recap `changed=0` cho mọi host (và `--check --diff` không có khác biệt).

**11. Handler.** Chạy **một lần**, ở cuối play (hoặc khi `meta: flush_handlers`), **chỉ khi** có task notify nó **và task đó báo changed**. Không chạy vì: task không thay đổi gì (file đã đúng từ lần chạy trước — đúng bẫy của ticket #7103); thiếu `notify`/sai tên handler; play thất bại trước khi tới cuối (trừ khi `--force-handlers`). Nginx đọc cấu hình **lúc khởi động/reload** — file trên đĩa đổi nhưng process vẫn dùng cấu hình cũ trong bộ nhớ, nên Ansible xanh mà hệ thống không đổi.

**12. Inventory.** Tĩnh: danh sách viết tay, phải sửa khi máy đổi. Động (`amazon.aws.aws_ec2`): hỏi AWS API mỗi lần chạy, lọc theo tag (`Project=taskhub`, đang `running`), tự nhóm theo tag — IP đổi sau stop/start hay máy được Terraform tạo lại thì inventory vẫn đúng. `hosts: webservers` không khớp nhóm nào → Ansible **chỉ cảnh báo** ("Could not match supplied host pattern") và bỏ qua play — playbook vẫn **xanh**. Nguy hiểm vì CI/người vận hành tin là đã cấu hình xong trong khi không host nào được đụng tới. Phòng: `ansible-playbook --list-hosts`, `ansible-inventory --graph`, kiểm tra recap có đủ host.

**13. Ansible qua SSM.** Connection plugin `amazon.aws.aws_ssm`: Ansible mở phiên Session Manager tới instance (không cần cổng 22), chuyển file qua một **S3 bucket** trung gian (instance tải bằng URL ký sẵn). Cần: máy điều khiển có `session-manager-plugin`, `boto3`/`botocore`, collection `amazon.aws`, credential AWS (`aws login`); EC2 có SSM Agent đang chạy, instance role có `AmazonSSMManagedInstanceCore`, đường ra Internet tới endpoint SSM/S3 (public IP ở v4); AWS: bucket cho plugin (v4: `taskhub-ansible-ssm-<account-id>`, lifecycle xóa sau 1 ngày), quyền IAM của người chạy với `ssm:StartSession` và S3 bucket đó.

**14. Phân vai.** Ranh giới v4: **Terraform** tạo và xóa **tài nguyên AWS** (VPC, SG, IAM, EC2, S3, CloudWatch, SSM parameter) — thứ có API, cần state, có vòng đời tạo/xóa. **Ansible** cấu hình **bên trong máy** (Docker, thư mục `/opt/taskhub`, file compose, chạy `deploy.sh`) — thứ thay đổi thường xuyên, cần idempotent, không cần state. Lý do: mỗi công cụ mạnh ở phần của nó; `user_data` chỉ chạy lần boot đầu (đổi nó thường phải thay máy), còn Ansible không có state nên không biết xóa những gì nó đã tạo trên AWS. Không nên bằng Terraform: cài gói/đổi file cấu hình trong máy đang chạy (dùng `remote-exec`/`user_data` để làm config management). Không nên bằng Ansible: tạo VPC/EC2 cho production — không có plan, không có state, khó xóa sạch và khó biết drift.

---

## Phần B — Lời giải tham khảo

Đây là **một** lời giải đạt R1–R11. Lời giải khác vẫn đạt nếu thỏa yêu cầu và 6 kiểm thử.

```text
ck07b/
├── main.tf
├── inventory.tftpl
├── ansible.cfg
├── group_vars/app.yml
├── templates/index.html.j2
├── templates/site.conf.j2
├── site.yml
└── Makefile
```

`main.tf`:

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
      version = "~> 2.5"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

variable "nodes" {
  description = "Tên node => cổng trên máy host"
  type        = map(number)
  default = {
    app1 = 8381
    app2 = 8382
  }
}

resource "docker_image" "ubuntu" {
  name         = "ubuntu:24.04"
  keep_locally = true
}

resource "docker_network" "this" {
  name = "ck07b-net"
}

resource "docker_container" "node" {
  for_each = var.nodes

  name     = "ck07b-${each.key}"
  image    = docker_image.ubuntu.image_id
  command  = ["sleep", "infinity"]
  hostname = each.key

  networks_advanced {
    name = docker_network.this.name
  }

  ports {
    internal = 80
    external = each.value
    ip       = "127.0.0.1"
  }
}

resource "local_file" "inventory" {
  filename        = "${path.module}/inventory.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/inventory.tftpl", {
    hosts = [for c in docker_container.node : c.name]
  })
}

output "urls" {
  value = { for name, port in var.nodes : name => "http://127.0.0.1:${port}" }
}
```

`inventory.tftpl`:

```text
[app]
%{ for h in hosts ~}
${h}
%{ endfor ~}

[app:vars]
ansible_connection=community.docker.docker
ansible_python_interpreter=/usr/bin/python3
```

`ansible.cfg`:

```ini
[defaults]
inventory = inventory.ini
retry_files_enabled = False
```

`group_vars/app.yml`:

```yaml
app_color: blue
```

`templates/index.html.j2`:

```text
<h1>ck07b {{ inventory_hostname }} {{ app_color }}</h1>
```

`templates/site.conf.j2`:

```text
server {
    listen 80 default_server;
    root /var/www/html;
    index index.html;
    add_header X-App-Color {{ app_color }};

    location / {
        try_files $uri $uri/ =404;
    }
}
```

`site.yml`:

```yaml
---
- name: Bootstrap Python
  hosts: all
  gather_facts: false
  tasks:
    - name: Cài python3 nếu chưa có
      ansible.builtin.raw: >-
        test -x /usr/bin/python3 && echo PRESENT ||
        (apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 > /dev/null && echo INSTALLED)
      register: py_bootstrap
      changed_when: "'INSTALLED' in py_bootstrap.stdout"

- name: Web app
  hosts: app
  tasks:
    - name: Cài nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Trang chủ
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: /var/www/html/index.html
        mode: "0644"

    - name: Cấu hình site
      ansible.builtin.template:
        src: templates/site.conf.j2
        dest: /etc/nginx/sites-available/default
        mode: "0644"
      notify: Reload nginx

    - name: Khởi động nginx nếu chưa chạy (container không có systemd)
      ansible.builtin.command: nginx
      args:
        creates: /run/nginx.pid

  handlers:
    - name: Reload nginx
      ansible.builtin.shell: nginx -t && nginx -s reload
```

`Makefile` (dòng lệnh phải thụt bằng **Tab**):

```make
.PHONY: up check down

up:
	terraform init -input=false
	terraform apply -auto-approve -input=false
	ansible-playbook site.yml

check:
	@terraform output -json urls \
	  | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).values()))' \
	  | while read -r url; do echo "== $$url"; curl -fsS "$$url" || exit 1; done

down:
	terraform destroy -auto-approve -input=false
	rm -f inventory.ini
```

Điểm hay bị sai:

- **R4:** inventory viết tay thay vì sinh từ Terraform → thêm `app3` không tự có trong inventory.
- **R6:** `raw` không có `changed_when` → luôn `changed` → hỏng R9.
- **R8:** đổi màu chỉ ở trang chủ thì không cần reload (nginx đọc file tĩnh mỗi request); thay đổi **cấu hình** (header `X-App-Color`) mới cần handler. Dùng `service`/`systemd` trong container sẽ lỗi vì không có systemd.
- **Kiểm thử 5:** plan khi thêm `app3` (chạy thật, 2026-10-31): `docker_container.node["app3"] will be created` + `local_file.inventory must be replaced` → dòng tổng là `Plan: 2 to add, 0 to change, 1 to destroy.` Cái "1 to destroy" là **file inventory** bị thay (nội dung đổi → `local_file` buộc thay), không phải container. Điều kiện đạt: không có dòng nào cho `node["app1"]`/`node["app2"]`. Nếu app1/app2 bị đụng → đã dùng `count` hoặc tên phụ thuộc thứ tự.

---

## Phần C — Từng ticket

Thứ tự lộ ra: #7101 chặn plan → #7102 hiện trong plan → #7103 khi chạy playbook (hai nguyên nhân lồng nhau) → #7104 lộ ra khi chạy lại, và càng rõ khi bạn sửa xong handler.

### 🎫 #7101 — Output lộ giá trị nhạy cảm

**Triệu chứng** (minh họa):

```text
│ Error: Output refers to sensitive values
│
│   on outputs.tf line 6:
│    6: output "db_password" {
│
│ To reduce the risk of accidentally exporting sensitive data that was intended to be only internal,
│ Terraform requires that any root module output containing sensitive data be explicitly marked as
│ sensitive, to confirm your intent.
```

**Nguyên nhân:** `random_password.result` là giá trị nhạy cảm; output gốc tham chiếu nó mà không khai báo `sensitive = true`.

**Sửa:**

```hcl
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
```

**Phải hiểu thêm** (ghi vào nhật ký): `terraform output -raw db_password` vẫn in mật khẩu, và nó nằm nguyên trong `terraform.tfstate`. `sensitive` chỉ chống lộ **trên màn hình/log CI**. Cách đúng hơn với mật khẩu thật: không xuất output này; lưu vào kho secret (v4: SSM SecureString bằng `value_wo`), ứng dụng đọc từ đó. Xóa hẳn output cũng đạt nếu bạn giải thích — nhưng verify.sh mục 4 kiểm tra output tồn tại và bị che, theo đúng yêu cầu ticket.

### 🎫 #7102 — `count` dịch chỉ số

**Triệu chứng** (minh họa, rút gọn):

```text
  # docker_container.node[0] must be replaced
-/+ resource "docker_container" "node" {
      ~ name     = "ck07-api" -> "ck07-worker" # forces replacement
  # docker_container.node[1] must be replaced
      ~ name     = "ck07-worker" -> "ck07-web" # forces replacement
  # docker_container.node[2] will be destroyed
Plan: 2 to add, 0 to change, 3 to destroy.
```

**Cách tìm:** so `terraform state list` (`node[0]`, `node[1]`, `node[2]`) với `var.services` mới (`["worker", "web"]`). Bỏ phần tử đầu → mọi chỉ số dịch lên.

**Hậu quả nếu apply:** `ck07-web` bị tạo lại → nginx cài từ sprint trước **mất** (container mới từ image ubuntu sạch), cổng 8280 gián đoạn.

**Sửa:** chuyển sang `for_each` và khai báo đường di chuyển trong state:

```hcl
resource "docker_container" "node" {
  for_each = toset(var.services)

  name     = "ck07-${each.key}"
  image    = docker_image.ubuntu.image_id
  command  = ["sleep", "infinity"]
  hostname = each.key

  networks_advanced {
    name = docker_network.ck07.name
  }

  dynamic "ports" {
    for_each = each.key == "web" ? [1] : []
    content {
      internal = 8080
      external = var.web_port
      ip       = "127.0.0.1"
    }
  }
}

moved {
  from = docker_container.node[1]
  to   = docker_container.node["worker"]
}

moved {
  from = docker_container.node[2]
  to   = docker_container.node["web"]
}
```

Plan mong đợi: hai dòng `has moved to`, **`node[0]` (api) will be destroyed**, `Plan: 0 to add, 0 to change, 1 to destroy`. Apply. `ck07-api` biến mất, hai node kia giữ ID.

Cách cũ hơn là `terraform state mv 'docker_container.node[1]' 'docker_container.node["worker"]'` — đạt kết quả tương tự nhưng sửa thẳng state, không qua review; `moved` là cách nên dùng.

### 🎫 #7103 — Playbook xanh mà không làm gì (hai nguyên nhân)

**Nguyên nhân 1 — sai tên nhóm.** Recap (minh họa):

```text
[WARNING]: Could not match supplied host pattern, ignoring: webservers

PLAY [Cấu hình web server] *****************************************************
skipping: no hosts matched

PLAY RECAP *********************************************************************
ck07-web     : ok=1    changed=0    unreachable=0    failed=0    skipped=0 ...
ck07-worker  : ok=1    changed=0    unreachable=0    failed=0    skipped=0 ...
```

`ck07-web` chỉ có `ok=1` (play bootstrap). Inventory có nhóm `[web]`, play viết `hosts: webservers`. Kiểm chứng: `ansible-inventory --graph`, `ansible-playbook site.yml --list-hosts`. Sửa: `hosts: web`.

**Nguyên nhân 2 — template đổi cổng nhưng không reload.** Sau khi sửa tên nhóm, lần chạy đầu: task "Cấu hình site" báo `changed` (listen 80 → 8080), nhưng nginx đã chạy từ trước nên vẫn nghe cổng 80; task "Khởi động nginx" báo `ok` (không phải `skipped` — chạy với `-v` sẽ thấy `"msg": "Did not run command since '/run/nginx.pid' exists"`). `curl 127.0.0.1:8280` vẫn lỗi (cổng 8280 trỏ vào 8080 trong container, nơi chưa ai nghe). Kiểm chứng:

```bash
docker exec ck07-web sh -c 'cat /etc/nginx/sites-available/default | grep listen'   # 8080
docker exec ck07-web sh -c 'cat /proc/net/tcp | head'   # hoặc cài iproute2 rồi ss -ltn: chỉ thấy :80 (0050)
```

Sửa: thêm `notify: Reload nginx` cho task template (handler đã có sẵn, chỉ chưa ai gọi).

**Bẫy tiếp theo:** chạy lại sau khi thêm `notify` — template **không** báo changed nữa (file đã đúng từ lần trước) → handler **không** chạy → vẫn cổng 80. Handler chỉ chạy khi task notify **thay đổi** gì đó. Cách xử lý đúng một lần: lệnh ad-hoc, giải thích trong nhật ký:

```bash
ansible web -m ansible.builtin.shell -a 'nginx -t && nginx -s reload'
```

Nếu lệnh này báo `ck07-web | FAILED | rc=1` kèm `[emerg] ... "server_tokens" directive is duplicate` → bạn đã chạm #7104.

### 🎫 #7104 — Task không idempotent

**Triệu chứng:** mỗi lần chạy, task "Hardening" báo `changed`; `docker exec ck07-web cat /etc/nginx/conf.d/hardening.conf` có nhiều dòng `server_tokens off;`; `docker exec ck07-web nginx -t` (chạy thật, 2026-10-31 — thời gian/PID sẽ khác):

```text
2026/10/31 09:15:06 [emerg] 3779#3779: "server_tokens" directive is duplicate in /etc/nginx/conf.d/hardening.conf:2
nginx: configuration file /etc/nginx/nginx.conf test failed
```

**Nguyên nhân:** `shell: echo ... >>` **nối thêm** mỗi lần chạy. Lần đầu vô hại (một dòng); từ lần hai cấu hình trùng lặp, chỉ lộ ra khi nginx được reload/khởi động lại — tức là đúng lúc bạn sửa #7103.

**Sửa:** quản lý **toàn bộ** file bằng `copy` (đưa file về đúng một dòng, xóa luôn các dòng trùng đã có) và notify handler:

```yaml
    - name: Hardening — ẩn phiên bản nginx
      ansible.builtin.copy:
        dest: /etc/nginx/conf.d/hardening.conf
        content: "server_tokens off;\n"
        mode: "0644"
      notify: Reload nginx
```

Vì sao không dùng `lineinfile`: nó đảm bảo dòng **có mặt**, nhưng không dọn các dòng trùng đã tồn tại → `nginx -t` vẫn lỗi. Lần chạy này task báo `changed` (sửa file) → handler reload → nginx nghe 8080 với cấu hình hợp lệ — cũng giải quyết luôn "bẫy tiếp theo" của #7103.

**Kiểm tra cuối:** chạy playbook hai lần — lần đầu sau khi sửa `ok=8 changed=2` có `RUNNING HANDLER [Reload nginx]`, lần hai `ck07-web : ok=7 changed=0 failed=0` (chạy thật; số `ok` có thể khác tùy cách bạn viết), `curl 127.0.0.1:8280` trả `ck07 OK from ck07-web`, `verify.sh` 7/7.

---

## Mẫu nhật ký

```markdown
### 🎫 #7102 — Plan muốn thay ck07-worker và ck07-web

- Triệu chứng: `docker_container.node[0] must be replaced` — `name = "ck07-api" -> "ck07-worker" # forces replacement`; Plan: 2 to add, 3 to destroy.
- Giả thuyết: đồng nghiệp chỉ bỏ "api" khỏi list → chỉ số count dịch chuyển.
- Kiểm chứng: `terraform state list` → node[0..2]; `grep default variables.tf` → ["worker","web"].
- Nguyên nhân gốc: resource dùng `count` theo list; địa chỉ gắn với chỉ số chứ không gắn với tên dịch vụ.
- Cách sửa: `for_each = toset(var.services)` + 2 block `moved` (node[1]→["worker"], node[2]→["web"]). Plan: 2 moved, 1 destroy (api). ID container worker/web không đổi (`docker inspect -f '{{.Id}}'` trước/sau).
- Vì sao không apply plan cũ rồi chạy lại Ansible: ck07-web bị tạo lại → gián đoạn, mất mọi thứ trong container; với EC2 thật là mất ổ gốc và IP.
- Phòng tránh: tập tài nguyên có danh tính luôn dùng `for_each`; review plan trong PR, mọi `replace`/`destroy` ngoài mô tả PR là cờ đỏ.
```
