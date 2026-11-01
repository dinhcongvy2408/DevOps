# Lab 03 — ALB + Auto Scaling + RDS trong một buổi (tuần 14)

> ⏱️ ~3 giờ (tính cả thời gian chờ RDS) · Mức độ: 🟥 Bắt buộc (instance refresh 🟨) · Kiến thức cần có trước: [07. RDS](../07-rds.md), [08. ELB & Auto Scaling](../08-elb-autoscaling.md), [06. AWS CLI](../06-aws-cli.md), [03. VPC](../03-vpc-networking.md)
> Môi trường: `[WSL]` (AWS CLI v2, `aws login`, profile `taskhub`), `[AWS Console]`. Region `ap-southeast-1`.
> **Dựng → kiểm tra → XÓA TOÀN BỘ trong cùng một buổi.** Không để qua đêm.

## Mục lục

- [0. Hộp chi phí và đồng hồ hẹn giờ](#0-hộp-chi-phí-và-đồng-hồ-hẹn-giờ)
- [1. Mục tiêu](#1-mục-tiêu)
- [2. Điều kiện trước khi bắt đầu](#2-điều-kiện-trước-khi-bắt-đầu)
- [3. Kiến trúc sẽ dựng](#3-kiến-trúc-sẽ-dựng)
- [4. Các bước](#4-các-bước)
- [5. Thí nghiệm](#5-thí-nghiệm)
- [6. Dọn dẹp — bắt buộc](#6-dọn-dẹp--bắt-buộc)
- [7. Kiểm tra không còn tài nguyên sót](#7-kiểm-tra-không-còn-tài-nguyên-sót)
- [8. Bài viết so sánh phải nộp](#8-bài-viết-so-sánh-phải-nộp)
- [9. Lỗi thường gặp](#9-lỗi-thường-gặp)
- [10. Câu hỏi sau lab](#10-câu-hỏi-sau-lab)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 0. Hộp chi phí và đồng hồ hẹn giờ

> 💰 **Ước tính chi phí khi tài nguyên đang chạy** (Singapore, giá kiểm tra 2026-10-31 — AWS Price List API; tự kiểm tra lại trước khi làm)
>
> | Tài nguyên | Đơn giá | Số lượng | USD/giờ |
> |---|---|---|---|
> | ALB-giờ | 0,0252 | 1 | 0,0252 |
> | LCU-giờ (lab dùng < 1 LCU) | 0,008 | ≤ 1 | ≤ 0,008 |
> | EC2 `t3.micro` | 0,0132 | 2 | 0,0264 |
> | RDS `db.t4g.micro` Single-AZ (PostgreSQL) | 0,025 | 1 | 0,025 |
> | RDS gp3 20 GB (0,138 USD/GB-tháng ÷ 730 giờ) | — | 20 GB | ≈ 0,0038 |
> | Public IPv4 (2 node ALB + 2 EC2) | 0,005 | 4 | 0,02 |
> | EBS gốc của 2 EC2 (8 GiB gp3 mỗi máy) | xem [trang giá EBS](https://aws.amazon.com/ebs/pricing/) | 16 GiB | rất nhỏ (vài phần nghìn USD) |
> | **Tổng** | | | **≈ 0,11 USD/giờ** |
>
> - Một buổi 3 giờ ≈ **0,35 USD** credit.
> - ⚠️ **Quên xóa một tháng ≈ 80 USD** — gần một nửa credit Free plan của bạn. Đây là lý do có mục 6 và 7.
> - Không chạy stress test CPU kéo dài: `t3` mặc định ở chế độ *unlimited*, CPU cao liên tục có thể phát sinh phí CPU credit.

⏰ **Trước khi gõ lệnh đầu tiên:**

1. Đặt **báo thức điện thoại** sau 2 giờ 30 phút với nội dung "BẮT ĐẦU DỌN LAB 03".
2. Ghi giờ bắt đầu vào `week14/lab03.md`.
3. Kiểm tra AWS Budget (tạo ở [bài 00](../00-aws-account-setup-cost-safety.md)) vẫn đang bật cảnh báo email.

Nếu buổi học bị gián đoạn (mất điện, phải đi): **chạy ngay script dọn dẹp ở mục 6**, làm lại từ đầu vào hôm khác. Không "để đó mai làm tiếp".

---

## 1. Mục tiêu

- Dựng được kiến trúc "sách giáo khoa" thu nhỏ: **ALB ở 2 AZ → Auto Scaling group 2 EC2 → RDS PostgreSQL private**.
- Chứng minh bằng thí nghiệm: ALB chia tải; ASG **tự thay** máy chết; health check hỏng → target bị loại khỏi ALB → ASG thay; database chỉ truy cập được từ máy trong SG app.
- 🟨 Thực hiện **rolling update** bằng instance refresh và quan sát traffic chuyển dần từ `v1` sang `v2`.
- **Xóa sạch** theo đúng thứ tự và chứng minh bằng lệnh CLI.
- Viết bài so sánh "EC2 + Compose" với "ALB + ASG + RDS".

Lab dùng một trang nginx đơn giản (hiện instance ID và AZ), **không** dùng `taskhub` — để buổi học ngắn và tập trung vào hạ tầng.

---

## 2. Điều kiện trước khi bắt đầu

| Cần có | Từ đâu | Kiểm tra |
|---|---|---|
| VPC `taskhub-vpc` với 4 subnet `taskhub-public-a/b`, `taskhub-private-a/b`; public subnet có route `0.0.0.0/0 → igw` | [Bài 03](../03-vpc-networking.md) | Lệnh ở Bước 1 |
| Instance profile `taskhub-ec2-role` (có `AmazonSSMManagedInstanceCore`) | [Bài 02](../02-iam.md), [bài 04](../04-ec2.md) | `aws iam get-instance-profile --instance-profile-name taskhub-ec2-role` |
| AWS CLI v2 đăng nhập bằng `aws login` | [Bài 06](../06-aws-cli.md) | `aws sts get-caller-identity` |
| Script `~/devops-lab/06-aws/find-leftovers.sh` | [Bài 06](../06-aws-cli.md) | `ls -l ~/devops-lab/06-aws/find-leftovers.sh` |
| Quota vCPU đủ cho 2 × `t3.micro` (4 vCPU) **cộng** mọi EC2 khác đang chạy | Tài khoản mới mặc định chỉ có **5 vCPU** cho On-Demand Standard | Bước 1 |
| EC2 `taskhub-app` (v2, `t3.small` = 2 vCPU) **đã dừng** trong buổi lab | Nếu không dừng: 2 + 2 × 2 = 6 vCPU > 5 → ASG báo `VcpuLimitExceeded` | Bước 1 |

---

## 3. Kiến trúc sẽ dựng

```text
                      Internet
                         │ HTTP :80
                ┌────────▼─────────┐
                │ lab03-alb        │  SG lab03-alb-sg: 80 từ 0.0.0.0/0
                │ (public-a, -b)   │
                └───┬──────────┬───┘
      listener :80 → lab03-web-tg (health check GET /health, 10 s, ngưỡng 2/2)
                    │          │
       ┌────────────▼──┐   ┌───▼───────────┐
       │ EC2 public-a  │   │ EC2 public-b  │  SG lab03-web-sg: 80 CHỈ từ lab03-alb-sg
       │ nginx, psql   │   │ nginx, psql   │  ASG lab03-web-asg: min 2 / desired 2 / max 2
       └───────┬───────┘   └───────┬───────┘  launch template lab03-web-lt (t3.micro, Ubuntu 24.04, IMDSv2)
               └──── TCP 5432 ─────┘
                ┌────────▼─────────┐
                │ RDS lab03-pg     │  SG lab03-db-sg: 5432 CHỈ từ lab03-web-sg
                │ private-a / -b   │  DB subnet group lab03-db-subnets, Public access = No
                └──────────────────┘
```

Vì sao EC2 ở **public** subnet? Để máy ra được Internet (`apt-get`, SSM) mà **không cần NAT Gateway** (≈ 0,045 USD/giờ mỗi cái). Bảo mật vẫn giữ được vì SG web **chỉ** nhận traffic từ SG ALB — bạn sẽ kiểm chứng ở Thí nghiệm 5.

Mọi tài nguyên được gắn tag `Project=taskhub`, `Env=lab`, `Lab=lab03` và có tên bắt đầu bằng `lab03-`, để dọn dẹp bằng tên/tag mà **không phụ thuộc** biến shell.

---

## 4. Các bước

Tất cả lệnh chạy ở `[WSL]` trừ khi ghi khác. Mọi ID được ghi vào file `vars.sh` để mở terminal mới vẫn dùng tiếp được.

### Bước 1 — Chuẩn bị biến và kiểm tra điều kiện `[WSL]`

```bash
mkdir -p ~/devops-lab/06-aws/lab03 && cd ~/devops-lab/06-aws/lab03
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws sts get-caller-identity --query Arn --output text

VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc \
  --query "Vpcs[0].VpcId" --output text)
sid() {
  aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=tag:Name,Values="$1" \
    --query "Subnets[0].SubnetId" --output text
}
PUB_A=$(sid taskhub-public-a); PUB_B=$(sid taskhub-public-b)
PRI_A=$(sid taskhub-private-a); PRI_B=$(sid taskhub-private-b)

cat > vars.sh <<EOF
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
VPC_ID=$VPC_ID
PUB_A=$PUB_A PUB_B=$PUB_B PRI_A=$PRI_A PRI_B=$PRI_B
EOF
cat vars.sh
```

Không được có giá trị `None`. Có `None` → tên VPC/subnet của bạn khác bài 03 — sửa tham số `Values=` cho đúng tên của bạn.

Kiểm tra quota vCPU cho On-Demand Standard instances (họ A, C, D, H, I, M, R, T, Z):

```bash
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A \
  --query "Quota.[QuotaName,Value]" --output text
```

Tài khoản mới thường thấy **5** (vCPU). Lab cần 4 vCPU (2 × `t3.micro`), nên **mọi EC2 khác phải đang dừng** — đặc biệt máy `taskhub-app` của v2 (`t3.small`, 2 vCPU). Xem đang có bao nhiêu vCPU chạy:

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running \
  --query "Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key=='Name']|[0].Value]" --output table
```

⚠️ Dừng máy v2 trong buổi lab (dữ liệu trên EBS còn nguyên; dừng còn tiết kiệm credit):

```bash
APP_IID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=taskhub-app \
  Name=instance-state-name,Values=running --query "Reservations[0].Instances[0].InstanceId" --output text)
[ "$APP_IID" != "None" ] && aws ec2 stop-instances --instance-ids "$APP_IID" \
  --query "StoppingInstances[0].CurrentState.Name" --output text
echo "APP_IID=$APP_IID" >> vars.sh
```

Sau lab, khởi động lại bằng `aws ec2 start-instances --instance-ids "$APP_IID"`. Lưu ý: máy v2 dùng **public IPv4 tự cấp** nên khi start lại sẽ có **IP mới** — cập nhật biến `APP_URL` của workflow deploy (v3) hoặc bản ghi DNS nếu có.

Muốn chạy cả hai cùng lúc hoặc muốn thử `max-size 3`: **Service Quotas** console → *Amazon EC2* → *Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances* → yêu cầu tăng (có thể mất vài giờ đến vài ngày được duyệt).

### Bước 2 — ⚠️ Ba security group `[WSL]`

```bash
TAGS_SG='ResourceType=security-group,Tags=[{Key=Project,Value=taskhub},{Key=Env,Value=lab},{Key=Lab,Value=lab03}]'

ALB_SG=$(aws ec2 create-security-group --group-name lab03-alb-sg --description "lab03 ALB" \
  --vpc-id "$VPC_ID" --tag-specifications "$TAGS_SG" --query GroupId --output text)
WEB_SG=$(aws ec2 create-security-group --group-name lab03-web-sg --description "lab03 web instances" \
  --vpc-id "$VPC_ID" --tag-specifications "$TAGS_SG" --query GroupId --output text)
DB_SG=$(aws ec2 create-security-group --group-name lab03-db-sg --description "lab03 RDS" \
  --vpc-id "$VPC_ID" --tag-specifications "$TAGS_SG" --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" --protocol tcp --port 80 --source-group "$ALB_SG"
aws ec2 authorize-security-group-ingress --group-id "$DB_SG"  --protocol tcp --port 5432 --source-group "$WEB_SG"

echo "ALB_SG=$ALB_SG WEB_SG=$WEB_SG DB_SG=$DB_SG" >> vars.sh
```

❓ Vì sao inbound của `lab03-web-sg` dùng `--source-group` thay vì `--cidr`? (Nhắc lại [bài 07 mục 4.2](../07-rds.md).) SG web **không** mở port 22 — vào máy bằng SSM.

### Bước 3 — ⚠️ Tạo RDS trước (chờ lâu nhất) `[WSL]`

```bash
aws rds create-db-subnet-group --db-subnet-group-name lab03-db-subnets \
  --db-subnet-group-description "lab03 private subnets" --subnet-ids "$PRI_A" "$PRI_B" \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab Key=Lab,Value=lab03

PG_VERSION=$(aws rds describe-db-engine-versions --engine postgres \
  --query "DBEngineVersions[?starts_with(EngineVersion, '17.')].EngineVersion | [-1]" --output text)
DB_PASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)
echo "PG_VERSION=$PG_VERSION"

aws rds create-db-instance \
  --db-instance-identifier lab03-pg \
  --engine postgres --engine-version "$PG_VERSION" \
  --db-instance-class db.t4g.micro \
  --allocated-storage 20 --storage-type gp3 --storage-encrypted \
  --master-username labadmin --master-user-password "$DB_PASS" \
  --db-subnet-group-name lab03-db-subnets \
  --vpc-security-group-ids "$DB_SG" \
  --no-publicly-accessible --no-multi-az \
  --backup-retention-period 1 \
  --engine-lifecycle-support open-source-rds-extended-support-disabled \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab Key=Lab,Value=lab03 \
  --query "DBInstance.DBInstanceStatus" --output text

echo "Mật khẩu DB (chỉ dùng trong buổi lab, ghi tạm ra giấy): $DB_PASS"
```

- Đầu ra mong đợi: `creating`. Instance cần khoảng 10–15 phút — làm Bước 4–8 trong lúc chờ.
- **Không** ghi `DB_PASS` vào `vars.sh` hay bất kỳ file nào. Database sẽ bị xóa cuối buổi.
- Giải thích từng tham số: [bài 07 mục 8](../07-rds.md). Đặc biệt `--engine-lifecycle-support ...-disabled`: thiếu nó, CLI **mặc định bật** Extended Support.

### Bước 4 — User data cho máy web `[WSL]`

```bash
cat > user-data-v1.sh <<'EOF'
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx postgresql-client

# IMDSv2: lấy token trước, rồi mới đọc metadata (launch template bắt buộc IMDSv2)
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
md() { curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/$1"; }
IID=$(md instance-id)
AZ=$(md placement/availability-zone)

echo "lab03 | $IID | $AZ | v1" > /var/www/html/index.html
echo ok > /var/www/html/health
systemctl enable --now nginx
EOF
bash -n user-data-v1.sh && echo "cú pháp OK"
```

| Dòng | Vì sao |
|---|---|
| `set -euxo pipefail` | Lỗi là dừng; `-x` in từng lệnh vào `/var/log/cloud-init-output.log` để debug |
| `postgresql-client` | Có `psql` để thử kết nối RDS ở Thí nghiệm 4 |
| Token IMDSv2 | Không có token → `401`, vì launch template đặt `HttpTokens=required` ([bài 04](../04-ec2.md)) |
| `/var/www/html/health` | File tĩnh cho health check của ALB. Với `taskhub` sẽ là `/actuator/health` |

### Bước 5 — ⚠️ Launch template `[WSL]`

```bash
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query Parameter.Value --output text)
aws ec2 describe-images --image-ids "$AMI_ID" --query "Images[0].[OwnerId,Name]" --output text
```

`OwnerId` phải là **099720109477** (Canonical). Ghi AMI ID cụ thể (không dùng `resolve:ssm:` — lý do ở [bài 08 mục 4.7](../08-elb-autoscaling.md)).

```bash
cat > lt-v1.json <<EOF
{
  "ImageId": "$AMI_ID",
  "InstanceType": "t3.micro",
  "IamInstanceProfile": { "Name": "taskhub-ec2-role" },
  "MetadataOptions": { "HttpTokens": "required", "HttpEndpoint": "enabled" },
  "NetworkInterfaces": [
    { "DeviceIndex": 0, "AssociatePublicIpAddress": true,
      "Groups": ["$WEB_SG"], "DeleteOnTermination": true }
  ],
  "UserData": "$(base64 -w0 user-data-v1.sh)"
}
EOF

aws ec2 create-launch-template --launch-template-name lab03-web-lt \
  --version-description v1 --launch-template-data file://lt-v1.json \
  --tag-specifications 'ResourceType=launch-template,Tags=[{Key=Project,Value=taskhub},{Key=Lab,Value=lab03}]' \
  --query "LaunchTemplate.[LaunchTemplateId,LatestVersionNumber]" --output text
echo "AMI_ID=$AMI_ID" >> vars.sh
```

- `AssociatePublicIpAddress: true` + `Groups`: khi khai báo network interface trong launch template, SG phải đặt **trong** interface (không đặt ở `SecurityGroupIds`). Subnet để trống — ASG sẽ chọn.
- `UserData` phải là **base64** khi gửi qua API.

### Bước 6 — ⚠️ Target group, ALB, listener `[WSL]`

```bash
TG_ARN=$(aws elbv2 create-target-group --name lab03-web-tg \
  --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance \
  --health-check-path /health --health-check-interval-seconds 10 \
  --healthy-threshold-count 2 --unhealthy-threshold-count 2 --matcher HttpCode=200 \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab Key=Lab,Value=lab03 \
  --query "TargetGroups[0].TargetGroupArn" --output text)

# Rút target nhanh hơn mặc định 300 s (trang tĩnh, không có request dài)
aws elbv2 modify-target-group-attributes --target-group-arn "$TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=30 > /dev/null

ALB_ARN=$(aws elbv2 create-load-balancer --name lab03-alb --type application \
  --scheme internet-facing --subnets "$PUB_A" "$PUB_B" --security-groups "$ALB_SG" \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab Key=Lab,Value=lab03 \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].DNSName" --output text)

aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
  --query "Listeners[0].ListenerArn" --output text

echo "TG_ARN=$TG_ARN ALB_ARN=$ALB_ARN ALB_DNS=$ALB_DNS" >> vars.sh
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB_DNS/"
```

Mã trả về lúc này là **503**: listener đã có nhưng target group chưa có target nào. Ghi lại — bạn vừa tạo ra lỗi 503 "đúng sách" ([bài 08 mục 11](../08-elb-autoscaling.md)).

### Bước 7 — ⚠️ Auto Scaling group `[WSL]`

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name lab03-web-asg \
  --launch-template "LaunchTemplateName=lab03-web-lt,Version=\$Latest" \
  --min-size 2 --max-size 2 --desired-capacity 2 \
  --vpc-zone-identifier "$PUB_A,$PUB_B" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB --health-check-grace-period 120 \
  --tags "Key=Name,Value=lab03-web,PropagateAtLaunch=true" \
         "Key=Project,Value=taskhub,PropagateAtLaunch=true" \
         "Key=Env,Value=lab,PropagateAtLaunch=true" \
         "Key=Lab,Value=lab03,PropagateAtLaunch=true"
```

`--max-size 2` (bằng desired) để không bao giờ vượt quota 5 vCPU mặc định. ASG vẫn **thay** máy hỏng được — nó terminate máy cũ rồi tạo máy mới trong giới hạn 2.

Chờ target healthy (2–4 phút: boot + `apt-get` + 2 lần health check):

```bash
watch -n 10 "aws elbv2 describe-target-health --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output text"
```

Thoát `watch` bằng **Ctrl+C** khi cả hai dòng là `healthy`. Nếu sau 6 phút vẫn `unhealthy`/`initial` → [mục 9](#9-lỗi-thường-gặp).

### Bước 8 — Kiểm tra chia tải `[WSL]`

```bash
for i in $(seq 1 8); do curl -s "http://$ALB_DNS/"; done
```

Đầu ra minh họa:

```text
lab03 | i-0a1b2c3d4e5f60001 | ap-southeast-1a | v1
lab03 | i-0a1b2c3d4e5f60002 | ap-southeast-1b | v1
lab03 | i-0a1b2c3d4e5f60001 | ap-southeast-1a | v1
lab03 | i-0a1b2c3d4e5f60002 | ap-southeast-1b | v1
...
```

Mở **terminal thứ hai** và để chạy suốt các thí nghiệm — đây là "người dùng" của bạn:

```bash
source ~/devops-lab/06-aws/lab03/vars.sh
while true; do
  printf '%s %s %s\n' "$(date +%T)" \
    "$(curl -s -o /tmp/lab03-body -m 2 -w '%{http_code}' "http://$ALB_DNS/")" \
    "$(cut -d'|' -f2 /tmp/lab03-body 2>/dev/null)"
  sleep 1
done | tee watch.log
```

### Bước 9 — Chờ RDS sẵn sàng `[WSL]`

```bash
aws rds wait db-instance-available --db-instance-identifier lab03-pg
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier lab03-pg \
  --query "DBInstances[0].Endpoint.Address" --output text)
echo "DB_ENDPOINT=$DB_ENDPOINT" >> vars.sh
echo "$DB_ENDPOINT"
```

Ghi vào `week14/lab03.md`: RDS mất bao nhiêu phút từ Bước 3 đến lúc `available`?

---

## 5. Thí nghiệm

Ghi kết quả từng thí nghiệm (giờ bắt đầu, giờ kết thúc, số dòng không phải `200` trong `watch.log`) vào `week14/lab03.md`.

### Thí nghiệm 1 — Máy "chết đột ngột" ⚠️

Giả lập máy hỏng bằng cách terminate thẳng qua EC2 API (ASG không được báo trước):

```bash
IID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names lab03-web-asg \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)
echo "Sẽ terminate $IID"
aws ec2 terminate-instances --instance-ids "$IID" --query "TerminatingInstances[0].CurrentState.Name" --output text
```

Quan sát:

- Terminal 2: có dòng `502`/`503`/`000` (timeout) nào không, trong bao lâu? Sau đó chỉ còn một instance ID trả lời.
- Sau vài phút ASG tạo máy mới:

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name lab03-web-asg \
  --max-items 3 --query "Activities[].[StartTime,StatusCode,Description]" --output text
```

❓ ASG phát hiện máy mất nhờ đâu (health check EC2 hay ELB)? Mất bao lâu từ lúc terminate đến khi có lại 2 target `healthy`?

### Thí nghiệm 2 — Rút máy "có kế hoạch" qua ASG ⚠️

Lần này yêu cầu **ASG** terminate (như khi thu nhỏ hoặc instance refresh), giữ nguyên desired:

```bash
IID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names lab03-web-asg \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)
aws autoscaling terminate-instance-in-auto-scaling-group --instance-id "$IID" \
  --no-should-decrement-desired-capacity --query "Activity.Description" --output text
```

Trong lúc chờ, xem target đó chuyển sang `draining`:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State]" --output text
```

❓ So với Thí nghiệm 1, terminal 2 có ít lỗi hơn không? Vì sao? (Gợi ý: ASG **hủy đăng ký** target khỏi ALB trước, chờ deregistration delay 30 giây, rồi mới terminate.)

### Thí nghiệm 3 — App hỏng nhưng máy còn sống ⚠️

Xóa file health check trên một máy bằng **SSM Run Command** (không cần SSH, không cần mở port):

```bash
IID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names lab03-web-asg \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)
CMD_ID=$(aws ssm send-command --instance-ids "$IID" --document-name AWS-RunShellScript \
  --parameters 'commands=["rm -f /var/www/html/health"]' \
  --query "Command.CommandId" --output text)
sleep 5
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$IID" \
  --query "[Status,StandardErrorContent]" --output text
```

Theo dõi:

```bash
watch -n 5 "aws elbv2 describe-target-health --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]' --output text"
```

Thứ tự mong đợi: target đó → `unhealthy` (`Target.ResponseCodeMismatch` — nginx trả 404 cho `/health`) sau khoảng 2 × 10 giây → ALB ngừng gửi traffic tới nó → ASG (health check type **ELB**) terminate và tạo máy mới. Kiểm tra lý do trong `describe-scaling-activities` (cột `Cause`).

❓ Nếu ASG dùng health check type **EC2**, chuyện gì sẽ xảy ra với máy này? Trang chủ của nó vẫn trả 200 — vì sao người dùng lại không còn thấy nó?

### Thí nghiệm 4 — Kết nối RDS từ máy app `[AWS Console]` `[EC2]`

1. `[AWS Console]` → EC2 → Instances → chọn một instance `lab03-web` → **Connect** → tab **Session Manager** → **Connect**. (Cách này không cần cài Session Manager plugin trên WSL.)
2. Trong phiên `[EC2]`:

```bash
sudo -iu ubuntu
DB="<dán DB_ENDPOINT vào đây>"
getent hosts "$DB"                                    # phải ra IP 10.20.11.x hoặc 10.20.12.x
timeout 3 bash -c "</dev/tcp/$DB/5432" && echo "TCP 5432 OK"
read -rs PGPASSWORD && export PGPASSWORD              # dán mật khẩu, Enter (không hiện ra màn hình)
psql "host=$DB port=5432 dbname=postgres user=labadmin sslmode=require" \
  -c "select version();" -c "select inet_server_addr();" -c "show rds.force_ssl;"
psql "host=$DB port=5432 dbname=postgres user=labadmin sslmode=disable" -c "select 1;"
unset PGPASSWORD
```

Quan sát:

- `psql` của Ubuntu 24.04 là bản 16, server là 17 → có thể in cảnh báo phiên bản; vẫn chạy được.
- `rds.force_ssl` = `1`; lệnh với `sslmode=disable` bị từ chối (`no pg_hba.conf entry ... no encryption`).

3. Thử từ **laptop** `[WSL]`:

```bash
source ~/devops-lab/06-aws/lab03/vars.sh
getent hosts "$DB_ENDPOINT"
timeout 5 bash -c "</dev/tcp/$DB_ENDPOINT/5432" && echo "kết nối được?!" || echo "không kết nối được — đúng thiết kế"
```

❓ Tên DNS từ laptop phân giải ra IP gì? Vì sao laptop biết IP mà vẫn không kết nối được? (Hai lớp chặn: IP private không có đường đi từ Internet; SG DB chỉ cho SG web.)

### Thí nghiệm 5 — Chứng minh EC2 không nhận traffic trực tiếp từ Internet `[WSL]`

```bash
PUB_IP=$(aws ec2 describe-instances --filters Name=tag:Lab,Values=lab03 Name=instance-state-name,Values=running \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
curl -s -m 5 -o /dev/null -w '%{http_code}\n' "http://$PUB_IP/" || echo "timeout — SG web chặn, chỉ cho ALB"
```

Máy **có** IP public (để ra Internet) nhưng **không** nhận được request trực tiếp — SG mới là bức tường.

### Thí nghiệm 6 — 🟨 Rolling update bằng instance refresh ⚠️

Tạo phiên bản 2 của trang (đổi `v1` → `v2`) và launch template version 2:

```bash
sed 's/| v1"/| v2"/' user-data-v1.sh > user-data-v2.sh
grep -n 'v2' user-data-v2.sh            # phải thấy dòng echo "... | v2"
aws ec2 create-launch-template-version --launch-template-name lab03-web-lt \
  --source-version 1 --version-description v2 \
  --launch-template-data "{\"UserData\":\"$(base64 -w0 user-data-v2.sh)\"}" \
  --query "LaunchTemplateVersion.VersionNumber" --output text
```

ASG trỏ `$Latest` nên đã thấy version 2, nhưng máy đang chạy **không đổi**. Bắt đầu refresh, giữ tối thiểu 50% (1/2 máy) healthy:

```bash
aws autoscaling start-instance-refresh --auto-scaling-group-name lab03-web-asg \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":90}' \
  --query "InstanceRefreshId" --output text

watch -n 15 "aws autoscaling describe-instance-refreshes --auto-scaling-group-name lab03-web-asg \
  --query 'InstanceRefreshes[0].[Status,PercentageComplete,StatusReason]' --output text"
```

Trong terminal 2, quan sát traffic chuyển dần: lúc đầu chỉ `v1`, giữa chừng lẫn `v1`/`v2`, cuối cùng chỉ `v2`. (Terminal 2 in instance ID; muốn thấy `v1`/`v2`, đổi `cut -d'|' -f2` thành `cut -d'|' -f2,4`.)

❓ Đây là chiến lược triển khai nào ở [CI/CD 05](../../05-CICD/05-deployment-strategies-rollback.md)? Trong lúc refresh, có lúc nào hai phiên bản cùng phục vụ không? Điều đó đòi hỏi gì ở database schema nếu đây là `taskhub`?

---

## 6. Dọn dẹp — bắt buộc

> ⚠️ Các lệnh dưới đây **xóa vĩnh viễn** tài nguyên của lab, kể cả database `lab03-pg` (không chụp snapshot cuối — lab không có dữ liệu thật; **không bao giờ** dùng `--skip-final-snapshot` với database có dữ liệu thật). Script chỉ xóa tài nguyên có tên bắt đầu bằng `lab03-`.

Dừng vòng lặp ở terminal 2 (**Ctrl+C**). Tạo script dọn dẹp — dựa trên **tên**, không dựa trên biến của buổi lab, để chạy được cả khi bạn đã đóng terminal:

```bash
cat > ~/devops-lab/06-aws/lab03/cleanup-lab03.sh <<'EOF'
#!/bin/bash
# Xóa toàn bộ tài nguyên Lab 03 theo đúng thứ tự phụ thuộc. Chạy lại nhiều lần cũng an toàn.
set -uo pipefail
export AWS_PROFILE="${AWS_PROFILE:-taskhub}" AWS_REGION="${AWS_REGION:-ap-southeast-1}"

step() { printf '\n== %s\n' "$*"; }

step "1/7 Auto Scaling group (terminate mọi instance của nhóm)"
if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names lab03-web-asg \
     --query "AutoScalingGroups[0].AutoScalingGroupName" --output text | grep -q lab03; then
  aws autoscaling delete-auto-scaling-group --auto-scaling-group-name lab03-web-asg --force-delete
  while aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names lab03-web-asg \
          --query "AutoScalingGroups[0].AutoScalingGroupName" --output text | grep -q lab03; do
    echo "  chờ ASG xóa xong..."; sleep 15
  done
fi

step "2/7 Launch template"
aws ec2 delete-launch-template --launch-template-name lab03-web-lt > /dev/null 2>&1 \
  && echo "  đã xóa" || echo "  không có / đã xóa"

step "3/7 ALB (listener bị xóa kèm) và target group"
ALB_ARN=$(aws elbv2 describe-load-balancers --names lab03-alb \
  --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi
TG_ARN=$(aws elbv2 describe-target-groups --names lab03-web-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null)
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN"
fi

step "4/7 RDS lab03-pg (KHÔNG snapshot cuối, xóa cả automated backup)"
if aws rds describe-db-instances --db-instance-identifier lab03-pg > /dev/null 2>&1; then
  aws rds delete-db-instance --db-instance-identifier lab03-pg \
    --skip-final-snapshot --delete-automated-backups \
    --query "DBInstance.DBInstanceStatus" --output text
  aws rds wait db-instance-deleted --db-instance-identifier lab03-pg
fi

step "5/7 DB subnet group"
aws rds delete-db-subnet-group --db-subnet-group-name lab03-db-subnets > /dev/null 2>&1 \
  && echo "  đã xóa" || echo "  không có / đã xóa"

step "6/7 Security groups (db → web → alb; ENI của ALB có thể cần vài phút để biến mất)"
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc --query "Vpcs[0].VpcId" --output text)
for name in lab03-db-sg lab03-web-sg lab03-alb-sg; do
  SG=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$name" \
    --query "SecurityGroups[0].GroupId" --output text)
  [ "$SG" = "None" ] && { echo "  $name: không có"; continue; }
  for try in 1 2 3 4 5 6 7 8; do
    if aws ec2 delete-security-group --group-id "$SG" 2>/dev/null; then echo "  $name: đã xóa"; break; fi
    echo "  $name: còn phụ thuộc, thử lại sau 30 s ($try/8)"; sleep 30
  done
done

step "7/7 Kiểm tra nhanh"
aws ec2 describe-instances --filters Name=tag:Lab,Values=lab03 \
  Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[].Instances[].InstanceId" --output text
echo "(dòng trên phải trống)"
EOF
chmod +x ~/devops-lab/06-aws/lab03/cleanup-lab03.sh
bash -n ~/devops-lab/06-aws/lab03/cleanup-lab03.sh && ~/devops-lab/06-aws/lab03/cleanup-lab03.sh
```

Vì sao **đúng thứ tự** này?

| Thứ tự | Lý do |
|---|---|
| ASG trước launch template | Không xóa được LT đang được ASG dùng; xóa ASG trước còn ngăn ASG **tạo lại** máy khi bạn xóa instance |
| ASG trước ALB/TG | ASG đang gắn TG; instance còn đăng ký trong TG |
| ALB trước TG | Không xóa được TG đang được listener dùng (xóa ALB thì listener đi kèm) |
| RDS trước DB subnet group | Subnet group đang được instance dùng |
| SG sau cùng, `db` → `web` → `alb` | `lab03-db-sg` tham chiếu `lab03-web-sg`, `lab03-web-sg` tham chiếu `lab03-alb-sg`; ENI của ALB/EC2/RDS phải biến mất trước |

Xóa RDS mất vài phút; toàn bộ script thường 10–15 phút. Đừng đóng máy khi script chưa in mục 7/7.

Cuối cùng:

- **Xóa dòng mật khẩu DB** khỏi giấy ghi chú (`vars.sh` không chứa bí mật nên giữ lại cũng được).
- Nếu cần máy v2 chạy tiếp: `source ~/devops-lab/06-aws/lab03/vars.sh && aws ec2 start-instances --instance-ids "$APP_IID"` — rồi cập nhật `APP_URL`/DNS theo IP public mới.

---

## 7. Kiểm tra không còn tài nguyên sót

Chạy script quét tài nguyên theo tag của [bài 06](../06-aws-cli.md):

```bash
~/devops-lab/06-aws/find-leftovers.sh
```

Và kiểm tra riêng cho Lab 03 — **mọi lệnh phải in ra rỗng**:

```bash
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?starts_with(AutoScalingGroupName,'lab03')].AutoScalingGroupName" --output text
aws ec2 describe-launch-templates --query "LaunchTemplates[?starts_with(LaunchTemplateName,'lab03')].LaunchTemplateName" --output text
aws elbv2 describe-load-balancers --query "LoadBalancers[?starts_with(LoadBalancerName,'lab03')].LoadBalancerName" --output text
aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'lab03')].TargetGroupName" --output text
aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'lab03')].DBInstanceIdentifier" --output text
aws rds describe-db-snapshots --snapshot-type manual --query "DBSnapshots[].DBSnapshotIdentifier" --output text
aws rds describe-db-subnet-groups --query "DBSubnetGroups[?starts_with(DBSubnetGroupName,'lab03')].DBSubnetGroupName" --output text
aws ec2 describe-security-groups --filters Name=group-name,Values='lab03-*' --query "SecurityGroups[].GroupName" --output text
aws ec2 describe-instances --filters Name=tag:Lab,Values=lab03 Name=instance-state-name,Values=pending,running,stopping,stopped --query "Reservations[].Instances[].InstanceId" --output text
aws ec2 describe-network-interfaces --filters Name=vpc-id,Values="$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc --query 'Vpcs[0].VpcId' --output text)" Name=description,Values='ELB app/lab03-alb*' --query "NetworkInterfaces[].NetworkInterfaceId" --output text
```

**Ngày hôm sau:** `[AWS Console]` → Billing and Cost Management → Bills / Credits — chi phí buổi lab đã xuất hiện và **không tăng thêm** vào ngày tiếp theo. Ghi con số thực tế vào `week14/lab03.md` và vào ADR của [bài 07](../07-rds.md).

---

## 8. Bài viết so sánh phải nộp

Tạo `week14/compare-ec2-compose-vs-alb-asg-rds.md` (khoảng 1 trang). Dùng **số liệu bạn đo được** trong lab, không chép từ bài:

| Tiêu chí | `taskhub` v2: 1 EC2 + Docker Compose | Lab 03: ALB + ASG + RDS |
|---|---|---|
| Chi phí/giờ và /tháng (Singapore, có nguồn) | | |
| Một máy chết thì sao? Bao lâu phục hồi? (số đo từ Thí nghiệm 1) | | |
| Một AZ sự cố thì sao? | | |
| Deploy có downtime không? (recreate vs instance refresh — Thí nghiệm 6) | | |
| Backup database (tự viết vs automated + PITR) | | |
| Số thành phần phải hiểu để debug | | |
| Thời gian dựng từ đầu (đo được) | | |
| Phù hợp cho giai đoạn nào của sản phẩm? | | |

Kết thúc bằng **một đoạn kết luận**: với `taskhub` hiện tại, chọn gì và khi nào sẽ chuyển — dùng làm phần "Hệ quả" cho ADR ở bài 07.

---

## 9. Lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra / sửa |
|---|---|---|
| Bước 1 ra `None` | Tên VPC/subnet khác bài 03 | `aws ec2 describe-subnets --query "Subnets[].Tags"` xem tên thật |
| `create-db-subnet-group`: không đủ AZ | Hai subnet private cùng một AZ | Kiểm tra AZ của `taskhub-private-a/b` |
| `describe-scaling-activities` có `StatusCode=Failed`, mô tả chứa **`VcpuLimitExceeded`** ("You have requested more vCPU capacity than your current vCPU limit…") | Tổng vCPU đang chạy + máy mới > quota (mặc định 5 cho tài khoản mới) — thường do quên dừng máy `taskhub-app` của v2 | Dừng máy v2 (Bước 1); kiểm tra quota: `aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A`; giữ `--max-size 2`; hoặc xin tăng quota |
| ASG báo không có quyền `iam:PassRole` | User không được truyền role cho EC2 | Kiểm tra quyền của `phuong-admin` ([bài 02](../02-iam.md)) |
| Target mãi `initial`/`unhealthy`, `Target.Timeout` | SG web chưa cho SG ALB vào 80; nginx chưa cài xong | `describe-security-groups --group-ids "$WEB_SG"`; xem log user data (dưới) |
| `Target.ResponseCodeMismatch` ngay từ đầu | User data lỗi trước khi tạo `/health` (ví dụ `apt-get` lỗi, IMDSv2 trả 401) | Log user data |
| ASG tạo/xóa máy liên tục | User data hỏng → health check không bao giờ đạt → ASG thay sau grace period | Đọc log user data trên một máy mới (nhanh tay trước khi nó bị thay), hoặc tạm đổi `--health-check-type EC2` để giữ máy lại debug |
| `aws ssm send-command`: `InvalidInstanceId` | Máy chưa đăng ký với SSM (role thiếu `AmazonSSMManagedInstanceCore`, hoặc máy không ra Internet được) | `aws ssm describe-instance-information` |
| `psql: ... timeout` từ máy web | SG DB chưa cho SG web; nhầm SG khi tạo RDS | `aws rds describe-db-instances --query "DBInstances[0].VpcSecurityGroups"` |
| `psql: password authentication failed` | Dán sai mật khẩu | Gõ lại; nếu mất mật khẩu: `aws rds modify-db-instance --db-instance-identifier lab03-pg --master-user-password ... --apply-immediately` |
| Instance refresh `Failed` / đứng yên | `MinHealthyPercentage` quá cao; user data v2 lỗi | `describe-instance-refreshes` cột `StatusReason` |
| Script dọn dẹp: SG `DependencyViolation` mãi | ENI của ALB/RDS chưa biến mất, hoặc còn tài nguyên khác dùng SG | Chờ thêm; tìm ENI: `aws ec2 describe-network-interfaces --filters Name=group-id,Values=<sg-id>` |

**Đọc log user data** (qua Session Manager trên console, `[EC2]`):

```bash
sudo tail -n 60 /var/log/cloud-init-output.log
sudo cloud-init status --long
curl -i localhost/health
```

---

## 10. Câu hỏi sau lab

1. Thí nghiệm 1 và 2 khác nhau thế nào về số request lỗi? Giải thích bằng deregistration delay.
2. Ở Thí nghiệm 3, ai phát hiện sự cố trước — ALB hay ASG? Mỗi bên phản ứng ra sao?
3. Vì sao Bước 6 trả 503 trước khi có ASG? Nếu ALB trả 504 thì bạn nghi gì?
4. Thứ tự dọn dẹp có ý nghĩa gì? Nếu xóa launch template trước ASG thì sao?
5. Nếu đây là `taskhub` thật, cần đổi gì: target group port, health check path, user data (lấy image tag nào, lấy mật khẩu DB ở đâu), biến `SPRING_DATASOURCE_URL`?
6. Thời gian tạo RDS bạn đo được ảnh hưởng thế nào đến quyết định "dựng lại toàn bộ môi trường bằng Terraform mỗi buổi học" ở Module 07?

Lời giải: [solutions/lab-03-solutions.md](../solutions/lab-03-solutions.md) — chỉ mở sau khi đã tự trả lời.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS Price List API — AWSELB / AmazonRDS (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-southeast-1/index.json) | Giá ALB, LCU, RDS db.t4g.micro, gp3 RDS ở Singapore | 2026-10-31 |
| [Amazon EC2 On-Demand pricing](https://aws.amazon.com/ec2/pricing/on-demand/) | Giá t3.micro Singapore (0,0132 USD/giờ khi kiểm tra) | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Public IPv4 0,005 USD/giờ, kể cả IP của ELB | 2026-10-31 |
| [Track your Free Tier usage for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | t3.micro trong danh sách Free plan; trừ credit | 2026-10-31 |
| [ALB — Health checks for target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html) | Trạng thái target, reason code | 2026-10-31 |
| [ALB — Edit target group attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html) | `deregistration_delay.timeout_seconds` | 2026-10-31 |
| [EC2 Auto Scaling — Health check grace period](https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-check-grace-period.html) | Mặc định 0 khi tạo bằng CLI | 2026-10-31 |
| [EC2 Auto Scaling — Instance refresh default values](https://docs.aws.amazon.com/autoscaling/ec2/userguide/understand-instance-refresh-default-values.html) | MinHealthyPercentage, instance warmup | 2026-10-31 |
| [RDS — Extended Support creating](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/extended-support-creating-db-instance.html) | `--engine-lifecycle-support` | 2026-10-31 |
| [RDS — Using SSL with PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html) | `rds.force_ssl=1` mặc định từ PG 15 | 2026-10-31 |
| [Ubuntu on AWS — Find Ubuntu images](https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images/) | SSM parameter AMI Ubuntu 24.04, owner 099720109477 | 2026-10-31 |
