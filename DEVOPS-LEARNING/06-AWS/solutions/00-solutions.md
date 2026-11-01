# Lời giải — Bài 00: Tạo tài khoản AWS an toàn và kiểm soát chi phí

> Chỉ đọc sau khi đã tự làm. Quay lại bài: [00-aws-account-setup-cost-safety.md](../00-aws-account-setup-cost-safety.md)

## Câu hỏi kiểm tra kiến thức (mục 13)

**1. Free plan vs Paid plan; hết credit thì sao?**
Cả hai đều nhận 100 USD credit khi tạo tài khoản và có thể nhận thêm tối đa 100 USD. Free plan: chỉ một số dịch vụ, **không bao giờ tính tiền**, không nhận khuyến mãi khác; kết thúc sau 6 tháng hoặc khi hết credit (cái nào đến trước). Paid plan: mọi dịch vụ, phần vượt credit tính tiền thật, tài khoản không đóng khi hết credit. Free plan hết credit → **tài khoản tự đóng**, mất quyền truy cập tài nguyên và dữ liệu.

**2. Sau khi tự đóng?**
AWS giữ nội dung **90 ngày** rồi xóa vĩnh viễn. Trong 90 ngày đó, nâng lên Paid plan (Billing → *Upgrade plan*) để lấy lại quyền truy cập.

**3. "Free tier eligible" với tài khoản sau 15/7/2025?**
Là danh sách loại máy được phép chạy trên Free plan (`t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large`); chi phí chạy chúng **trừ vào credit**. Chính sách cũ (tài khoản trước 15/7/2025): 12 tháng, hạn mức giờ miễn phí mỗi tháng cho `t2.micro`/`t3.micro`, vượt thì tính tiền.

**4. Hành động tự nâng lên Paid plan; ảnh hưởng tới cách đăng nhập?**
Tham gia AWS Organizations, dựng AWS Control Tower landing zone, tham gia AWS Partner Network (ngoài ra: hợp đồng Professional Services, Enterprise Agreement, mua Skill Builder Team, chỉ định tài khoản HIPAA/SEC). IAM Identity Center bản đầy đủ (organization instance) cần Organizations → sẽ nâng gói; bản account instance không cấp được quyền vào tài khoản AWS. Vì vậy chọn IAM user + MFA.

**5. Root và access key; việc chỉ root làm được?**
Access key của root là chìa khóa vĩnh viễn có **toàn quyền tuyệt đối**, không giới hạn được bằng policy; lộ ra là mất cả tài khoản lẫn thẻ thanh toán. Việc chỉ root làm: bật *Activate IAM Access* cho Billing; đổi email/mật khẩu root; đóng tài khoản; khôi phục quyền khi admin IAM duy nhất tự gỡ quyền; sửa bucket policy S3 chặn tất cả.

**6. MFA khuyến nghị cho root?**
Passkey hoặc security key (FIDO). Tốt hơn TOTP vì **chống phishing**: passkey gắn với tên miền thật của AWS bằng mật mã khóa công khai — trang giả không lấy được gì để dùng lại, còn mã 6 số thì người dùng có thể gõ nhầm vào trang giả.

**7. Budget không bao giờ cảnh báo?**
(a) Chọn *Net unblended costs* — trên Free plan chi phí sau credit luôn ≈ 0. (b) Email nhận cảnh báo **chưa xác minh** (hoặc rơi vào spam). Khả năng khác: số tiền budget đặt quá cao so với mức dùng thực tế; ngưỡng chỉ có *Forecasted* trong khi chưa đủ dữ liệu dự báo.

**8. Budgets có tốn tiền không?**
Theo dõi và gửi thông báo: **miễn phí**. Tốn tiền: action-enabled budget từ cái thứ ba trở đi (0,10 USD/ngày mỗi cái — hai cái đầu miễn phí), và budget report gửi định kỳ (0,01 USD mỗi báo cáo).

**9. Cron gọi Cost Explorer API mỗi 5 phút?**
12 lần/giờ × 24 × 30 = 8.640 request × 0,01 USD ≈ **86,4 USD/tháng** — gần hết credit ban đầu chỉ để xem chi phí. Xem miễn phí: Cost Explorer trên console, trang Bills, trang Billing Home; trạng thái gói và credit qua `aws freetier get-account-plan-state` (theo tài liệu là không tốn phí).

**10. `AdministratorAccess` mà không xem được Billing?**
Mặc định IAM user/role không vào được Billing kể cả có policy, cho đến khi **root** bật: Account → *IAM User and Role Access to Billing Information* → *Activate IAM Access*.

**11. Năm thứ vẫn tốn khi đã stop EC2?**
Ổ EBS (GB-tháng); Elastic IP (0,005 USD/giờ); snapshot/AMI tự tạo; NAT Gateway; load balancer; RDS đang chạy; CloudWatch Logs không có retention; tài nguyên ở region khác. (Bất kỳ 5 trong số này.)

**12. Hôm qua tạo EC2, hôm nay không thấy?**
(a) Console đang ở **region khác** → đổi region hoặc mở AWS Global View. (b) Đang đăng nhập **tài khoản/user khác** (ví dụ tài khoản thứ hai, hoặc một role) → kiểm tra góc trên phải / `aws sts get-caller-identity`. Khả năng thứ ba: máy đã bị terminate (trạng thái `terminated` còn hiện một thời gian ngắn) → CloudTrail tìm `TerminateInstances`.

**13. CloudTrail event history?**
90 ngày management event, theo từng region, bật sẵn, xem miễn phí. Giới hạn: mỗi lần tìm chỉ một region, một tài khoản, một thuộc tính lọc (cộng khoảng thời gian); không có data event.

**14. `Root` lúc 3 giờ sáng từ IP nước ngoài?**
Coi như root bị chiếm. Ngay lập tức: đăng nhập root (nếu còn được) → **đổi mật khẩu**, kiểm tra/đăng ký lại MFA, xóa mọi access key của root; kiểm tra IAM users/roles/access key lạ; xem CloudTrail các hành động sau thời điểm đó (tạo user? tạo EC2 ở region lạ?); xóa tài nguyên lạ; liên hệ AWS Support. Ghi postmortem.

---

## Bài tập tự làm (mục 14)

### Bài 1 — Ngân sách credit

Không có "đáp án số" duy nhất vì giá thay đổi và bạn phải dùng **số của calculator tại thời điểm làm bài**. Cách làm đúng:

```text
Chi phí tháng = giờ_máy × giá_t3.small_mỗi_giờ
              + 20 GiB × giá_gp3_mỗi_GB_tháng          (tính đủ tháng dù máy tắt)
              + giờ_có_IPv4 × 0,005 USD                  (Public IPv4)
```

Điểm hay sai:

- Kịch bản "4 giờ/ngày × 6 ngày/tuần" ≈ 4 × 6 × 4,3 ≈ **103 giờ/tháng** máy chạy.
- **Ổ gp3 tính đủ tháng** trong cả hai kịch bản.
- Public IPv4 **tự gán** bị thu hồi khi stop → chỉ tính trong giờ máy chạy. Nếu dùng **Elastic IP** thì tính đủ 730 giờ (≈ 3,65 USD) dù máy tắt — một lý do dự án không dùng Elastic IP.
- Số tháng credit đủ dùng = 100 / chi phí tháng (chưa tính các dịch vụ khác như CloudWatch, S3 — để dư 20–30%).

Kết luận mong đợi: kịch bản 24/7 tiêu credit nhanh hơn nhiều lần → **tắt máy khi không học** (bài 04 có lệnh), và từ v4 `terraform destroy`.

### Bài 2 — Budget thứ hai

- Loại: **Cost budget**, Monthly, Recurring, Fixed 8 USD.
- Filter: **Service** = *Amazon Elastic Compute Cloud - Compute* (và cân nhắc thêm *EC2 - Other* — nơi thường chứa EBS, NAT Gateway, data transfer; tên hiển thị có thể khác theo console) + **Region** = *Asia Pacific (Singapore)*.
- Loại chi phí: **Unblended** (lý do như bài).
- Ngưỡng: 80% Actual, 100% Forecasted.
- Vì sao hữu ích: budget tổng chỉ cho biết "đang tiêu nhiều"; budget theo dịch vụ chỉ ngay **thủ phạm** khả dĩ nhất từ bài 04 trở đi (EC2 + EBS + IPv4). Lưu ý: chi phí Public IPv4 có thể được ghi dưới mục VPC/EC2 khác nhau theo cách AWS phân loại — xác nhận trong Cost Explorer khi đã có dữ liệu.

### Bài 3 — Runbook "budget 80% ngày 10"

```text
1. Billing Home: credit còn bao nhiêu? Tốc độ tiêu 7 ngày gần nhất?
2. Cost Explorer: group by Service, khoảng 10 ngày đầu tháng, granularity Daily → dịch vụ nào tăng, từ ngày nào?
3. Cùng biểu đồ, group by Region → có region nào ngoài ap-southeast-1?
4. Trang Bills → dịch vụ đó → usage type (NatGateway-Hours? PublicIPv4? VolumeUsage?) → loại tài nguyên.
5. AWS Global View → tìm tài nguyên loại đó trên mọi region.
6. CloudTrail event history (đúng region) → ai tạo, lúc nào (Create*/Run*).
7. Quyết định: xóa / tắt / giữ. Xóa theo thứ tự phụ thuộc, kiểm tra lại bằng console/CLI.
8. Ghi troubleshooting-journal: triệu chứng, bằng chứng, nguyên nhân, cách phòng (checklist dọn lab?).
```

Đạt khi: đúng thứ tự "**tổng → dịch vụ → region → loại sử dụng → tài nguyên → ai tạo**", và có bước phòng tái diễn.

### Bài 4 — ADR

Mẫu đạt yêu cầu (rút gọn):

```markdown
# ADR-NNNN: Dùng IAM user + MFA thay vì IAM Identity Center cho tài khoản học tập

- Trạng thái: Đã chấp nhận · Ngày: 2027-01-04

## Bối cảnh
Một tài khoản AWS Free plan, một người dùng. Identity Center là cách AWS khuyến nghị.

## Các lựa chọn
1. Identity Center organization instance — cần AWS Organizations → tự nâng lên Paid plan.
2. Identity Center account instance — không hỗ trợ permission set, không cấp quyền vào tài khoản.
3. IAM user + MFA + `aws login` (credential tạm thời).

## Quyết định
Chọn 3.

## Hệ quả
- Tích cực: giữ được Free plan; không có access key dài hạn trên laptop.
- Tiêu cực: mật khẩu IAM user là thông tin dài hạn; không có SSO; không giống cách công ty làm.
- Đổi quyết định khi: nâng lên Paid plan và cần nhiều tài khoản (dev/prod) hoặc nhiều người.
```

(Số ADR tùy repo của bạn — xem các ADR đã có.)

### Bài 5 — Kiểm tra region

Đạt khi ảnh chụp AWS Global View cho thấy: Instances, Volumes, Elastic IPs, NAT gateways chỉ có ở `ap-southeast-1` (hoặc bằng 0). Lưu ý: **VPC mặc định** (default VPC), subnet và security group mặc định có sẵn ở mọi region — chúng **không** tính tiền, không cần xóa (xóa cũng được nhưng không bắt buộc).
