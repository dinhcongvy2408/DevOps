# Lời giải — Bài 07: Load balancing và reverse proxy

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [07-load-balancing-reverse-proxy.md](../07-load-balancing-reverse-proxy.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Forward vs reverse proxy?**
Forward proxy đứng phía client, client chủ động cấu hình dùng nó; nó giấu client khỏi server (server thấy IP proxy). Reverse proxy đứng phía server, client không biết nó tồn tại; nó giấu server/backend khỏi client (client chỉ thấy proxy).

**2. Bốn lý do đặt Nginx trước Spring Boot?**
Bất kỳ 4 trong: TLS termination tập trung; định tuyến theo đường dẫn/tên miền qua một port 443; phục vụ file tĩnh hiệu quả; chỉ mở 80/443 ra ngoài, ẩn port app; giới hạn kích thước request, chặn đường dẫn nhạy cảm như `/actuator`; gom access log; mở port < 1024 mà app không cần quyền root; load balancing nhiều instance.

**3. Vì sao log app chỉ thấy `127.0.0.1`? Sửa thế nào?**
Proxy mở kết nối TCP thứ hai tới app, nên IP nguồn mà app thấy là IP của proxy. Sửa: proxy gửi `X-Real-IP $remote_addr` và `X-Forwarded-For $proxy_add_x_forwarded_for`; app được cấu hình để đọc IP từ header này — và **chỉ tin** header khi request đến từ proxy đáng tin.

**4. `/api/users` với hai kiểu `proxy_pass`?**
- `proxy_pass http://app:8080;` (không URI) → app nhận `/api/users`.
- `proxy_pass http://app:8080/;` (URI là `/`) → phần khớp location `/api/` bị thay bằng `/` → app nhận `/users`.

**5. Thiếu `X-Forwarded-Proto`?**
App nghĩ request là HTTP (vì kết nối proxy → app là HTTP). Khi app tạo URL tuyệt đối hoặc redirect (ví dụ sau đăng nhập), nó dùng `http://` → trình duyệt bị đưa về HTTP (cảnh báo không an toàn, cookie `Secure` không gửi), hoặc lặp redirect vô hạn nếu proxy lại ép HTTP → HTTPS.

**6. 502 vs 504?**
502: proxy không nhận được phản hồi hợp lệ từ upstream — thường là kết nối bị từ chối (app chết, sai port, sai bind address). Kiểm tra đầu tiên: `error.log` (errno 111?) rồi `ss -tlnp` xem app có nghe đúng chỗ không.
504: proxy chờ upstream quá timeout — app treo/chậm, hoặc gói tới upstream bị firewall nuốt. Kiểm tra: `error.log` (`upstream timed out ... while reading response header` hay `while connecting`), đo thời gian gọi thẳng app, kiểm tra firewall.

**7. Reload vs restart; vì sao `nginx -t` trước?**
Reload: master đọc lại cấu hình, sinh worker mới, worker cũ xử lý nốt request — không rớt kết nối; cấu hình sai thì master giữ cấu hình cũ. Restart: dừng hẳn rồi chạy lại — rớt kết nối, và nếu cấu hình sai thì Nginx không lên lại → site sập. `nginx -t` phát hiện lỗi cú pháp/tham chiếu file trước khi áp dụng.

**8. Nginx chọn server block thế nào?**
Lọc theo địa chỉ:port trong `listen` khớp với kết nối, rồi so header `Host` với `server_name`. Không khớp → dùng block có `default_server` cho địa chỉ:port đó (không có thì block đầu tiên). Vì vậy mỗi địa chỉ:port chỉ được một `default_server`.

**9. Round robin / least_conn / ip_hash?**
Round robin (mặc định): backend giống nhau, request đồng đều. `least_conn`: request có thời gian xử lý chênh lệch nhiều (một số request dài) — tránh dồn vào server đang bận. `ip_hash`: cần cùng client về cùng server (phiên lưu trong RAM) — giải pháp tạm, nên làm app stateless.

**10. Health check bị động vs chủ động?**
Bị động: dựa vào request thật của người dùng; khi request lỗi (mặc định lỗi kết nối/timeout) thì đếm, đủ `max_fails` trong `fail_timeout` thì tạm loại server. Người dùng đầu tiên gặp lỗi có thể được thử lại sang server khác. Chủ động: proxy tự gửi request kiểm tra định kỳ, loại server **trước khi** người dùng gặp lỗi. Nginx mã nguồn mở chỉ có bị động; chủ động là của NGINX Plus (ALB, Kubernetes probe cũng là chủ động).

**11. Vì sao app nên stateless?**
Load balancer có thể gửi các request liên tiếp của cùng người dùng tới các server khác nhau. Nếu phiên lưu trong RAM của một server, người dùng mất phiên. Server có thể bị thêm/bớt bất kỳ lúc nào (auto scaling, rolling deploy). Lưu trạng thái ra ngoài (DB, Redis, token) thì mọi server tương đương nhau.

**12. L4 vs L7?**
L4 chỉ thấy IP/port, chuyển tiếp kết nối TCP/UDP, nhanh, không đọc HTTP. Ví dụ: AWS NLB, Kubernetes Service. L7 hiểu HTTP: định tuyến theo path/host/header, kết thúc TLS, thêm header. Ví dụ: AWS ALB, Kubernetes Ingress (thường do Nginx Ingress Controller thực hiện).

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Định tuyến theo đường dẫn

Backend:

```bash
cd ~/devops-lab/02-networking/lab07
mkdir -p frontend api-root/api
echo "<h1>frontend</h1>" > frontend/index.html
echo '{"tasks": []}' > api-root/api/tasks.json
python3 -m http.server 8081 --bind 127.0.0.1 --directory frontend &
python3 -m http.server 8082 --bind 127.0.0.1 --directory api-root &
```

Server block:

```nginx
server {
    listen 80 default_server;
    server_name _;

    location /actuator/ {
        deny all;                              # trả 403
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8082;      # không có "/" cuối → app nhận nguyên /api/...
        proxy_set_header Host            $host;
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host            $host;
    }
}
```

Kết quả mong đợi:

| Lệnh | Mã |
|---|---|
| `curl -s -o /dev/null -w "%{http_code}\n" http://localhost/` | 200 (frontend) |
| `curl -s http://localhost/api/tasks.json` | `{"tasks": []}` |
| `curl -s -o /dev/null -w "%{http_code}\n" http://localhost/actuator/health` | 403 |
| `curl -s -o /dev/null -w "%{http_code}\n" http://localhost/api/khong-co` | 404 (từ backend API) |

Lưu ý: `/actuator/health` khớp `location /actuator/` (tiền tố dài hơn `/`) nên bị chặn trước khi tới backend.

### Bài 2 — Header chuyển tiếp

(a) Có đủ 4 header — backend in ra (minh họa):

```text
Host: localhost
X-Real-IP: 127.0.0.1
X-Forwarded-For: 127.0.0.1
X-Forwarded-Proto: http
Connection: close
User-Agent: curl/8.5.0
Accept: */*
```

(b) Xóa hết 4 dòng:

```text
Host: 127.0.0.1:8080
Connection: close
User-Agent: curl/8.5.0
Accept: */*
```

`Host` thành `127.0.0.1:8080` vì mặc định Nginx gửi `Host: $proxy_host` — tức host:port trong `proxy_pass`. Không còn thông tin IP client và scheme.

Gửi `-H "X-Forwarded-For: 1.2.3.4"` ở cấu hình (a) → backend nhận `X-Forwarded-For: 1.2.3.4, 127.0.0.1` vì `$proxy_add_x_forwarded_for` **nối thêm** IP thật vào giá trị client gửi. Kết luận: phần đầu của `X-Forwarded-For` do **client tự khai** và có thể giả. App chỉ được tin phần do proxy đáng tin thêm vào (hoặc dùng `X-Real-IP` do proxy đặt). Đây là lý do Spring Boot có cấu hình riêng về proxy đáng tin.

### Bài 3 — Tự tạo 504

Backend chậm:

```python
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(10)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"slow but ok\n")

HTTPServer(("127.0.0.1", 8080), H).serve_forever()
```

Cấu hình:

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_read_timeout 3s;
}
location /slow/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_read_timeout 15s;
}
```

```bash
curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://localhost/
# 504 3.01
curl -s -o /dev/null -w "%{http_code} %{time_total}\n" http://localhost/slow/
# 200 10.01
```

Error log:

```text
... [error] ...: *12 upstream timed out (110: Connection timed out) while reading response header from upstream, client: 127.0.0.1, server: _, request: "GET / HTTP/1.1", upstream: "http://127.0.0.1:8080/", host: "localhost"
```

`while reading response header` → kết nối **đã thành công**, app chậm trả lời. So với timeout `while connecting` → không kết nối được (thường do firewall nuốt gói).

Lưu ý: với một upstream là địa chỉ đơn (không phải nhóm nhiều server), Nginx không có server khác để thử lại. Server python đơn luồng xử lý tuần tự, nên nếu gửi nhiều request cùng lúc, request sau phải chờ request trước — thời gian có thể dài hơn 10 giây.

### Bài 4 — Bảo trì không gián đoạn

Quy trình với vòng lặp chạy liên tục:

1. Thêm `down` vào `server 127.0.0.1:8081 down;` → `nginx -t && reload` → mọi request về 8082, vòng lặp toàn `200`.
2. `kill` backend 8081 (hoặc "nâng cấp" nó) → vẫn toàn `200` vì Nginx không gửi request tới server `down`.
3. Khởi động lại 8081, bỏ `down`, reload → lại chia đều.

So sánh: `kill` thẳng backend 8081 khi nó không `down` → request đang được gửi tới 8081 lúc đó bị lỗi kết nối. Với cấu hình mặc định (`proxy_next_upstream error timeout`), Nginx **thử lại** sang 8082 nên người dùng thường vẫn thấy `200`, nhưng error log có dòng `connect() failed (111...)`. Request đang xử lý dở trên 8081 lúc bị kill (nếu có) sẽ lỗi thật. Với API thay đổi dữ liệu (POST), Nginx mặc định không thử lại request không lũy đẳng nếu đã gửi đi — nên "rút server ra trước khi dừng" (drain) là cách đúng. Đây là điều ALB làm tự động bằng *deregistration delay* (Module 06).

### Bài 5 — Đọc `nginx -T`

Đáp án tham khảo trên Ubuntu 24.04 (có thể khác theo phiên bản):

| Ý | Dòng bằng chứng |
|---|---|
| (a) User worker | `user www-data;` |
| (b) Số worker | `worker_processes auto;` — bằng số nhân CPU |
| (c) File include | `include /etc/nginx/modules-enabled/*.conf;`, `include /etc/nginx/mime.types;`, `include /etc/nginx/conf.d/*.conf;`, `include /etc/nginx/sites-enabled/*;` — `nginx -T` in thêm dòng `# configuration file ...` trước nội dung từng file |
| (d) Định dạng log | Không khai báo `log_format` riêng → `access_log /var/log/nginx/access.log;` dùng định dạng mặc định `combined` |
| (e) `client_max_body_size` | Không xuất hiện → dùng mặc định `1m` |

Ý (d) và (e) dạy một điều quan trọng: thứ **không thấy** trong cấu hình nghĩa là đang dùng **giá trị mặc định** — phải tra tài liệu mới biết.
