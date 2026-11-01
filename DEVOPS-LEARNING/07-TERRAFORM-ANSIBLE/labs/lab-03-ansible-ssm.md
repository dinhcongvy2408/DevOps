# Lab 03 — Ansible cài Docker và triển khai taskhub lên EC2 qua SSM (không port 22)

> ⏱️ ~3–4 giờ · Mức độ: 🟥 **Lab bắt buộc tuần 16** · Kiến thức cần có trước: [05. Ansible](../05-ansible-fundamentals.md) (đã làm lab local), [Lab 02 — Hạ tầng taskhub bằng Terraform](lab-02-taskhub-infra-terraform.md) (EC2 đang chạy), [AWS 04 — EC2 & Session Manager](../../06-AWS/04-ec2.md), [AWS 06 — AWS CLI](../../06-AWS/06-aws-cli.md)
> Môi trường: `[WSL]` máy điều khiển (Ansible, AWS CLI, session-manager-plugin), `[EC2]` `taskhub-app`, `[AWS Console]` chỉ để xem
> Phiên bản khi viết: ansible-core 2.21.5, amazon.aws 12.0.0, Session Manager plugin bản mới nhất từ AWS, Ubuntu 24.04 trên EC2

## 💰 Ước tính chi phí

| Tài nguyên | Đến từ | Chi phí trong lab |
|---|---|---|
| EC2 `t3.small` + EBS gp3 20 GiB + 1 Public IPv4 | [Lab 02](lab-02-taskhub-infra-terraform.md) (Terraform) | Giá theo giờ như v2/v3 — xem [AWS 11 — bảng chi phí](../../06-AWS/11-putting-it-together.md). Lab 3–4 giờ ≈ dưới 0,2 USD |
| S3 `taskhub-ansible-ssm-<account-id>` | Lab 02 | Vài KB file tạm, xóa ngay sau mỗi lần chạy → gần 0 |
| Session Manager | — | Phiên Session Manager tới EC2 không tính phí riêng (theo trang giá Systems Manager — tự kiểm tra lại) |
| Gói Docker, image tải về EC2 | Internet | Data **vào** AWS không tính phí |

⚠️ **Rủi ro chi phí lớn nhất: quên tắt EC2.** Học xong buổi → `terraform destroy` theo [Lab 02](lab-02-taskhub-infra-terraform.md) (hoặc ít nhất stop instance) và chạy `~/devops-lab/06-aws/find-leftovers.sh`.

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Sơ đồ](#2-sơ-đồ)
- [3. Điều kiện trước khi bắt đầu](#3-điều-kiện-trước-khi-bắt-đầu)
- [Phần A — Chuẩn bị máy điều khiển](#phần-a--chuẩn-bị-máy-điều-khiển)
- [Phần B — Inventory động](#phần-b--inventory-động)
- [Phần C — Kết nối qua SSM](#phần-c--kết-nối-qua-ssm)
- [Phần D — Role docker](#phần-d--role-docker)
- [Phần E — Role taskhub và triển khai](#phần-e--role-taskhub-và-triển-khai)
- [Phần F — Chứng minh idempotency](#phần-f--chứng-minh-idempotency)
- [Phần G — Thí nghiệm](#phần-g--thí-nghiệm)
- [Xử lý sự cố](#xử-lý-sự-cố)
- [Checklist hoàn thành](#checklist-hoàn-thành)
- [Dọn dẹp](#dọn-dẹp)
- [Câu hỏi sau lab](#câu-hỏi-sau-lab)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

- Viết playbook `infra/ansible/playbooks/site.yml` trong repo `taskhub`: cài Docker Engine + compose plugin + AWS CLI lên EC2, đưa `compose.yaml`, `compose.aws.yaml`, cấu hình nginx, `scripts/deploy.sh` lên `/opt/taskhub`, chạy `deploy.sh <tag>`.
- Kết nối bằng **`amazon.aws.aws_ssm`** — Security Group **không** có rule port 22.
- Tìm máy bằng **inventory động** `amazon.aws.aws_ec2` (tag `Project=taskhub`), không ghi IP/instance ID vào file.
- Lần chạy thứ hai: **`changed=0`**.
- Giải thích được đường đi của một task: WSL → S3 → SSM → EC2.

## 2. Sơ đồ

```text
 [WSL] infra/ansible/
   ansible-playbook playbooks/site.yml -e taskhub_image_tag=v0.6.0
        │
        │ 1. inventory/aws_ec2.yml: ec2:DescribeInstances (tag Project=taskhub, running)
        │    → host "taskhub-app", ansible_host = i-0abc…, bucket = taskhub-ansible-ssm-<owner_id>
        │
        │ 2. Mỗi task:
        │    a. upload file module (.py) ──────────────► S3 taskhub-ansible-ssm-<account>/i-0abc…/…
        │    b. ssm:StartSession (qua session-manager-plugin) ──► SSM Agent trên EC2
        │    c. EC2 chạy: curl <presigned URL> ◄─────────────────── tải module từ S3
        │                 python3 module.py  → kết quả JSON trả về qua phiên SSM
        │    d. xóa file tạm trên S3
        ▼
 EC2 taskhub-app (public subnet, SG chỉ 80/443, SSM Agent ra ngoài qua 443)
   /opt/taskhub/{compose.yaml, compose.aws.yaml, docker/nginx/default.conf, scripts/deploy.sh, .env}
   docker compose: nginx · taskhub · postgres
```

Điểm cần hiểu: **EC2 không cần quyền IAM đọc bucket**. Máy điều khiển ký **presigned URL** ([AWS 05 — S3](../../06-AWS/05-s3.md)) rồi gửi cho EC2 qua phiên SSM; EC2 chỉ `curl` URL đó. Ngược lại, **máy điều khiển** (bạn, qua `aws login`) cần `s3:PutObject/GetObject/DeleteObject/ListBucket/GetBucketLocation` trên bucket — user admin của bạn đã có.

## 3. Điều kiện trước khi bắt đầu

Kiểm tra từng dòng `[WSL]`:

```bash
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws sts get-caller-identity --query Arn --output text           # đã aws login chưa?

# EC2 do Terraform tạo đang chạy và có tag đúng
aws ec2 describe-instances \
  --filters Name=tag:Project,Values=taskhub Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{id:InstanceId,name:Tags[?Key==`Name`]|[0].Value,ip:PublicIpAddress}' \
  --output table

# SSM Agent đã "Online" (vài phút sau khi máy boot)
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{id:InstanceId,ping:PingStatus,platform:PlatformName}' --output table

# Bucket trung chuyển của Ansible (Terraform output ở Lab 02)
terraform -chdir="$HOME/projects/taskhub/infra/terraform/envs/dev" output -raw ansible_ssm_bucket; echo
aws s3api head-bucket --bucket "taskhub-ansible-ssm-$(aws sts get-caller-identity --query Account --output text)" && echo "bucket OK"
```

| Thiếu gì | Làm gì |
|---|---|
| Không có instance `running` | Chạy `terraform apply` ở [Lab 02](lab-02-taskhub-infra-terraform.md) |
| `PingStatus` không phải `Online` | Chờ thêm vài phút; vẫn không → instance role thiếu `AmazonSSMManagedInstanceCore` hoặc không có đường ra Internet ([AWS 04](../../06-AWS/04-ec2.md)) |
| Không có bucket | Thiếu resource bucket trong Terraform `envs/dev` — thêm theo Lab 02 |

Repo `~/projects/taskhub` phải có (từ v2/v3): `compose.yaml`, `compose.aws.yaml`, `docker/nginx/default.conf`, `scripts/deploy.sh` (có quyền thực thi trong Git), và tham số `/taskhub/dev/postgres-password` đã có trong Parameter Store (Terraform tạo ở Lab 02).

---

## Phần A — Chuẩn bị máy điều khiển

### A1. boto3 trong môi trường của Ansible `[WSL]`

Plugin `aws_ec2` và `aws_ssm` dùng thư viện Python **boto3**. Ansible cài bằng pipx sống trong venv riêng → phải "tiêm" boto3 **vào venv đó**, không phải vào Python hệ thống:

```bash
pipx inject ansible boto3 botocore
pipx runpip ansible show boto3 | head -2      # Version phải >= 1.38.23 (yêu cầu của amazon.aws 12)
```

### A2. Session Manager plugin `[WSL]`

Theo tài liệu AWS cho Ubuntu (x86_64):

```bash
cd /tmp
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
session-manager-plugin
```

Lệnh cuối không tham số in một dòng xác nhận cài thành công (minh họa: *"The Session Manager plugin was installed successfully. Use the AWS CLI to start a session."*). Plugin được cài vào `/usr/local/bin/session-manager-plugin` — đúng đường dẫn mặc định mà `aws_ssm` tìm trước tiên.

Thử luôn bằng AWS CLI (đây chính là thứ Ansible sẽ dùng bên dưới):

```bash
IID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=taskhub-app Name=instance-state-name,Values=running \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ssm start-session --target "$IID"     # vào được shell → gõ: whoami; exit
```

### A3. Thư mục Ansible trong repo và collection `[WSL]`

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c feat/ansible-ssm
mkdir -p infra/ansible/{inventory/group_vars,playbooks,roles}
cd infra/ansible
```

`requirements.yml`:

```yaml
collections:
  - name: amazon.aws
    version: "12.0.0"
  - name: community.docker
    version: "5.4.0"
```

`ansible.cfg` (tối thiểu — tự thêm dần):

```ini
[defaults]
inventory = inventory/aws_ec2.yml
roles_path = roles
interpreter_python = /usr/bin/python3
```

```bash
ansible-galaxy collection install -r requirements.yml
ansible-galaxy collection list amazon.aws
ansible --version | grep 'config file'     # phải trỏ vào infra/ansible/ansible.cfg
```

❓ `collection list` có thể in hai bản `amazon.aws` (bản bạn vừa cài và bản đi kèm gói `ansible`). Bản nào được dùng? Vì sao ghim `12.0.0`?

---

## Phần B — Inventory động

### B1. Viết `inventory/aws_ec2.yml` `[WSL]`

Yêu cầu (tự viết trước, đối chiếu [tài liệu plugin `aws_ec2`](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ec2_inventory.html)):

| Yêu cầu | Tùy chọn của plugin |
|---|---|
| Tên file **phải** kết thúc bằng `aws_ec2.yml` | (plugin từ chối file khác tên) |
| Plugin `amazon.aws.aws_ec2`, region `ap-southeast-1` | `plugin`, `regions` |
| Chỉ máy tag `Project=taskhub` **và** đang chạy | `filters` (`tag:Project`, `instance-state-name`) |
| Tên host = tag `Name` | `hostnames` |
| Nhóm theo tag `Env` → `env_dev` | `keyed_groups` (key `ec2_tags.Env`, prefix `env`) |
| Tắt biến cũ `tags` (deprecated) | `use_deprecated_tags: false` |
| `ansible_host` = instance ID; tên bucket SSM ghép từ account id | `compose` (`instance_id`, `owner_id`) |

<details>
<summary>Gợi ý cấp 1</summary>

Mặc định plugin lấy cả máy `stopped`, `stopping`, `pending` nếu bạn không lọc `instance-state-name`. Trong `compose`, giá trị là **biểu thức Jinja2**: chuỗi cố định phải nằm trong nháy đơn bên trong nháy kép, ví dụ `"'abc-' ~ owner_id"`.

</details>

<details>
<summary>Gợi ý cấp 2</summary>

```yaml
plugin: amazon.aws.aws_ec2
regions: [ap-southeast-1]
filters:
  tag:Project: taskhub
  instance-state-name: running
hostnames: [tag:Name]
use_deprecated_tags: false
keyed_groups:
  - key: ec2_tags.Env
    prefix: env
compose:
  ansible_host: instance_id
  # còn thiếu một dòng cho bucket
```

</details>

### B2. Kiểm tra `[WSL]`

```bash
ansible-inventory --graph
ansible-inventory --host taskhub-app | grep -E '"(ansible_host|ansible_aws_ssm_bucket_name|instance_type|owner_id)"'
```

Kết quả mong đợi (minh họa):

```text
@all:
  |--@ungrouped:
  |--@aws_ec2:
  |  |--taskhub-app
  |--@env_dev:
  |  |--taskhub-app
```

```text
    "ansible_aws_ssm_bucket_name": "taskhub-ansible-ssm-111122223333",
    "ansible_host": "i-0abc1234def567890",
    "instance_type": "t3.small",
    "owner_id": "111122223333",
```

❓ Stop instance (Console) rồi chạy lại `--graph`: `taskhub-app` còn không? Xóa dòng `instance-state-name` khỏi filter và chạy lại: giờ thì sao? Start lại máy trước khi sang phần C.

---

## Phần C — Kết nối qua SSM

### C1. Biến kết nối `inventory/group_vars/all.yml` `[WSL]`

```yaml
ansible_connection: amazon.aws.aws_ssm
ansible_aws_ssm_region: ap-southeast-1
```

⚠️ **Vị trí file quan trọng:** Ansible chỉ đọc `group_vars/` nằm **cạnh nguồn inventory** (ở đây là `inventory/`) hoặc **cạnh playbook** (`playbooks/`). Đặt `infra/ansible/group_vars/` (cạnh `ansible.cfg`) thì biến **không** được đọc, Ansible âm thầm dùng SSH → `UNREACHABLE`. Kiểm chứng: `ansible-inventory --host taskhub-app | grep ansible_connection`.

Vì sao phải ghi region: mặc định của plugin là `us-east-1`. Profile thì plugin đọc từ biến môi trường `AWS_PROFILE` — không ghi tên profile vào Git.

### C2. Ping và ad-hoc `[WSL]`

```bash
ansible env_dev -m ansible.builtin.ping
ansible env_dev -m ansible.builtin.command -a "whoami"
ansible env_dev -m ansible.builtin.command -a "whoami" --become
ansible env_dev -m ansible.builtin.setup -a "filter=ansible_distribution*"
```

❓ `whoami` không `--become` trả về user nào? (Tài liệu plugin: `aws_ssm` **không** dùng `ansible_user`; phiên SSM thường chạy bằng `ssm-user`.) Có `--become` thì sao?

### C3. Nhìn tận mắt file đi qua S3 `[WSL]`

Mở terminal thứ hai, theo dõi bucket trong lúc terminal một chạy `ansible env_dev -m ansible.builtin.setup > /dev/null`:

```bash
B="taskhub-ansible-ssm-$(aws sts get-caller-identity --query Account --output text)"
for i in $(seq 1 15); do aws s3 ls "s3://$B" --recursive; echo ---; sleep 1; done
```

❓ Thấy file có tiền tố là gì? Chạy xong còn file nào không? Vì sao tài liệu plugin khuyên bucket **không** bật versioning?

---

## Phần D — Role docker

Tự viết `roles/docker/tasks/main.yml`. Yêu cầu: kết quả giống [user-data.sh của Module 06](../../06-AWS/labs/reference-v3/user-data.sh) nhưng **mọi bước idempotent**:

| Bước | Module gợi ý | Lưu ý |
|---|---|---|
| Gói phụ thuộc `ca-certificates`, `curl`, `python3-debian` | `ansible.builtin.apt` + `update_cache`, `cache_valid_time` | `python3-debian` là thư viện mà `deb822_repository` cần trên máy đích |
| Repo apt của Docker (định dạng deb822, khóa GPG của Docker) | `ansible.builtin.deb822_repository` | `suites` lấy từ fact `distribution_release` (`noble`); `architectures` đổi `x86_64` → `amd64` |
| `apt update` **chỉ khi** repo vừa được thêm | `ansible.builtin.apt` + `when: <register> is changed` | Điều kiện phải là boolean |
| `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` | `ansible.builtin.apt` | Theo [tài liệu Docker](https://docs.docker.com/engine/install/ubuntu/) |
| Docker chạy + bật khi boot | `ansible.builtin.systemd_service` | EC2 có systemd (khác container ở bài 05) |
| AWS CLI v2 (cho `deploy.sh` đọc Parameter Store) | `ansible.builtin.command: snap install aws-cli --classic` | Bắt buộc `creates: /snap/bin/aws` |

Playbook tạm `playbooks/site.yml`:

```yaml
- name: Cấu hình máy chủ taskhub
  hosts: env_dev
  become: true
  roles:
    - docker
```

```bash
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/site.yml
ansible env_dev -m ansible.builtin.command -a "docker version --format '{{ '{{' }}.Server.Version{{ '}}' }}'" --become
```

> Dấu `{{ '{{' }}` trong lệnh cuối: Ansible coi `{{ … }}` là biến Jinja2, nên muốn gửi nguyên chữ `{{.Server.Version}}` cho `docker` phải "thoát" như vậy. Đơn giản hơn: `-a "docker --version"`.

❓ Máy do Terraform tạo ở Lab 02 có thể đã cài Docker bằng user data. Khi đó lần chạy đầu của role báo `ok` hay `changed` cho task cài gói? Điều đó nói gì về việc giữ cả user data lẫn Ansible?

---

## Phần E — Role taskhub và triển khai

### E1. Copy file từ repo — chọn cách lấy file

Hai cách đưa file triển khai lên máy:

| Cách | Ưu | Nhược |
|---|---|---|
| `git clone` repo trên EC2 (như v2) | Quen thuộc | EC2 cần git + quyền đọc repo; dễ lệch với bản trên laptop; Ansible khó biết "có gì đổi" |
| **Copy từ repo trên máy điều khiển** (module `copy`, `src` trỏ về gốc repo) | Máy chủ nhận đúng bản đang ở nhánh của bạn; module `copy` tự so checksum → biết chính xác file nào đổi | Chạy từ nhánh chưa merge sẽ đẩy file chưa review lên máy → **chỉ chạy từ `main`** |

Bộ tham khảo chọn cách 2 với biến `taskhub_repo_root: "{{ playbook_dir }}/../../.."` (playbook nằm ở `infra/ansible/playbooks/` → lên 3 cấp là gốc repo).

### E2. Yêu cầu của `roles/taskhub/tasks/main.yml`

1. Tạo `/opt/taskhub`, `/opt/taskhub/scripts`, `/opt/taskhub/docker/nginx` (root, `0755`) — **một** task + `loop`.
2. Copy `compose.yaml`, `compose.aws.yaml`, `scripts/deploy.sh` (`0755`) — **một** task + `loop`, `register` kết quả.
3. Copy `docker/nginx/default.conf` bằng task **riêng**, `notify` một handler restart container nginx (xem E3).
4. Đọc tag đang chạy trong `/opt/taskhub/.env` và kiểm tra container `taskhub` có đang chạy — hai task **chỉ đọc**: `changed_when: false`, `check_mode: false`, `failed_when: false` (lần đầu chưa có `.env`, chưa có Docker khi `--check`).
5. Chạy `/opt/taskhub/scripts/deploy.sh {{ taskhub_image_tag }}` **chỉ khi**: file ở bước 2 đổi, **hoặc** tag khác tag đang chạy, **hoặc** container không chạy. `changed_when: true`.
6. In output của `deploy.sh` khi nó chạy.

Và trong playbook: `pre_tasks` dùng `ansible.builtin.assert` bắt buộc có `taskhub_image_tag` và đúng định dạng (cùng regex với `deploy.sh`: 7 ký tự hex hoặc `vX.Y.Z[-…]`).

<details>
<summary>Gợi ý cấp 1 — điều kiện ở bước 5</summary>

Một `register` trên task có `loop` vẫn dùng được với test `is changed` (đúng nếu **ít nhất một** vòng lặp changed). Biến register của task bị lỗi/bỏ qua có thể không có `stdout` → dùng `| default('')`.

</details>

<details>
<summary>Gợi ý cấp 2</summary>

```yaml
  when: >-
    (taskhub_copy is changed)
    or ((taskhub_current_tag.stdout | default('') | trim) != taskhub_image_tag)
    or ((taskhub_running.stdout | default('') | trim | length) == 0)
```

Container `taskhub` tìm bằng label do Compose gắn: `docker ps -q --filter label=com.docker.compose.project=taskhub --filter label=com.docker.compose.service=taskhub --filter status=running`. Không dùng `docker compose ps` vì nó đọc `compose.yaml` và đòi biến `TASKHUB_IMAGE_TAG` có sẵn.

</details>

### E3. Vì sao handler nginx phải **restart** container

`compose.yaml` gắn `./docker/nginx/default.conf` vào container bằng **bind mount một file**. Module `copy` ghi nội dung mới ra file tạm rồi **đổi tên** đè lên file cũ (ghi nguyên tử — không bao giờ để lại file ghi dở). Đổi tên = file mới có **inode khác**. Bind mount một file gắn theo inode lúc container khởi động → container vẫn thấy **file cũ**, `nginx -s reload` đọc lại đúng file cũ đó. Restart container → Docker gắn lại theo đường dẫn → thấy file mới. Bạn sẽ kiểm chứng ở thí nghiệm G3.

### E4. Chạy `[WSL]`

```bash
cd ~/projects/taskhub/infra/ansible
ansible-playbook playbooks/site.yml -e taskhub_image_tag=v0.5.0
```

Dùng tag đã có trên GHCR (release gần nhất của v3, hoặc một `:<sha7>` từ trang Packages). Kiểm tra từ WSL:

```bash
APP_URL="http://$(terraform -chdir=../terraform/envs/dev output -raw public_ip)"
curl -fsS "$APP_URL/actuator/health"; echo
```

Đầu ra cuối playbook (minh họa):

```text
TASK [taskhub : In kết quả deploy.sh] ******************************************
ok: [taskhub-app] =>
    taskhub_deploy.stdout_lines:
    - '>> Triển khai taskhub:v0.5.0 (đang chạy: chưa có)'
    - '>> OK: taskhub:v0.5.0'

PLAY RECAP *********************************************************************
taskhub-app : ok=15   changed=9    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

---

## Phần F — Chứng minh idempotency

```bash
ansible-playbook playbooks/site.yml -e taskhub_image_tag=v0.5.0
```

PLAY RECAP phải là **`changed=0`**. Không phải → tìm task nào `changed`, sửa, chạy lại cho tới khi đạt. Chụp PLAY RECAP vào PR.

Đổi tag → chỉ phần triển khai chạy:

```bash
ansible-playbook playbooks/site.yml -e taskhub_image_tag=<một-tag-khác-có-trên-GHCR>
```

❓ Lần này có bao nhiêu task `changed`, là những task nào? Role `docker` có làm gì không?

---

## Phần G — Thí nghiệm

| # | Thí nghiệm | Cách làm | Câu hỏi cần trả lời trong nhật ký |
|---|---|---|---|
| G1 | **Check mode** | Sửa một dòng comment trong `compose.yaml` của repo → `ansible-playbook playbooks/site.yml -e taskhub_image_tag=<tag-đang-chạy> --check --diff` | Diff in ra file nào? Task `deploy.sh` báo gì trong check mode, vì sao? Trên EC2 file có đổi không (`aws ssm start-session` → `cat /opt/taskhub/compose.yaml`)? Hoàn tác thay đổi trong repo |
| G2 | **Thiếu tag / tag lạ** | Chạy không có `-e`; rồi `-e 'taskhub_image_tag=v1;reboot'` | `assert` chặn ở đâu? Vì sao kiểm tra ở cả playbook **và** `deploy.sh`? |
| G3 | **Bind mount và inode** | Thêm `add_header X-Lab-03 "ok" always;` vào `docker/nginx/default.conf` của repo. Tạm đổi handler thành `nginx -s reload` (`docker exec <id> nginx -s reload`), chạy playbook, `curl -sI $APP_URL` → có header? Đổi lại handler restart, sửa header thành `"ok2"`, chạy lại → có header? | Giải thích bằng khái niệm inode. Trên EC2 so `stat -c %i /opt/taskhub/docker/nginx/default.conf` với `docker exec <id> stat -c %i /etc/nginx/conf.d/default.conf` trước và sau khi copy |
| G4 | **group_vars đặt sai chỗ** | Chuyển `inventory/group_vars/` ra cạnh `ansible.cfg` → `ansible env_dev -m ping` | Thông báo lỗi là gì? Vì sao Ansible lại thử SSH? Chuyển về chỗ cũ |
| G5 | **Region sai** | Tạm xóa dòng `ansible_aws_ssm_region` → `ansible env_dev -m ping -vvv` | Plugin mặc định region nào? Lỗi xuất hiện ở bước nào (S3 hay SSM)? Khôi phục |
| G6 | **Máy mới hoàn toàn** | (Nếu còn thời gian) `terraform apply -replace=<địa-chỉ-resource-EC2>` ở Lab 02 → chờ SSM Online → chạy playbook một lần | Máy mới chạy app sau bao nhiêu phút, không đụng tay vào máy? So với v2 (làm tay) |

---

## Xử lý sự cố

Thông báo lỗi dưới đây là minh họa — tìm **ý chính**.

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra | Cách sửa |
|---|---|---|---|
| `ansible-inventory --graph` rỗng | Chưa `aws login`/hết phiên; sai region; filter tag sai; máy chưa `running`; tên file inventory không kết thúc bằng `aws_ec2.yml` | `aws sts get-caller-identity`; `aws ec2 describe-instances --filters …` cùng filter | Sửa filter/region; đăng nhập lại |
| `Failed to import the required Python library (botocore or boto3)` | boto3 chưa có trong venv pipx của Ansible | `pipx runpip ansible show boto3` | `pipx inject ansible boto3 botocore` |
| `UNREACHABLE` + nhắc tới `ssh` | `ansible_connection` không được đọc → Ansible dùng SSH mặc định | `ansible-inventory --host taskhub-app \| grep ansible_connection` | Đặt `group_vars/` cạnh inventory (C1) |
| `UNREACHABLE` + `session-manager-plugin` not found | Chưa cài plugin hoặc không nằm trong PATH | `which session-manager-plugin` | Cài theo A2 |
| `TargetNotConnected` / không mở được phiên | SSM Agent chưa Online; instance thiếu `AmazonSSMManagedInstanceCore`; không có đường ra Internet | `aws ssm describe-instance-information` | Chờ; sửa role/route trong Terraform |
| `AccessDenied` khi upload / `NoSuchBucket` | Bucket sai tên, sai account, đã bị destroy | `ansible-inventory --host taskhub-app \| grep bucket`; `aws s3api head-bucket` | Tạo bucket trong Terraform; sửa `compose` |
| Lỗi tải file trên EC2 / HTTP 307 | Bucket khác region với instance → URL chuyển hướng | Region bucket: `aws s3api get-bucket-location` | Tạo bucket cùng region; hoặc `ansible_aws_ssm_s3_addressing_style: virtual` (theo tài liệu plugin) |
| `curl: not found` trên EC2 | Plugin cần `curl` trên máy đích để tải module | `aws ssm start-session` → `which curl` | AMI Ubuntu có sẵn curl; nếu bị gỡ, cài bằng module `raw` |
| `[WARNING]: Platform linux on host … is using the discovered Python interpreter…` | Ansible tự dò Python | — | `interpreter_python = /usr/bin/python3` trong `ansible.cfg` |
| `deb822_repository` lỗi thiếu thư viện `debian` | Máy đích chưa có `python3-debian` | — | Cài `python3-debian` ở task trước (hoặc `install_python_debian: true` từ core 2.20) |
| `Conditionals must have a boolean result` | Điều kiện `when` trả chuỗi | Đọc dòng `when` được báo | Viết điều kiện boolean |
| Task `deploy.sh` lỗi: `aws: command not found` | AWS CLI (snap) chưa cài, hoặc PATH khi `sudo` không có `/snap/bin` | `which aws` trong phiên `--become` | Cài AWS CLI ở role docker; kiểm tra `secure_path` của sudo |
| Task `deploy.sh` lỗi: `ParameterNotFound` / `AccessDenied` với SSM | Chưa có tham số mật khẩu hoặc instance role thiếu quyền `ssm:GetParameter` | `aws ssm get-parameter --name /taskhub/dev/postgres-password` (từ WSL, không `--with-decryption`) | Terraform Lab 02 |
| Playbook chạy rất chậm | Mỗi task = upload S3 + phiên SSM mới | Chạy với `-vvv` xem thời gian | Bình thường với `aws_ssm`; giảm số task (gộp bằng `loop`), tắt `gather_facts` ở play không cần facts |

## Checklist hoàn thành

- [ ] `ansible-inventory --graph` thấy `taskhub-app` trong `env_dev`; không có IP/instance ID nào ghi tay trong repo.
- [ ] `ansible env_dev -m ping` → `pong` qua SSM; Security Group **không** có rule port 22.
- [ ] Playbook cài Docker + AWS CLI, đưa file lên `/opt/taskhub`, chạy `deploy.sh`; `curl $APP_URL/actuator/health` → `{"status":"UP"…}`.
- [ ] Chạy lần hai: **`changed=0`** (ảnh chụp PLAY RECAP trong PR).
- [ ] Đổi tag → chỉ phần triển khai chạy; thiếu tag / tag lạ → `assert` chặn.
- [ ] Làm xong G1–G5, ghi câu trả lời vào `week16/ansible-ssm.md` của repo nhật ký.
- [ ] PR `feat/ansible-ssm` merge vào `main` qua review của chính bạn, CI xanh.

## Dọn dẹp

Ansible không tạo tài nguyên AWS tính phí — chi phí đến từ hạ tầng của Lab 02.

```bash
# Không học tiếp hôm nay → xóa hạ tầng envs/dev (lớp bootstrap, bucket state/backup giữ nguyên)
terraform -chdir="$HOME/projects/taskhub/infra/terraform/envs/dev" destroy      # ⚠️ xóa EC2 và các tài nguyên envs/dev
~/devops-lab/06-aws/find-leftovers.sh ap-southeast-1                            # mong đợi: không còn EC2/EBS/IPv4

# Bucket trung chuyển phải rỗng sau mỗi lần chạy thành công
aws s3 ls "s3://taskhub-ansible-ssm-$(aws sts get-caller-identity --query Account --output text)" --recursive
```

Ngày mai dựng lại: `terraform apply` → chờ SSM Online → `ansible-playbook playbooks/site.yml -e taskhub_image_tag=<tag>`. Đây chính là mục tiêu "dựng lại từ số 0 trong < 30 phút" của [v4](../../12-PRACTICAL-PROJECT/milestones/v4-terraform.md).

## Câu hỏi sau lab

1. Liệt kê theo thứ tự các bước xảy ra khi Ansible chạy **một** task qua `aws_ssm`. EC2 cần quyền IAM gì để tải module từ S3, vì sao?
2. Vì sao inventory động tốt hơn ghi IP vào `inventory.ini` cho dự án này? (Gợi ý: stop/start, `terraform apply -replace`.)
3. Role `taskhub` quyết định "có cần chạy `deploy.sh` không" dựa vào ba điều kiện. Bỏ điều kiện thứ ba (container không chạy) thì tình huống nào sẽ bị bỏ sót?
4. Ranh giới trách nhiệm: Terraform, Ansible, `deploy.sh`, workflow `Deploy` của v3 — mỗi thứ làm gì? Khi đổi **chỉ** tag image, nên dùng công cụ nào, vì sao?
5. So sánh `aws_ssm` với SSH + mở port 22 tạm thời từ IP của bạn: lợi ích, chi phí, rủi ro (dùng làm nội dung cho ADR-0009 của v4).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [amazon.aws — connection `aws_ssm`](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ssm_connection.html) · [mã nguồn 12.0.0](https://github.com/ansible-collections/amazon.aws/blob/12.0.0/plugins/connection/aws_ssm.py) | Yêu cầu (plugin, curl, S3), presigned URL, quyền S3 của máy điều khiển, region mặc định `us-east-1`, `AWS_PROFILE`, khuyên tắt versioning | 2026-10-31 |
| [amazon.aws — inventory `aws_ec2`](https://docs.ansible.com/ansible/latest/collections/amazon/aws/aws_ec2_inventory.html) · [mã nguồn 12.0.0](https://github.com/ansible-collections/amazon.aws/blob/12.0.0/plugins/inventory/aws_ec2.py) | Tên file `aws_ec2.yml`, `filters`, `hostnames`, `keyed_groups`, `compose`, `use_deprecated_tags`, mặc định lấy cả máy stopped, `owner_id` | 2026-10-31 |
| [amazon.aws 12.0.0 — CHANGELOG](https://github.com/ansible-collections/amazon.aws/blob/12.0.0/CHANGELOG.rst) · [requirements.txt](https://github.com/ansible-collections/amazon.aws/blob/12.0.0/requirements.txt) | boto3/botocore ≥ 1.38.23, ansible-core ≥ 2.18 | 2026-10-31 |
| [AWS — Install the Session Manager plugin on Ubuntu](https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-debian-and-ubuntu.html) | Lệnh tải `.deb` và `dpkg -i` | 2026-10-31 |
| [ansible-core 2.21.5 — module `deb822_repository`](https://github.com/ansible/ansible/blob/v2.21.5/lib/ansible/modules/deb822_repository.py) | Tùy chọn, yêu cầu `python3-debian`, `install_python_debian` (2.20) | 2026-10-31 |
| [Docker Docs — Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) | Repo apt, danh sách gói, danh sách gói xung đột | 2026-10-31 |
| [Ansible — Installing Ansible (pipx inject)](https://github.com/ansible/ansible-documentation/blob/devel/docs/docsite/rst/installation_guide/intro_installation.rst) | `pipx inject` thêm thư viện vào venv của Ansible | 2026-10-31 |
