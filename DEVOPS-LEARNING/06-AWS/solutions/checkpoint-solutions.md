# Lời giải — Checkpoint Giai đoạn 6 (AWS)

> Chỉ mở **sau khi đã commit bài làm** vào `~/devops-journey/week14/checkpoint/`. Đề bài: [checkpoint.md](../checkpoint.md).
> Phần A là **ý chính cần có**, không phải câu chữ bắt buộc. Đầu ra lệnh là **minh họa**.

## Mục lục

- [Phần A — Ý chính](#phần-a--ý-chính)
- [Phần B1 — Policy backup](#phần-b1--policy-backup)
- [Phần B2 — Trang trạng thái bằng CLI](#phần-b2--trang-trạng-thái-bằng-cli)
- [Phần C — Break-fix ck06](#phần-c--break-fix-ck06)
- [Mẫu nhật ký cho một ticket](#mẫu-nhật-ký-cho-một-ticket)

---

## Phần A — Ý chính

**1. Deny thắng allow.** *(bắt buộc đúng)* Không xóa được. IAM đánh giá: (1) mặc định **từ chối ngầm** (implicit deny); (2) có câu `Deny` khớp → **từ chối ngay**, không gì ghi đè được; (3) không có deny, có câu `Allow` khớp → cho phép. `AdministratorAccess` cho phép `*`, nhưng câu `Deny s3:DeleteBucket` khớp → từ chối. Bỏ cả hai policy → không còn allow nào → từ chối ngầm mọi thứ (trừ những gì policy khác/resource policy cho phép).

**2. Instance profile thay vì access key.** Access key trong `.env` là bí mật **dài hạn**: lộ qua backup, image, log, repo là dùng được tới khi bị thu hồi thủ công. Role cấp **thông tin tạm thời** qua Instance Metadata Service (`169.254.169.254`), SDK/CLI tự lấy và tự làm mới trước khi hết hạn (thường vài giờ); không có gì để lộ trong file. IMDSv2 bắt buộc mỗi phiên phải `PUT` lấy **token** trước, và token có giới hạn số bước mạng (hop limit) → chống kiểu tấn công **SSRF**: lừa ứng dụng gửi một request `GET` tới `169.254.169.254` để đọc credential. Một lỗ SSRF thông thường không tự gửi được `PUT` kèm header.

**3. OIDC.** Access key trong GitHub Secrets: dài hạn, phải xoay vòng tay, ai đọc được secret (workflow bị chèn mã, action bị chiếm) là có key dùng ở bất cứ đâu, bất cứ lúc nào. OIDC: mỗi lần chạy, GitHub phát một **JWT ngắn hạn** mô tả repo/nhánh/environment; AWS STS kiểm tra chữ ký và **trust policy** rồi đổi lấy credential tạm thời (mặc định 1 giờ). Điều kiện `sub = repo:<user>/taskhub:environment:production` nghĩa là **chỉ** job trong repo đó, chạy với environment `production` (có người duyệt) mới assume được role. Bỏ `sub` → **bất kỳ repo GitHub nào** (của bất kỳ ai) xin token với audience `sts.amazonaws.com` cũng có thể assume role của bạn — đây là lỗi cấu hình nguy hiểm kinh điển.

**4. Free plan.** Hết credit hoặc hết 6 tháng (cái nào đến trước) → tài khoản **tự đóng**, mất quyền truy cập tài nguyên; AWS giữ nội dung 90 ngày, trong 90 ngày đó có thể nâng lên Paid plan để lấy lại. Bật AWS Organizations (cần cho IAM Identity Center dạng organization) sẽ **tự động nâng** tài khoản lên Paid plan — mất "lưới an toàn không phát sinh phí". Trước hạn: quyết định giữ dự án chạy (nâng Paid plan + Budget chặt) hay đưa mọi thứ về dạng **dựng lại được** (Terraform ở Module 07, backup DB ra ngoài, README) rồi để tài khoản đóng.

**5. SG vs NACL.** *(bắt buộc đúng)*

| | Security group | Network ACL |
|---|---|---|
| Gắn vào | Network interface (instance) | Subnet |
| Trạng thái | **Stateful** — nhớ kết nối, gói trả lời tự được phép | **Stateless** — xét từng gói, cả hai chiều độc lập |
| Luật | Chỉ allow | Allow và deny |
| Thứ tự | Gộp mọi luật, không thứ tự | Theo số luật tăng dần, **luật khớp đầu tiên** quyết định |

Web server: client `x.x.x.x:51234` → instance `:80`. Gói trả lời đi **ra** tới cổng 51234 của client. NACL không nhớ kết nối nên phải có luật outbound cho dải cổng tạm (AWS khuyến nghị 1024-65535); SG nhớ kết nối nên gói trả lời tự được phép.

**6. Subnet public.** Subnet public = route table của nó có `0.0.0.0/0 → Internet Gateway`. Không có public IPv4 → IGW không có địa chỉ để dịch (IGW làm NAT 1:1 giữa public IP và private IP của instance) → Internet không tới được, instance cũng không ra được. Subnet private không có NAT Gateway → không có đường ra Internet → `apt-get update` thất bại (trừ khi dùng VPC endpoint/mirror nội bộ). taskhub không dùng NAT Gateway (~0,045 USD/giờ + phí dữ liệu): EC2 nằm ở subnet public, được bảo vệ bằng SG chỉ mở 80/443 và quản trị qua SSM — đánh đổi là máy có public IP (bề mặt tấn công lớn hơn) và không có tầng "chỉ đi ra".

**7. Đường đi request.** Trình duyệt → DNS (nếu dùng tên) → Internet → **IGW** (đổi public IP đích → private IP) → **route table** subnet (chiều về cần `0.0.0.0/0 → IGW`) → **NACL inbound** (TCP 80) → **SG inbound** (TCP 80) → ENI → kernel EC2 → **Docker publish** `0.0.0.0:80 → nginx:80` (DNAT) → **nginx** `proxy_pass http://taskhub:8080` qua mạng Docker nội bộ (DNS của Docker) → **Spring Boot** → PostgreSQL. Chiều về: SG tự cho (stateful), **NACL outbound** cổng tạm, route về IGW.
- **Timeout:** thiếu route, NACL chặn (vào hoặc ra), SG thiếu rule, không có public IP.
- **Connection refused:** gói tới máy nhưng không có gì nghe ở cổng 80 (container nginx không chạy, không publish, publish nhầm cổng, bind `127.0.0.1`).
- **502 Bad Gateway:** nginx chạy nhưng không kết nối được upstream (container taskhub chết/chưa sẵn sàng, sai tên service/cổng).

**8. Reboot / stop / terminate.** *(bắt buộc đúng)*

| | Giờ chạy instance | Ổ EBS | Public IPv4 tự gán | Dữ liệu ổ gốc |
|---|---|---|---|---|
| Reboot | Vẫn tính | Vẫn tính | **Giữ nguyên** | Còn |
| Stop | **Ngừng tính** | **Vẫn tính** (dung lượng đã cấp) | **Bị thu hồi**, start lại nhận IP **mới** (Elastic IP thì giữ, nhưng EIP cũng tính 0,005 USD/giờ) | Còn |
| Terminate | Ngừng | Ổ gốc bị xóa nếu `DeleteOnTermination=true` (mặc định của ổ gốc) | Mất | **Mất** |

Ứng dụng/người dùng tìm IP mới qua: `describe-instances`, output của Terraform (sau này), hoặc tốt hơn là **DNS** trỏ về IP/Elastic IP.

**9. Bẫy chi phí** (5 trong số các ý): NAT Gateway quên xóa sau lab (phát hiện: Cost Explorer theo service "VPC", trang VPC → NAT gateways); Elastic IP/Public IPv4 (tính theo giờ — VPC → Public IPs / IPAM, Cost Explorer "Public IPv4"); instance ở **region khác** (EC2 Global View); EBS volume/snapshot còn sót sau khi terminate (EC2 → Volumes/Snapshots, lọc `available`); ALB/RDS của lab tuần 14 (tính theo giờ kể cả không có traffic); CloudWatch Logs không đặt retention (log tích lũy mãi); dữ liệu ra Internet. Phòng tránh: AWS Budget có cảnh báo, theo dõi credit của Free plan, tag `Project`/`Env` cho mọi thứ + Tag Editor/Resource Explorer để tìm, checklist dọn dẹp cuối mỗi lab, Terraform `destroy` từ Module 07.

**10. Bảo vệ bucket backup.** Block Public Access: chặn mọi cấu hình làm bucket/object public, kể cả do lỡ tay viết policy sai. IAM policy (phía người dùng/role): ai được làm gì — role EC2 chỉ `PutObject` vào `backups/`. Bucket policy (phía tài nguyên): ràng buộc từ phía bucket, ví dụ bắt buộc HTTPS, chỉ cho principal cụ thể. Versioning: ghi đè/xóa nhầm vẫn khôi phục được bản cũ (bảo vệ khỏi lỗi người và một phần ransomware). Versioning **không** thay backup ở nơi khác: xóa bucket, xóa tài khoản, lỗi cấu hình toàn tài khoản vẫn mất hết. Lifecycle: tự xóa bản cũ quá N ngày / chuyển lớp lưu trữ rẻ hơn → chi phí không tăng mãi.

**11. RDS vs container.** RDS: backup tự động + khôi phục về **thời điểm bất kỳ** trong thời gian lưu, Multi-AZ (standby đồng bộ ở AZ khác, failover tự động), AWS vá engine trong maintenance window, giám sát sẵn; đắt hơn, ít quyền kiểm soát (không SSH, cấu hình qua parameter group). Container trên EC2: rẻ (dùng chung máy), toàn quyền, nhưng **bạn** lo backup, vá lỗi, khôi phục, và máy chết = DB chết. Khuyên chuyển khi: có dữ liệu thật cần RPO/RTO rõ ràng, nhiều instance ứng dụng cần chung một DB, team không có người trực vận hành DB.

**12. ALB + ASG.** Target trả 503 liên tục → vượt ngưỡng unhealthy → **ALB ngừng gửi traffic** tới target đó. Nếu ASG dùng health check kiểu ELB → ASG đánh dấu instance unhealthy → **terminate và tạo instance mới** từ launch template. PostgreSQL trong instance của ASG: instance có thể bị xóa bất cứ lúc nào (scale in, thay thế khi unhealthy) → mất dữ liệu; nhiều instance = nhiều DB riêng lẻ không đồng bộ. Instance trong ASG phải **stateless**; trạng thái nằm ở RDS/S3.

**13. CloudWatch.** Metric: chuỗi số theo thời gian (CPU, network). Log: dòng sự kiện văn bản. Alarm: theo dõi một metric, vượt ngưỡng trong N chu kỳ → hành động (SNS email, Auto Scaling). EC2 metric mặc định đến từ **hypervisor**, nhìn từ ngoài vào máy ảo — không thấy RAM hay dung lượng filesystem bên trong hệ điều hành; muốn có phải chạy CloudWatch Agent. `StatusCheckFailed`: phát hiện sự cố hạ tầng/hệ điều hành (phần cứng host, kernel treo, mất mạng của instance). Smoke test `/actuator/health`: phát hiện sự cố **ứng dụng** (container chết, mất kết nối DB, deploy hỏng) — máy vẫn "khỏe" trong mắt EC2.

**14. TTL.** Resolver của ISP/người dùng đã **cache** bản ghi cũ tới 3600 giây; sửa bản ghi không xóa được cache ở bên ngoài. Cách tránh: (a) dùng **Elastic IP** — IP không đổi khi stop/start. Nó **thay thế** public IP tự gán, nên lúc máy chạy chi phí như nhau (0,005 USD/giờ); khác biệt: Elastic IP vẫn tính tiền cả khi máy đang stop hoặc chưa gắn vào đâu — phải nhớ release khi không dùng; (b) **hạ TTL** (ví dụ 60–300 giây) **trước** những thay đổi dự kiến — đánh đổi: nhiều truy vấn DNS hơn (Route 53 tính theo số truy vấn, nhưng nhỏ ở quy mô này); (c) về lâu dài: đặt sau ALB và dùng bản ghi **alias**.

---

## Phần B1 — Policy backup

`part-b/taskhub-backup-writer.json` (thay `111122223333` bằng account ID của bạn):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "UploadIntoBackupsPrefixOnly",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::taskhub-backups-111122223333/backups/*"
    },
    {
      "Sid": "ListOnlyBackupsPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::taskhub-backups-111122223333",
      "Condition": {
        "StringLike": { "s3:prefix": ["backups/", "backups/*"] }
      }
    }
  ]
}
```

Kết quả Policy Simulator mong đợi:

| # | Kết quả | Vì sao |
|---|---|---|
| 1 | allowed | Khớp statement 1 |
| 2 | denied | Resource `other/*` không khớp `backups/*` → không allow nào → từ chối ngầm |
| 3 | denied | Không statement nào cho `s3:DeleteObject` → từ chối ngầm |
| 4 | allowed | Khớp statement 2, điều kiện `s3:prefix` thỏa |
| 5 | denied | Không có `s3:prefix` → điều kiện `StringLike` không thỏa → statement không áp dụng |
| 6 | denied | Bucket khác không có trong `Resource` |

**Hai `Resource` khác nhau:** `ListBucket` là thao tác trên **bucket** (ARN không có `/…`); `PutObject` là thao tác trên **object** (ARN `bucket/key`). Ghi `Resource` của bucket cho `PutObject` (hoặc ngược lại) → thao tác bị từ chối dù "trông đúng". **Ca 2 và 3 bị từ chối dù không có `Deny`:** mặc định của IAM là từ chối ngầm — chỉ những gì được allow tường minh mới được phép.

🟨 Ghi chú cho v5: `aws s3 cp` file lớn dùng multipart upload — các bước upload phần được cấp bởi `s3:PutObject`; muốn script tự hủy upload dở thì thêm `s3:AbortMultipartUpload` trên cùng resource object. Bucket dùng SSE-S3 nên không cần quyền KMS.

---

## Phần B2 — Trang trạng thái bằng CLI

### `part-b/user-data.sh`

```bash
#!/bin/bash
set -euo pipefail
# R6 — chốt chặn chi phí: đặt lịch tắt máy TRƯỚC mọi thứ khác (kể cả khi phần sau lỗi).
# Kết hợp với --instance-initiated-shutdown-behavior terminate → tắt máy = terminate.
shutdown -h +90 "ck06b: auto shutdown after 90 minutes"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx

# R5 — IMDSv2: lấy token bằng PUT, rồi gửi token trong header của mỗi request
TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -sS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.html <<EOF
<h1>ck06b status</h1>
<p>instance-id: ${IID}</p>
<p>availability-zone: ${AZ}</p>
EOF
```

`index.html` được nginx của Ubuntu ưu tiên trước trang mặc định (`index index.html index.htm index.nginx-debian.html;` trong site `default`).

### Các lệnh (WSL)

```bash
export AWS_PROFILE=taskhub
cd ~/devops-journey/week14/checkpoint/part-b

MYIP=$(curl -s https://checkip.amazonaws.com)
VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc \
  --query "Vpcs[0].VpcId" --output text)
SUBNET=$(aws ec2 describe-subnets --filters Name=tag:Name,Values=taskhub-public-b \
  --query "Subnets[0].SubnetId" --output text)
echo "$MYIP $VPC $SUBNET"            # kiểm tra trước khi tạo gì

# R1 — role + instance profile
cat > trust-ec2.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
EOF
aws iam create-role --role-name ck06b-ssm-only \
  --assume-role-policy-document file://trust-ec2.json \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab                         # ⚠️ tạo tài nguyên
aws iam attach-role-policy --role-name ck06b-ssm-only \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name ck06b-ssm-only
aws iam add-role-to-instance-profile --instance-profile-name ck06b-ssm-only --role-name ck06b-ssm-only
sleep 15   # IAM nhất quán sau (eventual consistency): profile vừa tạo có thể chưa dùng được ngay

# R2 — security group
SG=$(aws ec2 create-security-group --group-name ck06b-status-sg \
  --description "ck06b status page" --vpc-id "$VPC" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Project,Value=taskhub},{Key=Env,Value=lab}]' \
  --query GroupId --output text)                                             # ⚠️
aws ec2 authorize-security-group-ingress --group-id "$SG" \
  --protocol tcp --port 80 --cidr "${MYIP}/32"

# R3–R6 — instance
TAGS='{Key=Name,Value=ck06b-status},{Key=Project,Value=taskhub},{Key=Env,Value=lab},{Key=Owner,Value=phuong},{Key=ManagedBy,Value=manual}'
IID=$(aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --instance-type t3.micro \
  --subnet-id "$SUBNET" \
  --security-group-ids "$SG" \
  --iam-instance-profile Name=ck06b-ssm-only \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --instance-initiated-shutdown-behavior terminate \
  --user-data file://user-data.sh \
  --tag-specifications "ResourceType=instance,Tags=[$TAGS]" "ResourceType=volume,Tags=[$TAGS]" \
  --query "Instances[0].InstanceId" --output text)                           # ⚠️ bắt đầu tính phí
aws ec2 wait instance-running --instance-ids "$IID"
aws ec2 describe-instances --instance-ids "$IID" \
  --query "Reservations[0].Instances[0].[PublicIpAddress,Placement.AvailabilityZone,MetadataOptions.HttpTokens]" \
  --output text
```

| Tham số đáng chú ý | Vì sao |
|---|---|
| `resolve:ssm:/aws/service/canonical/...` | EC2 tự tra AMI ID mới nhất từ SSM parameter công khai của Canonical — không chép cứng ID (ID khác nhau theo region và đổi theo bản vá) |
| `--metadata-options HttpTokens=required` | IMDSv2 bắt buộc (R3) |
| `--instance-initiated-shutdown-behavior terminate` | `shutdown` từ bên trong máy = **terminate**, không phải stop (R6) |
| `--tag-specifications` cho `instance` **và** `volume` | Tag gắn ngay lúc tạo, ổ EBS cũng có tag để tìm và tính chi phí (R4) |
| `--user-data file://...` | AWS CLI tự mã hóa base64 cho tham số này |

Nếu `taskhub-public-b` **không** bật tự gán public IPv4, instance sẽ không có IP công khai: thêm `--associate-public-ip-address` vào `run-instances` (và ghi lại phát hiện này — subnet "public" của bạn có đúng như network plan không?).

**Vì sao không dùng lại `taskhub-ec2-role` (R1):** role đó có thêm quyền đọc Parameter Store `/taskhub/dev/*`, ghi log, ghi S3 backup. Máy trang trạng thái không cần những quyền đó; nếu nó bị chiếm, kẻ tấn công lấy được mật khẩu DB. Mỗi workload một role, quyền tối thiểu.

**Kiểm thử 3 — vì sao trang chủ vẫn có instance ID:** user data đã dùng IMDSv2 (PUT lấy token rồi gửi kèm header). Lệnh `curl` không token là kiểu IMDSv1 → bị từ chối với `401`.

### Dọn dẹp (R7)

```bash
aws ec2 terminate-instances --instance-ids "$IID"                          # ⚠️ xóa
aws ec2 wait instance-terminated --instance-ids "$IID"
aws ec2 delete-security-group --group-id "$SG"                             # chỉ xóa được khi instance đã terminate xong
aws iam remove-role-from-instance-profile --instance-profile-name ck06b-ssm-only --role-name ck06b-ssm-only
aws iam delete-instance-profile --instance-profile-name ck06b-ssm-only
aws iam detach-role-policy --role-name ck06b-ssm-only \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name ck06b-ssm-only

# Chứng minh
aws ec2 describe-instances --filters Name=tag:Name,Values=ck06b-status \
  --query "Reservations[].Instances[].State.Name" --output text           # terminated
aws ec2 describe-volumes --filters Name=tag:Name,Values=ck06b-status \
  --query "Volumes[].VolumeId" --output text                              # rỗng (ổ gốc DeleteOnTermination)
aws ec2 describe-security-groups --group-ids "$SG" 2>&1 | tail -n 1       # InvalidGroup.NotFound
aws iam get-instance-profile --instance-profile-name ck06b-ssm-only 2>&1 | tail -n 1   # NoSuchEntity
aws iam get-role --role-name ck06b-ssm-only 2>&1 | tail -n 1               # NoSuchEntity
```

Thứ tự gỡ IAM quan trọng: role không xóa được khi còn nằm trong instance profile hoặc còn policy gắn vào.

---

## Phần C — Break-fix ck06

| Ticket | Tầng | Nguyên nhân gốc | Sửa (tối thiểu, giữ ý định bảo mật) |
|---|---|---|---|
| #6201 | Security group | Inbound TCP 80 chỉ cho phép **từ security group `ck06-alb-sg`** — một load balancer chưa từng tồn tại → không ENI nào thuộc SG đó → mọi gói từ Internet bị từ chối | Thêm rule TCP 80 từ `0.0.0.0/0`. Giữ rule tham chiếu `ck06-alb-sg` để dùng khi có ALB; lúc đó **xóa** rule `0.0.0.0/0` — đó mới là thiết kế đích đúng |
| #6202 | NACL | Luật inbound **90** `deny TCP 1-1023` ("chặn quét cổng") đứng **trước** luật **100** `allow TCP 80` → gói tới cổng 80 khớp luật 90 trước → bị chặn | Thêm luật **80** `allow TCP 80 0.0.0.0/0` (số nhỏ hơn 90), xóa luật 100 thừa. Vẫn giữ ý định chặn các cổng thấp khác |
| #6203 | Security group (outbound) | Outbound chỉ cho TCP **80** ("chỉ cập nhật gói") → SSM Agent không tới được `ssm`/`ssmmessages`/`ec2messages` ở cổng **443**. apt vẫn chạy (mirror Ubuntu dùng HTTP 80), DNS và metadata không bị security group lọc → mọi thứ khác trông bình thường | Thêm outbound TCP 443 tới `0.0.0.0/0`. Agent thử lại định kỳ; chờ vài phút hoặc reboot |
| #6204 | Ứng dụng | nginx `listen 127.0.0.1:80` → chỉ nhận kết nối từ chính máy; gói từ ngoài tới private IP:80 không có socket nào nghe → kernel trả RST → `Connection refused` | Đổi thành `listen 80 default_server;`, `sudo nginx -t && sudo systemctl reload nginx` |

### Bằng chứng và lệnh

**#6201:**

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=ck06-web-sg \
  --query "SecurityGroups[0].IpPermissions[].{port:FromPort,cidr:IpRanges[].CidrIp,fromSG:UserIdGroupPairs[].GroupId}"
# [{"port": 80, "cidr": [], "fromSG": ["sg-0fedcba9876543210"]}]   ← nguồn là một SG, không phải CIDR
aws ec2 describe-network-interfaces --filters Name=group-id,Values=sg-0fedcba9876543210 \
  --query "NetworkInterfaces[].NetworkInterfaceId" --output text
# (rỗng) — không có gì thuộc ck06-alb-sg

aws ec2 authorize-security-group-ingress --group-id <ck06-web-sg> \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP until ALB exists}]'
```

**#6202:**

```bash
aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=<subnet> \
  --query "NetworkAcls[0].Entries[?Egress==\`false\`].[RuleNumber,RuleAction,Protocol,PortRange.From,PortRange.To,CidrBlock]" \
  --output table
# |  90 | deny  | 6 |    1 | 1023  | 0.0.0.0/0 |   ← khớp cổng 80 TRƯỚC
# | 100 | allow | 6 |   80 |   80  | 0.0.0.0/0 |   ← không bao giờ được xét cho cổng 80
# | 110 | allow | 6 | 1024 | 65535 | 0.0.0.0/0 |

aws ec2 create-network-acl-entry --network-acl-id <acl> --ingress --rule-number 80 \
  --protocol 6 --port-range From=80,To=80 --cidr-block 0.0.0.0/0 --rule-action allow
aws ec2 delete-network-acl-entry --network-acl-id <acl> --ingress --rule-number 100
```

Sau #6201 + #6202: `curl -v http://<ip>/` đổi từ **timeout** sang **Connection refused**.

**#6203:** role đã có `AmazonSSMManagedInstanceCore`, route và NACL đều cho 443 ra/cổng tạm vào → nhìn tới **outbound của security group**:

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=ck06-web-sg \
  --query "SecurityGroups[0].IpPermissionsEgress" --output table
# | 80 | tcp | 80 | 0.0.0.0/0 | package updates |    ← không có 443
aws ec2 authorize-security-group-egress --group-id <ck06-web-sg> \
  --ip-permissions 'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTPS to AWS APIs (SSM)}]'
```

🟦 Siết hơn nữa: thay `0.0.0.0/0` bằng VPC interface endpoint cho SSM (tốn phí theo giờ — không dùng trong dự án này).

**#6204:** trong Session Manager:

```bash
sudo ss -ltnp | grep ':80'
# LISTEN 0 511 127.0.0.1:80 0.0.0.0:* users:(("nginx",pid=1234,fd=6),...)   ← chỉ nghe loopback
curl -s localhost | head -1      # <h1>ck06-ok</h1>... — chạy được từ bên trong, nên đây là vấn đề "bind address"
sudo sed -i 's/listen 127.0.0.1:80 default_server;/listen 80 default_server;/' /etc/nginx/sites-available/ck06
sudo nginx -t && sudo systemctl reload nginx
sudo ss -ltnp | grep ':80'       # 0.0.0.0:80
```

Đây chính là bài học bind address ở [Network bài 05](../../02-NETWORKING/05-tcp-udp-ports-firewall.md) — `127.0.0.1` không phải "an toàn hơn", nó là "không ai bên ngoài vào được".

`bash verify.sh` → 4/4. Nếu còn `WARN` về outbound "All traffic": chấp nhận được nếu bạn giải thích (mặc định của AWS, máy cần gọi nhiều API khác nhau), nhưng phương án "TCP 80 + TCP 443" cho thấy bạn hiểu rõ máy cần gì.

---

## Mẫu nhật ký cho một ticket

```markdown
### Ticket #6202 — Vẫn timeout dù SG đã cho HTTP
- Triệu chứng: sau khi thêm rule SG 80 từ 0.0.0.0/0, `curl -m 10 -v http://13.250.x.x/` vẫn
  "Connection timed out after 10001 milliseconds".
- Tầng: NACL (subnet). SG đã đúng (kiểm tra bằng describe-security-groups).
- Tìm ra bằng: liệt kê các điểm kiểm soát trên đường đi; route đúng (0.0.0.0/0 → igw, active);
  describe-network-acls → inbound có luật 90 deny TCP 1-1023 nằm trước luật 100 allow TCP 80.
- Nguyên nhân gốc: NACL xét luật theo số tăng dần, luật khớp đầu tiên thắng. Luật "chặn quét cổng"
  bao trùm cả cổng 80.
- Sửa: thêm luật 80 allow TCP 80 0.0.0.0/0 (trước luật 90), xóa luật 100 thừa. Giữ luật 90 để vẫn
  chặn các cổng thấp khác ở mức subnet.
- Kiểm tra: curl đổi sang "Connection refused" ngay lập tức → lớp mạng đã thông, sang #6204.
- Bài học: khi thêm một luật deny rộng vào NACL, phải kiểm tra mọi luật allow có số lớn hơn.
```
