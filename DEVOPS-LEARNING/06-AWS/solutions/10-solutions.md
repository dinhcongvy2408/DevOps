# Lời giải — Bài 10: CloudWatch

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; account ID `111122223333` là ID ví dụ của AWS.

Quay lại bài: [10-cloudwatch.md](../10-cloudwatch.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)
- [Phần C — Câu hỏi ❓ trong bài thực hành](#phần-c--câu-hỏi--trong-bài-thực-hành)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Namespace/dimension/statistic/period; sai InstanceId.**
Namespace là nhóm chứa metric (`AWS/EC2`); dimension là cặp tên/giá trị thuộc danh tính metric (`InstanceId=i-...`); statistic là cách gộp điểm trong một period (`Average`, `Maximum`…); period là độ dài khoảng gộp (giây). Dimension là một phần danh tính → sai `InstanceId` = theo dõi một metric **không tồn tại** → không bao giờ có dữ liệu → `INSUFFICIENT_DATA`.

**2. Không có RAM/đĩa mặc định.**
Metric mặc định do hypervisor đo từ bên ngoài máy ảo; hypervisor không thấy bộ nhớ "đã dùng" theo nghĩa của Linux hay filesystem bên trong. Cần CloudWatch agent chạy trong máy đẩy lên dưới dạng custom metric: 0,30 USD/metric/tháng tại Singapore sau 10 metric miễn phí.

**3. Basic vs detailed.**
Basic: status check 1 phút, metric khác 5 phút, miễn phí. Detailed: 1 phút, tính phí theo từng metric như custom metric. Với basic, alarm CPU phải dùng period ≥ 300 giây.

**4. Baseline t3.small; chi phí unlimited.**
Baseline 20% mỗi vCPU (24 credit/giờ, 2 vCPU). Ở chế độ unlimited (mặc định của T3), nếu CPU trung bình 24 giờ vượt baseline và credit vay (surplus) không trả được, phần vay bị tính thêm theo vCPU-giờ. Surplus credit cũng bị tính khi instance stop/terminate hoặc chuyển sang standard.

**5. Group/stream/event; tên stream.**
Event là một dòng log + thời gian; stream là chuỗi event từ một nguồn; group nhóm các stream dùng chung retention, quyền, tag. Driver `awslogs` mặc định đặt tên stream = **container ID**.

**6. Retention mặc định.**
Lưu vô thời hạn ("Never expire"). Lưu trữ tính theo GB-tháng và cộng dồn mãi → hóa đơn tăng dần mà không ai để ý.

**7. `awslogs-create-group: false`.**
Tự tạo group bằng CLI cho phép đặt **retention 7 ngày và tag** ngay từ đầu; group do driver tạo sẽ "Never expire". Không cần cấp thêm `logs:CreateLogGroup` cho instance role → quyền hẹp hơn.

**8. blocking vs non-blocking.**
Blocking (mặc định): ghi log bị chặn khi driver không gửi kịp → ứng dụng có thể chậm/treo. Non-blocking: log vào bộ đệm; đầy thì bỏ log mới, ứng dụng vẫn chạy. Taskhub ưu tiên phục vụ người dùng hơn vài dòng log, nên chọn non-blocking (kèm bộ đệm 4 MB).

**9. Ai gửi log.**
Docker daemon (process trên host), không phải container. Credential: instance role `taskhub-ec2-role`, lấy qua instance metadata (IMDSv2).

**10. Thiếu quyền ghi log lúc deploy.**
Log driver không khởi tạo/gửi được → container mới có thể **không start**; deploy thất bại (và `deploy.sh` rollback về tag trước nếu có cơ chế đó). Thông báo lỗi chứa `AccessDeniedException ... logs:CreateLogStream`/`PutLogEvents`.

**11. Ba trạng thái; notBreaching.**
`OK`, `ALARM`, `INSUFFICIENT_DATA`. Instance stop có chủ đích → không có điểm dữ liệu → với `notBreaching`, thiếu dữ liệu được coi là bình thường → không báo động giả mỗi lần bạn tắt máy khi không học.

**12. Thử đường ống cảnh báo.**
`aws cloudwatch set-alarm-state --state-value ALARM --state-reason ...`: action chạy thật (email đến), trạng thái tự trở lại ở lần đánh giá kế tiếp. Không phải gây sự cố.

**13. Simplified automatic recovery.**
Xử lý lỗi **system status check** (phần cứng/phần mềm của host AWS), bật mặc định trên instance được hỗ trợ, không tốn thêm phí. Giữ: instance ID, IP private/public/Elastic IP, metadata, EBS, AZ. Mất: dữ liệu trong RAM, uptime về 0. **Không** chạy khi chỉ instance status check lỗi.

**14. CloudWatch vs CloudTrail.**
CloudWatch: hệ thống chạy thế nào (CPU, log ứng dụng, alarm). CloudTrail: ai gọi API AWS nào, khi nào, từ đâu. Ví dụ cần cả hai: alarm cho thấy taskhub không phục vụ từ 14:03 (CloudWatch); CloudTrail cho thấy `RevokeSecurityGroupIngress` trên `taskhub-web-sg` lúc 14:02 do một user thực hiện.

**15. Logs Insights tính tiền.**
Theo GB dữ liệu **được quét** (0,007 USD/GB tại Singapore, dùng chung 5 GB miễn phí). Giảm: chỉ chọn log group cần thiết; thu hẹp khoảng thời gian; hủy truy vấn trước khi rời trang; tránh dashboard tự làm mới truy vấn liên tục.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Metric filter + alarm theo số lỗi

```bash
export AWS_PROFILE=taskhub
aws logs put-metric-filter --log-group-name /taskhub/dev/app \
  --filter-name taskhub-error-count \
  --filter-pattern ERROR \
  --metric-transformations metricName=TaskhubErrorCount,metricNamespace=Taskhub,metricValue=1,defaultValue=0

TOPIC_ARN=$(aws sns list-topics --query "Topics[?ends_with(TopicArn, ':taskhub-alerts')].TopicArn" --output text)
aws cloudwatch put-metric-alarm --alarm-name taskhub-errors-high \
  --namespace Taskhub --metric-name TaskhubErrorCount \
  --statistic Sum --period 300 --evaluation-periods 1 --datapoints-to-alarm 1 \
  --threshold 5 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN"
```

- `Sum` vì mỗi dòng khớp đóng góp 1 → tổng = số lỗi trong 5 phút.
- `defaultValue=0`: phát 0 khi không có dòng khớp → biểu đồ liền mạch.
- Hạn mức: metric `TaskhubErrorCount` là **custom metric** (tính vào 10 metric miễn phí); alarm thứ ba tính vào 10 alarm metric miễn phí.
- Lưu ý: một stack trace Java nhiều dòng — chỉ dòng đầu có chữ `ERROR`, các dòng `at ...` không khớp → đếm "số sự kiện lỗi", không phải số dòng.

### Bài 2 — Dashboard

Đạt khi dashboard có đủ 6 widget yêu cầu, trục thời gian thống nhất, và widget Logs Insights dùng truy vấn:

```text
fields @timestamp | filter @message like /ERROR/ | stats count(*) as errors by bin(5m)
```

Lưu ý chi phí: mỗi lần mở/làm mới dashboard, widget Logs Insights chạy lại truy vấn (tính GB quét) → đặt khoảng thời gian mặc định ngắn (3 giờ) và không bật tự làm mới dày.

### Bài 3 — 🟨 CloudWatch agent

- **Quyền:** gắn managed policy `CloudWatchAgentServerPolicy` vào `taskhub-ec2-role` (hoặc thêm `cloudwatch:PutMetricData` có điều kiện namespace `CWAgent` vào `taskhub-ec2-app` — chặt hơn).
- **Cấu hình tối thiểu** (đối chiếu cú pháp với tài liệu agent khi làm):

  ```json
  {
    "metrics": {
      "namespace": "CWAgent",
      "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
      "metrics_collected": {
        "disk": { "measurement": ["used_percent"], "resources": ["/"] },
        "mem":  { "measurement": ["mem_used_percent"] }
      }
    }
  }
  ```

- **Số metric:** `disk_used_percent` cho `/` (1 metric — mỗi tổ hợp dimension là một metric riêng) + `mem_used_percent` (1) = 2. Cộng metric filter bài 1 = 3 custom metric → vẫn trong 10 miễn phí (khi không bật detailed monitoring).
- **Alarm:** `CWAgent` `disk_used_percent` với **đúng toàn bộ dimension** agent gửi (thường gồm `InstanceId`, `path`, `device`, `fstype`) — thiếu một dimension là alarm `INSUFFICIENT_DATA`. Dùng `aws cloudwatch list-metrics --namespace CWAgent` để lấy chính xác.
- Bài học: agent là thêm một phần mềm phải cài, cấu hình, cập nhật — đúng loại việc Ansible (v4) và node-exporter (v5) giải quyết có hệ thống hơn.

### Bài 4 — 🟨 Alarm recover

```bash
aws cloudwatch put-metric-alarm --alarm-name taskhub-recover \
  --namespace AWS/EC2 --metric-name StatusCheckFailed_System \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Maximum --period 60 --evaluation-periods 2 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:automate:ap-southeast-1:ec2:recover "$TOPIC_ARN"
```

Không đặt recover cho `StatusCheckFailed_Instance`: lỗi instance check nằm **trong** hệ điều hành của bạn (kernel, cấu hình, hết RAM); chuyển sang host khác không sửa được. Hành động phù hợp hơn là báo người xử lý (SNS) hoặc reboot.

### Bài 5 — Điều tra bằng CloudTrail

```bash
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=StopInstances \
  --max-results 3 --query 'Events[].[EventTime,Username,CloudTrailEvent]' --output text
```

`CloudTrailEvent` là chuỗi JSON chứa `sourceIPAddress`, `userAgent`, `requestParameters`. Public IP tự gán **có đổi** sau stop/start → phải cập nhật biến `APP_URL` của GitHub (v3) — nếu không, smoke test của lần deploy sau gọi sai địa chỉ và báo đỏ dù deploy thành công.

### Bài 6 — ADR mini: blocking hay non-blocking

Mẫu đạt yêu cầu:

> **Bối cảnh:** taskhub ghi log qua driver `awslogs`. Mạng từ EC2 tới CloudWatch có thể chập chờn. **Lựa chọn:** (1) blocking — không mất log, nhưng ứng dụng có thể treo khi không gửi được; (2) non-blocking + bộ đệm 4 MB — ứng dụng không bị ảnh hưởng, có thể mất log khi bộ đệm đầy. **Quyết định:** non-blocking, vì taskhub phục vụ người dùng quan trọng hơn sự đầy đủ của log debug, và không có yêu cầu kiểm toán. **Hệ quả:** có thể mất log đúng lúc sự cố mạng — chính lúc cần log nhất; phát hiện bằng khoảng trống thời gian trong log group và lỗi trong `journalctl -u docker`. Xem lại khi có yêu cầu lưu vết bắt buộc.

---

## Phần C — Câu hỏi ❓ trong bài thực hành

- **Bước 2 — vì sao không cần `logs:CreateLogGroup`:** log group được tạo trước bằng CLI và driver đặt `awslogs-create-group: false`, nên daemon chỉ tạo **stream** và ghi event.
- **Bước 6 — stream mới hay cũ khi deploy:** stream **mới**, vì tên stream mặc định là container ID và deploy tạo container mới. Log của nhiều phiên bản nằm ở nhiều stream trong cùng group; Logs Insights truy vấn cả group nên vẫn xem liền mạch.
- **Bước 9 — credit đã tiêu:** 2 vCPU × 100% × 15 phút = 30 credit tiêu; trong 15 phút instance tích được 24 × 0,25 = 6 credit → `CPUCreditBalance` giảm khoảng **24** (giá trị đo thực tế lệch một chút vì metric 5 phút và CPU không đúng tròn 100%). Nếu balance trước đó < 24, phần thiếu thành surplus credit.
