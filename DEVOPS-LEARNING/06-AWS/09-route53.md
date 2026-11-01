# 09. Route 53 — DNS trên AWS và tên miền cho taskhub

> ⏱️ ~2,5 giờ · Mức độ: 🟥 Bắt buộc (khái niệm hosted zone, record, alias, TTL, ủy quyền NS) · 🟨 Nên biết (routing policy, health check, TLS) · 🟦 Nâng cao (private hosted zone, split-view)
> Kiến thức cần có trước: [Networking 03 — DNS & DHCP](../02-NETWORKING/03-dns-dhcp.md), [Networking 06 — HTTP & TLS](../02-NETWORKING/06-http-https-tls.md), [03. VPC](03-vpc-networking.md), [04. EC2](04-ec2.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (`dig`, AWS CLI v2, `export AWS_PROFILE=taskhub`) · `[AWS Console]` · Region `ap-southeast-1` (Route 53 là dịch vụ **toàn cầu** — xem mục 4.1)
> 💰 **Chi phí:** phần lab bắt buộc (9A) **miễn phí** — chỉ dùng `dig`. Phần 9B **tùy chọn**, chỉ làm nếu bạn **đã có tên miền**: hosted zone 0,50 USD/tháng (xóa trong 12 giờ thì không tính phí). Giá kiểm tra ngày 2026-10-31.

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

- Phân biệt ba vai trò hay bị nhầm: **nhà đăng ký tên miền** (registrar), **dịch vụ DNS có thẩm quyền** (authoritative DNS — nơi chứa record) và **DNS resolver** (máy đi hỏi hộ bạn).
- Giải thích **hosted zone** (vùng được lưu trữ) là gì, khác nhau giữa **public** và **private** hosted zone.
- Đọc và tạo các record **A, AAAA, CNAME, TXT, MX, NS, SOA**; giải thích vì sao **không đặt được CNAME ở tên gốc** (zone apex) và **alias record** của Route 53 giải quyết điều đó thế nào.
- Chọn **TTL** hợp lý và biết hạ TTL **trước** khi đổi IP.
- **Ủy quyền** (delegate) một tên miền mua ở nhà đăng ký khác sang Route 53 bằng bản ghi **NS**, và tự kiểm chứng bằng `dig +trace`.
- Biết các **routing policy** chính (simple, weighted, failover, latency) và **health check** dùng để làm gì, tốn bao nhiêu.
- So sánh hai cách bật **HTTPS** cho `taskhub`: **ALB + ACM** và **Let's Encrypt trên nginx**, và giải thích vì sao với dự án này Route 53 là **tùy chọn**.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

DNS là "tầng đầu tiên" của mọi request. Khi DNS sai, mọi thứ phía sau có hoàn hảo đến đâu người dùng cũng không vào được — và lỗi DNS rất khó thấy vì nó **bị cache** ở nhiều nơi.

| Tình huống thật | Kiến thức trong bài |
|---|---|
| "Đã đổi IP server mà nửa số người dùng vẫn vào server cũ" | TTL, cache của resolver |
| "Mua tên miền ở nhà cung cấp trong nước, muốn quản lý DNS bằng Route 53" | Ủy quyền NS |
| "Trỏ `example.com` (không có `www`) vào load balancer" | Alias record ở zone apex |
| "Đưa 10% traffic sang bản mới" (canary — [Module 05 bài 05](../05-CICD/05-deployment-strategies-rollback.md)) | Weighted routing |
| "Region chính chết thì tự chuyển sang region dự phòng" | Failover routing + health check |
| "Xác minh quyền sở hữu tên miền để cấp chứng chỉ TLS" | Record TXT/CNAME xác thực (ACM, Let's Encrypt DNS-01) |
| Phỏng vấn: "Gõ URL vào trình duyệt thì chuyện gì xảy ra?" | Toàn bộ chuỗi phân giải ở mục 6 |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Ôn nhanh DNS (đã học ở Module 02)

Nếu phần này còn lạ, đọc lại [Networking 03](../02-NETWORKING/03-dns-dhcp.md) trước.

- **Resolver đệ quy** (recursive resolver — ví dụ `1.1.1.1`, `8.8.8.8`, hoặc `10.20.0.2` trong VPC) đi hỏi **thay** máy bạn, rồi **cache** câu trả lời trong khoảng **TTL** giây.
- **Máy chủ có thẩm quyền** (authoritative name server) là nơi **sở hữu** record của một vùng. Nó không đi hỏi ai, chỉ trả lời về vùng của mình.
- Việc phân giải đi theo **chuỗi ủy quyền**: root (`.`) → TLD (`.com`, `.vn`) → name server của tên miền. Mỗi tầng chỉ nói "hỏi tiếp ở đó" bằng record **NS**.

### 3.2. Ba vai trò khác nhau — đừng nhầm

| Vai trò | Làm gì | Ví dụ |
|---|---|---|
| **Registrar** (nhà đăng ký) | Bán quyền dùng tên miền theo năm; ghi vào TLD "tên miền này dùng name server nào" | Route 53 Domains, nhà đăng ký tên miền `.vn` trong nước, Namecheap… |
| **DNS hosting** (authoritative) | Lưu record A, CNAME, MX… và trả lời truy vấn | **Route 53 hosted zone**, Cloudflare DNS, DNS của chính registrar |
| **Resolver** | Hỏi hộ client, cache kết quả | ISP, `1.1.1.1`, Route 53 Resolver trong VPC |

Bạn **có thể** mua tên miền ở nơi A và để DNS ở Route 53 — chỉ cần sửa **NS** ở nơi A trỏ về Route 53 (mục 4.6). Đây là cấu hình rất phổ biến ở Việt Nam vì nhiều người mua tên miền `.vn` ở nhà đăng ký trong nước.

### 3.3. Record là gì

Một **record** (bản ghi tài nguyên — resource record) gồm 4 phần: **tên** (`api.example.com`), **loại** (`A`), **giá trị** (`203.0.113.10`), **TTL** (`300` giây). Tập record cùng tên và cùng loại gọi là **record set**.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Route 53 là gì

**Amazon Route 53** là dịch vụ DNS của AWS, gồm các phần:

1. **Domain registration** — mua/gia hạn tên miền (registrar).
2. **DNS hosting** — **hosted zone** chứa record; AWS chạy name server có thẩm quyền ở nhiều nơi trên thế giới.
3. **Health checking** — kiểm tra endpoint còn sống không, dùng cho failover.
4. **Route 53 Resolver** — resolver có sẵn trong mỗi VPC (địa chỉ "dải VPC + 2", ví dụ `10.20.0.2`, và `169.254.169.253`) — bạn đã gặp ở Module 02.

Route 53 là dịch vụ **toàn cầu**: hosted zone không thuộc region nào. Lệnh CLI vẫn chạy được dù profile đặt region `ap-southeast-1`.

Tên "53" lấy từ **cổng 53** — cổng của giao thức DNS.

### 4.2. 🟥 Hosted zone: public và private

**Hosted zone** = một "hộp chứa record" cho một tên miền (ví dụ `example.com`) hoặc tên miền con (`lab.example.com`).

| | Public hosted zone | 🟦 Private hosted zone |
|---|---|---|
| Ai hỏi được | Cả Internet | Chỉ các VPC được gắn (associate) |
| Dùng cho | Website, API công khai | Tên nội bộ: `db.internal.example.com` |
| Yêu cầu | Registrar trỏ NS về 4 name server của zone | VPC phải bật `enableDnsHostnames` **và** `enableDnsSupport` |

Khi tạo public hosted zone, Route 53 **tự tạo** 2 record:

- **NS** — 4 name server được gán cho zone này (dạng `ns-123.awsdns-45.com`, `ns-678.awsdns-12.net`, `.org`, `.co.uk`). Bốn TLD khác nhau để một TLD gặp sự cố vẫn còn đường khác.
- **SOA** (Start of Authority) — thông tin quản trị vùng, gồm TTL dùng cho **câu trả lời phủ định** (negative caching — cache cả câu trả lời "không tồn tại").

> ⚠️ **Bẫy hay gặp:** xóa zone rồi tạo lại zone cùng tên → Route 53 gán **bộ 4 NS mới**. Registrar vẫn trỏ về bộ cũ → tên miền "chết" cho tới khi bạn cập nhật NS ở registrar. Tương tự, lỡ tạo **hai** zone cùng tên thì chỉ zone có NS khớp với registrar là zone "thật" — sửa record ở zone còn lại không có tác dụng gì.

🟦 **Split-view DNS:** tạo public và private zone **cùng tên** — người ngoài Internet nhận câu trả lời của zone public, máy trong VPC nhận câu trả lời của zone private.

### 4.3. 🟥 Các loại record cần biết

| Loại | Giá trị | Dùng cho taskhub? |
|---|---|---|
| **A** | Địa chỉ IPv4 | `taskhub.example.com → <public IP EC2>` |
| **AAAA** | Địa chỉ IPv6 | Chưa dùng (VPC dự án chỉ có IPv4) |
| **CNAME** | Một **tên** khác | `www → taskhub.example.com`; record xác thực ACM |
| **TXT** | Chuỗi văn bản | Xác minh quyền sở hữu, SPF |
| **MX** | Máy chủ thư | Không dùng |
| **NS** | Name server | Tự tạo; dùng khi ủy quyền tên miền con |
| **SOA** | Thông tin vùng | Tự tạo, hiếm khi sửa |
| **CAA** 🟨 | CA nào được phép cấp chứng chỉ | `0 issue "letsencrypt.org"` |

### 4.4. 🟥 Alias record — "CNAME kiểu AWS"

Quy tắc DNS chuẩn: **không được đặt CNAME ở zone apex** (tên gốc, ví dụ `example.com` không có tiền tố), vì ở đó đã có NS và SOA, mà CNAME không được tồn tại cùng record khác.

Vấn đề: load balancer của AWS **không có IP cố định**, chỉ có một **tên** dạng `xxx.ap-southeast-1.elb.amazonaws.com`. Muốn `example.com` trỏ vào nó thì làm sao?

**Alias record** là phần mở rộng riêng của Route 53. Theo tài liệu AWS:

- Alias **đặt được ở zone apex**.
- Route 53 tự tra IP hiện tại của tài nguyên đích và **trả về record A/AAAA**. Với `dig`, bạn chỉ thấy `A`, không thấy "alias".
- Truy vấn alias tới **tài nguyên AWS** được hỗ trợ (ELB, CloudFront, S3 website, API Gateway, một record khác trong cùng zone…) **không tính phí**. CNAME thì có tính phí.
- **Không tự đặt được TTL** cho alias trỏ tới tài nguyên AWS — Route 53 dùng TTL của tài nguyên đó.

> **Alias KHÔNG trỏ thẳng được vào một EC2 instance.** Danh sách đích của alias không có EC2. Với `taskhub` (một EC2, không có load balancer), bạn dùng **record A bình thường** chứa public IP.

| | CNAME | Alias |
|---|---|---|
| Ở zone apex | ❌ | ✅ |
| Trỏ tới | Bất kỳ tên DNS nào | Chỉ một số tài nguyên AWS + record cùng zone |
| Phí truy vấn | Có | Miễn phí khi trỏ tới tài nguyên AWS |
| `dig` hiển thị | `CNAME` | `A` / `AAAA` |
| TTL | Tự đặt | Theo tài nguyên đích |

### 4.5. 🟥 TTL — đánh đổi giữa tốc độ thay đổi và tải

**TTL** (Time To Live) là số giây resolver được phép giữ câu trả lời trong cache.

| TTL | Ưu | Nhược |
|---|---|---|
| Dài (3600–86400) | Ít truy vấn → rẻ, nhanh cho người dùng | Đổi IP thì **rất lâu** mọi người mới thấy |
| Ngắn (60–300) | Đổi nhanh có hiệu lực | Nhiều truy vấn hơn (mỗi 1 triệu truy vấn đều tính tiền) |

**Quy trình chuẩn khi phải đổi IP** (ví dụ chuyển `taskhub` sang EC2 mới):

1. **Trước ít nhất một TTL cũ**: hạ TTL xuống 60 giây.
2. Chờ hết TTL cũ (để mọi cache đã nhận TTL mới).
3. Đổi giá trị record sang IP mới.
4. Giữ server cũ chạy thêm vài TTL (một số resolver không tôn trọng TTL tuyệt đối).
5. Mọi thứ ổn → nâng TTL lên lại.

### 4.6. 🟥 Ủy quyền (delegation) từ registrar bên ngoài sang Route 53

Bạn mua `example.com` ở registrar X. Muốn Route 53 quản lý DNS:

1. Tạo **public hosted zone** `example.com` trong Route 53 → ghi lại **4 NS** của zone.
2. Vào trang quản lý tên miền ở registrar X → mục **Nameservers** → thay bằng 4 NS đó.
3. Registrar cập nhật lên máy chủ TLD (`.com`). Từ giờ, khi resolver hỏi `.com` "ai giữ `example.com`?", câu trả lời là name server của Route 53.

Thời gian có hiệu lực phụ thuộc **TTL của record NS ở tầng TLD** — thường tới 1–2 ngày. Đó là lý do người ta nói "DNS propagation" (lan truyền DNS). Thực ra không có gì "lan truyền" cả: các resolver chỉ đang **đợi cache cũ hết hạn**.

**Cách an toàn hơn để học:** ủy quyền một **tên miền con**, ví dụ chỉ `lab.example.com`. Tạo zone `lab.example.com` ở Route 53, rồi ở DNS hiện tại của `example.com` thêm **record NS** cho `lab` trỏ về 4 NS của zone mới. Phần còn lại của tên miền (email, website khác) **không bị ảnh hưởng**. Lab 9B dùng cách này.

### 4.7. 🟥 Giá (kiểm tra 2026-10-31, trang giá Route 53)

| Hạng mục | Giá |
|---|---|
| Hosted zone (25 zone đầu) | **0,50 USD/zone/tháng** |
| Zone bị xóa trong vòng **12 giờ** sau khi tạo | **Không tính phí zone** (truy vấn vẫn tính) |
| Truy vấn chuẩn (1 tỷ đầu/tháng) | 0,40 USD / 1 triệu truy vấn |
| Truy vấn alias tới tài nguyên AWS | Miễn phí |
| Health check endpoint AWS (cơ bản) | 0,50 USD/tháng (trang giá ghi có thể dùng tới 50 health check endpoint AWS miễn phí — kiểm tra lại khi bạn dùng) |
| Health check endpoint ngoài AWS | 0,75 USD/tháng |
| Đăng ký tên miền | **Theo từng TLD, tính theo năm**. Credit khuyến mãi **không** dùng để trả phí tên miền |

> 💡 **Free plan:** credit của Free plan không trả được phí **đăng ký tên miền**. Nếu muốn có tên miền cho dự án, mua ở bất kỳ registrar nào bạn thấy hợp lý rồi ủy quyền NS — kết quả kỹ thuật như nhau.

### 4.8. 🟨 Routing policy — Route 53 trả lời "thông minh"

| Policy | Trả lời thế nào | Dùng khi |
|---|---|---|
| **Simple** | Một (hoặc nhiều) giá trị, như DNS thông thường | Hầu hết trường hợp — **taskhub dùng loại này** |
| **Weighted** | Chia theo trọng số, ví dụ 90/10 | **Canary** ở tầng DNS, A/B test |
| **Failover** | Bản chính khỏe thì trả bản chính, không thì trả bản dự phòng | Dự phòng giữa region/site — **cần health check** |
| **Latency** | Region có độ trễ thấp nhất tới người dùng | Ứng dụng chạy nhiều region |
| Geolocation | Theo quốc gia/châu lục của người dùng | Nội dung theo vùng, tuân thủ pháp lý |
| Multivalue answer | Nhiều IP, bỏ IP không khỏe | "Load balancing nghèo" ở tầng DNS |

**Giới hạn của canary bằng DNS** so với canary bằng load balancer ([Module 05 bài 05](../05-CICD/05-deployment-strategies-rollback.md)): DNS chia theo **truy vấn của resolver**, không theo request. Một resolver lớn (của một ISP) cache câu trả lời và trả cho hàng nghìn người → tỷ lệ thực tế lệch xa 90/10. Rollback cũng phải chờ hết TTL.

### 4.9. 🟨 Health check

Route 53 health check gửi request (HTTP/HTTPS/TCP) tới endpoint từ nhiều điểm trên thế giới. Dùng để:

- Quyết định **failover** (record chính "khỏe" hay không).
- Tạo **CloudWatch alarm** khi endpoint chết (gặp lại ở [bài 10](10-cloudwatch.md)).

Với `taskhub` một EC2, health check Route 53 chỉ có giá trị như một **giám sát từ bên ngoài** ("người dùng ở ngoài có vào được không"). Đây là điều CloudWatch metric của EC2 **không** cho biết (instance khỏe nhưng nginx chết thì metric EC2 vẫn bình thường). Bài 11 sẽ phân tích "khoảng mù" này.

### 4.10. 🟨 HTTPS cho taskhub — hai con đường

Từ [Networking 06](../02-NETWORKING/06-http-https-tls.md) bạn biết: chứng chỉ TLS gắn với **tên miền**. Không có tên miền thì không có chứng chỉ của CA công khai cho trình duyệt tin. Vì vậy **HTTPS cho taskhub phụ thuộc việc bạn có tên miền hay không**.

| | **A. ALB + ACM** | **B. Let's Encrypt trên nginx (EC2)** |
|---|---|---|
| Chứng chỉ | **ACM** (AWS Certificate Manager) — chứng chỉ public **miễn phí** khi dùng với dịch vụ tích hợp như ELB. Không lấy được private key (trừ loại "exportable" — **có phí**) | Let's Encrypt — miễn phí, private key nằm trên server của bạn |
| TLS kết thúc ở | ALB | nginx container trên EC2 |
| Gia hạn | ACM tự gia hạn | **Phải tự động hóa** (certbot + lịch chạy). Let's Encrypt đã công bố rút ngắn thời hạn chứng chỉ: 90 ngày → 64 ngày (mặc định từ 10/02/2027) → 45 ngày (16/02/2028) |
| Chi phí thêm | ALB tính theo giờ + LCU (xem [bài 08](08-elb-autoscaling.md)) | Không |
| Hợp với | Kiến trúc có load balancer (lab tuần 14) | **taskhub v3 một EC2** |

**Quyết định cho dự án:** Route 53 và HTTPS là **tùy chọn** trong v3.

- **Không có tên miền:** v3 chạy HTTP qua public IP. Ghi rõ trong README là hạn chế đã biết.
- **Có tên miền:** record A trỏ về EC2 + Let's Encrypt (cách B). Trong thiết lập của dự án, nginx chạy trong container nên plugin `certbot --nginx` (sửa file nginx trên host) **không áp dụng thẳng** được. Hướng phù hợp là `certbot certonly --webroot` với một thư mục chung mà nginx phục vụ ở `/.well-known/acme-challenge/` — để làm bài tập 🟨 (mục 14).

### 4.11. 🟥 Public IP thay đổi — DNS trỏ vào đâu?

IPv4 public **tự gán** của EC2 **đổi mỗi lần stop/start** ([bài 04](04-ec2.md)). Record A trỏ vào IP cũ sẽ thành "rác" — tệ hơn, IP đó có thể được cấp cho **khách hàng AWS khác** (rủi ro "dangling DNS" — tên miền của bạn trỏ vào server của người lạ).

Hai cách:

| Cách | Chi phí | Đánh đổi |
|---|---|---|
| **Elastic IP** — IP cố định gắn vào instance | 0,005 USD/giờ, **tính cả khi instance đang stop** (IP "idle" vẫn tính tiền) | Đơn giản; nhưng nếu bạn stop instance khi không học để tiết kiệm, EIP vẫn tốn ~3,6 USD/tháng |
| **Cập nhật record A mỗi lần start** (script gọi `aws route53 change-resource-record-sets`) | Gần như 0 | Thêm một bước tự động hóa; TTL phải ngắn (60) |

Với lịch "chỉ bật khi học" của dự án, cách 2 rẻ hơn. Nếu không có tên miền, vấn đề này không tồn tại — chỉ cần cập nhật biến `APP_URL` của GitHub (v3) khi IP đổi.

### 4.12. Gặp lại ở đâu

| Kiến thức | Gặp lại |
|---|---|
| TTL, cache | Đổi IP khi chuyển server; Kubernetes Service DNS (Module 09) |
| Alias tới ALB | Lab ALB tuần 14 ([bài 08](08-elb-autoscaling.md)) |
| Weighted routing | Canary — [Module 05 bài 05](../05-CICD/05-deployment-strategies-rollback.md) |
| Health check từ bên ngoài | Giám sát "blackbox" — Module 08 |
| Record do Terraform quản lý | `aws_route53_record` — Module 07 (v4) |
| Dangling DNS | Rà soát bảo mật — Module 10 |

---

## 5. Ví dụ thực tế

**Chuyển server không gián đoạn.** Một team chuyển API từ EC2 cũ (`203.0.113.10`) sang EC2 mới (`203.0.113.50`). Record `api.example.com` đang có TTL 86400 (1 ngày).

- Thứ Hai: hạ TTL xuống 60. Vẫn trỏ IP cũ.
- Thứ Ba (sau hơn 24 giờ): mọi resolver đã nhận TTL 60. Đổi record sang IP mới. Trong vòng vài phút, phần lớn traffic sang server mới.
- Thứ Tư: log server cũ gần như không còn request → tắt server cũ, nâng TTL lên 3600.

**Nếu bỏ qua bước hạ TTL:** đổi IP ngay lúc TTL còn 86400 → một số người dùng vào server cũ tới **một ngày** sau. Nếu đã tắt server cũ, họ thấy "trang web chết" trong khi team thấy mọi thứ bình thường từ máy mình.

**Sự cố NS kinh điển.** Một bạn junior "dọn dẹp" bằng cách xóa hosted zone `example.com` rồi tạo lại với các record y hệt. Website chết. Nguyên nhân: zone mới có **bộ NS khác**, registrar vẫn trỏ về bộ cũ (đã không còn tồn tại). Sửa: cập nhật NS ở registrar và chờ TTL của NS ở TLD. Bài học: **NS của hosted zone là thứ gắn với registrar — đừng xóa zone đang dùng**.

---

## 6. Sơ đồ kiến trúc

### 6.1. Chuỗi phân giải `taskhub.example.com` khi DNS nằm ở Route 53

```text
 Trình duyệt            Resolver đệ quy             Root (.)      TLD (.com)        Route 53 (authoritative)
 (laptop)               (ISP / 1.1.1.1)
    │ taskhub.example.com?    │                         │              │                       │
    ├────────────────────────►│ (cache rỗng)            │              │                       │
    │                         ├── ".com ở đâu?" ───────►│              │                       │
    │                         │◄── NS của .com ─────────┤              │                       │
    │                         ├── "example.com ở đâu?" ───────────────►│                       │
    │                         │◄── NS: ns-123.awsdns-45.com … ─────────┤  ← registrar đã ghi   │
    │                         ├── "taskhub.example.com A?" ───────────────────────────────────►│
    │                         │◄── A 203.0.113.10  TTL 60 ─────────────────────────────────────┤  ← hosted zone
    │◄── 203.0.113.10 ────────┤ (cache 60 giây)                                                │
    │
    └── TCP :80/:443 tới 203.0.113.10 → IGW → Security Group → EC2 (nginx)   ← bài 03, 04
```

### 6.2. Vị trí của Route 53 trong taskhub (tùy chọn)

```text
                     ┌──────────── Registrar (bất kỳ) ────────────┐
                     │ example.com  →  NS = 4 name server Route 53 │
                     └─────────────────────┬──────────────────────┘
                                           ▼
                     ┌──── Route 53 public hosted zone ────┐
                     │ example.com        NS, SOA (tự tạo)  │
                     │ taskhub            A   <public IP>   │ TTL 60
                     │ _acme-challenge…   TXT (nếu dùng DNS-01) │
                     └─────────────────────┬────────────────┘
                                           ▼
 Internet ──► IGW ──► taskhub-web-sg (80, 443) ──► EC2 taskhub-app ──► nginx ──► taskhub ──► postgres
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Tốn phí? |
|---|---|---|
| `dig <tên> <loại>` | Hỏi resolver mặc định | Không |
| `dig +short <tên>` | Chỉ in giá trị | Không |
| `dig +trace <tên>` | Tự đi hết chuỗi root → TLD → authoritative | Không |
| `dig @<server> <tên>` | Hỏi một server cụ thể (ví dụ name server của Route 53) | Không |
| `dig +norecurse @<ns> <tên>` | Hỏi authoritative mà không nhờ đệ quy | Không |
| `aws route53 list-hosted-zones` | Liệt kê zone | Không |
| `aws route53 list-resource-record-sets --hosted-zone-id <id>` | Xem record | Không |
| ⚠️ `aws route53 create-hosted-zone` | Tạo zone | **0,50 USD/tháng** (miễn nếu xóa trong 12 giờ) |
| ⚠️ `aws route53 change-resource-record-sets` | Tạo/sửa/xóa record | Không (bản thân record miễn phí) |
| `aws route53 get-change --id <id>` | Trạng thái thay đổi: `PENDING` → `INSYNC` | Không |
| `aws route53 test-dns-answer` | Hỏi Route 53 "zone này sẽ trả lời gì" | Không |
| ⚠️ `aws route53 delete-hosted-zone` | Xóa zone (phải xóa hết record trừ NS/SOA trước) | — |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `dig` — đọc từng phần của câu trả lời `[WSL]`

```bash
dig example.com A
```

Đầu ra (minh họa, đã rút gọn):

```text
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 41234
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; QUESTION SECTION:
;example.com.                   IN      A

;; ANSWER SECTION:
example.com.            1612    IN      A       93.184.215.14

;; Query time: 23 msec
;; SERVER: 10.255.255.254#53(10.255.255.254) (UDP)
```

| Phần | Ý nghĩa |
|---|---|
| `status: NOERROR` | Có tên này. `NXDOMAIN` = tên **không tồn tại**; `SERVFAIL` = resolver không lấy được câu trả lời (thường do authoritative lỗi hoặc DNSSEC) |
| `flags: ... ra` | `rd` = client xin đệ quy; `ra` = server hỗ trợ đệ quy. Có `aa` = câu trả lời **có thẩm quyền** (từ chính name server của zone) |
| `1612` | TTL **còn lại** trong cache. Hỏi lại sau 10 giây sẽ thấy ~1602 — bằng chứng câu trả lời đến từ cache |
| `SERVER` | Resolver đã trả lời. Trên WSL thường là IP nội bộ do WSL cấp (minh họa ở trên) |

### 8.2. `dig +trace` — tự đi chuỗi ủy quyền

```bash
dig +trace taskhub.example.com
```

Đầu ra minh họa (rút gọn, chỉ giữ dòng quan trọng):

```text
.                       518400  IN  NS  a.root-servers.net.
;; Received 239 bytes from 10.255.255.254#53 in 3 ms
com.                    172800  IN  NS  a.gtld-servers.net.
;; Received 1170 bytes from 198.41.0.4#53(a.root-servers.net) in 40 ms
example.com.            172800  IN  NS  ns-123.awsdns-45.com.
example.com.            172800  IN  NS  ns-678.awsdns-12.net.
;; Received 650 bytes from 192.5.6.30#53(a.gtld-servers.net) in 60 ms
taskhub.example.com.    60      IN  A   203.0.113.10
;; Received 72 bytes from 205.251.192.123#53(ns-123.awsdns-45.com) in 35 ms
```

Đọc từ trên xuống: root chỉ sang `.com`; `.com` chỉ sang name server `awsdns` (TTL **172800** = 2 ngày — đây chính là lý do đổi NS lâu có hiệu lực); name server Route 53 trả record A với TTL 60.

### 8.3. Hỏi thẳng name server của Route 53

```bash
dig +norecurse @ns-123.awsdns-45.com taskhub.example.com A
```

- `@ns-...` — bỏ qua resolver, hỏi thẳng authoritative.
- `+norecurse` — không xin đệ quy.

Nếu câu trả lời ở đây **đúng** mà `dig taskhub.example.com` (qua resolver) **sai** → zone đã đúng, resolver đang giữ cache cũ (hoặc registrar chưa trỏ NS đúng — kiểm tra bằng `+trace`).

### 8.4. Tạo/sửa record bằng CLI `[WSL]`

⚠️ Lệnh tạo/sửa DNS thật — chỉ chạy trên zone của bạn.

```bash
cat > /tmp/upsert-taskhub.json <<'EOF'
{
  "Comment": "taskhub A record",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "taskhub.lab.example.com",
      "Type": "A",
      "TTL": 60,
      "ResourceRecords": [{ "Value": "203.0.113.10" }]
    }
  }]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id Z0123456789ABCDEFGHIJ \
  --change-batch file:///tmp/upsert-taskhub.json
```

Đầu ra minh họa:

```json
{
    "ChangeInfo": {
        "Id": "/change/C01234567ABCDEFG",
        "Status": "PENDING",
        "SubmittedAt": "2027-01-18T03:12:45.123Z",
        "Comment": "taskhub A record"
    }
}
```

| Tham số | Ý nghĩa |
|---|---|
| `Action` | `CREATE` (lỗi nếu đã có), `DELETE` (phải khớp **chính xác** giá trị và TTL hiện tại), `UPSERT` (tạo hoặc ghi đè — dùng trong script) |
| `--hosted-zone-id` | ID zone (bắt đầu bằng `Z`), lấy từ `list-hosted-zones`. Không phải tên miền |
| `file://` | Đọc JSON từ file. Lưu ý **ba** dấu `/` khi đường dẫn tuyệt đối: `file:///tmp/...` |
| `Status: PENDING` | Đã nhận, đang đẩy tới mọi name server. `aws route53 get-change --id C01234567ABCDEFG` cho tới khi `INSYNC` (thường dưới một phút) |

### 8.5. `test-dns-answer` — hỏi Route 53 trước khi hỏi Internet

```bash
aws route53 test-dns-answer --hosted-zone-id Z0123456789ABCDEFGHIJ \
  --record-name taskhub.lab.example.com --record-type A
```

Trả về `RecordData` mà zone **sẽ** trả lời. Hữu ích khi nghi registrar/resolver: nếu `test-dns-answer` đúng thì lỗi nằm ngoài zone.

---

## 9. Bài thực hành từng bước

### 9A. 🟥 Bắt buộc — đọc DNS thật bằng `dig` (miễn phí) `[WSL]`

Mục tiêu: luyện đọc chuỗi ủy quyền, TTL, CNAME, và nhận ra tên miền nào đang dùng Route 53.

Nếu chưa có `dig`: `sudo apt install -y dnsutils` (đã làm ở Module 02).

**Bước 1 — Chuỗi ủy quyền.** Chọn 3 tên miền bạn hay dùng (một trang `.vn`, một trang `.com` lớn, một trang của trường/công ty). Với mỗi tên:

```bash
dig +trace <tên-miền> | grep -E 'IN\s+(NS|A|CNAME)\s|Received'
```

Ghi vào `week13/route53-notes.md`: TLD là gì, name server có thẩm quyền của tên miền là gì, TTL của record NS ở tầng TLD là bao nhiêu.

**Bước 2 — Tên miền nào dùng Route 53?**

```bash
for d in <tên-1> <tên-2> <tên-3> <tên-4> <tên-5>; do
  printf '%-25s ' "$d"; dig +short NS "$d" | sort | tr '\n' ' '; echo
done
```

Name server có dạng `ns-<số>.awsdns-<số>.<com|net|org|co.uk>` là Route 53. Ghi lại tên miền nào dùng Route 53, tên nào dùng nhà cung cấp khác.

❓ Vì sao một tên miền có 4 NS ở **4 TLD khác nhau**?

**Bước 3 — TTL đếm ngược.**

```bash
dig +noall +answer <một-tên-miền-bất-kỳ> A
sleep 15
dig +noall +answer <cùng-tên-miền> A
```

TTL lần 2 nhỏ hơn lần 1 khoảng 15 → câu trả lời đến từ **cache** của resolver. Hỏi thẳng authoritative (`dig +noall +answer @<một-NS-ở-bước-2> <tên> A`) → luôn thấy TTL **đầy đủ** như cấu hình.

**Bước 4 — Chuỗi CNAME.** Nhiều trang lớn dùng CDN, `www.<tên>` thường là CNAME:

```bash
dig +noall +answer www.<tên-miền-lớn>
```

Ghi lại chuỗi `CNAME → CNAME → A`. Mỗi mắt xích có TTL riêng.

**Bước 5 — Câu trả lời phủ định.**

```bash
dig khong-ton-tai-$RANDOM.<tên-miền-bất-kỳ> A
```

Quan sát `status: NXDOMAIN` và phần `AUTHORITY SECTION` có record **SOA**. Con số cuối cùng trong SOA (hoặc TTL của chính record SOA, tùy cách tính) quyết định resolver cache câu "không tồn tại" bao lâu. ❓ Vì sao điều này quan trọng khi bạn **vừa tạo** một record mới mà một số người vẫn thấy NXDOMAIN?

**Bước 6 — Đọc tài liệu.** Đọc trang "Choosing between alias and non-alias records" (link ở Nguồn tham khảo). Viết 5 dòng tóm tắt bằng lời của bạn.

### 9B. 🟨 Tùy chọn — ủy quyền tên miền con sang Route 53 (cần tên miền)

> 💰 **Ước tính chi phí:** hosted zone 0,50 USD/tháng. **Xóa zone trong 12 giờ thì không tính phí zone.** Truy vấn: vài trăm lượt khi làm lab → không đáng kể. Credit Free plan trả được phí hosted zone nhưng **không** trả phí đăng ký tên miền.
> **Điều kiện:** bạn sở hữu một tên miền (ví dụ `example.com`) và quản lý được DNS hiện tại của nó. EC2 `taskhub-app` của v2 đang chạy (để có IP trỏ tới) — nếu chưa có, dùng IP minh họa `203.0.113.10` (dải dành cho tài liệu, RFC 5737) chỉ để luyện DNS.
> Không làm phần này cũng **không ảnh hưởng** tới v3.

**Bước 1 — Tạo hosted zone cho tên miền con** ⚠️ (bắt đầu tính giờ 12 tiếng):

```bash
export AWS_PROFILE=taskhub
aws route53 create-hosted-zone \
  --name lab.example.com \
  --caller-reference "lab-$(date +%s)" \
  --hosted-zone-config Comment="taskhub lab, Project=taskhub"
```

- `--caller-reference` — chuỗi duy nhất chống tạo trùng khi gửi lại lệnh.
- Ghi lại `Id` (`/hostedzone/Z...`) và 4 tên trong `DelegationSet.NameServers`.

Gắn tag (hosted zone dùng `change-tags-for-resource`):

```bash
aws route53 change-tags-for-resource --resource-type hostedzone \
  --resource-id Z0123456789ABCDEFGHIJ \
  --add-tags Key=Project,Value=taskhub Key=Env,Value=dev Key=ManagedBy,Value=manual
```

**Bước 2 — Ủy quyền.** Ở nơi đang quản lý DNS của `example.com` (registrar hoặc DNS provider), thêm **4 record NS** tên `lab` trỏ về 4 name server ở bước 1.

**Bước 3 — Tạo record A** (JSON như mục 8.4, `Name` = `taskhub.lab.example.com`, giá trị = public IP của EC2).

**Bước 4 — Kiểm chứng theo thứ tự từ trong ra ngoài:**

```bash
aws route53 get-change --id <change-id>                                   # INSYNC?
aws route53 test-dns-answer --hosted-zone-id <zone-id> \
  --record-name taskhub.lab.example.com --record-type A                   # zone trả lời đúng?
dig +norecurse @<một-NS-của-zone> taskhub.lab.example.com A               # authoritative đúng?
dig +trace taskhub.lab.example.com                                        # chuỗi ủy quyền đi tới awsdns?
dig +short taskhub.lab.example.com                                        # resolver thường thấy chưa?
curl -sS -o /dev/null -w '%{http_code}\n' http://taskhub.lab.example.com/actuator/health   # nếu EC2 chạy
```

**Bước 5 — Mô phỏng đổi IP:** UPSERT record sang `203.0.113.50`, đo bao lâu `dig +short` (qua resolver) thấy giá trị mới. So với TTL bạn đặt.

**Bước 6 — Dọn dẹp** ⚠️ (trong vòng 12 giờ nếu muốn không tính phí zone):

```bash
# 1. Xóa record A (DELETE phải khớp đúng giá trị + TTL hiện tại)
#    → dùng JSON như 8.4 với "Action": "DELETE"
# 2. Xóa zone (chỉ còn NS và SOA mới xóa được)
aws route53 delete-hosted-zone --id Z0123456789ABCDEFGHIJ
# 3. Xóa 4 record NS "lab" ở DNS của example.com — tránh dangling delegation
# 4. Kiểm tra không còn zone nào sót
aws route53 list-hosted-zones --query 'HostedZones[].Name'
```

---

## 10. Kết quả mong đợi

- `week13/route53-notes.md` có: chuỗi ủy quyền của 3 tên miền, danh sách tên miền dùng/không dùng Route 53, bằng chứng TTL đếm ngược (hai lần `dig`), một chuỗi CNAME, một câu trả lời NXDOMAIN kèm SOA.
- Giải thích được bằng lời: "tại sao đổi NS mất tới 2 ngày còn đổi record A với TTL 60 chỉ mất 1 phút".
- (9B) `dig +trace taskhub.lab.example.com` đi tới name server `awsdns`; `curl` qua tên miền trả `200`; sau dọn dẹp `list-hosted-zones` không còn `lab.example.com.`.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách kiểm tra | Cách sửa |
|---|---|---|---|
| Tạo record xong, `dig` vẫn `NXDOMAIN` | Registrar/DNS cha chưa trỏ NS về zone; hoặc resolver cache câu phủ định | `dig +trace` dừng ở đâu? `dig @<NS-route53>` có đúng không? | Sửa NS ở registrar; chờ TTL phủ định (SOA) |
| `+trace` cho thấy NS **khác** bộ NS của zone | Zone đã bị xóa/tạo lại, hoặc có hai zone cùng tên | So `DelegationSet` của zone với kết quả `dig NS` | Cập nhật registrar theo zone đang dùng; xóa zone thừa |
| `InvalidChangeBatch ... CNAME ... at apex` | Đặt CNAME ở zone apex | — | Dùng alias (nếu đích là tài nguyên AWS) hoặc A |
| Không chọn được EC2 làm đích alias | Alias không hỗ trợ EC2 | Danh sách đích alias trong tài liệu | Dùng record A với IP (hoặc Elastic IP) |
| `InvalidChangeBatch ... values provided do not match the current values` khi DELETE | DELETE phải khớp đúng giá trị **và** TTL | `list-resource-record-sets` | Sao chép chính xác record hiện tại vào JSON |
| `HostedZoneNotEmpty` khi xóa zone | Còn record khác NS/SOA | `list-resource-record-sets` | Xóa hết record do bạn tạo trước |
| Website chết sau khi stop/start EC2 | Public IP tự gán đã đổi; record A trỏ IP cũ | So `dig +short` với IP trong console | Cập nhật record; cân nhắc Elastic IP hoặc script cập nhật (4.11) |
| Hóa đơn có 0,50 USD "HostedZone" mỗi tháng | Quên xóa zone thử nghiệm | `list-hosted-zones` | Xóa zone không dùng |
| 🟦 Private zone không phân giải trong VPC | VPC chưa bật `enableDnsHostnames`/`enableDnsSupport`, hoặc zone chưa gắn VPC | `aws ec2 describe-vpc-attribute` | Bật thuộc tính; associate VPC |

---

## 12. Đọc log và xử lý lỗi

DNS gần như không có "log" để đọc ở phía bạn. Công cụ chính là **so sánh câu trả lời ở từng tầng**. Quy trình 4 bước (từ trong ra ngoài):

```text
1. Zone có đúng không?          aws route53 test-dns-answer ...          → sai: sửa record
2. Authoritative có đúng không? dig +norecurse @ns-xxx.awsdns-xx.com ... → sai: change còn PENDING?
3. Ủy quyền có đúng không?      dig +trace ...                           → dừng/sai NS: sửa registrar
4. Resolver có đúng không?      dig @1.1.1.1 ... ; dig @8.8.8.8 ...      → khác nhau: cache, chờ TTL
```

Ví dụ phân tích (minh họa):

```text
$ dig +short taskhub.lab.example.com
203.0.113.10                         ← IP cũ
$ dig +short +norecurse @ns-123.awsdns-45.com taskhub.lab.example.com
203.0.113.50                         ← IP mới
```

→ Zone và authoritative đã đúng. Resolver đang trả câu trả lời cache. `dig taskhub.lab.example.com` (không `+short`) cho thấy TTL còn lại → biết chính xác còn phải chờ bao lâu. **Không cần sửa gì** — chỉ cần chờ (hoặc lần sau hạ TTL trước).

🟦 **Route 53 query logging** ghi mọi truy vấn tới public zone vào CloudWatch Logs — hữu ích khi điều tra, nhưng có phí lưu log. Không cần cho dự án.

Ghi các lỗi bạn gặp vào nhật ký debug theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Registrar, DNS hosting (authoritative) và resolver khác nhau thế nào? Route 53 đóng những vai nào?
2. Khi tạo public hosted zone, Route 53 tự tạo những record nào? Vì sao có 4 name server ở 4 TLD khác nhau?
3. Vì sao không đặt được CNAME ở zone apex? Alias record giải quyết thế nào?
4. Nêu 3 điểm khác nhau giữa alias và CNAME (đích, phí, cách `dig` hiển thị).
5. Vì sao không tạo được alias trỏ thẳng vào EC2 instance? Với taskhub một EC2, bạn dùng record gì?
6. TTL là gì? Mô tả quy trình đổi IP an toàn cho record đang có TTL 86400.
7. Bạn đổi NS ở registrar sang Route 53 nhưng sau 2 giờ một số người vẫn vào DNS cũ. Vì sao? Lệnh nào chứng minh?
8. Tạo hosted zone, xóa nó sau 3 giờ: có mất phí zone không? Còn truy vấn?
9. Weighted routing dùng cho canary có nhược điểm gì so với canary bằng load balancer?
10. Health check của Route 53 phát hiện được loại sự cố nào mà metric EC2 trong CloudWatch không phát hiện được?
11. ACM cấp chứng chỉ miễn phí. Vì sao taskhub v3 (một EC2, nginx trong container) không dùng chứng chỉ ACM trực tiếp trên nginx?
12. Public IP tự gán của EC2 đổi khi stop/start. Nêu hai cách giữ cho tên miền luôn trỏ đúng, kèm chi phí của từng cách.
13. "Dangling DNS" là gì và vì sao nguy hiểm?
14. `dig` trả `SERVFAIL` khác `NXDOMAIN` thế nào?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/09-solutions.md](solutions/09-solutions.md). Chỉ mở sau khi tự làm.

**Bài 1 — Vẽ chuỗi phân giải.** Với một tên miền `.vn` bạn chọn, dùng `dig +trace` và vẽ (bằng chữ) chuỗi phân giải đầy đủ như mục 6.1, ghi TTL ở mỗi tầng. Tầng nào có TTL dài nhất và điều đó ảnh hưởng gì khi đổi nhà cung cấp DNS?

**Bài 2 — Thiết kế DNS cho taskhub.** Giả sử bạn có `example.com`. Viết bảng record cần có cho: `taskhub.example.com` (API), `www.example.com` (trỏ về cùng chỗ), một record CAA chỉ cho phép Let's Encrypt. Ghi loại, giá trị, TTL và lý do chọn TTL.

**Bài 3 — Script cập nhật record khi EC2 start.** Viết `scripts/update-dns.sh` (chạy trên laptop, `[WSL]`) nhận `instance-id`, `hosted-zone-id`, `record-name`: lấy public IP hiện tại của instance (`aws ec2 describe-instances --query ...`), rồi UPSERT record A với TTL 60, chờ `INSYNC`. Yêu cầu: `set -euo pipefail`, báo lỗi rõ khi instance không có public IP (đang stop). Chỉ chạy thật nếu bạn làm 9B.

**Bài 4 — Phân tích sự cố.** Đồng nghiệp báo: "Mình tạo record `api.example.com` 5 phút trước, máy mình vẫn `NXDOMAIN` nhưng máy bạn thấy rồi." Trước khi tạo, đồng nghiệp đã thử truy cập `api.example.com` một lần. Giải thích nguyên nhân và cách chứng minh bằng `dig`.

**Bài 5 — 🟨 Let's Encrypt cho nginx trong container (thiết kế, chưa cần chạy).** Mô tả các thay đổi cần có trong `compose.yaml` và `docker/nginx/default.conf` để dùng `certbot certonly --webroot`: volume nào chung giữa nginx và certbot, location nào phục vụ `/.well-known/acme-challenge/`, server block 443 trỏ tới file chứng chỉ ở đâu, và cách tự động gia hạn + reload nginx. Thêm: rule nào trong `taskhub-web-sg` phải mở? Vì sao việc gia hạn càng ngày càng phải tự động hóa?

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Phân biệt được registrar / authoritative / resolver và giải thích được ủy quyền NS bằng `dig +trace`.
- [ ] Đọc được từng phần đầu ra `dig` (status, flags `aa`, TTL, SERVER).
- [ ] Giải thích được alias khác CNAME ở 3 điểm, và vì sao taskhub dùng record A.
- [ ] Mô tả được quy trình đổi IP có hạ TTL trước.
- [ ] Biết chi phí hosted zone và mẹo "xóa trong 12 giờ".
- [ ] So sánh được ALB + ACM với Let's Encrypt cho taskhub, và vì sao Route 53/HTTPS là tùy chọn trong v3.
- [ ] Nêu được rủi ro public IP đổi và dangling DNS.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Amazon Route 53 pricing](https://aws.amazon.com/route53/pricing/) | Giá hosted zone, quy tắc 12 giờ, truy vấn, alias miễn phí, health check, tên miền | 2026-10-31 |
| [Route 53 — Choosing between alias and non-alias records](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resource-record-sets-choosing-alias-non-alias.html) | Alias ở apex, danh sách đích, TTL, phí | 2026-10-31 |
| [Route 53 — Considerations when working with a private hosted zone](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zone-private-considerations.html) | `enableDnsHostnames`/`enableDnsSupport`, split-view | 2026-10-31 |
| [ACM — Billing (pricing)](https://docs.aws.amazon.com/acm/latest/userguide/acm-billing.html) | Chứng chỉ public miễn phí với dịch vụ tích hợp; exportable có phí | 2026-10-31 |
| [Amazon EC2 On-Demand Pricing](https://aws.amazon.com/ec2/pricing/on-demand/) | Elastic IP tính cả khi idle | 2026-10-31 |
| [AWS Price List — AmazonVPC (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/ap-southeast-1/index.json) | Public IPv4 in-use/idle 0,005 USD/giờ | 2026-10-31 |
| [Let's Encrypt — Decreasing Certificate Lifetimes to 45 Days (blog, 2025-12-02)](https://letsencrypt.org/2025/12/02/from-90-to-45/) | Mốc 64 ngày (10/02/2027) và 45 ngày (16/02/2028) | 2026-10-31 |
| [Let's Encrypt — Certificate Lifetime Rationale and Plans](https://letsencrypt.org/docs/cert-lifetimes/) | Lý do rút ngắn thời hạn chứng chỉ | 2026-10-31 |
| [Certbot instructions (nginx, snap)](https://certbot.eff.org/instructions?ws=nginx&os=snap) | Cài certbot, gia hạn thử `renew --dry-run` | 2026-10-31 |
| [RFC 5737](https://www.rfc-editor.org/rfc/rfc5737) | Dải IP dành cho tài liệu (`203.0.113.0/24`) | 2026-10-31 |
