# 06. HTTP, HTTPS và TLS

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [03. DNS và DHCP](03-dns-dhcp.md), [05. TCP, UDP, port và firewall](05-tcp-udp-ports-firewall.md)
> Môi trường: `[WSL]` Ubuntu 24.04

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

- Đọc được một **HTTP request** và **HTTP response** ở dạng thô: method, path, header, body, status code.
- Biết ý nghĩa vận hành của các **status code** hay gặp, và quan trọng hơn: **ai sinh ra** mã đó — ứng dụng hay reverse proxy.
- Giải thích vai trò của các header quan trọng: `Host`, `Content-Type`, `Location`, `X-Forwarded-For`…
- Giải thích **HTTPS** bảo vệ được những gì, **TLS handshake** diễn ra thế nào (mức khái niệm), **chứng chỉ** và **chuỗi tin cậy** hoạt động ra sao.
- Dùng thành thạo `curl` để debug HTTP (đọc `-v`, đo thời gian từng giai đoạn, giả lập DNS bằng `--resolve`).
- Dùng `openssl` để kiểm tra chứng chỉ của một website và tự tạo chứng chỉ self-signed.
- Nhận ra và giải thích các lỗi TLS phổ biến: hết hạn, sai tên miền, thiếu chain, self-signed.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Người dùng báo lỗi 502" | 502 do **reverse proxy** sinh ra, không phải app → kiểm tra kết nối proxy → app |
| "Người dùng báo lỗi 504" | Proxy chờ app **quá lâu** → app chậm, không phải app chết |
| "Upload file lớn bị lỗi 413" | Giới hạn kích thước body của **Nginx**, không phải lỗi code |
| "Website báo chứng chỉ không hợp lệ" | Hết hạn? Sai tên miền? Thiếu intermediate? — mỗi loại cách sửa khác nhau |
| "Sau khi đặt app sau HTTPS proxy, trang bị redirect vòng tròn" | App không biết request gốc là HTTPS → header `X-Forwarded-Proto` |
| "Trang web chậm" | Chậm ở DNS, kết nối, TLS hay app? → `curl -w` đo từng giai đoạn |
| "Muốn thử server mới trước khi đổi DNS" | `curl --resolve` |

Hầu như mọi dịch vụ bạn triển khai đều nói HTTP. Hiểu HTTP là hiểu được **ngôn ngữ** mà người dùng, load balancer, reverse proxy, ứng dụng và health check dùng để nói chuyện với nhau.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. HTTP nằm ở đâu?

**HTTP** (HyperText Transfer Protocol — giao thức truyền siêu văn bản) là giao thức **tầng Application** ([bài 01](01-osi-tcpip-model.md)), chạy **trên TCP** ([bài 05](05-tcp-udp-ports-firewall.md)):

```text
Trình duyệt gõ http://example.com/
  1. DNS:  example.com → 93.184.215.14          (bài 03)
  2. TCP:  bắt tay 3 bước tới 93.184.215.14:80  (bài 05)
  3. HTTP: gửi request dạng văn bản, nhận response
```

HTTPS = HTTP **chạy bên trong một đường hầm TLS** (mã hóa), mặc định port 443:

```text
  1. DNS → 2. TCP tới :443 → 3. TLS handshake (thỏa thuận mã hóa, kiểm tra chứng chỉ) → 4. HTTP (đã mã hóa)
```

### 3.2. Mô hình request/response và "không trạng thái"

- **Client** (trình duyệt, curl, app khác, load balancer) gửi **request** (yêu cầu).
- **Server** trả về **response** (phản hồi).
- HTTP là **stateless** (không trạng thái): mỗi request độc lập, server không tự nhớ request trước. Muốn "nhớ" người dùng đã đăng nhập, phải gửi kèm thông tin trong mỗi request — qua **cookie** hoặc **token** trong header.

> Tính stateless là lý do bạn có thể đặt **nhiều** bản sao app sau một load balancer ([bài 07](07-load-balancing-reverse-proxy.md)) — miễn là app không lưu phiên đăng nhập trong RAM của riêng nó.

### 3.3. HTTP/1.1 là văn bản thuần

Với HTTP/1.1, request và response là **văn bản đọc được**. Đây là lý do bạn có thể dùng `nc` làm "server giả" để xem chính xác curl gửi gì (lab Bước 2). Phiên bản mới hơn (HTTP/2, HTTP/3) dùng định dạng nhị phân nhưng **ý nghĩa** (method, header, status) giữ nguyên.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cấu trúc HTTP request

```text
POST /api/tasks?notify=true HTTP/1.1            ← dòng request: METHOD  PATH  VERSION
Host: taskhub.example.com                        ← header (mỗi dòng "Tên: giá trị")
User-Agent: curl/8.5.0
Accept: application/json
Content-Type: application/json
Content-Length: 27
                                                 ← một dòng TRỐNG: hết phần header
{"title":"Học bài 06 HTTP"}                     ← body (có thể không có)
```

| Phần | Ý nghĩa |
|---|---|
| **Method** (phương thức) | Hành động muốn làm |
| **Path** (đường dẫn) | Tài nguyên muốn truy cập, kèm **query string** sau dấu `?` |
| **Version** | `HTTP/1.1`, `HTTP/2` |
| **Header** | Thông tin bổ sung: host nào, định dạng gì, ai gửi… |
| **Body** (thân) | Dữ liệu gửi kèm (JSON, form, file) |

### 4.2. 🟥 Cấu trúc HTTP response

```text
HTTP/1.1 201 Created                             ← dòng trạng thái: VERSION  STATUS-CODE  REASON
Content-Type: application/json
Content-Length: 58
Location: /api/tasks/42

{"id":42,"title":"Học bài 06 HTTP","status":"TODO"}
```

### 4.3. 🟥 Methods

| Method | Dùng để | Có body? | Idempotent 🟨 |
|---|---|---|---|
| `GET` | Lấy dữ liệu | Không | Có |
| `HEAD` | Như GET nhưng **chỉ lấy header** — dùng cho health check, kiểm tra nhanh | Không | Có |
| `POST` | Tạo mới / gửi dữ liệu xử lý | Có | **Không** |
| `PUT` | Thay thế toàn bộ tài nguyên | Có | Có |
| `PATCH` | Sửa một phần tài nguyên | Có | Không đảm bảo |
| `DELETE` | Xóa | Thường không | Có |

🟨 **Idempotent** (lũy đẳng): gọi một lần hay nhiều lần cho **cùng kết quả** trên server. Ý nghĩa vận hành: khi request bị timeout, proxy/client có thể **tự gửi lại** request idempotent khá an toàn, nhưng gửi lại `POST` có thể tạo ra **hai** đơn hàng. Đây là lý do cấu hình "retry" ở load balancer cần cẩn thận.

### 4.4. 🟥 Status codes — và ai sinh ra chúng

Năm nhóm status code (theo [MDN — HTTP response status codes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status), định nghĩa trong RFC 9110):

| Nhóm | Nghĩa |
|---|---|
| `1xx` | Thông tin (ít gặp khi vận hành) |
| `2xx` | Thành công |
| `3xx` | Chuyển hướng |
| `4xx` | Lỗi **phía client** (request sai, thiếu quyền…) |
| `5xx` | Lỗi **phía server** |

Các mã DevOps gặp nhiều nhất:

| Mã | Tên | Ý nghĩa vận hành | Thường do ai sinh ra |
|---|---|---|---|
| `200` | OK | Thành công | App |
| `201` | Created | Tạo mới thành công (thường kèm header `Location`) | App |
| `204` | No Content | Thành công, không có body (hay gặp với DELETE) | App |
| `301` | Moved Permanently | Chuyển hướng **vĩnh viễn** — trình duyệt nhớ (cache) luôn | Proxy hoặc app (ví dụ chuyển HTTP → HTTPS) |
| `302` | Found | Chuyển hướng **tạm thời** | App (ví dụ chuyển tới trang đăng nhập) |
| `304` | Not Modified | Nội dung không đổi, dùng bản cache | Proxy/web server/app |
| `400` | Bad Request | Request sai định dạng (JSON hỏng, thiếu trường) | App |
| `401` | Unauthorized | **Chưa xác thực** — chưa đăng nhập, token thiếu/hết hạn | App |
| `403` | Forbidden | **Đã biết bạn là ai** nhưng không có quyền | App, hoặc proxy/WAF chặn, hoặc S3 bucket policy |
| `404` | Not Found | Không có tài nguyên | App, hoặc proxy không có `location` khớp |
| `405` | Method Not Allowed | Path đúng nhưng sai method (POST vào endpoint chỉ nhận GET) | App |
| `413` | Content Too Large | Body quá lớn | **Proxy** — Nginx mặc định giới hạn body 1 MB |
| `429` | Too Many Requests | Bị giới hạn tần suất (rate limit) | Proxy/API gateway/app |
| `500` | Internal Server Error | App gặp lỗi không xử lý được (exception) | **App** → xem log/stack trace của app |
| `502` | Bad Gateway | Proxy **không nhận được phản hồi hợp lệ** từ app phía sau: app chết, refused, đóng kết nối giữa chừng | **Proxy** (Nginx, ALB) |
| `503` | Service Unavailable | Dịch vụ tạm thời không phục vụ: quá tải, bảo trì, **không có backend nào khỏe** | Proxy/load balancer hoặc app |
| `504` | Gateway Timeout | Proxy **chờ app quá lâu** không thấy trả lời | **Proxy** |

**Quy tắc vàng khi debug 5xx:**

```text
500 → app đã nhận request và tự báo lỗi        → đọc LOG CỦA APP.
502 → proxy không nói chuyện được với app       → app có chạy không? đúng port không? (bài 05: ss -tlnp)
504 → proxy nói chuyện được nhưng app quá chậm  → app làm gì lâu thế? DB chậm? timeout proxy quá ngắn?
503 → không có backend khỏe / quá tải           → health check, số lượng instance.
```

**401 vs 403** — câu hỏi phỏng vấn kinh điển: 401 = "tôi **không biết bạn là ai**" (chưa xác thực — authentication). 403 = "tôi **biết bạn là ai**, nhưng bạn **không được phép**" (thiếu quyền — authorization).

### 4.5. 🟥 Headers quan trọng

| Header | Chiều | Ý nghĩa | Vì sao DevOps quan tâm |
|---|---|---|---|
| `Host` | Request | Tên miền client muốn truy cập | Một IP phục vụ **nhiều website** (virtual host — máy chủ ảo): server đọc `Host` để biết trả trang nào. Nginx dùng nó để chọn `server_name` |
| `Content-Type` | Cả hai | Định dạng body: `application/json`, `text/html`… | Gửi JSON mà quên header này → app trả 415 hoặc 400 |
| `Content-Length` | Cả hai | Kích thước body (byte) | Liên quan lỗi 413 |
| `User-Agent` | Request | Phần mềm gửi request | Phân tích log: trình duyệt, bot, health checker |
| `Cookie` / `Set-Cookie` | Request / Response | Lưu và gửi lại phiên làm việc | Sticky session ở load balancer |
| `Cache-Control` | Response | Cho phép cache bao lâu | Nội dung cũ "không cập nhật" sau khi deploy |
| `Location` | Response | Đích chuyển hướng (với 3xx) hoặc tài nguyên mới tạo (201) | Debug redirect sai/vòng tròn |
| `X-Forwarded-For` | Request | Chuỗi IP: client gốc → các proxy đã đi qua | Sau proxy, app chỉ thấy IP của proxy; IP thật của người dùng nằm ở header này |
| `X-Forwarded-Proto` | Request | Giao thức gốc client dùng (`http`/`https`) | App sau proxy kết thúc TLS cần biết request gốc là HTTPS để tạo link/redirect đúng |
| `X-Real-IP` | Request | IP client (quy ước của Nginx) | Như trên, một giá trị duy nhất |

Ba header `X-Forwarded-*`/`X-Real-IP` do **reverse proxy thêm vào** — bạn sẽ tự cấu hình chúng ở [bài 07](07-load-balancing-reverse-proxy.md).

### 4.6. 🟨 Keep-alive, HTTP/2, HTTP/3

- **HTTP/1.1 keep-alive** (giữ kết nối): một kết nối TCP dùng lại cho **nhiều** request, tránh bắt tay lại mỗi lần. Mặc định của HTTP/1.1.
- **HTTP/2**: nhiều request chạy song song trên **một** kết nối (multiplexing), header được nén, định dạng nhị phân. Trình duyệt chỉ dùng HTTP/2 qua HTTPS. Phiên bản được chọn trong lúc TLS handshake (cơ chế ALPN — bạn sẽ thấy chữ `ALPN` trong `curl -v`).
- 🟦 **HTTP/3**: chạy trên **QUIC** (dựa trên UDP). Chỉ cần nhận biết.

Với DevOps: ý nghĩa của method, header, status code **không đổi** giữa các phiên bản. Thứ thay đổi là hiệu năng và cách kết nối.

### 4.7. 🟥 HTTPS bảo vệ những gì?

HTTP thuần gửi mọi thứ dạng văn bản: mật khẩu, cookie, token đều có thể bị đọc trộm bởi bất kỳ ai trên đường truyền (Wi-Fi quán cà phê, nhà mạng). HTTPS dùng **TLS** (Transport Layer Security — bảo mật tầng giao vận) để đảm bảo 3 điều:

| Đảm bảo | Nghĩa | Chống lại |
|---|---|---|
| **Bảo mật** (confidentiality) | Dữ liệu được mã hóa | Nghe lén |
| **Toàn vẹn** (integrity) | Dữ liệu không bị sửa giữa đường | Chèn quảng cáo, chèn mã độc |
| **Xác thực** (authentication) | Bạn đang nói chuyện **đúng** với `bank.com`, không phải kẻ giả mạo | Tấn công kẻ đứng giữa (man-in-the-middle) |

Điều thứ ba đến từ **chứng chỉ**. Mã hóa mà không xác thực thì vô nghĩa: bạn có thể đang mã hóa rất an toàn… với kẻ tấn công.

> "SSL" là tên cũ của TLS. Mọi phiên bản SSL đều đã lỗi thời và không an toàn; người ta vẫn quen nói "chứng chỉ SSL" nhưng thực chất đang dùng TLS.

### 4.8. 🟥 TLS handshake (đơn giản hóa)

Sau khi TCP kết nối xong, trước khi gửi request HTTP đầu tiên:

```text
 Client (curl / trình duyệt)                          Server (taskhub.example.com:443)
   │ ── ClientHello ─────────────────────────────────► │
   │    • các phiên bản TLS và bộ mã hóa tôi hỗ trợ     │
   │    • SNI: "tôi muốn nói chuyện với                 │
   │      taskhub.example.com"                          │
   │    • ALPN: "tôi nói được h2, http/1.1"             │
   │                                                    │
   │ ◄── ServerHello + Certificate + Finished ───────── │
   │    • chọn phiên bản & bộ mã hóa                    │
   │    • CHỨNG CHỈ của server (+ intermediate)         │
   │                                                    │
   │  Client KIỂM TRA chứng chỉ:                        │
   │   ① chuỗi tin cậy có dẫn tới một Root CA           │
   │     mà máy mình tin không?                         │
   │   ② tên miền có nằm trong chứng chỉ (SAN) không?   │
   │   ③ còn hạn không?                                 │
   │   → Sai bất kỳ điều nào: DỪNG, báo lỗi.            │
   │                                                    │
   │ ── Finished ──────────────────────────────────────► │
   │ ═════ HTTP request/response đã được mã hóa ════════ │
```

Hai bên cũng trao đổi thông tin để cùng tạo ra **khóa phiên** (session key) dùng mã hóa dữ liệu. Bạn không cần hiểu toán học phía sau — chỉ cần biết **chứng chỉ được kiểm tra ở đâu và kiểm tra những gì**, vì đó là nơi lỗi xảy ra.

🟨 **TLS 1.2 vs TLS 1.3:** TLS 1.3 nhanh hơn (ít vòng trao đổi hơn) và bỏ các thuật toán yếu. Ngày nay nên dùng TLS 1.2 trở lên; TLS 1.0/1.1 đã lỗi thời.

### 4.9. 🟥 Chứng chỉ X.509 và chuỗi tin cậy

**Chứng chỉ** (certificate, chuẩn X.509) giống **căn cước công dân của website**. Các trường quan trọng:

| Trường | Ý nghĩa |
|---|---|
| **Subject** (chủ thể) | Chứng chỉ cấp cho ai, ví dụ `CN=taskhub.example.com` |
| **SAN** (Subject Alternative Name — tên thay thế) | **Danh sách tên miền** chứng chỉ hợp lệ. Trình duyệt hiện đại kiểm tra **SAN**, không dựa vào CN. Có thể có wildcard `*.example.com` |
| **Issuer** (bên cấp) | Ai ký chứng chỉ này |
| **Validity** (`notBefore`, `notAfter`) | Thời hạn hiệu lực |
| **Public key** | Khóa công khai của server (cặp với **private key** chỉ server giữ — giống SSH key ở [Linux bài 05](../01-LINUX/05-packages-ssh.md)) |

**Chuỗi tin cậy (chain of trust):**

```text
 Root CA  "ISRG Root X1"         ← có sẵn trong ROOT STORE của hệ điều hành/trình duyệt
   │  ký
 Intermediate CA "R11"           ← server PHẢI gửi kèm
   │  ký
 Leaf certificate "taskhub.example.com"   ← chứng chỉ của website
```

- **CA** (Certificate Authority — tổ chức cấp chứng chỉ): bên được tin cậy để xác minh "bạn đúng là chủ tên miền này" rồi ký chứng chỉ cho bạn.
- **Root store** (kho chứng chỉ gốc): danh sách Root CA mà máy bạn tin. Trên Ubuntu nằm ở `/etc/ssl/certs/`, cung cấp bởi gói `ca-certificates`.
- **Intermediate CA** (CA trung gian): Root CA hiếm khi ký trực tiếp, mà ký cho intermediate, intermediate ký cho website. **Server phải gửi kèm intermediate** — quên gửi là lỗi "thiếu chain" rất phổ biến: trình duyệt có thể vẫn chạy (nhờ cache hoặc tự tải), nhưng `curl`, Java, ứng dụng di động sẽ báo lỗi.

> Tên CA trong sơ đồ trên chỉ để minh họa cấu trúc. Hãy xem chuỗi thật bằng `openssl s_client -showcerts` trong lab.

**SNI** (Server Name Indication — chỉ định tên server): client gửi tên miền muốn truy cập **ngay trong ClientHello**, trước khi có chứng chỉ. Nhờ vậy một IP:443 có thể phục vụ nhiều website với nhiều chứng chỉ khác nhau — giống vai trò của header `Host`, nhưng ở tầng TLS.

### 4.10. 🟨 Các loại chứng chỉ bạn sẽ gặp

| Loại | Cách có | Được tin tự động? | Dùng khi |
|---|---|---|---|
| **Self-signed** (tự ký) | Tự tạo bằng `openssl` | **Không** — mọi client báo lỗi trừ khi được chỉ định tin | Lab, môi trường nội bộ thử nghiệm |
| **Let's Encrypt** | Miễn phí, tự động gia hạn qua giao thức ACME (công cụ certbot…) | Có | Server/VM tự quản lý — dự án taskhub trên EC2 |
| **AWS Certificate Manager (ACM)** | Miễn phí khi gắn vào dịch vụ AWS (ALB, CloudFront) | Có | Khi TLS kết thúc ở load balancer AWS (Module 06) |
| CA thương mại | Mua | Có | Doanh nghiệp có yêu cầu riêng |

### 4.11. Gặp lại ở đâu

| Khái niệm trong bài | Gặp lại ở |
|---|---|
| 502/504, `X-Forwarded-*`, `Host` | Cấu hình Nginx reverse proxy ([bài 07](07-load-balancing-reverse-proxy.md)), dự án v0 (Module 04) |
| Status code | Docker `HEALTHCHECK` và Kubernetes probe dựa vào mã 2xx/3xx (Module 04, 09); ALB health check (Module 06); alert theo tỉ lệ 5xx (Module 08) |
| `curl -w` | Đo hiệu năng, script healthcheck, smoke test sau deploy trong CI/CD (Module 05) |
| TLS, chứng chỉ | HTTPS cho dự án bằng Let's Encrypt, ACM (Module 06); Ingress TLS (Module 09); quản lý private key như secret (Module 10) |
| `--resolve` | Thử server mới trước khi đổi bản ghi Route 53 (Module 06) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Trang web chậm — chậm ở đâu?

```bash
curl -o /dev/null -s -w 'dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' https://taskhub.example.com/api/tasks
```

```text
dns=0.004 tcp=0.035 tls=0.081 ttfb=2.914 total=2.920
```

Các mốc thời gian **cộng dồn** từ lúc bắt đầu. DNS 4ms, kết nối TCP xong ở 35ms, TLS xong ở 81ms — mạng rất ổn. Nhưng byte đầu tiên của response (TTFB — time to first byte) phải tới 2,9 giây → **app (hoặc database) xử lý chậm**. Không cần đổ lỗi cho mạng hay nhà cung cấp cloud.

### Ví dụ 2: Chuyển sang server mới mà không cần đổi DNS

Bạn dựng EC2 mới ở IP `13.250.10.20` và muốn kiểm tra nó phục vụ đúng `taskhub.example.com` (đúng chứng chỉ, đúng nội dung) **trước khi** sửa bản ghi DNS:

```bash
curl -sv --resolve taskhub.example.com:443:13.250.10.20 https://taskhub.example.com/actuator/health -o /dev/null
```

`--resolve` bắt curl dùng IP bạn chỉ định cho tên miền đó, nhưng vẫn gửi đúng SNI và `Host` — y như người dùng thật sẽ thấy sau khi đổi DNS.

### Ví dụ 3: Redirect vòng tròn sau khi thêm HTTPS

Cấu hình: Nginx nhận HTTPS từ người dùng, **kết thúc TLS** (giải mã), rồi chuyển request sang app bằng HTTP thường. App được cấu hình "bắt buộc HTTPS": thấy request đến bằng HTTP → redirect sang `https://...` → người dùng lại vào Nginx → Nginx lại chuyển HTTP cho app → app lại redirect… Trình duyệt báo `ERR_TOO_MANY_REDIRECTS`.

Cách sửa: Nginx gửi kèm `X-Forwarded-Proto: https`, và app được cấu hình **tin** header này (Spring Boot có thuộc tính `server.forward-headers-strategy` cho việc đó — sẽ cấu hình ở dự án). Bạn sẽ thấy `curl -IL` in ra chuỗi `301 → 301 → 301…` cùng một `Location`.

---

## 6. Sơ đồ kiến trúc

### 6.1. Request HTTPS qua reverse proxy — ai sinh ra lỗi gì

```text
Trình duyệt ──HTTPS──► Nginx (:443, giữ chứng chỉ, kết thúc TLS) ──HTTP──► Spring Boot (:8080) ──► PostgreSQL
     │                     │                                                 │
 lỗi chứng chỉ        413 body quá lớn                                   500 exception
 (TLS, chưa tới       502 không kết nối được app / app đóng kết nối      400/401/403/404 do logic app
  HTTP)               504 app trả lời quá chậm
```

### 6.2. Mốc thời gian của `curl -w`

```text
0 ──► time_namelookup ──► time_connect ──► time_appconnect ──► time_starttransfer ──► time_total
      [DNS xong]          [TCP xong]       [TLS xong]          [byte đầu tiên về]     [tải xong]
       └─ bài 03 ─┘        └─ bài 05 ─┘     └─ bài này ─┘       └── app xử lý ──┘
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `curl -v <url>` | Xem toàn bộ quá trình: kết nối, TLS, request, response header | 🟥 |
| `curl -I <url>` | Chỉ lấy header (gửi HEAD) | 🟥 |
| `curl -L <url>` | Đi theo redirect | 🟥 |
| `curl -o /dev/null -s -w '<định dạng>' <url>` | Đo status code và thời gian | 🟥 |
| `curl -X POST -H ... -d ... <url>` | Gửi request có method/header/body | 🟥 |
| `curl -H "Host: ..." <url>` | Ghi đè header Host | 🟨 |
| `curl --resolve <host>:<port>:<ip> <url>` | Giả lập DNS cho một request | 🟨 |
| `curl -k` | Bỏ qua kiểm tra chứng chỉ — ⚠️ chỉ để chẩn đoán | 🟨 |
| `nc -l <port>` | Server giả, in ra request thô | 🟨 |
| `openssl s_client -connect <host>:443 -servername <host>` | Xem TLS handshake và chứng chỉ server gửi | 🟥 |
| `openssl x509 -noout -subject -issuer -dates -ext subjectAltName` | Đọc các trường của chứng chỉ | 🟥 |
| `openssl req -x509 ...` | Tạo chứng chỉ self-signed | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa** (curl 8.5.0 và OpenSSL 3.0.13 của Ubuntu 24.04 — vài dòng `*` của `curl -v` có thể khác chút giữa các bản curl). IP, ngày tháng, tên CA, bộ mã hóa trên máy bạn sẽ khác.

### `curl -v` — đọc từng dòng

```bash
curl -v https://github.com -o /dev/null
```

```text
*   Trying 20.205.243.166:443...
* Connected to github.com (20.205.243.166) port 443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: /etc/ssl/certs
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256
* ALPN, server accepted to use h2
* Server certificate:
*  subject: CN=github.com
*  start date: Feb  5 00:00:00 2026 GMT
*  expire date: Feb  5 23:59:59 2027 GMT
*  subjectAltName: host "github.com" matched cert's "github.com"
*  issuer: C=GB; O=Sectigo Limited; CN=Sectigo ECC Domain Validation Secure Server CA
*  SSL certificate verify ok.
> GET / HTTP/2
> Host: github.com
> user-agent: curl/8.5.0
> accept: */*
>
< HTTP/2 200
< server: GitHub.com
< content-type: text/html; charset=utf-8
< cache-control: max-age=0, private, must-revalidate
```

| Ký hiệu đầu dòng | Nghĩa |
|---|---|
| `*` | Thông tin của curl: DNS, kết nối TCP, TLS, chứng chỉ |
| `>` | Những gì curl **gửi đi** (request) |
| `<` | Những gì curl **nhận về** (response) |

Đọc theo các tầng ở [bài 01](01-osi-tcpip-model.md): `Trying` / `Connected` = TCP ✅ → `TLS handshake` + `SSL certificate verify ok` = TLS ✅ (đủ ba kiểm tra: chain, tên, hạn) → `ALPN ... h2` = thỏa thuận dùng HTTP/2 → `>` request → `<` response 200. Một lỗi xuất hiện ở dòng nào cho biết **tầng nào** hỏng.

`-o /dev/null` vứt body (HTML) đi để màn hình chỉ còn phần cần đọc.

### `curl -I`, `-L`

```bash
curl -I http://github.com
```

```text
HTTP/1.1 301 Moved Permanently
Content-Length: 0
Location: https://github.com/
```

- `-I`: gửi `HEAD`, chỉ in header. Nhanh, hay dùng để kiểm tra một URL sống hay chết. (Một số app không hỗ trợ HEAD đúng cách — khi đó dùng `-s -o /dev/null -w '%{http_code}'` với GET.)
- `-L`: tự đi theo header `Location`. Kết hợp `-IL` để thấy **cả chuỗi** redirect — công cụ số một để debug redirect vòng tròn.

### `curl -w` — đo status code và thời gian

```bash
curl -o /dev/null -s -w '%{http_code} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' https://github.com
```

```text
200 dns=0.012 tcp=0.051 tls=0.112 ttfb=0.398 total=0.455
```

| Biến | Thời điểm (tính từ lúc bắt đầu, đơn vị giây) |
|---|---|
| `%{http_code}` | Status code của response |
| `%{time_namelookup}` | Phân giải DNS xong |
| `%{time_connect}` | Kết nối TCP xong |
| `%{time_appconnect}` | TLS handshake xong (bằng 0 nếu là HTTP thường) |
| `%{time_starttransfer}` | Nhận byte đầu tiên của response (TTFB) |
| `%{time_total}` | Toàn bộ request xong |

Thời gian **từng giai đoạn** = hiệu số giữa hai mốc liên tiếp. Ví dụ thời gian app xử lý ≈ `ttfb − tls`.

| Tham số | Ý nghĩa |
|---|---|
| `-o /dev/null` | Không in body |
| `-s` | Im lặng (không thanh tiến trình, không thông báo lỗi) |
| `-w '<định dạng>'` | In thông tin theo định dạng sau khi xong (write-out) |

> Cặp `-s -o /dev/null -w '%{http_code}'` là "viên gạch" của mọi script healthcheck và smoke test sau deploy.

### Gửi request có method, header, body

```bash
curl -sS -X POST http://localhost:8080/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Học bài 06"}'
```

| Tham số | Ý nghĩa |
|---|---|
| `-X POST` | Chọn method (với `-d`, curl tự dùng POST nên `-X POST` có thể bỏ) |
| `-H 'Tên: giá trị'` | Thêm/ghi đè một header; dùng nhiều lần cho nhiều header |
| `-d '<dữ liệu>'` | Body. ⚠️ Nếu không có `-H 'Content-Type: ...'`, curl gửi kèm `Content-Type: application/x-www-form-urlencoded` — app Spring Boot nhận JSON sẽ báo lỗi 415/400 |

### `-H "Host: ..."` và `--resolve`

```bash
curl -sI -H "Host: taskhub.local" http://127.0.0.1:8080/
curl -sv --resolve taskhub.example.com:443:13.250.10.20 https://taskhub.example.com/ -o /dev/null
```

- `-H "Host: ..."`: kết nối tới IP `127.0.0.1` nhưng **nói** rằng mình muốn site `taskhub.local`. Dùng để thử virtual host trên Nginx. Với HTTPS, cách này **không** sửa được SNI → chứng chỉ sẽ không khớp.
- `--resolve <tên>:<port>:<ip>`: thay DNS cho đúng tên và port đó trong request này. Đúng cả `Host`, SNI và kiểm tra chứng chỉ → cách đúng để thử HTTPS trước khi đổi DNS.

### `curl -k` — ⚠️ chỉ để chẩn đoán

`-k` (`--insecure`) bỏ qua mọi kiểm tra chứng chỉ. Dùng **tạm thời** để trả lời câu hỏi "nếu bỏ qua chứng chỉ thì app có chạy không?" (tức là lỗi chỉ nằm ở chứng chỉ). **Không bao giờ** để `-k` (hay tương đương: `verify=False`, tắt kiểm tra SSL trong Java) trong script, cấu hình hay code chạy thật: nó vô hiệu hóa đúng phần **xác thực** của TLS — mở đường cho tấn công kẻ đứng giữa.

Cách đúng khi cần tin một chứng chỉ riêng (self-signed, CA nội bộ): `curl --cacert ca.crt ...` — chỉ tin đúng chứng chỉ đó.

### `openssl s_client` — xem chứng chỉ server gửi

```bash
openssl s_client -connect github.com:443 -servername github.com </dev/null 2>/dev/null | head -20
```

```text
CONNECTED(00000003)
---
Certificate chain
 0 s:CN = github.com
   i:C = GB, O = Sectigo Limited, CN = Sectigo ECC Domain Validation Secure Server CA
 1 s:C = GB, O = Sectigo Limited, CN = Sectigo ECC Domain Validation Secure Server CA
   i:C = US, ST = New Jersey, L = Jersey City, O = The USERTRUST Network, CN = USERTrust ECC Certification Authority
---
...
Verify return code: 0 (ok)
```

| Tham số / dòng | Ý nghĩa |
|---|---|
| `-connect host:port` | Kết nối TLS tới đâu |
| `-servername host` | Giá trị **SNI** gửi đi. Theo [tài liệu OpenSSL](https://docs.openssl.org/3.0/man1/openssl-s_client/), nếu bỏ qua thì OpenSSL lấy từ tên trong `-connect` khi đó là tên miền; khi bạn kết nối bằng IP thì **phải** đặt `-servername` |
| `-showcerts` | In **toàn bộ** chứng chỉ server gửi (dạng PEM). Lưu ý: đây là danh sách server gửi, chưa phải chuỗi đã được xác minh |
| `</dev/null` | Gửi "hết dữ liệu" ngay để lệnh tự thoát, không chờ bạn gõ |
| `s:` / `i:` | **s**ubject / **i**ssuer của từng chứng chỉ trong chain. Chứng chỉ số 0 là leaf; `i:` của số 0 phải trùng `s:` của số 1 — đó là "mắt xích" |
| `Verify return code: 0 (ok)` | Kiểm tra thành công. Khác 0 → đọc mô tả bên cạnh (hết hạn, self-signed, thiếu issuer…) |

### `openssl x509` — đọc các trường của chứng chỉ

```bash
openssl s_client -connect github.com:443 -servername github.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

```text
subject=CN = github.com
issuer=C = GB, O = Sectigo Limited, CN = Sectigo ECC Domain Validation Secure Server CA
notBefore=Feb  5 00:00:00 2026 GMT
notAfter=Feb  5 23:59:59 2027 GMT
X509v3 Subject Alternative Name:
    DNS:github.com, DNS:www.github.com
```

| Tham số | Ý nghĩa |
|---|---|
| `-noout` | Không in lại chứng chỉ dạng mã hóa |
| `-subject` / `-issuer` | Chủ thể / bên cấp |
| `-dates` | `notBefore` / `notAfter` — **hạn dùng**: thông tin số một cần giám sát |
| `-ext subjectAltName` | Danh sách tên miền hợp lệ |
| `-in file.crt` | Đọc từ file thay vì từ stdin |

🟨 Kiểm tra chứng chỉ còn hạn ít nhất N giây: `openssl x509 -noout -checkend 2592000 -in cert.crt` (2592000 giây = 30 ngày) — exit code 0 nếu còn hạn sau 30 ngày, 1 nếu sắp/đã hết hạn. Dùng trong script cảnh báo.

### `openssl req -x509` — tạo chứng chỉ self-signed

```bash
mkdir -p ~/devops-lab/02-networking/tls && cd ~/devops-lab/02-networking/tls
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout taskhub.key -out taskhub.crt -days 30 \
  -subj "/CN=taskhub.local" \
  -addext "subjectAltName=DNS:taskhub.local,DNS:localhost,IP:127.0.0.1"
chmod 600 taskhub.key
```

| Tham số | Ý nghĩa |
|---|---|
| `req -x509` | Tạo luôn chứng chỉ tự ký (thay vì tạo yêu cầu gửi CA ký) |
| `-newkey rsa:2048` | Tạo private key mới, thuật toán RSA 2048 bit |
| `-nodes` | Không đặt mật khẩu cho private key (để web server tự đọc được khi khởi động) — vì vậy phải bảo vệ file bằng quyền `600` |
| `-keyout` / `-out` | File private key / file chứng chỉ |
| `-days 30` | Hạn dùng |
| `-subj "/CN=..."` | Subject, khỏi phải trả lời câu hỏi tương tác |
| `-addext "subjectAltName=..."` | Thêm SAN — **bắt buộc** để client hiện đại chấp nhận tên miền |

> ⚠️ File `.key` là **private key** — bí mật như mật khẩu. Không commit lên Git, không gửi qua chat. Bộ chứng chỉ này sẽ được dùng lại ở lab Nginx của [bài 07](07-load-balancing-reverse-proxy.md).

---

## 9. Bài thực hành từng bước

**Lab: Nhìn tận mắt HTTP và TLS** · `[WSL]` · ~90 phút

Ghi câu trả lời vào `~/devops-lab/02-networking/lab06-answers.md`. Kiểm tra công cụ: `curl --version`, `openssl version`, `nc -h 2>&1 | head -1` (thiếu `nc` thì `sudo apt install netcat-openbsd`).

### Bước 1 — Xem request từ phía server bằng `python3 -m http.server`

```bash
mkdir -p ~/devops-lab/02-networking/web && cd ~/devops-lab/02-networking/web
echo "<h1>taskhub lab 06</h1>" > index.html
python3 -m http.server 8080 --bind 127.0.0.1
```

Terminal khác:

```bash
curl -s http://127.0.0.1:8080/
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/khong-co.html
curl -sI http://127.0.0.1:8080/
```

❓ Terminal của server in ra gì cho mỗi request? Request thứ hai trả mã gì? Lệnh `-I` gửi method nào (nhìn log server)?

Dừng server bằng `Ctrl+C`.

### Bước 2 — `nc` làm server giả: thấy chính xác curl gửi gì

```bash
nc -l 9999
```

Terminal khác:

```bash
curl -s --max-time 3 "http://127.0.0.1:9999/api/tasks?status=TODO" -H "Accept: application/json"
```

❓ Chép nguyên văn request mà `nc` in ra. Chỉ ra method, path, query string, version, từng header và **dòng trống**.

Lặp lại (chạy lại `nc -l 9999` trước mỗi lần) với:

```bash
curl -s --max-time 3 http://127.0.0.1:9999/api/tasks -d '{"title":"x"}'
curl -s --max-time 3 http://127.0.0.1:9999/api/tasks -H 'Content-Type: application/json' -d '{"title":"x"}'
```

❓ Hai request khác nhau ở header nào? Vì sao điều đó quan trọng với app Spring Boot?

**Thử đóng vai server:** chạy lại `nc -l 9999`, chạy `curl -v http://127.0.0.1:9999/` (không có `--max-time`), rồi gõ vào terminal của `nc`:

```text
HTTP/1.1 418 I'm a teapot
Content-Length: 6

hello
```

(gõ Enter sau mỗi dòng, kể cả dòng trống; sau chữ `hello` nhấn `Ctrl+C` nếu curl chưa thoát). ❓ curl hiển thị gì? Bạn vừa tự tay viết một HTTP response.

### Bước 3 — Phân tích `curl -v` một trang HTTPS thật

```bash
curl -v https://github.com -o /dev/null 2>&1 | grep -E '^\*  (subject|issuer|expire|subjectAltName)|SSL connection|ALPN, server|^< HTTP|^> (GET|Host)'
```

❓ Phiên bản TLS? HTTP/1.1 hay HTTP/2? Chứng chỉ cấp cho ai, ai cấp, hết hạn khi nào?

### Bước 4 — Đo thời gian từng giai đoạn

```bash
for url in https://github.com https://www.google.com https://ubuntu.com; do
  curl -o /dev/null -s -w "%{http_code} dns=%{time_namelookup} tcp=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}  $url\n" "$url"
done
```

❓ Với mỗi site, tính thời gian của từng giai đoạn (DNS, TCP, TLS, phía server). Giai đoạn nào chiếm nhiều thời gian nhất? Chạy lại lần hai — `dns` thay đổi thế nào? Vì sao? (Gợi ý: cache DNS — [bài 03](03-dns-dhcp.md).)

### Bước 5 — Đọc chứng chỉ và chuỗi tin cậy

```bash
openssl s_client -connect github.com:443 -servername github.com </dev/null 2>/dev/null | grep -E '^ [0-9] (s|i):|^   i:|Verify return code'
openssl s_client -connect github.com:443 -servername github.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

❓ Chain có mấy chứng chỉ? Chứng chỉ root có được server gửi không? Vì sao không cần gửi? Root CA cuối chuỗi có nằm trong `/etc/ssl/certs/` không? (Thử `ls /etc/ssl/certs | grep -i <một từ trong tên CA>`.)

### Bước 6 — Tái hiện lỗi chứng chỉ bằng badssl.com

[badssl.com](https://badssl.com/) cung cấp các tên miền có **chứng chỉ cố tình sai** để thử nghiệm:

```bash
for h in expired wrong.host self-signed untrusted-root incomplete-chain; do
  echo "== $h.badssl.com"
  curl -sS -o /dev/null "https://$h.badssl.com/" ; echo "exit=$?"
done
```

❓ Điền bảng: tên miền | thông báo lỗi của curl | exit code | lỗi thuộc kiểm tra nào trong 3 kiểm tra ở mục 4.8 (chain, tên, hạn).

Chạy thêm với `-k` cho một tên miền: `curl -sk -o /dev/null -w '%{http_code}\n' https://expired.badssl.com/`. ❓ Kết quả nói lên điều gì? Vì sao không được dùng `-k` trong script thật?

Mở thử các trang trên bằng trình duyệt. ❓ `incomplete-chain` có báo lỗi trên trình duyệt không? So sánh với curl và giải thích.

### Bước 7 — Tạo chứng chỉ self-signed và thử với một server TLS

Tạo chứng chỉ theo đúng lệnh ở [mục 8](#openssl-req--x509--tạo-chứng-chỉ-self-signed), rồi:

```bash
cd ~/devops-lab/02-networking/tls
openssl x509 -noout -subject -issuer -dates -ext subjectAltName -in taskhub.crt
openssl s_server -accept 8443 -cert taskhub.crt -key taskhub.key -www
```

Terminal khác:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://localhost:8443/ ; echo "exit=$?"
curl -sS -o /dev/null -w '%{http_code}\n' --cacert ~/devops-lab/02-networking/tls/taskhub.crt https://localhost:8443/ ; echo "exit=$?"
curl -sS -o /dev/null -w '%{http_code}\n' --cacert ~/devops-lab/02-networking/tls/taskhub.crt https://127.0.0.1:8443/ ; echo "exit=$?"
```

❓ Vì sao `subject` và `issuer` của chứng chỉ giống nhau? Lệnh nào thành công, lệnh nào lỗi, vì sao? Nếu bỏ phần `IP:127.0.0.1` trong SAN thì lệnh thứ ba sẽ ra sao?

Dừng `s_server` bằng `Ctrl+C`. **Giữ lại** thư mục `tls/` cho bài 07.

### Bước 8 — Commit

```bash
cp ~/devops-lab/02-networking/lab06-answers.md ~/devops-journey/week05/
cd ~/devops-journey && git add week05/lab06-answers.md
git commit -m "docs(network): lab 06 - http, curl, tls certificates"
git push
```

> ⚠️ **Không** commit thư mục `tls/` (có private key). Nếu repo `devops-journey` nằm gần đó, thêm `*.key` vào `.gitignore`.

---

## 10. Kết quả mong đợi

- **Bước 1:** server in mỗi request một dòng dạng `127.0.0.1 - - [31/Oct/2026 10:15:02] "GET / HTTP/1.1" 200 -`. Request thứ hai trả `404`. Lệnh `-I` gửi `HEAD`.
- **Bước 2:** `nc` in ra (minh họa):

  ```text
  GET /api/tasks?status=TODO HTTP/1.1
  Host: 127.0.0.1:9999
  User-Agent: curl/8.5.0
  Accept: application/json

  ```

  Với `-d` không có `-H`, request là `POST` kèm `Content-Type: application/x-www-form-urlencoded` và `Content-Length: 13`; khi thêm header thì là `Content-Type: application/json`. App Spring Boot mong nhận JSON sẽ từ chối request đầu (thường là 415 Unsupported Media Type). Khi tự viết response, curl hiển thị `< HTTP/1.1 418 I'm a teapot` và body `hello`.
- **Bước 3:** TLS 1.3 (hoặc 1.2), HTTP/2 (`ALPN, server accepted to use h2`), chứng chỉ `CN=github.com`, issuer là một CA thương mại, ngày hết hạn trong tương lai.
- **Bước 4:** với các site lớn, phần lớn thời gian thường nằm ở TCP + TLS (do khoảng cách địa lý) hoặc phía server. Lần chạy thứ hai `dns` nhỏ hơn hẳn nhờ cache DNS.
- **Bước 5:** chain thường có 2 chứng chỉ (leaf + intermediate). Root **không** được gửi vì client đã có sẵn root trong root store — chính root store là "điểm neo" của niềm tin, gửi root qua mạng thì cũng chẳng chứng minh được gì.
- **Bước 6** (thông báo có thể khác chữ tùy phiên bản):

| Tên miền | Lỗi curl (minh họa) | Exit | Kiểm tra bị hỏng |
|---|---|---|---|
| expired | `SSL certificate problem: certificate has expired` | 60 | Hạn |
| wrong.host | `SSL: no alternative certificate subject name matches target host name 'wrong.host.badssl.com'` | 60 | Tên (SAN) |
| self-signed | `SSL certificate problem: self-signed certificate` | 60 | Chain (không dẫn tới root tin cậy) |
| untrusted-root | `SSL certificate problem: self-signed certificate in certificate chain` | 60 | Chain (root không có trong root store) |
| incomplete-chain | `SSL certificate problem: unable to get local issuer certificate` | 60 | Chain (thiếu intermediate) |

  Với `-k`, curl nhận được mã `200`: **app vẫn chạy bình thường, vấn đề nằm hoàn toàn ở chứng chỉ**. Đó là giá trị chẩn đoán của `-k`; nhưng để nó trong script là tắt luôn khả năng phát hiện kẻ giả mạo. Trình duyệt thường **không** báo lỗi `incomplete-chain` vì có thể đã cache intermediate hoặc tự tải về — đây là lý do lỗi thiếu chain hay "lọt" qua kiểm thử bằng trình duyệt nhưng làm hỏng client khác (curl, Java, app di động).
- **Bước 7:** subject = issuer vì chứng chỉ **tự ký**. Lệnh 1 lỗi self-signed (exit 60); lệnh 2 và 3 thành công (`200`) vì `--cacert` chỉ định tin đúng chứng chỉ này và SAN có cả `localhost` lẫn `IP:127.0.0.1`. Bỏ `IP:127.0.0.1` khỏi SAN → lệnh 3 lỗi tên không khớp.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `curl: (60) SSL certificate problem: certificate has expired` | Chứng chỉ hết hạn — thường do gia hạn tự động hỏng | Gia hạn; kiểm tra cơ chế tự gia hạn (certbot timer); **giám sát** ngày hết hạn (Module 08) |
| `no alternative certificate subject name matches target host name` | Tên miền truy cập không có trong SAN | Cấp lại chứng chỉ có đúng tên; kiểm tra có truy cập bằng IP hoặc tên khác không |
| `unable to get local issuer certificate` | Server không gửi intermediate, hoặc máy client thiếu root CA | Cấu hình server gửi **fullchain** (leaf + intermediate); trên client cập nhật gói `ca-certificates` |
| `self-signed certificate` | Chứng chỉ tự ký / CA nội bộ chưa được tin | Môi trường thật: dùng chứng chỉ của CA tin cậy. Nội bộ: phân phối CA nội bộ cho client (`--cacert`, thêm vào root store) — không dùng `-k` |
| Java báo `PKIX path building failed` | Như hai lỗi trên, nhìn từ phía Java (truststore của JVM) | Kiểm tra chain bằng `openssl s_client -showcerts`; thêm CA vào truststore nếu là CA nội bộ |
| `ERR_TOO_MANY_REDIRECTS` | Redirect vòng tròn, thường HTTP ↔ HTTPS sau proxy | `curl -IL` để thấy vòng lặp; cấu hình `X-Forwarded-Proto` và cho app tin header đó |
| `400 Bad Request` khi gửi JSON | Thiếu `Content-Type: application/json` hoặc JSON sai cú pháp | Kiểm tra lại bằng `nc -l` (Bước 2) |
| `413` khi upload | Giới hạn body của Nginx (mặc định 1 MB) | Tăng `client_max_body_size` ([bài 07](07-load-balancing-reverse-proxy.md)) |
| Chứng chỉ đúng nhưng `openssl s_client` tới IP lại ra chứng chỉ khác | Không gửi SNI khi kết nối bằng IP → server trả chứng chỉ mặc định | Luôn thêm `-servername <tên miền>` |
| Lỗi TLS ngẫu nhiên về "not yet valid" | Đồng hồ máy client/server lệch | Kiểm tra giờ (`date`, `timedatectl`), đồng bộ NTP |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Đọc log truy cập của web server

Mỗi request HTTP thường được ghi một dòng trong **access log**. Ví dụ định dạng `combined` của Nginx (bạn đã phân tích ở [Linux bài 02](../01-LINUX/02-essential-commands-text.md)):

```text
203.0.113.7 - - [31/Oct/2026:10:21:44 +0700] "POST /api/tasks HTTP/1.1" 502 157 "-" "curl/8.5.0"
│                │                            │                          │   │    │     └ User-Agent
│                │                            │                          │   │    └ Referer
│                │                            │                          │   └ số byte trả về
│                │                            │                          └ status code
│                │                            └ dòng request: method, path, version
│                └ thời điểm
└ IP client (hoặc IP của proxy/load balancer phía trước!)
```

Đếm nhanh tỉ lệ status code để biết hệ thống có đang lỗi không:

```bash
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn
```

Thấy `502`/`504` tăng đột biến → mở **error log** của proxy (bài 07) để xem lý do cụ thể (`connect() failed (111: Connection refused) while connecting to upstream`, `upstream timed out`…). Thấy `500` → mở **log của app** tìm stack trace.

### 12.2. Quy trình debug "trang web lỗi"

```text
1. Tái hiện bằng curl -v (không dùng trình duyệt: trình duyệt có cache, extension, tự sửa lỗi).
2. Lỗi trước dòng "Connected"?     → DNS / TCP: quay lại bài 03, 05.
3. Lỗi ở phần TLS / certificate?   → openssl s_client -servername ... ; đọc Verify return code.
                                      Thử -k: nếu chạy được → lỗi CHỈ ở chứng chỉ.
4. Có response (< HTTP/...)?        → đọc status code theo bảng mục 4.4:
                                      4xx → request/quyền; 500 → log app; 502/504 → log proxy + app.
5. Chậm?                            → curl -w, xác định giai đoạn chậm.
6. Redirect lạ?                     → curl -IL, xem chuỗi Location.
7. Ghi vào troubleshooting-journal.md.
```

### 12.3. Exit code của curl liên quan TLS

| Exit | Nghĩa |
|---|---|
| `35` | Lỗi trong quá trình TLS handshake (ví dụ không thỏa thuận được phiên bản/bộ mã hóa, server không nói TLS) |
| `60` | Không xác minh được chứng chỉ của server (hết hạn, sai tên, chain không tin cậy) |

Kết hợp với bảng exit code ở [bài 05](05-tcp-udp-ports-firewall.md#curl---connect-timeout--thử-kết-nối-http-có-giới-hạn-thời-gian) (6 = DNS, 7 = kết nối, 28 = timeout), chỉ một con số đã cho biết lỗi ở tầng nào — rất tiện trong script.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Liệt kê các bước từ khi gõ `https://taskhub.example.com/api/tasks` đến khi nhận được response, gắn mỗi bước với bài học tương ứng.
2. Một HTTP request gồm những phần nào? Dòng trống trong request có vai trò gì?
3. HTTP "stateless" nghĩa là gì? Điều này liên quan thế nào đến việc chạy nhiều bản sao app sau load balancer?
4. Idempotent là gì? Vì sao cấu hình tự động gửi lại (retry) cho request `POST` nguy hiểm?
5. Phân biệt 401 và 403.
6. Phân biệt 500, 502, 503, 504: ai sinh ra, nên đọc log ở đâu trước?
7. Vì sao một địa chỉ IP có thể phục vụ nhiều website? Ở tầng HTTP và tầng TLS, thông tin nào giúp server biết client muốn site nào?
8. HTTPS đảm bảo 3 điều gì? Vì sao mã hóa mà không xác thực thì vô nghĩa?
9. Trong TLS handshake, client kiểm tra chứng chỉ theo 3 tiêu chí nào?
10. Intermediate certificate là gì? Vì sao lỗi thiếu intermediate hay không bị phát hiện khi thử bằng trình duyệt?
11. Vì sao server không cần gửi chứng chỉ root?
12. `curl -k` dùng khi nào và vì sao không được để trong script chạy thật? Cách đúng để tin một chứng chỉ self-signed là gì?
13. `-H "Host: ..."` và `--resolve` khác nhau thế nào khi thử một website HTTPS?
14. Bạn có `ttfb=3.1` và `tls=0.09`. Kết luận gì?
15. Vì sao app đứng sau proxy kết thúc TLS lại cần header `X-Forwarded-Proto`?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/06-solutions.md](solutions/06-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Script kiểm tra hạn chứng chỉ.** Viết `cert-check.sh` nhận danh sách tên miền qua tham số, in ra với mỗi tên miền: ngày hết hạn và **số ngày còn lại**; exit code khác 0 nếu có tên miền còn dưới `WARN_DAYS` ngày (biến môi trường, mặc định 21). Gợi ý: `openssl s_client ... | openssl x509 -noout -enddate`, `date -d ... +%s`. Thử với `github.com` và `expired.badssl.com`.

**Bài 2 — Đọc response.** Giải thích từng dòng và đưa ra **giả thuyết** về hệ thống phía sau cho mỗi response sau (lấy bằng `curl -sI`):

```text
(a) HTTP/1.1 301 Moved Permanently
    Server: nginx
    Location: https://taskhub.example.com/

(b) HTTP/1.1 502 Bad Gateway
    Server: nginx/1.24.0 (Ubuntu)

(c) HTTP/2 403
    server: AmazonS3
    content-type: application/xml

(d) HTTP/1.1 503 Service Temporarily Unavailable
    Server: awselb/2.0
```

**Bài 3 — Healthcheck bằng curl.** Viết một dòng lệnh (hoặc hàm Bash) trả exit code `0` chỉ khi URL trả status `2xx` trong vòng 5 giây, ngược lại trả `1` và in ra lý do (status code hoặc exit code của curl). Dùng lại được cho Docker `HEALTHCHECK` sau này. Thử với `https://github.com`, `https://github.com/khong-ton-tai-xyz`, `http://127.0.0.1:1`.

**Bài 4 — Chuỗi redirect.** Dùng `curl -sIL -o /dev/null -w ...` hoặc `curl -sIL` để in ra toàn bộ chuỗi redirect khi truy cập `http://github.com` và `http://www.github.com`. Có bao nhiêu bước? Mỗi bước status nào, `Location` nào? Thiết kế một chuỗi redirect **tối ưu** cho `taskhub.example.com` (HTTP → HTTPS, `www` → không `www`) với số bước ít nhất.

**Bài 5 — SNI.** Dùng `dig +short github.com` (hoặc `getent hosts`) lấy IP của github.com. So sánh kết quả `openssl s_client -connect <IP>:443` **có** và **không có** `-servername github.com` (xem `subject` và `Verify return code`). Giải thích sự khác biệt. Điều này liên quan gì tới việc một IP phục vụ nhiều website?

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Nhìn output `curl -v` bất kỳ, bạn chỉ ra được tầng nào thành công, tầng nào lỗi.
- [ ] Nghe "lỗi 502" hay "lỗi 504", bạn nói ngay được ai sinh ra nó và mở log nào trước.
- [ ] Giải thích được chuỗi tin cậy và vì sao thiếu intermediate gây lỗi ở curl nhưng không ở trình duyệt.
- [ ] Tự viết tay được một HTTP request và response hợp lệ (Bước 2).
- [ ] Tự tạo được chứng chỉ self-signed có SAN đúng và giải thích từng tham số.
- [ ] Làm xong Bài tập 1 và 2 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [MDN — Overview of HTTP](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Overview) | Tổng quan HTTP, dễ đọc | 2026-10-31 |
| [MDN — HTTP response status codes](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status) | Tra cứu status code | 2026-10-31 |
| [curl man page](https://curl.se/docs/manpage.html) | Mọi tham số curl, gồm biến của `-w` | 2026-10-31 |
| [OpenSSL — openssl-s_client](https://docs.openssl.org/3.0/man1/openssl-s_client/) | `-connect`, `-servername`, `-showcerts` | 2026-10-31 |
| [badssl.com](https://badssl.com/) | Tên miền có lỗi chứng chỉ để thực hành | 2026-10-31 |
| `man openssl-x509`, `man openssl-req` (chạy trên máy) | Tham số đầy đủ | — |
