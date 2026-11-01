# Lời giải — Bài 03: DNS và DHCP

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [03-dns-dhcp.md](../03-dns-dhcp.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. DNS giải quyết vấn đề gì?**
(1) Con người nhớ tên, máy dùng IP → cần ánh xạ tên ↔ IP. (2) IP của dịch vụ thay đổi (đổi server, nhiều IP, load balancer) nhưng tên giữ nguyên → tách "tên" khỏi "vị trí". (3) Một file danh bạ chung không mở rộng được cho hàng trăm triệu tên và không ai muốn chờ tải bản cập nhật → DNS là cơ sở dữ liệu **phân tán**, mỗi chủ domain tự quản lý phần của mình, kèm cache để chịu tải.

**2. Recursive resolver vs authoritative server?**
Recursive resolver nhận câu hỏi của client, đi hỏi giùm qua root → TLD → authoritative, rồi cache kết quả. Authoritative server giữ dữ liệu gốc của một zone và chỉ trả lời về zone đó. `8.8.8.8` là recursive resolver. Route 53 hosted zone (public) là authoritative server cho domain của bạn.

**3. Phân giải `api.taskhub.example.com` không cache:**
Stub resolver hỏi recursive resolver → resolver hỏi root: "ai quản lý `.com`?" → được danh sách server TLD `.com` → hỏi TLD: "ai quản lý `example.com`?" → được NS của `example.com` → hỏi authoritative của `example.com` về `api.taskhub.example.com` → nhận record (có thể là `A`, hoặc `CNAME` cần phân giải tiếp) → resolver cache theo TTL và trả về client. (Nếu `taskhub.example.com` được **ủy quyền** sang một bộ NS riêng thì có thêm một bước hỏi NS của `taskhub.example.com` — chấp nhận nếu bạn nêu được.)

**4. A vs CNAME, CNAME ở apex:**
`A` khi bạn có IPv4 cố định (Elastic IP của EC2). `CNAME` khi đích chỉ có **tên** và IP có thể thay đổi (tên của load balancer, CDN, dịch vụ SaaS). Không đặt CNAME ở `example.com` vì apex bắt buộc có `NS` và `SOA`, mà tên đã có CNAME thì không được có record nào khác. Trên Route 53 dùng alias record để giải quyết.

**5. Kế hoạch chuyển server (TTL 86400):**
- T−2 ngày (ít nhất 24 giờ trước): hạ TTL xuống `60`. Kiểm tra bằng `dig @<authoritative> taskhub.example.com` thấy TTL mới.
- Chờ ≥ 24 giờ để mọi cache giữ TTL cũ hết hạn.
- Giờ G: đổi record sang IP mới. Kiểm tra authoritative trả IP mới, rồi kiểm tra vài resolver công cộng (`@8.8.8.8`, `@1.1.1.1`).
- Giữ server cũ chạy thêm một thời gian để những client còn cache (hoặc có cache bên trong app như JVM) không bị lỗi.
- Ổn định rồi tăng TTL trở lại (ví dụ `3600`).

**6. Các tầng cache:** cache DNS của JVM (`networkaddress.cache.ttl`); systemd-resolved trên Linux (hoặc Windows DNS Client); cache của router nhà/DNS nhà mạng hoặc resolver công cộng; một số trình duyệt cũng có cache riêng. Chỉ cần nêu đúng 3.

**7. Thứ tự tra cứu trên Linux:** quy định bởi dòng `hosts:` trong `/etc/nsswitch.conf`, thường `files dns` → `/etc/hosts` trước, rồi tới DNS server khai báo trong `/etc/resolv.conf`.

**8. `dig` vs `getent hosts`:** `dig` hỏi thẳng DNS server, bỏ qua `/etc/hosts` và `nsswitch`. `getent hosts` dùng cùng cơ chế với ứng dụng (`getaddrinfo` + `nsswitch`) nên tính cả `/etc/hosts`. Muốn biết ứng dụng thấy gì → `getent hosts` (chạy đúng nơi ứng dụng chạy).

**9.** `NXDOMAIN`: tên **không tồn tại**. `SERVFAIL`: resolver **không lấy được** câu trả lời hợp lệ (authoritative hỏng, delegation sai, lỗi DNSSEC) — không nói gì về việc tên có tồn tại hay không. `NOERROR` + `ANSWER: 0`: tên **tồn tại** nhưng **không có record loại bạn hỏi** (ví dụ có `A` nhưng không có `AAAA`).

**10.** `Name or service not known` → DNS đã trả lời "không có": kiểm tra chính tả, record đã tạo chưa, có đúng zone không. `Temporary failure in name resolution` → không hỏi được DNS server: kiểm tra kết nối mạng, `/etc/resolv.conf`, firewall chặn port 53, VPN.

**11.** UDP port 53 cho hầu hết truy vấn; TCP port 53 khi câu trả lời lớn hoặc đồng bộ zone. Chặn port 53 → mọi thứ dùng tên miền đều lỗi (cài package, gọi API, kết nối DB theo tên) dù kết nối theo IP vẫn được — triệu chứng rất dễ gây nhầm lẫn.

**12.** DHCP cấp IP, subnet mask, default gateway, DNS server, thời hạn lease (và có thể thêm domain name, NTP…). DORA: Discover → Offer → Request → Acknowledge. Bước đầu phải broadcast vì máy **chưa có IP** và **chưa biết** DHCP server ở đâu.

**13.** WSL tự sinh `/etc/resolv.conf` (`generateResolvConf=true` mặc định trong `/etc/wsl.conf`) và chuyển truy vấn DNS sang Windows (DNS tunneling hoặc DNS proxy). WSL không nhất thiết dùng systemd-resolved nên có thể không thấy `127.0.0.53`.

**14.** `10.0.0.2` (địa chỉ thứ 2 của dải VPC) và `169.254.169.253`. Cấu hình DNS server cho instance qua **DHCP option set** của VPC (mặc định `AmazonProvidedDNS`), cùng hai thuộc tính VPC `enableDnsSupport`/`enableDnsHostnames`.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Chân dung DNS

Không có đáp án duy nhất. Các lệnh cần dùng:

```bash
D=example.vn                      # thay bằng domain bạn chọn
dig +noall +answer "$D" A
dig +noall +answer "$D" AAAA
dig +noall +answer "www.$D"
dig +short "$D" MX
dig +short "$D" NS
NS=$(dig +short "$D" NS | head -1)
dig @"$NS" "$D" A | grep -E 'flags|ANSWER SECTION' -A1
```

Đạt khi: bảng đủ các loại record, có TTL, và chỉ ra được cờ `aa` **có** trong câu trả lời từ authoritative (hỏi `@$NS`) nhưng **không có** khi hỏi resolver thường. Nếu TTL từ authoritative luôn là giá trị "tròn" (ví dụ đúng 300) còn từ resolver là số lẻ đang giảm dần → bạn đã hiểu cache.

### Bài 2 — Đọc output NXDOMAIN

- `status: NXDOMAIN`: tên `api.taskhub.example.com` **không tồn tại**.
- `flags: qr rd ra`: là câu trả lời, có yêu cầu và hỗ trợ đệ quy; không có `aa` → đến từ resolver (WSL).
- `ANSWER: 0, AUTHORITY: 1`: không có câu trả lời; phần AUTHORITY chứa SOA của zone `example.com` → cho biết zone nào "có thẩm quyền" nói rằng tên không tồn tại.
- SOA: server chính `ns-1.example.com.`, email quản trị `admin@example.com` (dấu chấm đầu thay cho `@`), serial `2026103101`, … và số cuối `300` liên quan tới thời gian **cache phủ định** (NXDOMAIN này có thể bị cache khoảng tới 300 giây; TTL 900 của chính record SOA cũng giới hạn thời gian này).
- `SERVER`: resolver của WSL trả lời.

Làm gì tiếp: kiểm tra chính tả; hỏi thẳng authoritative `dig @<NS của example.com> api.taskhub.example.com` để xác nhận record thật sự chưa có hay chỉ là cache phủ định; nếu vừa tạo record thì chờ tối đa thời gian negative cache; kiểm tra có phải `taskhub` được ủy quyền sang zone khác không (`dig NS taskhub.example.com`).

### Bài 3 — Runbook chuyển server

Mẫu đạt yêu cầu:

| Thời điểm | Việc | Kiểm tra |
|---|---|---|
| Thứ Sáu 18:00 (≥ 1 giờ trước, nên làm sớm hơn) | Hạ TTL `taskhub.example.com` từ 3600 → 60 | `dig @<ns> taskhub.example.com` thấy TTL 60 |
| Thứ Sáu – thứ Bảy | Kiểm tra server mới **không cần DNS**: thêm `203.0.113.50 taskhub.example.com` vào `/etc/hosts` của riêng bạn, hoặc `curl --resolve taskhub.example.com:443:203.0.113.50 https://taskhub.example.com/actuator/health` | Trả `200`, đúng phiên bản, chứng chỉ hợp lệ cho tên miền. **Xóa dòng `/etc/hosts` sau khi thử** |
| Thứ Bảy 20:00 | Đổi record `A` → `203.0.113.50` | `dig @<ns>` thấy IP mới; `dig @8.8.8.8`, `@1.1.1.1` thấy IP mới sau ≤ 60 giây |
| 20:00–20:30 | Theo dõi log, lỗi, lưu lượng của server mới; server cũ vẫn chạy | Tỉ lệ lỗi không tăng; lưu lượng trên server cũ giảm dần về 0 |
| Tiêu chí rollback | Lỗi 5xx tăng rõ rệt, health check thất bại, chức năng chính hỏng | Đổi record về `203.0.113.10` — vì TTL 60, rollback có hiệu lực trong khoảng 1 phút |
| Chủ nhật | Tăng TTL trở lại 3600; lên lịch tắt server cũ sau vài ngày | — |

Ý quan trọng: TTL 3600 thì phải hạ **ít nhất 1 giờ** trước giờ chuyển; nên làm sớm hơn để dư thời gian.

### Bài 4 — "Chỉ máy tôi bị"

| Nguyên nhân | Kiểm chứng |
|---|---|
| Dòng cũ trong `/etc/hosts` (hoặc `C:\Windows\System32\drivers\etc\hosts`) | `getent hosts staging.taskhub.example.com` khác `dig +short`; `grep staging /etc/hosts` |
| Cache DNS ở máy/trình duyệt còn IP cũ | `dig` (bỏ qua cache OS) cho IP mới mà trình duyệt vẫn ra cũ; xóa cache (Windows: `ipconfig /flushdns`), mở cửa sổ ẩn danh |
| Máy dùng resolver khác (VPN công ty, DNS riêng) còn cache cũ | So `dig staging...` với `dig @8.8.8.8 staging...`; xem `resolv.conf`/`ipconfig /all` |
| Cache HTTP / CDN / service worker của trình duyệt (không phải DNS!) | `curl -sI https://staging...` từ máy đó; xem header; thử trình duyệt khác |
| Proxy công ty | Kiểm tra cấu hình proxy (`env | grep -i proxy`, cài đặt proxy của Windows) |

Đạt khi có ≥ 4 nguyên nhân hợp lý kèm lệnh kiểm tra. Điểm cộng nếu nhận ra rằng **không phải mọi "ra trang cũ" đều do DNS**.

### Bài 5 — `check-dns.sh`

```bash
#!/usr/bin/env bash
# check-dns.sh — so sánh IP ứng dụng thấy (getent) với IP DNS trả về (dig)
set -uo pipefail

if [[ $# -eq 0 ]]; then
  echo "Cách dùng: $0 <tên-miền> [tên-miền...]" >&2
  exit 2
fi

status=0
for name in "$@"; do
  app_ips=$(getent ahostsv4 "$name" | awk '{print $1}' | sort -u)
  dns_ips=$(dig +short "$name" A | grep -E '^[0-9.]+$' | sort -u)

  if [[ -z "$app_ips" ]]; then
    echo "FAIL     $name: ứng dụng không phân giải được"
    status=1
    continue
  fi

  common=$(comm -12 <(echo "$app_ips") <(echo "$dns_ips"))
  if [[ -z "$common" ]]; then
    echo "MISMATCH $name: app=[$(echo $app_ips)] dns=[$(echo $dns_ips)]"
  else
    echo "OK       $name: $(echo $app_ips)"
  fi
done
exit "$status"
```

Giải thích các điểm chính:
- `getent ahostsv4` chỉ lấy IPv4 và đi qua `nsswitch` (giống ứng dụng); `getent hosts` có thể trả IPv6 trước.
- `dig +short ... A` có thể in tên CNAME xen giữa → lọc chỉ giữ dòng là IP.
- `comm -12` in các dòng chung của hai danh sách đã sắp xếp. Không có điểm chung → `MISMATCH`.
- Không dùng `set -e` vì `getent` trả exit code `2` khi không tìm thấy — đó là tình huống ta muốn tự xử lý.
- Thử: thêm một dòng vào `/etc/hosts` như lab Bước 6 → script phải báo `MISMATCH` (nhớ xóa dòng đó sau).

### Bài 6 — Câu hỏi phỏng vấn

Câu trả lời tốt bao gồm (theo thứ tự): trình duyệt kiểm tra cache của nó → hệ điều hành kiểm tra `/etc/hosts`/hosts file và cache của mình → hỏi recursive resolver (cấu hình qua DHCP hoặc thủ công) qua UDP 53 → resolver dùng cache, nếu không có thì đi root → TLD `.com` → authoritative của `example.com` (ví dụ Route 53) → nhận record (`A`, hoặc chuỗi `CNAME`/alias) → cache theo TTL ở mỗi tầng → trả IP về trình duyệt. Điểm cộng: nhắc TTL và hệ quả khi đổi IP; nhắc rằng DNS chỉ là bước đầu, sau đó mới là TCP → TLS → HTTP (bài 05, 06).
