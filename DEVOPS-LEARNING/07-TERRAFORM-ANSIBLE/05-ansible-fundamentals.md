# 05. Ansible — cấu hình máy chủ bằng code

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc (phần nền tảng) · Kiến thức cần có trước: [01. IaC là gì](01-iac-concepts.md), [Linux 03 — Permissions](../01-LINUX/03-permissions-users-groups.md), [Linux 05 — Packages & SSH](../01-LINUX/05-packages-ssh.md), [Docker 02 — Image & container](../04-DOCKER/02-images-containers.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (Python 3.12) làm **máy điều khiển**, `[Container]` 3 container `ubuntu:24.04` làm **máy được quản lý**
> Phiên bản khi viết: Ansible 14.5.0 (ansible-core 2.21.5), community.docker 5.4.0, amazon.aws 12.0.0

> 💰 **Chi phí của bài này: 0 USD.** Toàn bộ lab chạy bằng container trên máy bạn. Phần AWS (cài Docker lên EC2 qua SSM) nằm ở [Lab 03](labs/lab-03-ansible-ssm.md).
> ⚙️ **Điều kiện:** lệnh `docker` chạy được **trong WSL**. Nếu báo `Cannot connect to the Docker daemon`, bật Docker Desktop → Settings → Resources → WSL integration → Ubuntu (xem [bảng lỗi Docker bài 01](../04-DOCKER/01-vm-vs-container-architecture.md)).

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

- Giải thích mô hình của **Ansible**: **agentless** (không cài phần mềm riêng trên máy đích), **push** (máy điều khiển đẩy lệnh đi), máy điều khiển (**control node**) và máy được quản lý (**managed node**).
- Cài Ansible bằng **pipx** trên Ubuntu 24.04 và đọc được kết quả `ansible --version`.
- Viết **inventory** dạng INI và YAML: nhóm, biến theo nhóm/host, biết `group_vars/` phải đặt **ở đâu** thì Ansible mới đọc.
- Chạy lệnh **ad-hoc** và viết **playbook** gồm play, task, module, **handler**.
- Giải thích **idempotency** (chạy nhiều lần cho cùng kết quả): phân biệt `ok` và `changed`, biết vì sao `shell`/`command` phá idempotency và sửa bằng `creates:` / `changed_when:`.
- Dùng biến, **facts**, **template Jinja2**, điều kiện, vòng lặp, `become`.
- Tổ chức code thành **role**, cài **collection** bằng `requirements.yml`.
- Chọn **connection plugin** phù hợp: SSH, `community.docker.docker`, `amazon.aws.aws_ssm`.

## 2. Tại sao DevOps Engineer cần kiến thức này?

Ở v2/v3 bạn cấu hình EC2 bằng **user data** và gõ lệnh tay qua Session Manager. Cách này có ba vấn đề bạn đã gặp:

| Vấn đề ở v2/v3 | Ansible giải quyết thế nào |
|---|---|
| User data chỉ chạy **một lần** lúc boot đầu. Muốn đổi cấu hình → tạo lại máy | Playbook chạy lại **bao nhiêu lần cũng được**, chỉ sửa phần khác so với mong muốn |
| Sửa `compose.yaml` trong repo → phải vào máy cập nhật tay (giới hạn đã ghi ở [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md)) | Playbook copy file từ repo lên máy → repo là **nguồn sự thật duy nhất** |
| "Máy này cài gì, phiên bản nào?" — không ai nhớ | Playbook **là** tài liệu: đọc file là biết máy có gì |

**Terraform tạo máy, Ansible cấu hình máy.** Đây là cách chia việc phổ biến ở công ty:

| Công cụ | Trả lời câu hỏi | Ví dụ trong taskhub v4 |
|---|---|---|
| Terraform ([bài 02](02-terraform-basics.md)) | **Có những tài nguyên nào?** | VPC, SG, IAM role, EC2, S3 bucket |
| Ansible (bài này) | **Bên trong máy có gì, cấu hình ra sao?** | Docker Engine, AWS CLI, `/opt/taskhub`, chạy `deploy.sh` |

Trong phỏng vấn Junior, câu hỏi về Ansible thường xoay quanh: idempotency là gì, playbook khác ad-hoc thế nào, role dùng để làm gì, handler chạy khi nào. Tin tuyển dụng DevOps ở Việt Nam hay ghi "Ansible" cạnh "Terraform" — đây là quan sát chung, không phải thống kê.

## 3. Kiến thức nền tảng cần hiểu

| Khái niệm | Đã học ở | Dùng trong bài này |
|---|---|---|
| SSH, key, `~/.ssh/config` | [Linux 05](../01-LINUX/05-packages-ssh.md) | Ansible mặc định kết nối bằng SSH |
| `sudo`, user root | [Linux 03](../01-LINUX/03-permissions-users-groups.md) | `become: true` |
| apt, repository, GPG key | [Linux 05](../01-LINUX/05-packages-ssh.md) | Module `apt`, `deb822_repository` |
| YAML (thụt lề, list, map) | [Docker 05](../04-DOCKER/05-docker-compose.md), [CI/CD 02](../05-CICD/02-github-actions-basics.md) | Playbook, inventory YAML |
| Exit code, `set -e` | [Linux 06](../01-LINUX/06-bash-scripting.md) | Task `command` lỗi khi exit code ≠ 0 |
| Desired state (trạng thái mong muốn) | [01. IaC](01-iac-concepts.md) | Mỗi module mô tả trạng thái, không mô tả lệnh |

**Python ở hai đầu.** Ansible viết bằng Python. Máy điều khiển cần Python (ansible-core 2.21 yêu cầu **Python ≥ 3.12** — Ubuntu 24.04 có sẵn 3.12). Máy được quản lý cũng cần Python vì Ansible copy **module** (một đoạn chương trình Python) sang đó rồi chạy. Ngoại lệ: module `raw` chỉ gửi lệnh shell, không cần Python — dùng để cài Python lần đầu.

## 4. Giải thích chi tiết

### 4.1. 🟥 Ansible hoạt động thế nào

```text
 Máy điều khiển (WSL)                          Máy được quản lý
 ┌───────────────────────┐   kết nối            ┌────────────────────────┐
 │ ansible-playbook      │ ──(ssh / docker /──► │ 1. nhận file module .py │
 │  ├─ đọc inventory     │     aws_ssm)         │ 2. chạy bằng python3    │
 │  ├─ đọc playbook      │                      │ 3. trả JSON:            │
 │  └─ mỗi task:         │ ◄──── kết quả ────── │    {"changed": true,…}  │
 │     gửi module + tham số                     │ 4. xóa file tạm         │
 └───────────────────────┘                      └────────────────────────┘
```

- **Agentless:** không có tiến trình Ansible chạy thường trực trên máy đích (khác Puppet/Chef cài agent). Chỉ cần một đường kết nối + Python.
- **Push:** bạn chạy lệnh ở máy điều khiển, nó đẩy cấu hình đi. 🟦 Có chế độ ngược lại (`ansible-pull`: máy đích tự kéo playbook từ Git), không dùng trong khóa học.
- Mỗi **task** gọi một **module** với tham số. Module tự kiểm tra trạng thái hiện tại → chỉ thay đổi khi khác trạng thái mong muốn → báo `changed: true/false`.

### 4.2. 🟥 Cài đặt bằng pipx

Ubuntu 24.04 chặn `pip install` vào Python của hệ thống (PEP 668, lỗi `externally-managed-environment`). Tài liệu Ansible đưa **pipx** làm cách thay thế: mỗi ứng dụng một môi trường ảo riêng, lệnh vẫn gọi được từ mọi nơi.

```bash
# [WSL]
sudo apt update
sudo apt install -y pipx
pipx ensurepath                      # thêm ~/.local/bin vào PATH — mở terminal mới sau lệnh này
pipx install --include-deps ansible  # gói "ansible" đầy đủ: ansible-core + nhiều collection
ansible --version
```

| Gói | Gồm gì | Khi nào chọn |
|---|---|---|
| `ansible` | `ansible-core` + bộ collection cộng đồng (amazon.aws, community.docker, …) | Người mới, muốn có sẵn nhiều module |
| `ansible-core` | Chỉ lõi + `ansible.builtin` | Dự án tự quản lý collection bằng `requirements.yml` |

`--include-deps` để pipx tạo cả các lệnh của gói phụ thuộc (`ansible-playbook`, `ansible-galaxy`, … đến từ `ansible-core`). Nâng cấp sau này: `pipx upgrade --include-injected ansible`.

### 4.3. 🟥 Inventory — danh sách máy

**Inventory** liệt kê máy được quản lý và chia nhóm. Hai dạng tương đương:

```ini
# inventory.ini
[web]
web1.example.com
web2.example.com ansible_port=2222

[db]
db1.example.com

[prod:children]      # nhóm cha gồm các nhóm con
web
db

[web:vars]           # biến cho cả nhóm web
http_port=80
```

```yaml
# inventory.yml — cùng nội dung
all:
  children:
    prod:
      children:
        web:
          hosts:
            web1.example.com:
            web2.example.com:
              ansible_port: 2222
          vars:
            http_port: 80
        db:
          hosts:
            db1.example.com:
```

Luôn có hai nhóm ngầm định: `all` (mọi host) và `ungrouped` (host không thuộc nhóm nào).

**Biến theo file — nơi người mới hay sai nhất.** Thay vì ghi biến trong inventory, đặt vào thư mục:

```text
inventory.ini
group_vars/
  all.yml          ← mọi host
  web.yml          ← nhóm web
host_vars/
  web1.example.com.yml
```

⚠️ Ansible chỉ tìm `group_vars/` và `host_vars/` **ở thư mục chứa nguồn inventory** hoặc **ở thư mục chứa playbook**. Đặt cạnh `ansible.cfg` mà inventory nằm ở thư mục khác → biến **không được đọc**, không có cảnh báo nào. Đó là lý do bộ code tham khảo của taskhub đặt biến kết nối ở `inventory/group_vars/all.yml`. Biến nằm cạnh playbook ghi đè biến nằm cạnh inventory.

**Inventory động (dynamic inventory):** trên cloud, máy sinh ra và mất đi liên tục, IP đổi sau mỗi lần stop/start ([AWS bài 04](../06-AWS/04-ec2.md)). Thay vì ghi tay, một **inventory plugin** hỏi API của cloud: "cho tôi các EC2 có tag `Project=taskhub` đang chạy". Lab 03 dùng plugin `amazon.aws.aws_ec2`. Xem inventory đang có gì:

```bash
ansible-inventory -i inventory.ini --graph   # cây nhóm → host
ansible-inventory -i inventory.ini --host web2.example.com   # biến cuối cùng của một host
```

### 4.4. 🟥 Connection plugin — Ansible "đi" tới máy bằng đường nào

| Plugin | Đi bằng | Cần gì | Dùng trong khóa học |
|---|---|---|---|
| `ssh` (mặc định) | SSH, giống lệnh `ssh` | SSH key, port 22 mở | Máy chủ thông thường, máy on-premises |
| `community.docker.docker` | `docker exec` qua Docker CLI | Lệnh `docker` ở máy điều khiển, container đang chạy | **Lab của bài này** (miễn phí) |
| `amazon.aws.aws_ssm` | AWS Systems Manager Session Manager | `session-manager-plugin`, boto3, S3 bucket trung chuyển file, SSM Agent trên EC2 | **[Lab 03](labs/lab-03-ansible-ssm.md)** — taskhub v4, không mở port 22 |

Chọn bằng biến `ansible_connection` (theo host, nhóm, hoặc trong play). Playbook **không đổi** khi đổi đường kết nối — đó là điểm mạnh: lab này luyện trên container, Lab 03 chạy gần như cùng kiểu playbook lên EC2.

Inventory SSH điển hình (để bạn đọc được khi đi làm):

```ini
[app]
10.20.1.15 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/taskhub_ed25519
```

### 4.5. 🟥 Lệnh ad-hoc

Chạy **một** module lên nhiều máy, không cần file playbook:

```bash
ansible lab -m ansible.builtin.ping                 # kiểm tra kết nối + Python
ansible lab -m ansible.builtin.command -a "uptime"  # chạy một lệnh
ansible lab -m ansible.builtin.apt -a "name=tree state=present" -b   # cài gói (cần root)
```

Ad-hoc tiện để **kiểm tra nhanh** ("tất cả máy còn sống không?", "máy nào đầy disk?"). Mọi thứ cần lặp lại → viết playbook.

### 4.6. 🟥 Playbook, play, task, module, handler

```yaml
# web.yml
- name: Cài web server            # ← một PLAY: chọn host + danh sách task
  hosts: lab
  become: true
  tasks:
    - name: Cài nginx              # ← một TASK: gọi MỘT module
      ansible.builtin.apt:         # ← MODULE, viết đủ tên (FQCN)
        name: nginx
        state: present             # ← trạng thái mong muốn, không phải "lệnh cài"

    - name: Trang chủ
      ansible.builtin.template:
        src: index.html.j2
        dest: /var/www/html/index.html
      notify: Reload nginx         # ← nếu task này "changed" thì báo handler

  handlers:
    - name: Reload nginx           # ← HANDLER: chạy MỘT lần ở cuối play, chỉ khi được notify
      ansible.builtin.command: nginx -s reload
```

- **FQCN** (Fully Qualified Collection Name — tên đầy đủ): `ansible.builtin.apt` thay vì `apt`. Tránh nhầm khi hai collection có module trùng tên; ansible-lint cảnh báo nếu thiếu.
- **Handler** giải quyết bài toán: "chỉ reload nginx **khi** cấu hình thật sự đổi". 10 task cùng notify một handler → handler vẫn chỉ chạy 1 lần, ở cuối play.
- Task chạy **tuần tự từ trên xuống**, trên **mọi host song song** (mặc định 5 host một lúc — tham số `forks`). Một host lỗi → các task sau bỏ qua host đó, host khác vẫn chạy tiếp.

### 4.7. 🟥 Idempotency — trái tim của Ansible

**Idempotent**: chạy 1 lần hay 10 lần, kết quả cuối cùng như nhau, và lần thứ 2 trở đi **không thay đổi gì**.

Mỗi task báo một trong các trạng thái:

| Trạng thái | Nghĩa |
|---|---|
| `ok` | Máy đã đúng trạng thái mong muốn → không làm gì |
| `changed` | Máy chưa đúng → module đã sửa |
| `failed` | Lỗi |
| `skipping` | Điều kiện `when` sai → bỏ qua |

**Vì sao `command`/`shell` phá idempotency:** module `apt` biết kiểm tra "nginx đã cài chưa". Còn `command: echo hi >> /tmp/log` thì Ansible không biết lệnh đó làm gì → **luôn chạy, luôn báo `changed`**. Lần thứ 10 file log có 10 dòng.

Thứ tự ưu tiên khi viết task:

1. **Có module chuyên dụng → dùng module** (`apt`, `copy`, `template`, `file`, `lineinfile`, `systemd_service`, `user`…).
2. Bắt buộc dùng `command`/`shell` → **cho Ansible cách biết** khi nào không cần chạy:
   - `creates: /đường/dẫn` — file đã tồn tại thì bỏ qua (`removes:` ngược lại).
   - `changed_when: false` cho lệnh **chỉ đọc** (ví dụ `sed -n`, `docker ps`).
   - `changed_when: <điều kiện>` dựa vào output của lệnh.
3. `shell` chỉ khi cần pipe, redirect, biến shell. Còn lại dùng `command` (không qua shell → không bị lỗi trích dẫn, an toàn hơn).

**Chạy thử:** `ansible-playbook web.yml --check --diff` — `--check` không thay đổi gì, chỉ báo **sẽ** thay đổi; `--diff` in khác biệt nội dung file. Lưu ý: module `command`/`shell` **bị bỏ qua** trong check mode (Ansible không đoán được chúng làm gì), trừ khi task ghi `check_mode: false`.

### 4.8. 🟥 Biến, facts, register

**Nguồn biến hay gặp** (thứ tự từ **thấp** đến **cao**, đã đơn giản hóa — danh sách đầy đủ có hơn 20 mức trong tài liệu):

| Mức | Nguồn | Dùng cho |
|---|---|---|
| 1 (thấp nhất) | `roles/<role>/defaults/main.yml` | Giá trị mặc định của role, ai cũng ghi đè được |
| 2 | `group_vars/all.yml` | Chung cho mọi máy |
| 3 | `group_vars/<nhóm>.yml` | Theo nhóm |
| 4 | `host_vars/<host>.yml` | Riêng một máy |
| 5 | `vars:` trong play | Gắn với playbook |
| 6 | `register:`, `set_fact:` | Kết quả lúc chạy |
| 7 (cao nhất) | `-e` / `--extra-vars` trên dòng lệnh | Ghi đè mọi thứ (ví dụ tag image cần deploy) |

**Facts** — thông tin Ansible tự thu thập ở đầu play (`gather_facts: true`, mặc định): hệ điều hành, phiên bản, IP, RAM, kiến trúc CPU. Truy cập qua `ansible_facts`:

```yaml
- ansible.builtin.debug:
    msg: "{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }} ({{ ansible_facts['distribution_release'] }})"
# → "Ubuntu 24.04 (noble)"
```

Xem toàn bộ facts: `ansible ans07-node1 -m ansible.builtin.setup | less`.

**register** — lưu kết quả task vào biến để task sau dùng:

```yaml
- name: Đọc phiên bản nginx
  ansible.builtin.command: nginx -v
  register: nginx_ver
  changed_when: false
- ansible.builtin.debug:
    var: nginx_ver.stderr      # nginx -v in ra stderr
```

### 4.9. 🟥 Template Jinja2

`ansible.builtin.template` đọc file `.j2` ở máy điều khiển, điền biến bằng **Jinja2**, rồi ghi lên máy đích. Cú pháp:

| Cú pháp | Ý nghĩa |
|---|---|
| `{{ bien }}` | In giá trị |
| `{{ bien \| default('x') }}` | Filter: giá trị mặc định nếu chưa định nghĩa |
| `{% if dieu_kien %} … {% endif %}` | Điều kiện |
| `{% for x in danh_sach %} … {% endfor %}` | Vòng lặp |
| `{# ghi chú #}` | Ghi chú, không xuất hiện trong file kết quả |

Template chạy **trên máy điều khiển**: file `.j2` không cần tồn tại trên máy đích.

### 4.10. 🟥 Điều kiện và vòng lặp

```yaml
- name: Chỉ chạy trên Ubuntu
  ansible.builtin.apt:
    name: htop
  when: ansible_facts['distribution'] == 'Ubuntu'

- name: Tạo nhiều thư mục
  ansible.builtin.file:
    path: "/opt/app/{{ item }}"
    state: directory
  loop: [logs, data, scripts]
```

⚠️ **Từ ansible-core 2.19**, kết quả của `when:` **phải là boolean**. Viết `when: ket_qua.stdout` (một chuỗi) giờ là **lỗi** *"Conditionals must have a boolean result"*, trước đây chỉ âm thầm coi chuỗi không rỗng là đúng. Sửa: `when: ket_qua.stdout | length > 0`. Tutorial cũ trên mạng đầy kiểu viết này — gặp lỗi đó thì biết vì sao.

### 4.11. 🟥 become — chạy với quyền root

`become: true` = chạy task qua `sudo` (mặc định thành root). Đặt ở mức play (cả play), hoặc từng task. Chỉ nâng quyền ở chỗ cần — cùng nguyên tắc quyền tối thiểu như IAM.

Trong container của lab, bạn vốn là root — và **không được** bật `become`: `become` mặc định gọi `sudo`, mà image `ubuntu:24.04` không có sudo → task lỗi `sudo: not found` (rc 127), kể cả khi đang là root (đã thử, 2026-10-31). Trên EC2 qua `aws_ssm`, phiên SSM vào bằng user `ssm-user` → **bắt buộc** `become: true` để cài gói.

### 4.12. 🟥 Role — đóng gói để tái sử dụng

Playbook dài vài trăm dòng thì khó đọc. **Role** là cấu trúc thư mục chuẩn để gom task, biến, file, template, handler của **một việc**:

```text
roles/
└── docker/
    ├── tasks/main.yml       # task — bắt buộc
    ├── handlers/main.yml    # handler
    ├── defaults/main.yml    # biến mặc định (ưu tiên thấp nhất)
    ├── vars/main.yml        # biến cố định của role (ưu tiên cao, ít dùng)
    ├── templates/           # file .j2
    ├── files/               # file copy nguyên trạng
    └── meta/main.yml        # thông tin role, phụ thuộc
```

Playbook gọn lại thành:

```yaml
- hosts: env_dev
  become: true
  roles:
    - docker
    - taskhub
```

Tạo khung role: `ansible-galaxy role init roles/docker`. Chỉ giữ thư mục thật sự dùng.

### 4.13. 🟥 Collection và requirements.yml

**Collection** = gói phân phối gồm module, plugin, role (ví dụ `amazon.aws` chứa inventory `aws_ec2`, connection `aws_ssm` và hàng trăm module AWS). Ghim phiên bản cho dự án:

```yaml
# requirements.yml
collections:
  - name: amazon.aws
    version: "12.0.0"
  - name: community.docker
    version: "5.4.0"
```

```bash
ansible-galaxy collection install -r requirements.yml
ansible-galaxy collection list amazon.aws     # có thể thấy HAI bản: bản bạn cài + bản đi kèm gói ansible
```

Bản cài vào `~/.ansible/collections` được tìm **trước** bản đi kèm gói `ansible` → phiên bản ghim là bản thật sự chạy. Ghim phiên bản vì cùng lý do ghim action bằng SHA ([CI/CD bài 04](../05-CICD/04-secrets-environments.md)): máy khác, tháng sau, vẫn chạy đúng code bạn đã test. Ví dụ thật: amazon.aws 12.0.0 (10/2026) bỏ hỗ trợ ansible-core < 2.18 và tăng bản boto3 tối thiểu lên 1.38.23.

### 4.14. 🟨 Ansible Vault và secret

**Ansible Vault** mã hóa file biến bằng mật khẩu (`ansible-vault create secrets.yml`), commit được vào Git, giải mã lúc chạy (`--ask-vault-pass`).

taskhub **không** dùng Vault: mật khẩu database sống ở **Parameter Store** ([AWS bài 02](../06-AWS/02-iam.md), [v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md)), `deploy.sh` trên máy tự đọc bằng instance role. Mật khẩu **không bao giờ đi qua** máy điều khiển hay Ansible.

| | Ansible Vault | Parameter Store |
|---|---|---|
| Lưu ở đâu | File mã hóa trong Git | Dịch vụ AWS |
| Ai giải mã | Ai có mật khẩu vault | Ai có quyền IAM `ssm:GetParameter` |
| Đổi secret | Sửa file, commit, chạy lại playbook | Sửa một chỗ, ứng dụng đọc lại |
| Hợp với | Máy on-premises, không có cloud | Hạ tầng AWS |

⚠️ Riêng với `aws_ssm`: file module được trung chuyển qua S3. Nếu task chứa secret trong tham số, secret nằm trong file đó — tài liệu plugin khuyên dùng bucket **tắt versioning** để file tạm bị xóa hẳn sau mỗi lần chạy.

### 4.15. 🟨 ansible-lint

Công cụ kiểm tra playbook theo thực hành tốt (thiếu FQCN, `command` không có `changed_when`, quyền file không ghi rõ…):

```bash
pipx install ansible-lint      # môi trường riêng, có ansible-core riêng
ansible-lint playbooks/site.yml
```

Giống actionlint cho workflow ([CI/CD bài 02](../05-CICD/02-github-actions-basics.md)): bắt lỗi trước khi chạy thật.

### 4.16. 🟨 Đặt Ansible cạnh các lựa chọn khác

| Cách cấu hình máy | Chạy khi nào | Điểm mạnh | Điểm yếu |
|---|---|---|---|
| User data / cloud-init | Một lần, lúc boot đầu | Không cần công cụ ngoài | Không chạy lại; khó debug |
| Ansible | Bất cứ lúc nào bạn chạy | Idempotent, chạy lại được, đọc dễ | Cần máy điều khiển + đường kết nối |
| 🟦 Image dựng sẵn (Packer, Docker image) | Lúc build image | Máy mới khởi động là đủ đồ | Đổi cấu hình = build image mới |
| 🟦 Puppet/Chef/Salt | Agent tự áp dụng định kỳ | Tự sửa drift liên tục | Phải cài, vận hành agent + server |

taskhub v4 kết hợp: Terraform tạo EC2 (user data tối thiểu) → Ansible cài Docker + triển khai ứng dụng.

## 5. Ví dụ thực tế

**Tình huống:** công ty có 30 máy Ubuntu chạy dịch vụ nội bộ. Một lỗ hổng OpenSSL được công bố, cần nâng gói `openssl` lên bản vá trên toàn bộ máy, nhưng làm **từng đợt** để không sập cùng lúc.

```yaml
- name: Vá openssl theo đợt
  hosts: internal
  become: true
  serial: 5                    # mỗi đợt 5 máy; đợt lỗi thì dừng, không lan sang máy khác
  tasks:
    - name: Nâng openssl lên bản mới nhất trong repo
      ansible.builtin.apt:
        name: openssl
        state: latest
        update_cache: true
      notify: Restart nginx
  handlers:
    - name: Restart nginx
      ansible.builtin.systemd_service:
        name: nginx
        state: restarted
```

Không có Ansible: SSH vào 30 máy gõ lệnh, sót 2 máy, không ai biết máy nào đã vá. Có Ansible: một lệnh, log ghi rõ máy nào `changed`, máy nào `ok` (đã vá từ trước), máy nào `failed`. `serial` chính là **rolling update** bạn học ở [CI/CD bài 05](../05-CICD/05-deployment-strategies-rollback.md), áp dụng cho cấu hình máy.

## 6. Sơ đồ kiến trúc

**Lab của bài này (miễn phí):**

```text
 [WSL] máy điều khiển
 ~/devops-lab/07-ansible/local/
 ├── ansible.cfg ─────────── inventory = inventory.ini
 ├── inventory.ini ───────── nhóm [lab]: ans07-node1..3, ansible_connection=community.docker.docker
 ├── group_vars/lab.yml ──── biến cho nhóm lab
 ├── host_vars/ans07-node3.yml
 ├── web.yml + templates/index.html.j2
 │
 │  ansible-playbook web.yml
 │     │  docker exec (qua Docker CLI → Docker Desktop)
 ▼     ▼
 ┌────────────┐ ┌────────────┐ ┌────────────┐
 │ans07-node1 │ │ans07-node2 │ │ans07-node3 │   ubuntu:24.04 + python3 + nginx
 │ :80→18081  │ │ :80→18082  │ │ :80→18083  │
 └────────────┘ └────────────┘ └────────────┘
       ▲  curl localhost:18081..18083 từ WSL
```

**taskhub v4 ([Lab 03](labs/lab-03-ansible-ssm.md)):**

```text
 [WSL] ansible-playbook ── inventory aws_ec2 ──► EC2 API: "tag Project=taskhub, running?"
        │                                              → taskhub-app (i-0abc…)
        │ connection aws_ssm
        ├──► S3 taskhub-ansible-ssm-<account>  (file module tạm, xóa sau mỗi lần chạy)
        └──► SSM Session Manager ──► SSM Agent trên EC2 ──► curl tải module từ S3 (presigned URL)
                                                         └─► python3 chạy module, trả kết quả
 Không SSH, không port 22.
```

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `ansible --version` | Phiên bản, file config đang dùng, Python | 🟥 |
| `ansible-inventory --graph` / `--host <h>` | Xem nhóm, biến cuối cùng của host | 🟥 |
| `ansible <nhóm> -m ping` | Kiểm tra kết nối + Python | 🟥 |
| `ansible <nhóm> -m <module> -a "<tham số>" [-b]` | Lệnh ad-hoc | 🟥 |
| `ansible-playbook <file>.yml` | Chạy playbook | 🟥 |
| `ansible-playbook … --check --diff` | Chạy thử, xem khác biệt | 🟥 |
| `ansible-playbook … --limit <host>` | Chỉ chạy trên một số host | 🟥 |
| `ansible-playbook … -e key=value` | Truyền biến (ưu tiên cao nhất) | 🟥 |
| `ansible-playbook … -v / -vvv` | Log chi tiết hơn | 🟥 |
| `ansible-playbook … --tags <tag>` / `--list-tasks` | Chạy một phần / xem danh sách task | 🟨 |
| `ansible-playbook … --syntax-check` | Kiểm tra cú pháp | 🟨 |
| `ansible-galaxy collection install -r requirements.yml` | Cài collection | 🟥 |
| `ansible-galaxy role init <đường-dẫn>` | Tạo khung role | 🟨 |
| `ansible-doc <module>` | Tài liệu module ngay trong terminal | 🟨 |
| `ansible-lint` | Kiểm tra thực hành tốt | 🟨 |
| `ansible-vault create/edit/view` | Mã hóa file biến | 🟨 |

## 8. Giải thích câu lệnh và tham số

### `ansible --version`

```bash
ansible --version
```

Đầu ra minh họa (đường dẫn trên máy bạn sẽ khác):

```text
ansible [core 2.21.5]
  config file = /home/phuong/devops-lab/07-ansible/local/ansible.cfg
  configured module search path = ['/home/phuong/.ansible/plugins/modules', '/usr/share/ansible/plugins/modules']
  ansible python module location = /home/phuong/.local/share/pipx/venvs/ansible/lib/python3.12/site-packages/ansible
  ansible collection location = /home/phuong/.ansible/collections:/usr/share/ansible/collections
  executable location = /home/phuong/.local/bin/ansible
  python version = 3.12.3 (main, …) [GCC 13.2.0] (/home/phuong/.local/share/pipx/venvs/ansible/bin/python)
  jinja version = 3.1.x
  pyyaml version = 6.0.x (with libyaml v0.2.5)
```

| Dòng | Đọc để biết |
|---|---|
| `core 2.21.5` | Phiên bản lõi — quyết định cú pháp nào hợp lệ |
| `config file` | **File `ansible.cfg` nào đang có hiệu lực.** `None` = không tìm thấy → inventory mặc định `/etc/ansible/hosts` |
| `ansible collection location` | Nơi tìm collection, theo thứ tự |
| `python version` | Python của **máy điều khiển** (trong venv của pipx) |

Ansible tìm `ansible.cfg` theo thứ tự: biến `ANSIBLE_CONFIG` → `./ansible.cfg` (thư mục hiện tại) → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg`. Vì vậy **luôn `cd` vào thư mục dự án trước khi chạy**.

⚠️ Ansible **bỏ qua** `ansible.cfg` trong thư mục mà ai cũng ghi được (world-writable) vì lý do bảo mật. Thư mục trên ổ Windows (`/mnt/c/...`, `/mnt/d/...`) thường bị WSL báo quyền 777 → Ansible in cảnh báo và không đọc file. Đặt lab trong `~` của WSL.

### `ansible lab -m ansible.builtin.ping`

```text
ans07-node1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

`ping` của Ansible **không phải** ICMP ping ([Networking 08](../02-NETWORKING/08-network-troubleshooting-tools.md)): nó kết nối thật, chạy module Python và nhận về `pong`. `SUCCESS` nghĩa là đường kết nối + Python đều ổn.

### `ansible-playbook web.yml`

Đầu ra minh họa của lần chạy thứ hai (đã đúng trạng thái):

```text
PLAY [Cài web server] **********************************************************

TASK [Gathering Facts] *********************************************************
ok: [ans07-node1]
ok: [ans07-node2]
ok: [ans07-node3]

TASK [Cài nginx] ***************************************************************
ok: [ans07-node1]
...

PLAY RECAP *********************************************************************
ans07-node1 : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
ans07-node2 : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
ans07-node3 : ok=5    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

**PLAY RECAP** là dòng đọc đầu tiên: `changed=0` ở lần chạy thứ hai = playbook idempotent. `unreachable` = không kết nối được (khác `failed` = kết nối được nhưng task lỗi).

| Tham số | Ý nghĩa |
|---|---|
| `-i <inventory>` | Chọn inventory (ghi đè `ansible.cfg`) |
| `--check` | Không thay đổi gì, báo "sẽ thay đổi" |
| `--diff` | In khác biệt nội dung file (template, copy, lineinfile) |
| `--limit ans07-node1` | Chỉ chạy trên host/nhóm này |
| `-e taskhub_image_tag=v0.6.0` | Biến dòng lệnh, ưu tiên cao nhất |
| `--tags docker` | Chỉ chạy task/role có tag `docker` |
| `-v` … `-vvvv` | Càng nhiều `v` càng chi tiết; `-vvv` in cả lệnh kết nối |
| `--start-at-task "<tên>"` | Bắt đầu từ một task (debug playbook dài) |

## 9. Bài thực hành từng bước

> Môi trường: `[WSL]`. Cần Docker chạy được trong WSL (`docker ps` không lỗi). Port 18081–18083 phải trống — nếu máy bạn đã dùng, đổi sang số khác ở Bước 2 và mọi lệnh `curl`.

### Bước 1 — Cài Ansible và collection `[WSL]`

```bash
sudo apt update && sudo apt install -y pipx
pipx ensurepath
exec bash -l                                   # nạp lại PATH
pipx install --include-deps ansible
ansible --version | head -2

mkdir -p ~/devops-lab/07-ansible/local && cd ~/devops-lab/07-ansible/local
cat > requirements.yml <<'EOF'
collections:
  - name: community.docker
    version: "5.4.0"
EOF
ansible-galaxy collection install -r requirements.yml
ansible-galaxy collection list community.docker
```

❓ Lệnh cuối liệt kê mấy bản `community.docker`? Bản nào được dùng, vì sao?

### Bước 2 — Tạo 3 máy "được quản lý" bằng container `[WSL]`

```bash
for i in 1 2 3; do
  docker run -d --name "ans07-node$i" --hostname "ans07-node$i" \
    -p "1808$i:80" ubuntu:24.04 sleep infinity
done
docker ps --filter name=ans07- --format '{{.Names}}\t{{.Status}}\t{{.Ports}}'
```

`sleep infinity` giữ container sống để Ansible "vào" bằng `docker exec`. Container **không có systemd** — khác máy thật, phần sau sẽ thấy hệ quả.

### Bước 3 — Inventory, biến, ansible.cfg `[WSL]`

```bash
cat > ansible.cfg <<'EOF'
[defaults]
inventory = inventory.ini
EOF

cat > inventory.ini <<'EOF'
[lab]
ans07-node1
ans07-node2
ans07-node3

[lab:vars]
ansible_connection=community.docker.docker
ansible_python_interpreter=/usr/bin/python3
EOF

mkdir -p group_vars host_vars
cat > group_vars/lab.yml <<'EOF'
site_owner: phuong
site_color: steelblue
EOF
cat > host_vars/ans07-node3.yml <<'EOF'
site_color: tomato        # ghi đè biến nhóm cho riêng node3
EOF

ansible --version | grep 'config file'
ansible-inventory --graph
ansible-inventory --host ans07-node3
```

❓ `ansible-inventory --host ans07-node3` cho `site_color` bằng gì? Còn node1?

### Bước 4 — Lần ping đầu tiên thất bại (cố ý) `[WSL]`

```bash
ansible lab -m ansible.builtin.ping
```

Image `ubuntu:24.04` **không có Python**. Đọc thông báo lỗi (chạy thật với ansible-core 2.21.5, 2026-10-31; rút gọn — mỗi node một khối):

```text
[ERROR]: Task failed: Action failed: The module interpreter '/usr/bin/python3' was not found.
...
ans07-node1 | FAILED! => {
    "changed": false,
    "module_stderr": "/bin/sh: 1: /usr/bin/python3: not found\n",
    "module_stdout": "",
    "msg": "The module interpreter '/usr/bin/python3' was not found.",
    "rc": 127
}
```

`rc: 127` = "command not found" ([Linux 06](../01-LINUX/06-bash-scripting.md)). Ansible kết nối được (không phải `UNREACHABLE`), nhưng không có Python để chạy module.

### Bước 5 — Cài Python bằng module `raw` `[WSL]`

```bash
ansible lab -m ansible.builtin.raw -a "apt-get update -qq && apt-get install -y -qq python3 iproute2"
ansible lab -m ansible.builtin.ping
ansible ans07-node1 -m ansible.builtin.setup -a "filter=ansible_distribution*"
ansible ans07-node1 -m ansible.builtin.setup -a "filter=ansible_default_ipv4"
```

`raw` gửi thẳng chuỗi lệnh qua kết nối, không cần Python — dùng **duy nhất** cho việc "mồi" Python (và vài gói Ansible cần để thu thập facts). Sau đó dùng module bình thường.

Vì sao thêm `iproute2`? Ansible lấy fact mạng (`ansible_default_ipv4`…) bằng lệnh `ip`, mà image `ubuntu:24.04` không có. Thiếu nó, lần chạy đầu fact IP rỗng; cài nginx lại **kéo theo** `iproute2` → lần chạy thứ hai fact xuất hiện → template đổi → idempotency ở Bước 8 "hỏng" dù playbook không sai (đã gặp khi chạy thử bài, 2026-10-31). Bài học: kết quả template phụ thuộc facts, và facts phụ thuộc gói có trên máy.

### Bước 6 — Template trang chủ `[WSL]`

```bash
mkdir -p templates
cat > templates/index.html.j2 <<'EOF'
{# File này do Ansible sinh ra — sửa template, đừng sửa trên máy #}
<!doctype html>
<html>
<body style="background: {{ site_color }}; color: white; font-family: sans-serif">
  <h1>{{ inventory_hostname }}</h1>
  <p>{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}
     ({{ ansible_facts['distribution_release'] }}), {{ ansible_facts['processor_vcpus'] }} vCPU</p>
  <p>IP trong mạng Docker: {{ ansible_facts['default_ipv4']['address'] | default('không rõ') }}</p>
  <p>Người quản lý: {{ site_owner }}</p>
</body>
</html>
EOF
```

### Bước 7 — Playbook `[WSL]`

```bash
cat > web.yml <<'EOF'
- name: Cài web server
  hosts: lab
  # KHÔNG có `become: true` ở đây: container đã chạy bằng root, và image ubuntu:24.04 không cài sudo
  # → `become` (mặc định dùng sudo) sẽ lỗi "sudo: not found". Trên EC2 thật (Lab 03) thì PHẢI có become.
  tasks:
    - name: Cài nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true
        cache_valid_time: 3600

    - name: Trang chủ từ template
      ansible.builtin.template:
        src: templates/index.html.j2
        dest: /var/www/html/index.html
        owner: root
        group: root
        mode: "0644"
      notify: Reload nginx

    # Container không có systemd → không dùng được module systemd_service.
    # Khởi động nginx bằng lệnh, kèm `creates:` để lần sau không chạy lại.
    - name: Khởi động nginx (nếu chưa chạy)
      ansible.builtin.command:
        cmd: nginx
        creates: /run/nginx.pid

  handlers:
    - name: Reload nginx
      ansible.builtin.command: nginx -s reload
EOF

ansible-playbook web.yml --syntax-check
ansible-playbook web.yml
```

Kiểm tra từ WSL:

```bash
for p in 18081 18082 18083; do curl -s "localhost:$p" | grep -E '<h1>|background'; done
```

### Bước 8 — Chứng minh idempotency `[WSL]`

```bash
ansible-playbook web.yml
```

Đọc PLAY RECAP: mọi host phải `changed=0`. Không phải? Tìm task nào báo `changed` và vì sao (mục 11).

### Bước 9 — Sửa template, xem handler `[WSL]`

```bash
sed -i 's/Người quản lý/Quản trị viên/' templates/index.html.j2
ansible-playbook web.yml --check --diff     # xem trước, không đổi gì
ansible-playbook web.yml                    # áp dụng thật
```

❓ Trong lần chạy thật, task nào `changed`? Handler `Reload nginx` có chạy không, chạy mấy lần cho mỗi host? Chạy lại lần nữa thì sao?

### Bước 10 — Phá idempotency (cố ý) rồi sửa `[WSL]`

Thêm task này vào cuối danh sách `tasks` trong `web.yml`:

```yaml
    - name: Ghi nhật ký triển khai (CÁCH SAI)
      ansible.builtin.shell: echo "deployed $(date -Is)" >> /var/log/deploy.log
```

```bash
ansible-playbook web.yml
ansible-playbook web.yml
ansible ans07-node1 -m ansible.builtin.command -a "cat /var/log/deploy.log"
```

❓ Hai lần chạy liên tiếp đều báo gì cho task này? File log có mấy dòng? Viết lại task sao cho lần chạy thứ hai `changed=0` (có ít nhất hai cách — xem gợi ý mục 4.7). Kiểm chứng bằng cách chạy hai lần.

### Bước 11 — Biến dòng lệnh thắng mọi thứ `[WSL]`

```bash
ansible-playbook web.yml -e site_color=seagreen
curl -s localhost:18083 | grep background
```

❓ node3 có `host_vars` đặt `tomato`, sao giờ lại `seagreen`? Chạy lại **không** có `-e` thì trang trở về màu gì?

### Bước 12 — Dọn dẹp `[WSL]`

```bash
docker rm -f ans07-node1 ans07-node2 ans07-node3
docker ps -a --filter name=ans07-       # không còn dòng nào
```

Giữ thư mục `~/devops-lab/07-ansible/local/` để làm bài tập.

## 10. Kết quả mong đợi

- Bước 4: ping lỗi `python3: not found` (rc 127). Bước 5: ping trả `pong` cho cả 3 node.
- Bước 7: lần chạy đầu `changed` ở task cài nginx, template, khởi động nginx và handler reload (chạy thật: `ok=5 changed=4` mỗi host); `curl` 3 port trả 3 trang khác nhau có IP trong mạng Docker, node3 nền `tomato`.
- Bước 8: `changed=0` trên cả 3 host.
- Bước 9: `--check --diff` in đúng dòng đổi chữ; lần chạy thật chỉ task template `changed`, handler chạy **1 lần mỗi host**; chạy thêm lần nữa → `changed=0`.
- Bước 10: bản sai luôn `changed`, mỗi lần chạy thêm một dòng log; bản sửa → lần hai `changed=0`.
- Bước 11: cả 3 trang nền `seagreen`; chạy lại không `-e` → node1/2 `steelblue`, node3 `tomato`.

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| Lần chạy thứ hai template vẫn `changed`, diff chỉ khác dòng IP (`không rõ` → `172.17.0.x`) | Lần đầu máy chưa có lệnh `ip` (gói `iproute2`) nên fact `ansible_default_ipv4` rỗng; một task sau đó cài gói kéo theo `iproute2` | Cài `iproute2` ngay ở bước mồi (`raw`), trước khi thu thập facts |
| Gathering Facts `FAILED`, `"module_stderr": "/bin/sh: 1: sudo: not found\n"`, `rc: 127` | Play có `become: true` nhưng máy đích không có `sudo` (ví dụ container `ubuntu:24.04`) | Container đã là root → bỏ `become`; máy thật thì cài/cấu hình sudo hoặc đổi `become_method` |
| `externally-managed-environment` khi `pip install ansible` | Ubuntu 24.04 chặn pip vào Python hệ thống (PEP 668) | Dùng `pipx install --include-deps ansible` |
| `ansible: command not found` sau khi cài pipx | `~/.local/bin` chưa vào PATH | `pipx ensurepath` rồi mở terminal mới |
| `config file = None` dù có `ansible.cfg` | Chạy lệnh ở thư mục khác; hoặc thư mục world-writable (ổ `/mnt/c`, `/mnt/d`) nên Ansible bỏ qua | `cd` đúng thư mục; đặt dự án trong `~` của WSL |
| `Could not match supplied host pattern` | Inventory không được đọc (sai đường dẫn/config) hoặc tên nhóm sai | `ansible-inventory --graph` |
| Biến trong `group_vars/` "không có tác dụng" | `group_vars/` không nằm cạnh inventory hoặc cạnh playbook | Chuyển thư mục; kiểm tra bằng `ansible-inventory --host <h>` |
| `/usr/bin/python3: not found`, rc 127 | Máy đích chưa có Python | Cài bằng module `raw` (mục 9 Bước 5) |
| `Failed to connect to the host via ssh` / `UNREACHABLE` | Sai đường kết nối (quên `ansible_connection`), container đã dừng, sai SSH key/user | Kiểm tra biến kết nối; `docker ps`; chạy `-vvv` |
| `docker: command not found` / `Cannot connect to the Docker daemon` khi dùng connection docker | Connection `community.docker.docker` gọi Docker CLI ở máy điều khiển; WSL chưa bật tích hợp | Bật WSL integration trong Docker Desktop |
| `System has not been booted with systemd` | Dùng `systemd_service` trong container | Container không có systemd — dùng lệnh như lab; trên EC2 dùng `systemd_service` bình thường |
| Task `shell`/`command` luôn `changed` | Ansible không biết lệnh làm gì | Dùng module chuyên dụng, hoặc `creates:` / `changed_when:` |
| `Conditionals must have a boolean result` | `when:` trả về chuỗi/list (ansible-core ≥ 2.19 coi là lỗi) | Viết điều kiện boolean: `x.stdout \| length > 0` |
| `'dict object' has no attribute 'stdout'` ở task sau `--check` | Task `command` bị bỏ qua trong check mode nên biến register không có `stdout` | `check_mode: false` cho task chỉ đọc; dùng filter `default('')` |
| `mapping values are not allowed here` | YAML: chuỗi chứa `: ` không có nháy bao ngoài | Bọc nháy cả giá trị hoặc dùng `>-` / `\|` (đã gặp ở [CI/CD 02](../05-CICD/02-github-actions-basics.md)) |
| Gỡ gói bằng `apt state: absent` xóa nhầm gói khác | Tên đưa vào là gói ảo được gói khác "provides" (ví dụ `containerd` khi đã cài `containerd.io`) | Kiểm tra `dpkg -l` trước; chỉ gỡ đúng tên gói đã cài |

## 12. Đọc log và xử lý lỗi

**Quy trình khi playbook đỏ:**

1. Đọc **PLAY RECAP**: host nào `failed`, host nào `unreachable`.
2. Kéo lên tìm dòng `fatal: [host]: FAILED!` đầu tiên — đó là task gốc. Các lỗi sau thường là hệ quả.
3. Đọc các trường trong JSON lỗi:

| Trường | Ý nghĩa |
|---|---|
| `msg` | Mô tả lỗi của module |
| `rc` | Exit code (với `command`/`shell`) |
| `stdout` / `stderr` | Output của lệnh |
| `module_stderr` | Lỗi khi **chạy module** (thiếu Python, thiếu thư viện) |
| `invocation.module_args` | Tham số thật sự được gửi đi (sau khi điền biến) — xem với `-v` |

4. Chạy lại chỉ host lỗi, chi tiết hơn: `ansible-playbook web.yml --limit ans07-node2 -vvv`.
5. Tái hiện bằng ad-hoc với cùng module + tham số, hoặc vào máy xem trực tiếp (`docker exec -it ans07-node2 bash`, trên EC2 thì Session Manager).

Ví dụ minh họa — template dùng biến chưa định nghĩa:

```text
TASK [Trang chủ từ template] ***************************************************
fatal: [ans07-node1]: FAILED! => {"changed": false, "msg": "… 'site_owner' is undefined …"}
```

→ biến không tới được host: kiểm tra `ansible-inventory --host ans07-node1` xem có `site_owner` không; nếu không → `group_vars/` đặt sai chỗ hoặc sai tên nhóm.

Nhớ ghi lỗi vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

## 13. Câu hỏi kiểm tra kiến thức

1. "Agentless" và "push" nghĩa là gì? Máy được quản lý cần tối thiểu những gì?
2. Vì sao Ubuntu 24.04 không cho `pip install ansible` vào Python hệ thống, và pipx giải quyết thế nào?
3. Cho inventory ở `inventory/hosts.ini`, playbook ở `playbooks/site.yml`. Liệt kê các vị trí `group_vars/` mà Ansible đọc. Nếu cùng một biến được đặt ở cả hai nơi, nơi nào thắng?
4. Phân biệt `ok`, `changed`, `failed`, `unreachable`. Vì sao `unreachable` và `failed` cần hướng điều tra khác nhau?
5. Idempotency là gì? Vì sao module `apt` idempotent còn `command: apt-get install -y nginx` thì (về mặt báo cáo) không?
6. Ba cách làm task `command`/`shell` trở nên idempotent?
7. Handler khác task thường ở điểm nào? Ba task cùng `notify` một handler thì handler chạy mấy lần?
8. Sắp xếp theo độ ưu tiên tăng dần: `host_vars`, role `defaults`, `-e`, `group_vars/all`, `group_vars/<nhóm>`.
9. Facts là gì? Viết biểu thức lấy codename của Ubuntu.
10. Template Jinja2 được xử lý ở máy nào? File `.j2` có cần tồn tại trên máy đích không?
11. Vì sao `when: result.stdout` gây lỗi ở ansible-core 2.21? Viết lại cho đúng.
12. Module `raw` dùng khi nào, và vì sao không nên dùng cho mọi việc?
13. So sánh connection `ssh`, `community.docker.docker`, `amazon.aws.aws_ssm`: mỗi loại cần gì ở máy điều khiển và máy đích?
14. Vì sao ghim phiên bản collection trong `requirements.yml`? Lấy ví dụ một thay đổi phá vỡ tương thích có thật.
15. taskhub dùng Parameter Store thay vì Ansible Vault cho mật khẩu database — nêu hai lý do.

## 14. Bài tập tự làm

> Lời giải ở [solutions/05-solutions.md](solutions/05-solutions.md). Tự làm trước, kẹt 30 phút mới xem.

**Bài 1 — Inventory YAML.** Viết lại `inventory.ini` của lab thành `inventory.yml` tương đương (có biến nhóm). Chứng minh tương đương bằng `ansible-inventory -i inventory.yml --host ans07-node3` so với bản INI.

**Bài 2 — Role hóa.** Chuyển `web.yml` thành role `web` (tasks, handlers, templates, defaults với `site_color: gray`). Playbook mới chỉ còn vài dòng. Chạy hai lần, lần hai `changed=0`. Giải thích vì sao `site_color` trong `defaults` của role **không** thắng `group_vars/lab.yml`.

**Bài 3 — Người dùng và thư mục.** Thêm vào role: tạo user hệ thống `webops` (không shell đăng nhập), thư mục `/srv/site` thuộc `webops:webops` quyền `0750`, dùng **vòng lặp** tạo thêm `/srv/site/{logs,cache}`. Chỉ dùng module, không `command`.

**Bài 4 — Điều kiện.** Thêm task chỉ chạy trên host có tên kết thúc bằng `3`, in "máy canary". Viết điều kiện **boolean** đúng chuẩn ansible-core 2.21.

**Bài 5 — Check mode.** Viết một task đọc phiên bản nginx bằng `command` + `register`, rồi một task `debug` in phiên bản. Làm sao để `ansible-playbook --check` vẫn in được phiên bản (không lỗi `has no attribute 'stdout'`) và task đọc **không** bao giờ báo `changed`?

**Bài 6 — ansible-lint.** Cài ansible-lint bằng pipx, chạy trên playbook/role của bạn. Sửa hết cảnh báo hoặc ghi lý do bỏ qua từng cảnh báo vào nhật ký.

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Cài được Ansible bằng pipx, đọc được `config file` và phiên bản core từ `ansible --version`.
- [ ] Viết inventory INI/YAML, đặt `group_vars`/`host_vars` đúng chỗ và kiểm chứng bằng `ansible-inventory --host`.
- [ ] Giải thích được vì sao lần ping đầu lỗi rc 127 và sửa bằng `raw`.
- [ ] Playbook chạy lần hai `changed=0`; tự tìm và sửa được task phá idempotency.
- [ ] Giải thích được handler chạy khi nào, mấy lần.
- [ ] Biết thứ tự ưu tiên biến ở mức đơn giản và chứng minh `-e` thắng `host_vars`.
- [ ] Viết điều kiện `when` boolean, dùng `loop`, `register`, facts, template.
- [ ] Giải thích được khi nào dùng connection `ssh` / `docker` / `aws_ssm`.
- [ ] Tách được playbook thành role, ghim collection bằng `requirements.yml`.

### Gặp lại ở đâu

| Kiến thức | Dùng lại ở |
|---|---|
| Role `docker`, `taskhub`, inventory động, connection `aws_ssm` | [Lab 03](labs/lab-03-ansible-ssm.md), [dự án v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) |
| Idempotency, desired state | Terraform `plan` báo "No changes" ([bài 02](02-terraform-basics.md)); Kubernetes reconcile (Module 09) |
| Handler "chỉ restart khi cấu hình đổi" | Reload Prometheus/Grafana khi đổi config (Module 08) |
| `serial` (cập nhật theo đợt) | Rolling update ([CI/CD 05](../05-CICD/05-deployment-strategies-rollback.md)), Kubernetes Deployment (Module 09) |
| Secret không đi qua công cụ cấu hình | Rà soát bảo mật (Module 10) |

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Ansible docs — Installing Ansible (pipx)](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) · [mã nguồn trang](https://github.com/ansible/ansible-documentation/blob/devel/docs/docsite/rst/installation_guide/intro_installation.rst) | `pipx install --include-deps ansible`, `pipx upgrade --include-injected`, `pipx inject` | 2026-10-31 |
| [PyPI — ansible](https://pypi.org/project/ansible/) · [PyPI — ansible-core](https://pypi.org/project/ansible-core/) | Ansible 14.5.0 ↔ ansible-core 2.21.5, yêu cầu Python ≥ 3.12 | 2026-10-31 |
| [Ansible docs — How to build your inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html) · [mã nguồn trang](https://github.com/ansible/ansible-documentation/blob/devel/docs/docsite/rst/inventory_guide/intro_inventory.rst) | INI/YAML, nhóm, `group_vars`/`host_vars` cạnh inventory và playbook | 2026-10-31 |
| [Porting guide ansible-core 2.19 — Broken Conditionals](https://github.com/ansible/ansible-documentation/blob/devel/docs/docsite/rst/porting_guides/porting_guide_core_2.19.rst) | Điều kiện phải trả về boolean | 2026-10-31 |
| [community.docker — connection plugin `docker` (mã nguồn 5.4.0)](https://github.com/ansible-collections/community.docker/blob/5.4.0/plugins/connection/docker.py) | Dùng Docker CLI để exec vào container | 2026-10-31 |
| [amazon.aws 12.0.0 — CHANGELOG](https://github.com/ansible-collections/amazon.aws/blob/12.0.0/CHANGELOG.rst) | Yêu cầu ansible-core ≥ 2.18, boto3/botocore ≥ 1.38.23 | 2026-10-31 |
| [amazon.aws — connection `aws_ssm` (mã nguồn 12.0.0)](https://github.com/ansible-collections/amazon.aws/blob/12.0.0/plugins/connection/aws_ssm.py) | Yêu cầu S3 bucket, khuyên tắt versioning, không dùng `ansible_user` | 2026-10-31 |
| [ansible-core 2.21.5 — config base.yml](https://github.com/ansible/ansible/blob/v2.21.5/lib/ansible/config/base.yml) | `interpreter_python`, `roles_path`, thứ tự collection path | 2026-10-31 |
| [ansible-lint — Installing](https://github.com/ansible/ansible-lint/blob/main/docs/installing.md) | Cài bằng pip/pipx; phiên bản 26.10.1 trên PyPI | 2026-10-31 |
| [PEP 668 — Externally Managed Environments](https://peps.python.org/pep-0668/) | Lỗi `externally-managed-environment` | 2026-10-31 |
