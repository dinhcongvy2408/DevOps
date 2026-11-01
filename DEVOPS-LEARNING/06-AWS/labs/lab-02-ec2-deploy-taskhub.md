# Lab 02 — Triển khai `taskhub` lên EC2 bằng Docker Compose (tuần 12)

> Mức độ: 🟥 Bắt buộc · Thời lượng: 4–5 giờ (chia 2 buổi được — xem "Dừng giữa chừng") · Kiến thức cần có trước: [Lab 01 — Tạo VPC bằng tay](lab-01-vpc-by-hand.md), [IAM](../02-iam.md), [EC2](../04-ec2.md), [AWS CLI](../06-aws-cli.md), release `v0.3.0` của [milestone v1](../../12-PRACTICAL-PROJECT/milestones/v1-ci.md)
> Môi trường: `[WSL]` (AWS CLI, curl), `[AWS Console]`, `[EC2]` (shell trên máy chủ qua Session Manager), `[GitHub]`
> Kết quả: `http://<IP-public>/api/tasks` trả lời từ Internet; EC2 không mở port 22; mật khẩu database không nằm trong Git, user data hay GitHub.

## Mục lục

- [0. Trước khi bắt đầu](#0-trước-khi-bắt-đầu)
- [1. Kiến trúc lab](#1-kiến-trúc-lab)
- [2. Chuẩn bị repo: compose triển khai + deploy.sh](#2-chuẩn-bị-repo-compose-triển-khai--deploysh)
- [3. Lưu mật khẩu database vào Parameter Store](#3-lưu-mật-khẩu-database-vào-parameter-store)
- [4. IAM role cho EC2](#4-iam-role-cho-ec2)
- [5. Security Group](#5-security-group)
- [6. User data](#6-user-data)
- [7. Khởi tạo EC2](#7-khởi-tạo-ec2)
- [8. Vào máy bằng Session Manager](#8-vào-máy-bằng-session-manager)
- [9. Đưa code lên và triển khai](#9-đưa-code-lên-và-triển-khai)
- [10. Smoke test từ laptop](#10-smoke-test-từ-laptop)
- [11. Thử nghiệm bắt buộc](#11-thử-nghiệm-bắt-buộc)
- [12. Kết quả mong đợi](#12-kết-quả-mong-đợi)
- [13. Lỗi thường gặp](#13-lỗi-thường-gặp)
- [14. Dừng giữa chừng và dọn dẹp](#14-dừng-giữa-chừng-và-dọn-dẹp)
- [15. Câu hỏi sau lab](#15-câu-hỏi-sau-lab)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 0. Trước khi bắt đầu

### 0.1. 💰 Ước tính chi phí

| Tài nguyên | Đơn giá (ap-southeast-1) | Lab này dùng | Ghi chú |
|---|---|---|---|
| EC2 `t3.small` (2 vCPU, 2 GiB) | Tự tra trên [AWS Pricing Calculator](https://calculator.aws/) — cỡ vài xu USD/giờ (giá `us-east-1` là 0,0208 USD/giờ theo [instances.vantage.sh](https://instances.vantage.sh/aws/ec2/t3.small); Singapore thường cao hơn) | 4–5 giờ cho lab, sau đó chạy khi học v3 | Free plan: trừ vào **credit**, không phải "750 giờ miễn phí" như gói cũ |
| EBS gp3 20 GiB | Tự tra trên Calculator (tính theo GB-tháng) | Tính cả khi instance **stop** | Chỉ hết tính khi volume bị xóa (terminate) |
| Public IPv4 | **0,005 USD/giờ** mỗi địa chỉ ([VPC pricing](https://aws.amazon.com/vpc/pricing/)) | 1 địa chỉ, khi instance chạy | IP tự cấp bị trả lại khi stop → hết tính |
| Parameter Store (Standard) | Không tính phí lưu trữ | 1 tham số | |
| Session Manager, Run Command | Không tính phí cho EC2 | | |
| Data transfer | Rất nhỏ (pull image vài trăm MB từ GHCR là traffic **vào**) | | |

**Ghi lại số dư credit trước khi bắt đầu** (`[AWS Console]` Billing and Cost Management → Credits) và **sau khi xong** — đó là chi phí thật của lab, đưa vào bảng chi phí của dự án.

⚠️ Mọi lệnh tạo hoặc xóa tài nguyên đều được đánh dấu ⚠️. Đọc phần giải thích trước, chạy sau. Tôi (Claude) không chạy lệnh AWS nào — bạn tự chạy.

### 0.2. Kiểm tra điều kiện `[WSL]`

```bash
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws --version                                  # >= 2.32.0 (cần cho aws login)
aws login                                      # nếu phiên đã hết hạn
aws sts get-caller-identity --query Arn --output text
```

```text
arn:aws:iam::111122223333:user/phuong-admin          ← minh họa
```

Tìm lại các ID từ Lab 01 (VPC, subnet public-a) và lưu vào biến shell — các bước sau dùng chúng:

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc \
  --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=taskhub-public-a \
  --query 'Subnets[0].SubnetId' --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "$VPC_ID $SUBNET_ID $ACCOUNT_ID"
```

```text
vpc-0a1b2c3d4e5f60718 subnet-0123456789abcdef0 111122223333      ← minh họa
```

Một trong ba giá trị là `None` → Lab 01 chưa xong hoặc tên tag khác. Kiểm tra route table của `taskhub-public-a` **có** `0.0.0.0/0 → igw-...` — không có thì EC2 không tải được Docker, không nói chuyện được với SSM (lỗi số 1 ở mục 13).

Kiểm tra image cần triển khai **có thật và public** (không cần đăng nhập):

```bash
docker manifest inspect ghcr.io/<github-user>/taskhub:v0.3.0 > /dev/null && echo "image OK"
```

> Nếu WSL báo không kết nối được Docker, xem bảng lỗi ở [Docker bài 08](../../04-DOCKER/08-container-troubleshooting.md) — hoặc kiểm tra bằng trình duyệt: trang Packages của repo phải hiện `v0.3.0` và chữ **Public**.

---

## 1. Kiến trúc lab

```text
                       Internet
                          │  TCP 80
                          ▼
┌──────────────── VPC taskhub-vpc 10.20.0.0/16 ─────────────────────────────────────┐
│  route table public: 10.20.0.0/16 → local, 0.0.0.0/0 → igw                        │
│  ┌──────── subnet taskhub-public-a 10.20.1.0/24 (ap-southeast-1a) ─────────────┐  │
│  │  SG taskhub-web-sg: vào 80 từ 0.0.0.0/0 · KHÔNG có 22                        │  │
│  │  ┌──────── EC2 taskhub-app (t3.small, Ubuntu 24.04, IMDSv2) ─────────────┐   │  │
│  │  │ instance profile taskhub-ec2-role                                      │   │  │
│  │  │  ├─ AmazonSSMManagedInstanceCore  → Session Manager, Run Command       │   │  │
│  │  │  └─ taskhub-ec2-app               → đọc /taskhub/dev/* (Parameter St.) │   │  │
│  │  │ /opt/taskhub (git clone)                                               │   │  │
│  │  │  docker compose: nginx:80 ─► taskhub:8080 ─► postgres:5432 (pgdata)    │   │  │
│  │  └────────────────────────────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────┘
   EC2 ──ra ngoài 443──► ghcr.io (pull image) · ssm/ssmmessages/ec2messages (SSM Agent) · download.docker.com
   Bạn ──aws ssm start-session──► SSM ──(kênh do Agent mở RA ngoài)──► shell trên EC2   (không cần port 22)
```

Hai điểm then chốt:

1. **SSM Agent tự mở kết nối RA ngoài** tới dịch vụ SSM (HTTPS 443). Session Manager đi ngược lại kênh đó → Security Group không cần mở cổng **vào** nào cho quản trị.
2. **Instance role** cho EC2 quyền AWS tạm thời, tự xoay vòng, qua IMDS. Không có access key nào nằm trên máy chủ.

---

## 2. Chuẩn bị repo: compose triển khai + deploy.sh

Làm trên nhánh `feat/aws-ec2-deploy` của repo `taskhub` `[WSL]`, merge qua PR như mọi thay đổi khác (CI phải xanh).

### 2.1. Tách compose: triển khai vs phát triển

Ở v0, service `taskhub` có cả `build:` lẫn `image: taskhub:local`. Server **không bao giờ build** — nó chỉ kéo image đã được CI test và quét. Áp dụng cách tách ở [Module 05 — lời giải bài 05](../../05-CICD/solutions/05-solutions.md) (bài tập 4):

| File | Dùng ở | Service `taskhub` |
|---|---|---|
| `compose.yaml` | EC2 (và laptop) | `image: ghcr.io/<github-user>/taskhub:${TASKHUB_IMAGE_TAG:?set TASKHUB_IMAGE_TAG in .env}` — **không** `build:` |
| `compose.override.yaml` | Chỉ laptop — Compose **tự gộp** khi bạn chạy `docker compose ...` không có `-f` | `build:` + `image: taskhub:local` |

Tên biến `TASKHUB_IMAGE_TAG` đã dùng từ [Docker bài 06](../../04-DOCKER/06-registry.md) — giữ nguyên, đừng đặt tên khác.

⚠️ Bẫy: Compose **thay biến trước khi gộp file**. `compose.yaml` có `${TASKHUB_IMAGE_TAG:?...}` → trên laptop, `.env` cũng phải có dòng `TASKHUB_IMAGE_TAG=dev` (giá trị gì cũng được, override thay image). Thêm dòng đó vào `.env.example`.

Kiểm tra trên laptop:

```bash
docker compose config | grep -E 'image:|dockerfile'           # laptop: taskhub:local + build
docker compose -f compose.yaml config | grep -E 'image:'       # triển khai: ghcr.io/...:<tag>
```

### 2.2. `scripts/deploy.sh` cho EC2

Bắt đầu từ `scripts/deploy.sh` bạn viết ở [Module 05 bài 05](../../05-CICD/05-deployment-strategies-rollback.md) (bài tập 4). Bản cho EC2 cần thêm:

| Thêm | Vì sao |
|---|---|
| Kiểm tra định dạng tag: chỉ nhận `^[0-9a-f]{7}$` hoặc `^v[0-9]+\.[0-9]+\.[0-9]+(-...)?$` | Từ v3, tag đến từ GitHub Actions — chuỗi lạ không bao giờ được chạm tới shell |
| Đọc mật khẩu: `aws ssm get-parameter --name /taskhub/dev/postgres-password --with-decryption --query Parameter.Value --output text` rồi ghi dòng `POSTGRES_PASSWORD=` vào `.env` | Mật khẩu chỉ sống ở Parameter Store; `.env` trên server được tạo lại mỗi lần deploy |
| `chmod 600 .env`; chỉ thay **đúng dòng** cần đổi, không ghi đè cả file | `.env` chứa mật khẩu |
| `NGINX_HOST_PORT=80` nếu `.env` chưa có | Trên EC2 nginx nghe cổng 80 (laptop: 8000) |
| `docker compose -f compose.yaml ...` (chỉ định file) | Không gộp `compose.override.yaml` → không bao giờ build trên server |
| `--wait-timeout 180` | Healthcheck có `start_period: 60s`; `t3.small` khởi động Spring Boot chậm hơn laptop |

Thêm một dòng vào service `taskhub` của `compose.yaml`: **`mem_limit: 768m`**. Image chạy JVM với `-XX:MaxRAMPercentage=75.0` ([Docker bài 03](../../04-DOCKER/03-dockerfile-multistage.md)). Có giới hạn cgroup → heap tối đa tính theo 768 MiB. Không có → JVM tính theo **toàn bộ 2 GiB** của `t3.small`, có thể giành RAM của PostgreSQL và nginx → OOM killer ([bài 04 — EC2](../04-ec2.md)). Kiểm tra sau khi triển khai: `sudo docker stats --no-stream` — cột `MEM USAGE / LIMIT` của taskhub phải hiện `/ 768MiB`.

Nhớ: `git update-index --chmod=+x scripts/deploy.sh` (commit từ Windows có thể mất bit thực thi — lỗi đã gặp ở [Break-fix CI](../../05-CICD/labs/break-fix-01/README.md)).

Bản tham khảo hoàn chỉnh: [reference-v3/scripts/deploy.sh](reference-v3/scripts/deploy.sh) — ⚠️ mở sau khi tự viết xong.

### 2.3. Phát hành

PR → CI xanh → merge → chờ CI trên `main` xanh → `git tag -a v0.4.0 -m "v2: deploy lên EC2"` → `git push origin v0.4.0`. Workflow `Release` (v1) gắn tag `:v0.4.0` cho image của commit đó. Image **không đổi code ứng dụng** so với `v0.3.0` cũng không sao — phiên bản đánh dấu cả thay đổi cách triển khai.

---

## 3. Lưu mật khẩu database vào Parameter Store

⚠️ Tạo tài nguyên (không tính phí với tầng Standard) `[WSL]`:

```bash
DB_PW="$(openssl rand -hex 24)"            # 48 ký tự 0-9a-f: không có ký tự đặc biệt gây lỗi .env/shell
aws ssm put-parameter \
  --name /taskhub/dev/postgres-password \
  --type SecureString \
  --value "$DB_PW" \
  --description "Mat khau PostgreSQL cua taskhub (dev)" \
  --tags Key=Project,Value=taskhub Key=Env,Value=dev Key=Owner,Value=phuong Key=ManagedBy,Value=manual
unset DB_PW
```

```text
{
    "Version": 1,
    "Tier": "Standard"
}
```

| Tham số | Ý nghĩa |
|---|---|
| `--name /taskhub/dev/...` | Tên phân cấp → IAM policy cho phép đọc **cả nhánh** `/taskhub/dev/*` và không gì khác |
| `--type SecureString` | Giá trị được mã hóa bằng KMS (mặc định key `aws/ssm`) |
| `openssl rand -hex 24` | Mật khẩu ngẫu nhiên 24 byte; chỉ chữ số hex → không cần lo ký tự `$`, `/`, dấu cách trong `.env` |
| `unset DB_PW` | Không để mật khẩu nằm trong biến shell. (Giá trị vẫn có thể hiện trong danh sách process vài mili giây khi lệnh chạy — chấp nhận được trên laptop cá nhân) |

Kiểm tra (không giải mã, rồi giải mã):

```bash
aws ssm get-parameter --name /taskhub/dev/postgres-password --query Parameter.Value --output text
aws ssm get-parameter --name /taskhub/dev/postgres-password --with-decryption \
  --query Parameter.Value --output text | wc -c          # 49 (48 ký tự + xuống dòng)
```

Lần đầu in ra chuỗi mã hóa dài, lần sau mới là giá trị thật. Không in mật khẩu ra màn hình khi không cần.

> **PostgreSQL chỉ đọc `POSTGRES_PASSWORD` khi volume `pgdata` còn trống** ([Docker bài 04](../../04-DOCKER/04-volumes-networks-env.md)). Đổi giá trị trong Parameter Store sau khi database đã khởi tạo **không** đổi mật khẩu trong database → app báo `password authentication failed`. Đổi mật khẩu thật sự cần `ALTER USER` — bài tập ở mục 15.

---

## 4. IAM role cho EC2

Cần ba thứ: **role** (ai được nhận: dịch vụ EC2), **policy** (được làm gì), **instance profile** (cái "vỏ" để gắn role vào EC2). Lý thuyết ở [bài IAM](../02-iam.md).

Tạo thư mục làm việc `[WSL]`:

```bash
mkdir -p ~/devops-lab/06-aws/lab-02 && cd ~/devops-lab/06-aws/lab-02
```

`ec2-trust.json` — **ai** được nhận role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

`ec2-app-policy.json` — ở v2 chỉ cần đọc tham số của dự án (thay `111122223333` bằng `$ACCOUNT_ID` của bạn):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadTaskhubParameters",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParameters"],
      "Resource": "arn:aws:ssm:ap-southeast-1:111122223333:parameter/taskhub/dev/*"
    }
  ]
}
```

Vì sao không cần `kms:Decrypt`? Tham số dùng key mặc định `aws/ssm`; theo [tài liệu KMS về Parameter Store](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html), bạn không thể đặt chính sách truy cập riêng cho key này — quyền đọc được kiểm soát bằng `ssm:GetParameter`. Dùng customer managed key thì khác (phải thêm `kms:Decrypt`). v3 bổ sung quyền ghi CloudWatch Logs vào **chính policy này** (bản đầy đủ: [reference-v3/iam/taskhub-ec2-app-policy.json](reference-v3/iam/taskhub-ec2-app-policy.json)). Quyền S3 cho backup thì nằm ở một inline policy **riêng** `taskhub-ec2-s3-backup` mà bạn tạo ở [bài 05 — S3](../05-s3.md) — mỗi policy một mục đích, dễ đọc và dễ gỡ.

⚠️ Tạo tài nguyên IAM (không tính phí):

```bash
sed -i "s/111122223333/${ACCOUNT_ID}/g" ec2-app-policy.json

aws iam create-role --role-name taskhub-ec2-role \
  --assume-role-policy-document file://ec2-trust.json \
  --tags Key=Project,Value=taskhub Key=Env,Value=dev Key=Owner,Value=phuong Key=ManagedBy,Value=manual

aws iam attach-role-policy --role-name taskhub-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam put-role-policy --role-name taskhub-ec2-role \
  --policy-name taskhub-ec2-app --policy-document file://ec2-app-policy.json

aws iam create-instance-profile --instance-profile-name taskhub-ec2-role
aws iam add-role-to-instance-profile --instance-profile-name taskhub-ec2-role --role-name taskhub-ec2-role
```

| Lệnh | Làm gì |
|---|---|
| `create-role` + trust policy | Tạo role mà chỉ dịch vụ EC2 nhận được |
| `attach-role-policy ... AmazonSSMManagedInstanceCore` | Policy do AWS quản lý: đủ quyền để SSM Agent đăng ký, nhận lệnh, mở phiên Session Manager |
| `put-role-policy` | Policy **inline** gắn chặt với role — xóa role là xóa luôn. Hợp với quyền chỉ role này dùng |
| `create-instance-profile` + `add-role-to-instance-profile` | Console tự làm bước này khi bạn tạo role cho EC2; CLI thì phải tự làm. Đặt cùng tên với role cho dễ nhớ |

Kiểm tra:

```bash
aws iam list-attached-role-policies --role-name taskhub-ec2-role --query 'AttachedPolicies[].PolicyName'
aws iam list-role-policies --role-name taskhub-ec2-role
aws iam get-instance-profile --instance-profile-name taskhub-ec2-role \
  --query 'InstanceProfile.Roles[].RoleName'
```

> IAM có **độ trễ lan truyền**: dùng instance profile ngay sau khi tạo đôi khi báo `Invalid IAM Instance Profile name`. Chờ 10–20 giây rồi thử lại (mục 13).

---

## 5. Security Group

⚠️ Tạo tài nguyên (không tính phí):

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name taskhub-web-sg \
  --description "taskhub: HTTP from Internet, no SSH" \
  --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=taskhub-web-sg},{Key=Project,Value=taskhub},{Key=Env,Value=dev},{Key=Owner,Value=phuong},{Key=ManagedBy,Value=manual}]' \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description="HTTP from Internet"}]'

aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].{In:IpPermissions,Out:IpPermissionsEgress}'
```

Quan sát: chiều **vào** chỉ có TCP 80; chiều **ra** mặc định cho phép tất cả (`IpProtocol: -1`, `0.0.0.0/0`) — EC2 cần ra ngoài để tải Docker, pull image, nói chuyện với SSM. Vì SG **có trạng thái** (stateful), gói trả lời của các kết nối đó tự được cho vào ([bài VPC](../03-vpc-networking.md)).

**Không có port 22.** Toàn bộ quản trị đi qua Session Manager. Nếu bạn muốn thử SSH để so sánh: chỉ mở `22` từ `<IP-của-bạn>/32`, thử xong **xóa rule ngay** (`revoke-security-group-ingress`), và ghi vào nhật ký vì sao không giữ.

---

## 6. User data

User data là script **cloud-init** chạy **một lần**, bằng root, ở lần khởi động đầu tiên. Ta dùng nó để cài phần mềm nền — không dùng để triển khai app (app thay đổi thường xuyên, user data thì không chạy lại).

Tạo `user-data.sh` `[WSL]` (trong `~/devops-lab/06-aws/lab-02`):

```bash
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Docker Engine + compose plugin — theo docs.docker.com/engine/install/ubuntu
apt-get update
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# AWS CLI v2 — gói snap chính thức (deploy.sh cần để đọc Parameter Store)
snap install aws-cli --classic

echo "user-data hoàn tất: $(docker --version); $(aws --version)"
```

| Dòng | Vì sao |
|---|---|
| `set -euo pipefail` | Một bước hỏng → dừng ngay, thay vì chạy tiếp và để lại máy cài dở mà trông như "xong" ([Linux bài 06](../../01-LINUX/06-bash-scripting.md)) |
| `DEBIAN_FRONTEND=noninteractive`, `-y` | Không ai ở đó để bấm "Y" |
| Repo apt của Docker, không phải gói `docker.io` của Ubuntu | Đúng hướng dẫn chính thức, có compose plugin mới (`docker compose ...`) |
| `<<EOF` không có nháy | Cố ý: để `$(. /etc/os-release ...)` được thay bằng tên bản Ubuntu (`noble`) khi script chạy |
| **Không có** mật khẩu, token, `git clone` repo private | Ai có quyền `ec2:DescribeInstanceAttribute` đều đọc được user data (thử nghiệm E5) |

Bản tham khảo: [reference-v3/user-data.sh](reference-v3/user-data.sh). Kiểm tra cú pháp trước khi dùng: `bash -n user-data.sh`.

---

## 7. Khởi tạo EC2

### 7.1. Chọn AMI

Không chép AMI ID từ tutorial — mỗi Region một ID, và Canonical phát hành bản mới thường xuyên. Hỏi **tham số công khai** của Canonical trong Parameter Store:

```bash
AMI_ID=$(aws ssm get-parameters \
  --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameters[0].Value' --output text)
echo "$AMI_ID"
```

```text
ami-0abcdef1234567890          ← minh họa — của bạn sẽ khác
```

Kiểm tra AMI đó đúng là của Canonical và tên ổ gốc:

```bash
aws ec2 describe-images --image-ids "$AMI_ID" \
  --query 'Images[0].{Name:Name,Owner:OwnerId,Root:RootDeviceName}'
aws ssm get-parameters --names /aws/service/canonical/meta/publisher-id \
  --query 'Parameters[0].Value' --output text          # phải trùng Owner ở trên
```

Ghi lại `RootDeviceName` (thường là `/dev/sda1` với Ubuntu) — bước sau cần đúng tên này.

### 7.2. Kiểm tra loại instance thuộc Free plan

```bash
aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[*].[InstanceType]" --output text | sort
```

`t3.small` phải có trong danh sách. Vì sao không `t3.micro` (1 GiB)? JVM của Spring Boot + PostgreSQL + nginx + Docker + SSM Agent cùng chạy — 1 GiB rất sát, dễ bị OOM killer ([Linux bài 07](../../01-LINUX/07-logs-monitoring-troubleshooting.md)). Đánh đổi: `t3.small` tiêu credit nhanh hơn. Ghi quyết định này vào ADR của v2.

### 7.3. ⚠️ Khởi tạo (bắt đầu tính tiền)

```bash
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.small \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --associate-public-ip-address \
  --iam-instance-profile Name=taskhub-ec2-role \
  --metadata-options 'HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=1' \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","Encrypted":true,"DeleteOnTermination":true}}]' \
  --user-data file://user-data.sh \
  --tag-specifications \
    'ResourceType=instance,Tags=[{Key=Name,Value=taskhub-app},{Key=Project,Value=taskhub},{Key=Env,Value=dev},{Key=Owner,Value=phuong},{Key=ManagedBy,Value=manual}]' \
    'ResourceType=volume,Tags=[{Key=Name,Value=taskhub-app-root},{Key=Project,Value=taskhub},{Key=Env,Value=dev},{Key=Owner,Value=phuong},{Key=ManagedBy,Value=manual}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "$INSTANCE_ID"
```

| Tham số | Ý nghĩa và lý do |
|---|---|
| `--subnet-id` (public-a) + `--associate-public-ip-address` | Cần IP public để người dùng vào cổng 80 **và** để EC2 ra Internet qua IGW (không có NAT Gateway) |
| `--iam-instance-profile` | Gắn role ở mục 4 |
| `HttpTokens=required` | Chỉ cho **IMDSv2** (phải lấy token bằng `PUT` trước) — chặn kiểu tấn công SSRF đọc trộm quyền qua IMDSv1 |
| `HttpPutResponseHopLimit=1` | Gói trả lời token chỉ đi được **1 bước mạng**. Process trên host lấy được; container sau bridge (thêm 1 bước) **không** lấy được → app bị hack cũng không mượn được quyền của instance role. Thử nghiệm E6 kiểm chứng |
| `DeviceName` = tên ổ gốc ở 7.1 | Sai tên → AWS tạo **thêm** một ổ thay vì sửa ổ gốc |
| `Encrypted: true` | Mã hóa EBS bằng key mặc định — không tốn thêm, không có lý do để tắt |
| `DeleteOnTermination: true` | Terminate thì volume bị xóa theo → không còn "volume mồ côi" âm thầm tính tiền |
| `--user-data file://...` | CLI tự mã hóa base64 |
| Tag `Project=taskhub` | v3: role deploy **chỉ** được gửi lệnh tới instance có tag này. Thiếu tag = deploy bị từ chối |

Chờ máy sẵn sàng (2–4 phút):

```bash
aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "$PUBLIC_IP"
```

Kiểm tra EC2 đã đăng ký với SSM (có thể mất thêm 1–2 phút sau `status-ok`):

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].{Ping:PingStatus,Agent:AgentVersion,OS:PlatformName}'
```

```text
{ "Ping": "Online", "Agent": "3.3.x.x", "OS": "Ubuntu" }          ← minh họa
```

`null` sau 5 phút → mục 13, dòng "EC2 không hiện trong Session Manager".

---

## 8. Vào máy bằng Session Manager

Hai cách:

- **Không cần cài gì:** `[AWS Console]` EC2 → chọn `taskhub-app` → **Connect** → tab **Session Manager** → **Connect**.
- **Từ WSL:** cần cài **Session Manager plugin** cho AWS CLI (gói `.deb` — làm theo [hướng dẫn chính thức](https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-debian-and-ubuntu.html); bạn tự quyết định có cài hay không). Rồi:

```bash
aws ssm start-session --target "$INSTANCE_ID"
```

Phiên mở ra bằng user `ssm-user` (có sudo), shell mặc định là `sh`. Gõ `bash` cho quen tay. `[EC2]`:

```bash
whoami                                   # ssm-user
sudo cloud-init status --wait            # status: done   (error → đọc log bên dưới)
docker --version && docker compose version
aws --version
sudo tail -n 20 /var/log/cloud-init-output.log
```

User data lỗi ở đâu → `/var/log/cloud-init-output.log` có câu trả lời (đọc từ dưới lên, tìm dòng lỗi **đầu tiên** sau lệnh cuối cùng chạy được — cách đọc log ở [Linux bài 07](../../01-LINUX/07-logs-monitoring-troubleshooting.md)).

Kiểm tra máy **thấy** instance role (đây là IMDSv2: lấy token rồi mới hỏi):

```bash
TOKEN=$(curl -sS -X PUT http://169.254.169.254/latest/api/token \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
aws sts get-caller-identity --query Arn --output text
```

```text
taskhub-ec2-role
arn:aws:sts::111122223333:assumed-role/taskhub-ec2-role/i-0123456789abcdef0      ← minh họa
```

AWS CLI trên EC2 tự lấy quyền qua IMDS — không có file `~/.aws/credentials` nào.

---

## 9. Đưa code lên và triển khai

`[EC2]` (trong phiên Session Manager):

```bash
sudo git clone https://github.com/<github-user>/taskhub.git /opt/taskhub
cd /opt/taskhub
sudo git checkout v0.4.0                  # đúng phiên bản compose + deploy.sh của release
ls -l scripts/deploy.sh                   # phải có x: -rwxr-xr-x
```

Repo **public** nên clone không cần token. `git checkout v0.4.0` → HEAD tách rời (detached) đúng tại tag — bạn biết chính xác cấu hình nào đang chạy ([Git bài 01](../../03-GIT/01-git-fundamentals-internals.md)).

Triển khai:

```bash
sudo /opt/taskhub/scripts/deploy.sh v0.4.0
```

```text
>> Triển khai taskhub:v0.4.0 (đang chạy: chưa có)
[+] Pulling 1/1
 ✔ taskhub Pulled
[+] Running 4/4
 ✔ Network taskhub_default       Created
 ✔ Container taskhub-postgres-1  Healthy
 ✔ Container taskhub-taskhub-1   Healthy
 ✔ Container taskhub-nginx-1     Healthy
>> OK: taskhub:v0.4.0
```

(minh họa — dòng `Healthy` của nginx có thể khác vì nginx không có healthcheck)

Lần đầu mất 1–3 phút (pull `postgres:17`, `nginx`, image taskhub). Kiểm tra trên máy:

```bash
cd /opt/taskhub
sudo docker compose -f compose.yaml ps
sudo ls -l .env                                    # -rw------- root root
sudo grep -c POSTGRES_PASSWORD .env                # 1 — đừng cat file này ra màn hình
curl -s localhost/actuator/health                  # {"status":"UP"}
```

`deploy.sh` chạy bằng `sudo` vì: `/opt/taskhub` thuộc root, `.env` chỉ root đọc được, và Docker socket cần quyền root. Không thêm `ssm-user` vào nhóm `docker` — nhóm đó **tương đương root** ([Docker bài 07](../../04-DOCKER/07-docker-security.md)).

---

## 10. Smoke test từ laptop

`[WSL]`:

```bash
curl -fsS "http://$PUBLIC_IP/actuator/health"; echo
curl -i -X POST "http://$PUBLIC_IP/api/tasks" \
  -H 'Content-Type: application/json' -d '{"title":"Task đầu tiên trên AWS"}'
curl -s "http://$PUBLIC_IP/api/tasks"; echo
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "http://$PUBLIC_IP:8080/"   # 000 — SG chặn
nc -vz -w 3 "$PUBLIC_IP" 22                                                        # timeout — không có SSH
```

Hai dòng cuối chứng minh **chỉ** cổng 80 mở. `000`/timeout (gói bị SG lặng lẽ bỏ) khác với `Connection refused` (tới được máy nhưng không ai nghe) — phân biệt ở [Networking bài 08](../../02-NETWORKING/08-network-troubleshooting-tools.md).

---

## 11. Thử nghiệm bắt buộc

Ghi **thao tác → quan sát → giải thích** vào `docs/experiments/v2-tests.md` của repo.

| # | Thử nghiệm | Cách làm | Bạn phải giải thích được |
|---|---|---|---|
| E1 | **Stop/start đổi IP** | ⚠️ `aws ec2 stop-instances --instance-ids "$INSTANCE_ID"` → `wait instance-stopped` → `start-instances` → `wait instance-status-ok` → lấy lại `PublicIpAddress` | IP public **đổi**; IP private (10.20.1.x) **giữ nguyên**. App có tự chạy lại không, vì sao (gợi ý: `systemctl is-enabled docker` + `restart: unless-stopped`)? Dữ liệu task còn không (volume `pgdata` nằm trên EBS)? Hệ quả với người dùng và với v3 (`APP_URL`)? Hai cách giữ địa chỉ cố định và giá của chúng (Elastic IP vẫn 0,005 USD/giờ, **kể cả khi instance stop**; Route 53 cần domain) |
| E2 | **Reboot** | `aws ec2 reboot-instances ...`, đợi 1–2 phút, gọi lại API | IP **không** đổi khi reboot (khác stop/start). Container trở lại nhờ đâu? Đo thời gian từ lúc reboot tới khi `/actuator/health` trả `UP` |
| E3 | **Process app bị "crash"** | `[EC2]` `PID=$(sudo docker inspect -f '{{.State.Pid}}' taskhub-taskhub-1)` → `sudo kill -9 "$PID"` → `watch sudo docker compose -f compose.yaml ps` | Container tự khởi động lại (`RestartCount` tăng — `docker inspect -f '{{.RestartCount}}'`). So sánh: `sudo docker stop taskhub-taskhub-1` thì **không** tự lại — chính sách `unless-stopped` coi đó là bạn chủ động dừng. 🟨 Thử thêm `docker kill` và **ghi lại kết quả thật** (tài liệu và các bài viết không thống nhất về trường hợp này) |
| E4 | **Mật khẩu có lộ ở đâu không?** | (a) `[WSL]` `aws ec2 describe-instance-attribute --instance-id "$INSTANCE_ID" --attribute userData --query UserData.Value --output text \| base64 -d \| grep -i pass` (b) `git grep -i password` trong repo (c) `[EC2]` `sudo docker inspect taskhub-taskhub-1 --format '{{json .Config.Env}}'` | (a), (b): **không** có mật khẩu. (c): **CÓ** — biến môi trường của container hiện rõ cho bất kỳ ai có quyền root/Docker trên máy chủ. Mô hình đe dọa: cách làm này bảo vệ khỏi lộ qua Git, user data, AMI, log CI, ảnh chụp màn hình console; **không** bảo vệ khi máy chủ đã bị chiếm quyền root. Cách mạnh hơn (Docker secrets dạng file, app tự đọc Parameter Store lúc khởi động) để dành Module 10 — Security (tuần 21). Ghi kết luận này vào ADR — trung thực về giới hạn là điều người phỏng vấn đánh giá cao |
| E5 | **Ai đọc được user data?** | Chạy lại lệnh (a) ở E4 nhưng bỏ `grep` | Toàn bộ script hiện ra. Kết luận: user data **không** phải chỗ cho secret — với bất kỳ ai có quyền đọc thuộc tính instance |
| E6 | **Container có mượn được quyền của EC2 không?** | `[EC2]` Trên host: lấy token IMDSv2 như mục 8 (thành công). Trong container: `sudo docker compose -f compose.yaml exec taskhub curl -sS -m 3 -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60"` | Trong container lệnh **hết thời gian chờ** (không nhận được token) vì hop limit = 1 — ghi lại kết quả thật. Giải thích vì sao đây là lớp phòng thủ quan trọng: lỗ hổng SSRF/RCE trong app không biến thành quyền AWS. Khi nào phải nâng lên 2? |
| E7 | **Triển khai bản cũ (rollback tay)** | `sudo /opt/taskhub/scripts/deploy.sh v0.3.0` rồi `... v0.4.0` | Thời gian mỗi lần; dữ liệu còn nguyên. Vì sao an toàn ở đây (cùng schema Flyway)? Chuẩn bị cho diễn tập rollback < 5 phút ở v3 |
| E8 | **Tag không tồn tại** | `sudo /opt/taskhub/scripts/deploy.sh v9.9.9` | Pull lỗi `manifest unknown` (chữ có thể khác) → script quay về tag trước, exit khác 0, app **vẫn phục vụ** trong suốt quá trình. Đọc `.env`: `TASKHUB_IMAGE_TAG` là gì? |

---

## 12. Kết quả mong đợi

- [ ] `curl http://<IP-public>/actuator/health` từ laptop → `{"status":"UP"}`; tạo/đọc task được.
- [ ] Cổng 8080 và 22 từ Internet: timeout.
- [ ] Vào máy **chỉ** bằng Session Manager; Security Group không có rule 22.
- [ ] `aws ec2 describe-instances` cho `taskhub-app`: `MetadataOptions.HttpTokens = required`, `HttpPutResponseHopLimit = 1`; volume gốc `Encrypted = true`; đủ 5 tag.
- [ ] Mật khẩu: có trong Parameter Store; **không** có trong repo, user data, GitHub. `.env` trên máy chủ quyền `600`.
- [ ] E1–E8 đã ghi vào `docs/experiments/v2-tests.md`.
- [ ] Số credit đã dùng cho lab được ghi vào bảng chi phí.

---

## 13. Lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra | Cách sửa |
|---|---|---|---|
| `cloud-init status` = `error`; không có `docker` | Subnet không có route `0.0.0.0/0 → igw`, hoặc instance không có IP public → không tải được gói | `/var/log/cloud-init-output.log`; route table của subnet; `PublicIpAddress` | Sửa route/IP (Lab 01). User data không tự chạy lại: chạy tay từng lệnh, hoặc terminate và tạo lại |
| EC2 **không hiện** trong Session Manager / `describe-instance-information` rỗng | Thiếu instance profile; profile thiếu `AmazonSSMManagedInstanceCore`; không có đường ra Internet; Agent chưa chạy | `describe-instances --query '...IamInstanceProfile'`; route table; Console → EC2 → Actions → Monitor → **Get system log** | Gắn đúng profile (có thể gắn khi máy đang chạy: `aws ec2 associate-iam-instance-profile`), chờ vài phút |
| `Invalid IAM Instance Profile name` khi `run-instances` | IAM chưa lan truyền xong, hoặc gõ sai tên | `aws iam get-instance-profile --instance-profile-name taskhub-ec2-role` | Chờ 10–20 giây, chạy lại |
| `run-instances`: `VcpuLimitExceeded` / vượt quota | Hạn mức vCPU của tài khoản (tính tổng mọi instance đang chạy; `t3.small` cần 2 vCPU) đã hết — thường do còn instance khác đang chạy, kể cả ở lab khác | `[AWS Console]` Service Quotas → EC2 → *Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances* | Yêu cầu tăng quota, hoặc dùng loại nhỏ hơn tạm thời |
| `run-instances`: loại instance không được phép trên Free plan | Loại instance không nằm trong danh sách free-tier-eligible | Lệnh ở 7.2 | Chọn loại trong danh sách |
| `deploy.sh`: `AccessDeniedException ... ssm:GetParameter` | Policy inline sai ARN (account id, region, tên tham số) | `aws iam get-role-policy --role-name taskhub-ec2-role --policy-name taskhub-ec2-app` | Sửa ARN cho khớp `arn:aws:ssm:ap-southeast-1:<account>:parameter/taskhub/dev/*` |
| `deploy.sh`: `aws: command not found` | User data chưa chạy tới bước cài snap (lỗi ở bước trước) | `snap list aws-cli`; log cloud-init | `sudo snap install aws-cli --classic` |
| `required variable TASKHUB_IMAGE_TAG is missing a value` | Chạy `docker compose` tay trên EC2 khi `.env` chưa có tag | `sudo cat /opt/taskhub/.env \| cut -d= -f1` | Luôn triển khai qua `deploy.sh` |
| `taskhub` không healthy; log `password authentication failed` | Volume `pgdata` được khởi tạo với mật khẩu **khác** (đổi Parameter Store sau khi DB đã tạo) | `sudo docker compose -f compose.yaml logs taskhub \| grep -i password` | Xem ghi chú cuối mục 3; môi trường lab có thể xóa volume (⚠️ mất dữ liệu) để khởi tạo lại |
| Từ laptop `curl` timeout dù trên máy `curl localhost` OK | SG chưa mở 80, hoặc nhầm IP (IP đã đổi sau stop/start), hoặc nginx publish cổng khác 80 | `describe-security-groups`; `describe-instances ... PublicIpAddress`; `sudo ss -ltnp \| grep :80` | Sửa rule/IP; `.env` có `NGINX_HOST_PORT=80` |
| Máy rất chậm, `docker compose` treo, container bị kill (exit 137) | Hết RAM (đặc biệt nếu dùng `t3.micro`) | `free -m`; `sudo dmesg \| grep -i oom` | Dùng `t3.small`; giới hạn heap JVM (`-XX:MaxRAMPercentage` đã có trong Dockerfile) |

---

## 14. Dừng giữa chừng và dọn dẹp

### 14.1. Giữa các buổi học (trong suốt tuần 12–14)

EC2 này được dùng tiếp ở v3 (tuần 13). Lựa chọn:

| Cách | Tiết kiệm | Mất gì | Khi nào |
|---|---|---|---|
| ⚠️ **Stop** (`aws ec2 stop-instances`) | Hết tiền compute **và** IPv4 tự cấp | IP public đổi khi start lại; vẫn trả tiền EBS | **Mặc định** khi kết thúc mỗi buổi học |
| Để chạy | — | Credit (compute + IPv4 + EBS) chảy liên tục | Chỉ khi đang làm v3 nhiều ngày liền |
| ⚠️ **Terminate** | Hết mọi chi phí của instance + volume | Toàn bộ dữ liệu trên máy (database!) | Khi xong v3, hoặc trước v4 (Terraform sẽ dựng lại từ đầu) |

Free plan chỉ kéo dài 6 tháng hoặc đến khi hết credit — credit tiêu vào một instance quên tắt là credit **không còn** cho các tuần Terraform, Monitoring sau này.

### 14.2. ⚠️ Dọn dẹp hoàn toàn (khi kết thúc v3, hoặc nếu bỏ dở)

Thứ tự quan trọng: thứ phụ thuộc phải xóa trước.

```bash
# 1. Instance (volume tự xóa nhờ DeleteOnTermination)
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"

# 2. Security Group (chỉ xóa được khi không còn ENI nào dùng nó)
aws ec2 delete-security-group --group-id "$SG_ID"

# 3. Instance profile và role
aws iam remove-role-from-instance-profile --instance-profile-name taskhub-ec2-role --role-name taskhub-ec2-role
aws iam delete-instance-profile --instance-profile-name taskhub-ec2-role
aws iam delete-role-policy --role-name taskhub-ec2-role --policy-name taskhub-ec2-app
# Inline policy S3 thêm ở bài 05 — phải xóa trước, nếu không delete-role báo DeleteConflict
aws iam delete-role-policy --role-name taskhub-ec2-role --policy-name taskhub-ec2-s3-backup
aws iam list-role-policies --role-name taskhub-ec2-role          # phải rỗng trước khi delete-role
aws iam detach-role-policy --role-name taskhub-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name taskhub-ec2-role

# 4. (Tùy chọn — miễn phí) tham số mật khẩu
aws ssm delete-parameter --name /taskhub/dev/postgres-password
```

VPC của Lab 01 không tính phí (không có NAT Gateway) — giữ hay xóa theo hướng dẫn của Lab 01.

### 14.3. Kiểm tra không còn gì sót

```bash
aws ec2 describe-instances --filters Name=tag:Project,Values=taskhub \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text      # rỗng
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].[VolumeId,Size]' --output text                             # rỗng (volume mồ côi)
aws ec2 describe-addresses --query 'Addresses[].PublicIp' --output text          # rỗng (Elastic IP)
aws ec2 describe-security-groups --filters Name=group-name,Values=taskhub-web-sg \
  --query 'SecurityGroups[].GroupId' --output text                               # rỗng
aws iam get-role --role-name taskhub-ec2-role 2>&1 | grep -o NoSuchEntity        # NoSuchEntity
```

Rồi mở `[AWS Console]` **EC2 Global View** để chắc không có gì chạy ở Region khác (lỗi hay gặp: lỡ tạo ở `us-east-1` vì quên `AWS_REGION`). Hai ngày sau, kiểm tra lại mục Credits trong Billing — chi phí được cập nhật trễ.

---

## 15. Câu hỏi sau lab

1. Vì sao EC2 không cần cổng **vào** nào cho Session Manager, nhưng lại cần đường **ra** Internet? Nếu đặt EC2 vào subnet private (không NAT), cần thêm gì để Session Manager vẫn chạy, và cái đó tốn bao nhiêu? (gợi ý: VPC endpoint — tra giá)
2. Instance role, instance profile, trust policy, permission policy — mỗi thứ trả lời câu hỏi nào?
3. Vì sao `HttpPutResponseHopLimit=1` chặn được container mà không chặn được Docker daemon (log driver `awslogs` ở v3 vẫn chạy)?
4. Khác nhau giữa stop, reboot, terminate với: IP public, IP private, dữ liệu trên EBS, hóa đơn.
5. E4 cho thấy mật khẩu vẫn hiện trong `docker inspect`. Vậy Parameter Store đã mua được gì? Liệt kê 3 nơi mật khẩu **không** còn xuất hiện so với cách đặt thẳng vào `.env` trong Git hay user data.
6. 🟨 Viết quy trình **đổi mật khẩu database** không mất dữ liệu: thứ tự giữa `ALTER USER` trong PostgreSQL, cập nhật Parameter Store, và chạy lại `deploy.sh`. Downtime bao lâu?
7. 🟨 Server đang ở `git checkout v0.4.0`. Release `v0.5.0` đổi `compose.yaml`. Liệt kê các bước cập nhật máy chủ, và chỉ ra bước nào dễ quên nhất. (Đây là giới hạn của cách làm v2/v3 — Ansible ở v4 giải quyết.)

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Amazon EC2 — Free Tier usage](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Loại instance free-tier-eligible, lệnh `describe-instance-types` | 2026-10-31 |
| [AWS Billing — Free plan vs Paid plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Credit, 6 tháng, đóng tài khoản | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Giá Public IPv4 | 2026-10-31 |
| [Ubuntu on AWS — Find Ubuntu images](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/) | Tham số SSM `/aws/service/canonical/ubuntu/...` | 2026-10-31 |
| [Docker Docs — Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) | Lệnh cài trong user data | 2026-10-31 |
| [AWS CLI — Installing (snap)](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | `snap install aws-cli --classic` | 2026-10-31 |
| [Systems Manager — AMIs with SSM Agent preinstalled](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html) | Ubuntu 24.04 có sẵn SSM Agent (bản snap) | 2026-10-31 |
| [Systems Manager — Install the Session Manager plugin (Debian/Ubuntu)](https://docs.aws.amazon.com/systems-manager/latest/userguide/install-plugin-debian-and-ubuntu.html) | `aws ssm start-session` từ WSL | 2026-10-31 |
| [AWS KMS — Parameter Store SecureString](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html) | SecureString, key `aws/ssm`, quyền giải mã | 2026-10-31 |
| [AWS CLI — Sign in with `aws login`](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html) | Đăng nhập CLI bằng thông tin tạm thời | 2026-10-31 |
| [instances.vantage.sh — t3.small](https://instances.vantage.sh/aws/ec2/t3.small) | Tham khảo giá (bên thứ ba) | 2026-10-31 |
