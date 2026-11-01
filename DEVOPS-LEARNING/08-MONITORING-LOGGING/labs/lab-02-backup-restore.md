# Lab 02 — Backup PostgreSQL lên S3, diễn tập restore và đo RTO

> ⏱️ ~4 giờ (Phần A ~1,5 giờ trên laptop · Phần B ~2,5 giờ trên EC2) · Mức độ: 🟥 **Lab bắt buộc tuần 18**
> Kiến thức cần có trước: [Bài 06 — Incident response, backup/restore](../06-incident-response.md) (làm bài thực hành của bài 06 trước), [Bài 02 — Prometheus](../02-metrics-prometheus.md) (textfile collector), [AWS 05 — S3](../../06-AWS/05-s3.md) (bucket backup + inline policy `taskhub-ec2-s3-backup`), [Linux 08 — Cron & systemd timer](../../01-LINUX/08-cron-scheduling.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (Phần A) · `[EC2]` qua Session Manager, hạ tầng v4/v5 đã dựng bằng Terraform + Ansible (Phần B)
> Bản tham khảo (chỉ mở **sau khi** tự viết): [`scripts/backup.sh`](reference/scripts/backup.sh) · [`scripts/restore.sh`](reference/scripts/restore.sh) · [rule alert backup](reference/prometheus/rules/alerts.yml)

## Mục lục

- [Mục tiêu](#mục-tiêu)
- [Ước tính chi phí](#ước-tính-chi-phí)
- [Phần A — Laptop: dump, restore, chuyển đổi database](#phần-a--laptop-dump-restore-chuyển-đổi-database)
- [Phần B — EC2: backup tự động lên S3](#phần-b--ec2-backup-tự-động-lên-s3)
- [Phần C — Diễn tập restore và đo RTO](#phần-c--diễn-tập-restore-và-đo-rto)
- [Kết quả mong đợi](#kết-quả-mong-đợi)
- [Các lỗi thường gặp](#các-lỗi-thường-gặp)
- [Dọn dẹp](#dọn-dẹp)
- [Bài tập mở rộng](#bài-tập-mở-rộng)
- [Checklist hoàn thành](#checklist-hoàn-thành)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## Mục tiêu

Sau lab này, repo `taskhub` có:

- `scripts/backup.sh` — backup database lên S3, chạy trên **host** EC2 theo lịch, ghi metric khi thành công.
- `scripts/restore.sh` — restore một bản backup vào **database mới** và so sánh số dòng.
- Unit `systemd` (service + timer) chạy backup hằng ngày.
- `docs/runbooks/restore.md` — các bước restore và chuyển đổi, kèm **RTO đã đo**.
- Bằng chứng: alert `TaskhubBackupStale` đã từng firing và resolved.

Và bạn trả lời được bằng số liệu thật: *"Nếu mất database bây giờ, bạn mất tối đa bao nhiêu dữ liệu và mất bao lâu để khôi phục?"*

## Ước tính chi phí

| Hạng mục | Chi phí | Ghi chú |
|---|---|---|
| Phần A (laptop) | 0 USD | |
| EC2 v5 (`c7i-flex.large`) | Theo giờ chạy — đã tính ở [milestone v5](../../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) | Lab không tạo thêm máy. **Stop** máy sau buổi học |
| S3 Standard lưu dump | 0,025 USD/GB-tháng ở ap-southeast-1 (kiểm tra 2026-10-31) | Dump của `taskhub` cỡ vài chục KB → gần 0 |
| Request S3 (PUT/GET/LIST) | Rất nhỏ | Vài chục request mỗi ngày |

⚠️ Lab **không** tạo tài nguyên AWS mới. Bucket `taskhub-backups-<account-id>` đã có từ AWS bài 05 và được Terraform quản lý ở tầng `bootstrap` (v4).

---

## Phần A — Laptop: dump, restore, chuyển đổi database

### A1. Chuẩn bị `[WSL]`

Stack `taskhub` (app + postgres + nginx) phải đang chạy. Cổng 8000 trên máy bạn đã bị chiếm, nên dùng cổng khác (ví dụ 8088):

```bash
cd ~/projects/taskhub
grep -q '^NGINX_HOST_PORT=' .env || echo 'NGINX_HOST_PORT=8088' >> .env
docker compose up -d --wait
docker compose ps
mkdir -p ~/devops-lab/08-monitoring/backup
export APP=http://localhost:$(sed -n 's/^NGINX_HOST_PORT=//p' .env)
curl -fsS "$APP/actuator/health"; echo
```

Tạo vài task để có dữ liệu:

```bash
for i in 1 2 3 4 5; do
  curl -fsS -X POST "$APP/api/tasks" -H 'Content-Type: application/json' \
    -d "{\"title\":\"backup-lab task $i\"}" > /dev/null
done
docker compose exec -T postgres psql -U taskhub -d taskhub -tAc 'select count(*) from tasks'
```

Ghi lại con số này (gọi là **N0**).

### A2. Dump `[WSL]`

```bash
docker compose exec -T postgres pg_dump -U taskhub -d taskhub -Fc \
  > ~/devops-lab/08-monitoring/backup/taskhub-$(date -u +%Y%m%dT%H%M%SZ).dump
ls -lh ~/devops-lab/08-monitoring/backup/
```

❓ Vì sao bắt buộc `-T`? (Bài 06 §8.) Thử **cố ý** bỏ `-T` một lần, ra file khác, rồi so kích thước và chạy bước A3 với file đó. Ghi lại hiện tượng vào nhật ký debug.

### A3. Kiểm tra file dump đọc được `[WSL]`

```bash
DUMP=$(ls -t ~/devops-lab/08-monitoring/backup/taskhub-*.dump | head -n1)
docker compose exec -T postgres pg_restore --list < "$DUMP" | head -20
```

Mong đợi: phần đầu có `Format: CUSTOM` và các dòng `TABLE public tasks`, `TABLE DATA public tasks`, `flyway_schema_history`.

### A4. "Sự cố": xóa nhầm dữ liệu `[WSL]`

⚠️ Chỉ làm trên laptop:

```bash
docker compose exec -T postgres psql -U taskhub -d taskhub -c "delete from tasks where title like 'backup-lab%'"
docker compose exec -T postgres psql -U taskhub -d taskhub -tAc 'select count(*) from tasks'
```

Tạo thêm **1 task mới sau khi backup** (để thấy RPO):

```bash
curl -fsS -X POST "$APP/api/tasks" -H 'Content-Type: application/json' -d '{"title":"created-after-backup"}'
```

### A5. Restore vào database **mới** `[WSL]`

```bash
docker compose exec -T postgres createdb -U taskhub taskhub_restore
docker compose exec -T postgres pg_restore -U taskhub -d taskhub_restore \
  --no-owner --exit-on-error < "$DUMP"

q() { docker compose exec -T postgres psql -U taskhub -d "$1" -tAc "$2"; }
for db in taskhub taskhub_restore; do
  printf '%-16s tasks=%s  flyway_version=%s\n' "$db" \
    "$(q "$db" 'select count(*) from tasks')" \
    "$(q "$db" 'select max(version::int) from flyway_schema_history where success')"
done
```

Mong đợi: `taskhub_restore` có **N0** task, `taskhub` có ít hơn (đã xóa) **+1** task "created-after-backup". Cùng phiên bản Flyway.

### A6. Chuyển đổi (swap) `[WSL]`

App phải dừng — PostgreSQL không cho đổi tên database đang có kết nối:

```bash
date -u +%FT%TZ                                    # mốc bắt đầu chuyển đổi
docker compose stop taskhub
docker compose exec -T postgres psql -U taskhub -d postgres -c 'ALTER DATABASE taskhub RENAME TO taskhub_broken'
docker compose exec -T postgres psql -U taskhub -d postgres -c 'ALTER DATABASE taskhub_restore RENAME TO taskhub'
docker compose start taskhub
docker compose up -d --wait
curl -fsS "$APP/actuator/health"; echo
curl -fsS "$APP/api/tasks" | grep -o '"title":"[^"]*"'
date -u +%FT%TZ                                    # mốc kết thúc
```

Kiểm tra: 5 task `backup-lab` đã quay lại; task `created-after-backup` **không có** — đó là dữ liệu nằm trong khoảng **RPO** (tạo sau thời điểm backup).

❓ Nếu đây là sự cố thật, task `created-after-backup` có cứu được không? (Gợi ý: nó vẫn nằm trong `taskhub_broken`.) Viết câu SQL để chép riêng nó sang. Đây là lý do **không xóa** database hỏng ngay.

### A7. Dọn Phần A `[WSL]`

Sau khi đã ghi chép xong:

```bash
docker compose exec -T postgres dropdb -U taskhub taskhub_broken      # ⚠️ chắc chắn đó là DB cũ
docker compose exec -T postgres psql -U taskhub -d postgres -tAc '\l' | cut -d'|' -f1
```

---

## Phần B — EC2: backup tự động lên S3

### B1. Tự viết `scripts/backup.sh` theo đặc tả `[WSL]`

Viết trong repo `taskhub` (nhánh `feat/db-backup`), **chưa** mở bản tham khảo. Đặc tả — giống interface của bản tham khảo để sau này so sánh được:

| # | Yêu cầu |
|---|---|
| R1 | `#!/usr/bin/env bash` + `set -euo pipefail`. Chạy trên **host** bằng root, không trong container (container không có quyền AWS vì IMDS hop limit 1 — [AWS 04](../../06-AWS/04-ec2.md)) |
| R2 | Cấu hình bằng biến môi trường: `BACKUP_BUCKET` (**bắt buộc**, thiếu thì báo lỗi rõ ràng), `BACKUP_PREFIX` (mặc định `pg-dumps`), `COMPOSE_PROJECT` (mặc định `taskhub`), `DB_NAME`/`DB_USER` (mặc định `taskhub`), `TEXTFILE_DIR` (mặc định `/var/lib/node_exporter/textfile_collector`) |
| R3 | Tìm container postgres theo **nhãn Compose** (`com.docker.compose.project`, `com.docker.compose.service`), không phụ thuộc tên container; không thấy → exit khác 0 |
| R4 | `pg_dump -Fc` chạy **trong** container postgres (cùng phiên bản server), ghi ra **file tạm** trên host; file tạm luôn bị xóa khi script kết thúc (kể cả khi lỗi — `trap`) |
| R5 | Kiểm tra file đọc được bằng `pg_restore --list` trước khi upload |
| R6 | Upload lên `s3://$BACKUP_BUCKET/$BACKUP_PREFIX/taskhub-<UTC YYYYmmddTHHMMSSZ>.dump` — tên sắp xếp theo chữ = theo thời gian |
| R7 | **Chỉ khi mọi bước thành công**: ghi `taskhub_backup_last_success_timestamp_seconds` (và kích thước, thời gian chạy) vào `$TEXTFILE_DIR/taskhub_backup.prom` theo kiểu ghi file tạm rồi `mv` |
| R8 | In một dòng kết quả `OK: s3://… (<bytes> bytes, <s>s)`; lỗi thì exit khác 0 và in lỗi ra stderr |

Kiểm tra cú pháp: `bash -n scripts/backup.sh`. Commit, mở PR, merge.

Đưa script lên EC2 bằng **Ansible** (role `taskhub` copy cả thư mục `scripts/` — v4), không chép tay qua Session Manager:

```bash
cd ~/projects/taskhub/infra/ansible
ansible-playbook playbooks/site.yml --diff
```

### B2. Chạy tay lần đầu `[EC2]`

Mở Session Manager vào `taskhub-app` ([AWS 04](../../06-AWS/04-ec2.md)), rồi:

```bash
sudo -i
export PATH="$PATH:/snap/bin"                       # AWS CLI v2 cài bằng snap (role docker của v4)
aws sts get-caller-identity --query Arn --output text
# arn:aws:sts::111122223333:assumed-role/taskhub-ec2-role/i-0abc...   (minh họa)
install -d -m 0755 /var/lib/node_exporter/textfile_collector     # nếu Ansible role monitoring chưa tạo
export BACKUP_BUCKET="taskhub-backups-$(aws sts get-caller-identity --query Account --output text)"
export AWS_REGION=ap-southeast-1
time /opt/taskhub/scripts/backup.sh
```

Kết quả mẫu (minh họa):

```text
OK: s3://taskhub-backups-111122223333/pg-dumps/taskhub-20261120T091203Z.dump (10342 bytes, 2s)

real    0m3.418s
```

Kiểm chứng ba nơi:

```bash
aws s3 ls "s3://${BACKUP_BUCKET}/pg-dumps/"
cat /var/lib/node_exporter/textfile_collector/taskhub_backup.prom
curl -s 'http://127.0.0.1:9090/api/v1/query?query=taskhub_backup_last_success_timestamp_seconds' ; echo
```

Prometheus trên EC2 chỉ nghe ở `127.0.0.1:9090` (không mở ra Internet). Muốn xem bằng Grafana trên laptop: SSM port forwarding như bài 03.

### B3. Chứng minh quyền tối thiểu `[EC2]`

```bash
aws s3 rm "s3://${BACKUP_BUCKET}/pg-dumps/$(aws s3 ls "s3://${BACKUP_BUCKET}/pg-dumps/" | awk '{print $4}' | tail -n1)"
# delete failed: ... An error occurred (AccessDenied) ...   (minh họa)
aws s3 cp /etc/hostname "s3://${BACKUP_BUCKET}/lab/x.txt"
# upload failed: ... AccessDenied   (minh họa)
```

❓ Vì sao **không** cho máy chủ quyền xóa backup? (Gợi ý: kẻ tấn công chiếm được EC2, hoặc một script lỗi chạy `rm` — backup vẫn còn. Bản cũ hết hạn nhờ **lifecycle** của bucket, không nhờ script.)

### B4. Lên lịch bằng systemd timer `[EC2]`

Vì sao **systemd timer** thay vì cron (đã so sánh ở [Linux 08 §4.8](../../01-LINUX/08-cron-scheduling.md#48--systemd-timer--lựa-chọn-hiện-đại-thay-cho-cron)): bạn **stop EC2 khi không học**. Với `Persistent=true`, systemd lưu thời điểm chạy gần nhất xuống đĩa và chạy bù lần bị lỡ ngay khi máy bật lại; cron đơn thuần thì bỏ qua lần đó. Ngoài ra log nằm sẵn trong `journalctl`.

File biến môi trường (chỉ root đọc):

```bash
install -d -m 0750 /etc/taskhub
cat > /etc/taskhub/backup.env <<EOF
BACKUP_BUCKET=${BACKUP_BUCKET}
AWS_REGION=ap-southeast-1
EOF
chmod 0600 /etc/taskhub/backup.env
```

Service — `/etc/systemd/system/taskhub-backup.service`:

```ini
[Unit]
Description=Backup PostgreSQL taskhub lên S3
Wants=network-online.target
After=network-online.target docker.service

[Service]
Type=oneshot
# PATH mặc định của systemd KHÔNG có /snap/bin — thiếu dòng này thì "aws: command not found"
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
EnvironmentFile=/etc/taskhub/backup.env
ExecStart=/opt/taskhub/scripts/backup.sh
```

Timer — `/etc/systemd/system/taskhub-backup.timer`:

```ini
[Unit]
Description=Chạy taskhub-backup hằng ngày lúc 18:00 UTC (01:00 giờ Việt Nam)

[Timer]
OnCalendar=*-*-* 18:00:00 UTC
RandomizedDelaySec=10m
Persistent=true

[Install]
WantedBy=timers.target
```

| Dòng | Ý nghĩa (theo man page `systemd.timer`) |
|---|---|
| `OnCalendar=` | Hẹn giờ theo đồng hồ thực, cú pháp calendar event. Kiểm tra bằng `systemd-analyze calendar '*-*-* 18:00:00 UTC'` |
| `RandomizedDelaySec=10m` | Trễ ngẫu nhiên 0–10 phút, tránh nhiều job cùng chạy đúng một giây |
| `Persistent=true` | Lưu thời điểm chạy gần nhất xuống đĩa; lần bị lỡ (máy tắt) được chạy bù khi timer khởi động lại |

```bash
systemd-analyze calendar '*-*-* 18:00:00 UTC'
systemctl daemon-reload
systemctl enable --now taskhub-backup.timer
systemctl list-timers taskhub-backup.timer
systemctl start taskhub-backup.service          # chạy thử ngay, không chờ 18:00
journalctl -u taskhub-backup.service -n 20 --no-pager
```

Ở milestone v5, role Ansible `monitoring` (hoặc `taskhub`) phải tạo hai unit này và file env bằng `template` — làm tay ở đây để **hiểu**, rồi chuyển vào Ansible (bài tập 1).

### B5. Chứng minh alert backup hoạt động `[EC2]` `[Browser]`

Không ai muốn chờ 26 giờ. Giả lập "backup cuối cùng là 30 giờ trước" bằng cách ghi metric giả — **đúng kiểu atomic** như script:

```bash
f=/var/lib/node_exporter/textfile_collector/taskhub_backup.prom
cp "$f" /root/taskhub_backup.prom.real                       # giữ bản thật
old=$(date -d '30 hours ago' +%s)
sed "s/^taskhub_backup_last_success_timestamp_seconds .*/taskhub_backup_last_success_timestamp_seconds ${old}/" \
  /root/taskhub_backup.prom.real > "${f}.$$" && mv "${f}.$$" "$f"
```

Rule `TaskhubBackupStale` có `for: 10m`. Theo dõi trạng thái **pending → firing** ở Prometheus (Alerts) hoặc Grafana qua SSM port forwarding; chờ tin nhắn Telegram. Sau đó chạy backup thật để alert **resolved**:

```bash
systemctl start taskhub-backup.service
journalctl -u taskhub-backup.service -n 5 --no-pager
```

Ghi vào `docs/dr-drills.md`: giờ ghi metric giả, giờ alert pending, giờ firing, giờ nhận Telegram, giờ resolved.

### B6. Phá để hiểu `[EC2]`

Làm từng thí nghiệm, đọc `journalctl -u taskhub-backup.service`, khôi phục rồi mới làm cái tiếp theo:

| # | Phá | Mong đợi quan sát | Metric có bị cập nhật không? |
|---|---|---|---|
| E1 | Xóa dòng `Environment=PATH=…` khỏi service, `daemon-reload`, start | `aws: command not found`, service `failed` | Không |
| E2 | Đổi `BACKUP_BUCKET` trong `/etc/taskhub/backup.env` thành bucket không tồn tại | `NoSuchBucket` hoặc `AccessDenied` | Không |
| E3 | `docker compose -p taskhub stop postgres` rồi start service | Script báo không thấy container postgres | Không |
| E4 | `chmod 000` thư mục textfile rồi start (nhớ `chmod 755` lại) | Upload S3 **thành công** nhưng ghi metric lỗi → service `failed` | Không — và vì sao như vậy lại **đúng**? |

❓ Ở E4, backup đã lên S3 nhưng alert vẫn sẽ kêu sau 26 giờ. Đó là cảnh báo giả hay thật? Bạn sẽ ghi điều này vào runbook thế nào?

---

## Phần C — Diễn tập restore và đo RTO

### C1. Tự viết `scripts/restore.sh` `[WSL]`

Đặc tả (giống interface bản tham khảo):

| # | Yêu cầu |
|---|---|
| S1 | `set -euo pipefail`; dùng cùng biến `BACKUP_BUCKET`, `BACKUP_PREFIX`, `COMPOSE_PROJECT`, `DB_NAME`, `DB_USER` như backup.sh; thêm `TARGET_DB` (mặc định `taskhub_restore`) |
| S2 | **Từ chối** nếu `TARGET_DB` trùng `DB_NAME` — script này không bao giờ restore đè database đang chạy |
| S3 | Đối số thứ nhất (tùy chọn): key S3 cụ thể; không có → lấy bản **mới nhất** trong prefix |
| S4 | Tải về file tạm (xóa bằng `trap`), `dropdb --if-exists` + `createdb` **chỉ** với `TARGET_DB`, `pg_restore --no-owner --exit-on-error` |
| S5 | In so sánh số dòng `tasks` và phiên bản Flyway lớn nhất giữa `DB_NAME` và `TARGET_DB`, và thời gian restore |
| S6 | In ra (không tự chạy) các bước chuyển đổi — chuyển đổi là quyết định của con người |

### C2. Diễn tập có bấm giờ `[EC2]`

Kịch bản: "database bị hỏng lúc T0, ta khôi phục từ bản backup gần nhất". Chuẩn bị một backup mới, rồi tạo dữ liệu **sau** backup để đo RPO:

```bash
sudo -i
export PATH="$PATH:/snap/bin"; set -a; . /etc/taskhub/backup.env; set +a
systemctl start taskhub-backup.service
APP=http://localhost:80
curl -fsS -X POST "$APP/api/tasks" -H 'Content-Type: application/json' -d '{"title":"after-backup-1"}' > /dev/null
date -u +%FT%TZ | tee /root/drill-T0.txt          # T0: "phát hiện sự cố, quyết định restore"
```

Bước 1 — restore vào database mới (không ảnh hưởng người dùng):

```bash
time /opt/taskhub/scripts/restore.sh
```

Bước 2 — chuyển đổi (có downtime, làm theo đúng các bước script in ra):

```bash
cd /opt/taskhub
docker compose -p taskhub stop taskhub
pg=$(docker ps -q --filter label=com.docker.compose.project=taskhub --filter label=com.docker.compose.service=postgres)
docker exec "$pg" psql -U taskhub -d postgres -c 'ALTER DATABASE taskhub RENAME TO taskhub_broken'
docker exec "$pg" psql -U taskhub -d postgres -c 'ALTER DATABASE taskhub_restore RENAME TO taskhub'
docker compose -p taskhub start taskhub
until curl -fsS "$APP/actuator/health" | grep -q '"status":"UP"'; do sleep 2; done
date -u +%FT%TZ | tee /root/drill-T1.txt          # T1: dịch vụ chạy lại với dữ liệu đã khôi phục
curl -fsS "$APP/api/tasks" | grep -c 'after-backup-1' || true     # 0 = dữ liệu sau backup đã mất (RPO)
```

**RTO đo được = T1 − T0.** Ghi vào `docs/dr-drills.md` cùng: kích thước dump, thời gian tải, thời gian `pg_restore`, thời gian downtime (từ `stop` đến health `UP`), số task bị mất.

Ở môi trường thật còn thêm thời gian phát hiện, quyết định, giao tiếp. RTO của diễn tập là **cận dưới**.

### C3. Quay về dữ liệu ban đầu `[EC2]`

Diễn tập xong, đưa database gốc (có `after-backup-1`) trở lại — chính là thao tác "cứu dữ liệu trong khoảng RPO" ở mức thô:

```bash
docker compose -p taskhub stop taskhub
docker exec "$pg" psql -U taskhub -d postgres -c 'ALTER DATABASE taskhub RENAME TO taskhub_drill'
docker exec "$pg" psql -U taskhub -d postgres -c 'ALTER DATABASE taskhub_broken RENAME TO taskhub'
docker compose -p taskhub start taskhub
until curl -fsS "$APP/actuator/health" | grep -q '"status":"UP"'; do sleep 2; done
docker exec "$pg" dropdb -U taskhub taskhub_drill                  # ⚠️ đây là bản diễn tập
```

### C4. Viết runbook restore `[WSL]`

`docs/runbooks/restore.md`: khi nào restore (và khi nào **không** — ví dụ chỉ một vài dòng bị sai thì sửa bằng SQL có review), các bước C2 dưới dạng chép-dán được, cách chọn bản backup (bản mới nhất? bản trước thời điểm xóa nhầm?), cách cứu dữ liệu nằm trong khoảng RPO từ `taskhub_broken`, RTO đã đo kèm ngày đo, lịch diễn tập hằng tháng.

---

## Kết quả mong đợi

| Bước | Kết quả |
|---|---|
| A5 | `taskhub_restore` có N0 task; `taskhub` (sau khi xóa) có ít hơn + `created-after-backup` |
| A6 | Sau chuyển đổi: 5 task `backup-lab` trở lại, `created-after-backup` mất (RPO) |
| B2 | Dòng `OK: s3://…`; object xuất hiện trong `pg-dumps/`; Prometheus trả về giá trị metric |
| B3 | `aws s3 rm` và upload ngoài `pg-dumps/` đều `AccessDenied` |
| B4 | `systemctl list-timers` hiện `taskhub-backup.timer` với lần chạy kế tiếp lúc 18:00 UTC (+ trễ ngẫu nhiên) |
| B5 | `TaskhubBackupStale`: pending → firing sau ~10 phút → Telegram → resolved sau khi chạy backup thật |
| B6 | Mỗi thí nghiệm: service `failed`, metric **không** đổi |
| C2 | RTO đo được (thường vài chục giây đến vài phút với dữ liệu nhỏ); `after-backup-1` không có sau chuyển đổi |

So sánh với [lời giải](../solutions/lab-02-solutions.md) sau khi tự làm.

## Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `pg_restore: error: input file does not appear to be a valid archive` | Dump bằng `docker compose exec` **không** có `-T`, hoặc file rỗng | Dump lại với `-T`; `file <dump>` phải ra "PostgreSQL custom database dump" |
| `the input device is not a TTY` | `docker exec -it` / `compose exec` có TTY trong khi stdin là file/pipe | Dùng `-i` (không `-t`) với `docker exec`; `-T` với `compose exec` |
| `ERROR: database "taskhub" is being accessed by other users` | App chưa dừng khi đổi tên | `docker compose stop taskhub` trước |
| Chạy tay được, timer chạy thì `aws: command not found` | `PATH` của systemd không có `/snap/bin` | `Environment=PATH=…:/snap/bin` trong service |
| `Unable to locate credentials` | Chạy trong container (hop limit 1) hoặc instance mất role | Chạy trên host; `aws sts get-caller-identity` |
| `AccessDenied` khi `PutObject` | Sai prefix (không phải `pg-dumps/`), sai bucket, thiếu inline policy `taskhub-ec2-s3-backup` | `aws iam get-role-policy --role-name taskhub-ec2-role --policy-name taskhub-ec2-s3-backup` (từ laptop) |
| Metric không xuất hiện trong Prometheus | node-exporter không mount đúng thư mục textfile, hoặc file không đuôi `.prom` | `docker inspect` node-exporter xem volume; tên file `*.prom` |
| `TaskhubBackupMetricMissing` firing ngay sau khi dựng lại máy (v4 `apply` mới) | Máy mới chưa có file metric | Bình thường — chạy backup một lần; ghi vào runbook |
| `Failed to parse calendar specification` | Sai cú pháp `OnCalendar` | `systemd-analyze calendar '<biểu thức>'` |

## Dọn dẹp

- `[WSL]` Đã xóa `taskhub_broken` ở A7. Giữ thư mục `~/devops-lab/08-monitoring/backup/` (vài KB) hoặc xóa.
- `[EC2]` Đảm bảo không còn `taskhub_restore`, `taskhub_broken`, `taskhub_drill`:

  ```bash
  docker exec "$pg" psql -U taskhub -d postgres -tAc "select datname from pg_database where datname like 'taskhub%'"
  # chỉ còn: taskhub
  ```

- `[EC2]` Nếu đã làm B5: chắc chắn file metric là bản thật (chạy `systemctl start taskhub-backup.service` một lần).
- **Giữ** timer và các object trong `pg-dumps/` — đó là sản phẩm của v5.
- Kết thúc buổi học: **stop** EC2 (`aws ec2 stop-instances`) hoặc `terraform destroy` tầng `envs/dev` theo v4 — bucket backup ở tầng `bootstrap` **không** bị xóa. Kiểm tra sót tài nguyên: `~/devops-lab/06-aws/find-leftovers.sh`.

## Bài tập mở rộng

1. **Ansible hóa.** Đưa `/etc/taskhub/backup.env` (template, `mode: "0600"`), hai unit systemd và việc `enable --now` timer vào role Ansible. Chạy playbook hai lần: lần hai phải `changed=0`. Nhớ handler `systemd daemon_reload`.
2. **Retention cho bản hiện hành.** Lifecycle hiện tại (tầng `bootstrap` ở v4) chỉ xóa **phiên bản cũ** sau 30 ngày; object hiện hành trong `pg-dumps/` sống mãi. Thêm rule trong Terraform `bootstrap`: object hiện hành dưới prefix `pg-dumps/` hết hạn sau 35 ngày. Giải thích tổng thời gian một bản dump còn khôi phục được (có versioning). Vì sao sửa bằng Terraform chứ không bằng console?
3. **Bản sao thứ ba.** Thiết kế cách đạt 3-2-1 cho `taskhub` với chi phí ≈ 0 (ví dụ: script trên laptop tải bản dump mới nhất mỗi tuần qua `aws s3 cp`; hoặc giữ 3 bản gần nhất trên đĩa EC2). Phân tích mỗi cách bảo vệ khỏi rủi ro nào và **không** bảo vệ khỏi rủi ro nào.
4. **Kiểm tra kích thước sau upload.** Thêm vào `backup.sh` bước so kích thước object S3 (`aws s3api head-object --query ContentLength`) với file local; khác nhau → exit 1, không ghi metric.
5. **Restore từ một bản cũ hơn.** Dùng `aws s3api list-object-versions` để tìm một **phiên bản cũ** của một object (hoặc một key cũ hơn), restore nó bằng `restore.sh <key>`. Khi nào bạn cần bản cũ thay vì bản mới nhất?

## Checklist hoàn thành

- [ ] Phần A: restore vào DB mới, chuyển đổi, giải thích được task nào mất và vì sao (RPO).
- [ ] `scripts/backup.sh` và `scripts/restore.sh` của **bạn** đạt R1–R8, S1–S6, qua `bash -n`, đã merge qua PR.
- [ ] Timer chạy hằng ngày, `Persistent=true`, có log trong `journalctl`.
- [ ] Chứng minh được role EC2 **không** xóa được backup.
- [ ] Alert `TaskhubBackupStale` đã firing và resolved (có ghi giờ).
- [ ] `docs/dr-drills.md` có RTO đo được và số dữ liệu mất; `docs/runbooks/restore.md` hoàn chỉnh.
- [ ] Đã so sánh script của bạn với [bản tham khảo](reference/scripts/backup.sh) và ghi lại 2 điểm khác nhau + lý do.

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [PostgreSQL 17 — pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html) | `-Fc`, tính nhất quán, không chặn người dùng | 2026-10-31 |
| [PostgreSQL 17 — pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html) | `--list`, `--no-owner`, `--exit-on-error`, đọc stdin | 2026-10-31 |
| [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) | `OnCalendar`, `Persistent`, `RandomizedDelaySec` | 2026-10-31 |
| [node_exporter — Textfile Collector](https://github.com/prometheus/node_exporter) | `--collector.textfile.directory`, file `*.prom`, ghi file tạm rồi `mv` | 2026-10-31 |
| [GitLab — Postmortem of database outage of January 31](https://about.gitlab.com/blog/2017/02/10/postmortem-of-database-outage-of-january-31/) | Vì sao phải kiểm tra và giám sát backup | 2026-10-31 |
