# 07. Load balancing và reverse proxy

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [05. TCP, UDP, port và firewall](05-tcp-udp-ports-firewall.md), [06. HTTP, HTTPS và TLS](06-http-https-tls.md), [Linux 04 — Processes & systemd](../01-LINUX/04-processes-systemd.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (Nginx 1.24 từ kho Ubuntu), `[PowerShell]` để mở trình duyệt Windows

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc log và xử lý lỗi](#12-đọc-log-và-xử-lý-lỗi)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Phân biệt **forward proxy** và **reverse proxy**, giải thích được vì sao hầu như mọi ứng dụng web đều có một reverse proxy đứng trước.
- Đọc và viết một **server block** Nginx: `listen`, `server_name`, `location`, `proxy_pass`, `proxy_set_header`.
- Tránh được cạm bẫy **dấu `/` ở cuối `proxy_pass`**.
- Giải thích được **502 Bad Gateway** và **504 Gateway Timeout** từ góc nhìn của reverse proxy, và tìm ra nguyên nhân từ `error.log`.
- Cấu hình **load balancing** trong Nginx, hiểu các thuật toán và cơ chế health check bị động.
- Phân biệt load balancer **tầng 4 (L4)** và **tầng 7 (L7)** — nền tảng để hiểu AWS NLB/ALB và Kubernetes Service/Ingress.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Trang web báo 502 Bad Gateway" | Proxy không kết nối được tới app phía sau — đọc `error.log` của proxy, không phải log của app |
| "Log của app toàn IP `127.0.0.1`, không biết người dùng thật là ai" | Proxy phải chuyển IP thật qua header `X-Forwarded-For` / `X-Real-IP` |
| "Spring Boot tạo link redirect `http://` dù người dùng vào bằng `https://`" | Thiếu header `X-Forwarded-Proto` |
| "Một server không chịu nổi tải, cần thêm server thứ hai" | Đặt load balancer phía trước, chia request |
| "Gọi API báo 404 sau khi đưa qua Nginx, gọi thẳng app thì chạy" | Cạm bẫy dấu `/` của `proxy_pass` làm sai đường dẫn |
| Dự án `taskhub` v0 | Nginx chạy trong Docker Compose làm reverse proxy cho Spring Boot |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Proxy là gì?

**Proxy** (máy chủ trung gian) là một chương trình đứng giữa client và server: nhận request từ một bên, rồi **thay mặt** gửi request mới sang bên kia.

Điểm mấu chốt: với proxy, có **hai kết nối TCP riêng biệt** — client ↔ proxy và proxy ↔ server. Server phía sau chỉ thấy kết nối từ proxy. Đây là lý do log của app thấy IP của proxy chứ không phải IP người dùng (nhớ lại TCP ở [bài 05](05-tcp-udp-ports-firewall.md)).

### 3.2. Forward proxy và reverse proxy

| | Forward proxy (proxy chiều đi) | Reverse proxy (proxy chiều về) |
|---|---|---|
| Đứng về phía | **Client** | **Server** |
| Ai cấu hình dùng nó | Người dùng/công ty cấu hình trình duyệt, máy tính | Chủ website — người dùng không biết nó tồn tại |
| Ai bị "giấu" | Client (server chỉ thấy IP proxy) | Server (client chỉ thấy proxy) |
| Ví dụ | Proxy công ty để lọc web, ra Internet | **Nginx trước Spring Boot**, AWS ALB, Cloudflare |
| DevOps gặp khi | Server trong công ty phải qua proxy mới ra Internet (biến `HTTP_PROXY`) | **Hằng ngày** |

### 3.3. Load balancer là gì?

**Load balancer** (bộ cân bằng tải) là một reverse proxy có **nhiều server phía sau** và phân chia request giữa chúng. Mục đích:

- **Chịu tải** (scalability): 1 server chịu 500 request/giây, thêm server để chịu nhiều hơn.
- **Sẵn sàng cao** (high availability): 1 server chết, các server còn lại vẫn phục vụ.
- **Triển khai không gián đoạn**: rút từng server ra để cập nhật (gặp lại ở Module 05 — rolling deployment).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Vì sao đặt reverse proxy trước ứng dụng?

Spring Boot tự chạy được web server (Tomcat nhúng) ở port 8080. Vì sao vẫn cần Nginx?

| Lý do | Giải thích |
|---|---|
| **TLS termination** (kết thúc TLS) | Nginx giữ chứng chỉ và xử lý HTTPS; app phía sau chỉ cần HTTP. Đổi/gia hạn chứng chỉ ở một chỗ |
| **Định tuyến** (routing) | `/api/` → Spring Boot, `/` → file tĩnh của frontend, `admin.example.com` → app khác — tất cả qua port 443 duy nhất |
| **Phục vụ file tĩnh** | Nginx phục vụ ảnh/CSS/JS nhanh hơn và tốn ít RAM hơn để app Java làm |
| **Ẩn backend** | Chỉ port 80/443 của Nginx mở ra Internet; port 8080 của app chỉ nghe nội bộ |
| **Bảo vệ** | Giới hạn kích thước request (`client_max_body_size`), giới hạn tốc độ, chặn đường dẫn nhạy cảm (`/actuator`) |
| **Gom log truy cập** | Một nơi ghi access log chuẩn cho mọi ứng dụng |
| **Port thấp** | Port < 1024 cần quyền root để nghe. Nginx master chạy root để mở port 80/443, worker chạy user thường; app không cần root |

### 4.2. 🟥 Nginx: kiến trúc và vị trí file trên Ubuntu

Nginx gồm một **master process** (đọc cấu hình, mở port, quản lý) và nhiều **worker process** (xử lý request). Chi tiết ở [nginx Beginner's Guide](https://nginx.org/en/docs/beginners_guide.html) — đọc phần đầu tiên, không cần chép lại.

Vị trí file khi cài từ kho Ubuntu (`apt install nginx`):

| Đường dẫn | Vai trò |
|---|---|
| `/etc/nginx/nginx.conf` | File cấu hình chính: user, số worker, khối `http` chung. Thường **không sửa** |
| `/etc/nginx/sites-available/` | Nơi **lưu** cấu hình từng site |
| `/etc/nginx/sites-enabled/` | Chứa **symlink** tới các site đang **bật** — `nginx.conf` chỉ nạp thư mục này |
| `/etc/nginx/conf.d/*.conf` | Cũng được nạp — cách tổ chức phổ biến trên Red Hat và trong image Docker `nginx` |
| `/var/log/nginx/access.log`, `error.log` | Log truy cập và log lỗi |
| `/var/www/html/` | Thư mục web mặc định |

Bật/tắt site bằng **symbolic link** — đúng thứ bạn học ở [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#44--liên-kết-mềm-và-liên-kết-cứng):

```bash
sudo ln -s /etc/nginx/sites-available/taskhub /etc/nginx/sites-enabled/taskhub   # bật
sudo rm /etc/nginx/sites-enabled/taskhub                                          # tắt (file gốc vẫn còn)
```

### 4.3. 🟥 Cấu trúc một server block

```nginx
server {                                   # một "virtual host"
    listen 80;                             # nghe port 80 trên mọi địa chỉ IPv4
    server_name taskhub.local;             # áp dụng khi header Host = taskhub.local

    location /api/ {                       # request có đường dẫn bắt đầu bằng /api/
        proxy_pass http://127.0.0.1:8080;  # chuyển tiếp tới app
    }

    location / {                           # mọi request còn lại
        root /var/www/taskhub;             # phục vụ file tĩnh từ thư mục này
    }
}
```

**Nginx chọn server block nào?** Dựa vào port trong `listen` và header `Host` của request (nhớ lại [bài 06](06-http-https-tls.md)) so với `server_name`. Không khớp `server_name` nào → dùng server block có `default_server` (hoặc block đầu tiên). Trên Ubuntu, site `default` có sẵn đang giữ `listen 80 default_server` — đây là lý do lab phải tắt nó.

**Nginx chọn location nào?** Rút gọn cho Junior:

1. Các location **tiền tố** (prefix, ví dụ `location /api/`) — Nginx nhớ lại location có **tiền tố khớp dài nhất**.
2. Sau đó kiểm tra các location **regex** (`location ~ \.png$`) theo thứ tự trong file — regex đầu tiên khớp sẽ được dùng.
3. Không regex nào khớp → dùng location tiền tố dài nhất ở bước 1.

Ví dụ với `location /` và `location /api/`: request `/api/tasks` khớp cả hai, `/api/` dài hơn → được chọn.

### 4.4. 🟥 `proxy_pass` và cạm bẫy dấu `/`

Theo tài liệu [ngx_http_proxy_module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass), có hai trường hợp:

**(a) `proxy_pass` KHÔNG có URI** (chỉ có `scheme://host:port`, không có gì sau port):

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8080;
}
```

Đường dẫn được chuyển **nguyên vẹn**: `/api/tasks` → app nhận `/api/tasks`.

**(b) `proxy_pass` CÓ URI** (có bất cứ thứ gì sau port, **kể cả một dấu `/`**):

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8080/;
}
```

Phần khớp với location (`/api/`) bị **thay** bằng URI trong `proxy_pass` (`/`): `/api/tasks` → app nhận `/tasks`.

| Cấu hình | Request | App nhận |
|---|---|---|
| `location /api/` + `proxy_pass http://app:8080;` | `/api/tasks` | `/api/tasks` |
| `location /api/` + `proxy_pass http://app:8080/;` | `/api/tasks` | `/tasks` |
| `location /api/` + `proxy_pass http://app:8080/v1/;` | `/api/tasks` | `/v1/tasks` |

**Quy tắc thực hành:** nếu app của bạn có controller tại `/api/tasks` (như `taskhub`), **không** thêm dấu `/` cuối `proxy_pass`. Chỉ dùng dạng (b) khi bạn thực sự muốn **cắt bỏ** tiền tố.

### 4.5. 🟥 Header chuyển tiếp: app cần biết sự thật

Vì có hai kết nối TCP riêng (mục 3.1), app mất 3 thông tin. Proxy phải gửi lại qua header:

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host              $host;                       # tên miền người dùng gõ
    proxy_set_header X-Real-IP         $remote_addr;                # IP của client kết nối tới Nginx
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;  # chuỗi IP đi qua các proxy
    proxy_set_header X-Forwarded-Proto $scheme;                     # http hay https
}
```

| Header | Mất gì nếu thiếu | Ví dụ hậu quả |
|---|---|---|
| `Host` | Mặc định Nginx gửi `Host: $proxy_host` — tức `127.0.0.1:8080`, không phải tên miền thật | App tạo link tuyệt đối sai, app phục vụ nhiều tên miền không phân biệt được |
| `X-Real-IP` / `X-Forwarded-For` | IP thật của người dùng | Log toàn `127.0.0.1`; không chặn được IP tấn công; rate-limit theo IP vô dụng |
| `X-Forwarded-Proto` | Người dùng vào bằng HTTPS hay HTTP | Spring Boot redirect về `http://` → trình duyệt báo "không an toàn" hoặc lặp redirect |

`$proxy_add_x_forwarded_for` = giá trị `X-Forwarded-For` client gửi tới (nếu có) **nối thêm** `$remote_addr`. Khi có nhiều tầng proxy (ALB → Nginx → app), header này thành danh sách `ip-client, ip-alb`.

> ⚠️ App chỉ được **tin** các header này khi request thật sự đến từ proxy của bạn — client có thể tự gửi `X-Forwarded-For` giả. Spring Boot có cấu hình riêng cho việc tin header chuyển tiếp; sẽ cấu hình ở dự án v0 (Module 04).

### 4.6. 🟥 Timeout, 502 và 504

| Mã | Nghĩa từ góc nhìn proxy | Nguyên nhân hay gặp |
|---|---|---|
| **502 Bad Gateway** | Proxy **không nhận được phản hồi hợp lệ** từ upstream (server phía sau) | App chưa chạy / đã chết → `Connection refused`; sai port; app nghe `127.0.0.1` nhưng proxy ở máy/container khác |
| **504 Gateway Timeout** | Proxy kết nối/chờ upstream **quá thời gian** | App treo, truy vấn DB chậm, upstream bị firewall nuốt gói (DROP) nên kết nối không bao giờ xong |
| **503 Service Unavailable** | Không còn upstream nào khả dụng, hoặc app tự trả 503 khi quá tải/bảo trì | Mọi server trong upstream bị đánh dấu hỏng |

Các directive timeout (mặc định theo tài liệu proxy module):

| Directive | Mặc định | Ý nghĩa |
|---|---|---|
| `proxy_connect_timeout` | `60s` | Thời gian tối đa để **thiết lập** kết nối TCP tới upstream |
| `proxy_read_timeout` | `60s` | Thời gian tối đa **giữa hai lần đọc** dữ liệu từ upstream (không phải tổng thời gian) |
| `proxy_send_timeout` | `60s` | Thời gian tối đa giữa hai lần gửi dữ liệu tới upstream |

Ví dụ: một API xuất báo cáo mất 90 giây không trả byte nào → Nginx trả 504 sau 60 giây. Cách đúng thường **không phải** tăng timeout lên vô hạn, mà là đổi thiết kế (xử lý bất đồng bộ) — nhưng tăng `proxy_read_timeout` riêng cho location đó là cách tạm chấp nhận được.

### 4.7. 🟥 `reload` và `restart`

| | `reload` | `restart` |
|---|---|---|
| Cơ chế | Master nhận tín hiệu `SIGHUP`, đọc lại cấu hình, khởi động worker mới, worker cũ xử lý nốt request rồi thoát | Dừng hẳn tiến trình rồi chạy lại |
| Rớt kết nối? | **Không** | Có, trong giây lát |
| Cấu hình sai thì sao | Master giữ cấu hình cũ, tiếp tục chạy | Nginx **không khởi động lại được** → site sập |
| Dùng khi | Đổi cấu hình (gần như mọi lúc) | Nâng cấp binary, sự cố lạ |

Nhớ lại signal ở [Linux bài 04](../01-LINUX/04-processes-systemd.md). Quy trình chuẩn: **luôn `nginx -t` trước, rồi mới `reload`**.

### 4.8. 🟥 Load balancing trong Nginx

```nginx
upstream taskhub_backend {             # nhóm server phía sau, đặt trong khối http
    server 127.0.0.1:8081;
    server 127.0.0.1:8082;
}

server {
    listen 80;
    location / {
        proxy_pass http://taskhub_backend;   # trỏ tới tên upstream thay vì một địa chỉ
    }
}
```

Các thuật toán (theo tài liệu [ngx_http_upstream_module](https://nginx.org/en/docs/http/ngx_http_upstream_module.html) và [Using nginx as HTTP load balancer](https://nginx.org/en/docs/http/load_balancing.html)):

| Thuật toán | Cấu hình | Hoạt động | Hợp với |
|---|---|---|---|
| **Round robin có trọng số** | Mặc định | Lần lượt từng server, theo tỉ lệ `weight` | Các server giống nhau, request đồng đều |
| **Least connections** | `least_conn;` | Gửi tới server đang có **ít kết nối** nhất | Request dài ngắn khác nhau nhiều |
| **IP hash** | `ip_hash;` | Băm 3 octet đầu IPv4 của client → cùng client luôn tới cùng server | Cần "dính phiên" (sticky session) |
| **Weight** | `server x weight=3;` | Server mạnh nhận nhiều phần hơn (mặc định `1`) | Server cấu hình không đều |

**Health check (kiểm tra sức khỏe):**

- 🟥 **Bị động** (passive) — có trong Nginx mã nguồn mở: khi một request thật tới server bị lỗi (mặc định: lỗi kết nối hoặc timeout), Nginx đếm. Đủ `max_fails` lần (mặc định `1`) trong khoảng `fail_timeout` (mặc định `10s`) → server bị coi là hỏng trong `fail_timeout`, rồi được thử lại bằng request thật. Request lỗi được **chuyển sang server tiếp theo**.
- 🟨 **Chủ động** (active) — gửi request kiểm tra định kỳ (ví dụ `GET /actuator/health` mỗi 5 giây) **trước khi** người dùng gặp lỗi: thuộc **NGINX Plus** (bản thương mại), không có trong bản mã nguồn mở. AWS ALB và Kubernetes đều có health check chủ động — bạn sẽ cấu hình chúng ở Module 06 và 09.

```nginx
upstream taskhub_backend {
    server 127.0.0.1:8081 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8082 max_fails=3 fail_timeout=30s;
}
```

> Upstream chỉ có **một** server thì `max_fails`/`fail_timeout` bị bỏ qua — server đó không bao giờ bị đánh dấu hỏng.

🟨 **Sticky session** (phiên dính): nếu app lưu phiên đăng nhập trong RAM, người dùng bị chuyển sang server khác sẽ mất phiên. `ip_hash` là giải pháp tạm. Giải pháp đúng là làm app **không trạng thái** (stateless): lưu phiên vào Redis/database hoặc dùng token — điều kiện để scale ngang ở cloud và Kubernetes.

### 4.9. 🟥 Load balancer tầng 4 và tầng 7

Nhớ lại mô hình TCP/IP ở [bài 01](01-osi-tcpip-model.md):

| | L4 load balancer | L7 load balancer |
|---|---|---|
| Nhìn thấy | IP, port, TCP/UDP | Toàn bộ HTTP: URL, header, cookie, method |
| Quyết định dựa vào | IP:port | Đường dẫn, tên miền, header |
| TLS | Thường chuyển nguyên gói đi (passthrough) | Kết thúc TLS, đọc nội dung |
| Tốc độ | Rất nhanh, ít xử lý | Chậm hơn chút, linh hoạt hơn nhiều |
| Ví dụ | AWS **NLB**, Kubernetes **Service** (kube-proxy), `stream {}` của Nginx | AWS **ALB**, Nginx `http {}`, Kubernetes **Ingress** |
| Dùng khi | TCP không phải HTTP (database, MQTT), cần hiệu năng cực cao | Web/API — **phần lớn trường hợp** |

### 4.10. Gặp lại ở đâu

| Ở đây | Gặp lại |
|---|---|
| Nginx reverse proxy | Dự án `taskhub` v0: container Nginx trước container Spring Boot (Module 04) — `proxy_pass http://taskhub:8080` dùng **tên service** thay vì `127.0.0.1` |
| 502 / 504 | Debug Docker Compose, ALB target unhealthy (Module 06), Ingress (Module 09) |
| Load balancing + health check | AWS ALB + Target Group + Auto Scaling (Module 06), Kubernetes Service + readiness probe (Module 09) |
| `X-Forwarded-*` | ALB luôn thêm các header này; Spring Boot phải được cấu hình để tin chúng |
| TLS termination | Chứng chỉ trên Nginx (Let's Encrypt) hoặc trên ALB (ACM) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Cấu hình reverse proxy của `taskhub` trên EC2 (tuần 12)

```nginx
server {
    listen 80;
    server_name taskhub.example.com;

    client_max_body_size 5m;               # chặn upload quá 5 MB

    location /actuator/ {                  # không cho Internet xem thông tin nội bộ
        deny all;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Security Group chỉ mở 80/443. Spring Boot cấu hình `server.address=127.0.0.1` → kể cả ai đó mở nhầm port 8080 trên firewall cũng không truy cập thẳng app được (nhớ [bài 05](05-tcp-udp-ports-firewall.md) về bind address).

### Ví dụ 2: "Sau khi deploy, toàn bộ API trả 404"

Một kỹ sư "dọn dẹp" cấu hình, sửa `proxy_pass http://127.0.0.1:8080;` thành `proxy_pass http://127.0.0.1:8080/;` cho "đẹp". Trong `location /api/`, giờ app nhận `/tasks` thay vì `/api/tasks` → 404 từ Spring Boot. Cách phát hiện nhanh: xem **access log của app** (hoặc log Spring Boot) — đường dẫn app nhận được khác đường dẫn client gửi.

### Ví dụ 3: Bảo trì không gián đoạn với 2 backend

Có `server A` và `server B` trong upstream. Để nâng cấp A: thêm `down` vào dòng của A → `nginx -t && reload` → mọi request sang B → nâng cấp A → bỏ `down` → reload → làm tương tự với B. Đây là phiên bản thủ công của **rolling deployment** mà ALB và Kubernetes làm tự động.

---

## 6. Sơ đồ kiến trúc

### 6.1. Forward proxy và reverse proxy

```text
FORWARD PROXY (phía client)                     REVERSE PROXY (phía server)

 Máy nhân viên ─┐                                              ┌─► app-1 :8080
 Máy nhân viên ─┼─► [Proxy công ty] ──► Internet ──► [Nginx :443]┼─► app-2 :8080
 Máy nhân viên ─┘    (lọc, ghi log)                 (TLS, route) └─► static files
 Server thấy IP của proxy                         Client chỉ thấy Nginx
```

### 6.2. Hai kết nối TCP và các header chuyển tiếp

```text
 Trình duyệt                    Nginx (WSL)                         App (python/Spring)
 IP 172.24.80.1                 nghe 0.0.0.0:80                     nghe 127.0.0.1:8080
     │                               │                                    │
     │── TCP #1 ─────────────────────►│                                    │
     │   GET /api/tasks               │── TCP #2 (nguồn 127.0.0.1) ───────►│
     │   Host: localhost              │   GET /api/tasks                   │
     │                                │   Host: localhost                  │
     │                                │   X-Real-IP: 172.24.80.1           │
     │                                │   X-Forwarded-For: 172.24.80.1     │
     │                                │   X-Forwarded-Proto: http          │
     │◄──────────── 200 ──────────────│◄──────────── 200 ──────────────────│
```

### 6.3. Load balancing với health check bị động

```text
                       upstream taskhub_backend
                    ┌──────────────────────────────┐
 request 1 ──► Nginx ├──► 127.0.0.1:8081  ✅         │
 request 2 ──►       ├──► 127.0.0.1:8082  ❌ refused │──► thử lại sang 8081 ✅
                     │    (đánh dấu hỏng fail_timeout)│
 request 3 ──►       ├──► 127.0.0.1:8081  ✅         │
                    └──────────────────────────────┘
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `nginx -t` | Kiểm tra cú pháp cấu hình | 🟥 |
| `nginx -T` | Kiểm tra **và in toàn bộ** cấu hình đã nạp (gồm mọi file include) | 🟥 |
| `nginx -v` | Phiên bản | 🟥 |
| `systemctl reload nginx` / `nginx -s reload` | Nạp lại cấu hình không rớt kết nối | 🟥 |
| `systemctl status nginx` | Trạng thái service | 🟥 |
| `tail -f /var/log/nginx/error.log` | Theo dõi lỗi trực tiếp | 🟥 |
| `curl -I`, `curl -v` | Kiểm tra qua proxy ([bài 06](06-http-https-tls.md)) | 🟥 |
| `ss -tlnp` | Ai đang nghe port 80 / 8080 ([bài 05](05-tcp-udp-ports-firewall.md)) | 🟥 |
| `python3 -m http.server` | Backend thử nghiệm nhanh | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa** trên Ubuntu 24.04 WSL với Nginx 1.24 từ kho Ubuntu. Phiên bản, PID, thời gian trên máy bạn sẽ khác.

### `nginx -t` — kiểm tra cấu hình

```bash
sudo nginx -t
```

Cấu hình đúng:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Cấu hình sai (quên dấu `;`):

```text
nginx: [emerg] unexpected "}" in /etc/nginx/sites-enabled/taskhub:9
nginx: configuration file /etc/nginx/nginx.conf test failed
```

Đọc như mọi thông báo lỗi ([Linux bài 01, mục 12](../01-LINUX/01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý)): mức `[emerg]`, mô tả `unexpected "}"`, **file và số dòng** `taskhub:9`. Lỗi thường nằm ở dòng **ngay trước** dòng được báo.

> Cần `sudo` vì `nginx -t` đọc cả file chứng chỉ và thử mở file log thuộc root.

### `nginx -T` — xem cấu hình thật sự đang được nạp

```bash
sudo nginx -T | less
sudo nginx -T 2>/dev/null | grep -n "server_name\|listen\|proxy_pass"
```

Khi không hiểu vì sao Nginx "không theo" file bạn vừa sửa, `nginx -T` cho thấy **mọi** file được include, theo đúng thứ tự — bạn sẽ phát hiện site `default` vẫn còn bật, hoặc file của bạn chưa được symlink vào `sites-enabled`.

### `systemctl reload nginx` và `nginx -s reload`

```bash
sudo nginx -t && sudo systemctl reload nginx     # khi WSL có systemd
sudo nginx -t && sudo nginx -s reload            # cách gửi tín hiệu trực tiếp cho master
```

`&&` bảo đảm chỉ reload khi kiểm tra thành công (nhớ exit code ở [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#echo---exit-code)). Không có systemd: `sudo service nginx reload`.

### `python3 -m http.server` — backend thử nghiệm

```bash
python3 -m http.server 8080 --bind 127.0.0.1
```

```text
Serving HTTP on 127.0.0.1 port 8080 (http://127.0.0.1:8080/) ...
127.0.0.1 - - [05/Nov/2026 20:10:11] "GET / HTTP/1.0" 200 -
```

| Tham số | Ý nghĩa |
|---|---|
| `-m http.server` | Chạy module web server có sẵn của Python, phục vụ file trong **thư mục hiện tại** |
| `8080` | Port nghe |
| `--bind 127.0.0.1` | Chỉ nghe trên loopback — giống cách app thật nên được giấu sau proxy |

Để ý dòng log: request đến từ Nginx dùng `HTTP/1.0` — mặc định Nginx nói chuyện với upstream bằng HTTP/1.0 (đổi bằng `proxy_http_version 1.1`). Đây là bằng chứng cho "hai kết nối riêng biệt": client gửi HTTP/1.1, upstream nhận HTTP/1.0.

### Đọc một dòng `access.log`

```text
172.24.80.1 - - [05/Nov/2026:20:10:11 +0700] "GET / HTTP/1.1" 200 412 "-" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) ..."
```

Định dạng `combined`: IP client · user · thời gian · request line · **status** · số byte trả về · referer · user agent. Bạn đã phân tích dạng log này ở [Linux bài 02](../01-LINUX/02-essential-commands-text.md).

### Đọc một dòng `error.log` khi 502

```text
2026/11/05 20:12:40 [error] 2711#2711: *7 connect() failed (111: Connection refused) while connecting to upstream, client: 127.0.0.1, server: _, request: "HEAD / HTTP/1.1", upstream: "http://127.0.0.1:8080/", host: "localhost"
```

| Phần | Ý nghĩa |
|---|---|
| `[error]` | Mức log |
| `2711#2711` | PID#TID của worker |
| `*7` | Số thứ tự kết nối — dùng để gom các dòng của cùng một request |
| `connect() failed (111: Connection refused)` | **Nguyên nhân**: lời gọi hệ thống `connect()` thất bại, errno 111 = `ECONNREFUSED` — không có ai nghe port đó |
| `while connecting to upstream` | Lỗi xảy ra ở **phía upstream**, không phải phía client |
| `upstream: "http://127.0.0.1:8080/"` | Địa chỉ Nginx đã cố kết nối — so với nơi app thật sự nghe |

Các biến thể khác bạn sẽ gặp:

| Thông báo | Ý nghĩa | Mã trả client |
|---|---|---|
| `(111: Connection refused)` | Không có process nghe port đó | 502 |
| `(110: Connection timed out) while connecting to upstream` | Gói tin bị nuốt (firewall DROP, sai IP không tồn tại) | 504 |
| `upstream timed out (110: Connection timed out) while reading response header` | Kết nối được nhưng app trả lời quá `proxy_read_timeout` | 504 |
| `no live upstreams while connecting to upstream` | Mọi server trong upstream đang bị đánh dấu hỏng | 502 |
| `(13: Permission denied) while connecting to upstream` | Thường gặp trên Red Hat do SELinux chặn Nginx kết nối mạng | 502 |

---

## 9. Bài thực hành từng bước

**Lab: Nginx reverse proxy + load balancing** · `[WSL]` · ~90 phút

Mục tiêu: dựng đúng mô hình "proxy trước app", tự gây và đọc lỗi 502, rồi thêm load balancing. Kết quả dùng cho [milestone v-pre, tuần 5](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-5--nginx-reverse-proxy-thử-nghiệm).

Cần 3 terminal WSL: **T1** cho backend, **T2** cho log, **T3** để thao tác.

### Phần 1 — Reverse proxy

#### Bước 1 — Cài Nginx

> Đây là **cài phần mềm** vào WSL — bạn tự quyết định. Gỡ ở bước Dọn dẹp.

```bash
# T3
sudo apt update
sudo apt install -y nginx
nginx -v
ps -p 1 -o comm=          # "systemd" → dùng systemctl; khác → dùng service
```

Khởi động và kiểm tra:

```bash
sudo systemctl start nginx      # hoặc: sudo service nginx start
sudo ss -tlnp | grep ':80 '
curl -I http://localhost
```

Bạn sẽ thấy trang mặc định "Welcome to nginx!" với `Server: nginx/1.24.0 (Ubuntu)`.

#### Bước 2 — Dựng backend

```bash
# T1
mkdir -p ~/devops-lab/02-networking/lab07/backend
cd ~/devops-lab/02-networking/lab07/backend
echo "<h1>taskhub backend 8080</h1>" > index.html
python3 -m http.server 8080 --bind 127.0.0.1
```

```bash
# T3 — gọi thẳng backend, chưa qua Nginx
curl -s http://127.0.0.1:8080/
```

#### Bước 3 — Viết server block

```bash
# T3
sudo nano /etc/nginx/sites-available/taskhub
```

```nginx
# /etc/nginx/sites-available/taskhub — lab 07, phần 1
server {
    listen 80 default_server;               # nghe port 80; là server mặc định khi Host không khớp server_name nào
    server_name _;                          # "_" là tên giả, không khớp tên thật nào — kết hợp default_server để nhận mọi request

    access_log /var/log/nginx/taskhub.access.log;   # log truy cập riêng cho site này
    error_log  /var/log/nginx/taskhub.error.log;    # log lỗi riêng cho site này

    location / {                            # khớp mọi đường dẫn
        proxy_pass http://127.0.0.1:8080;   # chuyển tiếp tới backend; KHÔNG có "/" cuối → giữ nguyên đường dẫn
        proxy_set_header Host              $host;                      # giữ tên miền client gõ
        proxy_set_header X-Real-IP         $remote_addr;               # IP thật của client
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for; # chuỗi IP qua các proxy
        proxy_set_header X-Forwarded-Proto $scheme;                    # http hay https
        proxy_connect_timeout 5s;           # chờ kết nối tới backend tối đa 5s (mặc định 60s) — để lab thấy lỗi nhanh
    }
}
```

Tắt site mặc định, bật site mới:

```bash
sudo rm /etc/nginx/sites-enabled/default                     # chỉ xóa symlink, file gốc trong sites-available vẫn còn
sudo ln -s /etc/nginx/sites-available/taskhub /etc/nginx/sites-enabled/taskhub
ls -l /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx                 # hoặc: sudo service nginx reload
```

❓ Nếu **không** xóa symlink `default`, `nginx -t` báo lỗi gì? Vì sao? (Gợi ý: hai server block cùng `default_server` trên port 80.)

#### Bước 4 — Kiểm tra qua Nginx

```bash
# T2
sudo tail -f /var/log/nginx/taskhub.access.log
```

```bash
# T3
curl -I http://localhost
curl -s http://localhost/
```

Quan sát cả 3 terminal: T3 nhận nội dung backend; T2 ghi một dòng access log; T1 (python) ghi request **đến từ `127.0.0.1` bằng `HTTP/1.0`**.

Mở trình duyệt Windows tới `http://localhost`. Thường WSL tự chuyển tiếp `localhost` từ Windows vào WSL. Nếu không mở được, xem phần mạng WSL ở [bài 04](04-routing-nat-switching.md) và ghi lại vào nhật ký debug.

❓ Header `Server` trong `curl -I` là của Nginx hay python? Điều này cho biết gì về việc "ẩn backend"?

#### Bước 5 — Gây lỗi 502

```bash
# T1: nhấn Ctrl+C để dừng backend
# T2: đổi sang theo dõi error log
sudo tail -f /var/log/nginx/taskhub.error.log
```

```bash
# T3
curl -I http://localhost
```

❓ Mã trạng thái là gì? Copy nguyên văn dòng error log vào `lab07.md` và giải thích từng phần theo bảng ở mục 8.

#### Bước 6 — Gây lỗi 404 do dấu `/`

Khởi động lại backend (T1), tạo thêm thư mục con:

```bash
# T1
mkdir -p api && echo '{"tasks": []}' > api/tasks.json
python3 -m http.server 8080 --bind 127.0.0.1
```

Thêm vào server block, **trước** `location /`:

```nginx
    location /api/ {
        proxy_pass http://127.0.0.1:8080/;   # CÓ "/" cuối — cố ý để thấy cạm bẫy
    }
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -i http://localhost/api/tasks.json
```

❓ Nhìn log python ở T1: backend nhận đường dẫn nào? Sửa thành không có `/` cuối, reload, thử lại. Ghi lại cả hai kết quả.

### Phần 2 — Load balancing

#### Bước 7 — Hai backend khác nội dung

Dừng backend 8080 (T1). Tạo hai backend:

```bash
# T1
cd ~/devops-lab/02-networking/lab07
mkdir -p b1 b2
echo "<h1>backend-1 (8081)</h1>" > b1/index.html
echo "<h1>backend-2 (8082)</h1>" > b2/index.html
python3 -m http.server 8081 --bind 127.0.0.1 --directory b1 &
python3 -m http.server 8082 --bind 127.0.0.1 --directory b2 &
jobs
```

`--directory` chọn thư mục phục vụ; `&` chạy nền (job control ở [Linux bài 04](../01-LINUX/04-processes-systemd.md)).

#### Bước 8 — Cấu hình upstream

Sửa `/etc/nginx/sites-available/taskhub`: thêm khối `upstream` **ở ngoài** khối `server` (file trong `sites-enabled` được include bên trong khối `http`, nên `upstream` hợp lệ ở đây), và đổi `location /` sang dùng upstream:

```nginx
upstream taskhub_backend {                      # nhóm backend
    server 127.0.0.1:8081 max_fails=2 fail_timeout=15s;   # hỏng 2 lần trong 15s → nghỉ 15s
    server 127.0.0.1:8082 max_fails=2 fail_timeout=15s;
}

server {
    listen 80 default_server;
    server_name _;
    access_log /var/log/nginx/taskhub.access.log;
    error_log  /var/log/nginx/taskhub.error.log;

    location / {
        proxy_pass http://taskhub_backend;      # tên upstream thay cho địa chỉ
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
for i in 1 2 3 4 5 6; do curl -s http://localhost/; done
```

❓ Thứ tự backend trả lời là gì? Thử thêm `weight=3` cho 8081, reload, chạy lại 8 lần — tỉ lệ thay đổi thế nào?

#### Bước 9 — Failover

```bash
# T1: dừng backend 8082
kill %2          # %2 = job số 2 trong danh sách `jobs`
jobs
```

```bash
# T3
for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w "%{http_code} " http://localhost/; done; echo
sudo tail -5 /var/log/nginx/taskhub.error.log
```

❓ Người dùng có thấy lỗi nào không? Error log ghi gì? Sau khi dừng **cả hai** backend, mã trả về và thông báo log là gì?

### Phần 3 — 🟨 HTTPS với chứng chỉ tự ký

Khởi động lại 2 backend. Tạo chứng chỉ tự ký (self-signed) — cơ chế chứng chỉ đã học ở [bài 06](06-http-https-tls.md):

```bash
sudo mkdir -p /etc/nginx/tls
sudo openssl req -x509 -newkey rsa:2048 -nodes -days 30 \
  -keyout /etc/nginx/tls/taskhub.key -out /etc/nginx/tls/taskhub.crt \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost"
sudo chmod 600 /etc/nginx/tls/taskhub.key
```

> Nếu đã làm lab bài 06, bạn có thể dùng lại chứng chỉ ở `~/devops-lab/02-networking/tls/` thay vì tạo mới: `sudo cp ~/devops-lab/02-networking/tls/taskhub.{crt,key} /etc/nginx/tls/` rồi chạy lại lệnh `chmod` ở trên. Vì sao phải copy vào `/etc/nginx/tls/`? Nginx master process chạy bằng root nên đọc được key ở đâu cũng được, nhưng quy ước đặt cấu hình và bí mật của dịch vụ trong `/etc/<dịch-vụ>/` (bài 01 Linux) giúp người sau tìm thấy và không để key nằm trong thư mục home.

Thay khối `server` bằng hai khối:

```nginx
server {                                         # khối 1: HTTP chỉ để chuyển hướng
    listen 80 default_server;
    server_name _;
    return 301 https://$host$request_uri;        # chuyển mọi request sang HTTPS, giữ nguyên đường dẫn
}

server {                                         # khối 2: HTTPS
    listen 443 ssl default_server;               # nghe 443, bật TLS
    server_name _;
    ssl_certificate     /etc/nginx/tls/taskhub.crt;   # chứng chỉ (public)
    ssl_certificate_key /etc/nginx/tls/taskhub.key;   # khóa bí mật — chỉ root đọc được
    access_log /var/log/nginx/taskhub.access.log;
    error_log  /var/log/nginx/taskhub.error.log;

    location / {
        proxy_pass http://taskhub_backend;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;   # giờ sẽ là "https"
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -I http://localhost                 # 301 + Location: https://localhost/
curl -I https://localhost                # lỗi chứng chỉ — vì sao?
curl -kI https://localhost               # -k: bỏ qua kiểm tra chứng chỉ (CHỈ dùng khi thử nghiệm)
curl --cacert /etc/nginx/tls/taskhub.crt -I https://localhost   # tin đúng chứng chỉ này → không cần -k
```

❓ Vì sao `curl --cacert ...` chạy được mà không cần `-k`? Trong thực tế (EC2, tuần 12) thay chứng chỉ tự ký bằng gì?

### Bước 10 — Lưu kết quả và dọn dẹp

Lưu vào dự án theo [milestone tuần 5](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-5--nginx-reverse-proxy-thử-nghiệm):

```bash
mkdir -p ~/projects/taskhub/docs/experiments
cp /etc/nginx/sites-available/taskhub ~/projects/taskhub/docs/experiments/nginx-wsl.conf
cp ~/devops-lab/02-networking/lab07/lab07.md ~/devops-journey/week05/
```

Dọn dẹp:

```bash
kill %1 %2 2>/dev/null                                   # dừng backend python
sudo rm /etc/nginx/sites-enabled/taskhub
sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default   # bật lại site mặc định
sudo nginx -t && sudo systemctl reload nginx
# Tùy chọn — gỡ hẳn Nginx (⚠️ purge xóa cả cấu hình trong /etc/nginx):
# sudo systemctl stop nginx && sudo apt purge -y nginx nginx-common && sudo apt autoremove -y
```

---

## 10. Kết quả mong đợi

- **Bước 3:** Nếu giữ site `default`, `nginx -t` báo lỗi kiểu `a duplicate default server for 0.0.0.0:80` — chỉ được một `default_server` cho mỗi cặp địa chỉ:port.
- **Bước 4:** `curl -I` trả `HTTP/1.1 200 OK` với `Server: nginx/1.24.0 (Ubuntu)` — client chỉ thấy Nginx. Log python thấy request từ `127.0.0.1` dùng `HTTP/1.0`.
- **Bước 5:** `HTTP/1.1 502 Bad Gateway`; error log có `connect() failed (111: Connection refused) while connecting to upstream ... upstream: "http://127.0.0.1:8080/"`.
- **Bước 6:** Với `proxy_pass http://127.0.0.1:8080/;`, backend nhận `/tasks.json` → 404. Bỏ dấu `/` → backend nhận `/api/tasks.json` → 200.
- **Bước 8:** Round robin xen kẽ `backend-1`, `backend-2`. Với `weight=3`: khoảng 3 lần backend-1 cho 1 lần backend-2.
- **Bước 9:** Khi tắt 8082, người dùng vẫn nhận `200` (Nginx thử lại sang 8081), error log ghi `connect() failed (111...)` với upstream `127.0.0.1:8082` một lần rồi server đó bị đánh dấu hỏng. Tắt cả hai → `502`, log có `no live upstreams` hoặc `Connection refused`.
- **Phần 3:** `curl -I http://localhost` trả `301` với `Location: https://localhost/`. `curl` không `-k` báo `SSL certificate problem: self-signed certificate` vì chứng chỉ không do CA nào trong kho tin cậy ký. Với `--cacert`, bạn chỉ định tin chính chứng chỉ đó. Trên EC2 sẽ dùng chứng chỉ từ **Let's Encrypt** (miễn phí) hoặc ACM trên ALB.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Vẫn thấy "Welcome to nginx!" sau khi cấu hình | Site `default` vẫn bật, hoặc chưa symlink site mới, hoặc quên reload | `ls -l /etc/nginx/sites-enabled/`, `sudo nginx -T \| grep -n server_name` |
| `bind() to 0.0.0.0:80 failed (98: Address already in use)` | Đã có process khác nghe port 80 (Apache, Nginx khác, Docker container) | `sudo ss -tlnp \| grep ':80 '` tìm thủ phạm |
| `nginx: [emerg] unknown directive "proxy_pas"` | Gõ sai tên directive | Đọc số dòng trong thông báo, so với tài liệu |
| `"upstream" directive is not allowed here` | Đặt `upstream` bên trong `server` | `upstream` phải nằm trong `http` (ngoài `server`) |
| 404 chỉ khi đi qua Nginx | Dấu `/` cuối `proxy_pass` cắt mất tiền tố | Xem mục 4.4, so log đường dẫn app nhận được |
| 502 dù app đang chạy | App nghe khác địa chỉ/port Nginx trỏ tới (ví dụ app nghe `[::1]:8080` còn Nginx gọi `127.0.0.1:8080`) | `ss -tlnp` xem app nghe chính xác ở đâu |
| Redirect lặp vô tận sau khi bật HTTPS | App không biết request gốc là HTTPS, lại redirect sang HTTPS | Gửi `X-Forwarded-Proto` và cấu hình app tin header này |
| `413 Request Entity Too Large` khi upload | Mặc định `client_max_body_size` là 1 MB | Tăng trong server/location phù hợp |
| Sửa xong, `restart` làm site sập | Cấu hình sai, Nginx không khởi động lại được | Luôn `nginx -t` trước; dùng `reload` |

---

## 12. Đọc log và xử lý lỗi

**Nguyên tắc vàng của reverse proxy:** khi client nhận 5xx, **đọc `error.log` của proxy trước**, rồi mới đến log của app. Proxy biết chính xác nó đã cố kết nối tới đâu và thất bại thế nào.

Quy trình khi gặp 502/504:

1. **Xác nhận mã lỗi và ai trả lời:** `curl -I http://host/` — header `Server: nginx` + mã 502/504 = lỗi giữa Nginx và upstream.
2. **Đọc error log của site:** `sudo tail -20 /var/log/nginx/<site>.error.log` → tìm `upstream: "..."` và errno.
3. **Đối chiếu upstream với thực tế:** `sudo ss -tlnp | grep <port>` — có process nào nghe đúng địa chỉ:port đó không?
4. **Gọi thẳng upstream từ chính máy Nginx:** `curl -v http://127.0.0.1:8080/` — nếu gọi thẳng cũng lỗi → vấn đề ở app; nếu gọi thẳng được → vấn đề ở cấu hình proxy (đường dẫn, Host, timeout).
5. **Đọc log app** cho đúng request (thời điểm, đường dẫn).
6. **Ghi nhật ký debug** theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

Bảng tra nhanh errno thường gặp trong `error.log`:

| errno | Tên | Nghĩa |
|---|---|---|
| 111 | `ECONNREFUSED` | Đến được máy nhưng không ai nghe port |
| 110 | `ETIMEDOUT` | Không nhận được phản hồi — gói bị nuốt hoặc app quá chậm |
| 113 | `EHOSTUNREACH` | Không có đường tới máy đích |
| 13 | `EACCES` | Bị chặn bởi quyền (SELinux, socket file) |

Bạn sẽ gặp lại đúng các mã này trong `curl` và `nc` ở [bài 05](05-tcp-udp-ports-firewall.md) và [bài 08](08-network-troubleshooting-tools.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Forward proxy và reverse proxy khác nhau thế nào? Mỗi loại "giấu" ai?
2. Kể 4 lý do nên đặt Nginx trước Spring Boot dù Spring Boot tự chạy web server được.
3. Vì sao log của app phía sau proxy chỉ thấy IP `127.0.0.1`? Sửa bằng cách nào?
4. `location /api/` với `proxy_pass http://app:8080;` và `proxy_pass http://app:8080/;` — request `/api/users` đến app thành gì trong mỗi trường hợp?
5. Nếu thiếu `X-Forwarded-Proto`, chuyện gì có thể xảy ra với app khi người dùng vào bằng HTTPS?
6. Phân biệt 502 và 504. Mỗi mã gợi ý bạn kiểm tra gì đầu tiên?
7. `reload` khác `restart` thế nào? Vì sao luôn chạy `nginx -t` trước?
8. Nginx chọn server block nào khi nhận request? Vai trò của `default_server`?
9. Round robin, least_conn, ip_hash — khi nào dùng cái nào?
10. Health check bị động và chủ động khác nhau thế nào? Nginx mã nguồn mở có loại nào?
11. Vì sao app nên "không trạng thái" để load balancing hiệu quả?
12. Load balancer L4 và L7 khác nhau thế nào? Cho ví dụ mỗi loại trên AWS và Kubernetes.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/07-solutions.md](solutions/07-solutions.md) — chỉ mở sau khi tự làm.

**Bài 1 — Định tuyến theo đường dẫn.** Dựng hai backend: một phục vụ "frontend" (file HTML tĩnh) ở 8081, một là "API" ở 8082 có thư mục `api/`. Viết một server block sao cho `/` → frontend, `/api/` → API và **giữ nguyên** đường dẫn `/api/...`. Thêm một location chặn `/actuator/` bằng `deny all`. Kiểm chứng bằng `curl` và ghi lại mã trả về của từng đường dẫn.

**Bài 2 — Nhìn thấy header chuyển tiếp.** Lưu đoạn sau thành `echo_headers.py` và chạy nó làm backend ở 8080:

```python
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = "".join(f"{k}: {v}\n" for k, v in self.headers.items()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body)

HTTPServer(("127.0.0.1", 8080), H).serve_forever()
```

So sánh header backend nhận được khi: (a) có đủ 4 dòng `proxy_set_header`; (b) xóa hết 4 dòng. Giá trị `Host` trong (b) là gì và vì sao? Gửi thêm `curl -H "X-Forwarded-For: 1.2.3.4" http://localhost/` ở cấu hình (a) — backend nhận gì? Rút ra kết luận về việc app có nên tin mù quáng header này.

**Bài 3 — Tự tạo 504.** Viết một backend Python trả lời sau 10 giây (gợi ý: `time.sleep(10)` trong `do_GET`). Cấu hình `proxy_read_timeout 3s;`. Ghi lại mã trả về, thời gian chờ (đo bằng `curl -w "%{time_total}\n"`), và dòng error log. Sau đó tăng timeout lên 15s cho riêng location `/slow/`.

**Bài 4 — Bảo trì không gián đoạn.** Với upstream 2 backend, thực hiện quy trình ở Ví dụ 3 (`down`) trong lúc một vòng lặp `while true; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost/; sleep 0.2; done` chạy liên tục. Chứng minh không có request nào lỗi. So sánh với việc `kill` thẳng một backend: có request nào lỗi không?

**Bài 5 — Đọc cấu hình người khác.** Chạy `sudo nginx -T` sau lab, đọc toàn bộ đầu ra. Liệt kê: (a) user mà worker chạy; (b) số worker; (c) những file nào được include; (d) định dạng log mặc định; (e) `client_max_body_size` hiện tại. Mỗi ý ghi dòng cấu hình làm bằng chứng.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ được sơ đồ 6.2 và giải thích vì sao có hai kết nối TCP.
- [ ] Viết được server block reverse proxy từ trí nhớ, có đủ header chuyển tiếp, giải thích từng dòng.
- [ ] Dự đoán đúng đường dẫn app nhận được với mọi biến thể `proxy_pass` ở bảng mục 4.4.
- [ ] Nhìn một dòng `error.log` là biết lỗi 502 hay 504 và kiểm tra gì tiếp theo.
- [ ] Cấu hình được upstream có load balancing và giải thích health check bị động.
- [ ] Giải thích được L4 vs L7 và ánh xạ sang NLB/ALB, Service/Ingress.
- [ ] Hoàn thành Bài tập 2 và 3 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [nginx Beginner's Guide](https://nginx.org/en/docs/beginners_guide.html) | Kiến trúc master/worker, cấu trúc cấu hình, proxy cơ bản | 2026-10-31 |
| [ngx_http_proxy_module](https://nginx.org/en/docs/http/ngx_http_proxy_module.html) | `proxy_pass` (quy tắc URI), `proxy_set_header`, timeout và giá trị mặc định | 2026-10-31 |
| [ngx_http_upstream_module](https://nginx.org/en/docs/http/ngx_http_upstream_module.html) | `upstream`, `least_conn`, `ip_hash`, `weight`, `max_fails`, `fail_timeout` | 2026-10-31 |
| [Using nginx as HTTP load balancer](https://nginx.org/en/docs/http/load_balancing.html) | Thuật toán cân bằng tải, health check bị động, session persistence | 2026-10-31 |
