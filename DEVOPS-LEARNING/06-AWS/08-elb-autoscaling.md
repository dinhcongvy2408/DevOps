# 08. Elastic Load Balancing và Auto Scaling

> ⏱️ ~3,5 giờ · Mức độ: 🟥 Bắt buộc (sticky session, instance refresh nâng cao 🟦) · Kiến thức cần có trước: [Network 07 — Reverse proxy & load balancing](../02-NETWORKING/07-load-balancing-reverse-proxy.md), [03. VPC](03-vpc-networking.md), [04. EC2](04-ec2.md), [CI/CD 05 — Chiến lược triển khai](../05-CICD/05-deployment-strategies-rollback.md)
> Môi trường: `[WSL]` có AWS CLI v2 (profile `taskhub`), `[AWS Console]`. Region `ap-southeast-1`.
> Bài này **không tạo** tài nguyên tính phí. ALB + Auto Scaling group thật được dựng trong [Lab 03](labs/lab-03-alb-asg-rds-short.md) (tuần 14, một buổi rồi xóa).
> Số liệu khi viết (kiểm tra 2026-10-31): giá ELB Singapore từ AWS Price List API (bản công bố 2026-09-11).

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

- Phân biệt **ALB** (Application Load Balancer — tầng 7), **NLB** (Network Load Balancer — tầng 4) và **CLB** (Classic — thế hệ cũ), chọn đúng loại cho một ứng dụng web như `taskhub`.
- Giải thích các khối của ALB: **listener**, **rule**, **target group**, **health check** — và nối chúng với nginx `upstream` bạn đã viết ở Module 02.
- Cấu hình health check cho Spring Boot (`/actuator/health`, success code `200`) và đọc được trạng thái `initial/healthy/unhealthy/draining`.
- Giải thích **cross-zone load balancing** và yêu cầu **ALB phải ở ít nhất 2 AZ**.
- Tính chi phí ALB theo giờ + LCU ở Singapore, và vì sao một ALB "không có traffic" vẫn tốn tiền.
- Dựng được trên giấy **launch template** + **Auto Scaling group** (desired/min/max, health check kiểu ELB, grace period) và giải thích ASG tự thay instance hỏng thế nào.
- Liên hệ **instance refresh** với **rolling deployment** ở [CI/CD 05](../05-CICD/05-deployment-strategies-rollback.md), và **target tracking** với tự động mở rộng.
- Giải thích kiến trúc tham chiếu 2 AZ có NAT, và vì sao instance trong subnet private cần NAT hoặc VPC endpoint để kéo image, cập nhật gói.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

`taskhub` v2 chạy trên **một** EC2. Một máy = một điểm hỏng: máy chết, AZ sự cố, hay đơn giản là bạn deploy (recreate) — người dùng đều thấy lỗi. Load balancer + Auto Scaling là cặp đôi AWS dùng để giải quyết đúng ba vấn đề đó.

| Tình huống thật | Kiến thức trong bài |
|---|---|
| "Một server chết lúc 3 giờ sáng, không ai biết, nhưng người dùng vẫn vào được" | ASG thay instance hỏng, ALB chỉ gửi tới target healthy |
| "Deploy bản mới mà không có downtime" | Instance refresh = rolling, deregistration delay |
| "Black Friday traffic tăng gấp 5" | Target tracking scaling |
| ALB báo `502`/`503`/`504` | Đọc mã lỗi và target health |
| Hóa đơn: "ALB chạy cả tháng mà chẳng ai dùng, tốn 20 USD" | Giá theo giờ + LCU |
| Phỏng vấn: "ALB khác NLB thế nào? Health check của ASG kiểu EC2 khác ELB ra sao?" | Mục 4.1, 4.8 |

Junior DevOps gặp ALB/ASG gần như ở mọi công ty dùng AWS — kể cả khi ứng dụng chạy trên Kubernetes (EKS cũng tạo ALB/NLB qua controller).

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Bạn đã có nền: nginx `upstream`

Ở [Network 07](../02-NETWORKING/07-load-balancing-reverse-proxy.md), bạn đã viết:

```nginx
upstream app { server app1:8080; server app2:8080; }
server { listen 80; location / { proxy_pass http://app; } }
```

ALB là phiên bản **được quản lý, chạy trên nhiều AZ, tự mở rộng** của đúng ý tưởng đó:

| nginx (Module 02) | ALB |
|---|---|
| `listen 80;` | **Listener** HTTP:80 |
| `location /api/ { ... }` | **Listener rule** (điều kiện theo path/host/header) |
| `upstream app { server ...; }` | **Target group** |
| `server app1:8080;` | **Target** đã đăng ký (EC2 instance, IP, Lambda) |
| `max_fails` / passive check | **Health check** chủ động, có ngưỡng |
| Một container nginx — chết là xong | Nhiều **node** ở nhiều AZ, AWS lo thay thế |

### 3.2. Hai khái niệm "sức khỏe" khác nhau

- **Health check của target group** (ALB hỏi): "target này có trả lời đúng HTTP không?" → quyết định **gửi traffic hay không**.
- **Health check của Auto Scaling group** (ASG hỏi): "instance này có cần **thay** không?" → quyết định **giết và tạo máy mới**.

Mặc định ASG chỉ dùng **trạng thái EC2** (máy còn `running`, qua status check). Muốn ASG thay cả máy "còn sống nhưng app chết", phải bật **health check kiểu ELB** cho ASG (mục 4.8).

### 3.3. Từ vựng

| Thuật ngữ | Nghĩa |
|---|---|
| **Load balancer node** | Máy của AWS chạy ALB, một node mỗi AZ bạn bật |
| **Internet-facing / internal** | ALB có IP public (nhận traffic Internet) / chỉ IP private (dùng trong VPC) |
| **Listener** | Cổng + giao thức ALB lắng nghe (HTTP:80, HTTPS:443) |
| **Target group (TG)** | Nhóm đích + cấu hình health check |
| **Launch template (LT)** | "Công thức" tạo EC2: AMI, type, SG, IAM role, user data… có phiên bản |
| **Auto Scaling group (ASG)** | Nhóm EC2 tạo từ LT, giữ số lượng trong khoảng min–max |
| **Desired capacity** | Số instance ASG cố giữ lúc này |
| **Scaling policy** | Quy tắc thay đổi desired (ví dụ giữ CPU trung bình ~50%) |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 ALB, NLB, CLB — chọn loại nào

| | ALB | NLB | CLB |
|---|---|---|---|
| Tầng OSI | 7 (HTTP/HTTPS, gRPC, WebSocket) | 4 (TCP/UDP/TLS) | 4 và 7 (thế hệ trước) |
| Định tuyến theo path/host/header | ✅ | ❌ | Hạn chế |
| Health check | HTTP/HTTPS (xem được mã trả về) | TCP/HTTP/HTTPS | TCP/HTTP |
| IP tĩnh | ❌ (dùng tên DNS) | ✅ (một IP mỗi AZ, gắn được Elastic IP) | ❌ |
| Cross-zone mặc định | **Luôn bật** ở mức load balancer | **Tắt** | Tùy cách tạo |
| Giá Singapore (giờ / đơn vị dung lượng-giờ) | 0,0252 USD / 0,008 USD mỗi LCU | 0,0252 USD / 0,006 USD mỗi NLCU | 0,028 USD + 0,008 USD/GB |
| Dùng cho | Web/API như `taskhub` | Giao thức không phải HTTP, cần IP tĩnh, độ trễ cực thấp | Chỉ gặp ở hệ thống cũ — không tạo mới |

**`taskhub` dùng ALB**: ứng dụng HTTP, health check `/actuator/health`, sau này có thể định tuyến `/api/*` và `/` khác nhau.

### 4.2. 🟥 Listener, rule, target group

```text
Client ──HTTP:80──► Listener HTTP:80
                       │ rule ưu tiên 10: path /api/*  ──► TG "taskhub-api" (port 8080)
                       │ rule ưu tiên 20: host admin.* ──► TG "admin"
                       └ default action               ──► TG "taskhub-web" (port 80)
```

- Mỗi listener có **default action** (bắt buộc) và có thể có thêm **rule** đánh giá theo thứ tự ưu tiên.
- Action phổ biến: `forward` (tới TG), `redirect` (ví dụ HTTP → HTTPS), `fixed-response` (trả về nội dung cố định — hữu ích để báo "bảo trì").
- **Target type**: `instance` (đăng ký EC2 ID — ALB gửi tới IP private của instance) hoặc `ip` (đăng ký IP — dùng cho container/ECS). Lab dùng `instance`.

### 4.3. 🟥 Health check — cấu hình cho Spring Boot

Giá trị mặc định của target group ALB (target type `instance`/`ip`), theo tài liệu:

| Thiết lập | Mặc định | `taskhub` nên đặt | Vì sao |
|---|---|---|---|
| `HealthCheckPath` | `/` | **`/actuator/health`** | `/` của API có thể trả 404; actuator trả 200 khi app **và database** ổn ([tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)) |
| `Matcher` (success codes) | `200` | `200` | Actuator trả **503** khi `DOWN` → đúng là không healthy |
| `HealthCheckIntervalSeconds` | 30 | 10–15 (lab: 10) | Phát hiện nhanh hơn |
| `HealthCheckTimeoutSeconds` | 5 | 5 | |
| `HealthyThresholdCount` | 5 | 2–3 | Mặc định 5 × 30 s = 2,5 phút mới nhận instance mới — chậm |
| `UnhealthyThresholdCount` | 2 | 2 | |

**Trạng thái target** bạn sẽ thấy: `initial` (đang kiểm tra lần đầu) → `healthy`; `unhealthy` kèm **reason code** (`Target.ResponseCodeMismatch`, `Target.Timeout`, `Target.FailedHealthChecks`…); `draining` (đang rút ra); `unused` (chưa đăng ký, AZ chưa bật, instance đã dừng).

⚠️ **Fail open.** Nếu **mọi** target đều unhealthy, ALB **vẫn gửi traffic tới tất cả** (tài liệu gọi là *fails open*). Nghĩa là: health check sai cấu hình (ví dụ sai path) khiến cả nhóm "unhealthy" nhưng trang vẫn chạy — bạn tưởng ổn cho đến khi một instance thật sự hỏng. Luôn kiểm tra `describe-target-health` phải ra `healthy`.

🟨 **Health check đi sâu bao nhiêu?** Actuator mặc định kiểm cả database. Nếu database chậm một chút, **mọi** instance cùng unhealthy cùng lúc. Nhiều team tách *liveness* (app còn sống) và *readiness* (sẵn sàng nhận request) — Spring Boot có `/actuator/health/liveness` và `/actuator/health/readiness`. Bạn sẽ gặp lại hai khái niệm này rõ ràng nhất ở Kubernetes (Module 09).

### 4.4. 🟥 ALB cần ít nhất 2 AZ; cross-zone load balancing

- Theo tài liệu ALB: phải chọn **ít nhất hai subnet ở hai AZ khác nhau**; mỗi subnet nên có CIDR tối thiểu **/27** và **ít nhất 8 IP trống** để ALB mở rộng. Subnet `/24` của chúng ta dư.
- ELB tạo **một node trong mỗi AZ** được bật. Tên DNS của ALB phân giải ra IP của các node (TTL 60 giây).
- **Cross-zone load balancing**: node ở AZ-a có được gửi request tới target ở AZ-b không?
  - Với ALB: **luôn bật** ở mức load balancer; có thể tắt ở mức target group (hiếm khi cần).
  - Với NLB và GWLB: **mặc định tắt**.

Ví dụ của tài liệu: AZ-a có 2 target, AZ-b có 8 target. Cross-zone **bật** → mỗi target nhận 10% traffic. **Tắt** → mỗi target ở AZ-a nhận 25%, ở AZ-b chỉ 6,25% — lệch tải. Đó là lý do ALB bật sẵn.

### 4.5. 🟥 Giá ALB và vì sao nó không "miễn phí khi không dùng"

Giá ALB ở `ap-southeast-1` (AWS Price List API, bản 2026-09-11, kiểm tra 2026-10-31):

| Thành phần | Giá |
|---|---|
| ALB-giờ (hoặc phần lẻ giờ) | **0,0252 USD** |
| LCU-giờ | **0,008 USD** |
| Public IPv4 của các node ALB (internet-facing, 2 AZ = 2 IP) | 0,005 USD/IP/giờ (trang VPC pricing có ví dụ tính IP của ELB) |

**LCU** (Load Balancer Capacity Unit) đo 4 chiều — kết nối mới/giây, kết nối đang mở/phút, byte xử lý, số rule đánh giá (10 rule đầu miễn phí) — và **chỉ tính chiều cao nhất** trong mỗi giờ. Lab vài người dùng gần như luôn dưới 1 LCU.

Một ALB **không có một request nào** vẫn tốn: 0,0252 + 2 × 0,005 ≈ **0,035 USD/giờ ≈ 26 USD/tháng**. Đây là tài nguyên số 1 bị "quên xóa" sau lab.

> **Free plan:** trang ELB pricing vẫn mô tả mức miễn phí kiểu cũ (750 giờ chia giữa CLB và ALB + 15 LCU) và đồng thời ghi tài khoản mới từ 15/7/2025 nhận credit dùng được cho ELB. Với tài khoản của bạn (Free plan, credit), cứ **coi ALB là trừ credit theo giờ** và kiểm tra **Billing → Free Tier / Credits** sau buổi lab.

### 4.6. 🟨 Deregistration delay và sticky session

**Deregistration delay** (connection draining): khi một target bị rút khỏi TG (ASG thu nhỏ, instance refresh, bạn deregister), ALB **ngừng gửi request mới** nhưng chờ request đang xử lý xong — mặc định **300 giây**, trạng thái `draining`. Với API ngắn như `taskhub`, 30–60 giây là đủ và giúp deploy nhanh hơn. Nếu target tự đóng kết nối trước khi hết thời gian này, client nhận lỗi 5xx — liên quan trực tiếp tới **graceful shutdown** của Spring Boot và tín hiệu `SIGTERM` ([Docker 03](../04-DOCKER/03-dockerfile-multistage.md)).

🟦 **Sticky session**: ALB gắn cookie `AWSALB` để một người dùng luôn về cùng target (thời hạn 1 giây – 7 ngày). Chỉ cần khi app giữ **session trong RAM**. `taskhub` là REST API không trạng thái → **không bật**. Thiết kế không trạng thái là điều kiện để ASG thêm/bớt máy thoải mái.

### 4.7. 🟥 Launch template

**Launch template** gom mọi thứ cần để tạo một EC2 (thay cho "launch configuration" cũ):

| Trường | Lab 03 dùng | Ghi chú |
|---|---|---|
| `ImageId` | AMI Ubuntu 24.04 (ID cụ thể, tra từ SSM public parameter) | Xem lưu ý bên dưới |
| `InstanceType` | `t3.micro` | Nằm trong danh sách Free plan |
| `IamInstanceProfile` | `taskhub-ec2-role` | Để vào bằng SSM Session Manager |
| `MetadataOptions` | `HttpTokens=required` | IMDSv2 bắt buộc ([bài 04](04-ec2.md)) |
| `NetworkInterfaces` | `AssociatePublicIpAddress=true`, SG web | Subnet do ASG chọn |
| `UserData` | Script cài nginx (base64) | Chạy một lần lúc boot |

**Phiên bản**: mỗi lần sửa LT tạo **version mới** (1, 2, 3…). ASG trỏ tới một version cụ thể, hoặc `$Latest` / `$Default`. Thay đổi LT **không** tự đổi các instance đang chạy — phải **instance refresh** (mục 4.10).

**Về AMI và SSM parameter:** LT có thể ghi `ImageId: resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id` để luôn lấy AMI mới nhất. Nhưng tài liệu Auto Scaling ghi một giới hạn: ASG dùng LT có SSM parameter thì **không** chạy được instance refresh kiểu *skip matching* — mà console bật *skip matching* **mặc định**. Lab vì vậy tra AMI ID một lần rồi ghi ID cụ thể: tái lập được và tránh giới hạn này.

### 4.8. 🟥 Auto Scaling group

```text
               min=2      desired=2      max=4
ASG "web"  ─── [ i-aaa (1a) ] [ i-bbb (1b) ] ─── đăng ký tự động vào TG
                    │ i-aaa unhealthy (theo ELB health check, sau grace period)
                    ▼
               ASG terminate i-aaa → launch i-ccc (từ launch template) → TG kiểm tra → healthy
```

| Thiết lập | Ý nghĩa | Lab 03 |
|---|---|---|
| `min` / `max` / `desired` | Biên dưới / biên trên / số mục tiêu hiện tại | 2 / 2 / 2 (giữ dưới quota 5 vCPU mặc định của tài khoản mới) |
| `VPCZoneIdentifier` | Danh sách subnet — ASG **chia đều** instance qua các AZ | public-a, public-b |
| `TargetGroupARNs` | Tự đăng ký/hủy đăng ký instance vào TG | TG web |
| `HealthCheckType` | `EC2` (mặc định) hoặc thêm `ELB` | **ELB** |
| `HealthCheckGracePeriod` | Thời gian bỏ qua health check sau khi instance vào `InService` | 120 giây |

**Health check type `EC2` vs `ELB`:**

- `EC2`: ASG chỉ thay instance khi EC2 báo hỏng (status check fail, instance bị dừng/terminate). App chết mà máy còn chạy → ASG **không** biết.
- `ELB`: ASG **thêm** kết quả health check của target group. App trả 503 → TG đánh `unhealthy` → ASG thay máy. Đây là cấu hình nên dùng cho web.

**Grace period** — mặc định theo tài liệu: **300 giây khi tạo bằng console**, **0 khi tạo bằng CLI/SDK** (0 = tắt). Đặt 0 với một app Spring Boot cần 30–60 giây để khởi động là công thức cho vòng lặp "tạo máy → chưa kịp healthy → bị giết → tạo máy". Lab ghi rõ `--health-check-grace-period 120`.

### 4.9. 🟥 Scaling policy — target tracking

**Target tracking** giống bộ điều nhiệt: bạn đặt "giữ CPU trung bình của ASG ở 50%", ASG tự tạo CloudWatch alarm và tăng/giảm desired trong khoảng min–max.

```json
{
  "PredefinedMetricSpecification": { "PredefinedMetricType": "ASGAverageCPUUtilization" },
  "TargetValue": 50.0
}
```

Các metric định sẵn khác: `ASGAverageNetworkIn/Out`, `ALBRequestCountPerTarget` (số request mỗi target — hợp với web hơn CPU). Ngoài ra có **step scaling** và **scheduled scaling** (ví dụ tăng lên 4 máy lúc 8 giờ sáng ngày làm việc).

Lưu ý với instance `t3`: mặc định ở chế độ **unlimited** — chạy CPU cao liên tục có thể phát sinh phí CPU credit vượt mức. Đừng chạy stress test CPU dài trong lab.

### 4.10. 🟥 Instance refresh = rolling deployment trên AWS

Ở [CI/CD 05](../05-CICD/05-deployment-strategies-rollback.md), **rolling** là "thay dần từng phần". Trên ASG, đó là **instance refresh**:

1. Tạo **launch template version mới** (AMI mới, user data mới, image tag mới…).
2. `start-instance-refresh` — ASG thay instance cũ bằng instance mới **theo đợt**, giữ tối thiểu `MinHealthyPercentage` instance healthy.
3. Mỗi instance mới phải qua **warmup** (mặc định lấy *default instance warmup* nếu có, không thì lấy *health check grace period*) trước khi ASG thay tiếp.

Giá trị mặc định (theo tài liệu, khi không có instance maintenance policy): `MinHealthyPercentage` **90%**, `MaxHealthyPercentage` **100%**, auto rollback **tắt**, checkpoint **tắt**. Với ASG chỉ 2 instance, 90% nghĩa là phải giữ cả 2 → refresh **không thể bắt đầu thay** cho đến khi có thêm chỗ; lab đặt `MinHealthyPercentage=50` để thay từng máy một.

🟦 **Auto rollback**: bật thì ASG tự quay về cấu hình cũ nếu refresh thất bại (hoặc CloudWatch alarm bạn chỉ định chuyển sang `ALARM`) — đúng ý tưởng "deploy tự rollback" bạn tự viết bằng `deploy.sh` ở CI/CD 05.

### 4.11. 🟥 Kiến trúc tham chiếu 2 AZ có NAT (lý thuyết)

Kiến trúc "sách giáo khoa" mà phỏng vấn hay hỏi:

```text
Internet ─► IGW ─► ALB (public-a, public-b)
                     │
                     ▼ (SG ALB → SG app)
            EC2 app (private-a, private-b)  ── ra Internet qua ──► NAT Gateway (mỗi AZ một cái, nằm ở public subnet)
                     │
                     ▼ (SG app → SG db)
            RDS Multi-AZ (private-a primary, private-b standby)
```

**Vì sao app trong subnet private cần NAT (hoặc endpoint)?** Subnet private không có route tới IGW. Nhưng instance vẫn cần **gọi ra ngoài**: `apt-get update`, kéo image từ **GHCR** (`ghcr.io` là Internet), gọi API AWS (SSM, CloudWatch, S3). Không có đường ra → user data treo ở `apt-get`, container không pull được image, SSM agent không đăng ký → bạn còn không vào được máy để debug.

| Cách cho instance private ra ngoài | Dùng cho | Chi phí |
|---|---|---|
| **NAT Gateway** (mỗi AZ một cái để không phụ thuộc một AZ) | Mọi đích trên Internet (GHCR, apt, API ngoài) | ≈ 0,045 USD/giờ mỗi NAT + phí xử lý dữ liệu theo GB (xem [VPC pricing](https://aws.amazon.com/vpc/pricing/)) — 2 NAT chạy cả tháng ≈ 65 USD chưa tính dữ liệu |
| **Gateway VPC endpoint** cho S3/DynamoDB | Chỉ S3, DynamoDB | Không tính phí giờ |
| **Interface VPC endpoint** (PrivateLink) cho SSM, ECR, CloudWatch… | Chỉ dịch vụ AWS tương ứng | Tính theo giờ **mỗi endpoint mỗi AZ** + GB |

Với **ECR** (registry của AWS), instance private có thể kéo image chỉ bằng endpoint (ECR + S3 gateway). Với **GHCR** thì bắt buộc phải có đường ra Internet. Đó là một lý do thực tế khiến hệ thống production trên AWS hay dùng ECR.

**Vì sao giáo trình không làm kiến trúc này?** Chi phí NAT vượt xa phần còn lại của dự án. `taskhub` đặt EC2 ở **public subnet** với SG chặt (chỉ 80/443 vào, quản trị qua SSM) — đánh đổi chấp nhận được cho dự án học tập, và Lab 03 cũng đặt instance ở public subnet nhưng SG **chỉ cho ALB vào**. Bạn cần **vẽ và giải thích được** kiến trúc NAT trong phỏng vấn — đó là mục tiêu.

### 4.12. Gặp lại ở đâu

| Kiến thức | Gặp lại |
|---|---|
| ALB + TG + health check `/actuator/health` | [Lab 03](labs/lab-03-alb-asg-rds-short.md); [09. Route 53](09-route53.md) (alias record trỏ tới ALB); [10. CloudWatch](10-cloudwatch.md) (metric `HTTPCode_Target_5XX_Count`, `UnHealthyHostCount`) |
| Launch template, ASG, instance refresh | Terraform (Module 07, 🟨 module ASG); so sánh với Kubernetes Deployment (Module 09) |
| Liveness vs readiness | Kubernetes probes (Module 09) |
| Deregistration delay + graceful shutdown | Kubernetes `terminationGracePeriodSeconds` (Module 09) |
| NAT, VPC endpoint | [11. Kết nối các dịch vụ](11-putting-it-together.md); Module 10 (giảm bề mặt tấn công) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Health check "xanh" nhưng người dùng thấy lỗi

Team đặt health check path `/` cho API Spring Boot. `/` trả 404 → mọi target `unhealthy` → ALB **fail open**, vẫn gửi traffic → mọi thứ "chạy". Một tuần sau một instance hết RAM, trả 502 cho 50% request — ALB không loại nó ra vì cả nhóm vốn đã "unhealthy". Sửa: path `/actuator/health`, kiểm tra `describe-target-health` ra `healthy` là một bước bắt buộc sau mỗi thay đổi.

### Ví dụ 2: ASG giết máy liên tục

ASG tạo bằng CLI, không ghi grace period (mặc định 0), health check type ELB. App cần 50 giây để khởi động; ALB đánh `unhealthy` ở giây 20 → ASG terminate → tạo máy mới → lặp lại. Activity history đầy dòng *"instance failed ELB health checks"*. Sửa: grace period lớn hơn thời gian khởi động thực tế (đo bằng log), hoặc dùng lifecycle hook.

### Ví dụ 3: Deploy rolling trên 2 máy mà vẫn mất dịch vụ

Instance refresh với `MinHealthyPercentage=0` cho nhanh: ASG thay **cả hai** máy cùng lúc → khoảng 1 phút không có target healthy → 503. Bài học: con số `MinHealthyPercentage` chính là "bao nhiêu phần trăm sức chứa bạn chấp nhận mất khi deploy".

---

## 6. Sơ đồ kiến trúc

### 6.1. Lab 03 — tối giản, không NAT

```text
                       Internet
                          │ HTTP :80
                ┌─────────▼──────────┐
                │ ALB "lab03-alb"    │ SG lab03-alb-sg: 80 từ 0.0.0.0/0
                │ node 1a │ node 1b  │ (public-a, public-b)
                └────┬─────────┬─────┘
       listener :80 → TG "lab03-web-tg" (health check /health, 10 s, ngưỡng 2)
                     │         │
   ┌─────────────────▼─┐   ┌───▼───────────────┐
   │ EC2 (public-a)    │   │ EC2 (public-b)    │ SG lab03-web-sg: 80 CHỈ từ lab03-alb-sg
   │ nginx + trang ID  │   │ nginx + trang ID  │ (có IP public chỉ để ra Internet: apt, SSM)
   └─────────┬─────────┘   └─────────┬─────────┘
             └───────── ASG "lab03-web-asg" (min 2, desired 2, max 2, health check ELB) ─┘
                          │ TCP 5432 (SG web → SG db)
                ┌─────────▼──────────┐
                │ RDS "lab03-pg"     │ private-a / private-b (DB subnet group)
                └────────────────────┘
```

### 6.2. Một request đi qua ALB

```text
curl http://lab03-alb-123.ap-southeast-1.elb.amazonaws.com/
  1. DNS → IP của node ALB ở 1a hoặc 1b (TTL 60 s)
  2. Node nhận TCP :80 (SG ALB cho phép)
  3. Listener :80 → default action forward → TG
  4. Chọn target healthy (round robin, cross-zone bật) → mở kết nối tới IP PRIVATE của EC2 :80
     (SG web chỉ cho phép nguồn là SG ALB)
  5. nginx trả trang → ALB thêm header X-Forwarded-For (IP client thật) khi chuyển request
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích |
|---|---|
| `aws elbv2 describe-load-balancers` | Xem ALB/NLB: DNS name, trạng thái, AZ |
| `aws elbv2 describe-target-groups` | Xem TG và cấu hình health check |
| `aws elbv2 describe-target-health --target-group-arn ...` | **Lệnh debug số 1**: target nào healthy, reason code |
| `aws autoscaling describe-auto-scaling-groups` | Desired/min/max, instance và trạng thái |
| `aws autoscaling describe-scaling-activities` | **Lịch sử**: vì sao ASG tạo/xóa máy |
| `aws autoscaling describe-instance-refreshes` | Tiến độ rolling update |
| ⚠️ `aws elbv2 create-load-balancer` / `create-target-group` / `create-listener` | Tạo ALB — **bắt đầu tính tiền** |
| ⚠️ `aws ec2 create-launch-template` | Tạo LT (miễn phí, nhưng phải dọn) |
| ⚠️ `aws autoscaling create-auto-scaling-group` | Tạo ASG — **tạo EC2 tính tiền** |
| ⚠️ `aws autoscaling start-instance-refresh` | Thay toàn bộ instance |
| ⚠️ `aws autoscaling delete-auto-scaling-group --force-delete` | Xóa ASG **và terminate mọi instance** |
| ⚠️ `aws elbv2 delete-load-balancer` | Xóa ALB (kèm listener) |

---

## 8. Giải thích câu lệnh và tham số

### `describe-target-health`

```bash
# [WSL]
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[].[Target.Id,TargetHealth.State,TargetHealth.Reason]" \
  --output table
```

Đầu ra minh họa:

```text
---------------------------------------------------------------
|                    DescribeTargetHealth                     |
+----------------------+------------+-------------------------+
|  i-0a1b2c3d4e5f60001 |  healthy   |  None                   |
|  i-0a1b2c3d4e5f60002 |  unhealthy |  Target.ResponseCodeMismatch |
+----------------------+------------+-------------------------+
```

`Target.ResponseCodeMismatch` = target trả lời nhưng **sai mã** (ví dụ 404 vì sai path, 503 vì app DOWN). `Target.Timeout` = không trả lời kịp (SG chặn, app treo, chưa khởi động xong).

### ⚠️ `create-target-group` — đọc hiểu

```bash
aws elbv2 create-target-group --name lab03-web-tg \
  --protocol HTTP --port 80 --vpc-id "$VPC_ID" --target-type instance \
  --health-check-path /health --health-check-interval-seconds 10 \
  --healthy-threshold-count 2 --unhealthy-threshold-count 2 \
  --matcher HttpCode=200 \
  --tags Key=Project,Value=taskhub Key=Env,Value=lab Key=Lab,Value=lab03
```

| Tham số | Ý nghĩa |
|---|---|
| `--protocol HTTP --port 80` | ALB nói chuyện với target bằng HTTP cổng 80 |
| `--target-type instance` | Đăng ký bằng instance ID (ASG tự làm) |
| `--health-check-path /health` | Trong lab là file tĩnh của nginx; với `taskhub` là `/actuator/health` |
| `--healthy-threshold-count 2` | 2 lần thành công liên tiếp → healthy (nhanh hơn mặc định 5) |
| `--matcher HttpCode=200` | Chỉ 200 mới tính là khỏe |

### ⚠️ `create-auto-scaling-group` — đọc hiểu

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name lab03-web-asg \
  --launch-template "LaunchTemplateName=lab03-web-lt,Version=\$Latest" \
  --min-size 2 --max-size 2 --desired-capacity 2 \
  --vpc-zone-identifier "$PUB_A,$PUB_B" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB --health-check-grace-period 120 \
  --tags "Key=Name,Value=lab03-web,PropagateAtLaunch=true" \
         "Key=Project,Value=taskhub,PropagateAtLaunch=true" \
         "Key=Lab,Value=lab03,PropagateAtLaunch=true"
```

| Tham số | Ý nghĩa |
|---|---|
| `Version=\$Latest` | Dùng version mới nhất của LT. `\$` để bash không hiểu `$Latest` là biến |
| `--vpc-zone-identifier "subnet-a,subnet-b"` | Các subnet (phân cách bằng dấu phẩy) — ASG chia đều qua AZ |
| `--target-group-arns` | ASG tự đăng ký instance mới vào TG |
| `--health-check-type ELB` | Thay máy khi TG đánh unhealthy, không chỉ khi EC2 hỏng |
| `--health-check-grace-period 120` | Mặc định CLI là **0** — luôn ghi rõ |
| `PropagateAtLaunch=true` | Tag được gắn lên mọi instance ASG tạo — để tìm và dọn |

### `describe-scaling-activities`

```bash
aws autoscaling describe-scaling-activities --auto-scaling-group-name lab03-web-asg \
  --max-items 5 --query "Activities[].[StartTime,StatusCode,Description,Cause]" --output text
```

Đầu ra minh họa (rút gọn):

```text
2027-03-20T08:14:02Z  Successful  Launching a new EC2 instance: i-0...03  At 2027-03-20T08:13:51Z an instance was taken out of service in response to an ELB system health check failure.
2027-03-20T08:13:51Z  Successful  Terminating EC2 instance: i-0...02     At 2027-03-20T08:13:51Z an instance was taken out of service in response to an ELB system health check failure.
```

Cột **Cause** là câu trả lời cho "vì sao máy của tôi bị xóa?".

### ⚠️ `put-scaling-policy` (target tracking) — đọc hiểu

```bash
aws autoscaling put-scaling-policy --auto-scaling-group-name lab03-web-asg \
  --policy-name cpu50 --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":50.0}'
```

Lệnh này tự tạo CloudWatch alarm (thấy ở [bài 10](10-cloudwatch.md)). Xóa ASG thì policy và alarm đi kèm cũng bị xóa.

---

## 9. Bài thực hành từng bước

Thực hành bài này **không tốn tiền**: thiết kế trên giấy + mô phỏng ALB/ASG bằng Docker để hiểu cơ chế. ALB/ASG thật: [Lab 03](labs/lab-03-alb-asg-rds-short.md).

### Phần A — Mô phỏng "target group + health check + thay máy" bằng Docker Compose `[WSL]`

Mục tiêu: thấy tận mắt cơ chế mà ALB và ASG tự động hóa — nginx đóng vai ALB (loại backend hỏng), Compose `restart` đóng vai ASG (tạo lại "máy" chết).

**Bước 1.** Tạo thư mục và hai "instance":

```bash
mkdir -p ~/devops-lab/06-aws/elb-sim && cd ~/devops-lab/06-aws/elb-sim
mkdir -p web1 web2
echo "instance web1 (AZ-a)" > web1/index.html; echo ok > web1/health
echo "instance web2 (AZ-b)" > web2/index.html; echo ok > web2/health
```

**Bước 2.** `lb.conf` — nginx làm "ALB" với passive health check:

```nginx
upstream tg {
    server web1:80 max_fails=2 fail_timeout=10s;
    server web2:80 max_fails=2 fail_timeout=10s;
}
server {
    listen 80;
    location / {
        proxy_pass http://tg;
        proxy_next_upstream error timeout http_502 http_503;
        add_header X-Upstream $upstream_addr always;
    }
}
```

**Bước 3.** `compose.yaml`:

```yaml
name: elbsim
services:
  lb:
    image: nginx:1.30-alpine
    ports: ["127.0.0.1:8095:80"]
    volumes: ["./lb.conf:/etc/nginx/conf.d/default.conf:ro"]
    depends_on: [web1, web2]
  web1:
    image: nginx:1.30-alpine
    volumes: ["./web1:/usr/share/nginx/html:ro"]
    restart: always
  web2:
    image: nginx:1.30-alpine
    volumes: ["./web2:/usr/share/nginx/html:ro"]
    restart: always
```

```bash
docker compose up -d
for i in $(seq 1 6); do curl -s localhost:8095/; done
```

❓ Hai "instance" có thay phiên nhau trả lời không? Thuật toán gì? (So với ALB: round robin mặc định.)

**Bước 4.** "Instance hỏng" — dừng hẳn `web1` (giống EC2 bị terminate):

```bash
docker compose stop web1
for i in $(seq 1 6); do curl -s -o /dev/null -w '%{http_code} ' localhost:8095/; done; echo
docker compose start web1      # ASG "tạo máy thay thế"
```

> Nếu sau khi `start` mà `web1` không bao giờ quay lại vòng luân phiên: nginx OSS **phân giải tên `web1` một lần lúc khởi động** và giữ IP đó; container khởi động lại có thể nhận IP khác. Chạy `docker compose restart lb` để nginx phân giải lại. Đây cùng loại vấn đề với "JVM cache DNS khi RDS failover" ở [bài 07](07-rds.md) — và là lý do ALB dùng health check + đăng ký target theo ID chứ không theo tên.

❓ Có request nào lỗi không? nginx loại `web1` ra nhờ cơ chế gì? Khác **health check chủ động** của ALB thế nào? (nginx OSS chỉ có *passive* check: phát hiện khi request thật thất bại; ALB gửi request kiểm tra định kỳ dù không có traffic.)

**Bước 5.** "App chết nhưng máy còn sống" — đây là chỗ khác biệt giữa health check kiểu EC2 và ELB:

Thư mục web được mount `:ro` (container không sửa được), nên ta "làm hỏng app" bằng cách xóa trang chủ **trên host**:

```bash
rm web1/index.html
for i in $(seq 1 6); do curl -s -o /dev/null -w '%{http_code} ' localhost:8095/; done; echo
docker compose ps web1
```

❓ `web1` vẫn `running` (máy "còn sống") nhưng trả mã gì? `restart: always` có cứu được không? Ánh xạ sang AWS: ASG với health check type **EC2** có thay máy này không? Với **ELB** thì sao?

**Bước 6.** Khôi phục và dọn dẹp:

```bash
echo "instance web1 (AZ-a)" > web1/index.html
docker compose down
```

### Phần B — Thiết kế trên giấy `[WSL]`

**Bước 7.** Trong `week14/elb-asg-design.md`, viết cấu hình ALB/TG/LT/ASG cho **`taskhub` thật** (không phải lab):

- Target group: port nào (nginx 80 hay app 8080? — lý do), health check path, interval, ngưỡng.
- Deregistration delay bao nhiêu, gắn với cấu hình graceful shutdown nào của Spring Boot.
- ASG: min/max/desired, grace period (dựa trên thời gian khởi động thực tế bạn đo được ở log `Started TaskhubApplication in ... seconds`).
- **Vấn đề lớn:** PostgreSQL đang chạy trong Docker trên chính EC2. Điều gì xảy ra khi ASG có 2 instance? (Gợi ý: [bài 07 mục 4.10](07-rds.md).)

**Bước 8.** Tính chi phí một tháng (Singapore) cho kiến trúc: ALB + 2 × t3.small + RDS `db.t4g.micro` Single-AZ, có và không có 2 NAT Gateway. So với v2 (1 × t3.small). Ghi nguồn giá và ngày kiểm tra.

---

## 10. Kết quả mong đợi

- Bước 3: phản hồi luân phiên `web1`/`web2`.
- Bước 4: không có (hoặc rất ít) request lỗi khi `web1` dừng; sau khi `start`, `web1` quay lại vòng luân phiên.
- Bước 5: `web1` vẫn `running` nhưng trả **403** hoặc **404** (nginx không có `index.html`); bạn giải thích được vì sao `restart: always` không giúp gì và vì sao ASG cần health check kiểu ELB.
- `week14/elb-asg-design.md` có cấu hình TG/ASG có lý do cho từng con số, phân tích vấn đề database khi scale ra nhiều instance, và bảng chi phí có nguồn.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `describe-target-health` mãi `unhealthy`, reason `Target.Timeout` | SG của instance không cho **SG ALB** vào port của TG; app chưa nghe | Inbound SG web: port 80 từ SG ALB. Vào máy (SSM) `curl -i localhost/health` |
| `unhealthy`, reason `Target.ResponseCodeMismatch` | Sai path health check (404) hoặc app DOWN (503) | Sửa `--health-check-path`; kiểm tra app/database |
| ALB trả **503** | TG không có target nào đã đăng ký/ở AZ được bật | `describe-target-health`, kiểm tra ASG có gắn TG không |
| ALB trả **502** | Target đóng kết nối/trả phản hồi không hợp lệ (app crash giữa chừng, đóng kết nối khi đang draining) | Log app, `HTTPCode_Target_5XX_Count`, graceful shutdown |
| ALB trả **504** | Target không trả lời trong **idle timeout** (mặc định 60 giây) | Truy vấn chậm ở app/DB; tăng timeout chỉ là giải pháp tạm |
| Tạo ALB báo lỗi cần ít nhất 2 subnet/AZ | Chỉ chọn một subnet | Chọn public-a **và** public-b |
| ASG tạo rồi xóa máy liên tục | Grace period 0 (mặc định CLI) hoặc user data lỗi | Đặt grace period; đọc `describe-scaling-activities` và log user data (`/var/log/cloud-init-output.log`) |
| ASG không tạo được máy, scaling activity `Failed` với **`VcpuLimitExceeded`** | Tổng vCPU On-Demand đang chạy + máy mới vượt quota — tài khoản mới mặc định **5 vCPU**; `t3.micro`/`t3.small` đều 2 vCPU, nên máy v2 (`t3.small`) + 2 máy ASG = 6 | Dừng EC2 không dùng (máy v2 trong buổi lab); kiểm tra `aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A`; giữ `max` thấp hoặc xin tăng quota trong **Service Quotas** |
| Instance refresh "đứng yên" | `MinHealthyPercentage` quá cao so với số instance (90% của 2 = phải giữ 2) | Đặt `MinHealthyPercentage=50` cho ASG 2 máy |
| Xóa SG báo `DependencyViolation` sau khi xóa ALB | ENI của ALB chưa kịp xóa | Chờ vài phút rồi thử lại |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Thứ tự điều tra khi ALB trả lỗi

```text
1. Mã lỗi nào? 502 / 503 / 504 → bảng mục 11 thu hẹp nguyên nhân
2. describe-target-health → target nào unhealthy, reason code gì?
3. describe-scaling-activities → ASG vừa thay máy? (Cause)
4. Vào một instance bằng SSM:
     curl -i localhost/health            # app có trả 200 không?
     sudo tail -n 50 /var/log/cloud-init-output.log   # user data có lỗi không?
     sudo journalctl -u nginx --since "10 min ago"
5. Metric CloudWatch của ALB/TG: HealthyHostCount, UnHealthyHostCount,
   HTTPCode_ELB_5XX_Count (lỗi do ALB) vs HTTPCode_Target_5XX_Count (lỗi do app)
```

Phân biệt quan trọng nhất: **`HTTPCode_ELB_5XX`** = ALB tự sinh lỗi (không có target, target timeout) → nhìn hạ tầng; **`HTTPCode_Target_5XX`** = app trả 5xx → nhìn code/database. Đây là phiên bản AWS của bảng "bản mới lỗi hay hạ tầng lỗi" ở [CI/CD 05](../05-CICD/05-deployment-strategies-rollback.md).

### 12.2. Log truy cập của ALB 🟨

ALB có **access log** (tắt mặc định, ghi vào S3) — mỗi dòng có thời gian xử lý ở ALB, ở target, mã trả về của ELB và của target. Bật khi cần điều tra lỗi lặp lại; nhớ đặt lifecycle cho bucket ([bài 05](05-s3.md)) để log không tích tụ.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Ánh xạ listener, rule, target group, target sang các khối tương ứng trong cấu hình nginx `upstream`.
2. Khi nào chọn NLB thay vì ALB? Nêu 2 lý do.
3. Vì sao health check của `taskhub` nên là `/actuator/health` thay vì `/`? Actuator trả mã gì khi database DOWN, và ALB phản ứng thế nào?
4. "Fail open" là gì? Vì sao nó nguy hiểm khi health check bị cấu hình sai?
5. ALB yêu cầu tối thiểu bao nhiêu AZ? Cross-zone load balancing của ALB và NLB mặc định ra sao?
6. Tính chi phí một ALB internet-facing ở 2 AZ để chạy không tải cả tháng (Singapore, bảng giá trong bài).
7. Health check type `EC2` và `ELB` của ASG khác nhau thế nào? Cho ví dụ một sự cố mà chỉ `ELB` phát hiện được.
8. Grace period mặc định khi tạo ASG bằng console và bằng CLI là bao nhiêu? Đặt 0 với Spring Boot gây ra chuyện gì?
9. Deregistration delay là gì, mặc định bao nhiêu? Nó liên quan tới `SIGTERM` và graceful shutdown thế nào?
10. Instance refresh giống chiến lược triển khai nào ở CI/CD 05? Vì sao ASG 2 máy với `MinHealthyPercentage=90` không tiến triển?
11. Vì sao `taskhub` (REST API) không cần sticky session? Khi nào cần?
12. Vì sao instance trong subnet private cần NAT Gateway hoặc VPC endpoint? Kể 3 việc sẽ hỏng nếu không có.
13. Kéo image từ GHCR và từ ECR khác nhau thế nào về yêu cầu mạng đối với instance private?
14. Vì sao `taskhub` hiện tại (PostgreSQL trong Docker trên EC2) **không thể** đặt sau một ASG 2 instance?

---

## 14. Bài tập tự làm

**Bài 1 — Health check chủ động bằng script.** Viết `active-check.sh` chạy trên WSL, mỗi 5 giây `curl` tới `web1` và `web2` của Phần A (qua `docker compose exec` hoặc publish thêm port), đếm số lần thành công/thất bại liên tiếp và in trạng thái `healthy/unhealthy` theo đúng logic `HealthyThresholdCount=2`, `UnhealthyThresholdCount=2`. Đây chính là việc ALB làm.

**Bài 2 — Đọc tình huống.** Cho đoạn output `describe-scaling-activities` sau (minh họa): 6 dòng *Launching/Terminating* trong 10 phút, Cause đều là *"ELB system health check failure"*, user data cài một ứng dụng Java mất ~90 giây. Viết chẩn đoán và 2 cách sửa (theo thứ tự ưu tiên), kèm lệnh CLI.

**Bài 3 — Thiết kế rolling deploy cho `taskhub` trên ASG.** Mô tả từng bước: CI push image `:<sha7>` → tạo LT version mới (user data kéo đúng tag) → instance refresh (tham số nào, giá trị nào) → kiểm tra → rollback nếu lỗi (bằng gì?). So sánh với cách v3 deploy (SSM chạy `deploy.sh` trên một EC2).

**Bài 4 — Kiến trúc NAT vs không NAT.** Vẽ hai sơ đồ (chữ) cho `taskhub` production: (a) app ở private subnet + 2 NAT; (b) app ở public subnet + SG chặt + SSM. Lập bảng so sánh bảo mật, chi phí (có nguồn), độ phức tạp. Bạn chọn gì cho một startup 3 người? Vì sao?

**Bài 5 — Đọc mã lỗi.** Với mỗi mã 502, 503, 504 do ALB trả, viết một kịch bản cụ thể với `taskhub` gây ra nó và metric/lệnh để xác nhận.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ được luồng request Internet → ALB (2 AZ) → TG → EC2, có SG ở từng bước, và ánh xạ được sang nginx `upstream`.
- [ ] Cấu hình được health check cho Spring Boot và giải thích từng con số (path, matcher, interval, ngưỡng); hiểu "fail open".
- [ ] Giải thích được sự khác nhau giữa health check của TG và của ASG (EC2 vs ELB), cùng vai trò của grace period.
- [ ] Liên hệ được instance refresh với rolling deployment, và chọn được `MinHealthyPercentage` hợp lý.
- [ ] Tính được chi phí ALB (giờ + LCU + IPv4) và kiến trúc có NAT, có nguồn giá.
- [ ] Giải thích được vì sao instance private cần NAT/endpoint, và vì sao `taskhub` hiện chưa scale ngang được (database cục bộ).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Elastic Load Balancing pricing](https://aws.amazon.com/elasticloadbalancing/pricing/) | LCU (4 chiều, tính chiều cao nhất), mức miễn phí và credit cho tài khoản mới | 2026-10-31 |
| [AWS Price List API — AWSELB, ap-southeast-1](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-southeast-1/index.json) | Giá ALB/NLB/CLB ở Singapore (bản công bố 2026-09-11) | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Public IPv4 0,005 USD/giờ, kể cả IP của ELB; NAT Gateway | 2026-10-31 |
| [ALB — Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html) | Tối thiểu 2 AZ, subnet /27 + 8 IP trống, cross-zone luôn bật, idle timeout 60 s | 2026-10-31 |
| [ALB — Health checks for target groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/target-group-health-checks.html) | Giá trị mặc định health check, trạng thái target, reason code, fail open | 2026-10-31 |
| [ALB — Edit target group attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html) | Deregistration delay 300 s, round robin, sticky session `AWSALB` (1 s – 7 ngày) | 2026-10-31 |
| [How Elastic Load Balancing works](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html) | Node mỗi AZ, ví dụ cross-zone 10%/25%/6,25%, mặc định NLB/GWLB/CLB, DNS TTL 60 s | 2026-10-31 |
| [EC2 Auto Scaling — Health checks](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-health-checks.html) | Nguồn health check, thay instance unhealthy | 2026-10-31 |
| [EC2 Auto Scaling — Health check grace period](https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-check-grace-period.html) | 300 s (console), 0 (CLI/SDK) | 2026-10-31 |
| [EC2 Auto Scaling — Instance refresh](https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html) và [default values](https://docs.aws.amazon.com/autoscaling/ec2/userguide/understand-instance-refresh-default-values.html) | Min 90% / Max 100%, auto rollback, skip matching | 2026-10-31 |
| [EC2 Auto Scaling — SSM parameters in launch templates](https://docs.aws.amazon.com/autoscaling/ec2/userguide/using-systems-manager-parameters.html) | `resolve:ssm:`; giới hạn với instance refresh skip matching | 2026-10-31 |
| [Ubuntu on AWS — Find Ubuntu images](https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images/) | SSM public parameter của AMI Ubuntu, owner ID Canonical 099720109477 | 2026-10-31 |
