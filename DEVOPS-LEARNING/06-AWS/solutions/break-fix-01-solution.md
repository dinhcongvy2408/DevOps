# Lời giải — Break-fix AWS #1 (bf06)

> Chỉ đọc sau khi đã tự làm, hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý trong [đề bài](../labs/break-fix-01/README.md).
> Các đầu ra dưới đây là **minh họa** — ID, IP, thời gian và câu chữ chính xác trên máy bạn sẽ khác.

## Mục lục

- [Bức tranh tổng thể](#bức-tranh-tổng-thể)
- [Lỗi 1 — Subnet không có đường ra Internet](#lỗi-1--subnet-không-có-đường-ra-internet)
- [Lỗi 2 — Security group mở nhầm cổng](#lỗi-2--security-group-mở-nhầm-cổng)
- [Lỗi 3 — NACL chặn gói trả lời](#lỗi-3--nacl-chặn-gói-trả-lời)
- [Lỗi 4 — Role thiếu quyền cho Systems Manager](#lỗi-4--role-thiếu-quyền-cho-systems-manager)
- [Lỗi 5 — User data chạy lúc chưa có mạng](#lỗi-5--user-data-chạy-lúc-chưa-có-mạng)
- [Lỗi 6 — Cấu hình nginx sai cú pháp](#lỗi-6--cấu-hình-nginx-sai-cú-pháp)
- [Template đã sửa](#template-đã-sửa)
- [Phương pháp rút ra](#phương-pháp-rút-ra)

---

## Bức tranh tổng thể

| # | Tầng | Lỗi | Triệu chứng từ laptop | Che lỗi nào |
|---|---|---|---|---|
| 1 | Route table | Không có `0.0.0.0/0 → IGW` | timeout | 4 (agent không ra được Internet), 5 (apt không chạy được lúc boot) |
| 2 | Security group | Mở TCP 8080 thay vì 80 | timeout | — |
| 3 | NACL | Outbound thiếu dải cổng tạm 1024-65535 | timeout | — |
| 4 | IAM | Role thiếu `AmazonSSMManagedInstanceCore` | — (không vào được máy) | 5, 6 (không đọc được log trong máy) |
| 5 | Hệ điều hành | User data chạy một lần lúc chưa có mạng → nginx chưa cài | refused | 6 |
| 6 | Ứng dụng | `nginx.conf` thiếu `;` → giữ trang mặc định | 200 nhưng sai nội dung | — |

Thang triệu chứng: **timeout → refused → 200 sai nội dung → 200 đúng nội dung**. Mỗi lần triệu chứng đổi bậc là một tầng đã được sửa.

```text
Laptop ──► Internet ──► IGW ──► route table (1) ──► NACL inbound ──► SG (2) ──► ENI ──► nginx (5)(6)
   ▲                                                                                     │
   └──────────── Internet ◄── IGW ◄── route table (1) ◄── NACL outbound (3) ◄────────────┘
                                                        (SG stateful: chiều về tự được phép)
SSM Agent ──443──► ssm.ap-southeast-1.amazonaws.com : cần (1) + quyền IAM (4) + NACL out 443/in 1024-65535 (đã có)
```

---

## Lỗi 1 — Subnet không có đường ra Internet

**Bằng chứng:**

```bash
SUBNET=$(aws cloudformation describe-stacks --stack-name bf06 \
  --query "Stacks[0].Outputs[?OutputKey=='SubnetId'].OutputValue" --output text)
aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=$SUBNET \
  --query "RouteTables[0].[RouteTableId,Routes]" --output json
```

```text
[
  "rtb-0a1b2c3d4e5f60718",
  [ { "DestinationCidrBlock": "10.99.0.0/16", "GatewayId": "local", "State": "active", ... } ]
]
```

Chỉ có route `local`. Internet Gateway `bf06-igw` **có tồn tại và đã attach** vào VPC (`aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=<vpc>`), nhưng không route nào trỏ tới nó.

**Nguyên nhân gốc:** subnet "public" là subnet có route table với `0.0.0.0/0 → igw-…`. Tên subnet, việc tự gán public IP, hay việc IGW đã attach đều **không** đủ. Gói tin trả lời từ instance về địa chỉ laptop của bạn không khớp route nào ngoài `local` → bị rơi → timeout.

**Sửa** — Console: VPC → Route tables → `bf06-web-rt` → **Edit routes** → Add route `0.0.0.0/0`, Target *Internet Gateway* → `bf06-igw`. Hoặc CLI:

```bash
IGW=$(aws ec2 describe-internet-gateways --filters Name=tag:Name,Values=bf06-igw \
  --query "InternetGateways[0].InternetGatewayId" --output text)
# ⚠️ thay đổi cấu hình mạng
aws ec2 create-route --route-table-id rtb-0a1b2c3d4e5f60718 \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW"
```

**Kiểm tra:** `verify.sh` mục 1 PASS. `curl` vẫn timeout — bình thường, còn lỗi 2 và 3.

---

## Lỗi 2 — Security group mở nhầm cổng

**Bằng chứng:**

```bash
aws ec2 describe-security-groups --filters Name=group-name,Values=bf06-web-sg \
  --query "SecurityGroups[0].IpPermissions" --output table
```

```text
| FromPort | IpProtocol | ToPort |  CidrIp    | Description |
|  8080    |  tcp       |  8080  | 0.0.0.0/0  |  HTTP       |
```

**Nguyên nhân gốc:** nginx nghe cổng 80 (cổng mặc định của HTTP); rule chỉ cho 8080. Mô tả "HTTP" là chữ người viết, không phải thứ AWS kiểm tra. Security group mặc định **từ chối** mọi thứ không có rule cho phép → SYN tới cổng 80 bị rơi → timeout.

**Sửa:**

```bash
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=bf06-web-sg \
  --query "SecurityGroups[0].GroupId" --output text)
# ⚠️ mở cổng 80 cho Internet (đúng yêu cầu ticket)
aws ec2 authorize-security-group-ingress --group-id "$SG" \
  --ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP}]'
# ⚠️ đóng cổng không ai dùng (quyền tối thiểu)
aws ec2 revoke-security-group-ingress --group-id "$SG" --protocol tcp --port 8080 --cidr 0.0.0.0/0
```

**Không cần** thêm rule outbound: security group là **stateful** — kết nối được phép đi vào thì gói trả lời tự được phép đi ra. (Và security group này vẫn giữ rule outbound mặc định "all traffic".)

---

## Lỗi 3 — NACL chặn gói trả lời

**Bằng chứng:**

```bash
aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=$SUBNET \
  --query "NetworkAcls[0].Entries[?Egress==\`true\`].[RuleNumber,RuleAction,Protocol,PortRange.From,PortRange.To,CidrBlock]" \
  --output table
```

```text
|  100  | allow | 6  |  80  |  80  | 0.0.0.0/0 |
|  110  | allow | 6  | 443  | 443  | 0.0.0.0/0 |
| 32767 | deny  | -1 | None | None | 0.0.0.0/0 |
```

Xét một kết nối cụ thể: laptop `203.0.113.10:50123` → instance `:80`. Gói **trả lời** đi từ instance cổng 80 tới **cổng 50123** của laptop. Outbound chỉ cho cổng **đích** 80 và 443 → gói trả lời rơi vào luật `*` (32767) → **deny** → laptop không bao giờ nhận được SYN-ACK → timeout.

**Nguyên nhân gốc:** NACL là **stateless** — không nhớ kết nối, xét riêng từng gói theo cả hai chiều. Người dựng đã nghĩ tới chiều về cho **máy chủ đi ra ngoài** (inbound 1024-65535 cho apt và SSM Agent — vì vậy hai thứ đó vẫn sẽ chạy) nhưng quên chiều về cho **client đi vào**. Client Linux dùng cổng tạm 32768–60999, Windows dùng 49152–65535; AWS khuyến nghị mở `1024-65535` để bao hết.

**Sửa:**

```bash
NACL=$(aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=$SUBNET \
  --query "NetworkAcls[0].NetworkAclId" --output text)
# ⚠️ thêm luật outbound cho gói trả lời
aws ec2 create-network-acl-entry --network-acl-id "$NACL" --egress \
  --rule-number 120 --protocol 6 --port-range From=1024,To=65535 \
  --cidr-block 0.0.0.0/0 --rule-action allow
```

**Kiểm tra:** `curl -m 10 -v http://<ip>/` giờ báo **`Connection refused`** ngay lập tức thay vì chờ. Đây là bước ngoặt: mạng đã thông hai chiều, máy đã nhận SYN và trả RST vì **không có gì nghe ở cổng 80**.

---

## Lỗi 4 — Role thiếu quyền cho Systems Manager

**Bằng chứng:** Fleet Manager không có instance. Kiểm tra lần lượt ba điều kiện của managed node:

```bash
IID=$(aws cloudformation describe-stacks --stack-name bf06 \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)
aws ec2 describe-instances --instance-ids $IID \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" --output text
# arn:aws:iam::111122223333:instance-profile/bf06-ec2-role   ← có instance profile
aws iam list-attached-role-policies --role-name bf06-ec2-role --output table
# | CloudWatchAgentServerPolicy | arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy |
```

1. Agent: Ubuntu 24.04 AMI có sẵn (snap) ✅
2. Quyền: role chỉ có `CloudWatchAgentServerPolicy` — policy cho CloudWatch Agent gửi metric/log, **không** có các quyền `ssm:*`, `ssmmessages:*`, `ec2messages:*` mà agent cần ❌
3. Mạng ra `ssm.ap-southeast-1.amazonaws.com:443`: chỉ có sau khi sửa lỗi 1 ❌→✅

**Nguyên nhân gốc:** nhầm hai policy có tên nghe giống nhau. Ghi nhớ: Systems Manager cần **`AmazonSSMManagedInstanceCore`**.

**Sửa:**

```bash
# ⚠️ gắn thêm quyền cho role (nhớ: phải gỡ lại trước khi xóa stack — README mục 10)
aws iam attach-role-policy --role-name bf06-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

Agent thử kết nối lại định kỳ; thường vài phút là Online. Muốn nhanh: **Reboot** instance (giữ nguyên public IP, khác với stop/start).

```bash
aws ssm describe-instance-information --filters Key=InstanceIds,Values=$IID \
  --query "InstanceInformationList[0].[PingStatus,PlatformName,AgentVersion]" --output text
# Online  Ubuntu  3.3.xxxx.0
```

🟨 Có thể gỡ `CloudWatchAgentServerPolicy` nếu không chạy CloudWatch Agent (quyền tối thiểu) — nhưng nó không gây lỗi.

---

## Lỗi 5 — User data chạy lúc chưa có mạng

**Bằng chứng** (có thể thấy **ngay từ đầu bài**, không cần Session Manager):

```bash
aws ec2 get-console-output --instance-id $IID --latest --output text | grep -E 'bf06|E:|W:|Failed' | head
```

Hoặc trong Session Manager:

```bash
cloud-init status --long
sudo grep -nE '\[bf06\]|^E:|^W:|Err:' /var/log/cloud-init-output.log | head -20
```

```text
status: error
...
[bf06] setup-web start: 2027-01-20T03:12:01+00:00
Err:1 http://ap-southeast-1.ec2.archive.ubuntu.com/ubuntu noble InRelease
  Could not connect to ap-southeast-1.ec2.archive.ubuntu.com:80 ...
W: Some index files failed to download. They have been ignored, or old ones used instead.
E: Unable to locate package nginx
```

Không có dòng `[bf06] setup-web done` → script dừng giữa chừng (`set -e`). `systemctl status nginx` → `Unit nginx.service could not be found`.

**Nguyên nhân gốc:** user data (`scripts-user` của cloud-init) chỉ chạy **một lần**, ở lần khởi động **đầu tiên**. Lúc đó subnet chưa có route ra Internet (lỗi 1) → không tải được gói → nginx chưa từng được cài. Sửa route **sau đó** không làm user data chạy lại.

**Sửa:** chạy lại script đã được lưu sẵn:

```bash
sudo /opt/bf06/setup-web.sh
```

Lần này `apt-get` chạy được, nginx được cài và **tự khởi động với cấu hình mặc định** — rồi script lại dừng ở `nginx -t` (lỗi 6).

> Bài học cho taskhub v2: user data phải **chạy lại được** (idempotent) và nên ghi log rõ ràng. Tốt hơn nữa: đưa cấu hình server vào công cụ chạy lại được bất cứ lúc nào — đó là lý do Ansible xuất hiện ở v4.

---

## Lỗi 6 — Cấu hình nginx sai cú pháp

**Bằng chứng:**

```bash
curl -s http://<ip>/ | head -5          # từ laptop
```

```text
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

HTTP 200, nhưng là trang mặc định. Trong máy:

```bash
sudo nginx -t
```

```text
nginx: [emerg] invalid number of arguments in "root" directive in /etc/nginx/sites-enabled/bf06:5
nginx: configuration file /etc/nginx/nginx.conf test failed
```

(Số dòng nginx báo thường là dòng **kết thúc** directive — dòng có dấu `;` tiếp theo — nên có thể lệch một dòng so với chỗ thực sự thiếu `;`. Luôn nhìn cả dòng phía trên.)

**Nguyên nhân gốc:** dòng `root /var/www/bf06` thiếu dấu `;` → nginx đọc gộp với dòng dưới thành `root /var/www/bf06 index index.html;` — 3 tham số cho directive chỉ nhận 1. Script dừng ở `nginx -t` (đúng như thiết kế an toàn: không reload cấu hình hỏng). Tiến trình nginx cũ vẫn chạy với cấu hình đã nạp lúc cài → vẫn phục vụ trang mặc định dù file `default` đã bị xóa khỏi `sites-enabled`. **Nếu reboot lúc này**, nginx sẽ không khởi động được nữa (refused) — đây là lý do tiêu chí 4 của bài yêu cầu reboot thử.

**Sửa:**

```bash
sudo sed -i 's|root /var/www/bf06$|root /var/www/bf06;|' /etc/nginx/sites-available/bf06
sudo sed -i 's|root /var/www/bf06$|root /var/www/bf06;|' /opt/bf06/setup-web.sh   # sửa cả script gốc
sudo nginx -t && sudo systemctl reload nginx
curl -s localhost | head -1        # <h1>bf06-ok</h1>...
```

`verify.sh` → 6/6. Reboot thử → vẫn chạy.

---

## Template đã sửa

`diff -u broken-stack.yaml fixed-stack.yaml` (rút gọn, chỉ phần thay đổi):

```diff
+  WebDefaultRoute:
+    Type: AWS::EC2::Route
+    DependsOn: InternetGatewayAttachment
+    Properties:
+      RouteTableId: !Ref WebRouteTable
+      DestinationCidrBlock: 0.0.0.0/0
+      GatewayId: !Ref InternetGateway
@@ WebSecurityGroup
-          FromPort: 8080
-          ToPort: 8080
+          FromPort: 80
+          ToPort: 80
@@
+  NaclOutEphemeral:
+    Type: AWS::EC2::NetworkAclEntry
+    Properties:
+      NetworkAclId: !Ref WebNetworkAcl
+      RuleNumber: 120
+      Protocol: 6
+      RuleAction: allow
+      Egress: true
+      CidrBlock: 0.0.0.0/0
+      PortRange:
+        From: 1024
+        To: 65535
@@ Ec2Role
-        - !Sub arn:${AWS::Partition}:iam::aws:policy/CloudWatchAgentServerPolicy
+        - !Sub arn:${AWS::Partition}:iam::aws:policy/AmazonSSMManagedInstanceCore
@@ WebInstance
     DependsOn:
       - InternetGatewayAttachment
+      - WebDefaultRoute
@@ UserData
-            root /var/www/bf06
+            root /var/www/bf06;
```

`DependsOn: WebDefaultRoute` cho instance là chi tiết quan trọng: nó bảo đảm route ra Internet tồn tại **trước khi** máy khởi động và chạy user data — chính là thứ còn thiếu dẫn tới lỗi 5.

---

## Phương pháp rút ra

1. **Đi theo gói tin, cả hai chiều.** Liệt kê mọi điểm kiểm soát (route, NACL vào, SG, process, NACL ra, route về) rồi kiểm tra lần lượt. Không đoán.
2. **Đọc loại thất bại:** timeout = rơi gói trên đường; refused = tới nơi nhưng không ai nghe; 200 sai nội dung = cấu hình ứng dụng.
3. **Một lỗi có thể che nhiều lỗi.** Lỗi route vừa chặn web, vừa chặn SSM Agent, vừa làm hỏng user data. Sửa xong một lỗi phải **kiểm tra lại** những thứ phụ thuộc vào nó.
4. **Những thứ "chạy một lần"** (user data, migration, script khởi tạo) không tự chạy lại khi môi trường đã được sửa — phải thiết kế để chạy lại được.
5. **Thay đổi bằng tay là nợ.** Mọi sửa đổi trong sự cố phải được đưa ngược vào mã hạ tầng (template, Terraform) — nếu không, lần dựng lại sau sẽ mang đủ lỗi cũ. Đây là động lực của Module 07.
