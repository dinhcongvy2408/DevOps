# 00. Tạo tài khoản AWS an toàn và kiểm soát chi phí

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc — **làm TRƯỚC mọi bài khác của module** · Kiến thức cần có trước: [README Module 06](README.md), [Lộ trình §7 — Chiến lược kiểm soát chi phí AWS](../00-ROADMAP/learning-roadmap.md#7-chiến-lược-kiểm-soát-chi-phí-aws)
> Môi trường: `[AWS Console]` trình duyệt, điện thoại cài ứng dụng xác thực (hoặc passkey/khóa bảo mật), thẻ thanh toán quốc tế

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

- Giải thích được **Free plan** và **Paid plan** của AWS khác nhau thế nào, credit được tiêu ra sao, và chuyện gì xảy ra khi hết 6 tháng hoặc hết credit.
- Tạo tài khoản AWS, bảo vệ **root user** bằng MFA (ưu tiên passkey), và biết root user chỉ dùng cho việc gì.
- Tạo người dùng quản trị hằng ngày `phuong-admin` thay vì dùng root (chi tiết ở [bài 02](02-iam.md)).
- Thiết lập **lớp cảnh báo chi phí**: cảnh báo Free Tier, **AWS Budgets** với email, và biết đọc trang Billing.
- Kể được danh sách **những thứ âm thầm tốn tiền** và có thói quen **dọn dẹp hằng tuần**.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Ở công ty, bạn sẽ không tự tạo tài khoản AWS. Nhưng bạn **sẽ** gặp những tình huống sau:

| Tình huống thật | Cần kiến thức của bài này |
|---|---|
| "Tháng này hóa đơn AWS tăng 40%, xem giúp vì sao" | Đọc Billing theo dịch vụ/region, biết những thứ âm thầm tốn tiền |
| Một access key bị lộ lên GitHub, ai đó dựng máy đào coin | Root/IAM tách biệt, MFA, không dùng access key dài hạn, CloudTrail |
| Sếp hỏi: "Môi trường test này mỗi tháng tốn bao nhiêu?" | Tag tài nguyên, Budgets, Cost Explorer |
| Phỏng vấn: "Bạn kiểm soát chi phí dự án cá nhân thế nào?" | Toàn bộ bài — đây là câu hỏi hay gặp với Junior Cloud |
| Sáng thứ Hai: "Ai tạo cái NAT Gateway này từ thứ Sáu?" | Thói quen dọn dẹp, tag `Owner`, CloudTrail event history |

> **Với bạn lúc này:** sai lầm đắt nhất của người tự học AWS không phải là chọn sai dịch vụ mà là **quên xóa tài nguyên**. Bài này dựng "lưới an toàn" trước khi bạn tạo bất cứ thứ gì.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Tài khoản AWS là gì?

**AWS account** (tài khoản AWS) là một "thùng chứa" độc lập: mọi tài nguyên (máy ảo, ổ đĩa, bucket…) bạn tạo đều thuộc về đúng một tài khoản, và **hóa đơn tính theo tài khoản**. Mỗi tài khoản có một số định danh 12 chữ số (giáo trình dùng số ví dụ `111122223333` của tài liệu AWS — thay bằng số của bạn).

### 3.2. Root user và IAM user

| Danh tính | Là gì | Dùng khi nào |
|---|---|---|
| **Root user** (người dùng gốc) | Email + mật khẩu dùng lúc đăng ký. Có **toàn quyền tuyệt đối**, kể cả đóng tài khoản, đổi thẻ thanh toán | Chỉ cho vài việc **bắt buộc** phải dùng root (xem §4.4). Còn lại cất đi |
| **IAM user** (người dùng IAM) | Danh tính do bạn tạo **bên trong** tài khoản, quyền hạn do bạn cấp | Công việc hằng ngày: `phuong-admin` |

So sánh với Linux ([Linux bài 03](../01-LINUX/03-permissions-users-groups.md)): root user giống tài khoản `root`, IAM user giống user thường được cấp `sudo`. Bạn đã quen nguyên tắc "không đăng nhập thẳng bằng root" — ở đây giống hệt, chỉ là hậu quả khi lộ còn nặng hơn: kẻ xấu dùng **thẻ của bạn**.

### 3.3. Region

**Region** (vùng) là một khu vực địa lý có nhiều trung tâm dữ liệu của AWS, ví dụ `ap-southeast-1` (Singapore). Phần lớn tài nguyên (EC2, VPC, RDS…) **thuộc về một region**: tạo ở Singapore thì khi console đang chọn N. Virginia bạn sẽ **không thấy** nó — nhưng nó vẫn chạy và vẫn tính tiền. Bài [01](01-cloud-fundamentals.md) giải thích kỹ hơn.

### 3.4. Mô hình tính tiền: dùng bao nhiêu trả bấy nhiêu

AWS tính tiền theo **mức sử dụng**: theo giờ/giây chạy máy, theo GB lưu trữ mỗi tháng, theo GB dữ liệu truyền ra Internet, theo số request… Không có "gói tháng" cố định. Hệ quả:

- Thứ gì **tồn tại** là có thể đang tốn tiền, kể cả khi bạn không dùng (ổ đĩa, địa chỉ IP, NAT Gateway).
- **Tắt** (stop) máy ảo dừng tiền giờ máy, nhưng **ổ đĩa và IP vẫn tính**. Chỉ **xóa** mới dừng hẳn.

### 3.5. Credit

**Credit** (tín dụng khuyến mãi) là tiền ảo AWS tặng, tự động trừ vào chi phí. Với tài khoản mới, credit chính là "ngân sách học tập" của bạn — tiêu hết là hết.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Free plan và Paid plan

Từ ngày 15/7/2025, khi đăng ký tài khoản mới, AWS cho chọn một trong hai gói. Thông tin dưới đây lấy từ [tài liệu *Choosing a plan*](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) và [trang AWS Free Tier](https://aws.amazon.com/free/) (kiểm tra 2026-10-31):

| | **Free plan** | **Paid plan** |
|---|---|---|
| Credit cho tài khoản mới | 100 USD khi tạo tài khoản + tối đa 100 USD nữa khi hoàn thành các hoạt động AWS gợi ý | Giống Free plan |
| Dịch vụ được dùng | **Một số** dịch vụ chọn lọc; không có những thứ có thể tiêu vượt credit (ví dụ Savings Plans, Reserved Instances, một số sản phẩm Marketplace) | Mọi dịch vụ |
| Có bị tính tiền không? | **Không** — không phát sinh phí trong lúc dùng | Có — phần vượt credit tính theo giá thường |
| Khi hết credit hoặc hết 6 tháng (cái nào đến trước) | **Tài khoản tự đóng**, mất quyền truy cập tài nguyên và dữ liệu. AWS giữ nội dung **90 ngày** rồi xóa vĩnh viễn. Trong 90 ngày đó có thể nâng lên Paid plan để lấy lại | Tài khoản không đóng |
| Khuyến mãi khác | Không được nhận thêm credit khuyến mãi khác | Được |

**Vì sao giáo trình chọn Free plan** (đã quyết định ở [Lộ trình §7](../00-ROADMAP/learning-roadmap.md#7-chiến-lược-kiểm-soát-chi-phí-aws)): người mới chắc chắn sẽ có lúc quên xóa tài nguyên. Free plan biến sai lầm đó thành "mất credit" thay vì "mất tiền thật".

**Đánh đổi phải biết trước:**

1. **Đồng hồ 6 tháng chạy từ ngày tạo tài khoản.** Tạo ở tuần 11 → hết hạn khoảng tuần 37. Đó là lý do không tạo sớm hơn.
2. **Credit hết = tài khoản đóng = dự án biến mất.** Credit không phải "miễn phí vô hạn". Bạn phải theo dõi số dư (§4.6).
3. **Một số hành động tự động nâng lên Paid plan**, theo tài liệu AWS: tham gia **AWS Organizations**, dựng **AWS Control Tower** landing zone, tham gia AWS Partner Network, mua gói Skill Builder Team… Vì vậy giáo trình **không** dùng Organizations (§4.5).
4. Muốn giữ dự án chạy để demo sau 6 tháng → phải chủ động nâng lên Paid plan (Billing → **Upgrade plan**). Khi đó credit còn lại vẫn được dùng tiếp, nhưng phần vượt sẽ tính tiền thật.

### 4.2. 🟥 Credit bị tiêu như thế nào?

Trên Free plan, bạn **vẫn phát sinh chi phí theo giá thường** — chỉ là chi phí đó được trừ vào credit thay vì vào thẻ. Ví dụ:

- **Public IPv4**: 0,005 USD/giờ cho mỗi địa chỉ, **dù đang dùng hay để không** ([VPC pricing](https://aws.amazon.com/vpc/pricing/), kiểm tra 2026-10-31). Một địa chỉ để cả tháng ≈ 0,005 × 24 × 30 = **3,6 USD credit**.
- **EC2**: theo tài liệu [EC2 Free Tier](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html), với tài khoản tạo từ 15/7/2025, các loại máy được đánh dấu *Free tier eligible* là `t3.micro`, `t3.small`, `t4g.micro`, `t4g.small`, `c7i-flex.large`, `m7i-flex.large`. "Eligible" nghĩa là **được phép chạy trên Free plan và trừ vào credit** — **không** còn là "750 giờ miễn phí mỗi tháng" như chính sách cũ trước 15/7/2025. Đừng nhầm với các tutorial cũ.
- Giá theo giờ của từng loại máy ở Singapore: tra trên [trang giá EC2 On-Demand](https://aws.amazon.com/ec2/pricing/on-demand/) hoặc [AWS Pricing Calculator](https://calculator.aws/) — bài [01](01-cloud-fundamentals.md) có bài tập ước tính chi phí dự án.

> 💡 **Quy tắc ngón tay cái của giáo trình:** 100 USD credit cho 6 tháng ≈ **16 USD mỗi tháng**. Dự án chính (1 EC2 `t3.small`, 1 Public IPv4, ổ 20 GiB) chạy 24/7 sẽ tiêu một phần lớn con số đó. Vì vậy: **tắt khi không học**, và từ tuần 15 dùng `terraform destroy` để xóa hẳn.

### 4.3. 🟥 Đăng ký tài khoản — các bước và chỗ hay vấp

Giao diện đăng ký thay đổi theo thời gian; thứ tự thường gặp là:

1. **Email + tên tài khoản** → nhận mã xác minh qua email. Dùng email bạn **sẽ còn dùng lâu dài** — đây là danh tính root, mất email là rất khó lấy lại tài khoản.
2. **Mật khẩu root**: dài, ngẫu nhiên, lưu trong trình quản lý mật khẩu.
3. **Thông tin liên hệ**: chọn loại *Personal*, điền địa chỉ bằng chữ không dấu nếu form báo lỗi.
4. **Thông tin thanh toán**: thẻ Visa/Mastercard hỗ trợ thanh toán quốc tế. AWS có thể **tạm giữ một khoản nhỏ** để xác minh thẻ rồi hoàn lại — đây không phải phí.
5. **Xác minh danh tính** qua SMS hoặc cuộc gọi.
6. **Chọn gói Support**: chọn **Basic Support** — gói miễn phí dành cho mọi khách hàng ([AWS Support plans](https://aws.amazon.com/premiumsupport/plans/), kiểm tra 2026-10-31). Các gói khác (Business Support+, Enterprise…) đều trả phí.
7. **Chọn Free plan.**
8. Chờ kích hoạt — thường vài phút, đôi khi lâu hơn. Nếu một dịch vụ báo "account not activated", đợi rồi thử lại.

### 4.4. 🟥 Bảo vệ root user

**MFA là bắt buộc.** Theo [tài liệu IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/enable-mfa-for-root.html) (kiểm tra 2026-10-31): mọi loại tài khoản AWS đều **yêu cầu** root user có MFA; nếu chưa bật, bạn phải đăng ký MFA trong vòng **14 ngày** kể từ lần đăng nhập console đầu tiên. Đừng chờ đến lúc bị nhắc — bật ngay trong buổi đầu.

Các loại MFA AWS hỗ trợ cho root, theo thứ tự khuyến nghị:

| Loại | Ví dụ | Ghi chú |
|---|---|---|
| **Passkey / security key** (FIDO) | Passkey trong Google Password Manager, Windows Hello, 1Password, Bitwarden; khóa YubiKey | AWS **khuyến nghị** — chống phishing tốt nhất |
| Ứng dụng xác thực (TOTP) | Google Authenticator, Microsoft Authenticator | Mã 6 số đổi mỗi 30 giây. Chấp nhận được |
| Token phần cứng TOTP | Thiết bị sinh mã | Ít dùng cho cá nhân |

**Việc chỉ root mới làm được** (theo [danh sách của AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-tasks.html)) — những thứ bạn có thể gặp:

- Đổi email, mật khẩu root; **đóng** tài khoản.
- **Bật quyền truy cập Billing cho IAM** (*Activate IAM Access*) — bạn sẽ làm ở lab.
- Khôi phục quyền khi admin IAM duy nhất lỡ tự gỡ quyền của mình.
- Sửa bucket policy S3 lỡ chặn tất cả mọi người.

**Quy tắc cho root:**

- ❌ **Không bao giờ tạo access key cho root.**
- ❌ Không dùng root cho việc hằng ngày, kể cả "chỉ xem một chút".
- ✅ Cập nhật số điện thoại và email liên hệ chính xác — đây là đường khôi phục khi mất thiết bị MFA.
- ✅ Thêm **alternate contacts** (liên hệ thay thế) cho Billing và Security — có thể dùng chính email của bạn.

### 4.5. 🟥 Người dùng quản trị hằng ngày: IAM user `phuong-admin`

Sau khi bảo vệ root, bạn tạo một danh tính để làm việc hằng ngày:

- IAM user `phuong-admin`, thuộc group `admins`, group được gắn policy `AdministratorAccess`.
- Bật MFA cho `phuong-admin`.
- Đăng nhập bằng đường dẫn riêng của tài khoản (`https://<account-id>.signin.aws.amazon.com/console`).

Chi tiết từng bước, policy là gì, vì sao gắn quyền vào **group** chứ không vào user: [bài 02 — IAM](02-iam.md).

**Vì sao không dùng IAM Identity Center** (dịch vụ AWS khuyến nghị cho đăng nhập tập trung)? Đây là đánh đổi có chủ đích:

| Lựa chọn | Vấn đề với tài khoản Free plan đơn lẻ |
|---|---|
| Identity Center **organization instance** (bản đầy đủ) | Cần **AWS Organizations** → theo tài liệu AWS, tham gia Organizations sẽ **tự động nâng tài khoản lên Paid plan** |
| Identity Center **account instance** (bản gắn với một tài khoản) | Theo [tài liệu Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/account-instances-identity-center.html), account instance **không hỗ trợ permission set**, nên **không cấp được quyền vào tài khoản AWS** — chỉ dùng cho ứng dụng |
| **IAM user + MFA** | Đơn giản, đủ an toàn cho tài khoản học tập khi kết hợp MFA và `aws login` (không có access key dài hạn) |

Ở công ty, bạn sẽ gần như luôn đăng nhập qua Identity Center hoặc SSO của công ty. Hiểu vì sao ở đây chọn khác là một câu trả lời phỏng vấn tốt.

### 4.6. 🟥 Lưới an toàn chi phí: 4 lớp

| Lớp | Công cụ | Làm gì cho bạn | Chi phí |
|---|---|---|---|
| 1 | **Trang chủ Billing and Cost Management** | Hiển thị số dư credit, ngày hết hạn gói, số ngày còn lại | Miễn phí |
| 2 | **Email tự động của Free plan** | AWS gửi email định kỳ về số dư credit và khi sắp hết hạn gói ([tài liệu](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/tracking-free-tier-usage.html)) | Miễn phí |
| 3 | **Free Tier usage alerts** | Email khi một dịch vụ vượt **85%** hạn mức miễn phí. Bật sẵn cho tài khoản đơn lẻ; đổi email nhận tại **Billing preferences → Alert preferences** | Miễn phí |
| 4 | **AWS Budgets** | Email khi chi phí thực tế hoặc **dự báo** vượt ngưỡng bạn đặt | Theo [trang giá Budgets](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/): **theo dõi và gửi thông báo miễn phí**. Chỉ tốn tiền với *action-enabled budget* thứ ba trở đi (0,10 USD/ngày) và *budget report* gửi định kỳ (0,01 USD/báo cáo) — bài này không dùng hai thứ đó |

**Chọn đúng loại chi phí cho budget — điểm hay sai nhất:**

Khi tạo cost budget theo kiểu *Customize (advanced)*, mục **Advanced options** cho chọn cách tổng hợp chi phí ([tài liệu tạo cost budget](https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html)):

| Lựa chọn | Nghĩa | Dùng cho Free plan? |
|---|---|---|
| **Unblended costs** | Chi phí thực tế theo giá tại thời điểm dùng — **trước** khi trừ credit | ✅ **Chọn cái này.** Nó cho bạn thấy credit đang bị tiêu nhanh cỡ nào |
| **Net unblended costs** | Chi phí **sau khi** trừ mọi chiết khấu và **credit** | ❌ Trên Free plan con số này luôn gần 0 → budget không bao giờ cảnh báo |
| Amortized / net amortized, blended | Dành cho Savings Plans/Reserved Instances, nhiều tài khoản | Không liên quan |

Cấu hình khuyến nghị cho giáo trình:

- Tên `taskhub-monthly`, chu kỳ **Monthly**, **Recurring**, số tiền cố định **15 USD** (≈ 100 USD / 6 tháng, làm tròn xuống).
- Ba ngưỡng cảnh báo: **50% Actual**, **80% Actual**, **100% Forecasted**.
- Gửi tới email của bạn — người nhận phải **xác minh email** trước khi nhận được cảnh báo.

> ⚠️ Budget **không chặn** việc tiêu tiền — nó chỉ **báo**. Việc xóa tài nguyên vẫn là của bạn. (Budget actions có thể tự động áp policy/tắt máy, nhưng đó là 🟦, không cần lúc này.)

**Template *Zero spend budget*:** template này báo khi chi phí vượt hạn mức Free Tier. Trên Free plan, mọi thứ bạn chạy đều trừ vào credit, nên hãy dựa vào budget `taskhub-monthly` ở trên làm cảnh báo chính, và dùng số dư credit trên trang Billing để đối chiếu.

**Cost Explorer** — biểu đồ chi phí theo ngày, theo dịch vụ, theo region, theo tag. Xem trên console là đủ. Lần đầu bật có thể mất đến 24 giờ mới có dữ liệu. ⚠️ Gọi **API** Cost Explorer (`aws ce ...`) **tốn 0,01 USD mỗi request** ([trang giá Cost Explorer](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/), kiểm tra 2026-10-31) — đừng đưa lệnh đó vào script chạy theo vòng lặp hay cron.

**Quyền xem Billing của IAM user:** mặc định, **IAM user và role không vào được trang Billing**, kể cả khi có policy cho phép. Root phải bật một lần: menu tên tài khoản → **Account** → mục **IAM User and Role Access to Billing Information** → **Edit** → tick **Activate IAM Access** → **Update** ([tài liệu IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_billing.html)). Sau đó `phuong-admin` (có `AdministratorAccess`) xem được Billing mà không cần đăng nhập root nữa.

### 4.7. 🟥 Chọn region `ap-southeast-1`

Giáo trình dùng **Asia Pacific (Singapore) — `ap-southeast-1`** cho mọi thứ:

- Gần Việt Nam → độ trễ thấp khi bạn thao tác và demo.
- Có đủ mọi dịch vụ giáo trình cần.
- Thống nhất một region → dễ dọn dẹp, dễ đọc hóa đơn.

**Lỗi kinh điển:** console mặc định có thể mở ở **US East (N. Virginia) `us-east-1`**. Bạn tạo EC2 ở đó, hôm sau mở console thấy ở Singapore "không có gì" và quên mất máy kia vẫn chạy. Luôn liếc **ô chọn region góc trên bên phải** trước khi tạo tài nguyên.

Ngoại lệ hợp lý: một số dịch vụ là **global** (IAM, Billing, Route 53) — console có thể hiển thị "Global" hoặc tự chuyển sang `us-east-1` khi bạn mở chúng. Đó là bình thường.

### 4.8. 🟥 Những thứ âm thầm tốn tiền

| Thứ | Vì sao dễ quên | Cách phát hiện / phòng tránh |
|---|---|---|
| **Public IPv4 / Elastic IP** | 0,005 USD/giờ mỗi địa chỉ, **kể cả khi không gắn vào máy nào** | EC2 → *Elastic IPs*: không được còn địa chỉ thừa. Release ngay khi không dùng |
| **NAT Gateway** | Tính theo giờ (ví dụ 0,045 USD/giờ ở US East Ohio theo [VPC pricing](https://aws.amazon.com/vpc/pricing/)) **cộng** phí theo GB dữ liệu đi qua. Để quên một tháng ≈ 32 USD — gần hết ngân sách 2 tháng | Dự án chính **không dùng NAT Gateway**. Chỉ dựng trong lab ngắn tuần 14 rồi xóa |
| **EBS volume còn sót** | Terminate máy nhưng ổ đĩa phụ (hoặc ổ gốc nếu tắt *Delete on termination*) vẫn còn và vẫn tính theo GB-tháng | EC2 → *Volumes*: lọc trạng thái **available** = ổ không gắn vào đâu |
| **EBS snapshot** | Snapshot/AMI tự tạo còn lại sau lab | EC2 → *Snapshots* (chọn *Owned by me*), *AMIs* |
| **Máy EC2 đang `stopped`** | Không tính giờ máy, **nhưng** ổ đĩa vẫn tính; Elastic IP gắn vào vẫn tính | Terminate nếu không cần nữa |
| **Load balancer (ALB) không có traffic** | ALB tính theo giờ dù không có ai truy cập | Lab tuần 14: xóa ALB ngay sau buổi học |
| **RDS** | Tính theo giờ + lưu trữ + **snapshot cuối khi xóa** | Lab tuần 14: xóa instance, quyết định có giữ snapshot không, rồi xóa snapshot |
| **CloudWatch Logs không đặt retention** | Mặc định log group giữ **vĩnh viễn**, phí lưu trữ tăng dần | Luôn đặt retention (dự án dùng 7 ngày) |
| **Data transfer ra Internet** | Tính theo GB khi dữ liệu đi **ra** khỏi AWS | Không tải file lớn từ EC2 về máy liên tục; không để public bucket bị hotlink |
| **Tài nguyên ở region khác** | Bạn không nhìn thấy khi console đang ở Singapore | **AWS Global View** (§4.9) |

### 4.9. 🟥 Thói quen dọn dẹp hằng tuần (15 phút, mỗi Chủ nhật)

Mọi tài nguyên giáo trình đều gắn tag `Project=taskhub`, `Env=dev`, `Owner=<tên bạn>`, `ManagedBy=manual` (từ v4 đổi thành `terraform`). Tag là thứ giúp bạn **tìm lại** tài nguyên.

| Bước | Công cụ | Làm gì |
|---|---|---|
| 1 | **Billing and Cost Management → Home** | Số dư credit còn bao nhiêu? Tuần này tiêu bao nhiêu so với tuần trước? |
| 2 | **Cost Explorer** (console) | Nhóm theo *Service* rồi theo *Region*: có dịch vụ/region lạ không? |
| 3 | **AWS Global View** | Xem tổng hợp instance, volume, Elastic IP, NAT gateway, VPC… **trên mọi region** trong một màn hình ([tài liệu](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/global-view.html)). Chỉ xem, không sửa được |
| 4 | **Resource Groups & Tag Editor → Tag Editor** | Tìm tài nguyên theo tag `Project=taskhub` ở các region đã chọn; phát hiện tài nguyên **thiếu tag** (dấu hiệu tạo vội rồi quên) |
| 5 | Ghi nhật ký | Một dòng trong `devops-journey`: ngày, số dư credit, đã xóa gì |

🟦 **AWS Resource Explorer** là dịch vụ tìm kiếm tài nguyên trên nhiều region bằng chỉ mục (index) — mạnh hơn Tag Editor nhưng phải bật và cấu hình trước. Biết tên là đủ.

### 4.10. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại |
|---|---|
| IAM user, group, MFA, quyền tối thiểu | [Bài 02 — IAM](02-iam.md) |
| `aws login`, profile `taskhub`, không access key dài hạn | [Bài 06 — AWS CLI](06-aws-cli.md) |
| Public IPv4, NAT Gateway, vì sao dự án không dùng NAT | [Bài 03 — VPC](03-vpc-networking.md) |
| Tag, dọn dẹp, ước tính chi phí từng lab | Mọi lab AWS; [dự án v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) |
| CloudTrail event history | [Bài 01](01-cloud-fundamentals.md), [bài 10 — CloudWatch](10-cloudwatch.md) |
| `terraform destroy` để tiết kiệm credit | Module 07 (tuần 15–16) |
| Rà soát bảo mật tài khoản AWS | Module 10 (tuần 21) |

---

## 5. Ví dụ thực tế

**Chuyện 1 — "Tôi đã stop máy rồi mà sao vẫn tốn?"**
Một bạn học xong buổi tối thì *stop* EC2 và nghĩ đã an toàn. Cuối tháng credit vẫn giảm đều. Nguyên nhân: ổ EBS 20 GiB của máy vẫn tính theo GB-tháng, và một Elastic IP đã gắn vào máy (tạo để IP không đổi) vẫn tính 0,005 USD/giờ. Bài học: *stop* ≠ *xóa*. Muốn dừng hẳn chi phí thì terminate máy và release Elastic IP; muốn giữ nhưng rẻ thì chấp nhận phần ổ đĩa và **không** dùng Elastic IP khi chưa cần.

**Chuyện 2 — NAT Gateway quên xóa sau lab.**
Lab kiến trúc "chuẩn" có private subnet + NAT Gateway. Học xong, xóa EC2 và RDS nhưng quên NAT Gateway (nằm trong console VPC, không nằm trong EC2). Một tháng sau ≈ 32 USD tiền giờ + phí dữ liệu. Với Free plan, đó là gần 1/3 credit ban đầu biến mất. Lab tuần 14 của giáo trình vì vậy có **checklist xóa theo thứ tự** và lệnh CLI kiểm tra không còn NAT Gateway nào.

**Chuyện 3 — Access key lên GitHub.**
Kịch bản phổ biến trong các báo cáo bảo mật: một developer commit file chứa access key vào repo public. Trong vòng vài phút, bot quét GitHub tìm thấy và dùng key dựng hàng loạt máy lớn để đào tiền mã hóa. Phòng tránh ở giáo trình này: **không có access key dài hạn nào trên laptop** (dùng `aws login`, [bài 06](06-aws-cli.md)) và **không có access key nào trong GitHub** (pipeline dùng OIDC, [dự án v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md)).

---

## 6. Sơ đồ kiến trúc

**Danh tính trong tài khoản của bạn:**

```text
┌──────────────────────── AWS account 111122223333 (Free plan) ────────────────────────┐
│                                                                                     │
│  Root user (email đăng ký)                                                           │
│   ├─ MFA: passkey ✅          ├─ Access key: KHÔNG CÓ ✅                              │
│   └─ Chỉ dùng: bật IAM access to Billing, đổi email/mật khẩu, đóng tài khoản        │
│                                                                                     │
│  IAM group "admins" ── policy AdministratorAccess                                   │
│   └─ IAM user "phuong-admin" ── MFA ✅                                              │
│        ├─ Console: https://111122223333.signin.aws.amazon.com/console               │
│        └─ CLI (bài 06): aws login → credential tạm thời, profile "taskhub"          │
│                                                                                     │
│  (v2) IAM role "taskhub-ec2-role" ── gắn vào EC2                                    │
│  (v3) IAM role "taskhub-github-deploy" ── GitHub Actions nhận qua OIDC             │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

**Dòng chảy chi phí trên Free plan:**

```text
 Tài nguyên chạy ──► Chi phí theo giá thường (unblended) ──► Trừ vào credit ──► Bạn trả 0 USD
        │                       │                                  │
        │                       ▼                                  ▼
        │            Budget "taskhub-monthly" so ngưỡng   Số dư credit giảm ──► = 0 hoặc hết 6 tháng
        │            50% / 80% Actual, 100% Forecasted              │
        │                       │                                  ▼
        │                       ▼                      Tài khoản tự đóng → 90 ngày để nâng cấp
        │                Email cảnh báo                 → sau đó XÓA vĩnh viễn
        ▼
 Bạn xóa tài nguyên (budget không tự xóa giúp bạn)
```

---

## 7. Các câu lệnh cần biết

Bài này làm chủ yếu trên console. Các lệnh dưới đây **chỉ chạy được sau khi cài và đăng nhập AWS CLI ở [bài 06](06-aws-cli.md)** — ghi lại ở đây để quay lại dùng trong thói quen dọn dẹp hằng tuần.

| Lệnh | Mục đích | Tốn tiền? |
|---|---|---|
| `aws sts get-caller-identity` | "Tôi đang là ai, ở tài khoản nào?" | Không |
| `aws freetier get-account-plan-state` | Loại gói, trạng thái, credit còn lại, ngày hết hạn | Không (theo tài liệu Free Tier) |
| `aws freetier list-account-activities` | Các hoạt động giúp nhận thêm credit | Không |
| `aws budgets describe-budgets --account-id <id>` | Liệt kê budget đã tạo | Không |
| `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true` | Loại máy được dùng trên Free plan | Không |
| `aws ec2 describe-addresses` | Elastic IP đang giữ | Không |
| ⚠️ `aws ce get-cost-and-usage ...` | Chi phí theo dịch vụ | **0,01 USD mỗi lần gọi** |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `aws sts get-caller-identity`

```bash
# [WSL] — sau bài 06
aws sts get-caller-identity
```

```json
{
    "UserId": "AIDAEXAMPLEUSERID1234",
    "Account": "111122223333",
    "Arn": "arn:aws:iam::111122223333:user/phuong-admin"
}
```

*(Đầu ra minh họa.)* Đọc dòng `Arn`: nếu thấy `:root` thay vì `:user/phuong-admin` → bạn đang dùng **root** — dừng lại và sửa cấu hình. Lệnh này không cần quyền gì đặc biệt và nên là **lệnh đầu tiên** mỗi khi mở terminal làm việc với AWS.

### 8.2. `aws freetier get-account-plan-state`

```bash
aws freetier get-account-plan-state \
  --query "{type:accountPlanType,status:accountPlanStatus,credits:accountPlanRemainingCredits.amount,expires:accountPlanExpirationDate}" \
  --output table
```

```text
-------------------------------------------------------------
|                    GetAccountPlanState                    |
+---------+-------------------------------+---------+--------+
| credits |            expires            | status  | type   |
+---------+-------------------------------+---------+--------+
|  87.42  |  2027-07-04T00:00:00+00:00    |  ACTIVE |  FREE  |
+---------+-------------------------------+---------+--------+
```

*(Đầu ra minh họa — số và ngày là ví dụ.)*

| Phần | Ý nghĩa |
|---|---|
| `accountPlanType` | `FREE` hoặc `PAID` |
| `accountPlanStatus` | `NOT_STARTED`, `ACTIVE`, `EXPIRED` |
| `accountPlanRemainingCredits.amount` | Credit còn lại (USD) |
| `accountPlanExpirationDate` | Ngày gói hết hạn |
| `--query` | Biểu thức JMESPath chọn và đổi tên trường — học kỹ ở [bài 06](06-aws-cli.md) |

Nếu lệnh báo lỗi endpoint/region, thêm `--region us-east-1` (nhiều API thanh toán chạy ở endpoint `us-east-1`) và ghi lại hiện tượng vào nhật ký.

### 8.3. `aws freetier list-account-activities`

```bash
aws freetier list-account-activities \
  --filter-activity-statuses NOT_STARTED IN_PROGRESS \
  --query 'activities[].{Title:title,Credit:reward.credit.amount,Status:status}' \
  --output table
```

Liệt kê các hoạt động AWS gợi ý (khám phá một số dịch vụ) kèm số credit thưởng. Đây là cách **chính thức** để biết hoạt động nào được tính — đừng tin danh sách trên blog. Chỉ làm những hoạt động **có ích cho lộ trình** và tự đọc phần chi phí của hoạt động đó trước khi làm.

### 8.4. ⚠️ `aws ce get-cost-and-usage`

```bash
# ⚠️ Mỗi lần chạy tốn 0,01 USD — chỉ chạy tay khi cần, không đưa vào cron
aws ce get-cost-and-usage \
  --time-period Start=2027-01-01,End=2027-02-01 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table
```

| Tham số | Ý nghĩa |
|---|---|
| `--time-period Start=…,End=…` | Khoảng thời gian; `End` **không** tính (ngày đầu tháng sau) |
| `--granularity MONTHLY` | Gộp theo tháng (`DAILY` để xem theo ngày) |
| `--metrics UnblendedCost` | Chi phí **trước** credit — cùng lý do chọn *Unblended* cho budget |
| `--group-by Type=DIMENSION,Key=SERVICE` | Tách theo dịch vụ (đổi `SERVICE` thành `REGION` để tìm tài nguyên ở region lạ) |

Trong thói quen hằng tuần, dùng **Cost Explorer trên console** (miễn phí). Lệnh này chỉ để biết rằng có thể tự động hóa — và tự động hóa nó có giá.

### 8.5. `aws ec2 describe-instance-types` với bộ lọc Free Tier

```bash
aws ec2 describe-instance-types \
  --region ap-southeast-1 \
  --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[*].[InstanceType]" \
  --output text | sort
```

Lệnh chính thức trong [tài liệu EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html). Chạy lệnh này **trước** khi chọn loại máy ở bài 04 — danh sách có thể thay đổi so với lúc giáo trình được viết.

---

## 9. Bài thực hành từng bước

> **Ước tính chi phí:** 0 USD. Bài này không tạo tài nguyên tính phí nào (IAM, Budgets dạng cảnh báo email, cài đặt Billing đều miễn phí).
> **Thời gian:** 1,5–2 giờ. Làm liền một mạch, đừng bỏ dở giữa chừng ở trạng thái root chưa có MFA.

Tạo file ghi chép `~/projects/devops-journey/week11/aws-account-setup.md` (repo nhật ký của bạn). **Tuyệt đối không ghi mật khẩu, mã MFA, số thẻ** vào file này — chỉ ghi *đã làm gì, lúc nào*.

### Bước 1 — Chuẩn bị `[PowerShell]`/trình duyệt

- Trình quản lý mật khẩu sẵn sàng (Bitwarden, 1Password, hoặc trình quản lý của trình duyệt).
- Điện thoại có ứng dụng xác thực, hoặc thiết bị hỗ trợ passkey.
- Đọc lại [§4.1](#41--free-plan-và-paid-plan): bạn hiểu tài khoản sẽ tự đóng sau 6 tháng hoặc khi hết credit.

### Bước 2 — Đăng ký `[AWS Console]`

Làm theo [§4.3](#43--đăng-ký-tài-khoản--các-bước-và-chỗ-hay-vấp). Ở bước chọn gói: **Free plan**. Ở bước support: **Basic**.

Ghi vào nhật ký: ngày tạo tài khoản → tự tính **ngày hết hạn dự kiến** (+6 tháng).

### Bước 3 — MFA cho root `[AWS Console]`

1. Đăng nhập bằng **Root user**.
2. Menu tên tài khoản (góc trên phải) → **Security credentials**.
3. Mục **Multi-factor authentication (MFA)** → **Assign MFA device**.
4. Chọn **Passkey or security key** (khuyến nghị) hoặc **Authenticator app** → làm theo hướng dẫn.
5. Đăng xuất, đăng nhập lại bằng root để chắc chắn MFA hoạt động.

Kiểm tra trên cùng trang: mục **Access keys** phải **trống**. Nếu có key nào → xóa ngay.

### Bước 4 — Thông tin liên hệ `[AWS Console]`

Menu tên tài khoản → **Account**:

- Kiểm tra **Contact information** đúng số điện thoại.
- **Alternate contacts**: điền Billing và Security (email của bạn là được).

### Bước 5 — Bật quyền Billing cho IAM `[AWS Console]` (root)

Vẫn trang **Account** → **IAM User and Role Access to Billing Information** → **Edit** → tick **Activate IAM Access** → **Update**. Thông báo *IAM user/role access to billing information is activated* xuất hiện.

### Bước 6 — Tạo `phuong-admin` `[AWS Console]` (root, lần cuối)

Làm phần **lab của [bài 02](02-iam.md) mục "Tạo admin hằng ngày"** nếu bạn đã đọc bài đó. Nếu chưa, làm bản tối thiểu sau rồi quay lại bài 02 để hiểu từng bước:

1. Mở **IAM** → **User groups** → **Create group**: tên `admins`, gắn policy **AdministratorAccess**.
2. **Users** → **Create user**: tên `phuong-admin`, tick **Provide user access to the AWS Management Console**, chọn **I want to create an IAM user**, đặt mật khẩu mạnh (lưu vào trình quản lý mật khẩu), thêm vào group `admins`.
3. Ghi lại **Console sign-in URL** dạng `https://111122223333.signin.aws.amazon.com/console`.
4. **Đăng xuất root.**
5. Đăng nhập bằng `phuong-admin` qua URL trên → menu tên user → **Security credentials** → **Assign MFA device** → bật MFA.

Từ giờ, **mọi bước sau đều làm bằng `phuong-admin`**.

### Bước 7 — Chọn region `[AWS Console]`

Ô chọn region góc trên phải → **Asia Pacific (Singapore) ap-southeast-1**. Kiểm tra: mở EC2 → trên dashboard thấy tên region Singapore.

### Bước 8 — Cảnh báo Free Tier `[AWS Console]`

**Billing and Cost Management** → **Billing preferences** → **Alert preferences** → **Edit**:

- Tick **Receive AWS Free Tier alerts** (thường đã bật sẵn).
- Điền email nhận cảnh báo → **Update**.

Nếu `phuong-admin` không vào được trang Billing → xem lại Bước 5.

### Bước 9 — Budget `taskhub-monthly` `[AWS Console]`

**Billing and Cost Management** → **Budgets** → **Create budget**:

1. **Customize (advanced)** → **Cost budget** → **Next**.
2. Tên `taskhub-monthly` · Period **Monthly** · **Recurring budget** · Budgeting method **Fixed** · Amount **15** (USD).
3. **Budget scope**: *All AWS services*. **Advanced options** → chọn **Unblended costs** (đọc lại [§4.6](#46--lưới-an-toàn-chi-phí-4-lớp) nếu không nhớ vì sao).
4. **Next** → **Add an alert threshold** ba lần:

   | Threshold | Loại | Trigger |
   |---|---|---|
   | 50 | % of budgeted amount | Actual |
   | 80 | % of budgeted amount | Actual |
   | 100 | % of budgeted amount | Forecasted |

   Mỗi ngưỡng: **Email recipients** = email của bạn.
5. Bỏ qua **Attach actions** → **Create budget**.
6. Mở hộp thư, **xác minh email** nếu AWS gửi yêu cầu.

### Bước 10 — Làm quen trang Billing `[AWS Console]`

Mở **Billing and Cost Management → Home** và tìm, ghi vào nhật ký:

- Credit còn lại, ngày hết hạn gói, số ngày còn lại.
- Mục **Free Tier** / *Recommended actions* (có thể trống vì chưa dùng gì).
- **Cost Explorer**: bật nếu được hỏi (dữ liệu có thể mất đến 24 giờ mới hiện).

### Bước 11 — Thử CloudTrail event history `[AWS Console]`

Mở **CloudTrail** → **Event history** (region Singapore, và thử cả *US East N. Virginia* vì sự kiện IAM/đăng nhập là global và thường được ghi ở `us-east-1`). Tìm các sự kiện bạn vừa làm: `ConsoleLogin`, `CreateUser`, `CreateGroup`, `AttachGroupPolicy`. Đây là "camera an ninh" miễn phí của tài khoản ([§12](#12-đọc-log-và-xử-lý-lỗi)).

### Bước 12 — Danh sách ảnh chụp màn hình cho nhật ký

Chụp và lưu vào `week11/` (che số tài khoản nếu repo public):

- [ ] Trang **Security credentials** của root: MFA đã gán, **không có access key**.
- [ ] Trang **Security credentials** của `phuong-admin`: MFA đã gán.
- [ ] Budget `taskhub-monthly` với 3 ngưỡng cảnh báo.
- [ ] **Billing preferences** → Free Tier alerts đã bật.
- [ ] Trang Billing Home: số dư credit ngày đầu tiên.

### Bước 13 — Dọn dẹp

Không có tài nguyên tính phí nào được tạo. Việc duy nhất: **đăng xuất root** và cất thông tin root vào trình quản lý mật khẩu.

---

## 10. Kết quả mong đợi

- Đăng nhập root yêu cầu MFA; root không có access key.
- `phuong-admin` đăng nhập qua URL riêng của tài khoản, có MFA, xem được trang Billing.
- Budget `taskhub-monthly` (Unblended, 15 USD/tháng, 3 ngưỡng) đã tạo; email nhận cảnh báo đã xác minh.
- Free Tier alerts bật, gửi về email của bạn.
- Console mặc định ở `ap-southeast-1`.
- Nhật ký `week11/aws-account-setup.md` có ngày tạo tài khoản, ngày hết hạn dự kiến, số dư credit ban đầu và các ảnh chụp.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Thẻ bị từ chối ở bước thanh toán | Thẻ chưa bật thanh toán quốc tế/online, hoặc ngân hàng chặn giao dịch xác minh | Bật thanh toán quốc tế trong app ngân hàng, thử lại; thử thẻ khác |
| Không nhận được SMS/cuộc gọi xác minh | Định dạng số sai, nhà mạng chặn | Chọn đúng mã quốc gia +84, bỏ số 0 đầu; thử phương thức còn lại (SMS ↔ gọi) |
| Dịch vụ báo tài khoản chưa kích hoạt | Kích hoạt chưa xong | Đợi rồi thử lại; kiểm tra email từ AWS |
| `phuong-admin` mở Billing thấy *access denied* dù có `AdministratorAccess` | Root chưa bật **Activate IAM Access** | Đăng nhập root, làm Bước 5 |
| Budget không bao giờ gửi cảnh báo | Chọn *Net unblended costs* (luôn ≈ 0 trên Free plan), hoặc email chưa xác minh | Sửa budget sang *Unblended*; kiểm tra hộp thư/spam |
| "Máy EC2 của tôi biến mất!" | Console đang ở region khác | Đổi region; dùng AWS Global View |
| Một dịch vụ báo không dùng được trên tài khoản | Free plan chỉ có một số dịch vụ | Kiểm tra dịch vụ có trên Free plan không ([aws.amazon.com/free](https://aws.amazon.com/free/)); giáo trình chỉ dùng dịch vụ phổ biến. **Đừng** nâng lên Paid plan chỉ vì tò mò |
| Mất điện thoại có MFA | — | Dùng luồng khôi phục bằng email + số điện thoại đã đăng ký (lý do phải cập nhật thông tin liên hệ ở Bước 4); passkey đồng bộ ít gặp vấn đề này hơn |

---

## 12. Đọc log và xử lý lỗi

Với tài khoản AWS, "log" quan trọng nhất ở giai đoạn này là **CloudTrail event history** và **trang Bills**.

### 12.1. CloudTrail event history — ai đã làm gì?

Theo [tài liệu CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html): CloudTrail **bật sẵn**, event history lưu **90 ngày** các *management event* (sự kiện quản lý: tạo/sửa/xóa tài nguyên, đăng nhập) **theo từng region**, xem miễn phí. Mỗi lần tìm kiếm chỉ trong **một** region và **một** thuộc tính lọc.

Cách đọc một sự kiện (minh họa, đã rút gọn):

```json
{
  "eventTime": "2027-01-04T02:15:31Z",
  "eventSource": "iam.amazonaws.com",
  "eventName": "CreateUser",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "203.0.113.25",
  "userIdentity": { "type": "Root", "arn": "arn:aws:iam::111122223333:root" },
  "requestParameters": { "userName": "phuong-admin" }
}
```

| Trường | Trả lời câu hỏi |
|---|---|
| `eventTime` | Lúc nào (UTC — cộng 7 giờ ra giờ Việt Nam) |
| `eventSource` + `eventName` | Dịch vụ nào, hành động gì |
| `userIdentity` | **Ai** — `Root`, `IAMUser`, `AssumedRole`… |
| `sourceIPAddress` | Từ đâu (IP lạ = đáng ngờ) |
| `awsRegion` | Region nơi sự kiện được ghi |

**Quy tắc phát hiện bất thường:** sau tuần này, bạn **không bao giờ** nên thấy `userIdentity.type = Root` nữa, trừ khi chính bạn vừa làm việc chỉ root mới làm được. Thấy `Root` lạ = đổi mật khẩu root ngay và kiểm tra toàn bộ tài khoản.

### 12.2. Trang Bills — tiền đi đâu?

**Billing and Cost Management → Bills**: chi phí tháng hiện tại tách theo **dịch vụ → region → loại sử dụng** (usage type). Khi credit tụt bất thường:

1. Tìm dịch vụ có chi phí lớn nhất.
2. Mở xuống region — có phải Singapore không?
3. Đọc **usage type** (ví dụ chứa `NatGateway-Hours`, `PublicIPv4`, `EBS:VolumeUsage`) → biết loại tài nguyên.
4. Sang console dịch vụ đó, **đúng region**, tìm tài nguyên và xóa.
5. Ghi một mục vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md): triệu chứng (credit giảm X), bằng chứng (dòng nào trong Bills), nguyên nhân, cách sửa, cách phòng.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Free plan và Paid plan khác nhau ở những điểm nào? Chuyện gì xảy ra với tài khoản Free plan khi hết credit?
2. Sau khi tài khoản Free plan tự đóng, bạn còn bao nhiêu ngày để lấy lại dữ liệu và bằng cách nào?
3. "Instance type Free tier eligible" nghĩa là gì với tài khoản tạo sau 15/7/2025? Khác gì chính sách cũ?
4. Kể ba hành động sẽ **tự động nâng** tài khoản Free plan lên Paid plan. Điều này ảnh hưởng thế nào đến việc chọn cách đăng nhập (IAM user hay Identity Center)?
5. Vì sao không bao giờ tạo access key cho root? Kể hai việc **chỉ root** mới làm được.
6. Loại MFA nào AWS khuyến nghị cho root, và vì sao nó tốt hơn mã 6 số?
7. Bạn tạo budget trên Free plan nhưng chưa bao giờ nhận được cảnh báo dù đã chạy EC2 cả tuần. Hai nguyên nhân khả dĩ là gì?
8. Budgets có tốn tiền không? Trường hợp nào thì tốn?
9. Gọi `aws ce get-cost-and-usage` mỗi 5 phút bằng cron trong một tháng tốn khoảng bao nhiêu? Có cách nào xem chi phí miễn phí?
10. Vì sao `phuong-admin` có `AdministratorAccess` mà vẫn không xem được Billing? Ai sửa được và sửa ở đâu?
11. Kể năm thứ vẫn tốn tiền khi bạn đã *stop* hết máy EC2.
12. Bạn tạo EC2 hôm qua, hôm nay mở console không thấy. Hai khả năng và cách kiểm tra mỗi khả năng?
13. CloudTrail event history lưu bao lâu, có mất phí không, và giới hạn của nó khi tìm kiếm là gì?
14. Một sự kiện CloudTrail có `userIdentity.type = Root` lúc 3 giờ sáng từ IP nước ngoài. Bạn làm gì trước tiên?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/00-solutions.md](solutions/00-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Ngân sách credit.** Bạn có 100 USD credit (chưa tính phần thưởng thêm) và 6 tháng. Dùng [AWS Pricing Calculator](https://calculator.aws/) (không cần đăng nhập vào tài khoản, không tạo tài nguyên) để ước tính chi phí tháng ở `ap-southeast-1` của: 1 EC2 `t3.small` Linux On-Demand, 1 ổ gp3 20 GiB, 1 Public IPv4. Tính cho hai kịch bản: chạy 24/7 và chạy 4 giờ/ngày × 6 ngày/tuần. Với mỗi kịch bản, credit đủ dùng bao nhiêu tháng? Kết luận cho thói quen học của bạn.

**Bài 2 — Thiết kế budget thứ hai.** Thiết kế (trên giấy, chưa tạo) một budget **chỉ theo dõi** dịch vụ EC2 ở region Singapore, ngưỡng 8 USD/tháng. Dùng những filter nào? Chọn loại chi phí nào? Vì sao budget này hữu ích hơn budget tổng khi bạn bắt đầu bài 04?

**Bài 3 — Kịch bản sự cố.** Viết một runbook ngắn (≤ 15 dòng) cho tình huống: "Nhận email budget 80% vào ngày 10 của tháng." Các bước tìm nguyên nhân phải dùng công cụ cụ thể của bài này, theo thứ tự.

**Bài 4 — Đánh đổi danh tính.** Viết một ADR ngắn (theo [mẫu ADR](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr)) cho quyết định "Dùng IAM user + MFA thay vì IAM Identity Center cho tài khoản học tập". Phải có ít nhất một hệ quả tiêu cực và một điều kiện khiến bạn đổi quyết định.

**Bài 5 — Kiểm tra region.** Sau bài 04 (khi đã có EC2), dùng AWS Global View chụp màn hình chứng minh **không** có instance, volume, Elastic IP nào ở region khác ngoài Singapore.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được bằng lời của mình: credit bị trừ thế nào, khi nào tài khoản đóng, và 90 ngày sau đó là gì.
- [ ] Root có MFA, không có access key; bạn không đăng nhập root nữa kể từ khi tạo `phuong-admin`.
- [ ] `phuong-admin` có MFA và xem được Billing.
- [ ] Budget dùng **Unblended costs** và bạn giải thích được vì sao không dùng *Net unblended*.
- [ ] Kể được ít nhất 6 thứ âm thầm tốn tiền và nơi tìm chúng trên console.
- [ ] Đọc được một sự kiện CloudTrail: ai, làm gì, khi nào, từ đâu.
- [ ] Thói quen dọn dẹp hằng tuần được ghi vào lịch học.

---

## Nguồn tham khảo

| Vai trò | Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|---|
| Chính | [AWS Billing — Choosing a plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Free plan vs Paid plan, đóng tài khoản, 90 ngày, tự nâng cấp | 2026-10-31 |
| Chính | [AWS Free Tier](https://aws.amazon.com/free/) | Tổng quan gói, credit | 2026-10-31 |
| Chính | [Tracking your AWS Free Tier usage](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/tracking-free-tier-usage.html) | Theo dõi credit, email cảnh báo, Free Tier alerts 85% | 2026-10-31 |
| Chính | [EC2 — Track your Free Tier usage](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Loại máy eligible, lệnh lọc `free-tier-eligible` | 2026-10-31 |
| Chính | [IAM — MFA for the root user](https://docs.aws.amazon.com/IAM/latest/UserGuide/enable-mfa-for-root.html) | MFA bắt buộc, 14 ngày, passkey | 2026-10-31 |
| Chính | [IAM — AWS account root user](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-tasks.html) | Việc chỉ root làm được | 2026-10-31 |
| Chính | [IAM — Grant access to the billing console](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_billing.html) | *Activate IAM Access* | 2026-10-31 |
| Chính | [AWS Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/) | Budgets miễn phí, action-enabled, report | 2026-10-31 |
| Chính | [Creating a cost budget](https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html) | Unblended vs net unblended, ngưỡng Actual/Forecasted | 2026-10-31 |
| Bổ sung | [Using a budget template](https://docs.aws.amazon.com/cost-management/latest/userguide/budget-templates.html) | Zero spend / monthly cost template | 2026-10-31 |
| Bổ sung | [AWS Cost Explorer pricing](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/pricing/) | 0,01 USD mỗi request API | 2026-10-31 |
| Bổ sung | [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Public IPv4 0,005 USD/giờ, NAT Gateway | 2026-10-31 |
| Bổ sung | [IAM Identity Center — Account instances](https://docs.aws.amazon.com/singlesignon/latest/userguide/account-instances-identity-center.html) | Account instance không hỗ trợ permission set | 2026-10-31 |
| Bổ sung | [AWS Global View](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/global-view.html) | Xem tài nguyên trên mọi region | 2026-10-31 |
| Bổ sung | [CloudTrail event history](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html) | 90 ngày, miễn phí, giới hạn tìm kiếm | 2026-10-31 |
| Bổ sung | [AWS CLI — freetier get-account-plan-state](https://docs.aws.amazon.com/cli/latest/reference/freetier/get-account-plan-state.html) | Lệnh xem trạng thái gói và credit | 2026-10-31 |
| Bổ sung | [AWS Support plans](https://aws.amazon.com/premiumsupport/plans/) | Basic Support miễn phí | 2026-10-31 |
