# 06. Incident response, postmortem, backup/restore và rollback

> ⏱️ ~3,5 giờ · Mức độ: 🟥 Bắt buộc (PITR và RDS ở mức khái niệm 🟨) · Kiến thức cần có trước: [03. Grafana — dashboard & alert](03-grafana-dashboards-alerting.md), [04. Log tập trung](04-centralized-logging.md), [CI/CD 05 — Chiến lược triển khai & rollback](../05-CICD/05-deployment-strategies-rollback.md), [AWS 05 — S3](../06-AWS/05-s3.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (stack `taskhub` + `taskhub-mon` chạy trên laptop). Phần trên EC2 nằm ở [Lab 02 — Backup & restore](labs/lab-02-backup-restore.md).
> Phiên bản khi viết (kiểm tra 2026-10-31): PostgreSQL 17 (`postgres:17`), tài liệu PostgreSQL 17.

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ luồng hoạt động](#6-sơ-đồ-luồng-hoạt-động)
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

- Mô tả vòng đời một sự cố: **phát hiện → phân loại → giảm thiểu → khắc phục → postmortem**, và vai trò của từng người trong lúc xử lý.
- Phân loại mức độ nghiêm trọng (severity) và biết khi nào phải báo động "cả đội".
- Áp dụng nguyên tắc **"giảm thiểu trước, tìm nguyên nhân sau"**, chọn giữa rollback và roll forward.
- Viết một **runbook** ngắn mà người khác đọc lúc 3 giờ sáng vẫn làm theo được.
- Phân biệt backup **logic** (`pg_dump`) và **vật lý/PITR**; giải thích RPO, RTO, quy tắc 3-2-1.
- Giải thích vì sao **"backup chưa từng restore thử thì chưa phải backup"**, và giám sát chính việc backup.
- Viết một **postmortem không đổ lỗi** (blameless) có timeline, tác động, nguyên nhân, hành động khắc phục có người chịu trách nhiệm.

## 2. Tại sao DevOps Engineer cần kiến thức này?

Dashboard và alert (bài 02–04) chỉ cho bạn biết **có chuyện**. Bài này dạy **làm gì tiếp theo** — thứ phân biệt người "biết công cụ" với người được giao trực (on-call).

| Tình huống khi đi làm | Kiến thức cần |
|---|---|
| 2 giờ sáng, Telegram báo `TaskhubDown` | Quy trình: xác nhận → đánh giá ảnh hưởng → giảm thiểu → ghi lại |
| Deploy xong 10 phút thì lỗi 5xx tăng vọt | Rollback ngay bằng tag cũ (CI/CD 05), tìm nguyên nhân sau |
| Ai đó lỡ `DELETE` không có `WHERE` | Restore từ backup — và bạn phải biết **mất bao nhiêu dữ liệu** (RPO), **mất bao lâu** (RTO) |
| Sếp hỏi "chuyện gì đã xảy ra, có lặp lại không?" | Postmortem: timeline, nguyên nhân gốc, hành động phòng ngừa |
| Phỏng vấn: "Kể về một sự cố bạn đã xử lý" | Postmortem của incident drill trong module này chính là câu trả lời |

Câu hỏi phỏng vấn kinh điển cho Junior: *"Database production bị xóa nhầm, bạn làm gì?"* Câu trả lời tốt không bắt đầu bằng lệnh, mà bằng: dừng ghi thêm, đánh giá phạm vi, chọn bản backup, restore vào **database mới** để kiểm tra, rồi mới chuyển đổi — và nêu được RPO/RTO thực tế đã đo khi diễn tập.

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Sự cố (incident) là gì?

**Incident** (sự cố) là một sự kiện ngoài kế hoạch làm **giảm chất lượng dịch vụ** người dùng nhận được, hoặc có nguy cơ làm vậy: trang không vào được, chậm bất thường, mất dữ liệu, lộ dữ liệu. Một alert chưa chắc là incident (có thể là cảnh báo giả); một incident chưa chắc có alert (có thể do người dùng báo — và đó là dấu hiệu giám sát còn thiếu).

### 3.2. Từ vựng

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|---|---|---|
| On-call | Trực | Người nhận alert và chịu trách nhiệm phản hồi đầu tiên trong ca |
| Severity (SEV) | Mức nghiêm trọng | Thang phân loại ảnh hưởng, quyết định ai được gọi và báo cho ai |
| Mitigation | Giảm thiểu | Làm cho người dùng hết bị ảnh hưởng (rollback, chuyển traffic, khởi động lại) — **chưa** cần sửa tận gốc |
| Resolution | Khắc phục | Sửa nguyên nhân để sự cố không quay lại |
| Runbook | Sổ tay vận hành | Các bước cụ thể cho một loại sự cố/công việc lặp lại |
| Postmortem | Bản phân tích sau sự cố | Tài liệu viết sau sự cố: chuyện gì xảy ra, vì sao, làm gì để không lặp lại |
| Blameless | Không đổ lỗi | Tập trung vào hệ thống và quy trình, không quy lỗi cho cá nhân |
| RPO | Mục tiêu điểm khôi phục | Lượng dữ liệu tối đa chấp nhận mất, đo bằng **thời gian** (ví dụ 24 giờ) |
| RTO | Mục tiêu thời gian khôi phục | Thời gian tối đa từ lúc sự cố đến lúc dịch vụ chạy lại |
| MTTD / MTTR | Thời gian phát hiện / khôi phục trung bình | Chỉ số đo hiệu quả phát hiện và xử lý sự cố |

### 3.3. Ba câu hỏi đầu tiên khi nhận alert

1. **Có thật không?** Mở dashboard, gọi thử endpoint. Alert giả cũng cần ghi lại (để sửa alert).
2. **Ảnh hưởng ai, bao nhiêu?** Toàn bộ người dùng hay một chức năng? Có mất dữ liệu không?
3. **Gần đây có gì thay đổi?** Deploy, đổi cấu hình, đổi hạ tầng. Phần lớn sự cố đến sau một thay đổi — đó là lý do ta cần lịch sử deploy (GitHub Actions run, Git tag) và nhật ký thay đổi.

## 4. Giải thích chi tiết

### 4.1. 🟥 Vòng đời một sự cố

```text
  Phát hiện ──► Phân loại ──► Giảm thiểu ──► Khắc phục ──► Postmortem ──► Hành động phòng ngừa
  (alert,       (SEV, ai      (rollback,     (sửa code,    (timeline,     (ticket có người
  người dùng)   tham gia)     restart…)      cấu hình)     nguyên nhân)    chịu trách nhiệm)
       ▲                                                                         │
       └───────────────── alert/runbook tốt hơn, test mới ◄──────────────────────┘
```

- **Phát hiện**: lý tưởng là alert (bài 03), không phải người dùng gọi điện. Ghi lại **thời điểm** phát hiện — cần cho timeline và MTTD.
- **Phân loại**: chọn mức SEV (mục 4.2), quyết định có cần gọi thêm người không, mở "kênh sự cố" (một nhóm chat riêng) để mọi trao đổi nằm một chỗ.
- **Giảm thiểu**: mục tiêu duy nhất là **người dùng hết bị ảnh hưởng** (mục 4.4).
- **Khắc phục**: sau khi đã ổn định, tìm và sửa nguyên nhân gốc, có test, qua PR như mọi thay đổi khác.
- **Postmortem**: viết trong vài ngày, khi trí nhớ còn mới (mục 4.10).

### 4.2. 🟥 Mức độ nghiêm trọng (severity)

Mỗi công ty tự định nghĩa thang của mình. Bảng dưới tóm tắt thang 5 mức của tài liệu Incident Response công khai của PagerDuty (SEV-1 nặng nhất); theo tài liệu đó, SEV-1 và SEV-2 được coi là "major incident".

| Mức | Mô tả (tóm tắt) | Ví dụ với `taskhub` |
|---|---|---|
| SEV-1 | Nghiêm trọng, ảnh hưởng rất nhiều khách hàng, lộ dữ liệu, cần thông báo công khai | Database bị xóa, không có backup dùng được; lộ mật khẩu người dùng |
| SEV-2 | Hệ thống quan trọng gián đoạn nặng với nhiều người dùng | `taskhub` trả 502 cho mọi request |
| SEV-3 | Ảnh hưởng nhỏ hoặc vấn đề ổn định cần xử lý ngay, có thể leo thang | Lỗi 5xx 3% ở một endpoint; p95 latency tăng gấp 3 |
| SEV-4 | Vấn đề nhỏ, không chặn người dùng | Ổ đĩa 82% (cảnh báo sớm); backup đêm qua chậm 1 giờ |
| SEV-5 | Lỗi giao diện/không ảnh hưởng sử dụng | Sai chính tả trong thông báo lỗi |

Quy tắc thực tế: **không chắc thì chọn mức cao hơn**, hạ xuống sau. Chọn thấp rồi leo thang muộn tốn kém hơn nhiều.

### 4.3. 🟥 Vai trò khi xử lý sự cố

Theo tài liệu của PagerDuty, các vai trò thường gặp gồm Incident Commander, Deputy, Scribe, Subject Matter Expert, Customer Liaison, Internal Liaison. Với một team nhỏ (hoặc chỉ một mình bạn), một người kiêm nhiều vai, nhưng **các việc vẫn phải có người làm**:

| Vai trò | Việc chính | Khi bạn làm một mình |
|---|---|---|
| Incident Commander (IC) | Điều phối, quyết định, không tự tay sửa | Tự hỏi mỗi 15 phút: "mục tiêu hiện tại là gì? cần gọi ai?" |
| Scribe (người ghi chép) | Ghi timeline: giờ, ai làm gì, thấy gì | Ghi vào file `incident-notes.md` **ngay lúc làm**, kèm giờ UTC |
| Subject Matter Expert | Người hiểu sâu thành phần đang lỗi (DB, mạng…) | Chính bạn + tài liệu + runbook |
| Liaison (giao tiếp) | Cập nhật cho người dùng/sếp định kỳ | Một dòng trạng thái mỗi 30 phút, kể cả khi "chưa có gì mới" |

Vì sao IC **không** tự sửa? Người đang gõ lệnh bị cuốn vào chi tiết, quên nhìn toàn cảnh (đã 40 phút rồi, có nên rollback thay vì tiếp tục debug không?).

### 4.4. 🟥 Giảm thiểu trước, tìm nguyên nhân sau

Khi người dùng đang bị ảnh hưởng, câu hỏi đúng **không phải** "vì sao lỗi?" mà là "**cách nhanh nhất, an toàn nhất để người dùng hết bị ảnh hưởng là gì?**".

| Tình huống | Giảm thiểu | Khắc phục (sau đó) |
|---|---|---|
| Lỗi xuất hiện ngay sau deploy | **Rollback** về tag trước ([CI/CD 05 §4.9](../05-CICD/05-deployment-strategies-rollback.md#49--rollback-bằng-tag-bất-biến-và-khi-nào-roll-forward)) | Tìm bug, thêm test, deploy bản sửa |
| Container PostgreSQL bị dừng | Khởi động lại container | Vì sao nó dừng? OOM? Ai dừng? Thêm alert |
| Ổ đĩa sắp đầy | Xóa log/image cũ, tăng dung lượng | Đặt retention, alert sớm hơn |
| Dữ liệu bị xóa nhầm | Dừng ghi, restore vào DB mới, chuyển đổi | Phân quyền, review quy trình chạy SQL tay |

**Rollback vs roll forward** (đã học ở CI/CD 05):

- **Rollback** khi: lỗi rõ ràng do bản mới, bản cũ đã chạy tốt, schema database **tương thích ngược** (expand/contract).
- **Roll forward** (sửa nhanh và deploy bản mới) khi: rollback không được vì migration không đảo ngược được, hoặc bản sửa cực nhỏ và chắc chắn. Roll forward dưới áp lực thường **tạo thêm** lỗi — chỉ làm khi rollback thật sự không khả thi.

Bẫy kinh điển: debug 2 giờ để tìm nguyên nhân trong khi rollback chỉ mất 3 phút. Đặt giới hạn thời gian: "sau 15 phút chưa rõ nguyên nhân mà lỗi trùng thời điểm deploy → rollback".

### 4.5. 🟥 Runbook

**Runbook** là các bước cụ thể cho một loại tình huống, viết **trước** khi sự cố xảy ra. Runbook tốt:

- Bắt đầu bằng **triệu chứng** (alert nào, trông thế nào) và **mức ảnh hưởng**.
- Có lệnh **chép-dán được**, có kết quả mong đợi của từng lệnh.
- Có điều kiện **dừng/leo thang**: "nếu bước 3 không được trong 10 phút → rollback / gọi X".
- Được **link từ chính alert** (annotation `runbook_url` trong rule Prometheus — bài 03).
- Được cập nhật sau mỗi postmortem.

Khung runbook cho `taskhub` (lưu ở `docs/runbooks/<tên>.md` trong repo):

```markdown
# Runbook: <tên alert hoặc tình huống>

- Alert liên quan: `TaskhubDown` · Mức mặc định: SEV-2
- Người viết / cập nhật lần cuối: … / YYYY-MM-DD

## Triệu chứng
- …

## Kiểm tra nhanh (≤ 5 phút)
1. `<lệnh>` → mong đợi: `<kết quả>`
2. …

## Giảm thiểu
- Nếu <điều kiện A>: `<lệnh>`
- Nếu <điều kiện B>: rollback theo docs/runbooks/rollback.md

## Leo thang
- Sau 15 phút chưa ổn định: …

## Sau sự cố
- Viết postmortem nếu: người dùng bị ảnh hưởng > 5 phút, mất dữ liệu, phải rollback.
```

### 4.6. 🟥 Backup PostgreSQL — logic và vật lý

| | Backup logic (`pg_dump`) | Backup vật lý + WAL (PITR) |
|---|---|---|
| Lưu cái gì | Câu lệnh/dữ liệu để **tái tạo** database (schema + dữ liệu) | Bản sao file dữ liệu của **cả cluster** + các file WAL |
| Đơn vị | **Một** database (hoặc vài bảng) | **Toàn bộ** cluster, không chọn được một database |
| Khôi phục về | Thời điểm chạy dump | **Bất kỳ thời điểm nào** trong khoảng có WAL |
| Dùng khi | Database nhỏ/vừa, chuyển phiên bản, khôi phục một bảng | Database lớn, cần RPO tính bằng phút |
| `taskhub` dùng | ✅ (v5) | Khái niệm; RDS làm thay bạn (mục 4.7) |

Những điều tài liệu PostgreSQL 17 nói rõ về `pg_dump` (trích ý):

- Tạo bản backup **nhất quán** ngay cả khi database đang được dùng, và **không chặn** người đọc/ghi khác.
- Chỉ dump **một** database. Đối tượng **toàn cục** (role, tablespace) không nằm trong đó — muốn có phải dùng `pg_dumpall --globals-only`.
- Định dạng **custom** (`-Fc`): dùng với `pg_restore`, cho phép chọn và sắp xếp lại đối tượng khi restore, và **được nén mặc định** → đừng gzip thêm lần nữa.

Với `taskhub`, user `taskhub` được tạo bởi biến `POSTGRES_USER` của image `postgres` mỗi khi khởi tạo cluster mới, nên ta không cần backup role riêng. Ở hệ thống có nhiều user/quyền tạo tay, thiếu `pg_dumpall --globals-only` là lý do phổ biến khiến restore "chạy được nhưng app không đăng nhập được".

Tài liệu PostgreSQL về continuous archiving mô tả PITR: một **base backup** ở mức file + các file **WAL** được lưu liên tục; khi khôi phục, PostgreSQL "phát lại" WAL tới thời điểm bạn chọn. Giới hạn ghi rõ trong tài liệu: chỉ khôi phục được **toàn bộ cluster**, không chọn một database.

### 4.7. 🟨 RDS làm gì thay bạn

RDS (đã học ở [AWS 07](../06-AWS/07-rds.md)) chụp snapshot volume của **cả instance** trong backup window và giữ log giao dịch để **PITR** trong khoảng retention bạn chọn; khôi phục luôn tạo **instance mới**. Bạn không phải viết script backup — nhưng vẫn phải:

- Chọn retention đúng (RPO).
- **Diễn tập restore** (vẫn có thể có lỗi cấu hình: security group, parameter group, app trỏ endpoint mới).
- Hiểu chi phí snapshot thủ công (không tự xóa khi xóa instance).

ADR-0011 của dự án sẽ ghi lại vì sao `taskhub` chọn `pg_dump` → S3 thay vì RDS (chi phí, quy mô nhỏ, mục đích học).

### 4.8. 🟥 RPO, RTO và quy tắc 3-2-1

```text
  backup gần nhất          sự cố                     dịch vụ chạy lại
        │◄──── RPO thực tế ────►│◄──────── RTO thực tế ──────►│
  ──────●───────────────────────✖────────────────────────────●──────► thời gian
        dữ liệu trong đoạn này MẤT     người dùng không dùng được
```

- **RPO** của `taskhub` v5: backup mỗi 24 giờ → tệ nhất mất **gần 24 giờ** dữ liệu. Muốn RPO 1 giờ → backup mỗi giờ (tốn hơn) hoặc PITR.
- **RTO**: không phải con số bạn **mong muốn**, mà là con số bạn **đã đo** khi diễn tập (Lab 02). Gồm: phát hiện + quyết định + tải backup + restore + kiểm tra + chuyển đổi.

**Quy tắc 3-2-1** (quy tắc phổ biến trong ngành): **3** bản sao dữ liệu, trên **2** loại phương tiện/hệ thống khác nhau, **1** bản ở nơi khác (offsite). Áp vào `taskhub`:

| Bản | Ở đâu | Đánh giá |
|---|---|---|
| 1. Dữ liệu sống | Volume `pgdata` trên EBS của EC2 | Bản gốc |
| 2. Dump trên S3 (có versioning) | Dịch vụ khác, lưu trên nhiều AZ | ✅ khác hệ thống, ngoài máy EC2 |
| 3. ? | — | ❌ chưa có: script tham khảo xóa file dump tạm sau khi upload |

`taskhub` v5 mới đạt **2 bản**, và cả hai cùng tài khoản AWS, cùng region. Với một dự án học tập, đây là đánh đổi chấp nhận được — nhưng bạn phải **nêu được** khi trình bày dự án. Cách bổ sung bản thứ 3 (bài tập 3 của [Lab 02](labs/lab-02-backup-restore.md)): giữ vài bản dump gần nhất trên đĩa EC2 (rẻ nhưng chết cùng máy), định kỳ tải một bản về laptop, hoặc 🟦 S3 replication sang region/tài khoản khác.

### 4.9. 🟥 "Backup chưa restore thử thì chưa phải backup" — và giám sát backup

Backup hỏng thường hỏng **âm thầm**: script chạy nhưng file rỗng, phiên bản `pg_dump` không khớp server, quyền S3 sai, cron không chạy vì `PATH`… Bạn chỉ phát hiện vào đúng ngày cần restore (xem [ví dụ GitLab 2017](#ví-dụ-1-gitlab-2017--năm-cơ-chế-backup-không-cơ-chế-nào-cứu-được) ở mục 5).

Ba lớp phòng thủ, đều có trong Lab 02:

1. **Kiểm tra ngay khi backup**: exit code của mọi bước (`set -euo pipefail`), dump ra **file** trước rồi mới upload (pipe thẳng `pg_dump | aws s3 cp -` mà `pg_dump` lỗi giữa chừng thì S3 vẫn nhận một file dở dang trông như backup thật), file dump đọc được (`pg_restore --list` thành công). 🟨 Nâng cao: so kích thước object trên S3 với file local.
2. **Giám sát việc backup**: script ghi metric `taskhub_backup_last_success_timestamp_seconds` qua **textfile collector** của node_exporter (file `*.prom`, ghi ra file tạm rồi `mv` để không bao giờ bị đọc dở — đúng như README của node_exporter khuyến nghị). Alert khi lần thành công gần nhất cũ hơn 26 giờ.
3. **Diễn tập restore định kỳ** (mỗi tháng): restore vào database mới, đếm số dòng, đo thời gian → cập nhật RTO.

Vì sao **26** giờ mà không phải 24? Backup chạy lúc 18:00 nhưng có độ trễ ngẫu nhiên và thời gian chạy; ngưỡng đúng bằng chu kỳ sẽ báo động giả mỗi khi backup chậm vài phút.

### 4.10. 🟥 Postmortem không đổ lỗi

Chương *Postmortem Culture* trong sách *Site Reliability Engineering* của Google viết rằng postmortem không đổ lỗi giả định **mọi người liên quan đều có ý tốt**, và postmortem được kỳ vọng sau mọi sự kiện không mong muốn đáng kể. Các tiêu chí kích hoạt phổ biến trong chương: người dùng bị ảnh hưởng vượt ngưỡng, **mất dữ liệu bất kỳ**, on-call phải can thiệp (ví dụ rollback), thời gian khắc phục vượt ngưỡng, giám sát không phát hiện (phải phát hiện thủ công).

"Không đổ lỗi" **không** có nghĩa "không ai chịu trách nhiệm". Nó có nghĩa câu hỏi là "**hệ thống nào đã cho phép lỗi này xảy ra và không phát hiện sớm?**" thay vì "ai làm sai?". Nếu người gõ lệnh bị phạt, lần sau mọi người sẽ **giấu** sai sót — và bạn mất thông tin quý nhất.

| Đổ lỗi ❌ | Không đổ lỗi ✅ |
|---|---|
| "Phương deploy bản lỗi" | "Bản v0.6.2 qua CI xanh nhưng test không bao phủ trường hợp `title` rỗng" |
| "Ops quên gia hạn chứng chỉ" | "Không có alert khi chứng chỉ còn < 14 ngày; việc gia hạn làm thủ công" |
| "Cần cẩn thận hơn" (hành động không đo được) | "Thêm test X (owner: A, hạn 15/12); thêm alert Y (owner: B, hạn 10/12)" |

**Mẫu postmortem** (lưu `docs/postmortems/YYYY-MM-DD-<slug>.md`; cấu trúc dựa theo ví dụ postmortem ở phụ lục sách SRE của Google):

```markdown
# Postmortem: <tiêu đề ngắn> — YYYY-MM-DD

- Trạng thái: Nháp | Đã review · Mức: SEV-? · Người viết: … · Người review: …
- Thời gian ảnh hưởng: HH:MM–HH:MM UTC (… phút)

## Tóm tắt
2–3 câu: chuyện gì xảy ra, ảnh hưởng gì, đã xử lý thế nào.

## Tác động
- Người dùng: … (bao nhiêu request lỗi / bao lâu)
- Dữ liệu: mất / không mất (RPO thực tế: …)

## Timeline (UTC)
| Giờ | Sự kiện | Nguồn (alert, log, lệnh) |
|---|---|---|
| 10:02 | Deploy v0.6.2 | GitHub Actions run #… |
| 10:05 | Alert TaskhubHighErrorRate firing | Alertmanager |
| 10:08 | Xác nhận 5xx trên dashboard | Grafana |
| 10:11 | Quyết định rollback | IC |
| 10:14 | Rollback xong, lỗi về 0 | Deploy workflow |

## Nguyên nhân gốc và yếu tố góp phần
- Nguyên nhân trực tiếp (trigger): …
- Yếu tố góp phần: … (vì sao không bị chặn ở CI? vì sao phát hiện sau 3 phút?)

## Phát hiện
Phát hiện bằng gì? Nhanh/chậm? Lẽ ra phải phát hiện bằng gì?

## Điều gì làm tốt / chưa tốt / gặp may
- Tốt: …
- Chưa tốt: …
- Gặp may: …

## Hành động
| Hành động | Loại (phòng ngừa/phát hiện/giảm thiểu) | Người chịu trách nhiệm | Hạn | Ticket |
|---|---|---|---|---|

## Bài học
```

Hai quy tắc cho phần **Hành động**: mỗi dòng có **một người** chịu trách nhiệm và **hạn cụ thể**; mỗi dòng **kiểm chứng được** (có test, có alert, có PR) — "cẩn thận hơn" không phải hành động.

### 4.11. Gặp lại ở đâu

| Kiến thức trong bài | Gặp lại ở |
|---|---|
| Rollback bằng tag | Workflow `Deploy` với `workflow_dispatch` (v3) — diễn tập < 5 phút ở [v5](../12-PRACTICAL-PROJECT/milestones/v5-observability-backup.md) |
| `pg_dump`/`pg_restore`, RPO/RTO | [Lab 02 — Backup & restore](labs/lab-02-backup-restore.md), v5 |
| Postmortem | [Incident drill #1](labs/incident-drill-01/README.md), incident drill #2 tuần 22, phần "câu chuyện sự cố" khi phỏng vấn |
| Runbook, `runbook_url` | Annotation của rule Prometheus (bài 03); `docs/runbooks/` ở v1.0 |
| Backup monitoring | Textfile collector của node_exporter (bài 02) |
| Quyền tối thiểu cho backup | Inline policy `taskhub-ec2-s3-backup` ([AWS 05](../06-AWS/05-s3.md)) — chỉ `pg-dumps/*`, không có quyền xóa |

## 5. Ví dụ thực tế

### Ví dụ 1: GitLab 2017 — năm cơ chế backup, không cơ chế nào cứu được

Bài postmortem công khai của GitLab về sự cố database ngày 31/01/2017 (đăng 10/02/2017) là tài liệu kinh điển. Theo bài viết: một kỹ sư xóa nhầm dữ liệu trên database primary trong lúc xử lý sự cố replication; GitLab.com ngừng khoảng 18 giờ; ước tính mất dữ liệu của khoảng 5.000 project, 5.000 comment và 700 tài khoản. Khi tìm backup:

- Job `pg_dump` dùng phiên bản **9.2** trong khi database chạy **9.6** → lỗi, không tạo được backup; thông báo lỗi gửi qua email nhưng bị máy chủ nhận **từ chối** (không bật DMARC) → không ai biết. Bucket S3 **trống**.
- Snapshot đĩa chỉ bật cho server NFS, không bật cho database.
- Cuối cùng phải dùng một bản LVM snapshot mà một kỹ sư **tình cờ** chụp tay khoảng 6 giờ trước đó.

Bài học áp vào `taskhub`: chạy `pg_dump` **trong chính container PostgreSQL** (luôn cùng phiên bản với server), kiểm tra file dump đọc được, giám sát "lần backup thành công gần nhất" bằng metric (không dựa vào email), và diễn tập restore.

### Ví dụ 2: Rollback nhanh hơn debug

Một team deploy bản mới lúc 16:00, lỗi 5xx tăng lên 20%. On-call mở log và tìm thấy stack trace lạ, mất 50 phút để hiểu. Postmortem ghi: "rollback sẽ mất 4 phút; bản cũ đã chạy ổn 2 tuần; migration tương thích ngược". Hành động: thêm vào runbook quy tắc "lỗi xuất hiện trong 30 phút sau deploy → rollback trước, debug sau".

### Ví dụ 3: Restore được — nhưng sai thứ tự

Một team restore dump **đè thẳng** lên database production đang chạy (`pg_restore --clean`) để "cho nhanh". Restore lỗi giữa chừng vì app vẫn đang ghi → database ở trạng thái nửa cũ nửa mới. Đây là lý do quy trình của bài này luôn restore vào **database mới** (`taskhub_restore`), kiểm tra, rồi mới **chuyển đổi** khi app đã dừng.

## 6. Sơ đồ luồng hoạt động

### 6.1. Từ alert đến postmortem trên stack `taskhub`

```text
 Prometheus ──rule firing──► Alertmanager ──► Telegram / webhook-debug   (bài 03)
                                                   │
                                     on-call nhận alert, mở incident-notes.md (ghi giờ UTC)
                                                   │
                ┌──────────────────────────────────┼───────────────────────────────────┐
                ▼                                  ▼                                   ▼
        Grafana dashboard                  Loki (Explore)                   "Gần đây có gì đổi?"
        taskhub-overview                   {compose_service="taskhub"}      GitHub Actions, git log,
        (rate, 5xx, p95, up)               |= "ERROR"                       docker inspect, .env
                └──────────────────────────────────┼───────────────────────────────────┘
                                                   ▼
                              Giảm thiểu: rollback (Deploy workflow / deploy.sh <tag cũ>)
                                          khởi động lại thành phần · restore DB
                                                   ▼
                              Kiểm chứng: alert resolved, dashboard về bình thường
                                                   ▼
                              Postmortem: docs/postmortems/YYYY-MM-DD-<slug>.md
```

### 6.2. Luồng backup/restore của `taskhub` v5

```text
EC2 (host, không phải container — vì IMDS hop limit 1)
 systemd timer 18:00 UTC ─► scripts/backup.sh
   1. docker exec <postgres> pg_dump -Fc  ─► file tạm trên host (mktemp, tự xóa khi script kết thúc)
   2. pg_restore --list  (kiểm tra file đọc được)
   3. aws s3 cp ─► s3://taskhub-backups-<acct>/pg-dumps/taskhub-<UTC>.dump   (instance role, chỉ Put/Get pg-dumps/*)
   4. CHỈ KHI 1–3 thành công: ghi metric taskhub_backup_last_success_timestamp_seconds ─► textfile collector
                                                                     │
                                         node_exporter ─► Prometheus ─► alert TaskhubBackupStale
 Restore (scripts/restore.sh):
   S3 ─► pg_restore vào DB MỚI taskhub_restore ─► so số dòng ─► (dừng app) đổi tên DB ─► chạy app
```

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích |
|---|---|
| `docker compose exec -T postgres pg_dump -U taskhub -d taskhub -Fc > file.dump` | Backup logic định dạng custom từ container |
| `pg_restore --list file.dump` | Xem mục lục (TOC) của file dump — kiểm tra file đọc được |
| `createdb -U taskhub taskhub_restore` | Tạo database mới để restore vào |
| `pg_restore -U taskhub -d taskhub_restore --no-owner --exit-on-error < file.dump` | Restore vào database mới |
| `pg_dumpall -U taskhub --globals-only` | Dump role/tablespace (đối tượng toàn cục) |
| `psql -U taskhub -d <db> -c "select count(*) from tasks"` | Kiểm tra số dòng sau restore |
| `ALTER DATABASE taskhub RENAME TO taskhub_broken` | Chuyển đổi database (khi không còn kết nối) |
| `date -u +%FT%TZ` | Giờ UTC cho timeline |

## 8. Giải thích câu lệnh và tham số

### `docker compose exec -T postgres pg_dump -U taskhub -d taskhub -Fc > taskhub.dump`

```bash
docker compose -p taskhub exec -T postgres pg_dump -U taskhub -d taskhub -Fc > ~/devops-lab/08-monitoring/backup/taskhub.dump
```

| Phần | Ý nghĩa |
|---|---|
| `-p taskhub` | Project Compose của app (nếu bạn đang đứng trong thư mục repo có `name: taskhub` thì không cần) |
| `exec -T` | Chạy lệnh trong container đang chạy. **`-T` tắt cấp TTY** — bắt buộc khi output là **dữ liệu nhị phân** chuyển hướng ra file. Có TTY, ký tự xuống dòng có thể bị đổi (`\n` → `\r\n`) và file dump **hỏng âm thầm** |
| `pg_dump` trong container | Luôn cùng phiên bản với server → tránh đúng lỗi của GitLab 2017 |
| `-U taskhub -d taskhub` | User và database. Trong container, kết nối qua Unix socket nội bộ, không cần mật khẩu (cấu hình mặc định của image cho kết nối local — 🟨 xem `pg_hba.conf` nếu muốn biết chi tiết) |
| `-Fc` | Định dạng custom: nén sẵn, dùng với `pg_restore`, cho phép restore chọn lọc |
| `> file` | Chuyển hướng stdout **trên máy bạn** (WSL), không phải trong container |

Kết quả mẫu (minh họa):

```text
$ ls -lh ~/devops-lab/08-monitoring/backup/
-rw-r--r-- 1 phuong phuong 9.8K Nov 20 09:12 taskhub.dump
$ file ~/devops-lab/08-monitoring/backup/taskhub.dump
taskhub.dump: PostgreSQL custom database dump - v1.16-0
```

### `pg_restore --list`

```bash
docker compose -p taskhub exec -T postgres pg_restore --list < taskhub.dump | head
```

In ra mục lục (table of contents): danh sách bảng, index, sequence, dữ liệu. Thành công = file đọc được và đúng định dạng. Đây là bước kiểm tra rẻ nhất bạn nên chạy **sau mỗi lần backup**. Lưu ý `-T` cũng cần ở đây (đầu vào nhị phân qua stdin), và theo tài liệu `pg_restore`, không có tên file thì nó đọc **stdin**.

Đầu ra mẫu (minh họa, đã rút gọn):

```text
;
; Archive created at 2026-11-20 09:12:01 UTC
;     dbname: taskhub
;     TOC Entries: 14
;     Compression: gzip
;     Format: CUSTOM
...
218; 1259 16390 TABLE public tasks taskhub
3349; 0 16390 TABLE DATA public tasks taskhub
```

### `pg_restore -d taskhub_restore --no-owner --exit-on-error`

| Tham số | Ý nghĩa (theo tài liệu `pg_restore`) |
|---|---|
| `-d taskhub_restore` | Kết nối và restore **thẳng vào** database này (phải tồn tại — tạo bằng `createdb`) |
| `--no-owner` (`-O`) | Không chạy lệnh đặt chủ sở hữu theo database gốc; user đang kết nối sẽ sở hữu mọi đối tượng. Hữu ích khi restore sang nơi có user khác tên |
| `--exit-on-error` (`-e`) | Dừng ngay khi gặp lỗi SQL. Mặc định `pg_restore` **chạy tiếp** và chỉ báo số lỗi ở cuối — dễ bỏ sót |
| `--single-transaction` (`-1`) 🟨 | Gói cả restore trong một transaction: hoặc tất cả, hoặc không gì. Ngụ ý `--exit-on-error`. Không dùng được cùng `-j` |
| `--clean` / `--create` ⚠️ | Xóa đối tượng/database trước khi tạo lại. **Không dùng** trên database đang phục vụ người dùng |
| `-j N` 🟦 | Restore song song — chỉ với file thật (không phải stdin) |

### `ALTER DATABASE ... RENAME TO ...`

Chuyển đổi sau khi đã kiểm tra bản restore:

```sql
-- Chạy khi app đã dừng: PostgreSQL không cho đổi tên database đang có kết nối
ALTER DATABASE taskhub         RENAME TO taskhub_broken;
ALTER DATABASE taskhub_restore RENAME TO taskhub;
```

Phải kết nối vào **database khác** (ví dụ `postgres`) để chạy lệnh này. Giữ `taskhub_broken` vài ngày (để điều tra), rồi mới xóa.

## 9. Bài thực hành từng bước

Bài thực hành này **trên giấy và tài liệu** — phần chạy lệnh nằm ở [Lab 02](labs/lab-02-backup-restore.md) (backup/restore) và [Incident drill #1](labs/incident-drill-01/README.md) (xử lý sự cố). Làm bài này **trước** hai lab đó.

### Bước 1 — Tái dựng timeline từ log (≈ 30 phút)

Đọc đoạn log tổng hợp dưới đây (**minh họa**, từ nhiều nguồn, đã sắp theo thời gian UTC) và trả lời các câu hỏi bên dưới vào `~/devops-lab/08-monitoring/06/timeline.md`.

```text
2026-11-20T09:58:12Z github-actions  Deploy run #57 started (image_tag=7c1d2e4) by phuong-dev
2026-11-20T10:00:41Z deploy.sh       >> OK: taskhub:7c1d2e4
2026-11-20T10:03:05Z taskhub         {"level":"ERROR","logger_name":"o.h.engine.jdbc.spi.SqlExceptionHelper","message":"ERROR: column \"priority\" does not exist"}
2026-11-20T10:03:06Z nginx           "POST /api/tasks HTTP/1.1" 500
2026-11-20T10:05:30Z alertmanager    [FIRING:1] TaskhubHighErrorRate taskhub (5xx ratio 0.31)
2026-11-20T10:09:02Z phuong          ack alert in Telegram, opened Grafana
2026-11-20T10:21:40Z phuong          "found it: migration V3 not applied?"
2026-11-20T10:24:15Z github-actions  Deploy run #58 started (image_tag=v0.6.1) by phuong-dev
2026-11-20T10:26:50Z deploy.sh       >> OK: taskhub:v0.6.1
2026-11-20T10:28:30Z alertmanager    [RESOLVED] TaskhubHighErrorRate taskhub
```

Câu hỏi:

1. Thời điểm bắt đầu ảnh hưởng, thời điểm phát hiện (alert), thời điểm giảm thiểu xong. Tính MTTD (bắt đầu → alert) và thời gian ảnh hưởng.
2. Hành động giảm thiểu là gì? Có thể làm sớm hơn không, nếu có thì sớm hơn bao nhiêu phút?
3. Nguyên nhân trực tiếp có thể là gì (dựa vào log)? Liệt kê **2 yếu tố góp phần** ở mức hệ thống (không phải "ai đó sai").
4. Gán mức SEV và giải thích.

### Bước 2 — Phân loại 6 tình huống (≈ 15 phút)

Gán SEV (theo bảng mục 4.2) và hành động giảm thiểu đầu tiên cho mỗi tình huống, ghi vào cùng file:

1. Alert `HostDiskUsageHigh` (83%) lúc 23:00, mọi chức năng bình thường.
2. Trang chủ trả 502 cho mọi người dùng.
3. Phát hiện file `.env` có mật khẩu database đã bị commit lên repo public 2 giờ trước.
4. Alert `TaskhubBackupStale`: backup gần nhất 30 giờ trước, app chạy bình thường.
5. p95 latency của `GET /api/tasks` tăng từ 80 ms lên 600 ms, không có lỗi.
6. Nút "Xóa" trên giao diện hiển thị sai màu.

### Bước 3 — Viết runbook đầu tiên (≈ 45 phút)

Theo khung ở mục 4.5, viết `docs/runbooks/taskhub-down.md` trong repo `taskhub` cho alert `TaskhubDown`. Yêu cầu:

- Ít nhất 4 bước kiểm tra nhanh, mỗi bước có lệnh và kết quả mong đợi (`docker compose ps`, `docker compose logs taskhub --tail 50`, `curl` health qua nginx, trạng thái container `postgres`…).
- Nhánh giảm thiểu cho ít nhất 3 nguyên nhân: container app chết/khởi động lại liên tục, database không phản hồi, lỗi ngay sau deploy (→ rollback).
- Điều kiện leo thang có mốc thời gian.
- Thêm `runbook_url` trỏ tới file này vào rule `TaskhubDown` của bạn (bài 03) — dùng URL GitHub của file.

### Bước 4 — Chuẩn bị postmortem template trong repo

Tạo `docs/postmortems/TEMPLATE.md` từ mẫu ở mục 4.10. Incident drill #1 sẽ dùng nó.

## 10. Kết quả mong đợi

- `timeline.md`: có 3 mốc thời gian, MTTD ≈ 2–3 phút (tùy bạn chọn mốc bắt đầu ảnh hưởng là lỗi đầu tiên hay lúc deploy xong), thời gian ảnh hưởng ≈ 25 phút; nhận ra **rollback** lẽ ra làm được ngay khi thấy lỗi trùng thời điểm deploy (tiết kiệm ≈ 12–15 phút).
- Bảng phân loại 6 tình huống có lý do cho từng mức.
- `docs/runbooks/taskhub-down.md` người khác đọc làm theo được; rule `TaskhubDown` có `runbook_url`.
- `docs/postmortems/TEMPLATE.md` có đủ các mục.

So sánh với [lời giải](solutions/06-solutions.md) sau khi tự làm.

## 11. Các lỗi thường gặp

| Lỗi | Hậu quả | Cách tránh |
|---|---|---|
| Debug nguyên nhân trong khi người dùng vẫn đang lỗi | Kéo dài thời gian ảnh hưởng | Đặt giới hạn 15 phút → rollback |
| Không ghi giờ khi làm | Postmortem dựa vào trí nhớ, sai lệch | Ghi `incident-notes.md` ngay lúc làm, giờ UTC |
| Lẫn giờ địa phương và UTC | Timeline lệch 7 giờ giữa log server (UTC) và ghi chú (giờ Việt Nam) | Mọi thứ trong incident dùng UTC |
| `docker compose exec` không có `-T` khi dump/restore | File dump hỏng âm thầm hoặc restore treo | Luôn dùng `-T` với dữ liệu nhị phân |
| Gzip lại file `-Fc` | Tốn CPU, không nhỏ hơn bao nhiêu | `-Fc` đã nén sẵn |
| Restore đè lên database đang chạy | Database nửa cũ nửa mới | Restore vào DB mới, kiểm tra, rồi đổi tên |
| Postmortem toàn hành động "cẩn thận hơn" | Sự cố lặp lại | Mỗi hành động có owner, hạn, kiểm chứng được |
| Backup không có alert | Hỏng âm thầm hàng tuần | Metric + alert `TaskhubBackupStale` |
| Không backup role (`pg_dumpall --globals-only`) ở hệ thống nhiều user | Restore xong app không đăng nhập được | Dump globals riêng, hoặc tài liệu hóa cách tạo lại user |

## 12. Đọc log và xử lý lỗi

### 12.1. Các lỗi hay gặp khi dump/restore

| Thông báo (minh họa — chữ có thể khác theo phiên bản) | Nguyên nhân | Cách xử lý |
|---|---|---|
| `pg_dump: error: server version: 17.x; pg_dump version: 16.x` + `aborting because of server version mismatch` | `pg_dump` cũ hơn server (chạy từ máy khác, không phải trong container) | Chạy `pg_dump` trong chính container PostgreSQL |
| `pg_restore: error: input file does not appear to be a valid archive` | File hỏng (thiếu `-T`, file rỗng, upload dở) hoặc là file `.sql` (định dạng plain) | `file <dump>`; với `.sql` dùng `psql -f`; kiểm tra lại cách tạo file |
| `pg_restore: error: could not execute query: ERROR: role "xyz" does not exist` | Dump có lệnh đặt owner cho role không tồn tại ở nơi restore | `--no-owner`, hoặc tạo role trước (`pg_dumpall --globals-only`) |
| `ERROR: database "taskhub" is being accessed by other users` | Đổi tên/xóa DB khi app còn kết nối | Dừng service `taskhub` trước |
| `createdb: error: database creation failed: ERROR: database "taskhub_restore" already exists` | Lần restore trước còn sót | `dropdb -U taskhub taskhub_restore` rồi tạo lại (chắc chắn đó **không** phải DB đang dùng) |

### 12.2. Đọc log khi xử lý sự cố — thứ tự gợi ý

1. **Alert** nói gì, bắt đầu lúc nào (`startsAt` trong payload)?
2. **Dashboard** quanh thời điểm đó: thành phần nào đổi trước (5xx tăng trước hay `up` về 0 trước?).
3. **Log** của thành phần đổi trước, lọc theo khoảng thời gian, tìm `ERROR` **đầu tiên** (không phải cuối cùng) — giống cách đọc stack trace ở [Linux 07](../01-LINUX/07-logs-monitoring-troubleshooting.md).
4. **Thay đổi gần nhất**: lịch sử deploy, `docker inspect` (image, env, thời điểm tạo container).

Ghi mỗi phát hiện vào `incident-notes.md` kèm giờ — sau này nó trở thành timeline của postmortem, và nên được lưu như một mục trong [nhật ký debug](../00-ROADMAP/templates/troubleshooting-journal-template.md).

## 13. Câu hỏi kiểm tra kiến thức

1. Liệt kê 5 giai đoạn của vòng đời sự cố. Giảm thiểu khác khắc phục thế nào?
2. Vì sao "không chắc thì chọn SEV cao hơn"?
3. Vì sao Incident Commander không nên tự tay sửa lỗi?
4. Khi nào nên roll forward thay vì rollback? Rủi ro của roll forward dưới áp lực là gì?
5. Một runbook tốt có những phần nào? Vì sao nên link runbook từ alert?
6. `pg_dump` có chặn người dùng khác đọc/ghi không? Bản dump có nhất quán không?
7. `pg_dump` có backup role không? Muốn có thì dùng lệnh gì?
8. Vì sao không nên `gzip` file tạo bởi `pg_dump -Fc`?
9. Vì sao phải dùng `docker compose exec -T` khi dump ra file?
10. Định nghĩa RPO và RTO. Backup mỗi 24 giờ thì RPO tệ nhất là bao nhiêu?
11. Giải thích quy tắc 3-2-1 và đánh giá thiết lập backup của `taskhub` v5 theo quy tắc này.
12. Nêu 3 cách backup có thể hỏng âm thầm và cách phát hiện từng cách.
13. Vì sao ngưỡng alert backup là 26 giờ chứ không phải 24 giờ?
14. "Không đổ lỗi" có nghĩa là không ai chịu trách nhiệm? Giải thích.
15. Viết lại hành động "Đội vận hành cần cẩn thận hơn khi deploy" thành hành động kiểm chứng được.

## 14. Bài tập tự làm

**Bài 1 — Đọc một postmortem thật.** Đọc bài postmortem của GitLab về sự cố 31/01/2017 (link ở Nguồn tham khảo). Viết 1 trang: timeline rút gọn (6–8 mốc), các lớp backup đã thất bại và vì sao, 3 bài học áp dụng được ngay cho `taskhub`.

**Bài 2 — Runbook rollback.** Viết `docs/runbooks/rollback.md`: rollback `taskhub` bằng workflow `Deploy` (`workflow_dispatch` với `image_tag` cũ) và phương án dự phòng khi GitHub Actions không dùng được (Session Manager + `scripts/deploy.sh <tag>`). Nêu cách tìm tag "tốt" gần nhất.

**Bài 3 — RPO/RTO cho 3 phương án.** Lập bảng so sánh RPO, RTO ước tính, chi phí, độ phức tạp cho: (a) `pg_dump` mỗi 24 giờ lên S3 (v5); (b) `pg_dump` mỗi giờ; (c) RDS PostgreSQL với automated backup 7 ngày. Dùng giá bạn tự tra (ghi ngày tra). Kết luận phương án nào hợp với `taskhub` lúc này và khi nào nên đổi.

**Bài 4 — Severity cho dự án.** Định nghĩa thang SEV-1→SEV-4 **riêng cho `taskhub`**: mỗi mức có tiêu chí đo được (tỷ lệ lỗi, thời gian, mất dữ liệu), ai cần được báo, kỳ vọng thời gian phản hồi. Lưu `docs/runbooks/severity.md`.

**Bài 5 — Postmortem cho một sự cố cũ của bạn.** Chọn một lỗi khó nhất trong `troubleshooting-journal.md` từ đầu khóa học, viết lại thành postmortem theo mẫu mục 4.10 (kể cả khi "người dùng" chỉ là bạn).

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được vòng đời sự cố và vì sao "giảm thiểu trước".
- [ ] Gán SEV hợp lý cho một tình huống mới và nêu lý do.
- [ ] Có `docs/runbooks/taskhub-down.md` chép-dán làm theo được, được link từ alert.
- [ ] Phân biệt được backup logic và PITR; biết `pg_dump` không chứa role.
- [ ] Tính được RPO/RTO cho một thiết lập backup và nói được RTO phải **đo**, không đoán.
- [ ] Nêu được 3 cách backup hỏng âm thầm và cách giám sát.
- [ ] Viết được postmortem không đổ lỗi, hành động có owner và hạn.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Google SRE Book — Chapter 15: Postmortem Culture](https://sre.google/sre-book/postmortem-culture/) | Postmortem không đổ lỗi, tiêu chí kích hoạt postmortem | 2026-10-31 |
| [Google SRE Book — Appendix D: Example Postmortem](https://sre.google/sre-book/example-postmortem/) | Cấu trúc mẫu postmortem (Summary, Impact, Root Causes, Timeline, Action Items, Lessons Learned) | 2026-10-31 |
| [PagerDuty Incident Response Documentation](https://response.pagerduty.com/) | Các vai trò khi xử lý sự cố | 2026-10-31 |
| [PagerDuty — Severity Levels](https://response.pagerduty.com/before/severity_levels/) | Thang SEV-1→SEV-5, "major incident" | 2026-10-31 |
| [GitLab — Postmortem of database outage of January 31](https://about.gitlab.com/blog/2017/02/10/postmortem-of-database-outage-of-january-31/) | Ví dụ thật về backup hỏng âm thầm | 2026-10-31 |
| [PostgreSQL 17 — pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html) | Định dạng custom, không chặn người dùng, không chứa đối tượng toàn cục, `--no-owner` | 2026-10-31 |
| [PostgreSQL 17 — pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html) | `--list`, `--no-owner`, `--exit-on-error`, `--single-transaction`, `-j`, đọc stdin | 2026-10-31 |
| [PostgreSQL 17 — Continuous Archiving and PITR](https://www.postgresql.org/docs/17/continuous-archiving.html) | Base backup + WAL, giới hạn chỉ khôi phục cả cluster | 2026-10-31 |
| [Amazon RDS — Introduction to backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html) | Snapshot cả instance, PITR, snapshot thủ công không tự xóa | 2026-10-31 |
| [node_exporter — Textfile Collector](https://github.com/prometheus/node_exporter) | `--collector.textfile.directory`, file `*.prom`, ghi file tạm rồi `mv` | 2026-10-31 |
