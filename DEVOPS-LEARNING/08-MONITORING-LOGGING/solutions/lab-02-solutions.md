# Lời giải — Lab 02: Backup PostgreSQL lên S3, diễn tập restore và đo RTO

> Chỉ mở sau khi đã tự làm. Bản tham khảo đầy đủ của hai script: [backup.sh](../labs/reference/scripts/backup.sh), [restore.sh](../labs/reference/scripts/restore.sh).

## Phần A

**A2 — bỏ `-T`.** `docker compose exec` (không `-T`) cấp pseudo-TTY. Trên luồng có TTY, terminal có thể chuyển `\n` thành `\r\n` → file lớn hơn một chút và `pg_restore --list` báo `input file does not appear to be a valid archive` (hoặc lỗi giải nén). Hiện tượng cụ thể tùy môi trường — điều quan trọng là bạn **thấy** file hỏng mà lệnh dump vẫn exit 0. Đó là kiểu lỗi âm thầm bài 06 nói tới.

**A5.** Mong đợi (minh họa):

```text
taskhub          tasks=1  flyway_version=1
taskhub_restore  tasks=5  flyway_version=1
```

(`taskhub` còn 1 task `created-after-backup` nếu trước đó database rỗng; nếu bạn đã có task từ trước thì cộng thêm.)

**A6 — cứu task tạo sau backup.** Task đó nằm trong `taskhub_broken`. Một cách (chạy khi cả hai database cùng tồn tại; PostgreSQL không truy vấn chéo database trực tiếp, nên xuất ra rồi nạp vào):

```bash
docker compose exec -T postgres psql -U taskhub -d taskhub_broken -c \
  "\copy (select title, description, status, created_at, updated_at from tasks where title = 'created-after-backup') to stdout with csv" \
  > /tmp/rescued.csv
docker compose exec -T postgres psql -U taskhub -d taskhub -c \
  "\copy tasks (title, description, status, created_at, updated_at) from stdin with csv" < /tmp/rescued.csv
```

Tên cột lấy theo migration `V1` của bạn (tuần 6) — kiểm tra bằng `\d tasks`. Không chép cột `id`: để sequence của database đích sinh id mới, tránh trùng.

## Phần B

**Bản tự viết đạt yêu cầu khi** khớp R1–R8. So với [bản tham khảo](../labs/reference/scripts/backup.sh), các điểm hay bị thiếu:

| Điểm | Vì sao quan trọng |
|---|---|
| `trap 'rm -f "$tmp"' EXIT` | Không để rơi file dump (chứa dữ liệu) trong `/tmp` khi script lỗi |
| Dump ra file, **không** pipe thẳng lên S3 | `pg_dump` lỗi giữa chừng thì `aws s3 cp -` vẫn có thể tạo object dở dang |
| `docker exec -i` (có `-i`) cho `pg_restore --list < file` | Không có `-i`, stdin không được chuyển vào container → `pg_restore` treo hoặc đọc rỗng |
| Ghi metric **cuối cùng** và atomic (`> file.$$` rồi `mv`) | Metric chỉ phản ánh lần **thành công** trọn vẹn; node_exporter không đọc phải file dở |
| Tìm container theo nhãn Compose | Tên container có thể khác (`taskhub-postgres-1`, `taskhub_postgres_1`…) |

**B3.** Cả hai lệnh `AccessDenied`: inline policy `taskhub-ec2-s3-backup` (AWS 05) chỉ cho `PutObject`/`GetObject` trên `pg-dumps/*` và `ListBucket` với prefix `pg-dumps/`; không có `DeleteObject`, không có quyền ngoài prefix. Bản cũ hết hạn nhờ lifecycle — lifecycle do S3 thực hiện, không cần quyền của role.

**B4.** Kết quả mẫu (minh họa):

```text
$ systemctl list-timers taskhub-backup.timer
NEXT                         LEFT     LAST  PASSED  UNIT                  ACTIVATES
Fri 2026-11-20 18:04:31 UTC  8h left  -     -       taskhub-backup.timer  taskhub-backup.service
```

`NEXT` lệch vài phút khỏi 18:00 do `RandomizedDelaySec`. Nếu `systemd-analyze calendar` báo lỗi với hậu tố `UTC`, bỏ hậu tố đi — máy EC2 Ubuntu mặc định dùng múi giờ UTC (`timedatectl`), nhưng ghi rõ múi giờ vẫn tốt hơn.

**B5.** Chuỗi sự kiện mong đợi: ghi metric giả → trong vòng một chu kỳ scrape Prometheus thấy giá trị cũ → `TaskhubBackupStale` **pending** → sau `for: 10m` → **firing** → Alertmanager gửi Telegram (sau `group_wait`) → chạy backup thật → metric mới → rule hết đúng → **resolved** (có tin nhắn resolved nếu receiver bật `send_resolved`).

**B6.**

| # | Hiện tượng | Metric |
|---|---|---|
| E1 | `backup.sh: line …: aws: command not found`, `status=127`, service `failed` | Không đổi |
| E2 | `upload failed: … NoSuchBucket` (bucket không tồn tại) hoặc `AccessDenied` (bucket tồn tại nhưng không phải của bạn) | Không đổi |
| E3 | `LỖI: không thấy container postgres của project taskhub` | Không đổi |
| E4 | Object đã lên S3, rồi `Permission denied` khi ghi file `.prom.<pid>` → service `failed` | Không đổi |

E4 — cảnh báo **thật** theo nghĩa "hệ thống backup không còn đáng tin": bạn không thể phân biệt "backup ổn nhưng không ghi được metric" với "backup hỏng" nếu chỉ nhìn alert. Runbook nên có bước: "kiểm tra `aws s3 ls …/pg-dumps/` xem object mới nhất lúc nào" trước khi kết luận.

## Phần C

**C1** — đạt khi khớp S1–S6. Điểm quan trọng nhất: **S2** (từ chối restore đè database đang chạy) và chỉ `dropdb` database đích.

**C2** — kết quả mẫu (minh họa, dữ liệu nhỏ):

```text
Tải s3://taskhub-backups-111122223333/pg-dumps/taskhub-20261120T093001Z.dump ...
taskhub          tasks=12  flyway_version=1
taskhub_restore  tasks=11  flyway_version=1
Restore xong trong 3s (đây là một phần RTO của bạn).

real    0m4.902s
```

Chuyển đổi (stop app → đổi tên → start → health UP) thường mất thêm vài chục giây, chủ yếu là thời gian Spring Boot khởi động. RTO diễn tập ≈ **1–2 phút**. `grep -c after-backup-1` ra `0`.

`docs/dr-drills.md` mẫu:

```markdown
| Ngày | Loại | Kích thước dump | Tải | pg_restore | Downtime | RTO (T1−T0) | Mất dữ liệu (RPO) | Ghi chú |
|---|---|---|---|---|---|---|---|---|
| 2026-11-20 | Restore + swap trên EC2 | 11 KB | 1s | 2s | 38s | 1m24s | 1 task tạo sau backup | Spring Boot khởi động chiếm phần lớn downtime |
```

## Bài tập mở rộng

**1. Ansible.** Task mẫu:

```yaml
- name: Thư mục cấu hình backup
  ansible.builtin.file:
    path: /etc/taskhub
    state: directory
    mode: "0750"

- name: Biến môi trường cho backup (chỉ root đọc)
  ansible.builtin.copy:
    dest: /etc/taskhub/backup.env
    content: |
      BACKUP_BUCKET={{ taskhub_backup_bucket }}
      AWS_REGION={{ aws_region }}
    mode: "0600"

- name: Unit systemd của backup
  ansible.builtin.copy:
    src: "{{ item }}"
    dest: "/etc/systemd/system/{{ item }}"
    mode: "0644"
  loop:
    - taskhub-backup.service
    - taskhub-backup.timer
  notify: Reload systemd

- name: Bật timer backup
  ansible.builtin.systemd_service:
    name: taskhub-backup.timer
    enabled: true
    state: started
    daemon_reload: true
```

Handler `Reload systemd` dùng `ansible.builtin.systemd_service: daemon_reload: true`. `taskhub_backup_bucket` lấy từ output Terraform hoặc dựng từ account ID — không ghi cứng.

**2. Retention.** Rule thêm vào `aws_s3_bucket_lifecycle_configuration.backups` ở tầng `bootstrap`:

```hcl
  rule {
    id     = "expire-current-pg-dumps-after-35-days"
    status = "Enabled"

    filter {
      prefix = "pg-dumps/"
    }

    expiration {
      days = 35
    }
  }
```

Với versioning: sau 35 ngày object hiện hành bị S3 gắn delete marker (trở thành phiên bản cũ), rule có sẵn xóa phiên bản cũ sau 30 ngày nữa → một bản dump còn khôi phục được tối đa khoảng **65 ngày**; delete marker hết hạn được rule `remove-expired-delete-markers` dọn. Sửa bằng Terraform vì bucket do Terraform quản lý — sửa console sẽ bị `terraform apply` lần sau ghi đè (drift, Module 07).

**3. Bản sao thứ ba.** Tải về laptop hằng tuần: bảo vệ khỏi mất tài khoản AWS/xóa nhầm bucket/sự cố region; không bảo vệ khỏi mất laptop, và RPO của bản này là 1 tuần. Giữ 3 bản trên đĩa EC2: restore nhanh hơn (không cần tải) nhưng chết cùng máy/EBS — không phải offsite. Cả hai rẻ; kết hợp được.

**4.** Sau `aws s3 cp`:

```bash
remote_size="$(aws s3api head-object --bucket "$BUCKET" --key "$key" --query ContentLength --output text)"
[[ "$remote_size" == "$size" ]] || { echo "LỖI: kích thước S3 ($remote_size) khác local ($size)" >&2; exit 1; }
```

Cần quyền `s3:GetObject` (HeadObject dùng quyền này) — role đã có trên `pg-dumps/*`.

**5.** Cần bản cũ khi sự cố **đã nằm trong** bản mới nhất: ví dụ dữ liệu bị xóa nhầm lúc 15:00 nhưng không ai phát hiện tới hôm sau — bản backup đêm qua lúc 18:00 đã chứa trạng thái "bị xóa". Phải chọn bản **trước** thời điểm sự cố. Đó là lý do cần giữ nhiều bản theo thời gian, không chỉ bản mới nhất.
