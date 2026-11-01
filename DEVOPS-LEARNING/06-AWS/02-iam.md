# 02. IAM — Ai được làm gì trên AWS

> ⏱️ ~3–4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [00. Tạo tài khoản an toàn](00-aws-account-setup-cost-safety.md), [01. Cloud fundamentals](01-cloud-fundamentals.md), [Linux 03 — Permissions, users & groups](../01-LINUX/03-permissions-users-groups.md)
> Môi trường: `[AWS Console]`, `[WSL]` hoặc AWS CloudShell · 💰 Chi phí lab: **0 USD** (IAM, STS, Policy Simulator, CloudTrail Event history đều miễn phí)

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

- Phân biệt **root user**, **IAM user**, **IAM group**, **IAM role** và biết mỗi loại dùng khi nào.
- Phân biệt **xác thực** (authentication — bạn là ai) và **phân quyền** (authorization — bạn được làm gì).
- Đọc và tự viết một **IAM policy** JSON: `Version`, `Statement`, `Effect`, `Action`, `Resource`, `Condition`.
- Giải thích **logic đánh giá quyền**: deny tường minh thắng tất cả, allow thắng deny ngầm định, mặc định là từ chối.
- Phân biệt **trust policy** (ai được nhận role) và **permission policy** (role được làm gì); giải thích **instance profile** và **OIDC federation** ở mức khái niệm.
- Kiểm thử policy bằng **IAM Policy Simulator** và bằng lệnh thật, đọc sự kiện bị từ chối trong **CloudTrail**.
- Giải thích vì sao dự án `taskhub` dùng **IAM user + MFA** cho người, **role** cho máy, và **không có access key dài hạn** nào.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

IAM (Identity and Access Management — quản lý danh tính và truy cập) là **cổng vào** của mọi thứ trên AWS. Mọi lệnh bạn gõ, mọi request ứng dụng gửi đều đi qua IAM trước.

| Tình huống thật | Cần hiểu IAM vì |
|---|---|
| Pipeline GitHub Actions deploy lên EC2 (dự án v3, tuần 13) | Pipeline cần quyền AWS **mà không lưu access key** → role + OIDC |
| Ứng dụng trên EC2 đọc mật khẩu database từ Parameter Store (v2) | Máy cần quyền → **instance role**, không nhúng key vào code |
| "Tôi có quyền admin mà vẫn bị `AccessDenied`" | Phải đọc được thông báo lỗi, biết lớp policy nào đang chặn |
| Một access key bị đẩy lên GitHub public | Biết cách phát hiện (credential report, CloudTrail), vô hiệu hóa và thay thế |
| Phỏng vấn: "Role khác user thế nào?", "Least privilege là gì?" | Câu hỏi gần như chắc chắn gặp với vị trí Cloud/DevOps |

Nhiều sự cố bảo mật trên cloud không đến từ lỗ hổng phần mềm phức tạp, mà từ **quyền cấp quá rộng** hoặc **credential dài hạn bị lộ**. IAM là nơi bạn ngăn cả hai.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Nhắc lại từ Linux

Ở [Linux bài 03](../01-LINUX/03-permissions-users-groups.md) bạn đã gặp: user, group, quyền `rwx`, nguyên tắc "không chạy app bằng root". IAM là cùng ý tưởng ở quy mô cloud:

| Linux | AWS IAM |
|---|---|
| `root` | **Root user** của tài khoản AWS |
| User thường | **IAM user** |
| Group | **IAM group** |
| `sudo` tạm thời lên quyền | **Assume role** — nhận quyền tạm thời |
| Service account chạy daemon (user `taskhub`) | **Role** gắn vào EC2 / Lambda / pipeline |
| Quyền `rwx` trên file | **Policy** — JSON mô tả action nào trên resource nào |

### 3.2. Xác thực và phân quyền

- **Authentication (xác thực)**: chứng minh bạn là ai — mật khẩu + MFA khi vào Console, chữ ký request bằng credential khi dùng CLI/SDK.
- **Authorization (phân quyền)**: sau khi biết bạn là ai, AWS xét các **policy** để quyết định request được phép hay không.

Hai bước này độc lập: đăng nhập thành công (xác thực xong) không có nghĩa là làm được gì (chưa có quyền).

### 3.3. ARN — tên đầy đủ của mọi thứ

**ARN** (Amazon Resource Name) là định danh duy nhất của một tài nguyên:

```text
arn:aws:iam::111122223333:user/phuong-admin
arn:aws:iam::111122223333:role/taskhub-ec2-role
arn:aws:ec2:ap-southeast-1:111122223333:instance/i-0abc123def4567890
arn:aws:s3:::taskhub-backups-111122223333
└─┬┘└┬┘└┬┘ └─────┬──────┘└────┬─────┘└────────┬─────────┘
 arn  partition service  region   account-id     resource
```

IAM là dịch vụ **toàn cục** nên ARN của IAM để trống phần region (vẫn có account-id). ARN của S3 bucket để trống **cả** region lẫn account-id, vì tên bucket là duy nhất trên toàn AWS.

> `111122223333` là số tài khoản ví dụ trong tài liệu AWS. Thay bằng số tài khoản của bạn (12 chữ số).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Bốn loại danh tính (principal)

**Principal** là thực thể gửi request tới AWS.

| Principal | Là gì | Credential | Dùng cho | Trong dự án `taskhub` |
|---|---|---|---|---|
| **Root user** | Danh tính tạo ra tài khoản (email đăng ký) | Email + mật khẩu + MFA | **Chỉ** các việc chỉ root làm được (đóng tài khoản, đổi gói hỗ trợ…) | Khóa lại sau bài 00, MFA bắt buộc, **không có access key** |
| **IAM user** | Một người (hoặc ứng dụng — cách cũ) cụ thể trong tài khoản | Mật khẩu Console, và/hoặc **access key** dài hạn | Người cần đăng nhập Console | `phuong-admin` — dùng hằng ngày |
| **IAM group** | Tập hợp user để gắn quyền chung | Không có (group **không đăng nhập được**) | Gắn policy một lần cho nhiều user | `admins` |
| **IAM role** | Một "chiếc mũ quyền" ai đó/cái gì đó **đội tạm thời** | **Credential tạm thời** do STS cấp, tự hết hạn | Máy (EC2, pipeline), người cần lên quyền tạm thời, truy cập chéo tài khoản | `taskhub-ec2-role` (v2), `taskhub-github-deploy` (v3) |

Điểm then chốt: **user có credential dài hạn, role chỉ có credential tạm thời**. Credential tạm thời bị lộ thì tự hết hạn sau vài phút đến vài giờ; access key dài hạn bị lộ thì dùng được mãi đến khi bạn phát hiện.

### 4.2. 🟥 Cấu trúc một policy

Policy là tài liệu JSON. Ví dụ policy sẽ dùng trong lab:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucketsGlobal",
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Sid": "Ec2ReadSingaporeOnly",
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "*",
      "Condition": {
        "StringEquals": { "aws:RequestedRegion": "ap-southeast-1" }
      }
    }
  ]
}
```

| Phần tử | Ý nghĩa | Lưu ý |
|---|---|---|
| `Version` | Phiên bản **ngôn ngữ policy**, không phải ngày bạn viết | Luôn dùng `"2012-10-17"`. Bản cũ hơn không hỗ trợ biến như `${aws:username}` |
| `Statement` | Danh sách các câu lệnh quyền | Một policy có nhiều statement |
| `Sid` | Tên câu lệnh (tùy chọn) | Giúp đọc log, đọc Policy Simulator dễ hơn |
| `Effect` | `Allow` hoặc `Deny` | Chỉ hai giá trị |
| `Action` | API được phép/cấm, dạng `dịch-vụ:TênAPI` | Có wildcard: `ec2:Describe*` = mọi API bắt đầu bằng `Describe` |
| `Resource` | ARN tài nguyên áp dụng | `"*"` = mọi tài nguyên. Một số API **không hỗ trợ** giới hạn theo resource → bắt buộc `"*"` |
| `Condition` | Điều kiện thêm | Ví dụ: region, có MFA không, tag của resource, IP nguồn |

Đọc thành lời statement thứ hai: "**Cho phép** mọi API `ec2:Describe…` trên **mọi tài nguyên**, **với điều kiện** request gửi tới region **ap-southeast-1**."

**Vì sao `s3:ListAllMyBuckets` tách riêng, không có điều kiện region?** Đây là thao tác "liệt kê mọi bucket của tài khoản" — không gắn với region nào cụ thể. Tài liệu AWS lưu ý: với dịch vụ toàn cục như IAM, request luôn đi tới `us-east-1`, nên điều kiện `aws:RequestedRegion` đặt sai chỗ sẽ chặn luôn các API toàn cục. Tách statement giúp bạn khỏi phải đoán S3 gửi `ListBuckets` tới endpoint nào.

### 4.3. 🟥 Identity-based và resource-based policy

| | Identity-based policy | Resource-based policy |
|---|---|---|
| Gắn vào | User, group, role | Chính tài nguyên: S3 bucket, SQS queue, KMS key, **trust policy của role** |
| Có `Principal` không? | Không (principal là chính danh tính được gắn) | **Có** — phải ghi rõ ai được phép |
| Ví dụ trong khóa học | `AdministratorAccess` gắn vào group `admins` | Bucket policy của `taskhub-backups-…` (bài 05), trust policy của `taskhub-ec2-role` |

Trong **cùng một tài khoản**, theo tài liệu AWS, quyền thực tế là **hợp** (union) của hai loại: chỉ cần một bên cho phép (và không bên nào deny tường minh) là được.

### 4.4. 🟥 Managed và inline policy

| Loại | Ai tạo | Gắn cho bao nhiêu danh tính | Khi nào dùng |
|---|---|---|---|
| **AWS managed** | AWS tạo, AWS cập nhật | Nhiều | Bắt đầu nhanh: `AdministratorAccess`, `ReadOnlyAccess`, `AmazonSSMManagedInstanceCore` |
| **Customer managed** | Bạn | Nhiều | Quyền tối thiểu cho đúng việc của bạn — cách được khuyến nghị |
| **Inline** | Bạn | **Đúng một** — bị xóa cùng danh tính | Khi muốn quan hệ 1-1 chặt chẽ, quyền không được tái sử dụng nhầm |

AWS managed policy tiện nhưng **không tối thiểu**: ví dụ `ReadOnlyAccess` được AWS tự mở rộng khi có dịch vụ mới. Role `taskhub-ec2-role` của dự án dùng cả ba loại:

| Policy gắn vào `taskhub-ec2-role` | Loại | Cho phép |
|---|---|---|
| `AmazonSSMManagedInstanceCore` | AWS managed | Session Manager, Run Command (phần chuẩn) |
| `taskhub-ec2-app` | Customer managed | Đọc parameter `/taskhub/dev/*` (+ `kms:Decrypt` qua khóa `aws/ssm`), ghi CloudWatch Logs vào `/taskhub/dev/*` |
| `taskhub-ec2-s3-backup` | Inline | `s3:ListBucket` giới hạn prefix `pg-dumps/*`, `s3:PutObject`/`s3:GetObject` trên `pg-dumps/*`, **không** có quyền xóa — viết ở [bài 05 S3](05-s3.md) |

### 4.5. 🟥 Logic đánh giá quyền

Mỗi request, AWS gom mọi policy liên quan rồi quyết định theo thứ tự ưu tiên:

```text
                     Request đến
                         │
            ┌────────────▼────────────┐
            │ Có Deny tường minh nào  │── Có ──► ❌ TỪ CHỐI (không gì ghi đè được)
            │ khớp request không?     │
            └────────────┬────────────┘
                         │ Không
            ┌────────────▼────────────┐
            │ Có Allow nào khớp?      │── Không ─► ❌ TỪ CHỐI (deny ngầm định — mặc định)
            │ (và không lớp giới hạn  │
            │  nào chặn: boundary,    │
            │  SCP, session policy)   │
            └────────────┬────────────┘
                         │ Có
                         ▼
                     ✅ CHO PHÉP
```

Ba quy tắc cần thuộc:

1. **Mặc định là từ chối** (implicit deny). Một user mới tạo không làm được gì.
2. **Allow** mở quyền.
3. **Deny tường minh** (explicit deny) thắng mọi Allow, ở bất kỳ policy nào.

Sơ đồ đầy đủ (gồm SCP, RCP, permission boundary, session policy) ở trang [Policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) — mở ra xem một lần, bạn chưa cần nhớ hết.

### 4.6. 🟦 Permission boundary và SCP — các lớp "trần quyền"

- **Permission boundary**: một managed policy đặt **trần** cho user/role. Quyền thực tế = **giao** (intersection) của identity policy và boundary. Dùng khi bạn cho người khác tạo role nhưng không muốn họ tạo role mạnh hơn chính họ.
- **SCP** (Service Control Policy): trần quyền cho **cả tài khoản**, đặt từ AWS Organizations. Ngay cả root của tài khoản thành viên cũng bị giới hạn.

> ⚠️ **SCP cần AWS Organizations.** Với tài khoản **Free plan**, việc tham gia AWS Organizations sẽ **tự động nâng tài khoản lên Paid plan** (theo tài liệu AWS về Free plan). Vì vậy khóa học **không** dùng Organizations/SCP. Bạn chỉ cần biết SCP tồn tại — công ty lớn dùng rất nhiều.

### 4.7. 🟥 Role và STS AssumeRole

Một role có **hai** policy, đừng nhầm:

| | Trust policy | Permission policy |
|---|---|---|
| Trả lời câu hỏi | **Ai** được đội chiếc mũ này? | Đội mũ rồi thì **làm được gì**? |
| Loại | Resource-based (gắn vào role, có `Principal`) | Identity-based |
| Action đặc trưng | `sts:AssumeRole`, `sts:AssumeRoleWithWebIdentity` | `ec2:*`, `s3:GetObject`… |

Trust policy của role demo trong lab (chỉ `phuong-admin`, và chỉ khi có MFA):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::111122223333:user/phuong-admin" },
      "Action": "sts:AssumeRole",
      "Condition": { "Bool": { "aws:MultiFactorAuthPresent": "true" } }
    }
  ]
}
```

Luồng **assume role**:

```text
phuong-admin ──(1) sts:AssumeRole + mã MFA──► AWS STS
                                               │ (2) kiểm tra trust policy của role
                                               ▼
              ◄──(3) AccessKeyId + SecretAccessKey + SessionToken (hết hạn sau 1 giờ)
phuong-admin ──(4) gọi ec2:DescribeInstances bằng credential tạm thời──► EC2
                                               (5) xét permission policy của ROLE
```

Khi đã đội mũ, bạn **tạm bỏ** quyền của user gốc — quyền không cộng dồn. Console gọi là **Switch role**; CLI gọi là `aws sts assume-role` hoặc profile có `role_arn`.

**STS** (Security Token Service) là dịch vụ cấp credential tạm thời. Credential tạm thời có **ba** phần — thiếu `SessionToken` là request bị từ chối.

### 4.8. 🟥 Instance profile — role cho máy EC2 (xem trước v2)

Ứng dụng trên EC2 cần đọc mật khẩu từ Parameter Store. Cách **sai**: chép access key vào `.env` trên server. Cách **đúng**:

```text
EC2 "taskhub-app" ── gắn instance profile "taskhub-ec2-role"
     │
     │ App/CLI trên máy hỏi credential tại địa chỉ metadata 169.254.169.254 (IMDS)
     ▼
STS cấp credential tạm thời của role, tự xoay vòng trước khi hết hạn
     │
     ▼
aws ssm get-parameter --name /taskhub/dev/postgres-password  ✅ (không có key nào trên đĩa)
```

- **Instance profile** là "vỏ chứa" role để gắn vào EC2. Tạo role cho EC2 bằng Console thì AWS tạo instance profile cùng tên.
- Trust policy của role này cho phép **dịch vụ** EC2 nhận role: `"Principal": {"Service": "ec2.amazonaws.com"}`.
- Bạn sẽ tạo `taskhub-ec2-role` thật ở [bài 04 — EC2](04-ec2.md) (Bước 0, nếu chưa có) và dùng nó ở dự án v2. Quyền S3 backup được thêm ở [bài 05 — S3](05-s3.md).

### 4.9. 🟥 OIDC federation — pipeline không cần access key (xem trước v3)

Câu hỏi: GitHub Actions không phải máy trong AWS, làm sao nhận role mà không lưu access key vào GitHub Secrets?

```text
GitHub Actions job (environment: production)
     │ (1) GitHub ký một JWT: "tôi là repo phuong-dev/taskhub, environment production"
     ▼
AWS STS: AssumeRoleWithWebIdentity
     │ (2) kiểm tra chữ ký bằng OIDC provider token.actions.githubusercontent.com
     │ (3) kiểm tra trust policy: sub = repo:phuong-dev/taskhub:environment:production
     ▼                          aud = sts.amazonaws.com
Credential tạm thời của role "taskhub-github-deploy" (chỉ được gửi lệnh SSM tới EC2 taskhub)
```

- **OIDC** (OpenID Connect): chuẩn để một bên (GitHub) chứng nhận danh tính, bên kia (AWS) tin dựa trên chữ ký.
- Điều kiện `sub` cực kỳ quan trọng: thiếu nó, **bất kỳ repo GitHub nào** cũng có thể nhận role của bạn. Theo tài liệu IAM, AWS từ chối tạo trust policy cho GitHub OIDC nếu thiếu điều kiện `token.actions.githubusercontent.com:sub` hoặc giá trị chỉ là wildcard.
- Bạn đã gặp khái niệm này ở [Module 05 bài 04](../05-CICD/04-secrets-environments.md); làm thật ở dự án v3.

### 4.10. 🟥 MFA và access key

**MFA** (Multi-Factor Authentication — xác thực đa yếu tố): ngoài mật khẩu, cần thêm một thứ bạn **có**. AWS hỗ trợ (theo tài liệu IAM):

| Loại MFA | Chống phishing | Dùng được cho CLI `--token-code`? |
|---|---|---|
| **Passkey / security key** (FIDO) | ✅ Tốt nhất | ❌ Không truyền được cho STS. Dùng `aws login` thay thế |
| **Ứng dụng authenticator** (TOTP: Google Authenticator, Microsoft Authenticator, 1Password…) | Trung bình | ✅ Có |
| **Hardware TOTP token** | Trung bình | ✅ Có |

- Mỗi root user và IAM user đăng ký được **tối đa 8 thiết bị MFA**. Khuyến nghị: **một passkey + một authenticator app** (dự phòng khi mất máy, và để dùng `--token-code` trong lab).
- AWS **bắt buộc MFA cho root user** ở mọi loại tài khoản.
- AWS đã ngừng cho bật MFA qua SMS.

**Access key** (`AKIA…` + secret) là credential **dài hạn** để ký request CLI/SDK. Rủi ro:

- Không tự hết hạn. Lộ ở đâu (commit Git, ảnh chụp màn hình, log CI, file `.env` gửi qua chat) là dùng được ở đó.
- Bot quét GitHub public liên tục tìm chuỗi có dạng access key. Một key bị đẩy lên repo public có thể bị dùng để chạy máy đào tiền ảo trên tài khoản của bạn trong thời gian rất ngắn — đây là kịch bản đã được ghi nhận nhiều lần trong cộng đồng.
- Dự án `taskhub` có **0 access key dài hạn**: người dùng `aws login` (bài 06), EC2 dùng instance role, GitHub dùng OIDC.

**Credential report** — file CSV liệt kê mọi user và trạng thái credential (`password_enabled`, `mfa_active`, `access_key_1_active`, `access_key_1_last_used_date`…). Tạo được tối đa **4 giờ một lần**. Đây là cách nhanh nhất để audit "có ai chưa bật MFA? có key nào đang hoạt động?".

### 4.11. 🟥 IAM Identity Center hay IAM user? (quyết định cho Free plan)

Tài liệu AWS khuyến nghị người dùng nên đăng nhập bằng **IAM Identity Center** để dùng credential tạm thời. Vậy vì sao khóa học chọn **IAM user**?

| Lựa chọn | Vấn đề với tài khoản Free plan một mình |
|---|---|
| Identity Center — **organization instance** | Cần **AWS Organizations** → theo tài liệu Free plan, tham gia Organizations **tự động nâng lên Paid plan** |
| Identity Center — **account instance** (tạo được trên tài khoản đứng một mình) | Theo tài liệu AWS, account instance **không hỗ trợ permission set**, nên **không cấp được quyền truy cập tài khoản AWS** — chỉ dùng cho ứng dụng |
| **IAM user + MFA + `aws login`** ✅ | Không cần Organizations; CLI vẫn nhận **credential tạm thời** (xoay vòng 15 phút, phiên tối đa 12 giờ) — đạt mục tiêu "không key dài hạn" |

Khi đi làm ở công ty có nhiều tài khoản, bạn gần như chắc chắn dùng Identity Center. Ghi quyết định này thành ADR trong repo `taskhub` là một bài tập tốt (mục 14).

### 4.12. 🟨 Least privilege — quy trình thực tế

**Least privilege** (quyền tối thiểu): chỉ cấp đúng quyền cần cho đúng việc.

Viết policy tối thiểu ngay từ đầu rất khó. Quy trình thực tế:

1. **Bắt đầu rộng trong môi trường thử** (ví dụ `ReadOnlyAccess`, hoặc quyền đầy đủ một dịch vụ).
2. **Quan sát** việc thật sự được dùng:
   - Tab **Last Accessed** của user/role/policy (miễn phí): dịch vụ nào được dùng lần cuối khi nào; với EC2, IAM, Lambda, S3 có cả mức **action**. Hoạt động mới hiện sau **tối đa 4 giờ**.
   - 🟦 **IAM Access Analyzer policy generation**: đọc CloudTrail (tối đa 90 ngày) và **sinh ra policy** gồm các action đã dùng. Yêu cầu một **CloudTrail trail** ghi vào S3 — trail có chi phí lưu trữ S3, nên khóa học chỉ giới thiệu.
3. **Thu hẹp** thành customer managed policy, kiểm thử bằng **Policy Simulator**.
4. **Lặp lại** định kỳ.

### 4.13. 🟥 IAM Policy Simulator

Công cụ tại `https://policysim.aws.amazon.com` (hoặc từ IAM Console). Theo tài liệu AWS:

- **Không gửi request thật** → thử thoải mái cả action nguy hiểm như `ec2:TerminateInstances`.
- Hai chế độ: **Principal mode** (thử policy đang gắn vào user/role có sẵn) và **Custom mode** (dán policy đang viết dở).
- Cho bạn nhập giá trị **condition key** (ví dụ `aws:RequestedRegion`) để thử từng trường hợp.
- Chỉ ra **statement nào** cho phép hoặc deny tường minh.
- Kết quả **có thể khác** môi trường thật trong vài trường hợp nâng cao → luôn kiểm tra lại bằng lệnh thật.

### 4.14. Gặp lại ở đâu

| Kiến thức bài này | Gặp lại ở |
|---|---|
| Role + instance profile | `taskhub-ec2-role` — [bài 04 EC2](04-ec2.md), dự án v2 |
| Customer managed policy, `Resource` theo ARN | `taskhub-ec2-app` (Parameter Store, CloudWatch Logs) — dự án v2 |
| Inline policy giới hạn theo prefix | `taskhub-ec2-s3-backup` — [bài 05 S3](05-s3.md) |
| Bucket policy (resource-based) | [Bài 05 S3](05-s3.md) |
| OIDC + trust policy có `sub` | `taskhub-github-deploy` — dự án v3 |
| `aws sts`, credential tạm thời, `AccessDenied` | [Bài 06 AWS CLI](06-aws-cli.md) |
| CloudTrail | [Bài 10 CloudWatch](10-cloudwatch.md), Module 10 Security |
| Least privilege cho Terraform | Module 07 |
| ServiceAccount + RBAC (cùng ý tưởng) | Module 09 Kubernetes |

---

## 5. Ví dụ thực tế

**Tình huống 1 — "Tôi là admin mà vẫn bị từ chối".** Một bạn đã switch sang role chỉ-đọc từ sáng, quên mất, chiều chạy lệnh tạo bucket thì bị `AccessDenied`. Thanh điều hướng Console đang hiện **tên role** (display name + màu), không phải tên user. Bài học: luôn kiểm tra "mình đang là ai" — `aws sts get-caller-identity` trên CLI, góc trên phải trên Console.

**Tình huống 2 — Key lộ trên GitHub.** Một developer commit file cấu hình có access key vào repo public. Vài giờ sau, hóa đơn có hàng chục instance GPU ở các region chưa từng dùng. Xử lý đúng thứ tự: (1) **vô hiệu hóa** key ngay (Deactivate), (2) kiểm tra CloudTrail key đó đã làm gì, ở region nào, (3) dọn tài nguyên lạ, (4) xóa key, (5) mở case với AWS Support về chi phí. Phòng ngừa: không dùng key dài hạn; bật secret scanning (Module 05/10).

**Tình huống 3 — Condition region chặn nhầm.** Một team viết policy "chỉ cho phép ap-southeast-1" bằng Deny có điều kiện `aws:RequestedRegion` khác `ap-southeast-1`, áp cho mọi action. Ngay sau đó, không ai xem được IAM nữa, vì IAM luôn gọi `us-east-1`. Tài liệu AWS mô tả đúng trường hợp này và gợi ý dùng `NotAction` để loại trừ dịch vụ toàn cục.

---

## 6. Sơ đồ kiến trúc

Danh tính và quyền của dự án `taskhub` khi hoàn thiện v3:

```text
                         ┌──────────────────── Tài khoản AWS 111122223333 ────────────────────┐
 Bạn (người)             │                                                                    │
 ─ Console: mật khẩu+MFA─┼─► IAM user phuong-admin ──thuộc──► group admins ── AdministratorAccess
 ─ CLI: aws login ───────┼─►   (credential tạm thời, xoay 15 phút)                            │
                         │        │ switch role (lab)                                         │
                         │        ▼                                                           │
                         │   role taskhub-readonly-demo (lab, xóa sau bài)                    │
                         │                                                                    │
 EC2 taskhub-app ────────┼─► instance profile ─► role taskhub-ec2-role                        │
  (IMDS 169.254.169.254) │        ├─ AmazonSSMManagedInstanceCore (Session Manager)           │
                         │        ├─ taskhub-ec2-app (đọc /taskhub/dev/*, ghi log)            │
                         │        └─ taskhub-ec2-s3-backup (inline: pg-dumps/*, không xóa)    │
                         │                                                                    │
 GitHub Actions ─JWT─────┼─► OIDC provider token.actions.githubusercontent.com                │
  (env production)       │        └─► role taskhub-github-deploy (chỉ SSM SendCommand)        │
                         │                                                                    │
 Root user ── MFA, không access key, cất đi ──────────────────────────────────────────────────┤
                         └────────────────────────────────────────────────────────────────────┘
                     Mọi request ở trên đều được ghi vào CloudTrail Event history (90 ngày)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích |
|---|---|
| `aws sts get-caller-identity` | "Tôi đang là ai?" — lệnh đầu tiên khi debug quyền |
| `aws iam list-users` / `list-groups` / `list-roles` | Liệt kê danh tính |
| `aws iam list-attached-user-policies --user-name …` | Policy managed gắn trực tiếp vào user |
| `aws iam list-groups-for-user --user-name …` | User thuộc group nào (quyền đến từ group) |
| `aws iam get-role --role-name …` | Xem role, gồm trust policy |
| `aws iam get-policy` + `get-policy-version` | Đọc nội dung một customer managed policy |
| `aws sts assume-role …` | Nhận credential tạm thời của role |
| `aws iam simulate-principal-policy …` | Policy Simulator từ CLI |
| `aws iam generate-credential-report` / `get-credential-report` | Audit credential |
| `aws sts decode-authorization-message …` | Giải mã thông báo lỗi quyền dạng mã hóa |
| `aws cloudtrail lookup-events …` | Tra Event history |

Bạn sẽ cài và cấu hình CLI ở [bài 06](06-aws-cli.md). Với bài này, có thể chạy các lệnh trong **AWS CloudShell** (terminal ngay trên Console, miễn phí, đã có sẵn CLI và đăng nhập theo user Console của bạn).

---

## 8. Giải thích câu lệnh và tham số

> Mọi đầu ra dưới đây là **minh họa** — ID, thời gian, số tài khoản sẽ khác.

### 8.1. `aws sts get-caller-identity`

```bash
aws sts get-caller-identity
```

```json
{
    "UserId": "AIDAEXAMPLEUSERID1234",
    "Account": "111122223333",
    "Arn": "arn:aws:iam::111122223333:user/phuong-admin"
}
```

Lệnh này **không cần quyền gì** — luôn chạy được nếu credential hợp lệ. Sau khi assume role, `Arn` sẽ có dạng `arn:aws:sts::111122223333:assumed-role/taskhub-readonly-demo/phuong-lab` — chữ `assumed-role` và **tên phiên** ở cuối.

### 8.2. `aws sts assume-role` có MFA

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::111122223333:role/taskhub-readonly-demo \
  --role-session-name phuong-lab \
  --serial-number arn:aws:iam::111122223333:mfa/phuong-authenticator \
  --token-code 123456 \
  --duration-seconds 3600
```

| Tham số | Ý nghĩa |
|---|---|
| `--role-arn` | Role muốn nhận |
| `--role-session-name` | Tên phiên — xuất hiện trong ARN và **CloudTrail**, giúp biết ai đã dùng role. Đặt tên có nghĩa |
| `--serial-number` | ARN của thiết bị MFA **TOTP** (authenticator app). Xem ở IAM → Users → phuong-admin → Security credentials. Passkey không dùng được ở đây |
| `--token-code` | Mã 6 số đang hiện trên app |
| `--duration-seconds` | Thời hạn credential (mặc định 3600 = 1 giờ; không vượt quá *maximum session duration* của role) |

```json
{
    "Credentials": {
        "AccessKeyId": "ASIAEXAMPLETEMPKEY12",
        "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "SessionToken": "IQoJb3JpZ2luX2VjE...(rất dài)...",
        "Expiration": "2027-01-11T10:42:17+00:00"
    },
    "AssumedRoleUser": {
        "AssumedRoleId": "AROAEXAMPLEROLEID123:phuong-lab",
        "Arn": "arn:aws:sts::111122223333:assumed-role/taskhub-readonly-demo/phuong-lab"
    }
}
```

Để ý: key tạm thời bắt đầu bằng **`ASIA`**, key dài hạn của user bắt đầu bằng **`AKIA`**. Nhìn tiền tố là biết loại credential.

### 8.3. `aws iam simulate-principal-policy`

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::111122223333:role/taskhub-readonly-demo \
  --action-names ec2:DescribeInstances s3:CreateBucket \
  --context-entries ContextKeyName=aws:RequestedRegion,ContextKeyValues=us-east-1,ContextKeyType=string \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' \
  --output table
```

```text
-------------------------------------------
|         SimulatePrincipalPolicy         |
+----------------------+------------------+
|  ec2:DescribeInstances|  implicitDeny   |
|  s3:CreateBucket      |  implicitDeny   |
+----------------------+------------------+
```

| Tham số | Ý nghĩa |
|---|---|
| `--policy-source-arn` | User/role có policy cần thử (Principal mode) |
| `--action-names` | Danh sách action cần thử, cách nhau bằng dấu cách |
| `--context-entries` | Giá trị giả lập cho condition key |
| Kết quả `allowed` / `implicitDeny` / `explicitDeny` | Cho phép / không có Allow nào khớp / bị Deny tường minh |

### 8.4. Credential report

```bash
aws iam generate-credential-report
aws iam get-credential-report --query Content --output text | base64 -d | cut -d, -f1,4,8,9
```

```text
user,password_enabled,mfa_active,access_key_1_active
<root_account>,not_supported,true,false
phuong-admin,true,true,false
```

`Content` là CSV **mã hóa base64** → `base64 -d` để giải. `cut -d, -f…` chọn cột (đã học ở [Linux bài 02](../01-LINUX/02-essential-commands-text.md)). Kỳ vọng của `taskhub`: mọi dòng `mfa_active=true`, mọi `access_key_*_active=false`.

### 8.5. `aws sts decode-authorization-message`

Một số API (đặc biệt các thao tác thay đổi của EC2) trả lỗi kèm chuỗi mã hóa:

```text
An error occurred (UnauthorizedOperation) when calling the RunInstances operation:
You are not authorized to perform this operation. Encoded authorization failure message: 4kPq...(rất dài)...
```

```bash
aws sts decode-authorization-message --encoded-message '4kPq...' \
  --query DecodedMessage --output text | python3 -m json.tool
```

Cần quyền `sts:DecodeAuthorizationMessage` — role chỉ-đọc không có, nên hãy giải mã bằng `phuong-admin`. Kết quả là JSON có `allowed`, `explicitDeny`, `matchedStatements`, và `context` (principal, action, resource, giá trị condition) — cho biết **chính xác** request bị chặn vì sao.

### 8.6. `aws cloudtrail lookup-events`

```bash
aws cloudtrail lookup-events --region ap-southeast-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --max-results 5 \
  --query 'Events[].[EventTime,EventName,Username]' --output table
```

- Event history: **90 ngày** gần nhất, **chỉ management event**, **theo từng region**, **miễn phí** xem.
- Mỗi lần tra chỉ lọc được **một** thuộc tính (EventName, Username, ResourceName…) cộng khoảng thời gian.
- Chi tiết đầy đủ (gồm `errorCode`, `errorMessage`, `sourceIPAddress`) nằm trong trường `CloudTrailEvent` (một chuỗi JSON).
- Sự kiện xuất hiện **sau vài phút**, không tức thì.

---

## 9. Bài thực hành từng bước

> 💰 **Ước tính chi phí: 0 USD.** IAM, STS, Policy Simulator, CloudShell và CloudTrail Event history không tính phí. Lab **không** tạo tài nguyên tính tiền nào.
> ⏱️ ~90 phút. Chuẩn bị: điện thoại có ứng dụng authenticator (Google Authenticator, Microsoft Authenticator, 1Password, Bitwarden…).

### Bước 1 — Group `admins` và user `phuong-admin` `[AWS Console]`

> Nếu đã tạo ở [bài 00](00-aws-account-setup-cost-safety.md), chỉ cần kiểm tra lại theo checklist cuối bước này rồi sang Bước 2.

Đăng nhập bằng **root** (lần cuối cho việc thường ngày).

1. IAM → **User groups** → **Create group** → tên `admins` → gắn policy **AdministratorAccess** → Create.
2. IAM → **Users** → **Create user**:
   - User name: `phuong-admin` (thay `phuong` bằng tên bạn).
   - Tick **Provide user access to the AWS Management Console** → chọn **I want to create an IAM user** → mật khẩu tự đặt (dài, lưu vào trình quản lý mật khẩu).
   - Permissions: **Add user to group** → `admins`. **Không** gắn policy trực tiếp vào user.
   - Tags: `Project=taskhub`, `Owner=phuong`.
3. Ghi lại **Console sign-in URL** dạng `https://111122223333.signin.aws.amazon.com/console`.
4. **Không** tạo access key. Nếu Console gợi ý tạo, bỏ qua.
5. Sign out root.

**Checklist:** user nằm trong group `admins`; group có đúng `AdministratorAccess`; user có 0 access key.

### Bước 2 — Đăng nhập `phuong-admin`, bật 2 thiết bị MFA `[AWS Console]`

1. Mở sign-in URL ở Bước 1, đăng nhập `phuong-admin`.
2. Góc phải trên → tên user → **Security credentials** → **Assign MFA device**:
   - Thiết bị 1: **Passkey or security key** (dùng hằng ngày, chống phishing). Tên: `phuong-passkey`.
   - Thiết bị 2: **Authenticator app**, tên `phuong-authenticator` → quét QR → nhập **hai mã liên tiếp**.
3. Ghi lại **ARN** của thiết bị authenticator: `arn:aws:iam::111122223333:mfa/phuong-authenticator`.
4. **Sign out rồi đăng nhập lại** bằng MFA — phiên mới mới mang thông tin "đã xác thực MFA".

❓ Vì sao cần cả authenticator app khi đã có passkey? (Gợi ý: mục 4.10, cột cuối.)

### Bước 3 — Mở terminal: CloudShell (hoặc WSL nếu đã xong bài 06)

Chọn region **Asia Pacific (Singapore) ap-southeast-1** ở góc phải trên → bấm biểu tượng **CloudShell** (hình `>_`) ở thanh trên.

```bash
aws --version
aws sts get-caller-identity
```

Kỳ vọng: `Arn` là `…:user/phuong-admin`. Nếu bạn đã làm [bài 06](06-aws-cli.md), có thể dùng WSL với `export AWS_PROFILE=taskhub` thay cho CloudShell — các lệnh giống hệt.

### Bước 4 — Customer managed policy `taskhub-readonly-demo-policy` `[AWS Console]`

IAM → **Policies** → **Create policy** → tab **JSON** → dán policy ở [mục 4.2](#42--cấu-trúc-một-policy) → Next → tên `taskhub-readonly-demo-policy` → mô tả "Lab IAM: S3 list + EC2 describe chỉ ở Singapore" → tag `Project=taskhub` → Create.

Để ý cảnh báo/gợi ý của **policy validator** (bên dưới ô JSON) — nó là một phần của Access Analyzer, bắt lỗi cú pháp và cảnh báo bảo mật ngay khi bạn gõ.

### Bước 5 — Role `taskhub-readonly-demo` yêu cầu MFA `[AWS Console]`

1. IAM → **Roles** → **Create role** → Trusted entity type: **AWS account** → **This account** → tick **Require MFA** → Next.
2. Gắn policy `taskhub-readonly-demo-policy` → Next.
3. Tên `taskhub-readonly-demo`, tag `Project=taskhub` → Create role.
4. Mở role → tab **Trust relationships** → **Edit trust policy**. Console đã tạo principal là **cả tài khoản** (`…:root`) — nghĩa là mọi danh tính trong tài khoản **có quyền `sts:AssumeRole`** đều nhận được. Thu hẹp lại thành đúng user của bạn bằng trust policy ở [mục 4.7](#47--role-và-sts-assumerole) → **Update policy**.
5. Ghi lại **Role ARN**.

❓ Principal `arn:aws:iam::111122223333:root` trong trust policy có nghĩa là "chỉ root user được nhận role" không? (Đáp án trong lời giải — đây là hiểu lầm rất phổ biến.)

### Bước 6 — Kiểm thử bằng Policy Simulator `[AWS Console]`

Mở `https://policysim.aws.amazon.com` (đăng nhập sẵn bằng `phuong-admin`).

1. Cột trái: **Roles** → chọn `taskhub-readonly-demo`.
2. Chọn dịch vụ **Amazon EC2** → action `DescribeInstances`, `RunInstances`; dịch vụ **Amazon S3** → `ListAllMyBuckets`, `CreateBucket`; dịch vụ **AWS Identity and Access Management** → `ListUsers`.
3. Mở **Simulation Settings** → tìm `aws:RequestedRegion` → nhập `ap-southeast-1` → **Run Simulation**.
4. Đổi `aws:RequestedRegion` thành `us-east-1` → chạy lại.

Ghi kết quả vào bảng trong `week11/iam-lab.md` (repo nhật ký của bạn):

| Action | Region `ap-southeast-1` | Region `us-east-1` | Statement quyết định |
|---|---|---|---|
| `ec2:DescribeInstances` | ? | ? | ? |
| `ec2:RunInstances` | ? | ? | ? |
| `s3:ListAllMyBuckets` | ? | ? | ? |
| `s3:CreateBucket` | ? | ? | ? |
| `iam:ListUsers` | ? | ? | ? |

Tùy chọn — làm lại bằng CLI với lệnh ở [mục 8.3](#83-aws-iam-simulate-principal-policy).

### Bước 7 — Switch role trên Console `[AWS Console]`

1. Góc phải trên → tên user → **Switch role**.
2. Account: `111122223333`; Role: `taskhub-readonly-demo`; Display name: `RO-demo`; màu **vàng** → **Switch Role**.
3. Thử lần lượt và ghi lại điều xảy ra:
   - EC2 Console, region Singapore → Instances (danh sách rỗng nhưng **không lỗi**).
   - Đổi region sang **N. Virginia** → EC2 Instances → thông báo lỗi quyền.
   - S3 Console → danh sách bucket (có thể rỗng) → thử **Create bucket** → bị từ chối.
   - IAM Console → Users → bị từ chối.
4. Bấm `RO-demo` → **Switch back**.

❓ Bảng điều khiển EC2 (EC2 Dashboard) có thể hiện vài ô lỗi ngay cả ở Singapore. Vì sao? (Gợi ý: Console gọi nhiều API khác nhau để vẽ một trang; policy của bạn chỉ có `ec2:Describe*` — và một số ô gọi API ở dịch vụ khác hoặc region khác.)

### Bước 8 — Assume role bằng CLI `[CloudShell]` hoặc `[WSL]`

**8a. Thử không có MFA** — phải bị từ chối:

```bash
ROLE_ARN="arn:aws:iam::111122223333:role/taskhub-readonly-demo"   # thay số tài khoản
aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name no-mfa-test
```

Kỳ vọng: `AccessDenied ... is not authorized to perform: sts:AssumeRole`. Điều kiện `aws:MultiFactorAuthPresent` của trust policy không được thỏa.

**8b. Có MFA** — mở app authenticator lấy mã:

```bash
MFA_ARN="arn:aws:iam::111122223333:mfa/phuong-authenticator"
read -r -p "Mã MFA 6 số: " MFA_CODE

creds="$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name phuong-lab \
  --serial-number "$MFA_ARN" \
  --token-code "$MFA_CODE" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)"

# Tách 3 trường (phân cách bằng tab) vào biến môi trường của shell hiện tại
read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<< "$creds"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
unset creds

aws sts get-caller-identity --query Arn --output text
```

Kỳ vọng: `arn:aws:sts::111122223333:assumed-role/taskhub-readonly-demo/phuong-lab`.

> Vì sao dùng `read <<<` mà không `echo` credential? Credential tạm thời vẫn là bí mật trong 1 giờ — không in ra màn hình, không lưu vào file. Biến môi trường chỉ sống trong shell này.

**8c. Thử quyền của role:**

```bash
aws ec2 describe-instances --region ap-southeast-1 --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-instances --region us-east-1      --query 'Reservations[].Instances[].InstanceId'
aws s3api list-buckets --query 'Buckets[].Name'
aws iam list-users
aws ec2 create-vpc --region ap-southeast-1 --cidr-block 10.99.0.0/16 --dry-run
```

Ghi lại lệnh nào thành công, lệnh nào lỗi, **mã lỗi** là gì (`UnauthorizedOperation`, `AccessDenied`…). Lệnh cuối có `--dry-run`: AWS chỉ **kiểm tra quyền**, không tạo gì cả. Nếu thông báo lỗi có `Encoded authorization failure message`, chép chuỗi mã hóa đó lại.

**8d. Trở lại danh tính gốc và giải mã lỗi:**

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws sts get-caller-identity --query Arn --output text      # phải là user/phuong-admin

aws sts decode-authorization-message --encoded-message 'DÁN-CHUỖI-MÃ-HÓA-VÀO-ĐÂY' \
  --query DecodedMessage --output text | python3 -m json.tool
```

Tìm trong kết quả: `"allowed": false`, `"explicitDeny": false` → nghĩa là gì? `context.action` và `context.conditions` cho thấy gì?

### Bước 9 — Đọc sự kiện bị từ chối trong CloudTrail `[AWS Console]`

Đợi khoảng 5–10 phút sau Bước 8.

1. Console → **CloudTrail** → **Event history** (region **Singapore**).
2. Lookup attributes: **Event name** = `AssumeRole`. Bạn sẽ thấy cả lần thất bại (8a) và lần thành công (8b).
3. Mở lần thất bại → xem JSON: tìm `errorCode`, `errorMessage`, `userIdentity.arn`, `sourceIPAddress`, `requestParameters.roleSessionName`.
4. Đổi thành **Event name** = `CreateVpc` → mở sự kiện của 8c → tìm `errorCode` và `userIdentity` (lần này là `assumed-role/.../phuong-lab`).

❓ Lần gọi `describe-instances --region us-east-1` bị từ chối nằm ở Event history của region nào? Thử tìm ở Singapore, rồi đổi Console sang N. Virginia và tìm lại.

Bằng CLI (tùy chọn):

```bash
aws cloudtrail lookup-events --region ap-southeast-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --max-results 5 --query 'Events[].CloudTrailEvent' --output text \
  | python3 -c 'import sys, json
for line in sys.stdin:
    e = json.loads(line)
    print(e["eventTime"], e.get("errorCode", "OK"), e["userIdentity"].get("arn"))'
```

### Bước 10 — Audit nhanh `[CloudShell]` hoặc `[WSL]`

```bash
aws iam generate-credential-report
sleep 5
aws iam get-credential-report --query Content --output text | base64 -d | cut -d, -f1,4,8,9
```

Kỳ vọng: mọi dòng `mfa_active` là `true`, mọi `access_key_1_active` là `false`.

Mở IAM → Roles → `taskhub-readonly-demo` → tab **Last Accessed**. Có thể chưa hiện gì (tối đa 4 giờ) — quay lại xem trước khi dọn dẹp nếu kịp.

### Bước 11 — Dọn dẹp ⚠️

Role và policy demo không tốn tiền, nhưng **quyền thừa là rủi ro** — xóa đi là thói quen đúng.

1. ⚠️ IAM → Roles → `taskhub-readonly-demo` → **Delete** (gõ tên để xác nhận).
2. ⚠️ IAM → Policies → `taskhub-readonly-demo-policy` → **Delete** (policy phải không còn gắn vào đâu).
3. Trên Console, mục Switch role có thể còn lưu `RO-demo` trong lịch sử — không sao, role đã bị xóa thì không switch được nữa.
4. Trong shell: `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN MFA_CODE`.

**Giữ lại:** group `admins`, user `phuong-admin` và 2 thiết bị MFA — dùng suốt khóa học.

**Kiểm tra đã dọn sạch:**

```bash
aws iam get-role --role-name taskhub-readonly-demo 2>&1 | tail -1
# Kỳ vọng: ... (NoSuchEntity) ... The role with name taskhub-readonly-demo cannot be found.

aws iam list-policies --scope Local --query 'Policies[].PolicyName' --output text
# Kỳ vọng: không còn taskhub-readonly-demo-policy

aws iam list-access-keys --user-name phuong-admin --query 'AccessKeyMetadata' --output text
# Kỳ vọng: rỗng
```

---

## 10. Kết quả mong đợi

- [ ] Group `admins` có `AdministratorAccess`; `phuong-admin` thuộc group, có **2 thiết bị MFA**, **0 access key**.
- [ ] Bảng Policy Simulator đầy đủ 10 ô, giải thích được từng ô bằng statement tương ứng.
- [ ] Đã switch role trên Console và thấy khác biệt Singapore / N. Virginia.
- [ ] Assume role CLI: thất bại khi thiếu MFA, thành công khi có MFA; `Arn` có `assumed-role/…/phuong-lab`.
- [ ] Đã giải mã một `Encoded authorization failure message` và chỉ ra action, kết luận `allowed`/`explicitDeny`.
- [ ] Tìm được sự kiện `AssumeRole` thất bại trong CloudTrail với `errorCode`.
- [ ] Role và policy demo đã xóa; lệnh kiểm tra trả `NoSuchEntity`.
- [ ] `week11/iam-lab.md` ghi lại kết quả và câu trả lời cho các câu ❓.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `AccessDenied ... sts:AssumeRole` dù đã nhập MFA | Dùng ARN thiết bị **passkey** cho `--serial-number`; hoặc mã đã hết hạn (30 giây); hoặc giờ hệ thống lệch | Dùng ARN thiết bị **authenticator**; nhập mã mới; kiểm tra giờ: `date -u` |
| `AccessDenied ... sts:AssumeRole` dù có MFA đúng | Trust policy ghi sai ARN user (sai số tài khoản, sai tên) | IAM → Role → Trust relationships, so từng ký tự với `aws sts get-caller-identity` |
| Switch role báo "Invalid information in one or more fields" | Gõ sai account ID/role name, hoặc user đăng nhập **không có MFA** trong phiên này | Kiểm tra lại; sign out rồi sign in **bằng MFA** |
| Lệnh chạy được ở Singapore, lỗi ở region khác | Điều kiện `aws:RequestedRegion` — **đúng như thiết kế** | Thêm `--region ap-southeast-1` hoặc đặt region mặc định |
| `The security token included in the request is expired` | Credential tạm thời quá 1 giờ | `unset` biến môi trường rồi assume lại |
| Sau khi assume role, mọi lệnh vẫn chạy như admin | Quên `export`; hoặc chạy lệnh ở **tab terminal khác** | `aws sts get-caller-identity` để kiểm tra |
| Sau lab, `phuong-admin` bị lỗi quyền lạ | Quên `unset` → vẫn đang dùng credential của role | `unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` |
| Không xóa được policy: *cannot be deleted while attached* | Policy vẫn gắn vào role | Xóa role trước, hoặc detach policy |
| Policy validator báo lỗi `MalformedPolicyDocument` | JSON thiếu dấu phẩy/ngoặc, hoặc `Version` sai | Đọc dòng được chỉ ra; kiểm tra JSON bằng `python3 -m json.tool < policy.json` |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Đọc một thông báo `AccessDenied`

Thông báo lỗi IAM hiện đại thường nói rõ **lớp policy nào** gây ra (minh họa):

```text
An error occurred (AccessDenied) when calling the ListUsers operation:
User: arn:aws:sts::111122223333:assumed-role/taskhub-readonly-demo/phuong-lab
is not authorized to perform: iam:ListUsers on resource: arn:aws:iam::111122223333:user/
because no identity-based policy allows the iam:ListUsers action
```

Đọc theo 4 phần:

| Phần | Giá trị | Câu hỏi bạn tự trả lời |
|---|---|---|
| `User:` | `assumed-role/taskhub-readonly-demo/phuong-lab` | Mình có đang đúng danh tính không? |
| `perform:` | `iam:ListUsers` | Action chính xác cần thêm vào policy là gì? |
| `on resource:` | ARN | Resource nào? Policy có ghi đúng ARN không? |
| `because …` | `no identity-based policy allows` | **Deny ngầm định** → thiếu Allow. Nếu là `with an explicit deny in …` → có Deny tường minh, thêm Allow **không** giải quyết được |

### 12.2. Quy trình debug quyền 5 bước

1. **Tôi là ai?** `aws sts get-caller-identity`.
2. **Đọc lỗi**: action nào, resource nào, implicit hay explicit deny.
3. **Mã hóa?** Có `Encoded authorization failure message` → `decode-authorization-message`.
4. **Thử giả lập**: Policy Simulator với đúng action, resource, condition.
5. **Kiểm chứng bằng log**: CloudTrail Event history → `errorCode`, `userIdentity`, region.

Ghi lại mọi lỗi quyền bạn gặp vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Phân biệt authentication và authorization. Đăng nhập Console thành công thì chắc chắn làm được gì chưa?
2. Root user khác IAM user `phuong-admin` ở những điểm nào? Việc gì bắt buộc phải dùng root?
3. Vì sao group không đăng nhập được, mà quyền vẫn nên gắn vào group thay vì gắn trực tiếp vào user?
4. Viết lại bằng lời ý nghĩa của từng phần tử trong statement `Ec2ReadSingaporeOnly` ở mục 4.2.
5. Một user có Allow `s3:*` trong identity policy, và bucket có bucket policy Deny `s3:DeleteObject` với principal là user đó. User có xóa được object không? Vì sao?
6. "Implicit deny" và "explicit deny" khác nhau thế nào? Thêm một Allow có sửa được cả hai không?
7. Trust policy và permission policy của một role trả lời hai câu hỏi gì? Loại nào có phần tử `Principal`?
8. Credential tạm thời của STS gồm những phần nào? Nhìn tiền tố access key, phân biệt key dài hạn và tạm thời thế nào?
9. Instance profile là gì? Vì sao không chép access key vào `.env` trên EC2?
10. Trong OIDC giữa GitHub và AWS, điều kiện `sub` để làm gì? Chuyện gì xảy ra nếu thiếu nó?
11. Vì sao passkey không dùng được cho `aws sts assume-role --token-code`? Lấy credential CLI bằng passkey thế nào?
12. Vì sao khóa học không dùng IAM Identity Center dù AWS khuyến nghị nó?
13. Policy Simulator khác lệnh thật ở điểm nào? Vì sao vẫn phải thử lại bằng lệnh thật?
14. Một policy Deny mọi action khi `aws:RequestedRegion` khác `ap-southeast-1`. Vì sao sau đó không xem được IAM nữa?
15. Bạn phát hiện một access key của `phuong-admin` đang hoạt động mà mình không nhớ đã tạo. Liệt kê các bước xử lý theo đúng thứ tự.

---

## 14. Bài tập tự làm

> Lời giải: [solutions/02-solutions.md](solutions/02-solutions.md) — chỉ mở sau khi tự làm.

**Bài 1 — Đọc policy.** Không chạy thử, cho biết các request sau được phép hay không, giải thích bằng tên statement:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Sid": "A", "Effect": "Allow", "Action": "s3:*", "Resource": "arn:aws:s3:::taskhub-backups-111122223333/*" },
    { "Sid": "B", "Effect": "Allow", "Action": "s3:ListBucket", "Resource": "arn:aws:s3:::taskhub-backups-111122223333" },
    { "Sid": "C", "Effect": "Deny", "Action": "s3:DeleteObject", "Resource": "*",
      "Condition": { "BoolIfExists": { "aws:MultiFactorAuthPresent": "false" } } }
  ]
}
```

(a) Tải lên object `pg-dumps/2027-01-10.sql.gz`. (b) Liệt kê các object trong bucket. (c) Xóa object khi gọi từ CLI bằng credential tạm thời **không** có MFA. (d) Xóa chính bucket.

**Bài 2 — Viết policy `taskhub-ec2-app` (bản nháp).** Viết customer managed policy cho `taskhub-ec2-role` đúng mô tả: đọc parameter dưới `/taskhub/dev/*` ở ap-southeast-1 (kèm `kms:Decrypt` qua khóa `aws/ssm`) và ghi log vào log group dưới `/taskhub/dev/*`. **Không** đưa quyền S3 vào đây — S3 backup là inline policy riêng `taskhub-ec2-s3-backup` ở [bài 05](05-s3.md). Giải thích vì sao tách thành hai policy có lợi. Dùng ARN cụ thể nhất có thể. Kiểm tra cú pháp bằng policy validator trên Console (chỉ bấm **Next** để xem cảnh báo, **không cần** tạo). Tra *Service Authorization Reference* để biết action nào hỗ trợ giới hạn theo resource.

**Bài 3 — Trust policy cho EC2 và cho GitHub.** Viết hai trust policy: (a) cho `taskhub-ec2-role` (dịch vụ EC2 được nhận); (b) cho `taskhub-github-deploy` (chỉ repo `phuong-dev/taskhub`, environment `production`). Giải thích vì sao (b) dùng `sts:AssumeRoleWithWebIdentity` còn (a) dùng `sts:AssumeRole`.

**Bài 4 — Profile role trong `~/.aws/config`.** Sau khi xong [bài 06](06-aws-cli.md), tạo lại role demo, rồi cấu hình profile `taskhub-ro` dùng `role_arn`, `source_profile = taskhub`, `mfa_serial`. Chạy `aws sts get-caller-identity --profile taskhub-ro` và mô tả CLI hỏi gì. Credential được cache ở đâu? Nhớ dọn role sau khi xong.

**Bài 5 — ADR.** Viết `docs/adr/NNNN-iam-user-thay-vi-identity-center.md` trong repo `taskhub` theo [mẫu ADR](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr): bối cảnh Free plan, các lựa chọn, quyết định, hệ quả (gồm: "khi chuyển sang Paid plan + Organizations thì sẽ làm gì").

**Bài 6 — Điều tra.** Chỉ dùng CloudTrail Event history, trả lời: hôm nay ai đã tạo policy `taskhub-readonly-demo-policy`, lúc mấy giờ (UTC), từ IP nào, qua Console hay CLI? (Gợi ý: trường `userAgent`, `sourceIPAddress`. Sự kiện IAM nằm ở region nào?)

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đạt bài này khi, **không nhìn tài liệu**:

- [ ] Vẽ được sơ đồ danh tính của `taskhub` (mục 6) và giải thích từng mũi tên.
- [ ] Viết được một policy JSON có `Condition` và đọc được policy người khác viết.
- [ ] Giải thích được logic đánh giá bằng 3 quy tắc, và trả lời đúng câu 5, 6 ở mục 13.
- [ ] Phân biệt được trust policy / permission policy, và viết được trust policy cho EC2.
- [ ] Debug một lỗi `AccessDenied` theo quy trình 5 bước, dùng đúng công cụ ở mỗi bước.
- [ ] Giải thích cho người khác vì sao `taskhub` có 0 access key dài hạn mà CLI, EC2, pipeline vẫn làm việc được.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [IAM — Policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) | Logic đánh giá, union identity/resource policy, intersection với boundary và SCP | 2026-10-31 |
| [IAM — Managed policies and inline policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html) | AWS managed / customer managed / inline | 2026-10-31 |
| [IAM — Global condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html) | `aws:RequestedRegion` (IAM luôn là `us-east-1`), `aws:MultiFactorAuthPresent` | 2026-10-31 |
| [IAM — Secure API access with MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html) | Trust policy yêu cầu MFA, `AssumeRole` với MFA | 2026-10-31 |
| [IAM — AWS Multi-factor authentication](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa.html) | Loại MFA, tối đa 8 thiết bị, root bắt buộc MFA, passkey không dùng cho STS | 2026-10-31 |
| [IAM — Switch to a role (console)](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-console.html) | Switch role, thời hạn phiên, role chaining 1 giờ | 2026-10-31 |
| [IAM — Create a role for OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html) | Trust policy cho GitHub OIDC, bắt buộc điều kiện `sub` | 2026-10-31 |
| [IAM — Policy simulator](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html) | Principal/Custom mode, condition key, khác biệt với môi trường thật | 2026-10-31 |
| [IAM — Last accessed information](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_last-accessed.html) | Tab Last Accessed, độ trễ 4 giờ | 2026-10-31 |
| [IAM Access Analyzer — policy generation](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html) | Sinh policy từ CloudTrail, cần trail, tối đa 90 ngày | 2026-10-31 |
| [IAM — Credential reports](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_getting-report.html) | Cột báo cáo, 4 giờ/lần | 2026-10-31 |
| [AWS CLI — decode-authorization-message](https://docs.aws.amazon.com/cli/latest/reference/sts/decode-authorization-message.html) | Giải mã thông báo lỗi quyền | 2026-10-31 |
| [CloudTrail — Event history](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/view-cloudtrail-events.html) | 90 ngày, management event, theo region, miễn phí | 2026-10-31 |
| [IAM Identity Center — Account instances](https://docs.aws.amazon.com/singlesignon/latest/userguide/account-instances-identity-center.html) | Account instance không hỗ trợ permission set | 2026-10-31 |
| [AWS Billing — Free plan](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) | Organizations tự nâng lên Paid plan | 2026-10-31 |
| [AWS CloudShell — Service quotas](https://docs.aws.amazon.com/cloudshell/latest/userguide/limits.html) | 1 GB lưu trữ mỗi region, hết phiên sau 20–30 phút không thao tác | 2026-10-31 |
