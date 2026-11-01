# 07. RDS — PostgreSQL do AWS quản lý

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc (Multi-AZ DB cluster, RDS Proxy 🟦) · Kiến thức cần có trước: [03. VPC](03-vpc-networking.md), [04. EC2](04-ec2.md), [06. AWS CLI](06-aws-cli.md), [Docker 04 — Volume](../04-DOCKER/04-volumes-networks-env.md), [Tạo app taskhub (tuần 6)](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)
> Môi trường: `[WSL]` có AWS CLI v2 đăng nhập bằng `aws login` (profile `taskhub`), `[AWS Console]`. Region `ap-southeast-1`.
> Bài này **không tạo** RDS. Phần thực hành chỉ dùng lệnh đọc (miễn phí) và Docker trên máy. RDS thật được dựng trong [Lab 03 — ALB + ASG + RDS](labs/lab-03-alb-asg-rds-short.md) ở tuần 14, trong **một buổi** rồi xóa.
> Số liệu khi viết (kiểm tra 2026-10-31): RDS for PostgreSQL 17 (17.11), giá Singapore lấy từ AWS Price List API.

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

- Giải thích **Amazon RDS** (Relational Database Service — dịch vụ cơ sở dữ liệu quan hệ được quản lý) làm thay bạn những gì so với PostgreSQL tự chạy trong Docker, và **bạn vẫn phải tự làm** những gì.
- Thiết kế phần mạng cho RDS: **DB subnet group** ở 2 AZ, subnet **private**, **Public access = No**, **security group tham chiếu security group**.
- Chọn **instance class** và **storage** phù hợp với ngân sách học tập (db.t4g.micro / db.t3.micro, gp3 20 GiB) và tính được chi phí theo giờ.
- Phân biệt **Single-AZ**, **Multi-AZ DB instance** và 🟦 **Multi-AZ DB cluster**; biết failover mất bao lâu và ứng dụng Java phải làm gì.
- Giải thích **automated backup**, **snapshot**, **PITR** (point-in-time recovery — khôi phục về một thời điểm) và vì sao khôi phục luôn tạo **instance mới**.
- Tránh hai bẫy chi phí: **RDS Extended Support** (mặc định **bật** khi tạo bằng CLI) và **snapshot quên xóa**.
- Viết được lập luận "khi nào `taskhub` nên chuyển sang RDS" dưới dạng ADR.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Database là thành phần **có trạng thái** (stateful) duy nhất của `taskhub`. Container app chết thì chạy lại là xong; database mất dữ liệu thì không có lệnh nào cứu được — trừ khi đã có backup đúng cách.

| Tình huống thật | Kiến thức trong bài |
|---|---|
| "Ổ đĩa EC2 hỏng, PostgreSQL trong Docker mất hết dữ liệu" | Vì sao managed database tồn tại; backup tự động |
| "Ai đó chạy `DELETE` thiếu `WHERE` lúc 14:32, khôi phục về 14:31 được không?" | PITR |
| "App không kết nối được database trên AWS" | Subnet group, security group, `Public access` |
| Hóa đơn tăng vì "RDS Extended Support" dù không ai bật | Mặc định của CLI/API |
| Phỏng vấn: "Multi-AZ khác read replica thế nào? Failover mất bao lâu?" | Mục 4.5 |
| ADR của dự án: "PostgreSQL tự chạy thay vì RDS" ([gợi ý trong README dự án](../12-PRACTICAL-PROJECT/README.md)) | Mục 4.10 |

Junior DevOps thường **không** thiết kế database, nhưng gần như chắc chắn phải: tạo/xóa môi trường có RDS, mở đúng đường mạng cho app, kiểm tra backup còn chạy, và khôi phục khi có sự cố.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. "Managed" nghĩa là gì — mô hình trách nhiệm chia sẻ áp dụng cho database

Nhắc lại **Shared Responsibility Model** từ [bài 01](01-cloud-fundamentals.md): AWS lo phần "của cloud", bạn lo phần "trong cloud". Với database, ranh giới nằm ở chỗ khác nhau tùy cách chạy:

| Việc | PostgreSQL trong Docker trên EC2 (`taskhub` v2) | Amazon RDS |
|---|---|---|
| Phần cứng, ổ đĩa vật lý, hypervisor | AWS | AWS |
| Hệ điều hành của máy chạy database, vá bảo mật OS | **Bạn** | AWS |
| Cài, nâng cấp **bản vá nhỏ** PostgreSQL (17.10 → 17.11) | **Bạn** (đổi image, chạy lại) | AWS, trong **maintenance window** bạn chọn |
| Nâng **phiên bản lớn** (16 → 17) | **Bạn** | **Bạn** quyết định và bấm (AWS làm phần kỹ thuật) |
| Backup hằng ngày + log để khôi phục theo thời điểm | **Bạn** tự viết (`pg_dump` + cron — v5) | AWS tự động |
| Dự phòng khi một AZ sự cố | **Bạn** (rất khó) | Bật **Multi-AZ** |
| Thiết kế schema, index, truy vấn chậm | **Bạn** | **Bạn** |
| Ai được kết nối (mạng, mật khẩu, quyền SQL) | **Bạn** | **Bạn** |
| Theo dõi dung lượng, CPU, kết nối | **Bạn** | **Bạn** (AWS cung cấp metric, bạn đặt alarm) |

> **Điểm then chốt:** RDS không làm thay phần "trong database" (schema, truy vấn, bảo mật truy cập). Nó gỡ khỏi vai bạn phần **vận hành máy chủ database** — phần mà khi làm sai thì mất dữ liệu.

### 3.2. Bạn mất gì khi dùng RDS

- **Không SSH/không shell** vào máy chạy database. Không cài extension tùy ý — chỉ những extension RDS hỗ trợ.
- **Không có tài khoản superuser thật**: user chủ (master user) có vai trò `rds_superuser`, bị giới hạn một số quyền.
- **Chi phí riêng**: tính theo giờ instance + GB lưu trữ + backup vượt mức miễn phí — trong khi PostgreSQL trong Docker "ăn ké" CPU/RAM của EC2 đang chạy.
- **Thời gian tạo/xóa lâu**: tạo một instance nhỏ thường mất khoảng 10–15 phút (ước lượng theo kinh nghiệm, không phải cam kết của AWS) — so với vài giây của `docker compose up`.

### 3.3. Endpoint là tên DNS, không phải IP

RDS cấp cho mỗi instance một **endpoint** dạng `lab03-pg.xxxxxxxx.ap-southeast-1.rds.amazonaws.com`. Luôn kết nối bằng tên này. IP phía sau **có thể đổi** (khi failover, khi đổi cấu hình) — tài liệu AWS khuyến nghị rõ "dùng DNS name, không dùng IP". Đây chính là kiến thức DNS ở [Network 03](../02-NETWORKING/03-dns-dhcp.md).

### 3.4. Từ vựng

| Thuật ngữ | Nghĩa |
|---|---|
| **DB instance** | Một máy chủ database do RDS quản lý (có thể chứa nhiều database bên trong) |
| **DB instance class** | Cỡ máy: `db.t4g.micro`, `db.m6g.large`… (tương tự EC2 instance type, có tiền tố `db.`) |
| **DB subnet group** | Danh sách subnet (ít nhất 2 AZ) mà RDS được phép đặt instance vào |
| **Parameter group** | Bộ cấu hình PostgreSQL (`postgresql.conf`) được quản lý dưới dạng tài nguyên AWS |
| **Automated backup** | Snapshot hằng ngày + log giao dịch, giữ trong **retention period** |
| **DB snapshot (manual)** | Bản chụp bạn tự tạo, **không** tự xóa khi xóa instance |
| **Maintenance window** | Khung giờ hằng tuần AWS được phép vá/khởi động lại |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Mạng: DB subnet group phải có 2 AZ — kể cả khi chỉ chạy Single-AZ

Theo tài liệu RDS, **mỗi DB subnet group phải có subnet ở ít nhất hai Availability Zone**. Lý do: nếu sau này bạn bật Multi-AZ hoặc AWS cần thay máy, RDS phải có chỗ ở AZ khác để đặt standby/instance mới.

Với VPC mẫu của giáo trình (bạn dùng bảng IP của mình trong `docs/network-plan.md`):

| Subnet | AZ | CIDR mẫu | Dùng cho RDS? |
|---|---|---|---|
| `taskhub-private-a` | ap-southeast-1a | 10.20.11.0/24 | ✅ |
| `taskhub-private-b` | ap-southeast-1b | 10.20.12.0/24 | ✅ |
| `taskhub-public-a/b` | 1a / 1b | 10.20.1.0/24, 10.20.2.0/24 | ❌ — database không đặt ở subnet có đường ra Internet Gateway |

Nhắc lại từ [bài 03](03-vpc-networking.md): subnet "private" là subnet mà **route table không có** route `0.0.0.0/0 → igw-...`. Hai subnet private của chúng ta không có NAT → database **không ra được Internet** và **Internet không vào được**. RDS không cần ra Internet để chạy; AWS quản lý nó qua mạng nội bộ của dịch vụ.

Tài liệu cũng lưu ý: mỗi subnet phải còn đủ IP trống cho RDS dùng khi bảo trì/failover — một `/24` là dư.

### 4.2. 🟥 `Public access = No` và security group tham chiếu security group

**Public access** (tham số CLI `--publicly-accessible` / `--no-publicly-accessible`) quyết định instance có **IP public** hay không. Với `taskhub`: **luôn là No**.

Ngay cả khi `Public access = No`, ai kết nối được vẫn do **security group** quyết định. Cách đúng là **SG tham chiếu SG**, không dùng dải IP:

```text
SG của app (taskhub-web-sg / lab03-web-sg)
        │  inbound của DB SG: TCP 5432, Source = sg-<id của SG app>
        ▼
SG của DB (taskhub-db-sg / lab03-db-sg)
```

Vì sao tốt hơn `Source = 10.20.0.0/16`?

- Chỉ **những ENI mang SG app** mới vào được, không phải mọi máy trong VPC.
- ASG thêm/bớt instance, IP thay đổi liên tục — rule theo SG **không cần sửa**.
- Đọc rule là hiểu ý đồ: "app được nói chuyện với DB".

Đây là cùng nguyên tắc "chỉ nginx publish port, PostgreSQL không publish" ở [Docker 05](../04-DOCKER/05-docker-compose.md) — chỉ khác là bây giờ bức tường là security group thay vì Docker network.

### 4.3. 🟥 Instance class, storage và giá (Singapore)

**Free plan.** Trang RDS Free Tier ghi: *"Free plan is available on db.t3.micro and db.t4g.micro instances"* cho MySQL, PostgreSQL, MariaDB. Với tài khoản tạo sau 15/7/2025 (tài khoản của bạn), mức sử dụng được **trừ vào credit**, không phải "miễn phí 750 giờ" như tài liệu cũ trên mạng.

Giá on-demand RDS for PostgreSQL ở `ap-southeast-1` (AWS Price List API, kiểm tra 2026-10-31):

| Thành phần | Giá | Ghi chú |
|---|---|---|
| `db.t4g.micro` Single-AZ | **0,025 USD/giờ** | Graviton (ARM), 2 vCPU, 1 GiB RAM |
| `db.t4g.micro` Multi-AZ | 0,051 USD/giờ | Gấp đôi — vì có thêm standby |
| `db.t3.micro` Single-AZ | 0,028 USD/giờ | Intel |
| Lưu trữ gp3 Single-AZ | 0,138 USD/GB-tháng | 20 GB ≈ 2,76 USD/tháng |
| Lưu trữ gp3 Multi-AZ | 0,276 USD/GB-tháng | Gấp đôi — dữ liệu nằm ở cả primary và standby |
| Backup vượt mức miễn phí | 0,095 USD/GB-tháng | Miễn phí = 100% dung lượng đã cấp phát |

Ví dụ: `db.t4g.micro` Single-AZ + 20 GB gp3 chạy cả tháng ≈ 0,025 × 730 + 2,76 ≈ **21 USD/tháng** — khoảng 10–20% tổng credit Free plan của bạn **mỗi tháng**. Đó là lý do dự án chính dùng PostgreSQL trong Docker, còn RDS chỉ dựng trong lab ngắn.

> ⚠️ Giá thay đổi theo thời gian và theo Region. Trước mỗi lab, mở [trang giá RDS](https://aws.amazon.com/rds/postgresql/pricing/) hoặc [AWS Pricing Calculator](https://calculator.aws/) để kiểm tra lại.

**Instance "burstable" (`t`).** Giống EC2 t3/t4g: có **CPU credit**. Đủ cho học tập; với database production tải đều thì thường chọn họ `m`/`r`.

**Storage.** Chọn **gp3**. Tối thiểu 20 GiB với gp3 cho PostgreSQL (console sẽ báo nếu thấp hơn). 🟨 **Storage autoscaling** (`--max-allocated-storage`) tự tăng dung lượng khi gần đầy — hữu ích cho production, nhưng nhớ: dung lượng **chỉ tăng, không giảm được** (khi restore cũng không giảm được, theo tài liệu PITR).

### 4.4. 🟥 Backup tự động, snapshot và PITR

**Automated backup** gồm hai phần:

1. Một **snapshot ổ đĩa** mỗi ngày trong **backup window**.
2. **Log giao dịch** được RDS tải lên S3 **mỗi 5 phút** (theo tài liệu PITR).

Nhờ (1) + (2), bạn khôi phục được về **bất kỳ thời điểm nào** trong **retention period**, muộn nhất là `LatestRestorableTime` (thường cách hiện tại vài phút).

| Thông số | Giá trị (theo tài liệu RDS) |
|---|---|
| Retention period | 0–35 ngày. **0 = tắt automated backup** |
| Mặc định khi tạo bằng console | 7 ngày |
| Mặc định khi tạo bằng CLI/API (không ghi tham số) | **1 ngày** |
| Đổi giữa 0 và khác 0 | Gây **gián đoạn** (outage) |
| Dung lượng backup miễn phí | Bằng 100% storage đã cấp phát, trong mỗi Region |

**Ba điều hay bị hiểu sai:**

1. **Khôi phục luôn tạo instance MỚI** với endpoint MỚI. Instance cũ vẫn nguyên. App phải đổi sang endpoint mới (hoặc bạn đổi tên instance) — đó là việc bạn phải ghi trong runbook.
2. **Instance khôi phục dùng parameter group mặc định** (nếu restore bằng console) và bạn chọn lại security group. Quên bước này → app không kết nối được dù database đã khôi phục xong.
3. **Snapshot thủ công không bị xóa** khi xóa instance và vẫn tính tiền lưu trữ — nguồn "chi phí ma" phổ biến nhất của người mới.

**Automated backup có thay thế `pg_dump` không?** Không hoàn toàn. Snapshot RDS chỉ khôi phục được **vào RDS**, trong cùng tài khoản/Region (trừ khi copy). `pg_dump` cho ra file SQL **mang đi đâu cũng được** (sang Docker trên laptop, sang nhà cung cấp khác). Nhiều team dùng cả hai. `taskhub` v5 dùng `pg_dump` lên S3 vì database chạy trong Docker.

### 4.5. 🟥 Single-AZ, Multi-AZ DB instance, 🟦 Multi-AZ DB cluster

```text
Single-AZ                     Multi-AZ DB instance                  🟦 Multi-AZ DB cluster
┌────────┐                    ┌────────┐ đồng bộ  ┌─────────┐       writer ──► reader A (đọc được)
│primary │ AZ-a               │primary │ ───────► │ standby │       (AZ-a) └─► reader B (đọc được)
└────────┘                    └────────┘  AZ-a    └─────────┘ AZ-b         3 AZ khác nhau
AZ-a sự cố = mất dịch vụ      standby KHÔNG đọc được                bán đồng bộ (cần ≥1 reader xác nhận)
đến khi AWS khôi phục         failover thường 60–120 giây           chỉ hỗ trợ một số class (không có db.t*)
```

**Multi-AZ DB instance** (loại phổ biến nhất):

- RDS duy trì một **standby đồng bộ** (synchronous) ở AZ khác. Mọi thay đổi ghi vào cả hai trước khi xác nhận.
- Standby **không phục vụ đọc** — tài liệu ghi rõ đây không phải giải pháp mở rộng đọc. Muốn đọc song song: **read replica** (bất đồng bộ) hoặc Multi-AZ DB cluster.
- Khi primary hỏng (hoặc khi vá OS, khi bạn bấm *Reboot with failover*), RDS chuyển **DNS của endpoint** sang standby. Theo tài liệu: **thường 60–120 giây**, có thể lâu hơn với giao dịch lớn.
- Giá gấp đôi Single-AZ: cả giờ instance (0,051 so với 0,025 USD/giờ) lẫn storage (0,276 so với 0,138 USD/GB-tháng).

**Ứng dụng Java và DNS cache.** Vì failover là **đổi DNS**, ứng dụng phải **tra DNS lại**. Tài liệu RDS khuyến nghị đặt TTL cache DNS của JVM **không quá 60 giây** (`networkaddress.cache.ttl=60`) và cho biết nhiều JVM hiện đại (không bật security manager) đã có mặc định dưới 60 giây. Ngoài ra, connection pool (HikariCP trong Spring Boot) phải bỏ các kết nối cũ đã chết và mở kết nối mới — Hikari làm được việc này khi kết nối hỏng bị phát hiện.

🟦 **Multi-AZ DB cluster**: 1 writer + 2 reader **đọc được** ở 3 AZ, dùng replication bán đồng bộ; failover phụ thuộc độ trễ replica. Chỉ hỗ trợ các class như `db.m6gd`, `db.r6gd`, `db.c6gd`… (danh sách trong tài liệu) — không có `db.t*`, nên ngoài tầm ngân sách học tập. Đừng nhầm với **Aurora** (một engine khác của AWS).

### 4.6. 🟨 Parameter group — `postgresql.conf` dưới dạng tài nguyên

Bạn không sửa được `postgresql.conf` trên RDS. Thay vào đó:

- Mỗi instance gắn một **DB parameter group**. Mặc định là group `default.postgres17` — **không sửa được**.
- Muốn đổi tham số (ví dụ `log_min_duration_statement` để log truy vấn chậm): tạo **custom parameter group** (họ `postgres17`), sửa, gắn vào instance.
- Tham số **dynamic** áp dụng ngay; tham số **static** cần **reboot**. Console hiển thị trạng thái `pending-reboot`.

Một tham số bạn sẽ gặp: **`rds.force_ssl`**. Theo tài liệu RDS, với PostgreSQL **15 trở lên**, mặc định là **1** — kết nối **không dùng SSL bị từ chối**. `psql` và driver JDBC PostgreSQL mặc định dùng `sslmode=prefer` (thử SSL trước) nên thường vẫn kết nối được; nhưng nếu ai đó cấu hình `sslmode=disable`, họ sẽ gặp lỗi `no pg_hba.conf entry ... no encryption`.

### 4.7. 🟥 Mã hóa, mật khẩu chủ

- **Mã hóa lúc lưu** (encryption at rest) bằng KMS: bật **khi tạo** (`--storage-encrypted`). Một instance đã tạo không mã hóa thì không bật trực tiếp được — phải snapshot → copy snapshot có mã hóa → restore thành instance mới. Vì vậy: luôn bật từ đầu.
- **Mã hóa đường truyền**: SSL như mục 4.6.
- **Mật khẩu master user**: hai lựa chọn — tự đặt, hoặc để RDS quản lý trong **AWS Secrets Manager** (tự xoay vòng; Secrets Manager tính phí theo mỗi secret mỗi tháng — xem [bảng giá Secrets Manager](https://aws.amazon.com/secrets-manager/pricing/)). Lab của giáo trình tự sinh mật khẩu ngẫu nhiên, chỉ giữ trong biến shell, xóa cùng instance. `taskhub` thật (nếu chuyển RDS) nên để mật khẩu trong Parameter Store SecureString — giống cách v2 làm với `/taskhub/dev/postgres-password`.

### 4.8. 🟥 Bẫy chi phí: RDS Extended Support bật mặc định khi dùng CLI

Mỗi phiên bản lớn PostgreSQL trên RDS có **ngày hết hỗ trợ chuẩn** (end of standard support). Sau ngày đó, nếu instance đang **đăng ký Extended Support**, AWS **tự tính thêm phí** để tiếp tục chạy phiên bản cũ (tối đa 3 năm). Nếu **không** đăng ký, AWS **tự nâng** lên phiên bản lớn tiếp theo.

Điểm nguy hiểm, theo tài liệu RDS:

| Cách tạo | Extended Support mặc định |
|---|---|
| Console | **Không** chọn (ô *Enable RDS Extended Support* để trống) |
| AWS CLI / API / CloudFormation, **không ghi tham số** | **Bật** (`open-source-rds-extended-support`) |

→ Khi tạo bằng CLI cho lab, luôn ghi:

```bash
--engine-lifecycle-support open-source-rds-extended-support-disabled
```

Lịch hỗ trợ (theo trang release calendar RDS for PostgreSQL, kiểm tra 2026-10-31):

| Phiên bản | Hết hỗ trợ chuẩn trên RDS |
|---|---|
| PostgreSQL 14 | 28/02/2027 — **gần đúng lúc bạn học tuần 14**, đừng chọn |
| PostgreSQL 16 | 28/02/2029 |
| **PostgreSQL 17** (khớp `postgres:17` của `taskhub`) | 28/02/2030 |
| PostgreSQL 18 | 28/02/2031 |

Giữ **cùng phiên bản lớn** giữa laptop (Docker) và RDS để migration Flyway và hành vi SQL giống nhau.

### 4.9. 🟦 RDS Proxy

**RDS Proxy** là connection pool do AWS quản lý, đứng giữa app và RDS: gom nhiều kết nối từ app thành ít kết nối tới database, giảm thời gian gián đoạn khi failover. Có ích khi có **rất nhiều** kết nối ngắn (ví dụ Lambda). Với `taskhub` (một vài instance Spring Boot đã có HikariCP) thì không cần, và Proxy tính phí riêng. Chỉ cần biết tên và công dụng.

### 4.10. 🟥 Khi nào `taskhub` nên chuyển sang RDS? (chất liệu cho ADR)

| Tiêu chí | PostgreSQL trong Docker trên EC2 (hiện tại) | RDS |
|---|---|---|
| Chi phí thêm/tháng (Singapore) | ~0 (dùng chung t3.small) | ~21 USD (`db.t4g.micro` + 20 GB) |
| Backup | Tự viết, tự kiểm tra (v5) | Tự động + PITR |
| Mất một AZ | Mất dịch vụ, có thể mất dữ liệu kể từ backup cuối | Multi-AZ: failover 1–2 phút |
| EC2 bị xóa nhầm (`terraform destroy`) | **Mất volume `pgdata`** nếu không backup | Database tách khỏi EC2, không ảnh hưởng |
| Học được gì | Vận hành PostgreSQL thật, backup/restore bằng tay | Dịch vụ managed, mạng, IAM |
| Mở rộng ra nhiều EC2 (ASG) | **Không làm được** — mỗi EC2 có một database riêng | Bắt buộc phải có database dùng chung |

**Kết luận cho dự án học tập:** giữ PostgreSQL trong Docker vì chi phí và vì bạn cần tự làm backup/restore ở v5. **Điều kiện để chuyển sang RDS** (ghi vào ADR): khi cần nhiều hơn một instance app (ALB + ASG), khi dữ liệu có giá trị thật, hoặc khi yêu cầu RPO/RTO chặt hơn khả năng tự vận hành.

> **RPO** (Recovery Point Objective — mất tối đa bao nhiêu dữ liệu) và **RTO** (Recovery Time Objective — mất bao lâu để chạy lại) là hai chỉ số sẽ quay lại ở Module 08 (backup/restore).

### 4.11. Gặp lại ở đâu

| Kiến thức | Gặp lại |
|---|---|
| DB subnet group, SG tham chiếu SG | [Lab 03](labs/lab-03-alb-asg-rds-short.md); Terraform module RDS (Module 07, 🟨) |
| PITR, snapshot, RPO/RTO | Module 08 — backup/restore và diễn tập sự cố; v5 `pg_dump` lên S3 |
| Failover = đổi DNS, DNS cache JVM | [08. ELB & Auto Scaling](08-elb-autoscaling.md) (ALB cũng dùng DNS TTL 60 giây); Kubernetes Service (Module 09) |
| Extended Support, phiên bản lớn | Kế hoạch nâng cấp trong runbook v1.0 |
| Secrets Manager / Parameter Store | v2–v3 (`/taskhub/dev/postgres-password`), Module 10 |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Đã có backup" nhưng không khôi phục được

Một team bật automated backup 7 ngày và yên tâm. Khi cần khôi phục, họ mới phát hiện: (1) không ai biết restore tạo **instance mới** nên app vẫn trỏ endpoint cũ; (2) instance mới gắn SG mặc định nên app không kết nối được; (3) mất 40 phút mới xong vì chưa từng diễn tập. Bài học: **backup chưa diễn tập restore = chưa có backup**. Module 08 sẽ bắt bạn diễn tập.

### Ví dụ 2: Database "public" vì tiện debug

Một dev bật `Public access = Yes` và mở SG `5432` từ `0.0.0.0/0` để kết nối từ máy nhà "cho nhanh", định tắt sau. Vài giờ sau log đầy các lần dò mật khẩu `postgres`/`admin` từ khắp nơi. Cách đúng để kết nối từ laptop vào database private: đi qua một EC2 trong VPC (SSM Session Manager, 🟨 port forwarding qua SSM) — không bao giờ mở database ra Internet.

### Ví dụ 3: Hóa đơn RDS tăng không rõ lý do

Một hệ thống được dựng bằng script CLI từ 2022 với PostgreSQL 12. Không ai ghi `--engine-lifecycle-support`. Sau ngày hết hỗ trợ chuẩn, dòng *Extended Support* xuất hiện trên hóa đơn mỗi tháng. Bài học: đọc mặc định của API, và đặt lịch nâng cấp phiên bản lớn trước hạn.

---

## 6. Sơ đồ kiến trúc

### 6.1. RDS trong VPC của `taskhub` (khi có ALB + ASG — dựng ở Lab 03)

```text
                         Internet
                            │
                     ┌──────┴──────┐  Internet Gateway (taskhub-igw)
VPC 10.20.0.0/16     │             │
┌────────────────────┼─────────────┼───────────────────────────────────┐
│  AZ ap-southeast-1a│             │ AZ ap-southeast-1b                │
│ ┌──────────────────▼──┐   ┌──────▼──────────────┐                     │
│ │ public-a 10.20.1/24 │   │ public-b 10.20.2/24 │  route 0.0.0.0/0→igw│
│ │  ALB node  EC2 web  │   │  ALB node  EC2 web  │                     │
│ └─────────────┬───────┘   └───────┬─────────────┘                     │
│               │ TCP 5432 (SG web → SG db)                              │
│ ┌─────────────▼───────┐   ┌───────▼─────────────┐                     │
│ │ private-a 10.20.11/24│  │ private-b 10.20.12/24│ KHÔNG có route ra   │
│ │  RDS primary        │   │ (chỗ cho standby     │ Internet            │
│ │                     │   │  nếu bật Multi-AZ)   │                     │
│ └─────────────────────┘   └─────────────────────┘                     │
│        └──────── DB subnet group "lab03-db-subnets" ──────┘           │
└──────────────────────────────────────────────────────────────────────┘
```

### 6.2. Luồng PITR

```text
Ngày 1 02:00      Ngày 2 02:00                 14:31   14:32 (DELETE nhầm)   bây giờ
  snapshot ─────────── snapshot ── log ── log ── log ──── log ──── log ──►
                                    │ (log tải lên S3 mỗi 5 phút)
restore-db-instance-to-point-in-time --restore-time 14:31
  = lấy snapshot ngày 2 + phát lại log đến 14:31
  → instance MỚI "taskhub-pg-restored" (endpoint mới, SG/param group phải đặt lại)
```

---

## 7. Các câu lệnh cần biết

Tất cả lệnh trong bảng là lệnh **đọc** (miễn phí), trừ những dòng có ⚠️.

| Lệnh | Mục đích |
|---|---|
| `aws rds describe-db-engine-versions --engine postgres ...` | Liệt kê phiên bản PostgreSQL RDS hỗ trợ |
| `aws rds describe-orderable-db-instance-options ...` | Class nào, storage nào, Multi-AZ được không — cho một phiên bản/Region |
| `aws rds describe-db-instances` | Xem instance: trạng thái, endpoint, AZ, backup |
| `aws rds describe-db-snapshots --snapshot-type manual` | Tìm snapshot thủ công còn sót (tốn tiền) |
| `aws rds describe-events --source-type db-instance --duration 1440` | Sự kiện 24 giờ qua: backup, failover, reboot |
| ⚠️ `aws rds create-db-subnet-group ...` | Tạo subnet group (miễn phí, nhưng phải dọn) |
| ⚠️ `aws rds create-db-instance ...` | **Tạo instance — bắt đầu tính tiền** |
| ⚠️ `aws rds delete-db-instance --skip-final-snapshot ...` | **Xóa instance và dữ liệu** |
| ⚠️ `aws rds restore-db-instance-to-point-in-time ...` | Tạo **instance mới** từ backup — tính tiền thêm |

---

## 8. Giải thích câu lệnh và tham số

### `describe-db-engine-versions` — phiên bản nào đang có

```bash
# [WSL]
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws rds describe-db-engine-versions --engine postgres \
  --query "DBEngineVersions[?starts_with(EngineVersion, '17.')].EngineVersion" \
  --output text
```

Đầu ra minh họa:

```text
17.7    17.9    17.10   17.11
```

| Thành phần | Ý nghĩa |
|---|---|
| `--engine postgres` | Chỉ PostgreSQL (không phải `aurora-postgresql`) |
| `--query "...[?starts_with(EngineVersion, '17.')]..."` | JMESPath (đã học ở [bài 06](06-aws-cli.md)): lọc các bản 17.x |
| `--output text` | In gọn trên một dòng |

Chọn bản **mới nhất** trong danh sách. Một số bản cũ có trạng thái không cho tạo mới (release calendar ghi chú `NO_CREATE`).

### `describe-orderable-db-instance-options` — class này có dùng được không

```bash
aws rds describe-orderable-db-instance-options --engine postgres \
  --engine-version 17.11 --db-instance-class db.t4g.micro \
  --query "OrderableDBInstanceOptions[].{Storage:StorageType,MultiAZ:MultiAZCapable,AZs:join(',',AvailabilityZones[].Name)}" \
  --output table
```

Đầu ra minh họa:

```text
------------------------------------------------------------------------------------
|                         DescribeOrderableDBInstanceOptions                       |
+-------------------------------------------------------------+----------+---------+
|                             AZs                             | MultiAZ  | Storage |
+-------------------------------------------------------------+----------+---------+
|  ap-southeast-1a,ap-southeast-1b,ap-southeast-1c            |  True    |  gp2    |
|  ap-southeast-1a,ap-southeast-1b,ap-southeast-1c            |  True    |  gp3    |
|  ap-southeast-1a,ap-southeast-1b,ap-southeast-1c            |  True    |  io1    |
+-------------------------------------------------------------+----------+---------+
```

Lệnh này trả lời câu hỏi "tôi có tạo được tổ hợp này ở Region này không" **trước khi** tạo — tránh lỗi giữa chừng.

### ⚠️ `create-db-instance` — đọc hiểu (chạy thật ở Lab 03)

```bash
aws rds create-db-instance \
  --db-instance-identifier lab03-pg \
  --engine postgres --engine-version "$PG_VERSION" \
  --db-instance-class db.t4g.micro \
  --allocated-storage 20 --storage-type gp3 --storage-encrypted \
  --master-username labadmin --master-user-password "$DB_PASS" \
  --db-subnet-group-name lab03-db-subnets \
  --vpc-security-group-ids "$DB_SG" \
  --no-publicly-accessible --no-multi-az \
  --backup-retention-period 1 \
  --engine-lifecycle-support open-source-rds-extended-support-disabled \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab Key=Lab,Value=lab03
```

| Tham số | Vì sao |
|---|---|
| `--db-instance-identifier` | Tên instance, cũng là phần đầu của endpoint |
| `--engine-version "$PG_VERSION"` | Phiên bản đầy đủ lấy từ lệnh `describe-db-engine-versions` |
| `--db-instance-class db.t4g.micro` | Rẻ nhất, nằm trong danh sách Free plan |
| `--allocated-storage 20 --storage-type gp3` | 20 GiB gp3 |
| `--storage-encrypted` | Mã hóa lúc lưu (không bật được sau) |
| `--master-user-password "$DB_PASS"` | Lấy từ biến shell, **không** gõ thẳng vào lệnh (tránh lưu vào `~/.bash_history`) |
| `--db-subnet-group-name` | Đặt vào 2 subnet private |
| `--vpc-security-group-ids` | SG chỉ cho SG app vào 5432 |
| `--no-publicly-accessible` | Không có IP public |
| `--no-multi-az` | Single-AZ cho lab (rẻ bằng nửa) |
| `--backup-retention-period 1` | Ghi rõ thay vì dựa vào mặc định |
| `--engine-lifecycle-support ...-disabled` | **Tránh phí Extended Support** (mặc định CLI là bật) |
| `--tags` | Để `find-leftovers.sh` ([bài 06](06-aws-cli.md)) tìm thấy khi dọn dẹp |

### ⚠️ `delete-db-instance`

```bash
aws rds delete-db-instance --db-instance-identifier lab03-pg \
  --skip-final-snapshot --delete-automated-backups
aws rds wait db-instance-deleted --db-instance-identifier lab03-pg
```

| Tham số | Ý nghĩa |
|---|---|
| `--skip-final-snapshot` | Không chụp snapshot cuối. **Dữ liệu mất vĩnh viễn.** Chấp nhận được cho lab (không có dữ liệu thật); **không bao giờ** dùng cho production |
| `--delete-automated-backups` | Xóa luôn automated backup (nếu không, chúng được giữ đến hết retention) |
| `wait db-instance-deleted` | Chặn đến khi xóa xong (thường vài phút) — để biết chắc đã hết tính tiền |

Không có `--skip-final-snapshot` thì phải ghi `--final-db-snapshot-identifier <tên>` — snapshot đó **tồn tại mãi** đến khi bạn tự xóa.

### `restore-db-instance-to-point-in-time` — đọc hiểu

```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier taskhub-pg \
  --target-db-instance-identifier taskhub-pg-restored \
  --restore-time 2027-03-15T07:31:00Z \
  --db-subnet-group-name taskhub-db-subnets \
  --vpc-security-group-ids sg-0123456789abcdef0 \
  --no-publicly-accessible
```

- `--restore-time` là **UTC** (chữ `Z`). 14:31 giờ Việt Nam (UTC+7) = 07:31Z. Nhầm múi giờ là lỗi kinh điển khi khôi phục lúc căng thẳng.
- Thay `--restore-time` bằng `--use-latest-restorable-time` để lấy thời điểm muộn nhất có thể.
- Ghi rõ subnet group và SG — đừng để mặc định.

---

## 9. Bài thực hành từng bước

Thực hành bài này **không tạo tài nguyên AWS**. Phần A dùng lệnh đọc; phần B dùng Docker trên máy để **tự cảm nhận** những việc RDS làm thay bạn. RDS thật: [Lab 03](labs/lab-03-alb-asg-rds-short.md).

### Phần A — Khảo sát RDS bằng lệnh đọc `[WSL]`

**Bước 1.** Đăng nhập và đặt Region:

```bash
aws login --profile taskhub          # nếu phiên đã hết hạn
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
aws sts get-caller-identity --query Arn --output text
```

**Bước 2.** Tìm bản PostgreSQL 17 mới nhất, lưu vào biến:

```bash
PG_VERSION=$(aws rds describe-db-engine-versions --engine postgres \
  --query "DBEngineVersions[?starts_with(EngineVersion, '17.')].EngineVersion | [-1]" \
  --output text)
echo "$PG_VERSION"
```

❓ Vì sao `| [-1]` lấy được bản mới nhất? (Gợi ý: thứ tự kết quả trả về — kiểm tra bằng cách bỏ `| [-1]`.)

**Bước 3.** Kiểm tra `db.t4g.micro` và `db.t3.micro` dùng được gp3 không (lệnh ở mục 8). Ghi kết quả vào `week14/rds-notes.md`.

**Bước 4.** Xem các DB parameter group mặc định và giá trị `rds.force_ssl` của họ `postgres17`:

```bash
aws rds describe-db-parameters --db-parameter-group-name default.postgres17 \
  --query "Parameters[?ParameterName=='rds.force_ssl'].[ParameterName,ParameterValue,ApplyType]" \
  --output table
```

> Nếu group `default.postgres17` chưa tồn tại trong tài khoản của bạn (nó thường được tạo khi bạn tạo instance đầu tiên), dùng `aws rds describe-engine-default-parameters --db-parameter-group-family postgres17 --query "EngineDefaults.Parameters[?ParameterName=='rds.force_ssl']"`.

**Bước 5.** Kiểm tra tài khoản **không có** RDS/snapshot nào đang tồn tại (thói quen trước và sau mỗi lab):

```bash
aws rds describe-db-instances --query "DBInstances[].DBInstanceIdentifier" --output text
aws rds describe-db-snapshots --snapshot-type manual --query "DBSnapshots[].DBSnapshotIdentifier" --output text
```

Hai lệnh phải in ra **rỗng**.

### Phần B — Tự làm "PITR" bằng tay với Docker để thấy RDS làm thay gì `[WSL]`

Mục tiêu: cảm nhận khôi phục **về một thời điểm** khó thế nào khi tự vận hành — chỉ với `pg_dump` bạn chỉ quay về được **thời điểm dump**, không phải "14:31".

**Bước 6.** Chạy PostgreSQL 17 tạm:

```bash
mkdir -p ~/devops-lab/06-aws/rds-feel && cd ~/devops-lab/06-aws/rds-feel
docker run -d --name pg-feel -e POSTGRES_PASSWORD=feel-only -p 127.0.0.1:55433:5432 postgres:17
sleep 5
docker exec pg-feel psql -U postgres -c "create table tasks(id serial primary key, title text, created_at timestamptz default now());"
```

**Bước 7.** Ghi dữ liệu, dump, rồi ghi thêm, rồi "xóa nhầm":

```bash
docker exec pg-feel psql -U postgres -c "insert into tasks(title) values ('A'),('B');"
docker exec pg-feel pg_dump -U postgres -Fc -f /tmp/dump-1.pgc postgres
docker cp pg-feel:/tmp/dump-1.pgc .
sleep 60
docker exec pg-feel psql -U postgres -c "insert into tasks(title) values ('C - ghi sau dump');"
docker exec pg-feel psql -U postgres -c "select now();"     # ghi lại: đây là thời điểm "14:31"
docker exec pg-feel psql -U postgres -c "delete from tasks;" # "14:32" — xóa nhầm
```

**Bước 8.** Khôi phục từ dump vào một database mới và so sánh:

```bash
docker exec pg-feel psql -U postgres -c "create database restored;"
docker cp dump-1.pgc pg-feel:/tmp/dump-1.pgc
docker exec pg-feel pg_restore -U postgres -d restored /tmp/dump-1.pgc
docker exec pg-feel psql -U postgres -d restored -c "select id,title from tasks order by id;"
```

❓ Dòng `C` có trong bản khôi phục không? Muốn có nó, bạn cần thêm cơ chế gì? (Gợi ý: **WAL archiving** — đúng thứ RDS làm khi "tải log lên S3 mỗi 5 phút".) Ghi câu trả lời vào `week14/rds-notes.md`.

**Bước 9.** ⚠️ Dọn dẹp (chỉ xóa container của bài này):

```bash
docker rm -f pg-feel
rm -f ~/devops-lab/06-aws/rds-feel/dump-1.pgc
```

### Phần C — Viết nháp ADR `[WSL]`

**Bước 10.** Trong repo `taskhub`, tạo nháp `docs/adr/NNNN-postgresql-self-managed-vs-rds.md` (số tiếp theo của bạn) theo [mẫu ADR](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr). Dùng bảng ở mục 4.10, số liệu giá bạn tự kiểm tra lại, và nêu **điều kiện kích hoạt** để chuyển sang RDS. Trạng thái: "Đề xuất" — bạn sẽ chốt sau Lab 03.

---

## 10. Kết quả mong đợi

- `week14/rds-notes.md` có: bản PostgreSQL 17 mới nhất, kết quả kiểm tra class/storage, giá trị `rds.force_ssl`, câu trả lời về dòng `C`.
- Hai lệnh ở Bước 5 in ra rỗng.
- Bản khôi phục ở Bước 8 có `A`, `B` nhưng **không có** `C` — và bạn giải thích được vì sao.
- Nháp ADR có bảng so sánh, số liệu có ngày kiểm tra, và điều kiện chuyển đổi rõ ràng.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `DBSubnetGroupDoesNotCoverEnoughAZs` khi tạo subnet group / instance | Subnet group chỉ có subnet ở 1 AZ | Thêm subnet ở AZ thứ hai (`private-b`) |
| App báo `Connection timed out` tới endpoint | SG của DB không cho SG app vào 5432; hoặc app chạy ngoài VPC (laptop) | Sửa inbound rule DB SG: `5432` từ **SG app**. Từ laptop thì không kết nối trực tiếp được — đúng thiết kế |
| `Connection refused` thay vì timeout | Hiếm với RDS — thường là sai port, hoặc instance đang `rebooting`/`modifying` | `describe-db-instances` xem `DBInstanceStatus`, `Endpoint.Port` |
| `FATAL: password authentication failed for user "labadmin"` | Sai mật khẩu, hoặc biến `$DB_PASS` rỗng khi tạo | Đổi mật khẩu: `modify-db-instance --master-user-password ... --apply-immediately` |
| `no pg_hba.conf entry for host ... no encryption` | Client dùng `sslmode=disable`, mà PG ≥ 15 mặc định `rds.force_ssl=1` | Dùng `sslmode=require` (hoặc `verify-full` với CA bundle của RDS) |
| `InvalidParameterCombination` khi chọn class | Class không hỗ trợ phiên bản/Region/Multi-AZ đó | Chạy `describe-orderable-db-instance-options` trước |
| Hóa đơn có dòng *Extended Support* | Tạo bằng CLI không ghi `--engine-lifecycle-support` với phiên bản đã hết hỗ trợ chuẩn | Nâng phiên bản lớn; lần sau ghi rõ tham số |
| Đã xóa instance mà vẫn bị tính phí RDS | Còn **manual snapshot** hoặc final snapshot | `describe-db-snapshots --snapshot-type manual` → xóa snapshot không cần |
| Restore xong app vẫn thấy dữ liệu cũ | App vẫn trỏ **endpoint cũ** | Đổi endpoint trong cấu hình app (hoặc đổi tên instance) |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Ba nguồn thông tin của RDS

| Nguồn | Xem thế nào | Trả lời câu hỏi |
|---|---|---|
| **Events** | `aws rds describe-events --source-type db-instance --source-identifier lab03-pg --duration 1440` hoặc tab *Logs & events* | Có failover/reboot/backup lúc mấy giờ? |
| **Database log** (`postgresql.log`) | Tab *Logs & events* → *Logs*; hoặc `aws rds download-db-log-file-portion` | Ai kết nối thất bại, truy vấn lỗi gì |
| **Metric CloudWatch** | Tab *Monitoring*: `CPUUtilization`, `FreeStorageSpace`, `DatabaseConnections`, `FreeableMemory` | Database có đang quá tải/sắp đầy không ([bài 10](10-cloudwatch.md)) |

Ví dụ events (minh họa):

```text
2027-03-15T07:12:04Z  lab03-pg  Backing up DB instance
2027-03-15T07:14:51Z  lab03-pg  Finished DB Instance backup
2027-03-15T09:02:10Z  lab03-pg  Multi-AZ instance failover started.
2027-03-15T09:03:37Z  lab03-pg  Multi-AZ instance failover completed
```

Đọc: failover mất ~87 giây — khớp khoảng "60–120 giây" của tài liệu. Nếu app báo lỗi lâu hơn nhiều so với con số này → nghi DNS cache hoặc connection pool của app, không phải RDS.

### 12.2. Quy trình khi "app không kết nối được RDS"

Đi từ dưới lên, giống [Network 08](../02-NETWORKING/08-network-troubleshooting-tools.md):

1. **Instance có `available` không?** `describe-db-instances --query "DBInstances[].DBInstanceStatus"`.
2. **DNS:** từ máy app, `getent hosts <endpoint>` → phải ra IP **10.20.11.x/12.x** (private). Ra IP public → instance đang `Public access = Yes`.
3. **Mạng (L4):** từ máy app, `nc -zv <endpoint> 5432` hoặc `timeout 3 bash -c '</dev/tcp/<endpoint>/5432'`. Timeout → SG/route/NACL. Thành công → mạng ổn, chuyển sang bước 4.
4. **Xác thực (L7):** `psql "host=<endpoint> dbname=postgres user=labadmin sslmode=require"`. Lỗi mật khẩu/SSL → đọc thông báo `FATAL:` và `postgresql.log`.

Ghi mỗi lần debug vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Kể 3 việc RDS làm thay bạn và 3 việc bạn **vẫn phải** làm khi dùng RDS.
2. Vì sao DB subnet group bắt buộc có subnet ở 2 AZ ngay cả khi instance là Single-AZ?
3. `Public access = No` có đủ để chặn mọi kết nối không mong muốn không? Còn cần gì?
4. Vì sao rule `5432 từ sg-app` tốt hơn `5432 từ 10.20.0.0/16`?
5. Tính chi phí một tháng của `db.t4g.micro` Multi-AZ + 20 GB gp3 ở Singapore với bảng giá trong bài.
6. Automated backup gồm hai thành phần nào? Thành phần nào cho phép PITR?
7. Khôi phục PITR có ghi đè lên instance đang chạy không? Sau khi khôi phục cần làm thêm 2 việc gì?
8. Multi-AZ DB instance khác read replica ở điểm nào (đồng bộ/bất đồng bộ, đọc được hay không, mục đích)?
9. Failover Multi-AZ hoạt động bằng cơ chế gì? Vì sao ứng dụng Java cần quan tâm đến DNS cache?
10. Tạo RDS bằng CLI mà không ghi `--engine-lifecycle-support` thì sao? Bằng console thì sao?
11. Vì sao không nên chọn PostgreSQL 14 cho lab vào đầu năm 2027?
12. `--skip-final-snapshot` nghĩa là gì? Khi nào được phép dùng?
13. Kết nối với `sslmode=disable` tới RDS PostgreSQL 17 sẽ ra sao? Vì sao?
14. Nêu 2 điều kiện khiến `taskhub` **buộc** phải chuyển database sang RDS (hoặc dịch vụ tương đương).

---

## 14. Bài tập tự làm

**Bài 1 — Tính tiền.** Lập bảng chi phí tháng (Singapore) cho 3 phương án: (a) PostgreSQL trong Docker trên `t3.small` hiện tại; (b) `db.t4g.micro` Single-AZ; (c) `db.t4g.micro` Multi-AZ. Tính cả storage 20 GB và backup giả sử 25 GB snapshot. Số liệu lấy từ trang giá (ghi ngày kiểm tra), không chép từ bài.

**Bài 2 — Thiết kế mạng.** Vẽ (bằng chữ) sơ đồ VPC của bạn với RDS: subnet nào trong DB subnet group, rule inbound/outbound của `taskhub-db-sg`, và chứng minh laptop của bạn **không** kết nối được tới database dù biết endpoint.

**Bài 3 — Runbook khôi phục.** Viết `docs/runbooks/rds-pitr.md` (giả định `taskhub` đã dùng RDS): các bước từ "phát hiện xóa nhầm lúc 14:32 giờ VN" đến "app chạy lại với dữ liệu 14:31". Phải có lệnh CLI đầy đủ (UTC đúng), bước đổi endpoint trong app, bước kiểm tra dữ liệu, và bước dọn instance cũ.

**Bài 4 — Lệnh tạo an toàn.** Viết một script `create-lab-rds.sh` chỉ **in ra** (không chạy) lệnh `create-db-instance` với đủ các tham số an toàn ở mục 8, lấy `PG_VERSION` tự động, sinh mật khẩu ngẫu nhiên bằng `openssl rand`, và **từ chối** chạy nếu thiếu biến `DB_SG` hoặc subnet group chưa tồn tại (kiểm tra bằng lệnh `describe`).

**Bài 5 — Hoàn thiện ADR.** Sau Lab 03, chốt ADR ở Bước 10: thêm số liệu thực tế bạn đo được (thời gian tạo instance, thời gian xóa, chi phí buổi lab trên Billing).

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được ranh giới trách nhiệm AWS/bạn khi dùng RDS bằng ví dụ cụ thể (vá OS, vá PostgreSQL nhỏ/lớn, schema, quyền truy cập).
- [ ] Vẽ được VPC có RDS: subnet group 2 AZ private, SG tham chiếu SG, Public access = No — và giải thích từng lựa chọn.
- [ ] Tự viết được lệnh `create-db-instance` an toàn và giải thích từng tham số, đặc biệt `--engine-lifecycle-support`.
- [ ] Giải thích được PITR (snapshot + log), vì sao tạo instance mới, và hai việc phải làm sau khi khôi phục.
- [ ] Phân biệt được Single-AZ / Multi-AZ instance / read replica, nói được thời gian failover và tác động lên app Java.
- [ ] Trả lời được câu phỏng vấn "Vì sao dự án của bạn không dùng RDS?" bằng số liệu và điều kiện chuyển đổi.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Amazon RDS Free Tier](https://aws.amazon.com/rds/free/) | Free plan: db.t3.micro, db.t4g.micro; MySQL/PostgreSQL/MariaDB | 2026-10-31 |
| [AWS Price List API — AmazonRDS, ap-southeast-1](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/ap-southeast-1/index.json) | Giá db.t4g.micro/db.t3.micro, gp3, backup ở Singapore | 2026-10-31 |
| [Amazon RDS for PostgreSQL pricing](https://aws.amazon.com/rds/postgresql/pricing/) | Trang giá chính thức để kiểm tra lại | 2026-10-31 |
| [RDS — Working with a DB instance in a VPC](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html) | DB subnet group ≥ 2 AZ, Public access, dùng DNS name thay IP | 2026-10-31 |
| [RDS — Introduction to backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html) | Automated backup, snapshot thủ công không tự xóa, dung lượng backup miễn phí 100% | 2026-10-31 |
| [RDS — Backup retention period](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html) | 0–35 ngày, mặc định 7 (console) / 1 (CLI), 0 = tắt | 2026-10-31 |
| [RDS — Restoring a DB instance to a specified time](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html) | PITR tạo instance mới, log tải lên S3 mỗi 5 phút, parameter group mặc định | 2026-10-31 |
| [RDS — Multi-AZ DB instance deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html) | Standby đồng bộ, không phục vụ đọc | 2026-10-31 |
| [RDS — Failing over a Multi-AZ DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.Failover.html) | Failover 60–120 giây, đổi DNS, JVM DNS TTL ≤ 60 giây | 2026-10-31 |
| [RDS — Multi-AZ DB cluster deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/multi-az-db-clusters-concepts.html) | 1 writer + 2 reader, 3 AZ, danh sách instance class | 2026-10-31 |
| [RDS — Extended Support](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/extended-support.html) và [Creating with Extended Support](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/extended-support-creating-db-instance.html) | Phí sau end of standard support; mặc định bật với CLI/API, tắt với console; `--engine-lifecycle-support` | 2026-10-31 |
| [Release calendar for Amazon RDS for PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-release-calendar.html) | Ngày hết hỗ trợ chuẩn của PG 14/16/17/18, các bản 17.x | 2026-10-31 |
| [RDS — Using SSL with a PostgreSQL DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html) | `rds.force_ssl` mặc định 1 từ PostgreSQL 15 | 2026-10-31 |
