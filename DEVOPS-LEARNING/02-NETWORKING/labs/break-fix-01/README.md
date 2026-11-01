# Break-fix Network #1 — Sáng thứ Hai ở taskhub-edge

> ⏱️ 90–150 phút · Môi trường: `[Lab Compose]` · Kiến thức cần có: bài [01](../../01-osi-tcpip-model.md) → [08](../../08-network-troubleshooting-tools.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã hoàn thành hoặc đã bị kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Sơ đồ hệ thống](#2-sơ-đồ-hệ-thống)
- [3. Khởi tạo môi trường](#3-khởi-tạo-môi-trường)
- [4. Các lệnh bạn được dùng](#4-các-lệnh-bạn-được-dùng)
- [5. Các ticket](#5-các-ticket)
- [6. Luật chơi](#6-luật-chơi)
- [7. Sản phẩm phải nộp](#7-sản-phẩm-phải-nộp)
- [8. Gợi ý](#8-gợi-ý)
- [9. Dọn dẹp](#9-dọn-dẹp)

---

## 1. Bối cảnh

Cuối tuần vừa rồi, một đồng nghiệp đã "dọn dẹp lại" cấu hình hệ thống `taskhub-edge` để chuẩn bị chuyển lên cloud: đổi port, tách mạng, siết firewall. Anh ấy nghỉ phép từ hôm nay và **không để lại ghi chú nào**. Sáng thứ Hai, 4 ticket đang chờ bạn.

Hệ thống gồm 5 "máy" chạy trên laptop của bạn. **Bạn chưa cần hiểu Docker** — hãy coi mỗi container là **một máy tính nhỏ có IP riêng**, nối với nhau bằng các mạng riêng. Bạn chỉ cần chạy đúng các lệnh `docker compose ...` được hướng dẫn. Module 04 sẽ giải thích chúng hoạt động thế nào.

---

## 2. Sơ đồ hệ thống

```text
 Trình duyệt Windows
   http://localhost:18080
          │
          ▼
 ┌─────────────────┐   mạng frontend 172.28.1.0/24
 │ web  (nginx)    │◄──────────────────────────────┐
 │ reverse proxy   │                                │
 └───────┬─────────┘                         ┌──────┴───────┐
         │ mạng backend 172.28.5.0/24        │ client       │
         │                                   │ (jump host — │
   ┌─────┼──────────────┐                    │  bạn đứng ở  │
   ▼     ▼              ▼                    │  đây để debug)│
 ┌─────┐ ┌─────────┐                         └──────┬───────┘
 │ api │ │ reports │◄──────── backend ──────────────┘
 │:8000│ │ :9000   │
 └─────┘ └─────────┘

 ┌──────────┐   mạng ops 172.28.7.0/24
 │ status   │
 │ :9100    │
 └──────────┘
```

| Đường dẫn trên web | Chuyển tới |
|---|---|
| `/` | web tự trả lời `taskhub-edge OK` |
| `/api/...` | `api` port 8000 |
| `/reports/...` | `reports` port 9000 |
| `/status/...` | `status` port 9100 |

Tên dịch vụ (`web`, `api`, `reports`, `status`, `client`) chính là **tên máy** — các máy trong cùng một mạng tìm nhau bằng tên này qua DNS nội bộ. `api` còn có thêm tên `api.internal`.

---

## 3. Khởi tạo môi trường

Trong WSL:

```bash
mkdir -p ~/devops-lab/02-networking && cd ~/devops-lab/02-networking
# Copy thư mục lab từ giáo trình về (đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING)
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/02-NETWORKING/labs/break-fix-01 .
cd break-fix-01
find . -type f -exec sed -i 's/\r$//' {} +   # phòng trường hợp file bị đổi sang CRLF khi copy từ Windows
docker compose up -d
docker compose logs -f client                # chờ dòng "client ready", rồi nhấn Ctrl+C
```

Lần đầu mất khoảng 2–3 phút để tải image và cài công cụ. Khi xong, vào jump host:

```bash
docker compose exec client bash
verify                                        # kiểm tra tiến độ bất cứ lúc nào
```

Mở trình duyệt trên Windows: `http://localhost:18080/api/health` — bạn sẽ thấy ngay vấn đề đầu tiên.

> **Gặp lỗi khi `docker compose up`?**
> - `port is already allocated` → port 18080 đang bị dùng. Sửa `18080` trong `compose.yaml` thành port khác (ví dụ `18090`).
> - `Pool overlaps with other one on this address space` → dải `172.28.x.x` trùng với một mạng có sẵn trên máy bạn (VPN công ty, mạng Docker khác). Đổi `172.28` thành `172.30` ở **mọi chỗ** trong `compose.yaml`. Đây cũng là một bài học: hai mạng có dải IP chồng lấn nhau không thể cùng tồn tại ([bài 02](../../02-ipv4-subnet-cidr.md)).

---

## 4. Các lệnh bạn được dùng

Mọi lệnh `docker compose` chạy trong thư mục `break-fix-01` trên WSL.

| Mục đích | Lệnh |
|---|---|
| Xem các máy đang chạy và port | `docker compose ps` |
| Đọc log của một máy | `docker compose logs <tên>` (thêm `-f` để theo dõi liên tục, `--tail 50` để xem 50 dòng cuối) |
| Vào jump host (đủ công cụ: `dig`, `curl`, `nc`, `ping`, `ip`, `tcpdump`, `traceroute`) | `docker compose exec client bash` |
| Vào máy web (Alpine, có `sh`, `wget`, `nslookup`) | `docker compose exec web sh` |
| Vào máy reports, api, status | `docker compose exec <tên> bash` |
| Kiểm tra cấu hình nginx | `docker compose exec web nginx -t` |

**Cách áp dụng thay đổi** — cấu hình nằm trong các file ở thư mục lab, sửa bằng VS Code hoặc `nano`:

| Bạn sửa file | Áp dụng bằng |
|---|---|
| `web/conf.d/default.conf` | `docker compose exec web nginx -t && docker compose exec web nginx -s reload` |
| `compose.yaml` | `docker compose up -d` (Compose tự tạo lại máy có cấu hình thay đổi) |
| File trong `reports/` | `docker compose up -d --force-recreate reports` |

> Sửa trực tiếp bên trong container (ví dụ gõ lệnh `iptables` trong máy reports) có tác dụng ngay, **nhưng sẽ mất khi máy được tạo lại**. Dùng cách đó để **thử giả thuyết**, sau đó sửa vào file cấu hình để cách sửa tồn tại lâu dài — giống hệt cách làm đúng trên server thật.

---

## 5. Các ticket

### 🎫 Ticket #3001 — P1 — API trả 502 Bad Gateway

> **Người báo:** Team QA
> **Mô tả:** Mọi request tới `http://localhost:18080/api/...` đều trả `502 Bad Gateway`. Team dev khẳng định app `api` vẫn đang chạy bình thường: "log có ghi listening mà".
> **Kết quả mong đợi:** `curl http://web/api/health` từ jump host trả `200` kèm JSON có `"service": "api"`.

### 🎫 Ticket #3002 — P2 — Trang báo cáo treo rồi báo 504

> **Người báo:** Team kế toán
> **Mô tả:** Mở `/reports/daily` thì trình duyệt quay khoảng 5 giây rồi hiện `504 Gateway Time-out`. Tuần trước vẫn dùng bình thường. Đồng nghiệp nghỉ phép có nhắn "đã siết firewall cho reports".
> **Kết quả mong đợi:** `/reports/daily` trả `200`. Firewall vẫn phải **chặn mọi nguồn không cần thiết** — không được gỡ bỏ firewall.

### 🎫 Ticket #3003 — P2 — Trang trạng thái 502

> **Người báo:** Team vận hành
> **Mô tả:** `/status/` trả `502`. `docker compose ps` cho thấy máy `status` vẫn chạy, log của nó cũng không có lỗi gì.
> **Kết quả mong đợi:** `/status/` trả `200` kèm JSON có `"service": "status"`.

### 🎫 Ticket #3004 — P3 — Jump host gọi thẳng api.internal bị lỗi

> **Người báo:** Chính bạn, trong lúc xử lý #3001
> **Mô tả:** Từ jump host, `curl http://api.internal:8000/health` luôn lỗi sau vài giây — **kể cả sau khi #3001 đã được sửa**. Lạ ở chỗ `dig api.internal` lại trả về một IP trông rất hợp lý.
> **Kết quả mong đợi:** từ jump host, `api.internal` phân giải ra **cùng IP** với kết quả của DNS và `curl` gọi được.

---

## 6. Luật chơi

1. **Không sửa** `apps/server.py` — đó là "ứng dụng của team dev". Bạn chỉ sửa **hạ tầng**: biến môi trường, cấu hình nginx, firewall, mạng.
2. **Không đọc** `client/verify.sh` — nó chứa đáp án.
3. **Không dùng AI.** Được dùng: `man`, `--help`, các bài học trong giáo trình, [nginx docs](https://nginx.org/en/docs/beginners_guide.html).
4. **Debug theo tầng** ([bài 08](../../08-network-troubleshooting-tools.md)): tên có phân giải được không → có đường đi không → port có mở không → HTTP trả gì → log nói gì. Ghi lại kết quả ở mỗi tầng.
5. **Phân biệt thông báo lỗi** là chìa khóa của bài này: `Connection refused`, `Connection timed out`, `No route to host`, `Could not resolve host`. Mỗi loại chỉ về một nguyên nhân khác nhau — đừng bỏ qua chúng.
6. Không có lời giải "tắt" kiểu gỡ hết firewall hay cho mọi máy vào chung một mạng. Mọi thay đổi phải theo nguyên tắc **tối thiểu cần thiết** và giải thích được.

---

## 7. Sản phẩm phải nộp

Tạo file `~/devops-journey/week05/break-fix-network-01.md` gồm:

1. **Timeline** các lỗi theo đúng thứ tự bạn phát hiện (ticket #3001 có **2 lỗi** nối tiếp nhau).
2. Với **mỗi lỗi**, theo [mẫu nhật ký debug](../../../00-ROADMAP/templates/troubleshooting-journal-template.md):

   ```markdown
   ### Lỗi N: <tên ngắn>
   - Triệu chứng (dán nguyên thông báo lỗi và mã HTTP):
   - Tầng nghi ngờ (DNS / đường đi / port / HTTP / ứng dụng) và lý do:
   - Lệnh quan sát đã dùng và kết quả:
   - Nguyên nhân gốc:
   - Cách sửa (file nào, dòng nào):
   - Cách phòng tránh lần sau:
   - Gặp lại ở đâu trên cloud (AWS / Kubernetes):
   ```

3. Bảng tổng kết **4 loại thông báo lỗi** bạn đã gặp: thông báo nguyên văn → ý nghĩa → nguyên nhân trong bài này.
4. Kết quả `verify` cuối cùng (dán vào).

---

## 8. Gợi ý

Chỉ mở từng cấp khi đã thử ít nhất 15 phút ở cấp trước.

<details>
<summary>💡 Gợi ý cấp 1 — Hướng tiếp cận</summary>

- Bắt đầu mỗi ticket bằng **log của reverse proxy**: `docker compose logs web --tail 30`. Nginx ghi rất rõ nó thử kết nối tới **địa chỉ nào, port nào** và thất bại vì lý do gì.
- Sau đó **đi vòng qua nginx**: từ jump host, gọi thẳng dịch vụ phía sau (`nc -zv <tên> <port>`, `curl -v http://<tên>:<port>/`). Nếu gọi thẳng cũng lỗi → vấn đề nằm ở dịch vụ hoặc mạng, không phải ở nginx.
- Đọc log khởi động của từng dịch vụ (`docker compose logs api`) — nó nói chính xác dịch vụ đang nghe ở đâu.
- Nhìn lại sơ đồ mục 2 và **so sánh với `compose.yaml`**: mỗi máy thực sự nằm trong mạng nào?

</details>

<details>
<summary>💡 Gợi ý cấp 2 — Lệnh nên dùng</summary>

- Phân giải tên: `dig +short <tên>` (hỏi thẳng DNS) **và** `getent hosts <tên>` (hỏi theo đúng cách ứng dụng hỏi, có đọc `/etc/hosts`). So sánh hai kết quả.
- Port: `nc -zv -w 3 <tên> <port>` — chú ý lệnh **trả lỗi ngay** hay **chờ hết 3 giây**.
- Trong máy reports: `iptables -L INPUT -n -v --line-numbers` — cột `pkts` cho biết luật nào đang "bắt" gói tin. Gọi thử vài lần rồi xem lại số này thay đổi ở dòng nào.
- IP của máy nào đó: `getent hosts web` hoặc `ip -4 addr` bên trong máy đó.
- Từ máy web: `docker compose exec web nslookup status 127.0.0.11` — hỏi DNS nội bộ xem web có "nhìn thấy" status không.

</details>

<details>
<summary>💡 Gợi ý cấp 3 — Gần như đáp án</summary>

- #3001 có 2 lỗi: (1) nginx gửi tới **sai port** của api; (2) api chỉ nghe trên **loopback** nên máy khác không kết nối được dù nó "đang chạy".
- #3002: firewall của reports chỉ cho phép một dải IP **cũ**, không phải dải mà web đang thực sự dùng để gọi tới.
- #3003: status nằm ở một mạng mà web **không tham gia** — DNS nội bộ chỉ trả lời tên của các máy trong cùng mạng.
- #3004: jump host có một dòng cố định trong `/etc/hosts` (do `extra_hosts` trong `compose.yaml` tạo ra) trỏ `api.internal` tới IP cũ. `dig` không đọc `/etc/hosts`, còn `curl` thì có.

</details>

---

## 9. Dọn dẹp

Khi xong (hoặc muốn làm lại từ đầu):

```bash
docker compose down -v
```

Lệnh này xóa toàn bộ máy và mạng của lab. Muốn làm lại với lỗi ban đầu: copy lại thư mục lab từ giáo trình (vì bạn đã sửa các file cấu hình).
