# 10. CloudWatch — metrics, logs, alarm cho taskhub

> ⏱️ ~3,5 giờ · Mức độ: 🟥 Bắt buộc (metrics, logs, retention, alarm, SNS) · 🟨 Nên biết (CloudWatch agent, metric filter, dashboard, recover action) · 🟦 Nâng cao (log class, metric math)
> Kiến thức cần có trước: [02. IAM](02-iam.md), [04. EC2](04-ec2.md), [06. AWS CLI](06-aws-cli.md), [Linux 07 — Log & troubleshooting](../01-LINUX/07-logs-monitoring-troubleshooting.md), [Docker 08 — Xử lý sự cố container](../04-DOCKER/08-container-troubleshooting.md). Đã có EC2 `taskhub-app` của [v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) đang chạy
> Môi trường: `[WSL]` AWS CLI v2 (`export AWS_PROFILE=taskhub`, region `ap-southeast-1`) · `[EC2]` qua SSM Session Manager · `[AWS Console]`
> 💰 **Chi phí:** lab nằm trong mức miễn phí của CloudWatch (5 GB log, 10 alarm metric, 1.000 email SNS/tháng). Rủi ro duy nhất: chạy thử tải CPU quá lâu trên `t3.small` (chế độ unlimited) — mục 9, bước 9 giới hạn 15 phút, chi phí tối đa vài cent. Giá kiểm tra ngày 2026-10-31.

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

- Giải thích **metric** (chỉ số) trong CloudWatch: namespace, tên, **dimension**, statistic, period; biết EC2 gửi gì **mặc định** và vì sao **RAM, dung lượng đĩa không có sẵn**.
- Phân biệt **basic monitoring** (5 phút, miễn phí) và **detailed monitoring** (1 phút, có phí).
- Đưa log của container `taskhub` lên **CloudWatch Logs** bằng Docker log driver `awslogs`, đặt **retention** (thời gian lưu) để không bị tính tiền vô hạn.
- Viết truy vấn **Logs Insights** cơ bản để tìm dòng `ERROR`.
- Tạo **alarm** (cảnh báo) cho CPU và **status check**, gửi email qua **SNS** (Simple Notification Service), và **thử alarm** mà không cần gây sự cố thật.
- Hiểu **CPU credit** của `t3` và vì sao tải CPU kéo dài có thể **tốn thêm tiền**.
- Phân biệt **CloudWatch** (hệ thống đang chạy thế nào) với **CloudTrail** (ai đã gọi API nào).

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

"Hệ thống chạy được" chưa đủ. Bạn phải **biết khi nào nó không chạy** — tốt nhất là **trước** người dùng.

| Tình huống thật | Kiến thức trong bài |
|---|---|
| 3 giờ sáng server treo, sáng ra khách hàng báo | Alarm status check + SNS |
| "Hôm qua lúc 14h có lỗi gì?" — nhưng container đã bị tạo lại, `docker logs` mất sạch | Log tập trung ngoài server (CloudWatch Logs) |
| Hóa đơn CloudWatch tăng dần mỗi tháng không rõ lý do | Retention mặc định **không bao giờ hết hạn** |
| "RAM server còn bao nhiêu?" — không có metric nào | Giới hạn của metric mặc định, CloudWatch agent |
| "Ai đã stop instance lúc 2 giờ chiều?" | CloudTrail, không phải CloudWatch |
| Phỏng vấn: "Bạn giám sát hệ thống thế nào? Alarm nào bạn đặt và vì sao?" | Toàn bộ bài |

Bài này là **giám sát cơ bản bằng dịch vụ có sẵn của AWS** cho v3. Module 08 (v5) sẽ thay phần lớn bằng **Prometheus + Grafana + Loki + Alloy** — mạnh hơn và không phụ thuộc AWS. Hiểu CloudWatch trước giúp bạn so sánh được hai cách.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Ba loại tín hiệu

| Tín hiệu | Là gì | Ví dụ | Trong bài này |
|---|---|---|---|
| **Metric** | Con số theo thời gian | CPU 35% lúc 10:05 | CloudWatch Metrics |
| **Log** | Dòng văn bản mô tả sự kiện | `ERROR ... Connection refused` | CloudWatch Logs |
| **Trace** | Đường đi của một request qua nhiều dịch vụ | API → DB mất 120 ms | Không học ở đây (Module 08) |

Metric trả lời "**có vấn đề không, lớn cỡ nào**". Log trả lời "**vấn đề là gì**". Alarm biến metric thành **hành động** (gửi email, khởi động lại máy).

### 3.2. Hypervisor nhìn thấy gì

EC2 là máy ảo. **Hypervisor** (phần mềm của AWS chạy máy ảo) thấy được CPU máy ảo dùng bao nhiêu, bao nhiêu byte mạng ra vào — nên AWS gửi được các metric này **mà không cần cài gì** trong máy.

Nhưng hypervisor **không** biết bên trong hệ điều hành: RAM "đã dùng" theo nghĩa của Linux, filesystem `/` còn bao nhiêu phần trăm, process nào đang chạy. Muốn có các số này, phải có **phần mềm chạy trong máy** đẩy lên — **CloudWatch agent** (mục 4.3). Đây là câu hỏi phỏng vấn rất hay gặp.

### 3.3. CloudWatch là dịch vụ theo region

Metric, log group, alarm đều nằm trong **một region**. Tạo alarm ở `us-east-1` cho instance ở `ap-southeast-1` sẽ không bao giờ có dữ liệu. Luôn kiểm tra `AWS_REGION`/profile.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Metric: namespace, dimension, statistic, period

Theo tài liệu CloudWatch:

| Khái niệm | Nghĩa | Ví dụ |
|---|---|---|
| **Namespace** | "Thư mục" chứa metric, tách metric của các dịch vụ | `AWS/EC2`, `AWS/EBS`, `CWAgent` |
| **Metric name** | Tên chỉ số | `CPUUtilization` |
| **Dimension** | Cặp tên/giá trị — **một phần danh tính** của metric | `InstanceId=i-0abc...` |
| **Statistic** | Cách gộp các điểm dữ liệu trong một period | `Average`, `Maximum`, `Minimum`, `Sum`, `SampleCount`, percentile `p95` |
| **Period** | Độ dài một khoảng gộp, tính bằng giây | `300` (5 phút) |

Hai metric cùng tên nhưng **khác dimension** là **hai metric khác nhau**. Alarm sai `InstanceId` sẽ nằm mãi ở trạng thái thiếu dữ liệu.

**Metric được giữ bao lâu** (tài liệu CloudWatch): điểm 1 phút giữ 15 ngày, điểm 5 phút giữ 63 ngày, điểm 1 giờ giữ 455 ngày (15 tháng). Dữ liệu chi tiết được gộp dần thành độ phân giải thô hơn. Metric **không xóa được** — chỉ tự hết hạn sau 15 tháng không có dữ liệu mới.

### 4.2. 🟥 EC2 gửi gì mặc định

| Metric (`AWS/EC2`) | Ý nghĩa | Ghi chú |
|---|---|---|
| `CPUUtilization` | % CPU **của cả instance** | Metric chính cho alarm tải |
| `NetworkIn` / `NetworkOut` | Byte mạng vào/ra | Phát hiện traffic bất thường |
| `StatusCheckFailed_System` | Lỗi **hạ tầng AWS** (host vật lý, mạng, nguồn điện) | Không phải lỗi của bạn |
| `StatusCheckFailed_Instance` | Lỗi **trong máy ảo** (kernel panic, hết RAM tới mức treo, cấu hình mạng OS sai) | Lỗi của bạn |
| `StatusCheckFailed` | 1 nếu **một trong** các status check lỗi | Alarm "server chết" |
| `CPUCreditBalance`, `CPUSurplusCreditBalance`, `CPUSurplusCreditsCharged` | Credit CPU của dòng burstable (`t3`) | Mục 4.4 |

**Basic vs detailed monitoring** (tài liệu EC2):

| | Basic (mặc định) | Detailed |
|---|---|---|
| Chu kỳ | Status check: **1 phút**. Metric khác: **5 phút** | 1 phút |
| Chi phí | **Miễn phí** | Tính theo **từng metric** EC2 gửi (như custom metric), dùng chung 10 metric miễn phí/tháng |
| Hệ quả cho alarm | Period tối thiểu 300 giây với CPU | Period 60 giây |

Với `taskhub`, **basic là đủ**. Alarm CPU với period 300 giây × 2 lần đánh giá = phát hiện trong khoảng 10–15 phút. Chấp nhận được với một dự án học tập.

### 4.3. 🟨 RAM và ổ đĩa — CloudWatch agent

Muốn alarm "ổ đĩa còn dưới 15%" (rất đáng có, vì `pgdata` và image Docker cũ có thể làm đầy đĩa 20 GiB) phải cài **CloudWatch agent** trong EC2. Agent đọc số liệu từ Linux và đẩy lên namespace `CWAgent` dưới dạng **custom metric** — **0,30 USD/metric/tháng** tại Singapore sau khi hết 10 metric miễn phí (giá kiểm tra 2026-10-31).

Dự án **chưa cài agent ở v3** (giữ đơn giản và miễn phí). Đây là một **khoảng mù đã biết** — [bài 11](11-putting-it-together.md) liệt kê nó, và Module 08 giải quyết bằng `node-exporter` + Prometheus. Bài tập 3 (mục 14) cho bạn thử agent ở mức 🟨.

### 4.4. 🟥 CPU credit của t3 — liên quan trực tiếp tới tiền

`t3.small` là dòng **burstable** (bùng nổ): theo bảng credit của AWS, nó có 2 vCPU nhưng **baseline** (mức nền) chỉ **20% mỗi vCPU**, tích **24 credit/giờ**. Một credit = 1 vCPU chạy 100% trong 1 phút.

- Dùng dưới 20% → tích credit (tối đa 576).
- Dùng trên 20% → tiêu credit đã tích.
- `t3` khởi chạy ở chế độ **unlimited** (mặc định): hết credit vẫn chạy nhanh bằng **surplus credit** (credit vay). Nếu **trung bình 24 giờ** vượt baseline, phần vay không trả được bị **tính thêm tiền** theo vCPU-giờ (bảng ví dụ của AWS ở us-east-1: 0,05 USD/vCPU-giờ).

Hệ quả cho bạn:

- Spring Boot khởi động (vài chục giây CPU cao) là bình thường, credit lo được.
- Một tiến trình **kẹt vòng lặp 100% CPU cả ngày** vừa làm app chậm, vừa **tốn thêm tiền** → đáng có alarm CPU.
- Metric `CPUSurplusCreditBalance` > 0 kéo dài là dấu hiệu bạn đang vay credit.

### 4.5. 🟥 CloudWatch Logs: log group, log stream, retention

| Khái niệm | Nghĩa | taskhub |
|---|---|---|
| **Log event** | Một dòng log + thời gian | `2027-01-20T03:12:45Z INFO ... Started TaskhubApplication` |
| **Log stream** | Chuỗi event **từ một nguồn** | Một container (driver `awslogs` mặc định đặt tên stream = **container ID**) |
| **Log group** | Nhóm stream dùng chung retention, quyền, tag | `/taskhub/dev/app` |

> ⚠️ **Bẫy chi phí lớn nhất của CloudWatch Logs:** theo tài liệu, **mặc định log được lưu vô thời hạn** ("Never expire"). Lưu trữ tính **0,03 USD/GB-tháng** tại Singapore, cộng dồn mãi. Luôn đặt retention ngay khi tạo log group. Dự án dùng **7 ngày** (log để debug sự cố gần đây; lưu lâu là việc của hệ thống log ở Module 08).

Lưu ý thêm từ tài liệu: log hết hạn **không bị xóa ngay**, có thể mất tới 72 giờ — nhưng đã được đánh dấu xóa thì **không còn tính tiền** lưu trữ. Log group **không đổi tên được**.

### 4.6. 🟥 Đưa log container lên CloudWatch: driver `awslogs`

Ở [Docker 08](../04-DOCKER/08-container-troubleshooting.md) bạn biết: container ghi ra stdout/stderr, **Docker daemon** nhận và chuyển cho **log driver** (mặc định `json-file`, lưu file trên máy). Đổi driver sang **`awslogs`** → daemon đẩy thẳng lên CloudWatch Logs.

Thêm vào service `taskhub` trong `/opt/taskhub/compose.yaml` trên EC2:

```yaml
services:
  taskhub:
    # ... image, environment, depends_on, healthcheck giữ nguyên ...
    logging:
      driver: awslogs
      options:
        awslogs-region: ap-southeast-1
        awslogs-group: /taskhub/dev/app
        mode: non-blocking
        max-buffer-size: 4m
```

| Tùy chọn | Ý nghĩa (theo tài liệu Docker) |
|---|---|
| `awslogs-region` | Region của CloudWatch. Bỏ trống trên EC2 thì dùng region của instance — ghi rõ vẫn tốt hơn |
| `awslogs-group` | **Bắt buộc**. Log group đích |
| `awslogs-stream` | Không đặt → dùng **container ID**. Container bị tạo lại (deploy) → stream mới |
| `awslogs-create-group` | Mặc định `false`. Dự án **giữ `false`** và tự tạo group bằng CLI kèm retention 7 ngày. Nếu để driver tự tạo, group sinh ra với retention "Never expire" (bẫy 4.5) và role cần thêm quyền `logs:CreateLogGroup` |
| `mode` | `blocking` (**mặc định**) hoặc `non-blocking` — xem dưới |
| `max-buffer-size` | Bộ đệm cho chế độ `non-blocking` (mặc định 1 MB) |

**`blocking` hay `non-blocking` — một quyết định DevOps thật sự:**

- `blocking` (mặc định): khi CloudWatch chậm/không tới được, lệnh **ghi log của ứng dụng bị chặn** → ứng dụng có thể **treo** chỉ vì không gửi được log.
- `non-blocking`: log vào bộ đệm trong bộ nhớ. Theo tài liệu Docker, **bộ đệm đầy thì log mới bị bỏ** — ứng dụng vẫn chạy.

Với `taskhub`, **ứng dụng phục vụ người dùng quan trọng hơn vài dòng log** → chọn `non-blocking`. Hệ thống cần lưu vết đầy đủ (kế toán, kiểm toán) có thể chọn ngược lại. Biết giải thích đánh đổi này là điểm cộng lớn khi phỏng vấn.

**Quyền IAM — ai gửi log?** Không phải container, mà là **Docker daemon** (process trên host). Daemon lấy credential tạm thời của **instance role** `taskhub-ec2-role` qua instance metadata (IMDSv2). Policy `taskhub-ec2-app` của role (xem [bài 02](02-iam.md), [bài 04](04-ec2.md)) cần:

```json
{
  "Sid": "WriteTaskhubLogs",
  "Effect": "Allow",
  "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
  "Resource": "arn:aws:logs:ap-southeast-1:111122223333:log-group:/taskhub/dev/*:*"
}
```

Tài liệu Docker ví dụ bằng `"Resource": "*"` — dự án **thu hẹp** về đúng các log group `/taskhub/dev/*` (nguyên tắc quyền tối thiểu).

**`docker logs` còn dùng được không?** Có, nhờ **dual logging** của Docker Engine: daemon giữ một bản cache cục bộ (mặc định 5 file × 20 MB mỗi container). Tài liệu Docker cũng nói rõ giới hạn: khi gặp sự cố mạng tới đích log, **bản cache không được ghi** — nên đừng coi nó là bản sao đầy đủ.

> ⚠️ **Hậu quả ít ai nghĩ tới:** nếu log driver không khởi tạo được (log group chưa tồn tại, role thiếu quyền), **container không start được**. Một thay đổi IAM tưởng vô hại có thể làm lần deploy sau thất bại. Bài 11 đưa điều này vào bảng phân tích sự cố.

### 4.7. 🟥 Logs Insights — truy vấn log

**CloudWatch Logs Insights** là ngôn ngữ truy vấn log, các lệnh nối bằng `|`:

```text
fields @timestamp, @logStream, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

| Thành phần | Ý nghĩa |
|---|---|
| `@timestamp`, `@message`, `@logStream` | Trường **tự phát hiện** (bắt đầu bằng `@`) |
| `filter ... like /ERROR/` | Lọc bằng biểu thức chính quy |
| `stats count(*) by bin(5m)` | Đếm theo khoảng 5 phút — vẽ "lỗi tăng lúc nào" |
| `parse` | Tách trường từ chuỗi |

**Tính tiền theo GB dữ liệu được quét**: 0,007 USD/GB tại Singapore, dùng chung hạn mức miễn phí 5 GB (ingest + lưu trữ + quét). Tài liệu khuyên: chọn đúng log group, **thu hẹp khoảng thời gian**, và hủy truy vấn trước khi đóng trang.

🟨 **Metric filter**: biến số dòng khớp mẫu (ví dụ `ERROR`) thành **metric** → đặt alarm "hơn 5 lỗi trong 5 phút". Metric này là custom metric (dùng chung 10 metric miễn phí). Bài tập 1.

### 4.8. 🟥 Alarm

Một **metric alarm** theo dõi **một metric** (hoặc biểu thức), so với **ngưỡng** qua một số **period**, rồi thực hiện **action**.

| Thành phần | Ví dụ cho alarm CPU taskhub |
|---|---|
| Metric + dimension | `AWS/EC2` `CPUUtilization`, `InstanceId=i-0abc...` |
| Statistic + period | `Average`, `300` giây (basic monitoring) |
| Ngưỡng + so sánh | `GreaterThanThreshold` `80` |
| Evaluation periods / datapoints to alarm | `2` / `2` → "2 trong 2 period liên tiếp" (≈ 10 phút) |
| Treat missing data | Cách xử lý khi không có điểm dữ liệu (xem dưới) |
| Action | Gửi tới SNS topic `taskhub-alerts` khi vào `ALARM` (và khi về `OK`) |

**Ba trạng thái:**

| Trạng thái | Nghĩa |
|---|---|
| `OK` | Metric trong ngưỡng |
| `ALARM` | Vượt ngưỡng đủ số period |
| `INSUFFICIENT_DATA` | Chưa đủ dữ liệu: alarm mới tạo, instance đang stop, **dimension sai**, sai region |

Alarm chỉ chạy action khi **đổi trạng thái** (không gửi email liên tục khi đang `ALARM`).

**Treat missing data** — khi thiếu điểm dữ liệu thì coi là gì: `missing` (mặc định), `notBreaching` (coi như ổn), `breaching` (coi như vi phạm), `ignore` (giữ trạng thái cũ). Với alarm status check của một server **hay được stop khi không học**, `notBreaching` tránh alarm "kêu" vô nghĩa khi instance đang tắt có chủ đích.

**Giá:** 10 alarm metric (độ phân giải chuẩn) đầu tiên miễn phí; sau đó 0,10 USD/alarm metric/tháng tại Singapore.

**Thử alarm không cần gây sự cố:** `aws cloudwatch set-alarm-state` đặt tạm alarm sang trạng thái bất kỳ → action chạy thật (email đến), và tài liệu ghi rõ trạng thái này chỉ kéo dài tới lần đánh giá kế tiếp. Đây là cách kiểm tra "đường ống cảnh báo" mà không làm hỏng gì.

### 4.9. 🟥 SNS — gửi email cảnh báo

**SNS** (Simple Notification Service) theo mô hình publish/subscribe: alarm **publish** vào **topic** `taskhub-alerts`, các **subscription** (email, SMS, HTTP, Lambda…) nhận bản sao.

- Subscription email ở trạng thái **`PendingConfirmation`** cho tới khi bạn bấm link xác nhận trong email. Chưa xác nhận → không nhận gì.
- Giá tại Singapore: **1.000 email đầu tiên mỗi tháng miễn phí**, 1 triệu request API đầu tiên miễn phí (bảng giá SNS, kiểm tra 2026-10-31).

### 4.10. 🟨 Status check và tự phục hồi

Theo tài liệu EC2:

- **Simplified automatic recovery** — **bật mặc định** trên các instance được hỗ trợ, không tốn thêm tiền. Khi **system status check** lỗi (lỗi phần cứng/phần mềm của host AWS), AWS thử chuyển instance sang host khác. Instance giữ nguyên ID, IP private, **IP public** và EBS; mất dữ liệu trong RAM, hệ điều hành như vừa khởi động lại.
- **CloudWatch action based recovery** — bạn tự tạo alarm trên `StatusCheckFailed_System` với action recover; phục hồi nhanh hơn và báo qua SNS.
- **Không** phục hồi tự động khi chỉ **instance status check** lỗi — đó là lỗi bên trong máy của bạn, AWS không tự sửa được.

So với stop/start bằng tay: stop/start chuyển instance sang host mới nhưng **đổi public IP** (nếu không có Elastic IP). Phục hồi tự động thì giữ IP.

Với v3: dựa vào simplified automatic recovery có sẵn + alarm `StatusCheckFailed` gửi email để **bạn biết**. Alarm recover riêng là bài tập 🟨.

### 4.11. 🟨 Dashboard

Dashboard gom nhiều biểu đồ vào một trang. Miễn phí: **3 dashboard tùy chỉnh, mỗi cái tối đa 50 metric**/tháng; dashboard tự động (automatic dashboard) miễn phí. Một dashboard `taskhub` gồm CPU, mạng, status check và widget Logs Insights đếm `ERROR` là đủ cho v3.

### 4.12. 🟥 Bảng giá và hạn mức miễn phí (Singapore, kiểm tra 2026-10-31)

| Hạng mục | Miễn phí mỗi tháng | Giá sau mức miễn phí |
|---|---|---|
| Metric EC2 basic monitoring | Luôn miễn phí | — |
| Custom metric + detailed monitoring metric | 10 metric | 0,30 USD/metric (10.000 đầu) |
| API request | 1 triệu (trừ `GetMetricData` và hai API khác luôn tính phí) | — |
| Log ingest (lớp Standard) | **5 GB chung** cho ingest + lưu trữ + quét Logs Insights | 0,70 USD/GB |
| Lưu trữ log | (trong 5 GB chung) | 0,03 USD/GB-tháng |
| Logs Insights quét | (trong 5 GB chung) | 0,007 USD/GB |
| Alarm chuẩn | 10 alarm metric | 0,10 USD/alarm metric |
| Dashboard | 3 dashboard × 50 metric | Xem trang giá |
| SNS email | 1.000 email | 2 USD / 100.000 email |

**Ước tính cho taskhub:** một app nhỏ, vài nghìn request/ngày ghi vài MB log/ngày → vài chục đến vài trăm MB/tháng, xa mức 5 GB. Hai alarm, một topic — trong mức miễn phí. Thứ có thể vượt: bật log ở mức `DEBUG` rồi quên tắt, hoặc quên đặt retention.

### 4.13. 🟥 CloudTrail khác CloudWatch thế nào

| | CloudWatch | **CloudTrail** |
|---|---|---|
| Trả lời câu hỏi | "Hệ thống đang **chạy** thế nào?" | "**Ai** đã **làm gì** với tài khoản AWS, lúc nào, từ đâu?" |
| Dữ liệu | Metric, log ứng dụng, alarm | Bản ghi gọi API (console, CLI, SDK) |
| Ví dụ | CPU 95% lúc 14:03 | `phuong-admin` gọi `StopInstances` lúc 14:01 từ IP X |
| Mặc định | Metric dịch vụ AWS có sẵn | **Event history**: 90 ngày management event mỗi region, **bật sẵn, xem không mất phí** |

Khi điều tra sự cố, bạn thường dùng **cả hai**: CloudWatch cho thấy app chết lúc 14:03; CloudTrail cho thấy ai đó sửa security group lúc 14:02.

### 4.14. Gặp lại ở đâu

| Kiến thức | Gặp lại |
|---|---|
| Log driver `awslogs`, log group `/taskhub/dev/app` | [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md) — deploy xong đọc log ở đâu |
| Alarm + SNS `taskhub-alerts` | v3; Module 08 (Grafana alerting thay thế/bổ sung) |
| Khoảng mù RAM/đĩa | [Bài 11](11-putting-it-together.md); Module 08 (`node-exporter`) |
| Metric filter, Logs Insights | Module 08 — so sánh với LogQL của Loki |
| CloudTrail | Module 10 — điều tra bảo mật |
| `aws_cloudwatch_metric_alarm` | Module 07 — Terraform tạo lại alarm (v4) |

---

## 5. Ví dụ thực tế

**Sự cố "app chậm dần rồi chết" (tình huống minh họa).**

- 02:10 — Một job lỗi kẹt vòng lặp, CPU `taskhub-app` lên 100%.
- 02:20 — Alarm `taskhub-cpu-high` (2 × 5 phút > 80%) chuyển `ALARM` → email tới điện thoại người trực.
- 02:25 — Người trực mở Logs Insights trên `/taskhub/dev/app`, khoảng thời gian 30 phút:

  ```text
  fields @timestamp, @message
  | filter @message like /ERROR|WARN/
  | stats count(*) by bin(1m)
  ```

  Thấy WARN tăng vọt từ 02:09. Đọc vài dòng đầu tiên → tìm ra request gây lỗi.
- 02:35 — Rollback về image tag trước ([Module 05 bài 05](../05-CICD/05-deployment-strategies-rollback.md)). CPU về 5%. Alarm về `OK` → email "OK".
- Sáng hôm sau — postmortem. Kiểm tra `CPUSurplusCreditsCharged` để biết sự cố có làm phát sinh phí CPU credit không.

**Không có CloudWatch Logs**, người trực phải SSH/SSM vào máy, và nếu container đã bị khởi động lại nhiều lần thì log cũ có thể đã mất. **Không có alarm**, người đầu tiên biết là khách hàng.

---

## 6. Sơ đồ kiến trúc

```text
                                 Region ap-southeast-1
 ┌──────────────────────── EC2 taskhub-app (t3.small) ────────────────────────┐
 │                                                                             │
 │  container taskhub ──stdout/stderr──► Docker daemon                         │
 │                                         │  log driver awslogs (non-blocking)│
 │                                         │  credential: instance role        │
 │                                         │  taskhub-ec2-role (qua IMDSv2)    │
 │                                         ▼                                   │
 │                                   PutLogEvents ─────────────┐               │
 └─────────────────────────────────────────────────────────────┼───────────────┘
        ▲ hypervisor đo CPU, mạng, status check                 │ HTTPS ra Internet qua IGW
        │ (không cần agent)                                     ▼
 ┌──────┴─────────────── CloudWatch ───────────────────────────────────────────┐
 │ Metrics  AWS/EC2  CPUUtilization, StatusCheckFailed…   (5 phút / 1 phút)    │
 │ Logs     /taskhub/dev/app  ── retention 7 ngày ── Logs Insights             │
 │ Alarms   taskhub-cpu-high        (CPU > 80%, 2×300s)                         │
 │          taskhub-status-check    (StatusCheckFailed ≥ 1, 2×60s)              │
 └───────────────────────┬─────────────────────────────────────────────────────┘
                         │ đổi trạng thái → publish
                         ▼
               SNS topic taskhub-alerts ──► email (đã xác nhận subscription)

 CloudTrail (riêng biệt): ai gọi API nào — Event history 90 ngày, miễn phí
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Tốn phí? |
|---|---|---|
| `aws cloudwatch list-metrics --namespace AWS/EC2 --dimensions Name=InstanceId,Value=<id>` | Xem metric có sẵn của instance | Không |
| `aws cloudwatch get-metric-statistics ...` | Lấy số liệu một metric | Trong 1 triệu API miễn phí |
| ⚠️ `aws logs create-log-group` | Tạo log group | Không (dữ liệu mới tính) |
| `aws logs put-retention-policy` | Đặt retention | Không |
| `aws logs describe-log-groups` | Xem group, retention, dung lượng | Không |
| `aws logs tail <group> --follow` | Xem log trực tiếp từ laptop | Không |
| `aws logs start-query` / `get-query-results` | Chạy Logs Insights bằng CLI | Theo GB quét |
| ⚠️ `aws sns create-topic` / `subscribe` | Tạo topic, đăng ký email | Trong mức miễn phí |
| ⚠️ `aws cloudwatch put-metric-alarm` | Tạo/cập nhật alarm | 10 alarm miễn phí |
| `aws cloudwatch describe-alarms` | Xem trạng thái alarm | Không |
| `aws cloudwatch set-alarm-state` | **Thử** alarm | Không |
| `aws cloudwatch describe-alarm-history` | Lịch sử đổi trạng thái (giữ 30 ngày) | Không |
| `aws cloudtrail lookup-events` | Tra ai đã gọi API | Không |
| ⚠️ `aws cloudwatch delete-alarms`, `aws logs delete-log-group`, `aws sns delete-topic` | Dọn dẹp | — |

---

## 8. Giải thích câu lệnh và tham số

> Mọi lệnh dưới đây chạy ở `[WSL]` với `export AWS_PROFILE=taskhub` và region `ap-southeast-1` trong profile. ID dùng giá trị minh họa — thay bằng của bạn.

### 8.1. Lấy instance ID của taskhub theo tag

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=taskhub-app Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
echo "$INSTANCE_ID"
```

```text
i-0abc1234def567890
```

Không hard-code ID trong ghi chú — instance có thể được tạo lại (v4 dùng Terraform).

### 8.2. Đọc số liệu CPU

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --start-time "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 --statistics Average Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Average,Maximum]' --output table
```

Đầu ra minh họa:

```text
-------------------------------------------------------------
|                   GetMetricStatistics                     |
+----------------------------+---------------+--------------+
|  2027-01-20T03:00:00+00:00 |  2.1          |  6.8         |
|  2027-01-20T03:05:00+00:00 |  1.9          |  3.2         |
+----------------------------+---------------+--------------+
```

| Tham số | Ý nghĩa |
|---|---|
| `--dimensions` | Phải khớp **chính xác** dimension của metric |
| `--start-time/--end-time` | Thời gian **UTC** (CloudWatch luôn dùng UTC) |
| `--period 300` | Basic monitoring chỉ có điểm 5 phút; đặt 60 sẽ không có thêm dữ liệu |
| `--statistics Average Maximum` | Average che mất đỉnh ngắn; Maximum cho thấy đỉnh |

### 8.3. Tạo log group và đặt retention

⚠️ Tạo tài nguyên (miễn phí cho tới khi có dữ liệu).

```bash
aws logs create-log-group --log-group-name /taskhub/dev/app \
  --tags Project=taskhub,Env=dev,Owner=phuong,ManagedBy=manual
aws logs put-retention-policy --log-group-name /taskhub/dev/app --retention-in-days 7
aws logs describe-log-groups --log-group-name-prefix /taskhub/ \
  --query 'logGroups[].[logGroupName,retentionInDays,storedBytes]' --output table
```

```text
--------------------------------------------
|            DescribeLogGroups             |
+-------------------+-----+----------------+
|  /taskhub/dev/app |  7  |  0             |
+-------------------+-----+----------------+
```

Cột retention **trống** = "Never expire" → sửa ngay.

### 8.4. Xem log từ laptop

```bash
aws logs tail /taskhub/dev/app --since 15m --follow
aws logs tail /taskhub/dev/app --since 1h --filter-pattern ERROR
```

- `--since` — `15m`, `1h`, `2d`…
- `--follow` — như `tail -f`, Ctrl+C để thoát.
- `--filter-pattern` — cú pháp **filter pattern** của CloudWatch Logs (khác Logs Insights). `ERROR` khớp các event chứa từ đó.

### 8.5. Logs Insights bằng CLI

```bash
QUERY_ID=$(aws logs start-query --log-group-name /taskhub/dev/app \
  --start-time "$(date -u -d '-1 hour' +%s)" --end-time "$(date -u +%s)" \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20' \
  --query queryId --output text)
sleep 5
aws logs get-query-results --query-id "$QUERY_ID" --query 'status'
aws logs get-query-results --query-id "$QUERY_ID" \
  --query 'results[].[ (@[?field==`"@timestamp"`].value)[0], (@[?field==`"@message"`].value)[0] ]' --output text
```

- `--start-time/--end-time` là **epoch giây**.
- `status` có thể là `Running` → chờ thêm rồi gọi lại; `Complete` mới đọc kết quả.
- Phần `--query` thứ hai dùng JMESPath ([bài 06](06-aws-cli.md)) để rút ra hai cột dễ đọc.

### 8.6. SNS topic và email

⚠️ Tạo tài nguyên (miễn phí trong hạn mức).

```bash
TOPIC_ARN=$(aws sns create-topic --name taskhub-alerts \
  --tags Key=Project,Value=taskhub Key=Env,Value=dev \
  --query TopicArn --output text)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint you@example.com
aws sns list-subscriptions-by-topic --topic-arn "$TOPIC_ARN" \
  --query 'Subscriptions[].[Endpoint,SubscriptionArn]' --output table
```

```text
---------------------------------------------------
|           ListSubscriptionsByTopic              |
+-------------------+-----------------------------+
|  you@example.com  |  PendingConfirmation        |
+-------------------+-----------------------------+
```

Thay `you@example.com` bằng email thật của bạn. Mở hộp thư (kiểm tra cả thư rác), bấm **Confirm subscription** → chạy lại lệnh, cột thứ hai thành một ARN dài.

### 8.7. Alarm CPU và alarm status check

⚠️ Tạo tài nguyên (10 alarm đầu miễn phí).

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name taskhub-cpu-high \
  --alarm-description "taskhub-app CPU > 80% trong 10 phút" \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Average --period 300 \
  --evaluation-periods 2 --datapoints-to-alarm 2 \
  --threshold 80 --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" \
  --tags Key=Project,Value=taskhub Key=Env,Value=dev

aws cloudwatch put-metric-alarm \
  --alarm-name taskhub-status-check \
  --alarm-description "taskhub-app status check failed" \
  --namespace AWS/EC2 --metric-name StatusCheckFailed \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Maximum --period 60 \
  --evaluation-periods 2 --datapoints-to-alarm 2 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" --ok-actions "$TOPIC_ARN" \
  --tags Key=Project,Value=taskhub Key=Env,Value=dev
```

| Tham số | Vì sao chọn giá trị này |
|---|---|
| `--period 300` (CPU) | Basic monitoring gửi CPU mỗi 5 phút; tài liệu khuyên period ≥ độ phân giải của metric |
| `--period 60` (status check) | Status check có điểm 1 phút ngay cả với basic monitoring |
| `--evaluation-periods 2 --datapoints-to-alarm 2` | Tránh báo động vì một đỉnh ngắn (Spring Boot khởi động) |
| `--statistic Maximum` (status check) | Giá trị 0/1 — chỉ cần một lần lỗi trong period là đáng chú ý |
| `--treat-missing-data notBreaching` | Instance stop có chủ đích (không học) → không có dữ liệu → không báo động giả |
| `--ok-actions` | Nhận cả email "đã hồi phục" — biết sự cố kết thúc lúc nào |

`put-metric-alarm` cũng dùng để **cập nhật**: chạy lại với cùng tên sẽ ghi đè cấu hình.

### 8.8. Thử alarm

```bash
aws cloudwatch set-alarm-state --alarm-name taskhub-cpu-high \
  --state-value ALARM --state-reason "Thu duong ong canh bao (test)"
aws cloudwatch describe-alarm-history --alarm-name taskhub-cpu-high \
  --history-item-type StateUpdate --max-records 5 \
  --query 'AlarmHistoryItems[].[Timestamp,HistorySummary]' --output table
```

```text
-----------------------------------------------------------------------------
|                          DescribeAlarmHistory                             |
+----------------------------------+----------------------------------------+
|  2027-01-20T03:40:12.345+00:00   |  Alarm updated from ALARM to OK        |
|  2027-01-20T03:38:01.123+00:00   |  Alarm updated from OK to ALARM        |
+----------------------------------+----------------------------------------+
```

Email "ALARM" đến trong khoảng một phút; ở lần đánh giá kế tiếp alarm tự về `OK` (vì CPU thật thấp) → email "OK".

---

## 9. Bài thực hành từng bước

> 💰 **Ước tính chi phí:** log vài MB, 2 alarm, 1 topic, vài email → **trong mức miễn phí**. Bước 9 chạy tải CPU tối đa 15 phút trên `t3.small`: nếu instance đã chạy rảnh vài giờ thì credit tích lũy đủ trả; trường hợp xấu nhất vay khoảng 0,4 vCPU-giờ ≈ **0,02 USD** (theo mức 0,05 USD/vCPU-giờ trong ví dụ của AWS).
> **Điều kiện:** EC2 `taskhub-app` (v2) đang chạy taskhub bằng Compose trong `/opt/taskhub`; role `taskhub-ec2-role` đã có policy ghi log như mục 4.6 (thiếu thì thêm theo [bài 02](02-iam.md)); bạn vào được máy bằng SSM Session Manager.

### Bước 1 — Chuẩn bị biến `[WSL]`

```bash
export AWS_PROFILE=taskhub
aws sts get-caller-identity --query Arn --output text   # đúng user/role của bạn?
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=taskhub-app Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text)
echo "$INSTANCE_ID"
```

Không ra ID nào → instance đang stop hoặc sai tag/region. Dừng lại và sửa trước.

### Bước 2 — Kiểm tra quyền của instance role `[WSL]`

```bash
aws iam list-attached-role-policies --role-name taskhub-ec2-role
aws iam list-role-policies --role-name taskhub-ec2-role
```

Mở policy `taskhub-ec2-app` (inline: `aws iam get-role-policy --role-name taskhub-ec2-role --policy-name taskhub-ec2-app`; nếu là customer managed policy thì dùng `aws iam get-policy-version`) và tìm statement có `logs:CreateLogStream`, `logs:PutLogEvents` trên `/taskhub/dev/*`. ❓ Vì sao **không** cần `logs:CreateLogGroup`?

### Bước 3 — Tạo log group có retention `[WSL]`

Chạy các lệnh ở mục 8.3. Xác nhận cột retention = `7`.

### Bước 4 — Bật driver `awslogs` cho taskhub `[EC2]`

Mở phiên SSM ([bài 04](04-ec2.md)):

```bash
aws ssm start-session --target "$INSTANCE_ID"
```

Trong phiên (`[EC2]`):

```bash
sudo -i
cd /opt/taskhub
cp compose.yaml compose.yaml.bak-$(date +%Y%m%d%H%M)
```

Thêm khối `logging:` (mục 4.6) vào service `taskhub` bằng `nano compose.yaml`. Kiểm tra cú pháp rồi tạo lại **chỉ** container taskhub:

```bash
docker compose config --quiet && echo "compose OK"
docker compose up -d taskhub
docker compose ps
docker inspect --format '{{.HostConfig.LogConfig.Type}} {{json .HostConfig.LogConfig.Config}}' "$(docker compose ps -q taskhub)"
docker compose logs --tail 5 taskhub      # dual logging — vẫn đọc được
```

Đầu ra mong đợi (minh họa) của `docker inspect`:

```text
awslogs {"awslogs-group":"/taskhub/dev/app","awslogs-region":"ap-southeast-1","max-buffer-size":"4m","mode":"non-blocking"}
```

> 📌 Thay đổi này nằm **trên EC2**, chưa có trong repo. Sau lab, đưa khối `logging:` vào file compose dùng cho EC2 trong repo `taskhub` qua một Pull Request — theo hướng dẫn của [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md), để lần đồng bộ sau không làm mất cấu hình.

### Bước 5 — Sinh log, kể cả lỗi `[EC2]`

```bash
# Request bình thường qua nginx
for i in $(seq 1 5); do curl -s -o /dev/null -w '%{http_code}\n' http://localhost/api/tasks; done

# Gây lỗi có kiểm soát: tạm dừng database
docker compose stop postgres
for i in $(seq 1 3); do curl -s -o /dev/null -w '%{http_code}\n' http://localhost/api/tasks; done
docker compose start postgres
sleep 20
curl -s http://localhost/actuator/health; echo
exit    # thoát sudo -i; gõ exit lần nữa để đóng phiên SSM
```

Khi database dừng, request trả `500` và app ghi stack trace mức `ERROR` (nội dung chính xác tùy phiên bản). Sau khi `start postgres`, health trở lại `{"status":"UP"}` — app tự kết nối lại.

### Bước 6 — Đọc log từ laptop `[WSL]`

```bash
aws logs describe-log-streams --log-group-name /taskhub/dev/app \
  --query 'logStreams[].[logStreamName,lastEventTimestamp]' --output table
aws logs tail /taskhub/dev/app --since 15m --filter-pattern ERROR
```

Tên stream là container ID dài 64 ký tự. ❓ Lần deploy sau (container mới) sẽ có stream mới hay ghi tiếp stream cũ?

### Bước 7 — Logs Insights `[AWS Console]` rồi `[WSL]`

1. Console → **CloudWatch** → **Logs Insights** → chọn **đúng một** log group `/taskhub/dev/app` → khoảng thời gian **30 phút**.
2. Chạy truy vấn ở mục 4.7. Sau đó chạy:

   ```text
   fields @timestamp, @message
   | filter @message like /ERROR/
   | stats count(*) as errors by bin(1m)
   ```

   Chuyển sang tab **Visualization** → thấy cột lỗi đúng lúc bạn dừng database.
3. Chạy lại truy vấn đầu bằng CLI (mục 8.5). Ghi dung lượng đã quét (console hiển thị số byte scanned) vào ghi chú.

### Bước 8 — SNS và alarm `[WSL]`

1. Tạo topic + subscription (mục 8.6), **xác nhận email**.
2. Tạo hai alarm (mục 8.7).
3. Chờ 5–10 phút rồi xem:

   ```bash
   aws cloudwatch describe-alarms --alarm-name-prefix taskhub- \
     --query 'MetricAlarms[].[AlarmName,StateValue,StateReason]' --output table
   ```

   Hai alarm nên ở `OK`. Nếu vẫn `INSUFFICIENT_DATA` sau 15 phút → kiểm tra `InstanceId` và region (mục 11).
4. Thử đường ống cảnh báo bằng `set-alarm-state` (mục 8.8). Email "ALARM" rồi "OK" phải đến.

### Bước 9 — Gây tải CPU thật (tối đa 15 phút) `[EC2]`

Mở lại phiên SSM, rồi:

```bash
sudo docker run --rm --name cpu-burn alpine:3.20 \
  sh -c 'apk add --no-cache stress-ng >/dev/null && stress-ng --cpu 2 --timeout 15m --metrics-brief'
```

- `--cpu 2` — 2 worker, đủ làm đầy 2 vCPU của `t3.small`.
- `--timeout 15m` — tự dừng; đóng phiên cũng không kéo dài quá 15 phút vì container có `--rm` và `stress-ng` tự thoát. Nếu muốn dừng sớm: mở phiên khác, `sudo docker stop cpu-burn`.

Không muốn tải image? Thay bằng vòng lặp shell (mỗi vòng ăn 1 vCPU):

```bash
for n in 1 2; do timeout 900 sh -c 'while :; do :; done' & done; wait
```

Trong lúc chờ, ở `[WSL]` theo dõi:

```bash
watch -n 60 "aws cloudwatch describe-alarms --alarm-names taskhub-cpu-high --query 'MetricAlarms[0].StateValue' --output text"
```

Với basic monitoring, alarm vào `ALARM` sau khoảng 10–15 phút (2 điểm 5 phút liên tiếp > 80%). Khi tải dừng, khoảng 5–10 phút sau alarm về `OK`.

Sau đó xem credit:

```bash
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUCreditBalance \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --start-time "$(date -u -d '-2 hour' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 --statistics Average --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Average]' --output text
```

❓ `CPUCreditBalance` giảm bao nhiêu trong 15 phút? Có khớp phép tính "2 vCPU × 100% × 15 phút = 30 credit, trừ phần tích được trong thời gian đó" không?

### Bước 10 — CloudTrail: ai đã làm gì `[WSL]`

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutMetricAlarm \
  --max-results 5 --query 'Events[].[EventTime,Username,EventName]' --output table
```

Bạn thấy chính mình đã tạo alarm lúc nào. Thử thêm `AttributeKey=EventName,AttributeValue=StartSession` để thấy các phiên SSM.

### Bước 11 — Dọn dẹp

**Giữ lại** cho v3 (đều trong mức miễn phí): log group `/taskhub/dev/app` (retention 7 ngày), topic `taskhub-alerts`, hai alarm `taskhub-cpu-high` và `taskhub-status-check`.

**Kiểm tra không còn gì sót của bài thử:**

```bash
# [EC2] container stress không còn
sudo docker ps -a --filter name=cpu-burn
# [WSL] alarm, topic, log group đúng như dự định — không có bản thừa
aws cloudwatch describe-alarms --alarm-name-prefix taskhub- --query 'MetricAlarms[].AlarmName'
aws sns list-topics --query 'Topics[].TopicArn'
aws logs describe-log-groups --query 'logGroups[?retentionInDays==`null`].logGroupName'   # group nào chưa có retention?
```

Lệnh cuối liệt kê log group **không có retention** — bất kỳ group nào hiện ra (kể cả do dịch vụ khác tự tạo) đều nên được đặt retention.

**Khi kết thúc giai đoạn AWS thủ công** (trước khi chuyển sang Terraform ở v4) — ⚠️ xóa vĩnh viễn:

```bash
aws cloudwatch delete-alarms --alarm-names taskhub-cpu-high taskhub-status-check
aws sns delete-topic --topic-arn "$TOPIC_ARN"
aws logs delete-log-group --log-group-name /taskhub/dev/app
```

---

## 10. Kết quả mong đợi

- `aws logs tail /taskhub/dev/app` hiển thị log của taskhub, có các dòng `ERROR` đúng lúc dừng database.
- `describe-log-groups` cho thấy retention `7`.
- Logs Insights vẽ được biểu đồ số lỗi theo phút.
- Subscription email đã xác nhận; nhận được 4 email: ALARM/OK từ `set-alarm-state` và ALARM/OK từ tải CPU thật.
- `describe-alarm-history` ghi đủ các lần đổi trạng thái.
- Ghi chú `week13/cloudwatch-lab.md` có: số credit CPU đã tiêu, dung lượng Logs Insights đã quét, và câu trả lời cho các câu hỏi ❓.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách kiểm tra | Cách sửa |
|---|---|---|---|
| `docker compose up` báo lỗi, container taskhub **không start**, thông báo nhắc tới `awslogs` / `log group does not exist` | Log group chưa tạo, sai tên, hoặc sai region | `aws logs describe-log-groups --log-group-name-prefix /taskhub/` | Tạo group đúng tên/region; hoặc sửa `awslogs-group` |
| Lỗi `AccessDeniedException ... not authorized to perform: logs:CreateLogStream` / `PutLogEvents` | Role thiếu quyền, hoặc `Resource` sai ARN (thiếu `:*` ở cuối) | `aws iam get-role-policy ...`; `journalctl -u docker` trên EC2 | Sửa policy; tạo lại container |
| Lỗi credential (`NoCredentialProviders` hoặc tương tự) | Instance không có instance profile, hoặc IMDS bị chặn | `aws ec2 describe-instances --query '...IamInstanceProfile'` | Gắn `taskhub-ec2-role`; kiểm tra metadata options |
| Log group có dữ liệu nhưng `aws logs tail` trống | Sai region trong profile, hoặc `--since` quá ngắn | `aws configure get region --profile taskhub` | Thêm `--region ap-southeast-1`; tăng `--since` |
| Alarm mãi `INSUFFICIENT_DATA` | Sai `InstanceId`, sai region, instance đang stop | `aws cloudwatch list-metrics --namespace AWS/EC2 --dimensions Name=InstanceId,Value=<id>` | Tạo lại alarm với dimension đúng |
| Alarm CPU không bao giờ vào `ALARM` dù CPU 100% | Period 60 với basic monitoring; hoặc thời gian tải ngắn hơn evaluation | Xem `Period`, `EvaluationPeriods` trong `describe-alarms` | Period 300; chạy tải ≥ 15 phút |
| Không nhận email | Subscription chưa xác nhận; email vào thư rác; alarm thiếu `--alarm-actions` | `list-subscriptions-by-topic`; `describe-alarms --query '...AlarmActions'` | Xác nhận; thêm action |
| Hóa đơn CloudWatch Logs tăng dần | Log group "Never expire" | Lệnh lọc `retentionInDays==null` ở bước 11 | Đặt retention |
| App chậm/treo khi mạng ra ngoài chập chờn | Driver `awslogs` ở chế độ `blocking` (mặc định) | `docker inspect` xem `mode` | Đặt `mode: non-blocking` (chấp nhận có thể mất log) |
| `get-query-results` trả `Running` mãi | Truy vấn quét nhiều dữ liệu | `status` | Thu hẹp thời gian; chọn một log group |

---

## 12. Đọc log và xử lý lỗi

**Khi log không lên CloudWatch**, đi từ nguồn ra đích:

```text
1. App có ghi log không?          docker compose logs --tail 20 taskhub     (dual logging cache)
2. Container dùng driver nào?     docker inspect --format '{{.HostConfig.LogConfig}}' <container>
3. Daemon báo lỗi gì?             sudo journalctl -u docker --since "15 min ago" | grep -i awslogs
4. Instance có credential không?  [EC2] TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
                                         -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
                                         curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
                                         http://169.254.169.254/latest/meta-data/iam/security-credentials/
                                  → phải in ra taskhub-ec2-role
5. Role có quyền không?           [WSL] aws iam get-role-policy ...  (Resource có khớp /taskhub/dev/*?)
6. Đúng group, đúng region?       [WSL] aws logs describe-log-streams --log-group-name /taskhub/dev/app
```

Dòng log minh họa ở bước 3 khi role thiếu quyền:

```text
dockerd[812]: level=error msg="Failed to put log events" errorCode=AccessDeniedException
  message="User: arn:aws:sts::111122223333:assumed-role/taskhub-ec2-role/i-0abc... is not authorized to perform:
  logs:PutLogEvents on resource: arn:aws:logs:ap-southeast-1:111122223333:log-group:/taskhub/dev/app:log-stream:..."
```

Đọc dòng này: **ai** (`assumed-role/taskhub-ec2-role` — chứng tỏ credential đúng), **thiếu quyền gì** (`logs:PutLogEvents`), **trên tài nguyên nào** (ARN đầy đủ). Ba thông tin đủ để sửa policy mà không cần đoán. Đây là cách đọc mọi lỗi `AccessDenied` của AWS ([bài 02](02-iam.md)).

**Khi alarm "kêu" bất ngờ:** `describe-alarm-history` cho biết **lúc nào** và **giá trị** gây đổi trạng thái (trong `HistoryData`); đối chiếu với CloudTrail để xem có ai vừa thay đổi gì.

Ghi lại vào nhật ký debug theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Namespace, dimension, statistic, period là gì? Vì sao alarm sai `InstanceId` ở mãi `INSUFFICIENT_DATA`?
2. Vì sao EC2 không có metric RAM và dung lượng đĩa mặc định? Muốn có thì làm gì, tốn bao nhiêu?
3. Basic và detailed monitoring khác nhau thế nào về chu kỳ và chi phí? Ảnh hưởng gì tới period của alarm CPU?
4. `t3.small` có baseline bao nhiêu? Chế độ unlimited có thể làm phát sinh chi phí trong trường hợp nào?
5. Log group, log stream, log event khác nhau thế nào? Driver `awslogs` đặt tên stream mặc định ra sao?
6. Retention mặc định của log group là gì và vì sao đó là bẫy chi phí?
7. Vì sao dự án giữ `awslogs-create-group: false` và tự tạo log group bằng CLI?
8. `mode: blocking` và `non-blocking` khác nhau thế nào? Vì sao taskhub chọn `non-blocking`?
9. Ai thực sự gửi log lên CloudWatch: container hay Docker daemon? Credential lấy từ đâu?
10. Role thiếu quyền ghi log thì chuyện gì xảy ra lúc deploy?
11. Ba trạng thái của alarm là gì? `treat-missing-data notBreaching` giúp gì cho một server hay được stop?
12. Làm thế nào kiểm tra email cảnh báo hoạt động mà không gây sự cố thật?
13. Simplified automatic recovery xử lý loại lỗi nào, giữ lại gì, mất gì? Nó có xử lý lỗi instance status check không?
14. CloudWatch và CloudTrail trả lời những câu hỏi khác nhau nào? Cho ví dụ điều tra cần cả hai.
15. Logs Insights tính tiền theo gì? Nêu hai cách giảm chi phí truy vấn.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/10-solutions.md](solutions/10-solutions.md). Chỉ mở sau khi tự làm.

**Bài 1 — Alarm theo số lỗi.** Tạo **metric filter** trên `/taskhub/dev/app` đếm các event chứa `ERROR` thành metric `TaskhubErrorCount` (namespace `Taskhub`), rồi alarm khi tổng > 5 trong 5 phút, gửi tới `taskhub-alerts`. Thử bằng cách dừng database như bước 5. Ghi lại: metric filter này tính vào hạn mức miễn phí nào?

**Bài 2 — Dashboard taskhub.** Tạo dashboard `taskhub` (console hoặc `aws cloudwatch put-dashboard`) gồm: CPU (Average và Maximum), NetworkIn/Out, StatusCheckFailed, `CPUCreditBalance`, và một widget Logs Insights đếm lỗi theo 5 phút. Chụp màn hình đưa vào `docs/` của repo.

**Bài 3 — 🟨 CloudWatch agent cho đĩa và RAM.** Đọc tài liệu CloudWatch agent, cài trên `taskhub-app`, chỉ thu `disk_used_percent` cho `/` và `mem_used_percent`. Tính trước chi phí (bao nhiêu metric, nằm trong 10 metric miễn phí không — nhớ cộng cả metric filter bài 1). Tạo alarm đĩa > 85%. Role cần thêm quyền gì?

**Bài 4 — 🟨 Alarm recover.** Tạo alarm trên `StatusCheckFailed_System` với action recover (`arn:aws:automate:ap-southeast-1:ec2:recover`) và thông báo SNS. Giải thích vì sao không nên đặt action recover cho `StatusCheckFailed_Instance`. Không thể gây lỗi hệ thống thật — chỉ kiểm tra cấu hình bằng `describe-alarms`.

**Bài 5 — Điều tra bằng CloudTrail.** Stop rồi start `taskhub-app` từ console. Dùng `aws cloudtrail lookup-events` tìm hai sự kiện đó: ai, lúc nào, từ IP nào. Public IP của instance có đổi không? Điều đó ảnh hưởng tới biến `APP_URL` của v3 thế nào?

**Bài 6 — Viết quyết định.** Viết một đoạn ngắn (ADR mini) cho câu hỏi: "Log của taskhub nên `blocking` hay `non-blocking`?" Gồm bối cảnh, hai lựa chọn, quyết định, hệ quả (cái gì có thể mất, làm sao phát hiện việc mất log).

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được namespace/dimension/statistic/period và đọc được số liệu bằng `get-metric-statistics`.
- [ ] Nói được vì sao không có metric RAM/đĩa mặc định và cách có chúng.
- [ ] Đưa được log container lên CloudWatch Logs với retention 7 ngày, và giải thích ai gửi log, bằng quyền gì.
- [ ] Giải thích được đánh đổi `blocking`/`non-blocking`.
- [ ] Viết được truy vấn Logs Insights lọc và đếm lỗi.
- [ ] Tạo được alarm CPU và status check có SNS email, thử được bằng `set-alarm-state`.
- [ ] Giải thích được CPU credit của `t3` và rủi ro chi phí khi tải cao kéo dài.
- [ ] Phân biệt được CloudWatch và CloudTrail bằng ví dụ.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Amazon CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) | Hạn mức miễn phí (5 GB log, 10 metric, 10 alarm, 3 dashboard) | 2026-10-31 |
| [AWS Price List — AmazonCloudWatch (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudWatch/current/ap-southeast-1/index.json) | Giá Singapore: ingest 0,70 USD/GB, lưu 0,03 USD/GB-tháng, quét 0,007 USD/GB, metric 0,30 USD, alarm 0,10 USD | 2026-10-31 |
| [AWS Price List — AmazonSNS (ap-southeast-1)](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonSNS/current/ap-southeast-1/index.json) | 1.000 email miễn phí, 1 triệu request miễn phí | 2026-10-31 |
| [CloudWatch — Metrics concepts](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html) | Namespace, dimension, period, retention của metric | 2026-10-31 |
| [CloudWatch — Using alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Alarms.html) | Loại alarm, `set-alarm-state`, lịch sử 30 ngày | 2026-10-31 |
| [CloudWatch Logs — Working with log groups and log streams](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/Working-with-log-groups-and-streams.html) | Retention mặc định vô thời hạn, độ trễ xóa 72 giờ | 2026-10-31 |
| [CloudWatch Logs Insights — Query syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html) | Lệnh `fields`, `filter`, `stats`, khuyến nghị giảm chi phí | 2026-10-31 |
| [Docker — Amazon CloudWatch Logs logging driver](https://docs.docker.com/engine/logging/drivers/awslogs/) | Tùy chọn `awslogs-*`, quyền IAM, credential từ instance profile | 2026-10-31 |
| [Docker — Configure logging drivers](https://docs.docker.com/engine/logging/configure/) | `mode` blocking/non-blocking, `max-buffer-size` | 2026-10-31 |
| [Docker — Dual logging](https://docs.docker.com/engine/logging/dual-logging/) | `docker logs` với driver từ xa, giới hạn cache | 2026-10-31 |
| [EC2 — Manage detailed monitoring](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/manage-detailed-monitoring.html) | Basic 5 phút/status check 1 phút, detailed tính phí | 2026-10-31 |
| [EC2 — Burstable performance: key concepts](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-credits-baseline-concepts.html) | Bảng credit `t3.small` (24 credit/giờ, baseline 20%) | 2026-10-31 |
| [EC2 — Unlimited mode concepts](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances-unlimited-mode-concepts.html) | T3 mặc định unlimited, phí surplus credit | 2026-10-31 |
| [EC2 — Automatic instance recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html) | Simplified automatic recovery, giữ IP, không xử lý lỗi instance status check | 2026-10-31 |
| [CloudTrail — Working with event history](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html) | 90 ngày, miễn phí, theo region | 2026-10-31 |
