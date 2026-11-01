# Lời giải — Bài 07. RDS

> Chỉ mở sau khi đã tự làm. Bài: [07-rds.md](../07-rds.md). Giá trong lời giải là giá Singapore khi kiểm tra 2026-10-31 — hãy tự kiểm tra lại.

## Câu hỏi trong phần thực hành

**Bước 2 — `| [-1]`.** `describe-db-engine-versions` trả danh sách phiên bản theo thứ tự tăng dần (bỏ `| [-1]` sẽ thấy `17.7 ... 17.11`). `[-1]` trong JMESPath là phần tử cuối → bản mới nhất. Đây là quan sát từ kết quả, không phải cam kết của API; nếu cần chắc chắn tuyệt đối, sắp xếp lại hoặc kiểm tra thêm thuộc tính `Status`.

**Bước 8 — dòng `C`.** Không có. `pg_dump` chụp trạng thái **tại thời điểm dump**; mọi thứ ghi sau đó (dòng `C`) không nằm trong file. Muốn khôi phục về "14:31" cần **base backup + WAL archiving** liên tục (PostgreSQL ghi mọi thay đổi vào WAL; lưu WAL lại thì phát lại được đến thời điểm bất kỳ). RDS làm đúng việc đó: snapshot hằng ngày + tải log giao dịch lên S3 mỗi 5 phút.

## Câu hỏi kiểm tra kiến thức

1. **RDS làm thay:** vá OS của máy database; cài bản vá nhỏ PostgreSQL trong maintenance window; backup tự động + PITR; (khi bật) Multi-AZ và failover; thay phần cứng hỏng. **Bạn vẫn làm:** thiết kế schema/index, tối ưu truy vấn; kiểm soát truy cập (mạng, SG, mật khẩu, quyền SQL); quyết định nâng phiên bản lớn; đặt alarm, theo dõi dung lượng; diễn tập khôi phục.
2. Để RDS có chỗ đặt standby/instance thay thế ở AZ khác khi bật Multi-AZ hoặc khi AWS cần thay máy. Tài liệu yêu cầu subnet group có subnet ở ít nhất 2 AZ, và khuyên làm vậy cả với Single-AZ.
3. Không đủ. `Public access = No` chỉ bỏ IP public. Mọi máy trong VPC (hoặc mạng nối với VPC) vẫn có thể kết nối nếu SG cho phép. Cần SG chỉ cho **SG app** vào 5432, subnet private, mật khẩu mạnh, SSL (`rds.force_ssl`).
4. Rule theo SG chỉ cho ENI mang SG app vào (không phải mọi máy trong VPC), tự đúng khi ASG thay IP, và thể hiện rõ ý đồ. Rule theo dải `/16` mở cho mọi thứ trong VPC — kể cả máy bị chiếm quyền không liên quan.
5. `db.t4g.micro` Multi-AZ: 0,051 × 730 ≈ 37,23 USD. Storage Multi-AZ có **đơn giá riêng**: gp3 Multi-AZ ở Singapore là 0,276 USD/GB-tháng (gấp đôi Single-AZ, vì dữ liệu nằm ở cả primary và standby) → 20 × 0,276 = 5,52 USD. Tổng ≈ **42,75 USD/tháng**. Điểm dễ sai: lấy giá storage Single-AZ cho Multi-AZ.
6. Snapshot ổ đĩa hằng ngày (trong backup window) và log giao dịch tải lên S3 mỗi 5 phút. **Log** cho phép PITR — snapshot chỉ cho mốc hằng ngày.
7. Không. PITR luôn tạo **instance mới** (endpoint mới). Sau đó: (1) gắn đúng SG (và subnet group) — nếu không app không kết nối được; (2) gắn custom parameter group nếu có (restore bằng console dùng group mặc định); rồi đổi endpoint trong cấu hình app.
8. Multi-AZ instance: standby **đồng bộ**, **không đọc được**, mục đích **sẵn sàng cao** (failover). Read replica: **bất đồng bộ**, **đọc được**, mục đích **mở rộng đọc** (có thể "promote" thành instance độc lập, nhưng không tự failover như Multi-AZ).
9. RDS đổi bản ghi **DNS** của endpoint sang standby (thường 60–120 giây). JVM cache kết quả DNS; nếu TTL cache quá dài (hoặc vô hạn), app vẫn gọi IP cũ đã chết → lỗi kéo dài. Tài liệu khuyên TTL ≤ 60 giây; connection pool phải bỏ kết nối hỏng và mở lại.
10. CLI/API không ghi tham số → **bật** Extended Support (`open-source-rds-extended-support`) → sau ngày hết hỗ trợ chuẩn bị tính phí. Console → **không** chọn mặc định → sau ngày hết hỗ trợ chuẩn RDS tự nâng phiên bản lớn.
11. PostgreSQL 14 hết hỗ trợ chuẩn trên RDS ngày 28/02/2027 (community EOL 12/11/2026). Học tuần 14 vào khoảng đầu 2027 → sát hoặc qua ngày đó → hoặc bị tính Extended Support, hoặc bị nâng cấp tự động, và lệch với `postgres:17` của dự án.
12. Xóa instance **không chụp snapshot cuối** → dữ liệu mất vĩnh viễn (trừ snapshot thủ công có sẵn). Chỉ dùng cho môi trường không có dữ liệu cần giữ (lab, môi trường tạm dựng lại được).
13. Bị từ chối, lỗi dạng `no pg_hba.conf entry for host ... no encryption`. Vì từ PostgreSQL 15, `rds.force_ssl` mặc định là 1 — mọi kết nối không SSL bị từ chối.
14. Ví dụ: (a) cần chạy **nhiều instance app** sau ALB/ASG — cần database dùng chung, không thể mỗi EC2 một PostgreSQL; (b) yêu cầu **RPO/RTO** chặt (mất tối đa vài phút dữ liệu, chạy lại trong vài phút khi một AZ sự cố) vượt khả năng tự vận hành; (c) dữ liệu có giá trị thật và đội không đủ người trực vận hành database.

## Bài tập tự làm

**Bài 1 — Tính tiền (khung đáp án, dùng giá 2026-10-31).**

| Phương án | Compute | Storage 20 GB | Backup (25 GB snapshot, miễn phí 20 GB) | Tổng/tháng |
|---|---|---|---|---|
| (a) Docker trên `t3.small` sẵn có | 0 (đã trả cho EC2) | Nằm trong EBS 20 GB của EC2 (đã trả) | Bạn tự lưu `pg_dump` lên S3 — vài cent | ~0 thêm |
| (b) `db.t4g.micro` Single-AZ | 0,025 × 730 = 18,25 | 2,76 | (25 − 20) × 0,095 = 0,48 | ≈ 21,5 USD |
| (c) `db.t4g.micro` Multi-AZ | 0,051 × 730 = 37,23 | 20 × 0,276 = 5,52 | (25 − 20) × 0,095 = 0,48 | ≈ 43,2 USD |

Bài đạt khi mỗi con số có nguồn và ngày kiểm tra, và bạn ghi rõ giả định (730 giờ/tháng, không tính data transfer).

**Bài 2 — Thiết kế mạng.** Subnet group: `taskhub-private-a`, `taskhub-private-b`. `taskhub-db-sg`: inbound TCP 5432 nguồn `sg-<taskhub-web-sg>`; outbound: mặc định (cho phép tất cả) chấp nhận được, hoặc thu hẹp — RDS không cần chủ động ra ngoài. Chứng minh laptop không kết nối được: endpoint phân giải ra IP private `10.20.x.x` (không định tuyến được từ Internet); không có IP public (`Public access = No`); kể cả có đường đi, SG chỉ cho SG web. Bằng chứng: `timeout 5 bash -c '</dev/tcp/<endpoint>/5432'` thất bại từ WSL.

**Bài 3 — Runbook PITR (các bước chính).**

1. Xác định thời điểm an toàn: 14:31 giờ VN = **07:31Z**. Kiểm tra `LatestRestorableTime` ≥ thời điểm đó.
2. `restore-db-instance-to-point-in-time --source-db-instance-identifier taskhub-pg --target-db-instance-identifier taskhub-pg-0731 --restore-time 2027-03-15T07:31:00Z --db-subnet-group-name taskhub-db-subnets --vpc-security-group-ids <db-sg> --no-publicly-accessible` (+ `--db-parameter-group-name` nếu có custom group).
3. `aws rds wait db-instance-available --db-instance-identifier taskhub-pg-0731`.
4. Kiểm tra dữ liệu từ máy app (SSM): đếm bản ghi, kiểm tra bản ghi bị xóa nhầm đã có lại.
5. Đổi endpoint: cập nhật `SPRING_DATASOURCE_URL` (Parameter Store/`.env`) → deploy lại app → smoke test `/actuator/health`.
6. Giữ instance cũ vài ngày để điều tra (hoặc snapshot thủ công), sau đó xóa có kế hoạch; ghi postmortem.

Lưu ý quan trọng: dữ liệu ghi **sau** 14:31 trên instance cũ (giao dịch hợp lệ từ 14:31 đến lúc chuyển) sẽ không có trên instance mới — runbook phải nêu cách xử lý (chấp nhận mất, hoặc trích xuất thủ công từ instance cũ).

**Bài 4 — Script mẫu.**

```bash
#!/bin/bash
# Chỉ IN RA lệnh tạo RDS cho lab, không chạy.
set -euo pipefail
: "${DB_SG:?Đặt DB_SG=<sg-id> trước khi chạy}"
SUBNET_GROUP=${SUBNET_GROUP:-lab03-db-subnets}

if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" > /dev/null 2>&1; then
  echo "Subnet group $SUBNET_GROUP chưa tồn tại" >&2
  exit 1
fi

PG_VERSION=$(aws rds describe-db-engine-versions --engine postgres \
  --query "DBEngineVersions[?starts_with(EngineVersion, '17.')].EngineVersion | [-1]" --output text)
DB_PASS=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 24)

cat <<EOF
aws rds create-db-instance \\
  --db-instance-identifier lab03-pg \\
  --engine postgres --engine-version $PG_VERSION \\
  --db-instance-class db.t4g.micro \\
  --allocated-storage 20 --storage-type gp3 --storage-encrypted \\
  --master-username labadmin --master-user-password '<mật khẩu trong biến DB_PASS>' \\
  --db-subnet-group-name $SUBNET_GROUP \\
  --vpc-security-group-ids $DB_SG \\
  --no-publicly-accessible --no-multi-az \\
  --backup-retention-period 1 \\
  --engine-lifecycle-support open-source-rds-extended-support-disabled
EOF
echo "Mật khẩu (chỉ hiện một lần): $DB_PASS" >&2
```

Điểm chấm: `set -euo pipefail`; `${VAR:?}` để từ chối khi thiếu biến; kiểm tra subnet group bằng lệnh `describe` (exit code); không in mật khẩu vào lệnh sẽ bị copy vào history; có đủ `--engine-lifecycle-support ...-disabled`, `--no-publicly-accessible`, `--storage-encrypted`.

**Bài 5.** Không có đáp án duy nhất. Đạt khi ADR có số đo thật (ví dụ "tạo mất 12 phút, xóa mất 6 phút, buổi lab tốn 0,38 USD theo Billing") và phần "Hệ quả" phản ánh các số đó.
