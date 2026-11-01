# Lời giải — Bài 08. Elastic Load Balancing và Auto Scaling

> Chỉ mở sau khi đã tự làm. Bài: [08-elb-autoscaling.md](../08-elb-autoscaling.md). Giá: Singapore, kiểm tra 2026-10-31.

## Câu hỏi trong phần thực hành

**Bước 3.** Có — `web1`/`web2` luân phiên, vì nginx mặc định dùng **round robin** cho `upstream`. ALB target group cũng mặc định round robin.

**Bước 4.** Thường không có (hoặc chỉ một vài) request lỗi. Khi `web1` dừng, kết nối tới nó lỗi; `proxy_next_upstream error timeout ...` khiến nginx **thử lại ngay** request đó với `web2`, và sau `max_fails=2` lần lỗi trong `fail_timeout`, nginx tạm loại `web1` 10 giây. Đây là **passive health check**: chỉ phát hiện khi request thật thất bại. ALB dùng **active health check**: tự gửi `GET /health` định kỳ, phát hiện cả khi không có traffic, và có ngưỡng healthy/unhealthy rõ ràng. Lưu ý: ALB **không** tự gửi lại request lỗi sang target khác như `proxy_next_upstream` — trong khoảng 2 × interval trước khi target bị đánh `unhealthy`, một số request có thể nhận 502/504.

**Bước 5.** `web1` vẫn `running` nhưng trả **403** (nginx không có trang index và không bật autoindex) — "máy sống, app chết". `restart: always` **không** giúp gì vì container không thoát. Trên AWS: ASG với health check type **EC2** không thay máy này (EC2 vẫn khỏe). Với **ELB**: target group đánh `unhealthy` (`Target.ResponseCodeMismatch`) → ASG thay máy sau grace period. Trong mô phỏng này, nginx vẫn gửi request tới `web1` vì 403 không nằm trong `proxy_next_upstream` (chỉ có `http_502 http_503`) — tương tự ALB sẽ vẫn gửi traffic nếu health check path của bạn không phát hiện được lỗi.

**Bước 7 — gợi ý thiết kế cho `taskhub`.**

- Target group trỏ tới **nginx cổng 80** (giữ nginx làm reverse proxy trong máy như v0–v2), health check `/actuator/health` (nginx chuyển tiếp), matcher `200`, interval 15 s, healthy 2, unhealthy 2. Phương án khác: bỏ nginx trong máy, TG trỏ thẳng app 8080 — ít thành phần hơn, nhưng mất phần cấu hình nginx đã có.
- Deregistration delay 30–60 s; Spring Boot bật `server.shutdown=graceful` + `spring.lifecycle.timeout-per-shutdown-phase` nhỏ hơn delay; Docker `stop_grace_period` đủ dài để app kịp xử lý `SIGTERM`.
- Grace period lớn hơn thời gian khởi động đo được (ví dụ log `Started TaskhubApplication in 18 seconds` + thời gian kéo image + khởi động Docker → đặt 180 s).
- **Vấn đề database:** mỗi EC2 có một PostgreSQL riêng trong Docker → 2 instance = 2 database khác nhau; người dùng tạo task trên máy A rồi ALB gửi request sau sang máy B → không thấy task. Bắt buộc phải tách database ra một nơi dùng chung (RDS) trước khi scale ngang.

## Câu hỏi kiểm tra kiến thức

1. Listener ↔ `listen 80;` · rule ↔ `location ...` (điều kiện định tuyến) · target group ↔ `upstream` (kèm health check) · target ↔ `server app1:8080;`.
2. Khi cần giao thức không phải HTTP (TCP/UDP, ví dụ database, game, MQTT); khi cần **IP tĩnh** (đối tác whitelist IP, gắn Elastic IP); khi cần độ trễ cực thấp/thông lượng rất lớn ở tầng 4; khi muốn giữ nguyên IP nguồn của client ở tầng mạng.
3. `/` của API có thể trả 404 → mọi target "unhealthy". `/actuator/health` trả **200** khi app và database ổn, **503** khi `DOWN` → ALB đánh target đó `unhealthy` và ngừng gửi traffic tới nó (nếu còn target khác healthy).
4. Khi **mọi** target unhealthy, ALB vẫn gửi traffic tới tất cả. Nguy hiểm: health check cấu hình sai khiến cả nhóm luôn "unhealthy" mà trang vẫn chạy → bạn không phát hiện ra; đến khi một máy hỏng thật, ALB không loại được nó.
5. Tối thiểu **2 AZ** (2 subnet ở 2 AZ khác nhau). Cross-zone: ALB luôn bật ở mức load balancer (tắt được ở mức target group); NLB (và GWLB) mặc định **tắt**.
6. 0,0252 USD/giờ + 2 IP × 0,005 USD/giờ = 0,0352 USD/giờ × 730 ≈ **25,7 USD/tháng**, chưa tính LCU (gần 0 khi không có traffic). Con số chính xác xem trên Billing.
7. `EC2`: chỉ thay khi EC2 báo hỏng (status check fail, instance dừng). `ELB`: thêm kết quả health check của target group. Ví dụ chỉ `ELB` phát hiện: Spring Boot hết kết nối database và trả 503, hoặc nginx chạy nhưng app container đã chết — máy vẫn "running".
8. Console: **300 giây**; CLI/SDK: **0** (tắt). Đặt 0 với Spring Boot cần 30–60 giây khởi động → ALB đánh `unhealthy` trước khi app kịp sẵn sàng → ASG terminate → tạo máy mới → lặp lại vô hạn.
9. Khi target bị hủy đăng ký, ALB ngừng gửi request **mới** nhưng chờ request đang xử lý hoàn tất trong tối đa **300 giây** (mặc định), trạng thái `draining`. Liên quan: sau khi draining (hoặc khi ASG terminate), container nhận `SIGTERM`; app phải xử lý xong request dở dang và đóng kết nối gọn gàng (graceful shutdown). Nếu app đóng kết nối trước khi hết delay, client nhận lỗi 5xx.
10. **Rolling**. ASG 2 máy với `MinHealthyPercentage=90` → phải giữ ít nhất 90% × 2 = 1,8 → làm tròn lên 2 máy healthy, mà `MaxHealthyPercentage=100` không cho tạo thêm máy → không thể thay máy nào. Đặt 50% (thay từng máy), hoặc tăng `MaxHealthyPercentage` (cho phép tạo máy mới trước khi xóa máy cũ — tốn thêm tiền, và có thể vượt quota vCPU).
11. `taskhub` là REST API không giữ session trong RAM; mọi trạng thái nằm trong database → request nào tới máy nào cũng như nhau. Cần sticky session khi app lưu session/giỏ hàng trong bộ nhớ của từng máy (ứng dụng web kiểu cũ) và chưa chuyển session ra nơi dùng chung (Redis, database).
12. Subnet private không có route tới IGW nên không ra Internet được. Hỏng: `apt-get update`/cài gói trong user data; kéo image từ GHCR/Docker Hub; SSM agent không đăng ký (không vào máy được); gửi log/metric tới CloudWatch; gọi API bên ngoài.
13. GHCR nằm trên Internet → instance private **bắt buộc** có NAT (hoặc proxy). ECR là dịch vụ AWS → kéo được qua **VPC endpoint** (interface endpoint cho ECR API/DKR + gateway endpoint cho S3 nơi chứa layer), không cần NAT.
14. Mỗi instance có một PostgreSQL riêng với dữ liệu riêng → dữ liệu không nhất quán giữa các máy (xem gợi ý Bước 7). Ngoài ra ASG terminate máy là **mất volume `pgdata`** của máy đó.

## Bài tập tự làm

**Bài 1 — Script mẫu.**

```bash
#!/bin/bash
# Mô phỏng active health check của ALB: interval 5 s, healthy 2, unhealthy 2.
set -uo pipefail
INTERVAL=5 HEALTHY_T=2 UNHEALTHY_T=2
declare -A ok_streak fail_streak state
targets=(web1 web2)
for t in "${targets[@]}"; do ok_streak[$t]=0; fail_streak[$t]=0; state[$t]=initial; done

cd ~/devops-lab/06-aws/elb-sim
while true; do
  for t in "${targets[@]}"; do
    code=$(docker compose exec -T "$t" wget -q -S -O /dev/null http://localhost/health 2>&1 \
             | awk '/HTTP\//{print $2; exit}')
    if [ "${code:-000}" = "200" ]; then
      ok_streak[$t]=$(( ok_streak[$t] + 1 )); fail_streak[$t]=0
      [ "${ok_streak[$t]}" -ge "$HEALTHY_T" ] && state[$t]=healthy
    else
      fail_streak[$t]=$(( fail_streak[$t] + 1 )); ok_streak[$t]=0
      [ "${fail_streak[$t]}" -ge "$UNHEALTHY_T" ] && state[$t]=unhealthy
    fi
    printf '%s %-5s code=%-3s %s\n' "$(date +%T)" "$t" "${code:-000}" "${state[$t]}"
  done
  sleep "$INTERVAL"
done
```

Điểm chấm: đếm chuỗi **liên tiếp** (thành công reset bộ đếm thất bại và ngược lại); trạng thái chỉ đổi khi đạt ngưỡng; container dừng (lệnh `exec` lỗi) được tính là thất bại. `nginx:alpine` có `wget` của BusyBox; nếu `-S` không in header trong môi trường của bạn, thay bằng cách kiểm tra exit code của `wget -q -O /dev/null`.

**Bài 2 — Chẩn đoán.** User data mất ~90 giây nhưng health check đánh `unhealthy` trước khi app sẵn sàng → ASG (type ELB) thay máy sau grace period quá ngắn (có thể là 0 do tạo bằng CLI). Sửa theo thứ tự: (1) tăng grace period > thời gian khởi động thực tế: `aws autoscaling update-auto-scaling-group --auto-scaling-group-name <asg> --health-check-grace-period 180`; (2) rút ngắn khởi động bằng AMI dựng sẵn (cài sẵn Java/Docker, không `apt-get` lúc boot) hoặc dùng lifecycle hook để chỉ đưa instance vào `InService` khi app đã sẵn sàng. Không nên "sửa" bằng cách đổi sang health check type EC2 — làm vậy chỉ che lỗi.

**Bài 3 — Rolling deploy trên ASG (khung).** CI push `:<sha7>` → tạo LT version mới với user data đặt `TASKHUB_IMAGE_TAG=<sha7>` (hoặc user data đọc tag từ Parameter Store, khi đó chỉ cần cập nhật parameter và refresh) → `start-instance-refresh` với `MinHealthyPercentage=50` (2 máy) hoặc cao hơn khi nhiều máy, `InstanceWarmup` ≥ thời gian khởi động, 🟦 `AutoRollback=true` kèm alarm `HTTPCode_Target_5XX_Count` → kiểm tra `describe-instance-refreshes` và smoke test qua ALB → rollback: `cancel-instance-refresh` + rollback (auto hoặc `rollback-instance-refresh`), hoặc refresh lại với LT version cũ. So với v3: v3 chỉ đổi container trên **một** máy (nhanh, có downtime ngắn của recreate); ASG thay **cả máy** (chậm hơn, không downtime nếu đủ capacity, rollback cũng là thay máy).

**Bài 4.** Không có đáp án duy nhất. Bài tốt nêu: (a) private + NAT: bề mặt tấn công nhỏ hơn (instance không có IP public), chi phí NAT ≈ 0,045 USD/giờ × 2 × 730 ≈ 65 USD/tháng + phí dữ liệu, phức tạp hơn; (b) public + SG chặt + SSM: rẻ, đơn giản, an toàn ở mức chấp nhận được nếu SG chỉ mở cho ALB và không có port quản trị. Startup 3 người giai đoạn đầu thường chọn (b) hoặc một nền tảng managed; khi có yêu cầu tuân thủ/bảo mật cao hơn thì (a). Quan trọng là lập luận có số liệu và nguồn.

**Bài 5 — Ví dụ.**

- **502**: container `taskhub` crash (OOM) giữa lúc xử lý request → target đóng kết nối/trả phản hồi không hợp lệ. Xác nhận: `HTTPCode_ELB_502_Count` tăng, log container (`docker logs`, exit 137), `dmesg` OOM.
- **503**: mọi máy ASG bị thay cùng lúc (instance refresh `MinHealthyPercentage=0`) → target group không có target đăng ký/healthy. Xác nhận: `describe-target-health` rỗng hoặc toàn `draining`/`initial`, `HealthyHostCount=0`.
- **504**: truy vấn PostgreSQL chậm (thiếu index, khóa bảng) khiến request vượt idle timeout 60 giây. Xác nhận: `TargetResponseTime` cao, log truy vấn chậm của PostgreSQL, ALB access log có `target_processing_time` = -1 hoặc rất lớn.
