# Lời giải — Bài 04: Amazon EC2

> Chỉ mở sau khi đã tự làm. Bài: [04-ec2.md](../04-ec2.md). Output trong file này là minh họa.

## Câu hỏi kiểm tra kiến thức (mục 13)

**1. `c7i-flex.large`?**
- `c` là họ compute optimized (nặng CPU).
- `7` là thế hệ 7.
- `i` là CPU Intel.
- `flex` là biến thể Flex, giá rẻ hơn, phù hợp tải không chạy hết CPU liên tục.
- `large` là cỡ máy.

**2. `t3.small` chạy trung bình 35% CPU suốt 24 giờ?**
Máy vượt baseline 15% trên mỗi vCPU. Lượng credit tiêu thêm mỗi giờ = 0,15 × 2 vCPU × 60 phút = **18 credit/giờ** (theo định nghĩa 1 credit = 1 vCPU chạy 100% trong 1 phút).
- **Chế độ `standard`**: máy tiêu credit đã tích. Nếu bắt đầu với số dư đầy (576), sau 24 giờ máy đã tiêu 432 credit nên vẫn chạy nhanh. Sang ngày thứ hai thì cạn, CPU bị hạ về 20%. Nếu bắt đầu với số dư 0, máy bị giới hạn ngay. Không phát sinh thêm phí.
- **Chế độ `unlimited`**: máy chạy nhanh liên tục. Phần vượt baseline trung bình 24 giờ = 0,15 × 2 × 24 = 7,2 vCPU-giờ. Với giá $0,05/vCPU-giờ (trang giá EC2, T3 Linux), mỗi ngày tốn thêm khoảng $0,36, tức hơn 10 USD/tháng chỉ riêng phần surplus. Con số chính xác còn phụ thuộc credit tích từ trước. Ý cần nhớ: **`unlimited` biến vấn đề hiệu năng thành vấn đề chi phí**.

**3. Không hard-code AMI ID.** AMI ID khác nhau theo region và thay đổi mỗi khi Canonical phát hành bản vá. ID cũ có thể chứa lỗ hổng đã được vá, hoặc bị gỡ đi. Thay vào đó, hard-code **đường dẫn SSM parameter** `/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id` và lấy ID lúc chạy.

**4. Vẫn bị tính tiền khi `stopped`:**
- Volume EBS (GB-tháng).
- Elastic IP gắn với máy (EIP luôn bị tính tiền, kể cả khi đang rảnh).
- Snapshot EBS, nếu có.

Thêm nữa: dữ liệu lưu ở dịch vụ khác (S3, log CloudWatch) không liên quan gì đến trạng thái máy, vẫn tính bình thường.

**5. Stop/start:**

| Thứ | Kết quả |
|---|---|
| Public IPv4 tự cấp | **Đổi** |
| Private IPv4 | Giữ nguyên |
| Elastic IP | Vẫn gắn |
| Dữ liệu trên root EBS | Giữ nguyên |
| Dữ liệu trong RAM | Mất |

**6. User data có chạy lại sau stop/start không?** Không. Mặc định user data chỉ chạy ở lần boot đầu tiên. Muốn một tác vụ chạy mỗi lần boot thì làm **systemd unit** và `systemctl enable` nó ([Linux 04](../../01-LINUX/04-processes-systemd.md)). Nginx trong lab tự chạy lại chính vì lý do này (`systemctl enable --now nginx`), không phải nhờ user data.

**7. IMDSv2 chống được gì?** Nó chống **SSRF**: kẻ tấn công lừa ứng dụng gửi một request `GET` tới URL tùy ý, ví dụ `http://169.254.169.254/...`. Với IMDSv1, một request `GET` như vậy là đủ để đọc credential của role. IMDSv2 bắt buộc bước lấy token bằng **`PUT`** kèm header đặc biệt, sau đó mới gửi token trong header của request `GET`. Phần lớn lỗ hổng SSRF chỉ cho kẻ tấn công điều khiển URL của một request `GET`, không chọn được method `PUT` và không thêm được header tùy ý. Vì vậy chúng không lấy được token.

**8. Hop limit 2 cho Docker?** Container chạy trong bridge network, nên gói tin trả lời của IMDS phải đi qua thêm một bước định tuyến (host → `docker0` → container). Mỗi bước làm TTL giảm 1. Với hop limit 1, gói tin trả lời token "chết" trước khi tới container, nên container không nhận được token. Hop limit 2 có giảm bảo mật một chút, vì container cũng lấy được credential của role. Dự án chấp nhận đánh đổi này vì ứng dụng trong container cần gọi AWS (Parameter Store, CloudWatch Logs), còn role thì đã được giới hạn ở quyền tối thiểu.

**9. Ba điều kiện để dùng được Session Manager:**
- (1) SSM Agent đang chạy.
- (2) Instance profile có `AmazonSSMManagedInstanceCore`.
- (3) Có HTTPS 443 outbound tới các endpoint `ssm`, `ssmmessages` và `ec2messages`, thông qua Public IP + IGW, NAT, hoặc VPC interface endpoint.

Máy ở private subnet không có NAT thiếu điều kiện (3): nó không có đường nào ra các endpoint, trừ khi bạn tạo interface endpoint (tính phí theo giờ).

**10. Session Manager tốt hơn SSH ở đâu?**
- Không có port inbound nào, nên không có gì để bot quét.
- Xác thực bằng IAM + MFA thay cho private key có thể bị copy hoặc lộ.
- Thu hồi quyền ở một chỗ (IAM) là xong.
- Ghi log phiên được.
- Không phụ thuộc IP nhà bạn.
- Dùng chung agent với Run Command, thứ mà v3 dùng để deploy.

**11. `DeleteOnTermination=true` ảnh hưởng gì đến dữ liệu PostgreSQL?** Volume `pgdata` của Docker nằm trên root volume. Terminate máy đồng nghĩa root volume bị xóa, kéo theo **mất toàn bộ dữ liệu database**. Dự án xử lý ở **v5** bằng backup `pg_dump` lên S3 cùng với diễn tập restore. Ở v2, bật termination protection để tránh xóa nhầm.

**12. Bỏ `mem_limit` thì sao?** JVM lấy 75% RAM của máy: 0,75 × 2 GiB ≈ **1,5 GiB heap**. Cộng thêm phần ngoài heap, process Java có thể vượt 1,7 GiB, gần bằng toàn bộ máy. PostgreSQL và hệ điều hành thiếu RAM, nên kernel OOM killer giết một process. Nếu nạn nhân là PostgreSQL, ứng dụng trả 503. Nếu là Java, container thoát với mã 137. Đặt `mem_limit` cho container giúp JVM tính heap theo giới hạn của container (ví dụ 768 MiB × 75% ≈ 576 MiB).

**13. System check khác Instance check thế nào?**
- **System** lỗi là lỗi phía hạ tầng AWS. Hãy stop/start để chuyển sang máy vật lý khác, hoặc chờ AWS xử lý.
- **Instance** lỗi là lỗi trong máy của bạn (hết RAM, cấu hình mạng sai, filesystem hỏng). Hãy đọc console output, reboot, hoặc sửa cấu hình. Không vào được thì gỡ volume sang máy khác để sửa (🟦).

**14. Chạy được bao nhiêu `t3.small` với quota mặc định?** Quota 5 vCPU chia cho 2 vCPU mỗi máy = **2** `t3.small` chạy cùng lúc (2 × 2 = 4 ≤ 5; máy thứ ba sẽ cần 6). Instance ở trạng thái stopped **không** tính vào quota.

---

## Bài tập tự làm (mục 14)

### Bài 1 — Đọc cấu hình đang chạy

```bash
aws ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].{Id:InstanceId,Name:Tags[?Key==`Name`]|[0].Value,AZ:Placement.AvailabilityZone,Tokens:MetadataOptions.HttpTokens,Hop:MetadataOptions.HttpPutResponseHopLimit,Profile:IamInstanceProfile.Arn,RootVolume:BlockDeviceMappings[0].Ebs.VolumeId}' \
  --output table

VOL=$(aws ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)
aws ec2 describe-volumes --volume-ids "$VOL" \
  --query 'Volumes[0].{Type:VolumeType,SizeGiB:Size,Encrypted:Encrypted,Iops:Iops,Throughput:Throughput}' --output table
```

Giải thích:
- `{Key:expr,...}` là *multiselect hash* của JMESPath, tạo object có tên cột tùy ý nên bảng dễ đọc.
- Thông tin cỡ và loại volume **không** nằm trong `describe-instances`, vì instance chỉ giữ ID của volume. Phải gọi thêm `describe-volumes`.
- Nếu máy có nhiều volume, `BlockDeviceMappings[0]` chưa chắc là root. Chặt chẽ hơn thì so khớp `DeviceName` với `RootDeviceName`: ``BlockDeviceMappings[?DeviceName==`/dev/sda1`]``.

### Bài 2 — User data hỏng có chủ đích

Bằng chứng nằm trong `aws ec2 get-console-output --instance-id "$IID" --latest --output text`, hoặc trong `/var/log/cloud-init-output.log` (đọc qua Session Manager):

```text
+ apt-get install -y ngnix
E: Unable to locate package ngnix
... Failed to run module scripts_user ...
```

Dòng `+ ...` cuối cùng là lệnh thất bại. Dòng `E:` ngay bên dưới là nguyên nhân.

**Sửa user data rồi stop/start có được không?** Không. Theo tài liệu EC2, user data mới chỉ hiển thị trong metadata sau khi start, còn **script thì không chạy lại**, vì mặc định nó chỉ chạy ở lần boot đầu. Có hai cách đúng:
- Terminate máy rồi tạo máy mới với user data đã sửa. Đây là tư duy "máy dùng một lần" (cattle, not pets).
- Hoặc vào máy và cài tay. Không nên dùng cách này, vì lần dựng sau lại hỏng.

Nhớ terminate máy và kiểm tra checklist dọn dẹp.

### Bài 3 — IMDSv2 mặc định cấp tài khoản

```bash
aws ec2 modify-instance-metadata-defaults --region ap-southeast-1 \
    --http-tokens required --http-put-response-hop-limit 2
aws ec2 get-instance-metadata-defaults --region ap-southeast-1
```

```json
{
    "AccountLevel": {
        "HttpTokens": "required",
        "HttpPutResponseHopLimit": 2
    },
    "ManagedBy": "account"
}
```

Console: EC2 → **Dashboard** → thẻ **Account attributes** → **Data protection and security** → **IMDS defaults** → **Manage**.

Thiết lập này **chỉ áp dụng cho instance tạo mới** trong region đó. Instance đang tồn tại giữ nguyên cấu hình cũ, phải sửa từng máy bằng `modify-instance-metadata-options`. Thiết lập cũng chỉ áp dụng cho **một region**; muốn áp dụng region khác phải chạy lại lệnh cho region đó.

### Bài 4 — Container và hop limit

```bash
# [EC2] Docker đã cài. -m 5 để không treo lâu.
docker run --rm curlimages/curl -sS -m 5 -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" ; echo " exit=$?"
```

```bash
# [WSL] đổi hop limit
aws ec2 modify-instance-metadata-options --instance-id "$IID" \
  --http-endpoint enabled --http-tokens required --http-put-response-hop-limit 1
# ... chạy lại lệnh trên EC2 → timeout (curl: (28) ...), exit khác 0
aws ec2 modify-instance-metadata-options --instance-id "$IID" \
  --http-endpoint enabled --http-tokens required --http-put-response-hop-limit 2
# ... chạy lại → in ra token (chuỗi dài), exit=0
```

Giải thích bằng đường đi của gói tin:
- Container gửi gói tin từ `172.17.0.x`, qua `docker0`, NAT trên host, rồi tới IMDS.
- Gói tin trả lời đi ngược lại: IMDS → host → **định tuyến qua `docker0`** → container.
- Bước định tuyến thêm này làm TTL giảm 1. Với hop limit 1, gói tin trả lời bị bỏ trước khi tới container. Với hop limit 2 thì tới được.
- Process chạy thẳng trên host (không trong container) thì không bị ảnh hưởng.

Nhớ terminate máy sau khi xong.

### Bài 5 — Chi phí 1 tháng

Công thức (giá tra ngày X, ghi rõ nguồn):

```text
P_ec2  = giá t3.small Linux On-Demand Singapore (USD/giờ)    ← Pricing Calculator / Price List API
P_ebs  = giá gp3 Singapore (USD/GB-tháng)                     ← trang giá EBS
P_ipv4 = 0.005 USD/giờ                                       ← trang giá VPC

24/7:          730·P_ec2 + 20·P_ebs + 730·P_ipv4
Học 3 giờ/ngày: 90·P_ec2  + 20·P_ebs + 90·P_ipv4     (≈ 30 ngày × 3 giờ; EBS vẫn tính đủ tháng,
                                                      Public IPv4 tự cấp bị thu hồi khi stop)
Số tháng credit đủ dùng = credit còn lại / chi phí tháng
```

Kết luận đạt yêu cầu phải có:
- Con số cụ thể kèm ngày tra giá.
- Nhận xét: phần instance và IPv4 chiếm phần lớn khi chạy 24/7. Khi stop ngoài giờ học, EBS thành khoản cố định đáng kể.
- Quyết định: chạy 24/7 chỉ trong thời gian cần demo, còn lại stop (hoặc `terraform destroy` từ v4).

### Bài 6 — Runbook "không vào được máy"

Khung đạt yêu cầu (tối đa 1 trang):

```markdown
# Runbook: Không kết nối được EC2 taskhub-app qua Session Manager

## Triệu chứng
Console báo "SSM Agent is not online" / instance không có trong Fleet Manager.

## Chẩn đoán (theo thứ tự)
1. Trạng thái & status check
   aws ec2 describe-instance-status --instance-ids <id> --include-all-instances
   → stopped? impaired? → start / stop-start (System) / xem console output (Instance)
2. IAM: instance profile có AmazonSSMManagedInstanceCore?
   aws ec2 describe-instances ... IamInstanceProfile.Arn
   aws iam list-attached-role-policies --role-name taskhub-ec2-role
3. Mạng ra ngoài: Public IP? Route 0.0.0.0/0 → igw? SG/NACL outbound 443?
4. Agent: aws ec2 get-console-output --latest | tail -50
   (vào được máy) sudo snap services amazon-ssm-agent; /var/log/amazon/ssm/errors.log
## Khắc phục nhanh
- Thiếu role → gắn instance profile (không cần reboot; chờ vài phút)
- Thiếu route/IP → sửa route table / gán IP
- Agent dừng → (qua SSH tạm từ <my-ip>/32 nếu bắt buộc) sudo snap start amazon-ssm-agent
## Sau sự cố
Ghi postmortem ngắn: nguyên nhân gốc, vì sao không phát hiện sớm, alarm nào cần thêm.
```

Điểm cộng nếu runbook ghi rõ: "gắn role vào máy đang chạy dùng `aws ec2 associate-iam-instance-profile`, không cần tạo lại máy".
