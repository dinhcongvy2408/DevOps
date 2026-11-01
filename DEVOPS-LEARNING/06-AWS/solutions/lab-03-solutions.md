# Lời giải — Lab 03. ALB + Auto Scaling + RDS

> Chỉ mở sau khi đã tự làm. Lab: [lab-03-alb-asg-rds-short.md](../labs/lab-03-alb-asg-rds-short.md). Thời gian và số lỗi phụ thuộc buổi lab của bạn — dưới đây là giải thích cơ chế và khoảng giá trị hợp lý, không phải "con số đúng".

## Câu hỏi trong các bước

**Bước 2 — `--source-group`.** Chỉ ENI mang `lab03-alb-sg` (các node ALB) được vào port 80 của máy web; không cần biết IP của ALB (IP node ALB có thể đổi khi ALB mở rộng). Tương tự `lab03-db-sg` chỉ nhận từ `lab03-web-sg`.

**Bước 6 — 503.** Listener forward tới target group chưa có target nào → ALB không có đích để gửi → tự trả 503.

## Thí nghiệm

**Thí nghiệm 1 — Máy chết đột ngột.**

- Terminal 2 thường thấy vài dòng lỗi (`502`, `504` hoặc `000` khi `curl -m 2` timeout) trong khoảng 10–30 giây. Lý do: instance bị terminate thẳng qua EC2 API → ALB chưa biết, vẫn gửi request tới nó cho đến khi health check thất bại 2 lần liên tiếp (2 × 10 s), hoặc đến khi instance chuyển trạng thái và target thành `unused`.
- ASG phát hiện qua **health check EC2** (instance không còn ở trạng thái `running`) — xảy ra trước cả health check ELB. ASG terminate bản ghi và launch máy mới. Trong `describe-scaling-activities`, Cause có nội dung kiểu "an instance was taken out of service in response to an EC2 instance status check failure" hoặc nói instance đã bị terminate (chữ chính xác có thể khác).
- Thời gian từ terminate đến khi có lại 2 target `healthy`: thường 3–6 phút (phát hiện + boot + `apt-get` trong user data + 2 health check). Phần lớn là thời gian **user data** — lý do production hay dùng AMI dựng sẵn.

**Thí nghiệm 2 — Rút máy qua ASG.** Ít hoặc không có lỗi. `terminate-instance-in-auto-scaling-group` khiến ASG **hủy đăng ký** target khỏi target group trước (target chuyển `draining`), ALB ngừng gửi request mới, chờ deregistration delay (30 s) cho request đang dở, rồi ASG mới terminate. Đây là cách mọi thao tác có kế hoạch (scale in, instance refresh) nên diễn ra.

**Thí nghiệm 3 — App hỏng, máy sống.**

- ALB phát hiện trước: sau ~20 giây (2 lần × 10 s) target → `unhealthy`, reason `Target.ResponseCodeMismatch` (nginx trả 404 cho `/health`). ALB ngừng gửi traffic tới máy đó — terminal 2 chỉ còn một instance ID.
- ASG phản ứng sau: vì health check type là **ELB** và máy đã qua grace period, ASG đánh dấu unhealthy, terminate và tạo máy mới. Cause: "...in response to an ELB system health check failure."
- Nếu type là **EC2**: ASG không thay máy (EC2 vẫn khỏe). Máy đó vẫn chạy, trang chủ vẫn trả 200 nếu truy cập trực tiếp, nhưng ALB **không gửi traffic** tới nó vì health check của target group thất bại → bạn trả tiền cho một máy không phục vụ ai, sức chứa giảm một nửa, và không có gì tự sửa.

**Thí nghiệm 4 — RDS.**

- Từ máy web: `getent hosts` ra IP `10.20.11.x` hoặc `10.20.12.x`; TCP 5432 OK; `psql` chạy (có thể cảnh báo client 16 / server 17); `rds.force_ssl` = `1`; `sslmode=disable` bị từ chối với lỗi `no pg_hba.conf entry ... no encryption`.
- Từ laptop: tên DNS **vẫn phân giải** (DNS public của RDS trả về IP private của instance không public) ra `10.20.x.x`, nhưng không kết nối được: (1) IP private không có đường đi từ Internet/laptop vào VPC; (2) dù có đường đi, `lab03-db-sg` chỉ cho `lab03-web-sg`.

**Thí nghiệm 5.** `curl` tới IP public của máy web → timeout. Máy có IP public để **đi ra** (apt, SSM), nhưng SG không có rule inbound nào cho Internet — chỉ cho SG ALB. "Có IP public" ≠ "mở ra Internet"; SG mới là thứ quyết định.

**Thí nghiệm 6 — Instance refresh.** Chiến lược **rolling**. Có một khoảng thời gian cả `v1` và `v2` cùng phục vụ (sau khi máy v2 đầu tiên healthy, trước khi máy v1 cuối cùng bị thay). Với `taskhub`, điều đó đòi hỏi schema database **tương thích với cả hai phiên bản** — tức migration phải theo mẫu expand/contract ([CI/CD 05](../../05-CICD/05-deployment-strategies-rollback.md)): phiên bản mới không được xóa/đổi tên cột mà phiên bản cũ còn dùng.

## Câu hỏi sau lab

1. Thí nghiệm 1: ALB không được báo trước, vẫn gửi traffic tới máy đang chết cho đến khi health check phát hiện → có lỗi. Thí nghiệm 2: ASG hủy đăng ký trước, ALB rút target bằng **deregistration delay** (request mới không tới, request dở được hoàn tất) → gần như không lỗi.
2. ALB phát hiện trước (health check mỗi 10 s, ngưỡng 2) và **ngừng gửi traffic**; ASG phản ứng sau (dựa vào kết quả health check ELB) và **thay máy**. Hai cơ chế bổ sung nhau: ALB bảo vệ người dùng ngay, ASG khôi phục sức chứa.
3. 503 vì target group chưa có target. 504 nghĩa là ALB đã gửi request tới target nhưng target không trả lời trong idle timeout (60 s mặc định) → nghi app/database chậm hoặc treo, không phải thiếu target.
4. Thứ tự đi ngược chiều phụ thuộc: xóa thứ đang **được dùng** sau thứ **đang dùng nó**. Xóa launch template trước ASG: API từ chối vì ASG còn tham chiếu LT (và nếu xóa được thì ASG không còn công thức để tạo máy, rơi vào trạng thái lỗi). Tệ hơn: nếu bạn xóa instance trước khi xóa ASG, ASG sẽ **tạo lại** máy mới.
5. Với `taskhub`: target group trỏ nginx:80 (hoặc app:8080), health check `/actuator/health`; user data cài Docker + Compose, lấy file compose (clone repo), lấy `TASKHUB_IMAGE_TAG` (từ Parameter Store hoặc truyền qua LT version), lấy mật khẩu DB từ Parameter Store SecureString `/taskhub/dev/postgres-password` bằng instance role; `SPRING_DATASOURCE_URL=jdbc:postgresql://<rds-endpoint>:5432/taskhub` (bỏ service `postgres` khỏi compose vì database chuyển sang RDS); thêm `sslmode=require` vào URL nếu cần.
6. Nếu RDS mất 10–15 phút để tạo và vài phút để xóa, việc `terraform destroy`/`apply` toàn bộ mỗi buổi học sẽ tốn thêm ~20 phút chờ mỗi buổi — chấp nhận được cho lab ngắn, nhưng là lý do dự án chính giữ PostgreSQL trong Docker (dựng cùng EC2 trong vài phút). Ở Module 07 bạn sẽ cân nhắc: tách RDS thành stack riêng (giữ lại) hoặc chấp nhận chờ.

## Bài viết so sánh — tiêu chí chấm

- Mọi con số có nguồn: giá có ngày kiểm tra; thời gian phục hồi, thời gian dựng lấy từ `week14/lab03.md` của bạn.
- Phân biệt rõ **máy chết** (ASG xử lý) và **AZ sự cố** (v2: mất dịch vụ; lab: ALB + ASG ở 2 AZ tiếp tục phục vụ — nhưng RDS Single-AZ trong lab vẫn là điểm hỏng đơn nếu nó nằm đúng AZ sự cố).
- Kết luận có điều kiện chuyển đổi cụ thể (ví dụ: "chuyển khi cần > 1 instance app hoặc khi dữ liệu thật cần RPO ≤ 5 phút"), không chỉ "ALB + ASG + RDS tốt hơn".
