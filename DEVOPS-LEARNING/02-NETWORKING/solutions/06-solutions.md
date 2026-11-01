# Lời giải — Bài 06: HTTP, HTTPS và TLS

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [06-http-https-tls.md](../06-http-https-tls.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Từ khi gõ URL đến khi có response.**
(1) Trình duyệt/curl tách URL: giao thức `https`, tên miền, path `/api/tasks`. (2) **DNS** phân giải tên miền ra IP — [bài 03](../03-dns-dhcp.md). (3) Hệ điều hành chọn đường đi, gói tin đi qua gateway, có thể qua NAT — [bài 04](../04-routing-nat-switching.md). (4) **TCP** bắt tay 3 bước tới IP:443, qua các lớp firewall — [bài 05](../05-tcp-udp-ports-firewall.md). (5) **TLS** handshake: SNI, chứng chỉ, kiểm tra chain/tên/hạn, tạo khóa phiên — bài 06. (6) **HTTP** request được gửi trong đường hầm TLS; thường đi qua reverse proxy/load balancer tới app — [bài 07](../07-load-balancing-reverse-proxy.md). (7) App xử lý (có thể gọi DB), trả response với status code, header, body.

**2. Các phần của request.**
Dòng request (method, path kèm query string, version), các header, **một dòng trống**, body (tùy chọn). Dòng trống báo hiệu "hết phần header": server biết từ đây trở đi là body (độ dài body xác định bằng `Content-Length` hoặc cơ chế chia khúc).

**3. Stateless và load balancer.**
Server không tự nhớ các request trước; mỗi request phải mang đủ thông tin (cookie, token). Vì vậy request nào cũng có thể được xử lý bởi **bất kỳ** bản sao app nào → load balancer chia request tự do giữa nhiều instance, thêm/bớt instance dễ dàng. Điều kiện: app không giữ phiên đăng nhập trong RAM của riêng nó (hoặc phải dùng sticky session — kém linh hoạt hơn).

**4. Idempotent và retry POST.**
Idempotent: gọi một hay nhiều lần cho cùng một kết quả trên server (GET, PUT, DELETE). POST thường **không** idempotent: mỗi lần gọi tạo một bản ghi mới. Nếu request POST đã được app xử lý nhưng response bị timeout trên đường về, proxy tự gửi lại → tạo **trùng** (hai đơn hàng, trừ tiền hai lần).

**5. 401 vs 403.**
401: chưa xác thực — server không biết bạn là ai (thiếu/sai/hết hạn token). 403: đã xác thực hoặc server không cần biết — nhưng bạn không có quyền với tài nguyên này.

**6. 500/502/503/504.**

| Mã | Ai sinh | Đọc log ở đâu trước |
|---|---|---|
| 500 | App (exception không xử lý) | Log app, tìm stack trace |
| 502 | Proxy/LB: không nhận được phản hồi hợp lệ từ app (app chết, refused, đóng kết nối) | Error log của proxy → rồi trạng thái app (`ss -tlnp`, `systemctl status`) |
| 503 | Proxy/LB (không có backend khỏe, quá tải, bảo trì) hoặc app | Health check của LB, số instance khỏe, log app |
| 504 | Proxy/LB: chờ app quá lâu | Error log proxy (`upstream timed out`) → hiệu năng app/DB, cấu hình timeout |

**7. Một IP, nhiều website.**
Tầng HTTP: header **`Host`** cho server biết client muốn site nào (virtual host). Tầng TLS: **SNI** trong ClientHello — cần thiết vì server phải chọn **chứng chỉ** trước khi giải mã được request (lúc đó chưa đọc được `Host`).

**8. Ba đảm bảo của HTTPS.**
Bảo mật (mã hóa), toàn vẹn (không bị sửa), xác thực (đúng là server thật). Mã hóa mà không xác thực: kẻ đứng giữa chỉ cần đóng vai server, nhận dữ liệu đã giải mã rồi chuyển tiếp — bạn mã hóa rất an toàn nhưng **với kẻ tấn công**.

**9. Ba tiêu chí kiểm tra chứng chỉ.**
(1) Chuỗi tin cậy dẫn tới một Root CA có trong root store của client. (2) Tên miền đang truy cập nằm trong SAN. (3) Thời điểm hiện tại nằm trong khoảng `notBefore`–`notAfter`.

**10. Intermediate.**
CA trung gian được root ký, dùng để ký chứng chỉ cho website — root được giữ offline cho an toàn. Server phải gửi kèm intermediate. Trình duyệt hay "che" lỗi thiếu intermediate vì nó có thể đã cache intermediate từ các site khác hoặc tự tải về theo thông tin trong chứng chỉ; curl, Java, nhiều thư viện không làm vậy nên báo lỗi.

**11. Không gửi root.**
Niềm tin bắt nguồn từ root store **có sẵn** trên client. Root gửi qua mạng không chứng minh được gì (ai cũng có thể tự tạo một "root"); client chỉ tin root mà nó đã có. Gửi root chỉ tốn băng thông.

**12. `curl -k`.**
Dùng tạm thời khi chẩn đoán để biết lỗi có phải **chỉ** do chứng chỉ không. Để trong script là tắt xác thực server → mở đường cho man-in-the-middle, và che mất cảnh báo khi chứng chỉ hết hạn. Cách đúng: `--cacert <ca.crt>` (chỉ tin đúng CA/chứng chỉ đó) hoặc thêm CA nội bộ vào root store/truststore.

**13. `-H "Host"` vs `--resolve`.**
`-H "Host: x"` chỉ đổi header HTTP; kết nối và SNI vẫn dựa trên URL (thường là IP) → với HTTPS, chứng chỉ sẽ không khớp tên. `--resolve x:443:IP` đổi kết quả DNS cho tên `x` → URL vẫn là `https://x/`, nên `Host`, SNI và kiểm tra SAN đều đúng như người dùng thật.

**14. `ttfb=3.1`, `tls=0.09`.**
DNS + TCP + TLS xong trong 0,09 giây — mạng ổn. Khoảng 3 giây còn lại là thời gian từ khi gửi request tới khi nhận byte đầu tiên → phía server (app, DB, dịch vụ app gọi tới) xử lý chậm.

**15. `X-Forwarded-Proto`.**
Proxy kết thúc TLS rồi gửi HTTP thường cho app. Nếu không có header này, app tưởng người dùng truy cập bằng HTTP: tạo link `http://...`, đặt cookie thiếu cờ `Secure`, hoặc redirect sang HTTPS → vòng lặp redirect vô tận.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — `cert-check.sh`

```bash
#!/usr/bin/env bash
# cert-check.sh — in hạn chứng chỉ TLS và cảnh báo khi sắp hết hạn
# Dùng: WARN_DAYS=30 ./cert-check.sh github.com expired.badssl.com
set -uo pipefail     # không dùng -e: muốn kiểm tra hết mọi tên miền dù một tên miền lỗi

WARN_DAYS="${WARN_DAYS:-21}"
now=$(date +%s)
status=0

if (( $# == 0 )); then
  echo "Dùng: $0 <tên-miền>..." >&2
  exit 2
fi

for host in "$@"; do
  end=$(timeout 10 openssl s_client -connect "${host}:443" -servername "$host" </dev/null 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

  if [[ -z "$end" ]]; then
    echo "ERROR $host: không lấy được chứng chỉ"
    status=2
    continue
  fi

  days=$(( ( $(date -d "$end" +%s) - now ) / 86400 ))
  if (( days < WARN_DAYS )); then
    echo "WARN  $host: hết hạn $end (còn $days ngày)"
    (( status == 0 )) && status=1
  else
    echo "OK    $host: hết hạn $end (còn $days ngày)"
  fi
done

exit "$status"
```

Kết quả minh họa:

```text
OK    github.com: hết hạn Feb  5 23:59:59 2027 GMT (còn 97 ngày)
WARN  expired.badssl.com: hết hạn Apr 12 23:59:59 2015 GMT (còn -4220 ngày)
```

Điểm đáng chú ý:
- `openssl s_client` **vẫn in chứng chỉ** dù xác minh thất bại → lấy được ngày hết hạn của cả chứng chỉ đã hết hạn.
- `-servername` bắt buộc để nhận đúng chứng chỉ khi server phục vụ nhiều site.
- `timeout 10` tránh treo script khi host bị chặn (timeout ở [bài 05](../05-tcp-udp-ports-firewall.md)).
- Phiên bản nâng cao: `openssl x509 -checkend $(( WARN_DAYS * 86400 ))` trả exit code trực tiếp, khỏi tính ngày.
- Script này chạy bằng cron hằng ngày ([Linux bài 08](../../01-LINUX/08-cron-scheduling.md)) đã là một hệ thống giám sát chứng chỉ đơn giản. Module 08 sẽ làm việc này bằng Prometheus.

### Bài 2 — Đọc response

**(a) `301` + `Server: nginx` + `Location: https://...`** — Nginx đang chuyển mọi request HTTP sang HTTPS. Hệ thống có Nginx đứng trước, có cấu hình chứng chỉ. Đây là cấu hình **đúng**, mong muốn.

**(b) `502` + `Server: nginx/1.24.0 (Ubuntu)`** — response do **chính Nginx** sinh ra (không phải app), Nginx bản Ubuntu 24.04 cài từ apt. Nginx không nhận được phản hồi hợp lệ từ upstream: app chết, sai port, app nghe `127.0.0.1` trong khi Nginx gọi IP khác… Việc tiếp: `tail /var/log/nginx/error.log`, `sudo ss -tlnp`. Phụ: header `Server` lộ phiên bản Nginx — nên tắt (`server_tokens off`) để không giúp kẻ tấn công biết phiên bản (Module 10).

**(c) `HTTP/2 403` + `server: AmazonS3` + XML** — request đi thẳng tới (hoặc qua CloudFront tới) **S3**. 403 từ S3 thường là: bucket/object không công khai, bucket policy chặn, hoặc **object không tồn tại** mà người gọi không có quyền liệt kê bucket (S3 trả 403 thay vì 404 để không tiết lộ object có tồn tại hay không). Body XML chứa mã lỗi chi tiết (`AccessDenied`). Module 06 sẽ học.

**(d) `503` + `Server: awselb/2.0`** — response do **AWS Application Load Balancer** sinh ra. 503 ở ALB thường nghĩa là không có target khỏe nào trong target group (mọi instance fail health check, hoặc chưa đăng ký target). Việc tiếp: xem trạng thái health check của target group, log app trên instance.

Bài học: header `Server` cho biết **lớp nào** sinh ra response — chìa khóa để biết nên mở log ở đâu.

### Bài 3 — Healthcheck bằng curl

```bash
check_url() {
  local url="$1"
  local code rc
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url")
  rc=$?                                  # exit code của curl
  if (( rc != 0 )); then
    echo "FAIL $url: curl exit $rc" >&2  # 6 DNS, 7 kết nối, 28 timeout, 35/60 TLS
    return 1
  fi
  if [[ "$code" == 2* ]]; then
    echo "OK   $url: HTTP $code"
    return 0
  fi
  echo "FAIL $url: HTTP $code" >&2
  return 1
}

check_url https://github.com                     # OK   HTTP 200
check_url https://github.com/khong-ton-tai-xyz   # FAIL HTTP 404
check_url http://127.0.0.1:1                     # FAIL curl exit 7
```

Hai cái bẫy:
- Viết `local code=$(curl ...)` trên **cùng một dòng** thì `$?` là exit code của lệnh `local` (luôn 0), không phải của curl. Phải khai báo `local` trước rồi mới gán — đúng như trên.
- `curl -f`/`--fail` cũng trả exit code khác 0 (22) khi status ≥ 400, nhưng **coi 3xx là thành công**. Muốn đúng "chỉ 2xx" thì phải kiểm tra `http_code` như trên.

Với Docker `HEALTHCHECK` (Module 04) chỉ cần exit code: `curl -fsS --max-time 5 http://localhost:8080/actuator/health || exit 1`.

### Bài 4 — Chuỗi redirect

```bash
curl -sIL http://github.com | grep -iE '^(HTTP|location)'
curl -sIL http://www.github.com | grep -iE '^(HTTP|location)'
```

Kết quả minh họa (GitHub có thể thay đổi cấu hình):

```text
HTTP/1.1 301 Moved Permanently
Location: https://github.com/
HTTP/2 200

HTTP/1.1 301 Moved Permanently
Location: https://www.github.com/
HTTP/2 301
location: https://github.com/
HTTP/2 200
```

Mỗi bước redirect là thêm một vòng request (với HTTPS mới: thêm cả TCP + TLS) → chậm hơn, nhất là trên mạng di động.

Thiết kế tối ưu cho `taskhub.example.com` — **mọi** điểm vào chỉ cần **tối đa một** redirect, thẳng tới đích cuối cùng:

| Người dùng gõ | Response | Số bước |
|---|---|---|
| `http://taskhub.example.com/x` | `301 → https://taskhub.example.com/x` | 1 |
| `http://www.taskhub.example.com/x` | `301 → https://taskhub.example.com/x` (thẳng, không qua `https://www`) | 1 |
| `https://www.taskhub.example.com/x` | `301 → https://taskhub.example.com/x` | 1 |
| `https://taskhub.example.com/x` | `200` | 0 |

Điều kiện: chứng chỉ phải có **cả** `www.taskhub.example.com` trong SAN — nếu không, người dùng gõ `https://www...` sẽ gặp lỗi chứng chỉ **trước khi** kịp nhận redirect. Nhớ giữ nguyên path (`/x`) khi redirect.

### Bài 5 — SNI

```bash
IP=$(getent hosts github.com | awk '{print $1; exit}')
openssl s_client -connect "$IP:443" </dev/null 2>/dev/null | openssl x509 -noout -subject
openssl s_client -connect "$IP:443" -servername github.com </dev/null 2>/dev/null | openssl x509 -noout -subject
```

- Khi `-connect` là **IP**, OpenSSL không tự gửi SNI (SNI chỉ chứa tên miền). Server không biết bạn muốn site nào nên trả **chứng chỉ mặc định** — có thể là chứng chỉ khác, có thể vẫn là `github.com` (tùy cách GitHub cấu hình), hoặc handshake thất bại.
- Có `-servername github.com` → server chọn đúng chứng chỉ cho `github.com`.
- ⚠️ `Verify return code: 0 (ok)` của `s_client` mặc định chỉ kiểm tra **chuỗi tin cậy**, **không** kiểm tra tên miền có khớp SAN không. Vì vậy có thể thấy `ok` dù chứng chỉ thuộc tên miền khác. Muốn kiểm tra cả tên: thêm `-verify_hostname github.com`. curl thì luôn kiểm tra tên.

Liên hệ: một IP phục vụ nhiều website HTTPS **cần SNI** để chọn chứng chỉ, vì việc chọn chứng chỉ xảy ra trước khi server đọc được header `Host` (lúc đó dữ liệu chưa được giải mã). Đây là cách các load balancer và CDN phục vụ hàng nghìn tên miền trên cùng một dải IP.
