# Lời giải — Bài 09: Route 53

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; `example.com`, `203.0.113.x` là giá trị dành cho tài liệu.

Quay lại bài: [09-route53.md](../09-route53.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)
- [Phần C — Câu hỏi ❓ trong bài thực hành](#phần-c--câu-hỏi--trong-bài-thực-hành)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Registrar / authoritative / resolver.**
Registrar bán quyền dùng tên miền và ghi vào TLD "tên miền dùng name server nào". DNS hosting có thẩm quyền lưu record và trả lời về vùng của mình. Resolver đi hỏi hộ client theo chuỗi ủy quyền và cache kết quả. Route 53 đóng được cả ba: Route 53 Domains (registrar), hosted zone (authoritative), Route 53 Resolver trong VPC (resolver) — cộng thêm health check.

**2. Record tự tạo; 4 name server.**
NS (4 name server gán cho zone) và SOA. Bốn name server nằm ở bốn TLD khác nhau (`.com`, `.net`, `.org`, `.co.uk`) để sự cố ở một TLD hay một nhóm máy chủ không làm tên miền mất phân giải.

**3. CNAME ở apex; alias.**
Ở apex đã có NS và SOA; quy tắc DNS không cho CNAME cùng tồn tại với record khác cùng tên. Alias là phần mở rộng của Route 53: Route 53 tự tra IP của tài nguyên đích và trả về A/AAAA, nên đặt được ở apex.

**4. Alias vs CNAME.**
(1) Đích: alias chỉ trỏ tới một số tài nguyên AWS và record cùng zone; CNAME trỏ tới tên bất kỳ. (2) Phí: truy vấn alias tới tài nguyên AWS miễn phí; CNAME tính phí (trỏ sang record Route 53 khác còn bị tính hai truy vấn). (3) `dig`: alias hiện là `A`/`AAAA`; CNAME hiện là `CNAME`. Thêm: alias tới tài nguyên AWS không tự đặt TTL được.

**5. Alias tới EC2.**
Danh sách đích alias không có EC2 instance. Với một EC2, dùng record **A** chứa public IP (hoặc Elastic IP). Có load balancer thì alias tới load balancer.

**6. TTL; đổi IP an toàn.**
TTL là số giây resolver được giữ câu trả lời. Với TTL 86400: hạ TTL xuống 60 → chờ ít nhất 86400 giây để mọi cache nhận TTL mới → đổi giá trị sang IP mới → giữ server cũ thêm vài TTL → nâng TTL lên lại.

**7. Đổi NS sau 2 giờ chưa hiệu lực.**
Record NS của tên miền ở tầng TLD có TTL dài (thường 172800 giây = 2 ngày). Resolver đã cache bộ NS cũ sẽ tiếp tục hỏi DNS cũ cho tới khi hết TTL. Chứng minh: `dig +trace example.com` (thấy TLD đã trả NS mới) so với `dig NS example.com @<resolver-của-người-bị-lỗi>` (vẫn bộ cũ, TTL còn lại lớn).

**8. Xóa zone sau 3 giờ.**
Không mất phí zone — theo trang giá, zone xóa trong vòng 12 giờ sau khi tạo không bị tính. Truy vấn tới zone public trong thời gian đó vẫn tính (không đáng kể).

**9. Canary bằng weighted DNS.**
DNS chia theo truy vấn của **resolver**, và câu trả lời bị cache. Một resolver lớn trả cùng một đáp án cho rất nhiều người → tỷ lệ thực tế lệch xa trọng số. Rollback phải chờ hết TTL. Load balancer chia theo **từng request** và đổi trọng số có hiệu lực ngay.

**10. Health check Route 53 thấy gì mà metric EC2 không thấy.**
Kiểm tra từ bên ngoài, theo đúng đường người dùng đi: nginx chết, app trả lỗi, security group bị sửa, public IP đổi. Metric EC2 chỉ thấy máy ảo (CPU, mạng, status check) — máy vẫn "khỏe" trong mọi trường hợp trên.

**11. Vì sao không dùng ACM trực tiếp trên nginx.**
Chứng chỉ ACM public thường (miễn phí) **không lấy được private key** — chỉ gắn được vào dịch vụ tích hợp (ALB, CloudFront…). Loại exportable lấy được key nhưng **có phí hằng tháng** và phải tự export lại mỗi lần gia hạn. Taskhub v3 không có ALB, nên dùng Let's Encrypt trên nginx (miễn phí, cần tự động gia hạn).

**12. Public IP đổi — hai cách.**
(1) Elastic IP: IP cố định, 0,005 USD/giờ, tính cả khi instance stop (idle). (2) Script cập nhật record A mỗi lần start (UPSERT, TTL ngắn): gần như miễn phí, thêm một bước tự động hóa.

**13. Dangling DNS.**
Record vẫn trỏ vào tài nguyên đã bị bạn giải phóng (IP, bucket, hosted zone đã xóa…). IP đó có thể được cấp cho người khác → tên miền của bạn hiển thị nội dung của họ (lừa đảo, đánh cắp cookie theo tên miền). Phòng: xóa record **trước** khi giải phóng tài nguyên; rà soát định kỳ.

**14. SERVFAIL vs NXDOMAIN.**
`NXDOMAIN`: authoritative trả lời chắc chắn rằng tên **không tồn tại**. `SERVFAIL`: resolver **không lấy được** câu trả lời hợp lệ (authoritative không trả lời, ủy quyền hỏng, DNSSEC lỗi) — tên có thể tồn tại.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Vẽ chuỗi phân giải

Mẫu (minh họa, tên miền giả định `vidu.vn`):

```text
.   (root)        NS a.root-servers.net …           TTL 518400
vn. (TLD)         NS <máy chủ TLD .vn> …            TTL 172800
vidu.vn.          NS ns1.<nhà-cung-cấp> …           TTL 3600–172800 (tùy cấu hình ở TLD)
vidu.vn.          A  <ip>                           TTL 300
```

Tầng dài nhất thường là root và TLD. Ảnh hưởng: khi **đổi nhà cung cấp DNS** (đổi NS ở registrar), resolver giữ bộ NS cũ tới hết TTL của record NS ở tầng TLD (thường 1–2 ngày). Vì vậy phải giữ cả DNS cũ và mới cùng đúng record trong thời gian chuyển.

### Bài 2 — Thiết kế DNS cho taskhub

| Tên | Loại | Giá trị | TTL | Lý do |
|---|---|---|---|---|
| `taskhub.example.com` | A | `<public IP EC2>` | 60 | IP tự gán đổi khi stop/start → TTL ngắn để cập nhật nhanh |
| `www.example.com` | CNAME | `taskhub.example.com` | 300 | Cùng đích; đổi IP chỉ cần sửa một record A |
| `example.com` | CAA | `0 issue "letsencrypt.org"` | 3600 | Chỉ Let's Encrypt được cấp chứng chỉ cho tên miền; hiếm khi đổi |

(Nếu `www` dùng alias tới record A cùng zone thay vì CNAME cũng đúng — truy vấn alias trong zone miễn phí. Không đặt CNAME ở `example.com`.)

### Bài 3 — `scripts/update-dns.sh`

```bash
#!/usr/bin/env bash
# Cập nhật record A trỏ về public IP hiện tại của một EC2 instance.
# Dùng: update-dns.sh <instance-id> <hosted-zone-id> <record-name>
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Dùng: $0 <instance-id> <hosted-zone-id> <record-name>" >&2
  exit 2
fi
instance_id="$1" zone_id="$2" record="$3"

ip="$(aws ec2 describe-instances --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)"
if [[ -z "$ip" || "$ip" == "None" ]]; then
  echo "Instance $instance_id không có public IP (đang stop?)" >&2
  exit 1
fi

batch="$(mktemp)"
trap 'rm -f "$batch"' EXIT
cat > "$batch" <<EOF
{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{
  "Name":"${record}","Type":"A","TTL":60,
  "ResourceRecords":[{"Value":"${ip}"}]}}]}
EOF

change_id="$(aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" \
             --change-batch "file://${batch}" --query 'ChangeInfo.Id' --output text)"
aws route53 wait resource-record-sets-changed --id "$change_id"
echo "${record} -> ${ip} (INSYNC)"
```

Điểm chấm: `set -euo pipefail`; kiểm tra số tham số; xử lý `None` (AWS CLI in `None` khi giá trị rỗng ở `--output text`); file tạm có `trap` xóa; chờ `INSYNC` (`aws route53 wait resource-record-sets-changed` hoặc vòng lặp `get-change`). Script cần quyền `ec2:DescribeInstances`, `route53:ChangeResourceRecordSets` (trên đúng zone), `route53:GetChange`.

### Bài 4 — "Tôi vẫn NXDOMAIN"

Đồng nghiệp đã truy cập `api.example.com` **trước** khi record tồn tại → resolver của họ nhận `NXDOMAIN` và **cache câu trả lời phủ định** trong khoảng thời gian do SOA của zone quy định (negative caching). Máy bạn dùng resolver khác (hoặc chưa từng hỏi) nên thấy record ngay.

Chứng minh:

```bash
dig api.example.com                                   # trên máy đồng nghiệp: NXDOMAIN, AUTHORITY có SOA
dig +norecurse @ns-123.awsdns-45.com api.example.com  # authoritative: đã có A → zone đúng
dig @1.1.1.1 api.example.com                          # resolver khác: có A
```

Sửa: chờ hết thời gian cache phủ định, hoặc đổi resolver/xóa cache cục bộ. Bài học: đừng "thử" một tên trước khi tạo record.

### Bài 5 — 🟨 Let's Encrypt cho nginx trong container (thiết kế)

- **Volume chung:** `certbot-www` (webroot) và `letsencrypt` (chứa `/etc/letsencrypt`), gắn vào cả nginx (chỉ đọc) và container `certbot`.
- **nginx, server 80:** `location /.well-known/acme-challenge/ { root /var/www/certbot; }` và chuyển hướng phần còn lại sang HTTPS (sau khi đã có chứng chỉ).
- **nginx, server 443:** `listen 443 ssl;` với `ssl_certificate /etc/letsencrypt/live/<tên-miền>/fullchain.pem;` và `ssl_certificate_key .../privkey.pem;`, `proxy_pass http://taskhub:8080;` như cũ.
- **Cấp lần đầu:** chạy container certbot với `certonly --webroot -w /var/www/certbot -d taskhub.example.com` (cổng 80 phải mở và record A đã trỏ đúng).
- **Gia hạn:** lịch chạy định kỳ (cron hoặc systemd timer — [Linux 08](../../01-LINUX/08-cron-scheduling.md)) gọi `certbot renew`, rồi `docker compose exec nginx nginx -s reload`. Thử bằng `certbot renew --dry-run`.
- **Security group:** mở **443** (và giữ **80** cho HTTP-01 challenge và chuyển hướng).
- **Vì sao phải tự động hóa:** Let's Encrypt rút thời hạn chứng chỉ từ 90 ngày xuống 64 ngày (mặc định từ 10/02/2027) rồi 45 ngày (16/02/2028). Gia hạn tay sẽ quên và chứng chỉ hết hạn → trình duyệt chặn truy cập.

---

## Phần C — Câu hỏi ❓ trong bài thực hành

- **4 NS ở 4 TLD khác nhau:** như câu A2 — tránh một điểm hỏng chung.
- **Bước 5 — vì sao NXDOMAIN quan trọng khi vừa tạo record:** câu trả lời "không tồn tại" cũng được cache (thời gian theo SOA) → ai đã hỏi trước khi record tồn tại sẽ tiếp tục thấy NXDOMAIN một lúc (xem bài 4).
