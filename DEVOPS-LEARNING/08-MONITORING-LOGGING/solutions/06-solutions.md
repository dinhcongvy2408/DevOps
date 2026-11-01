# Lời giải — Bài 06: Incident response, postmortem, backup/restore

> Chỉ mở sau khi đã tự làm. Với câu hỏi mở, đây là **một** đáp án hợp lý — đáp án của bạn khác nhưng lập luận đúng vẫn đạt.

## Bài thực hành (mục 9)

### Bước 1 — Timeline

| Mốc | Giờ (UTC) | Căn cứ |
|---|---|---|
| Thay đổi | 09:58:12 bắt đầu deploy, 10:00:41 deploy xong `7c1d2e4` | GitHub Actions, `deploy.sh` |
| Bắt đầu ảnh hưởng | 10:03:05 (lỗi đầu tiên trong log) | Log `taskhub`, nginx 500 |
| Phát hiện | 10:05:30 alert firing | Alertmanager |
| Giảm thiểu xong | 10:26:50 (deploy `v0.6.1` OK) — xác nhận 10:28:30 alert resolved | `deploy.sh`, Alertmanager |

1. MTTD ≈ **2 phút 25 giây** (10:03:05 → 10:05:30). Thời gian ảnh hưởng ≈ **23–25 phút** (10:03 → 10:26/10:28). Một số người tính từ lúc deploy xong (10:00:41) — chấp nhận được nếu ghi rõ cách tính. Rule có `for: 5m` nên alert không thể sớm hơn khoảng 5 phút kể từ khi tỷ lệ lỗi vượt ngưỡng liên tục — nếu bạn thấy MTTD < 5 phút ở đây thì nghĩa là lỗi đã bắt đầu tích lũy trước 10:03:05 (log chỉ cho thấy dòng lỗi đầu tiên được **ghi lại**). Ghi chú điểm này cho thấy bạn đọc số liệu có phê phán.
2. Giảm thiểu = **rollback** về `v0.6.1`. Có thể làm ngay sau khi ack alert (10:09) vì lỗi xuất hiện **3 phút sau deploy** — nhanh hơn ≈ **12–15 phút** (on-call mất 10:09 → 10:21 để tìm nguyên nhân rồi mới rollback).
3. Nguyên nhân trực tiếp khả dĩ: code mới dùng cột `priority` nhưng migration thêm cột chưa chạy (hoặc chưa có) trong môi trường này. Yếu tố góp phần (ví dụ): (a) CI chạy test với database không giống production về trạng thái migration / test không bao phủ đường ghi; (b) không có smoke test **sau deploy** gọi `POST /api/tasks` — deploy báo OK chỉ vì health `UP`; (c) runbook không có quy tắc "lỗi trùng thời điểm deploy → rollback trước".
4. **SEV-2** hoặc **SEV-3**: 31% request lỗi, chức năng tạo task hỏng → ảnh hưởng nặng tới nhiều người dùng → SEV-2 hợp lý; nếu chỉ một endpoint ít dùng thì SEV-3. Lập luận quan trọng hơn con số.

### Bước 2 — Phân loại

| # | SEV | Giảm thiểu đầu tiên |
|---|---|---|
| 1 | SEV-4 | Xem gì đang tăng (`du`, `docker system df`), dọn log/image cũ; lên lịch tăng dung lượng. Không cần gọi người lúc 23:00 |
| 2 | SEV-2 (SEV-1 nếu là sản phẩm thật nhiều người dùng) | Kiểm tra thay đổi gần nhất → rollback; kiểm tra container app/nginx |
| 3 | SEV-1 (lộ thông tin bí mật) | **Xoay vòng** mật khẩu ngay (đổi trong Parameter Store + database), coi như đã lộ; sau đó mới dọn lịch sử Git. Xóa commit **không** đủ |
| 4 | SEV-3 (dữ liệu có rủi ro, chưa mất) | Chạy backup tay ngay, rồi tìm vì sao timer không chạy |
| 5 | SEV-3 | Kiểm tra thay đổi gần nhất, tải database, truy vấn chậm; rollback nếu trùng deploy |
| 6 | SEV-5 | Mở ticket |

### Bước 3 — Runbook (mẫu rút gọn)

```markdown
# Runbook: TaskhubDown — app không trả metric cho Prometheus

- Alert: `TaskhubDown` (`up{job="taskhub"} == 0` trong 1 phút) · Mức mặc định: SEV-2
- Cập nhật lần cuối: 2026-11-20

## Triệu chứng
Prometheus không scrape được `taskhub:8080/actuator/prometheus`. Thường đi kèm nginx trả 502.

## Kiểm tra nhanh (≤ 5 phút)
1. `cd /opt/taskhub && docker compose ps` → mong đợi: `taskhub` Up (healthy). Thấy `Restarting` / `Exited`?
2. `docker compose logs taskhub --tail 50` → tìm `APPLICATION FAILED TO START`, dòng `Caused by:` cuối cùng.
3. `curl -fsS localhost/actuator/health` (EC2: cổng 80; laptop: NGINX_HOST_PORT) → mong đợi `{"status":"UP"...}`.
4. `docker compose ps postgres` → healthy? `docker compose logs postgres --tail 30`.
5. Lịch sử deploy: GitHub → Actions → Deploy, lần chạy gần nhất lúc nào, tag nào?

## Giảm thiểu
- App restart liên tục ngay sau deploy (≤ 30 phút) → rollback: chạy workflow Deploy với image_tag trước đó (docs/runbooks/rollback.md).
- App bị OOMKilled (`docker inspect -f '{{.State.OOMKilled}}'` = true) → `docker compose up -d taskhub`; mở ticket xem mem_limit/heap.
- Database không healthy → `docker compose start postgres`; nếu không lên được → docs/runbooks/restore.md.

## Leo thang
- 15 phút chưa rõ nguyên nhân và không có deploy gần đây → ưu tiên khởi động lại toàn stack; 30 phút → coi là SEV-1, ghi nhận và viết postmortem.

## Sau sự cố
Viết postmortem nếu người dùng bị ảnh hưởng > 5 phút, có rollback, hoặc mất dữ liệu.
```

Annotation trong rule:

```yaml
annotations:
  summary: "taskhub không trả metric"
  runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/taskhub-down.md"
```

## Câu hỏi kiểm tra (mục 13)

1. Phát hiện → phân loại → giảm thiểu → khắc phục → postmortem. Giảm thiểu = người dùng hết bị ảnh hưởng (có thể chỉ là tạm thời: rollback, restart). Khắc phục = sửa nguyên nhân để không quay lại.
2. Chọn thấp rồi leo thang muộn: không đủ người, không ai báo người dùng, mất thời gian. Chọn cao rồi hạ xuống: chỉ tốn chút công sức.
3. Người đang sửa bị cuốn vào chi tiết, mất cái nhìn toàn cảnh: thời gian đã trôi bao lâu, có nên đổi hướng (rollback) không, ai cần được báo.
4. Roll forward khi rollback không khả thi (migration không đảo ngược được, bản cũ có lỗ hổng nghiêm trọng) hoặc bản sửa cực nhỏ và chắc chắn. Rủi ro: code viết vội, test ít, dưới áp lực → dễ tạo lỗi mới chồng lên lỗi cũ.
5. Triệu chứng, kiểm tra nhanh có lệnh + kết quả mong đợi, nhánh giảm thiểu theo điều kiện, điều kiện leo thang có thời gian, việc sau sự cố. Link từ alert → người nhận alert lúc 3 giờ sáng có ngay hướng dẫn, không phải đi tìm.
6. Không chặn (đọc/ghi vẫn chạy). Bản dump nhất quán tại một thời điểm (tài liệu PostgreSQL).
7. Không. `pg_dumpall --globals-only` cho role và tablespace.
8. `-Fc` đã nén mặc định; gzip lại tốn CPU mà gần như không nhỏ thêm.
9. `docker compose exec` mặc định cấp TTY; TTY có thể biến đổi luồng byte (xuống dòng) → file nhị phân hỏng âm thầm. `-T` tắt TTY.
10. RPO: lượng dữ liệu tối đa chấp nhận mất (đo bằng thời gian). RTO: thời gian tối đa để khôi phục dịch vụ. Backup mỗi 24 giờ → RPO tệ nhất gần 24 giờ (sự cố xảy ra ngay trước lần backup kế tiếp) — thực tế còn cộng thêm độ trễ ngẫu nhiên và thời gian chạy.
11. 3 bản, 2 loại phương tiện/hệ thống, 1 bản offsite. `taskhub` v5: dữ liệu sống trên EBS + dump trên S3 = 2 bản, khác hệ thống, S3 nằm ngoài máy EC2; **chưa** có bản thứ 3, và cùng tài khoản/region.
12. (a) `pg_dump` lỗi (sai phiên bản, sai mật khẩu) nhưng script không dừng → upload file rỗng: `set -euo pipefail`, dump ra file rồi `pg_restore --list`. (b) Lịch không chạy (PATH, timer chưa enable, máy tắt): metric `last_success` + alert `TaskhubBackupStale`, `Persistent=true`. (c) Upload sai chỗ/sai quyền: kiểm tra object tồn tại, alert dựa trên metric chỉ ghi khi upload thành công. (d) File dump hợp lệ nhưng thiếu dữ liệu/không restore được: diễn tập restore định kỳ, so số dòng.
13. Timer có trễ ngẫu nhiên (đến 10 phút) và thời gian chạy; ngưỡng đúng 24 giờ sẽ báo động giả mỗi khi lần sau chạy muộn hơn lần trước vài phút. 2 giờ dư là đệm.
14. Không. Vẫn có người chịu trách nhiệm cho từng **hành động**. "Không đổ lỗi" là phân tích hệ thống/quy trình thay vì quy lỗi cá nhân — để mọi người dám kể hết sự thật.
15. Ví dụ: "Thêm bước smoke test `POST /api/tasks` sau deploy vào workflow Deploy (owner: phuong-dev, hạn 2026-12-05, PR #…)" và "Thêm quy tắc rollback-trước-debug vào runbook (owner: phuong-dev, hạn 2026-11-25)".

## Bài tập tự làm (mục 14)

**Bài 1.** Timeline rút gọn (theo bài postmortem của GitLab): sự cố replication → kỹ sư xóa nhầm dữ liệu trên primary → phát hiện → tìm backup: `pg_dump` hỏng vì phiên bản 9.2 so với 9.6, email báo lỗi bị từ chối (DMARC), S3 trống, snapshot đĩa không bật cho database → dùng LVM snapshot chụp tay ~6 giờ trước → khôi phục, mất ~18 giờ chủ yếu do chép dữ liệu từ đĩa chậm. Bài học cho `taskhub`: chạy `pg_dump` trong container cùng phiên bản; giám sát backup bằng metric chứ không bằng email; diễn tập restore và đo thời gian (tốc độ chép/tải cũng là một phần RTO).

**Bài 2.** Runbook rollback cần: cách tìm tag tốt gần nhất (GitHub Releases, lịch sử workflow Deploy thành công, `docker inspect` trên EC2 trước khi deploy), lệnh `workflow_dispatch` (UI hoặc `gh workflow run Deploy -f image_tag=v0.6.1`), phương án dự phòng (Session Manager → `sudo /opt/taskhub/scripts/deploy.sh v0.6.1`), kiểm chứng (health, smoke test, alert resolved), và cảnh báo migration không tương thích ngược (CI/CD 05 §4.8).

**Bài 3.** Khung đáp án (con số giá là của bạn, có ngày tra):

| | RPO | RTO ước tính | Chi phí | Độ phức tạp |
|---|---|---|---|---|
| (a) pg_dump 24h → S3 | ≤ 24h | Phút (đã đo ở Lab 02) | ≈ 0 | Thấp, tự viết script + giám sát |
| (b) pg_dump 1h → S3 | ≤ 1h | Như (a) | ≈ 0 (nhiều object hơn, cần lifecycle) | Như (a); dump lớn thì tải database |
| (c) RDS + automated backup 7 ngày | Phút (PITR) | Hàng chục phút (tạo instance mới + đổi endpoint) | Instance RDS theo giờ (AWS 07) | Thấp về backup, nhưng thêm dịch vụ |

Kết luận hợp lý: (a) phù hợp `taskhub` (dữ liệu học tập, chi phí ≈ 0); chuyển (c) khi dữ liệu có giá trị thật, cần RPO phút, hoặc cần Multi-AZ.

**Bài 4.** Tiêu chí ví dụ: SEV-1 = mất/lộ dữ liệu hoặc toàn bộ API lỗi > 15 phút; SEV-2 = > 20% request lỗi hoặc chức năng chính hỏng > 5 phút; SEV-3 = lỗi < 20% hoặc p95 > 1s kéo dài; SEV-4 = không ảnh hưởng người dùng (cảnh báo sớm). Mỗi mức ghi ai được báo (với dự án cá nhân: chính bạn + kênh Telegram) và thời gian phản hồi kỳ vọng.

**Bài 5.** Đạt khi postmortem có timeline có giờ (kể cả ước lượng, ghi rõ là ước lượng), yếu tố góp phần ở mức hệ thống (thiếu tài liệu, thiếu kiểm tra tự động, môi trường khác nhau), và hành động kiểm chứng được.
