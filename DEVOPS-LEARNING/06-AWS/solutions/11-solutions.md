# Lời giải — Bài 11: Ghép các dịch vụ thành hệ thống thật

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Số liệu giá lấy từ bảng ở bài 11 (Singapore, kiểm tra 2026-10-31).

Quay lại bài: [11-putting-it-together.md](../11-putting-it-together.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Sáu lớp.**
Mạng (VPC, subnet, route table, IGW, SG) · Danh tính (IAM user, instance role, deploy role OIDC) · Tính toán (EC2 + Docker Compose) · Dữ liệu (PostgreSQL + EBS, Parameter Store, S3) · Quan sát (CloudWatch metrics/logs/alarm, SNS, CloudTrail) · Phân phối (GitHub Actions, GHCR, SSM Run Command).

**2. Data plane vs control plane.**
Data plane: đường traffic người dùng. Control plane: đường quản trị/deploy (API AWS, GitHub Actions, SSM). Ví dụ chỉ ảnh hưởng control plane: GitHub Actions sập, GHCR sập, phiên `aws login` hết hạn, SSM agent mất kết nối — không deploy được nhưng app vẫn phục vụ.

**3. Luồng request (≥ 8 chặng).**
DNS (nếu có) → Internet tới public IP → IGW dịch 1:1 sang private IP → route table subnet public → NACL → security group (cổng 80) → ENI/kernel, Docker DNAT tới container nginx → nginx `proxy_pass` tới `taskhub:8080` qua DNS Docker → Spring Boot JDBC tới `postgres:5432` → PostgreSQL đọc từ volume trên EBS. Mỗi chặng kèm cấu hình như bảng 4.2.

**4. SG stateful, NACL stateless.**
SG ghi nhớ kết nối: phản hồi của kết nối đã được phép vào thì tự được ra. NACL đánh giá từng gói độc lập: nếu sửa NACL, phải cho phép cả chiều ra tới dải cổng tạm của client.

**5. Không cổng 22.**
SSM agent trên EC2 **chủ động** mở kết nối HTTPS ra dịch vụ SSM (qua IGW, vì instance có public IP). Session Manager và Run Command đi qua kênh đó — không cần cổng vào nào. Quyền dựa trên IAM, mọi phiên được ghi lại (CloudTrail).

**6. Chuỗi tin cậy.**
GitHub job (environment `production`) → JWT OIDC → STS `AssumeRoleWithWebIdentity` (trust policy kiểm tra `aud`, `sub`) → credential tạm thời của `taskhub-github-deploy` → `ssm:SendCommand` → SSM agent chạy `deploy.sh` bằng root → instance role đọc Parameter Store. Mắt xích mạnh nhất: SSM → EC2 (root trên máy). Giới hạn bằng: policy chỉ cho document `AWS-RunShellScript` và instance có tag `Project=taskhub`; trust policy chỉ cho `sub` của environment `production`; environment có người duyệt và chỉ cho nhánh `main`.

**7. Trust policy kiểm tra gì; thiếu `sub`.**
`aud = sts.amazonaws.com` và `sub = repo:<user>/taskhub:environment:production` (cùng issuer là OIDC provider đã đăng ký). Chỉ kiểm tra `aud`: **mọi** workflow của **mọi** repo trên GitHub lấy được token có `aud` đó → bất kỳ ai cũng assume được role deploy của bạn → chạy lệnh root trên EC2.

**8. Khoanh vùng `AccessDenied`.**
Đọc ARN trong thông báo: `assumed-role/taskhub-github-deploy/...` → mắt xích GitHub → AWS hoặc policy deploy; `assumed-role/taskhub-ec2-role/...` → mắt xích EC2 → dịch vụ (Parameter Store, Logs). Lỗi ngay ở bước `configure-aws-credentials` ("Not authorized to perform sts:AssumeRoleWithWebIdentity") → trust policy/OIDC.

**9. Dữ liệu sống sót.**
Sống qua: tạo lại container, reboot, stop/start, simplified auto recovery. Mất: terminate instance (root volume mặc định bị xóa); không truy cập được khi AZ sự cố. Chỉ một bản dữ liệu → cần backup (v5).

**10. Khoảng mù và nơi lấp.**
RAM, dung lượng đĩa, log nginx/postgres, ứng dụng có trả lời không giữa các lần deploy (kiểm tra từ bên ngoài), độ trễ request. Lấp: Module 08 (v5) — node-exporter + Prometheus (RAM/đĩa), Loki + Alloy (log mọi container), alert theo ứng dụng, giám sát blackbox; một phần có thể lấp sớm bằng CloudWatch agent hoặc metric filter.

**11. GitHub Actions sập 2 giờ.**
Người dùng không bị ảnh hưởng — đó là control plane. Chỉ không deploy/rollback tự động được; vẫn rollback tay qua SSM nếu cần.

**12. Chi phí 24/7.**
≈ 24,87 USD/tháng: `t3.small` 19,27 + IPv4 3,65 + EBS 1,92 + S3 0,03. EC2 chiếm phần lớn (~77%).

**13. Đóng tài khoản trước 6 tháng.**
Free plan kết thúc khi **hết credit hoặc hết 6 tháng, tùy điều nào đến trước**. Chỉ có 100 USD credit, 24/7 tiêu ~25 USD/tháng → hết credit sau khoảng 4 tháng → tài khoản đóng, mất truy cập tài nguyên (còn 90 ngày để nâng cấp lên Paid plan).

**14. Chi phí ẩn.**
Elastic IP idle; log group "Never expire"; NAT Gateway quên xóa; hosted zone thử nghiệm; snapshot/AMI cũ; `t3` unlimited chạy tải cao; ALB/RDS của lab không xóa; dữ liệu ra Internet vượt 100 GB; tài nguyên tạo nhầm ở region khác.

**15. Gấp 100 lần tải + chịu mất một AZ.**
ALB + Auto Scaling Group trải 2 AZ (app phải stateless, session không lưu trong máy); RDS Multi-AZ (hoặc ít nhất RDS có backup tự động); app và DB vào private subnet, chỉ ALB ở public; đường ra Internet cho instance private qua NAT Gateway mỗi AZ hoặc VPC endpoint; hạ tầng bằng Terraform để dựng lại được; giám sát và alert theo ứng dụng. Tốn thêm: ALB theo giờ + LCU, nhiều instance, RDS Multi-AZ (gấp đôi phần database), NAT theo giờ + dữ liệu mỗi AZ, công vận hành.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Runbook "không vào được taskhub"

```text
B1. DNS/IP:  dig +short <tên-miền>  (nếu có)  vs  aws ec2 describe-instances ... PublicIpAddress
             Khác nhau → IP đã đổi sau stop/start → cập nhật record / APP_URL. Giống → B2.
B2. Mạng:    curl -sv -m 5 http://<ip>/ 
             Timeout → aws ec2 describe-security-groups (còn cổng 80?), route table (còn 0.0.0.0/0 → igw?),
                       NACL có bị sửa? CloudTrail: ai đổi gì gần đây? → sửa, xong.
             Có phản hồi (kể cả lỗi) → mạng ổn → B3.
B3. nginx:   Connection refused → nginx không nghe:
             [EC2] docker compose ps; docker compose logs --tail 50 nginx → sửa cấu hình/khởi động lại.
             502/504 → nginx sống, upstream lỗi → B4.
B4. App:     [EC2] docker compose ps taskhub (unhealthy? restarting?); aws logs tail /taskhub/dev/app --since 30m
             OOM/exit 137 → RAM (free -m, docker stats); lỗi khởi động → đọc "Caused by" cuối → B5 nếu lỗi DB.
B5. DB:      curl -s localhost/actuator/health (DB DOWN?); docker compose logs --tail 50 postgres;
             df -h (đĩa đầy?) → giải phóng đĩa / khởi động lại / restore (v5).
Sau cùng:    ghi nhật ký debug + cập nhật docs/failure-analysis.md.
```

Điểm chấm: đi từ ngoài vào trong; mỗi bước có lệnh cụ thể và tiêu chí rẽ nhánh; có bước kiểm tra "IP đổi" và CloudTrail; kết thúc bằng ghi nhận.

### Bài 2 — Lấp một khoảng mù rẻ nhất

| Cách | Chi phí | Ưu | Nhược |
|---|---|---|---|
| Health check Route 53 tới `/actuator/health` + alarm | Theo trang giá (có thể miễn phí với endpoint AWS — kiểm tra lại) | Kiểm tra từ nhiều nơi trên thế giới, đúng đường người dùng | Cần tên miền/IP công khai ổn định; IP đổi phải cập nhật |
| Metric filter đếm `ERROR` + alarm | Trong 10 metric/10 alarm miễn phí | Có ngay, không cần thêm thành phần | Không phát hiện được "app im lặng chết" (không có log thì không có lỗi để đếm) |
| GitHub Actions `schedule` 15 phút gọi `/actuator/health` | Miễn phí (repo public) | Kiểm tra từ bên ngoài, tự gửi email khi workflow đỏ | Lịch không đảm bảo đúng giờ (có thể trễ khi GitHub tải cao); workflow lịch bị tắt sau 60 ngày repo không hoạt động; dùng control plane để giám sát data plane |

Câu trả lời đạt: chọn một cách, nêu đúng nhược điểm chính, và hiểu rằng "kiểm tra từ bên ngoài" (blackbox) bắt được nhiều loại lỗi nhất.

### Bài 3 — Tính lại chi phí (24/7, 730 giờ)

| Phương án | Tính | USD/tháng | Đánh đổi |
|---|---|---|---|
| Gốc (`t3.small`) | 19,27 + 3,65 + 1,92 + 0,03 | ≈ 24,87 | — |
| (a) `t3.micro` | 0,0132 × 730 = 9,64; + 3,65 + 1,92 + 0,03 | ≈ 15,24 | 1 GiB RAM cho JVM + PostgreSQL + nginx + Docker: dễ bị OOM, phải siết heap (`-XX:MaxRAMPercentage`), `shared_buffers`; baseline CPU chỉ 10%/vCPU |
| (b) Elastic IP, stop 2/3 thời gian | Instance 243 giờ × 0,0264 = 6,42; EIP tính **đủ 730 giờ** (in-use + idle) = 3,65; EBS 1,92; S3 0,03 | ≈ 12,02 | So với không dùng EIP (IPv4 chỉ tính 243 giờ = 1,22 → tổng ≈ 9,59): EIP đắt hơn ≈ 2,43 USD/tháng để đổi lấy IP cố định |
| (c) Thêm ALB | 24,87 + (giờ ALB × 730) + LCU | Tra giá ELB Singapore, ghi ngày | Có HTTPS bằng ACM miễn phí, health check, sẵn sàng cho ASG; nhưng thêm một khoản cố định theo giờ chạy 24/7 dù không có traffic. Đạt khi bạn ghi được giá đã tra, ngày tra, và so sánh nó với chi phí `t3.small` |

### Bài 4 — v3 cho 2 AZ (trên giấy)

Các điểm phải có:

- **Public subnet a/b:** ALB (và NAT Gateway nếu chọn NAT, mỗi AZ một cái để không phụ thuộc chéo AZ).
- **Private subnet a/b:** instance của ASG (tối thiểu 2, mỗi AZ một), RDS Multi-AZ (subnet group gồm private-a, private-b).
- **SG chuỗi:** ALB SG mở 80/443 từ Internet; app SG chỉ nhận từ ALB SG; RDS SG chỉ nhận 5432 từ app SG.
- **Đường ra Internet của instance private:** cần cho SSM (agent), kéo image từ GHCR, cập nhật OS. NAT Gateway (đơn giản, tốn tiền theo giờ + dữ liệu) hoặc VPC interface endpoint cho SSM (mỗi endpoint cũng tính theo giờ) — nhưng GHCR nằm **ngoài AWS** nên endpoint không giúp được → vẫn cần NAT, hoặc chuyển image sang **ECR** (có endpoint).
- **Thay đổi ứng dụng:** stateless (không session trong RAM, không lưu file local — file upload lên S3); Flyway migration chạy **một lần** khi có nhiều instance (Flyway có khóa trong bảng lịch sử, nhưng nên chạy như một bước riêng trước khi rolling update); health check ALB dùng `/actuator/health`; migration tương thích ngược để rolling update an toàn ([Module 05 bài 05](../../05-CICD/05-deployment-strategies-rollback.md)).

### Bài 5 — Kiểm tra trust policy

Giả sử điều kiện là `StringEquals` cho `aud = sts.amazonaws.com` và `sub = repo:<user>/taskhub:environment:production`.

| Tình huống token | `sub` trong token | Kết quả | Vì sao |
|---|---|---|---|
| Job trên nhánh `main`, **không** khai báo environment | `repo:<user>/taskhub:ref:refs/heads/main` | ❌ Từ chối | `sub` không khớp chuỗi environment |
| Job trong repo khác (`attacker/taskhub`) có `environment: production` | `repo:attacker/taskhub:environment:production` | ❌ Từ chối | Khác repo |
| Workflow `pull_request` | `repo:<user>/taskhub:pull_request` | ❌ Từ chối | Không phải environment `production` |
| Job có `environment: production` chạy từ nhánh `feat/x` | `repo:<user>/taskhub:environment:production` | ✅ **STS chấp nhận** | `sub` theo environment không chứa tên nhánh |

Dòng cuối là điểm quan trọng: khi dùng `sub` theo environment, **thứ chặn nhánh lạ là luật "deployment branches" của environment** (chỉ `main`) và người duyệt — cấu hình ở [Module 05 bài 04](../../05-CICD/04-secrets-environments.md). Thiếu luật đó, ai có quyền push nhánh vào repo có thể deploy.

### Bài 6 — ADR thứ ba

Chấm như bước 7 của bài: có bối cảnh, ít nhất 2 lựa chọn, quyết định có **số liệu** (chi phí/tháng, thời gian), hệ quả tiêu cực trung thực, và việc cần làm thêm (ví dụ ADR-0006: "thêm backup S3 + diễn tập restore ở v5; xem lại khi cần Multi-AZ").
