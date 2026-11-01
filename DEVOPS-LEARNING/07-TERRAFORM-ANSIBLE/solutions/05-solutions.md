# Lời giải — Bài 05: Ansible

> Chỉ mở sau khi đã tự làm. Đáp án không phải duy nhất — tiêu chí là **giải thích được vì sao**.
> Quay lại bài: [05-ansible-fundamentals.md](../05-ansible-fundamentals.md)

## Câu hỏi trong bài thực hành (mục 9)

**Bước 1 — Mấy bản `community.docker`?** Thường là hai: bản `5.4.0` vừa cài vào `~/.ansible/collections` và bản đi kèm gói `ansible` (trong venv pipx). Ansible dùng bản tìm thấy **đầu tiên** theo thứ tự collection path — `~/.ansible/collections` đứng trước → bản `5.4.0` được dùng. Đó là lý do ghim trong `requirements.yml` có tác dụng thật.

**Bước 3 — `site_color` của node3 và node1?** node3: `tomato` (`host_vars` ưu tiên cao hơn `group_vars`). node1: `steelblue` (chỉ có biến nhóm).

**Bước 9 — Task nào changed, handler chạy mấy lần?** Chỉ task "Trang chủ từ template" `changed` trên cả 3 host. Handler `Reload nginx` chạy **1 lần mỗi host**, ở cuối play. Chạy thêm lần nữa: template không đổi → không `changed` → không notify → handler không chạy → `changed=0`.

**Bước 10 — Task `shell` sai.** Cả hai lần đều `changed`; file log có 2 dòng (thêm 1 dòng mỗi lần). Hai cách sửa:

```yaml
# Cách 1: chỉ ghi lần đầu
- name: Ghi nhật ký triển khai lần đầu
  ansible.builtin.shell: echo "deployed $(date -Is)" > /var/log/deploy.log
  args:
    creates: /var/log/deploy.log

# Cách 2: dùng module mô tả TRẠNG THÁI (một dòng cố định phải có trong file)
- name: Đánh dấu máy do Ansible quản lý
  ansible.builtin.lineinfile:
    path: /var/log/deploy.log
    line: "managed-by: ansible"
    create: true
    mode: "0644"
```

Bài học: "ghi thời gian mỗi lần chạy" vốn **không** phải trạng thái mong muốn — nó là một sự kiện. Muốn lưu lịch sử chạy thì dùng log của chính Ansible (hoặc callback), đừng ép một task phải idempotent khi bản chất nó không phải.

**Bước 11 — Vì sao `seagreen` thắng `host_vars`?** `-e` (extra vars) có độ ưu tiên **cao nhất**, ghi đè mọi nguồn khác. Chạy lại không `-e`: node1/node2 về `steelblue`, node3 về `tomato` — biến dòng lệnh không được "lưu lại" ở đâu cả.

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Agentless: không cài tiến trình riêng thường trực trên máy đích. Push: máy điều khiển chủ động kết nối và đẩy module đi. Máy được quản lý cần: một đường kết nối (SSH, docker exec, SSM…) và Python (trừ khi chỉ dùng `raw`).

**2.** PEP 668: Ubuntu 24.04 đánh dấu Python hệ thống là "externally managed" — `pip install` vào đó có thể làm hỏng gói apt phụ thuộc Python, nên pip từ chối với lỗi `externally-managed-environment`. pipx tạo **một venv riêng** cho Ansible và đưa các lệnh (`ansible`, `ansible-playbook`…) vào `~/.local/bin`.

**3.** `inventory/group_vars/` (cạnh nguồn inventory) và `playbooks/group_vars/` (cạnh playbook). Cùng biến ở cả hai → bản **cạnh playbook** thắng (theo tài liệu inventory). `group_vars/` cạnh `ansible.cfg` ở thư mục cha **không** được đọc.

**4.** `ok`: đã đúng, không làm gì. `changed`: đã sửa. `failed`: kết nối được, task lỗi → đọc `msg`, `rc`, `stderr`. `unreachable`: không kết nối được → điều tra đường kết nối (SSH key, plugin, container dừng, SSM Agent offline), chưa cần nhìn task.

**5.** Idempotent: chạy nhiều lần, trạng thái cuối giống nhau và lần sau không thay đổi gì. Module `apt` kiểm tra gói đã cài chưa trước khi làm → báo `ok`. `command: apt-get install -y nginx` thì Ansible chỉ biết lệnh chạy thành công (exit 0) → luôn báo `changed`, dù thực tế apt không cài thêm gì. Báo cáo sai làm mất tín hiệu "có gì thay đổi thật".

**6.** (a) `creates:`/`removes:`; (b) `changed_when: false` cho lệnh chỉ đọc; (c) `changed_when:` dựa trên output (ví dụ `"'already' not in result.stdout"`). Tốt nhất: thay bằng module chuyên dụng.

**7.** Handler chỉ chạy khi được `notify` **và** task notify báo `changed`; chạy ở **cuối play** (hoặc khi gặp `meta: flush_handlers`), và chỉ **một lần** dù được notify nhiều lần. Ba task cùng notify → 1 lần.

**8.** Role `defaults` < `group_vars/all` < `group_vars/<nhóm>` < `host_vars` < `-e`.

**9.** Facts: thông tin Ansible tự thu thập về máy đích ở đầu play (module `setup`). Codename Ubuntu: `{{ ansible_facts['distribution_release'] }}` → `noble` với 24.04.

**10.** Ở máy điều khiển. File `.j2` không cần có trên máy đích; chỉ file kết quả được ghi lên đó.

**11.** Từ ansible-core 2.19, kết quả điều kiện phải là boolean; `result.stdout` là chuỗi → lỗi *Conditionals must have a boolean result*. Sửa: `when: result.stdout | length > 0` (hoặc `result.stdout != ''`).

**12.** `raw` gửi thẳng lệnh shell, không cần Python → dùng để mồi Python lên máy mới (hoặc thiết bị mạng không có Python). Không dùng cho mọi việc vì không idempotent, không trả kết quả có cấu trúc, không hỗ trợ check mode.

**13.**

| Plugin | Máy điều khiển cần | Máy đích cần |
|---|---|---|
| `ssh` | Client SSH, private key | sshd, port mở, public key, Python |
| `community.docker.docker` | Docker CLI kết nối được daemon | Container đang chạy, Python |
| `amazon.aws.aws_ssm` | `session-manager-plugin`, boto3/botocore, quyền IAM (SSM + S3 bucket trung chuyển) | SSM Agent online, đường ra endpoint SSM + S3, `curl`, Python |

**14.** Để mọi máy, mọi thời điểm chạy đúng code đã test; collection mới có thể đổi hành vi. Ví dụ thật: amazon.aws **12.0.0** (10/2026) bỏ hỗ trợ ansible-core < 2.18, nâng boto3/botocore tối thiểu lên 1.38.23, xóa tham số `placement_group`/`tenancy` của `ec2_instance` và `template` của `cloudformation`.

**15.** (a) Mật khẩu không bao giờ nằm trong Git, kể cả dạng mã hóa, và không đi qua máy điều khiển — `deploy.sh` trên EC2 tự đọc bằng instance role; (b) quyền đọc được kiểm soát bằng IAM và ghi lại trong CloudTrail; đổi mật khẩu ở một chỗ, không cần chạy lại playbook với mật khẩu vault.

## Bài tập tự làm (mục 14)

### Bài 1 — Inventory YAML

```yaml
# inventory.yml
all:
  children:
    lab:
      hosts:
        ans07-node1:
        ans07-node2:
        ans07-node3:
      vars:
        ansible_connection: community.docker.docker
        ansible_python_interpreter: /usr/bin/python3
```

`group_vars/` và `host_vars/` giữ nguyên (cùng thư mục với `inventory.yml`). So sánh: `ansible-inventory -i inventory.yml --host ans07-node3` và `-i inventory.ini` → cùng `site_color: tomato`, cùng biến kết nối.

### Bài 2 — Role hóa

```text
roles/web/
├── defaults/main.yml      # site_color: gray, site_owner: unknown
├── handlers/main.yml      # Reload nginx
├── tasks/main.yml         # 3 task của web.yml
└── templates/index.html.j2
```

```yaml
# web.yml
- name: Cài web server
  hosts: lab
  # không có become: container ans07-* đã là root và không có sudo (xem Bước 7 của bài)
  roles:
    - web
```

Nhớ đổi `src: templates/index.html.j2` thành `src: index.html.j2` — trong role, module `template` tự tìm trong `roles/web/templates/`. `defaults` của role có độ ưu tiên **thấp nhất** → `group_vars/lab.yml` (`steelblue`) thắng. Mục đích của `defaults`: cho role chạy được ngay cả khi người dùng không đặt biến nào, nhưng không bao giờ "giành" quyền quyết định của inventory.

### Bài 3 — Người dùng và thư mục

```yaml
- name: User hệ thống webops
  ansible.builtin.user:
    name: webops
    system: true
    shell: /usr/sbin/nologin
    create_home: false

- name: Thư mục site
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: webops
    group: webops
    mode: "0750"
  loop:
    - /srv/site
    - /srv/site/logs
    - /srv/site/cache
```

`user` với `system: true` tạo UID < 1000 và group cùng tên (giống `useradd --system` ở [Linux 03](../../01-LINUX/03-permissions-users-groups.md)).

### Bài 4 — Điều kiện boolean

```yaml
- name: Máy canary
  ansible.builtin.debug:
    msg: "máy canary"
  when: inventory_hostname is match('.*3$')
```

`is match(...)` là một **test** của Jinja2 → luôn trả boolean. Cách khác: `when: inventory_hostname.endswith('3')`. Sai: `when: "{{ inventory_hostname[-1] }}"` (chuỗi, và còn dùng `{{ }}` trong `when` — Ansible cảnh báo vì `when` vốn đã là biểu thức).

### Bài 5 — Check mode

```yaml
- name: Đọc phiên bản nginx
  ansible.builtin.command: nginx -v
  register: nginx_ver
  changed_when: false
  check_mode: false        # vẫn chạy khi --check vì nó chỉ đọc

- name: In phiên bản
  ansible.builtin.debug:
    msg: "{{ nginx_ver.stderr | default('chưa có nginx') }}"
```

Không có `check_mode: false`: module `command` bị bỏ qua trong check mode → `nginx_ver` không có `stderr` → task sau lỗi. `changed_when: false` để task đọc không bao giờ làm bẩn PLAY RECAP.

### Bài 6 — ansible-lint

Cảnh báo hay gặp với playbook của lab và cách xử lý:

| Quy tắc (ví dụ) | Ý nghĩa | Sửa |
|---|---|---|
| `fqcn[action-core]` | Thiếu tên đầy đủ module | `apt` → `ansible.builtin.apt` |
| `no-changed-when` | `command`/`shell` không có `changed_when` | Thêm `changed_when`/`creates` |
| `risky-file-permissions` | File tạo ra không ghi `mode` | Thêm `mode: "0644"` |
| `name[casing]` | Tên task không viết hoa chữ đầu | Viết hoa chữ đầu |
| `yaml[truthy]` | Dùng `yes`/`no` thay vì `true`/`false` | Dùng `true`/`false` |

Tên quy tắc cụ thể phụ thuộc phiên bản ansible-lint — đọc đúng thông báo trên máy bạn. Cảnh báo bạn quyết định giữ (ví dụ `command: nginx` trong container) → ghi lý do vào nhật ký, hoặc thêm comment `# noqa: <rule>` kèm giải thích.
