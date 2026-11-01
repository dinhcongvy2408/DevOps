# Break-fix AWS #1 — "Trang trạng thái không vào được"

> ⏱️ 90–150 phút · Môi trường: `[WSL]` (AWS CLI) + `[AWS Console]` (trình duyệt) · Tuần 13–14
> Kiến thức cần có: Module 06 bài [02 — IAM](../../02-iam.md), [03 — VPC](../../03-vpc-networking.md), [04 — EC2](../../04-ec2.md), [06 — AWS CLI](../../06-aws-cli.md); [Network bài 05 — TCP/UDP, port, firewall](../../../02-NETWORKING/05-tcp-udp-ports-firewall.md); [Network bài 08 — công cụ chẩn đoán](../../../02-NETWORKING/08-network-troubleshooting-tools.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã xong, hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Chi phí ước tính](#2-chi-phí-ước-tính)
- [3. Khởi tạo môi trường](#3-khởi-tạo-môi-trường)
- [4. Công cụ bạn được dùng](#4-công-cụ-bạn-được-dùng)
- [5. Ticket](#5-ticket)
- [6. Luật chơi](#6-luật-chơi)
- [7. Tiêu chí hoàn thành](#7-tiêu-chí-hoàn-thành)
- [8. Sản phẩm phải nộp](#8-sản-phẩm-phải-nộp)
- [9. Gợi ý](#9-gợi-ý)
- [10. Dọn dẹp](#10-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Bối cảnh

Một đồng nghiệp dựng nhanh "trang trạng thái" cho `taskhub` trên AWS: một VPC riêng, một EC2 Ubuntu 24.04 chạy nginx, trang chủ hiển thị chữ `bf06-ok`. Bạn ấy để lại đúng một dòng: *"Mình đã siết bảo mật mạng và tạo role cho EC2 rồi, chạy lệnh deploy là xong."*

Thực tế: từ lúc dựng, **chưa ai mở được trang này**. Instance vẫn `running`, status check `2/2 passed` — nhưng trình duyệt chỉ quay mãi rồi báo hết giờ.

Bạn **không có mã nguồn hạ tầng** (coi như file template không tồn tại), không có SSH key, không có mật khẩu. Thứ bạn có: quyền admin trên tài khoản AWS, Console, AWS CLI, và Session Manager — nếu bạn làm cho nó chạy được.

Đây là loại sự cố bạn sẽ gặp thật: **mọi tầng đều "có vẻ ổn"**, lỗi nằm ở chỗ các tầng ghép với nhau.

---

## 2. Chi phí ước tính

> 💰 **Ước tính:** 1 EC2 `t3.micro` + 1 Public IPv4 trong 1–2 giờ. Public IPv4 là **0,005 USD/giờ**; giá `t3.micro` ở `ap-southeast-1` xem trên [trang giá EC2 On-Demand](https://aws.amazon.com/ec2/pricing/on-demand/) hoặc [AWS Pricing Calculator](https://calculator.aws/) — cả bài thường **dưới 0,10 USD** nếu bạn dọn dẹp đúng hạn, trừ vào credit của Free plan. VPC, subnet, route table, security group, NACL, IAM role, CloudFormation (với tài nguyên AWS) không tính phí riêng.
>
> ⚠️ **Rủi ro chi phí duy nhất là quên xóa.** Đặt hẹn giờ 3 tiếng trên điện thoại ngay bây giờ. Nếu phải dừng giữa chừng quá vài giờ: làm [mục 10 — Dọn dẹp](#10-dọn-dẹp) rồi hôm khác tạo lại (lỗi được cài lại y hệt).

---

## 3. Khởi tạo môi trường

**Điều kiện:** đã làm [bài 00](../../00-aws-account-setup-cost-safety.md) (MFA, Budget) và [bài 06](../../06-aws-cli.md) (AWS CLI v2, `aws login` với profile `taskhub`).

`[WSL]`:

```bash
export AWS_PROFILE=taskhub
aws login                                   # nếu phiên đăng nhập đã hết hạn
aws sts get-caller-identity                 # phải thấy user admin của bạn, KHÔNG phải root
aws configure get region                    # phải là ap-southeast-1

mkdir -p ~/devops-lab/06-aws/bf06 && cd ~/devops-lab/06-aws/bf06
# Đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/06-AWS/labs/break-fix-01/{broken-stack.yaml,verify.sh} .
sed -i 's/\r$//' broken-stack.yaml verify.sh
```

⚠️ **Lệnh tạo tài nguyên tính phí** (đọc mục 2 trước khi Enter):

```bash
aws cloudformation deploy \
  --stack-name bf06 \
  --template-file broken-stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --tags Project=taskhub Env=lab Lab=bf06 ManagedBy=cloudformation Owner=<tên-bạn>
```

| Tham số | Ý nghĩa |
|---|---|
| `deploy` | Tạo change set rồi thực thi; stack chưa có thì tạo mới, có rồi thì cập nhật. Lệnh **chờ** đến khi xong mới trả lại dấu nhắc |
| `--stack-name bf06` | Tên stack — mọi tài nguyên của bài nằm trong stack này, xóa một lần là sạch |
| `--capabilities CAPABILITY_NAMED_IAM` | Bạn xác nhận cho phép template tạo IAM role **có tên cố định**. Thiếu cờ này → lỗi `InsufficientCapabilities` |
| `--tags` | Gắn tag cho stack; CloudFormation lan truyền tag xuống các tài nguyên hỗ trợ tag |

Đầu ra mong đợi (minh họa):

```text
Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - bf06
```

Lấy địa chỉ trang và thử:

```bash
aws cloudformation describe-stacks --stack-name bf06 \
  --query "Stacks[0].Outputs" --output table
curl -m 10 -v http://<PublicIp>/
bash verify.sh                       # kiểm tra tiến độ bất cứ lúc nào (lần đầu: 0/6)
```

> Lỗi khi deploy? `aws cloudformation describe-stack-events --stack-name bf06 --max-items 15` — tìm sự kiện `CREATE_FAILED` **đầu tiên** (theo thời gian). Lỗi hay gặp: hết quota vCPU của tài khoản mới (xem [bài 04](../../04-ec2.md)), quên `--capabilities`, đăng nhập nhầm region.

---

## 4. Công cụ bạn được dùng

| Mục đích | Ở đâu / lệnh (tất cả đều chỉ **đọc**, trừ khi bạn chủ động sửa) |
|---|---|
| Trạng thái instance, status check, IP | `[AWS Console]` EC2 → Instances → `bf06-web` · `aws ec2 describe-instances --filters Name=tag:Name,Values=bf06-web` |
| Log khởi động (không cần vào máy) | EC2 → chọn instance → **Actions → Monitor and troubleshoot → Get system log** · `aws ec2 get-console-output --instance-id <id> --latest --output text` |
| Subnet, route table, IGW | VPC → Subnets (tab **Route table**, **Network ACL**) · `aws ec2 describe-route-tables`, `describe-internet-gateways`, `describe-subnets` |
| Security group | EC2 → Security Groups · `aws ec2 describe-security-groups --group-ids <sg>` |
| Network ACL | VPC → Network ACLs (tab **Inbound rules**, **Outbound rules**) · `aws ec2 describe-network-acls` |
| Role của instance | EC2 → instance → tab **Security** → IAM Role → IAM · `aws iam get-instance-profile`, `list-attached-role-policies` |
| Systems Manager | Systems Manager → **Fleet Manager** (danh sách managed node) · `aws ssm describe-instance-information` |
| Vào máy (khi đã sửa được) | EC2 → instance → **Connect** → tab **Session Manager** → Connect (shell trong trình duyệt, user `ssm-user` có sudo) |
| Trong máy | `cloud-init status --long`, `sudo tail -n 80 /var/log/cloud-init-output.log`, `systemctl status nginx`, `sudo nginx -t`, `ss -ltnp`, `curl -sv localhost` |
| Từ laptop | `curl -m 10 -v http://<ip>/`, `nc -vz -w 5 <ip> 80` |
| Kiểm tra tiến độ | `bash verify.sh` |

**Phân biệt hai kiểu thất bại của `curl`** — đây là manh mối số một của bài (ôn [Network bài 05](../../../02-NETWORKING/05-tcp-udp-ports-firewall.md)):

| `curl` báo | Nghĩa ở tầng mạng | Hướng điều tra |
|---|---|---|
| `Connection timed out` / `Operation timed out` | Gói SYN hoặc gói trả lời **bị rơi** đâu đó, không ai trả lời | Đường đi: route, NACL, security group, public IP |
| `Connection refused` | Gói tin **tới nơi**, máy đích trả RST vì không có gì lắng nghe ở cổng đó | Trong máy: service, cổng, địa chỉ bind |
| Trả về HTTP nhưng sai nội dung | Mạng ổn, server chạy, nhưng **cấu hình** không như mong đợi | Cấu hình ứng dụng |

---

## 5. Ticket

### 🎫 Ticket #6101 — P1 — Trang trạng thái không truy cập được

> **Người báo:** Trưởng nhóm
> **Mô tả:** `http://<PublicIp>/` không vào được từ bất kỳ đâu. Instance chạy, status check xanh.
> **Kết quả mong đợi:** `curl http://<PublicIp>/` từ laptop trả **HTTP 200** với nội dung chứa `bf06-ok`. Trang phải mở cho **mọi người trên Internet** (`0.0.0.0/0`) ở cổng **80**.
> **Ghi chú:** Có **nhiều lỗi xếp chồng** trên đường đi của gói tin. Sửa xong một lỗi, triệu chứng có thể **đổi** (từ timeout sang refused, từ refused sang sai nội dung) — đó là dấu hiệu tiến bộ.

### 🎫 Ticket #6102 — P2 — Không vào được máy để xem log

> **Người báo:** Team vận hành
> **Mô tả:** "Không có SSH key, mà Session Manager cũng không thấy instance này. Không xem được log trong máy."
> **Kết quả mong đợi:** Instance xuất hiện trong **Fleet Manager** với trạng thái **Online**; mở được shell bằng Session Manager. **Không** mở cổng 22, không tạo key pair.

---

## 6. Luật chơi

1. **Không đọc `broken-stack.yaml` và `verify.sh`** trước khi xong — coi như hạ tầng do người khác dựng.
2. **Không dùng AI.** Được dùng: Console, AWS CLI, docs AWS chính thức, các bài trong giáo trình.
3. **Sửa tài nguyên đang có, không tạo bản thay thế:** không tạo VPC/subnet/route table/security group/NACL/role **mới**, không gắn Elastic IP, không mở cổng 22, không tạo key pair, không stop/terminate instance (stop/start làm **đổi** public IP; reboot thì được).
4. **Không chạy lại `aws cloudformation deploy`** với template đã sửa cho tới khi xong bài. Bạn đang luyện xử lý sự cố trên hệ thống đang chạy; viết lại template là việc **sau** sự cố (mục 8).
5. **Quyền tối thiểu:** chỉ mở đúng thứ cần (TCP 80). "Mở hết cho chắc" (`All traffic`, NACL cho phép mọi thứ) là không đạt, dù trang chạy.
6. **Ghi lại mọi thay đổi** bạn làm (tài nguyên nào, trước/sau) — mục 10 cần danh sách này để dọn dẹp được.
7. Mỗi lỗi: ghi **bằng chứng đầu tiên** (dòng log, kết quả lệnh, ảnh màn hình) **trước khi** sửa.

---

## 7. Tiêu chí hoàn thành

1. `bash verify.sh` → **6/6**, không còn `WARN` nào.
2. `curl -s http://<PublicIp>/` từ laptop chứa `bf06-ok`.
3. Mở được Session Manager vào `bf06-web` và chạy `sudo nginx -t` thành công.
4. **Bài tập "sau sự cố":** trong máy, chạy lại `sudo reboot`, chờ 2 phút, trang **vẫn** chạy. (Nếu không — bạn mới sửa triệu chứng, chưa sửa nguyên nhân.)

---

## 8. Sản phẩm phải nộp

Tạo `~/devops-journey/week14/break-fix-aws-01.md` gồm:

1. **Timeline** các lỗi theo thứ tự bạn gặp, kèm triệu chứng `curl` (timeout / refused / sai nội dung) ở từng mốc.
2. Mỗi lỗi theo [mẫu nhật ký debug](../../../00-ROADMAP/templates/troubleshooting-journal-template.md):

   ```markdown
   ### Lỗi N: <tên ngắn>
   - Triệu chứng (lệnh + kết quả nguyên văn):
   - Tầng nào (route / NACL / SG / IAM / hệ điều hành / ứng dụng):
   - Tìm ra bằng cách nào (Console ở đâu / lệnh CLI nào):
   - Nguyên nhân gốc:
   - Cách sửa (Console hoặc lệnh CLI, trước/sau):
   - Vì sao lỗi này che lỗi khác (nếu có):
   ```

3. **Sơ đồ đường đi của gói tin** từ laptop tới nginx và chiều về, đánh dấu từng điểm kiểm soát (IGW, route table, NACL vào/ra, SG, process) và lỗi nằm ở đâu.
4. **Sửa ở gốc:** viết `fixed-stack.yaml` — bản template đã sửa hết lỗi (bây giờ mới được mở `broken-stack.yaml`). So sánh bằng `diff -u broken-stack.yaml fixed-stack.yaml` và dán vào nhật ký. 🟨 Không bắt buộc deploy bản sửa.
5. Một đoạn ngắn: vì sao **user data** chỉ là "chạy một lần lúc khởi động đầu tiên" lại làm sự cố này khó hơn, và v2 của taskhub nên rút ra điều gì.

---

## 9. Gợi ý

Chỉ mở từng cấp khi đã thử ít nhất 15 phút ở cấp trước.

<details>
<summary>💡 Gợi ý cấp 1 — Hướng tiếp cận</summary>

- Bắt đầu từ **ngoài vào trong**, theo đúng đường đi của gói tin: Internet → IGW → route table của subnet → NACL (vào) → security group → process trong máy → và **chiều về** qua NACL (ra). Đừng nhảy vào máy trước khi chắc phần mạng.
- Status check `2/2` chỉ nói "phần cứng ảo và hệ điều hành khởi động được", **không** nói gì về mạng của bạn hay ứng dụng.
- Một subnet là "public" vì **điều gì**, không phải vì cái tên.
- Security group và NACL khác nhau ở một chữ: **stateful**. Chữ đó quyết định bạn có cần nghĩ tới chiều về hay không.
- Session Manager cần **ba thứ** cùng lúc. Có thể bạn thiếu nhiều hơn một.
- Không vào được máy vẫn đọc được log khởi động — tìm trong menu **Monitor and troubleshoot**.
- Khi triệu chứng đổi từ *timeout* sang *refused*: chúc mừng, mạng đã thông. Câu hỏi tiếp theo: **có gì đang lắng nghe ở cổng 80 không, và vì sao không?**

</details>

<details>
<summary>💡 Gợi ý cấp 2 — Chỗ cần nhìn</summary>

- Route table **đang gắn với subnet** (VPC → Subnets → tab *Route table*) có dòng `0.0.0.0/0` không? Target là gì? Một Internet Gateway "đã attach vào VPC" vẫn vô dụng nếu không route nào trỏ tới nó.
- Security group: so cổng trong rule với cổng nginx thật sự nghe. Mô tả của rule ghi "HTTP" không có nghĩa là cổng đúng.
- NACL: viết ra một kết nối cụ thể — laptop của bạn (cổng nguồn ngẫu nhiên, ví dụ 50123) → instance cổng 80. Gói **trả lời** đi từ cổng nào tới cổng nào? Bảng **Outbound rules** có luật nào cho phép nó không?
- Session Manager: (1) agent có trong AMI không — Ubuntu 24.04 có sẵn; (2) role của instance có policy nào? So với policy mà docs Systems Manager yêu cầu; (3) agent có đường ra `ssm.ap-southeast-1.amazonaws.com:443` không — phụ thuộc chính các lỗi mạng ở trên.
- Sau khi sửa quyền, agent cần vài phút để nhận. Đợi 5–10 phút hoặc **Reboot** instance (reboot giữ nguyên public IP).
- Trong system log hoặc `/var/log/cloud-init-output.log`, tìm dòng `[bf06]` và các dòng `E:` / `W:` của `apt-get`. Lúc máy khởi động lần đầu, nó có ra được Internet không?
- Script cài đặt được lưu lại trong máy: xem `/opt/bf06/`.
- `nginx -t` trước, `systemctl reload` sau — và đọc **số dòng** mà `nginx -t` chỉ ra.

</details>

<details>
<summary>💡 Gợi ý cấp 3 — Gần như đáp án</summary>

Thứ tự lỗi hợp lý (bạn có thể gặp 1–3 theo thứ tự khác, vì cả ba đều cho triệu chứng *timeout*):

1. Route table `bf06-web-rt` gắn với subnet **không có** route `0.0.0.0/0 → igw-…` → subnet không phải public thật. Thêm route.
2. Security group `bf06-web-sg` mở TCP **8080** thay vì **80**. Thêm rule 80 từ `0.0.0.0/0`, xóa rule 8080.
3. NACL `bf06-web-nacl` chiều **Outbound** chỉ cho TCP 80 và 443 — thiếu dải cổng tạm `1024-65535` cho gói trả lời tới client. Thêm luật outbound allow TCP 1024-65535 tới `0.0.0.0/0`.
   → Sau 1–3: `curl` chuyển từ *timeout* sang *refused*.
4. Role `bf06-ec2-role` chỉ có `CloudWatchAgentServerPolicy`, **thiếu** `AmazonSSMManagedInstanceCore` → instance không thành managed node. Gắn policy, chờ hoặc reboot.
5. User data chạy **một lần** lúc khởi động đầu tiên — khi đó subnet chưa ra được Internet (lỗi 1) → `apt-get` thất bại → nginx **chưa từng được cài**. Chạy lại `sudo /opt/bf06/setup-web.sh`.
6. Script ghi file cấu hình nginx thiếu dấu `;` sau dòng `root /var/www/bf06` → `nginx -t` báo lỗi, script dừng → nginx vẫn chạy cấu hình mặc định ("Welcome to nginx!") thay vì trang `bf06-ok`. Sửa `/etc/nginx/sites-available/bf06` (và cả script), `sudo nginx -t && sudo systemctl reload nginx`.

</details>

---

## 10. Dọn dẹp

> ⚠️ Làm **cùng ngày**. Xóa stack là **không hoàn tác được** — nhưng đó chính là điều bạn muốn.

**Bước 1 — Hoàn tác những thay đổi có thể chặn việc xóa stack.** CloudFormation xóa được tài nguyên **nó tạo ra**, kể cả khi bạn đã sửa chúng bằng tay (route, rule SG, rule NACL bạn thêm vào sẽ biến mất cùng tài nguyên chứa chúng). Nhưng có thứ nó **không biết** và có thể làm việc xóa thất bại:

- Policy bạn **gắn thêm** vào role `bf06-ec2-role`: IAM không cho xóa role khi còn policy gắn vào mà CloudFormation không quản lý. Gỡ trước:

  ```bash
  aws iam list-attached-role-policies --role-name bf06-ec2-role --output table
  # ⚠️ gỡ policy bạn đã gắn tay (lặp lại cho từng policy không có trong template)
  aws iam detach-role-policy --role-name bf06-ec2-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  ```

- Nếu bạn lỡ tạo tài nguyên **mới** trong VPC `bf06-vpc` (vi phạm luật 3 — route table, security group, ENI, Elastic IP…): xóa chúng **trước**. VPC không xóa được khi còn tài nguyên bên trong, và Elastic IP còn giữ thì **vẫn tính tiền** dù instance đã mất.

**Bước 2 — Xóa stack và chờ:**

```bash
aws cloudformation delete-stack --stack-name bf06          # ⚠️ xóa toàn bộ tài nguyên của bài
aws cloudformation wait stack-delete-complete --stack-name bf06
echo "exit code: $?"                                       # 0 = xóa xong
```

Nếu `wait` báo lỗi (trạng thái `DELETE_FAILED`): đọc sự kiện để biết tài nguyên nào kẹt và vì sao, xử lý tài nguyên đó bằng tay, rồi chạy lại `delete-stack`:

```bash
aws cloudformation describe-stack-events --stack-name bf06 --max-items 20 \
  --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceStatusReason]" --output table
```

**Bước 3 — Kiểm tra không còn gì sót** (mọi lệnh đều phải trả về rỗng / lỗi "không tồn tại"):

```bash
aws cloudformation describe-stacks --stack-name bf06 2>&1 | tail -n 1     # ... does not exist
aws ec2 describe-instances --filters Name=tag:Lab,Values=bf06 \
  --query "Reservations[].Instances[?State.Name!='terminated'].InstanceId" --output text
aws ec2 describe-vpcs --filters Name=cidr,Values=10.99.0.0/16 --query "Vpcs[].VpcId" --output text
aws ec2 describe-addresses --query "Addresses[].PublicIp" --output text   # Elastic IP: phải rỗng (nếu bạn không dùng ở bài khác)
aws iam get-role --role-name bf06-ec2-role 2>&1 | tail -n 1               # ... NoSuchEntity
```

**Bước 4** — Ngày hôm sau, mở **Billing and Cost Management** xem chi phí EC2/VPC của ngày làm bài có khớp ước tính ở mục 2 không. Ghi con số vào nhật ký.

Muốn làm lại từ đầu: xóa stack như trên rồi chạy lại lệnh `deploy` ở mục 3.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS CLI — `cloudformation deploy`](https://docs.aws.amazon.com/cli/latest/reference/cloudformation/deploy/index.html) | Các cờ `--capabilities`, `--tags`, hành vi chờ đến khi xong | 2026-10-31 |
| [Canonical — Find Ubuntu images on AWS](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/) | Đường dẫn SSM parameter của AMI Ubuntu | 2026-10-31 |
| [Amazon VPC — Network ACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html) | NACL stateless, luật xét theo thứ tự số, dải cổng tạm; NACL không lọc DNS tới Route 53 Resolver và IMDS | 2026-10-31 |
| [Systems Manager — Find AMIs with the SSM Agent preinstalled](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html) | Ubuntu 24.04 có sẵn SSM Agent (snap), lệnh kiểm tra trạng thái | 2026-10-31 |
| [Systems Manager — Troubleshooting managed node availability](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-managed-nodes.html) | Điều kiện để instance thành managed node | 2026-10-31 |
| [CloudFormation — `AWS::EC2::NetworkAclEntry`](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-ec2-networkaclentry.html) | Thuộc tính luật NACL | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Giá Public IPv4 | 2026-10-31 |
