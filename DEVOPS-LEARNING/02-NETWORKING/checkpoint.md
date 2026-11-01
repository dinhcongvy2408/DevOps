# Checkpoint Module 02 — Networking Fundamentals

> ⏱️ Tổng ~4 giờ (có thể chia 2 buổi) · Làm vào cuối tuần 5
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

## Mục lục

- [Quy tắc](#quy-tắc)
- [Phần A — Lý thuyết (50 phút)](#phần-a--lý-thuyết-50-phút)
- [Phần B — Thực hành (90 phút)](#phần-b--thực-hành-90-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép**: `man`, `--help`, [nginx docs](https://nginx.org/en/docs/beginners_guide.html), các bài học trong module này. **Không** dùng công cụ tính subnet online ở Phần B1 — phải tính bằng tay.
3. Tự bấm giờ cho từng phần. Hết giờ thì dừng và ghi lại mình đang ở đâu — đó cũng là dữ liệu đánh giá.
4. Nộp bài: tạo thư mục `~/devops-journey/week05/checkpoint/` gồm `part-a.md`, `part-b/` (bảng subnet + file `default.conf` + kết quả kiểm thử), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.

---

## Phần A — Lý thuyết (50 phút)

Trả lời ngắn gọn bằng lời của bạn (2–6 câu mỗi câu). Mục tiêu là giải thích **bản chất**, không phải chép định nghĩa.

1. Mô hình TCP/IP có những tầng nào? Xếp các thứ sau vào đúng tầng và giải thích ngắn: `ping`, DNS, Security Group, Application Load Balancer, switch, địa chỉ MAC, `curl`.
2. Khi `curl` gửi một HTTP request từ laptop tới một server ở xa, gói tin được **đóng gói (encapsulation)** thế nào? Khi đi qua từng router, địa chỉ nào thay đổi (MAC hay IP) và địa chỉ nào giữ nguyên?
3. **Tính bằng tay** cho dải `10.20.32.0/19`: địa chỉ mạng, địa chỉ broadcast, địa chỉ dùng được đầu tiên và cuối cùng, tổng số địa chỉ. Nếu đây là một subnet trên AWS thì dùng được bao nhiêu địa chỉ? Địa chỉ `10.20.64.1` có thuộc dải này không? Trình bày cách tính.
4. Kể 3 dải private IPv4. Một EC2 trong public subnet có IP private `10.0.1.25` và IP public `13.212.x.x`. Bên trong máy (`ip addr`) bạn thấy IP nào? Vì sao? Ai thực hiện việc "đổi" giữa hai IP đó?
5. Mô tả quá trình phân giải `app.example.com` từ lúc trình duyệt cần IP đến lúc nhận được câu trả lời: recursive resolver, root, TLD, authoritative làm gì? Bạn vừa đổi record A của domain có TTL `3600` — vì sao một số người dùng vẫn vào IP cũ, và lần sau nên làm gì trước khi đổi?
6. `dig +short api.internal` trả `10.0.5.20` nhưng `curl http://api.internal` lại kết nối tới `10.0.9.99`. Nêu 2 nguyên nhân có thể và lệnh để xác nhận mỗi nguyên nhân.
7. Cho bảng route:

   ```text
   default via 10.0.1.1 dev eth0
   10.0.1.0/24 dev eth0 proto kernel scope link src 10.0.1.25
   172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
   ```

   Gói tin tới `8.8.8.8`, `10.0.1.40`, `172.17.0.5`, `10.0.2.7` lần lượt đi qua đâu? `default via` nghĩa là gì? Lệnh nào hỏi kernel trực tiếp "gói tới IP X sẽ đi đường nào"?
8. SNAT và DNAT khác nhau thế nào? Mỗi thứ sau là SNAT hay DNAT, giải thích: (a) AWS NAT Gateway cho EC2 trong private subnet tải package; (b) `docker run -p 8080:80 nginx`; (c) router Wi-Fi nhà bạn khi laptop truy cập Internet.
9. Mô tả TCP three-way handshake. Vì sao DNS thường dùng UDP? Kể một trường hợp DNS dùng TCP.
10. Phân biệt `Connection refused`, `Connection timed out`, `No route to host`: mỗi lỗi cho biết điều gì đã xảy ra với gói tin, và bạn kiểm tra gì tiếp theo?
11. `ss -tlnp` trên server cho kết quả:

    ```text
    LISTEN 0 100   127.0.0.1:8080   0.0.0.0:*   users:(("java",pid=812,fd=9))
    LISTEN 0 4096  0.0.0.0:22       0.0.0.0:*   users:(("sshd",pid=501,fd=3))
    ```

    Từ một máy khác, `curl http://<IP-server>:8080` ra kết quả gì, vì sao? Sửa ở đâu? Nếu app này chạy trong container với `-p 8080:8080`, có truy cập được từ ngoài không?
12. Firewall stateful và stateless khác nhau thế nào? Trên AWS, Security Group là loại nào, Network ACL là loại nào? Vì sao với NACL bạn phải cho phép **cả chiều về** trên dải port tạm (ephemeral ports), còn với Security Group thì không?
13. Trong bối cảnh có Nginx làm reverse proxy, `502 Bad Gateway`, `503 Service Unavailable` và `504 Gateway Time-out` khác nhau thế nào? Với mỗi mã, bạn xem log nào và tìm dòng gì đầu tiên?
14. Mô tả đơn giản TLS handshake: server gửi gì, client kiểm tra những gì trên chứng chỉ? Kể 3 lỗi TLS hay gặp khi vận hành và lệnh `openssl` để kiểm tra.
15. **Câu tổng hợp:** Người dùng gõ `https://app.example.com/api/tasks` vào trình duyệt. Mô tả lần lượt các bước từ đầu đến khi nhận được JSON (DNS → TCP → TLS → HTTP → reverse proxy → app). Với **mỗi bước**, nêu một cách nó có thể hỏng và lệnh bạn dùng để kiểm tra bước đó.

---

## Phần B — Thực hành (90 phút)

### B1. Thiết kế subnet bằng tay (40 phút)

Công ty cấp cho dự án dải VPC **`10.30.0.0/20`** trên AWS, dùng **2 Availability Zone** (`a` và `b`). Yêu cầu cho **mỗi AZ**:

| Loại subnet | Số máy cần chứa tối thiểu |
|---|---|
| public (load balancer, bastion) | 50 |
| private-app (ứng dụng, có thể scale) | 400 |
| private-db (database) | 20 |

Ràng buộc:

- AWS giữ lại **5 địa chỉ** trong mỗi subnet — tính vào khi chọn kích thước.
- Chọn subnet **nhỏ nhất** đủ dùng cho mỗi loại.
- Các subnet **không chồng lấn**, được **căn đúng biên** (địa chỉ đầu chia hết cho kích thước khối).
- Xếp sao cho phần còn trống của VPC **liền một khối lớn nhất có thể** để dành cho tương lai.

Nộp `part-b/subnet-plan.md` gồm:

1. Bảng: tên subnet · AZ · CIDR · địa chỉ đầu – cuối · số địa chỉ dùng được trên AWS.
2. Phần tính toán cho **ít nhất 2 subnet** (chuyển sang nhị phân hoặc giải thích theo khối).
3. Dải còn trống sau khi xếp. Trả lời: còn đặt thêm được một subnet `/22` không? Nếu được, ở CIDR nào?

### B2. Cấu hình Nginx reverse proxy (50 phút)

#### Môi trường

```bash
mkdir -p ~/devops-lab/02-networking && cd ~/devops-lab/02-networking
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/02-NETWORKING/labs/checkpoint .
cd checkpoint
find . -type f -exec sed -i 's/\r$//' {} +
cd part-b
docker compose up -d
```

Hệ thống gồm `edge` (Nginx, mở ra `http://localhost:18081`), `api` (backend A, port 8000) và `frontend` (backend B, port 3000). Cả hai backend trả JSON mô tả request mà chúng nhận được: `service`, `path`, `host_header`, `x_real_ip`, `x_forwarded_for`. Đọc JSON này để kiểm chứng cấu hình của bạn.

Viết cấu hình trong `part-b/conf.d/default.conf`, áp dụng bằng:

```bash
docker compose exec edge nginx -t && docker compose exec edge nginx -s reload
```

#### Đề bài

1. `/health` do **chính Nginx** trả lời `ok` (text), không chuyển tới backend nào.
2. `/api/...` chuyển tới **api (backend A)**, **bỏ tiền tố `/api`**: request `/api/tasks?status=done` tới backend với đường dẫn `/tasks?status=done`.
3. Mọi đường dẫn còn lại chuyển tới **frontend (backend B)**, giữ nguyên đường dẫn.
4. Backend phải nhận được: header `Host` **gốc** của client (không phải `api:8000`), `X-Real-IP` và `X-Forwarded-For`.
5. Mọi directive có comment giải thích bằng lời của bạn.

#### Kiểm thử bắt buộc

Chạy từ WSL, ghi lệnh và kết quả vào `part-b/test-results.md`:

| # | Kiểm thử | Kết quả mong đợi |
|---|---|---|
| 1 | `curl -s http://localhost:18081/health` | `ok` |
| 2 | `curl -s http://localhost:18081/` | `"service": "frontend-B"`, `"path": "/"` |
| 3 | `curl -s 'http://localhost:18081/about?lang=vi'` | `"service": "frontend-B"`, `"path": "/about?lang=vi"` |
| 4 | `curl -s 'http://localhost:18081/api/tasks?status=done'` | `"service": "api-A"`, `"path": "/tasks?status=done"` |
| 5 | `curl -sI http://localhost:18081/api` | Giải thích kết quả bạn nhận được (mã HTTP, header `Location`) và **vì sao** Nginx trả như vậy |
| 6 | JSON của kiểm thử 4 | `host_header` là `localhost` hoặc `localhost:18081`; `x_real_ip` và `x_forwarded_for` khác `null` |

Dọn dẹp sau khi xong: `docker compose down -v` (trong `part-b`).

---

## Phần C — Break-fix (90 phút)

### Khởi tạo

Trong thư mục `checkpoint` đã copy ở Phần B (không phải `part-b`):

```bash
cd ~/devops-lab/02-networking/checkpoint
docker compose up -d
docker compose logs -f client          # chờ "client ready", rồi Ctrl+C
docker compose exec client bash
verify-checkpoint                      # kiểm tra tiến độ bất cứ lúc nào
```

> Coi mỗi container là một máy. Chưa cần hiểu Docker — chỉ dùng các lệnh trong bảng "Các lệnh bạn được dùng" của [break-fix #1](labs/break-fix-01/README.md#4-các-lệnh-bạn-được-dùng), áp dụng tương tự với các máy ở đây: `edge`, `api`, `dns`, `client`.
> Nếu gặp `Pool overlaps ...`: đổi `172.29` thành `172.31` ở **mọi chỗ** trong `compose.yaml`, `dns/hosts.taskhub` và `client/verify.sh` (đây là ngoại lệ duy nhất được sửa file verify).

### Bối cảnh

Cuối tuần, reverse proxy của taskhub được chuyển sang **máy mới** (`edge`, IP `172.29.1.10`). Người làm việc đó đã sinh chứng chỉ TLS mới, dọn lại cấu hình Nginx và báo "xong". Sáng nay máy monitoring (`client`, đứng ở đó để làm bài) bắn ra 4 cảnh báo.

Hệ thống có **DNS server riêng** cho miền `taskhub.test` (máy `dns`, IP `172.29.1.53`, phần mềm dnsmasq). Bản ghi của nó nằm trong file `dns/hosts.taskhub`. Máy client dùng DNS server này.

Chứng chỉ TLS là **tự ký (self-signed)** — vì vậy luôn gọi HTTPS kèm `--cacert /certs/edge.crt` để curl tin chứng chỉ đó:

```bash
curl -v --cacert /certs/edge.crt https://app.taskhub.test/
```

### Các ticket

| Ticket | Mô tả | Kết quả mong đợi |
|---|---|---|
| 🎫 #4001 | `curl https://app.taskhub.test/` từ máy monitoring treo vài giây rồi báo lỗi kết nối. "Máy mới chạy rồi mà!" | `app.taskhub.test` phân giải ra IP của edge mới |
| 🎫 #4002 | Sau khi #4001 được sửa, curl báo lỗi chứng chỉ — dù đã dùng `--cacert` đúng file. | `curl --cacert /certs/edge.crt https://app.taskhub.test/` trả `taskhub app OK` |
| 🎫 #4003 | `/api/report` luôn trả `504` sau khoảng 5 giây. Team dev xác nhận báo cáo mất **khoảng 8 giây** là bình thường; mức chấp nhận được là **dưới 15 giây**. | `/api/report` trả `200` |
| 🎫 #4004 | Healthcheck `http://app.taskhub.test/health` (HTTP, port 80) của monitoring trả `404 unknown site`, dù cấu hình có viết `location = /health`. | Healthcheck trả `ok` |

### Luật chơi

- **Không sửa** `apps/server.py` và **không đọc** `client/verify.sh`.
- Sửa ở file cấu hình trong thư mục lab. Cách áp dụng:

  | File sửa | Áp dụng bằng |
  |---|---|
  | `edge/conf.d/default.conf` | `docker compose exec edge nginx -t && docker compose exec edge nginx -s reload` |
  | `dns/hosts.taskhub` | `docker compose restart dns` |
  | `certs/gen.sh` | `docker compose up -d --force-recreate certgen`, rồi reload nginx như dòng đầu |

- Ticket #4003: chỉ tăng giới hạn chờ **vừa đủ** theo yêu cầu và giải thích con số bạn chọn — không đặt vô hạn hay hàng giờ.
- Ghi nhật ký debug cho **từng ticket** theo mẫu của [break-fix #1](labs/break-fix-01/README.md#7-sản-phẩm-phải-nộp) vào `part-c.md` (nên viết trong thư mục `checkpoint` trên WSL để còn lại sau khi dọn dẹp).

Dọn dẹp sau khi xong: `docker compose down -v` (trong `checkpoint`).

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 12/15 câu đúng **bản chất** (tự chấm theo lời giải, trung thực). Câu 3 và câu 15 **bắt buộc đúng** | 30% |
| B | B1: bảng subnet đúng, không chồng lấn, căn đúng biên, tính đúng số địa chỉ. B2: qua cả 6 kiểm thử, có comment, trong 90 phút cho cả B1 + B2 | 35% |
| C | `verify-checkpoint` đạt 4/4 trong 90 phút **và** nhật ký nêu được **cách tìm ra** từng lỗi (lệnh nào, thấy gì) | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần → tick vào [checklist module](README.md#7-checklist-hoàn-thành-module) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#networking).

---

## Nếu chưa đạt

Không chuyển sang Module 03/04 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ)):

| Sai ở | Ôn lại |
|---|---|
| Câu A1–A2 | [Bài 01](01-osi-tcpip-model.md) |
| Câu A3–A4, Phần B1 | [Bài 02](02-ipv4-subnet-cidr.md) |
| Câu A5–A6, ticket #4001 | [Bài 03](03-dns-dhcp.md) |
| Câu A7–A8 | [Bài 04](04-routing-nat-switching.md) |
| Câu A9–A12 | [Bài 05](05-tcp-udp-ports-firewall.md) |
| Câu A14, ticket #4002 | [Bài 06](06-http-https-tls.md) |
| Câu A13, Phần B2, ticket #4003, #4004 | [Bài 07](07-load-balancing-reverse-proxy.md) |
| Câu A15, không biết bắt đầu Phần C từ đâu | [Bài 08](08-network-troubleshooting-tools.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt (Phần C: copy lại thư mục lab từ giáo trình để có lỗi ban đầu).
