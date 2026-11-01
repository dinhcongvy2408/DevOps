# Lời giải — Bài 07. Logs, Monitoring & Troubleshooting

> ⚠️ Chỉ đọc sau khi bạn đã tự làm và ghi lại câu trả lời của mình. So sánh **cách suy luận**, không chỉ đáp án.
> Quay lại bài học: [07-logs-monitoring-troubleshooting.md](../07-logs-monitoring-troubleshooting.md)

## Mục lục

- [Bài 1 — Đọc stack trace](#bài-1--đọc-stack-trace)
- [Bài 2 — Thống kê lỗi theo nguồn](#bài-2--thống-kê-lỗi-theo-nguồn)
- [Bài 3 — Logrotate cho taskhub dùng create](#bài-3--logrotate-cho-taskhub-dùng-create)
- [Bài 4 — Runbook ổ đầy](#bài-4--runbook-ổ-đầy)
- [Bài 5 — Quan sát I/O wait](#bài-5--quan-sát-io-wait)
- [Bài 6 — Trả lời phỏng vấn](#bài-6--trả-lời-phỏng-vấn)

---

## Bài 1 — Đọc stack trace

**Nguyên nhân gốc** (`Caused by` cuối cùng):

```text
org.postgresql.util.PSQLException: FATAL: password authentication failed for user "taskhub"
```

PostgreSQL **đã nhận kết nối** (nên không phải `Connection refused` hay `timed out` — mạng và port đều ổn) nhưng **từ chối xác thực**: sai mật khẩu cho user `taskhub`, hoặc phương thức xác thực không khớp.

**Code của ứng dụng:** không có dòng `com.example.taskhub` nào. Lỗi xảy ra lúc Spring/Hibernate khởi tạo kết nối, trước khi code của bạn chạy. Đây là trường hợp phổ biến với lỗi khởi động: vấn đề nằm ở **cấu hình**, không phải code.

Hai lớp phía trên (`BeanCreationException`, `JDBCConnectionException`) chỉ là framework "bọc" lỗi gốc lại.

**Giả thuyết và cách kiểm chứng:**

| # | Giả thuyết | Kiểm chứng |
|---|---|---|
| 1 | App đọc sai / không đọc được mật khẩu (biến môi trường thiếu, file `.env` hoặc `EnvironmentFile` sai, typo tên biến) | `systemctl cat taskhub` xem `Environment=`/`EnvironmentFile=`; kiểm tra file env có tồn tại và đúng tên biến `SPRING_DATASOURCE_PASSWORD`; nếu app đang chạy: `sudo cat /proc/<PID>/environ \| tr '\0' '\n' \| grep -i datasource` |
| 2 | Mật khẩu của user trong PostgreSQL khác với cấu hình (bị đổi, DB mới tạo lại) | Thử đăng nhập tay bằng đúng thông tin app dùng: `psql -h localhost -U taskhub -d taskhub` |
| 3 | App kết nối nhầm tới instance DB khác (sai host/port trong URL) | Xem `spring.datasource.url` thực tế; so với log khởi động; xem log PostgreSQL phía server có dòng `password authentication failed` cùng thời điểm không |

Bước tốt nhất đầu tiên: **thử đăng nhập tay bằng chính thông tin app đang dùng** — tách được ngay vấn đề nằm ở "app đọc cấu hình" hay "phía DB".

---

## Bài 2 — Thống kê lỗi theo nguồn

```bash
journalctl -p warning --since today -o short-iso --no-pager \
  | grep -v '^--' \
  | awk '{print $3}' \
  | sed -E 's/\[[0-9]+\]//; s/:$//' \
  | sort | uniq -c | sort -rn | head
```

Giải thích từng bước:

| Bước | Tác dụng |
|---|---|
| `-p warning --since today` | Mức warning trở lên, từ 00:00 hôm nay |
| `-o short-iso` | Định dạng `2026-10-31T09:30:44+0700 LEGION sshd[640]: ...` — cột 3 là nguồn |
| `grep -v '^--'` | Bỏ các dòng thông báo của journalctl như `-- No entries --`, `-- Boot ... --` |
| `awk '{print $3}'` | Lấy cột thứ 3: `sshd[640]:` |
| `sed -E 's/\[[0-9]+\]//; s/:$//'` | Bỏ `[640]` và dấu `:` cuối → `sshd` |
| `sort \| uniq -c \| sort -rn` | Đếm và sắp giảm dần |

Kết quả mẫu:

```text
     12 kernel
      5 sshd
      2 taskhub
```

🟦 Cách chắc chắn hơn (không phụ thuộc vị trí cột), cần cài `jq`:

```bash
journalctl -p warning --since today -o json --no-pager | jq -r '.SYSLOG_IDENTIFIER // "unknown"' | sort | uniq -c | sort -rn
```

---

## Bài 3 — Logrotate cho taskhub dùng `create`

```text
/var/log/taskhub/*.log {
    weekly
    maxsize 100M
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 taskhub adm
    sharedscripts
    postrotate
        systemctl kill -s HUP taskhub.service >/dev/null 2>&1 || true
    endscript
}
```

| Dòng | Ý nghĩa |
|---|---|
| `weekly` | Xoay mỗi tuần |
| `maxsize 100M` | Xoay **sớm hơn** nếu file vượt 100MB, kể cả chưa đủ 1 tuần. Khác với `size 100M` — `size` **bỏ qua** điều kiện thời gian, chỉ xét kích thước |
| `rotate 8` | Giữ 8 bản cũ |
| `compress` / `delaycompress` | Nén bằng gzip, nhưng hoãn nén bản mới nhất một chu kỳ |
| `missingok` / `notifempty` | Không lỗi nếu thiếu file; không xoay file rỗng |
| `create 0640 taskhub adm` | Sau khi đổi tên file cũ, tạo file mới với quyền `rw-r-----`, chủ `taskhub`, group `adm` (để người trong group adm đọc được log) |
| `sharedscripts` | Với mẫu `*.log` khớp nhiều file, chỉ chạy `postrotate` **một lần** thay vì mỗi file một lần |
| `postrotate ... endscript` | Sau khi xoay, gửi tín hiệu HUP để app mở lại file log mới. `\|\| true` để logrotate không báo lỗi nếu service đang không chạy |

**Lưu ý quan trọng:**

- `maxsize` chỉ được kiểm tra **khi logrotate chạy** — mặc định mỗi ngày một lần trên Ubuntu. Nếu log có thể vượt 100MB trong vài giờ, phải cho logrotate chạy thường xuyên hơn (sửa timer). Đây là câu hỏi phỏng vấn hay.
- Nếu `/var/log/taskhub` thuộc user `taskhub` (không phải root), thêm `su taskhub adm` để tránh lỗi "parent directory has insecure permissions".
- Giả định app xử lý được tín hiệu HUP bằng cách mở lại log. Nếu không, phải dùng `copytruncate`.
- Kiểm tra trước khi áp dụng thật: `sudo logrotate -d /etc/logrotate.d/taskhub`.

---

## Bài 4 — Runbook ổ đầy

Một runbook mẫu (bạn có thể viết khác, quan trọng là **có thứ tự** và **có lệnh cụ thể**):

```markdown
# Runbook: Ổ đĩa đầy

## Triệu chứng
- Alert disk > 90%, hoặc log có `No space left on device`, hoặc app không ghi được file.

## 1. Xác định ổ nào và loại "đầy" nào
    df -h          # dung lượng
    df -i          # inode
- `Use%` cao → mục 2. `IUse%` cao → mục 4.

## 2. Tìm thư mục lớn (đi từ trên xuống)
    sudo du -h --max-depth=1 -x / 2>/dev/null | sort -h | tail
    sudo du -h --max-depth=1 -x /var 2>/dev/null | sort -h | tail
Nghi phạm thường gặp: /var/log, /var/lib/docker, /tmp, /home/*/.cache, file dump/heap dump.

## 3. Nếu là log
- KHÔNG `rm` file đang được ghi. Dùng: `sudo truncate -s 0 <file>`
- Xóa log cũ đã xoay (`*.gz`, `*.1`) nếu không cần.
- Journal: `sudo journalctl --vacuum-size=500M`
- Sau sự cố: kiểm tra cấu hình logrotate (/etc/logrotate.d/taskhub).

## 4. Nếu df ≠ du (file đã xóa nhưng còn mở)
    sudo lsof +L1
- Khởi động lại process đang giữ file (sau khi báo team).

## 5. Nếu hết inode
    sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2,3 | sort | uniq -c | sort -rn | head
- Xóa file nhỏ rác (cache, session) trong thư mục tìm được.

## 6. Docker chiếm chỗ
- Sẽ bổ sung ở Module 04.

## Sau khi xử lý
- Xác nhận `df -h` đã giảm, app ghi file bình thường.
- Ghi postmortem: nguyên nhân, vì sao alert không báo sớm hơn, cách phòng tránh.
```

---

## Bài 5 — Quan sát I/O wait

Kết quả thường thấy trong lúc `dd` chạy:

- `bo` tăng mạnh (hàng chục đến hàng trăm nghìn block/s, tùy tốc độ SSD).
- `b` = 1 (chính process `dd` đang bị chặn chờ ghi đĩa).
- `wa` tăng lên (vài % đến vài chục %, tùy máy).
- Sau khi xong, cả ba trở về gần 0.

**`oflag=direct`** yêu cầu ghi **trực tiếp xuống đĩa**, bỏ qua **page cache** (bộ đệm trang của kernel). Không có cờ này, dữ liệu được ghi vào RAM trước và kernel đẩy xuống đĩa sau — `dd` kết thúc rất nhanh, còn `bo`/`wa` chỉ tăng rải rác về sau, khó quan sát. Với `direct`, mỗi lần ghi phải đợi đĩa thật → hiện tượng chờ I/O lộ rõ.

Trên WSL, ổ Linux là một file ổ ảo (`.vhdx`) nằm trên ổ Windows, nên con số có thể khác máy thật — nhưng xu hướng vẫn giống nhau.

---

## Bài 6 — Trả lời phỏng vấn

Câu trả lời mẫu (~2 phút):

> "502 nghĩa là reverse proxy (ví dụ Nginx) **không nhận được phản hồi hợp lệ từ backend**, nên tôi nghi backend trước. Tôi đi theo thứ tự:
>
> 1. **Backend có chạy không?** `systemctl status taskhub` hoặc `docker ps`. Nếu đã chết, tôi xem lý do: `journalctl -u taskhub -n 100`, đọc `Caused by` cuối cùng trong stack trace. Nếu thấy `status=9/KILL` mà log app không có gì, tôi kiểm tra OOM killer bằng `dmesg -T | grep -i 'killed process'`.
> 2. **Có lắng nghe đúng port không?** `ss -tlnp | grep 8080` — so với port mà Nginx đang `proxy_pass` tới.
> 3. **Gọi trực tiếp từ server có được không?** `curl -v localhost:8080/actuator/health`. Được thì backend ổn, vấn đề ở giữa Nginx và backend — tôi xem `/var/log/nginx/error.log`, thường sẽ thấy `connect() failed (111: Connection refused)` hoặc `upstream timed out`.
> 4. **Kiểm tra nhanh tài nguyên** để tìm nguyên nhân gốc: `uptime`, `free -h`, `df -h` — ổ đầy hoặc hết RAM là các nguyên nhân hay gặp khiến app chết.
> 5. Sau khi khôi phục, tôi ghi lại timeline và viết postmortem: nguyên nhân gốc, vì sao monitoring không báo sớm, và cách phòng tránh."

Điểm được đánh giá cao: **giải thích được 502 nghĩa là gì**, đi theo thứ tự hợp lý, **quan sát trước khi sửa**, nhắc đến **postmortem**.
