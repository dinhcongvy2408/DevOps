# Lời giải — 02. IAM

> Chỉ mở sau khi đã tự làm. Bài học: [02-iam.md](../02-iam.md). Đầu ra minh họa có thể khác trên tài khoản của bạn.

## Mục lục

- [Câu hỏi trong bài thực hành (❓)](#câu-hỏi-trong-bài-thực-hành-)
- [Mục 13 — Câu hỏi kiểm tra kiến thức](#mục-13--câu-hỏi-kiểm-tra-kiến-thức)
- [Mục 14 — Bài tập tự làm](#mục-14--bài-tập-tự-làm)

---

## Câu hỏi trong bài thực hành (❓)

**Bước 2 — Vì sao cần cả authenticator app khi đã có passkey?**
Theo tài liệu IAM, thông tin MFA của passkey/security key **không truyền được** cho các API STS (`AssumeRole`, `GetSessionToken`). Lệnh `aws sts assume-role --serial-number … --token-code …` cần thiết bị **TOTP**. Thêm nữa, có hai thiết bị nghĩa là mất một cái vẫn đăng nhập được mà không phải làm thủ tục khôi phục tài khoản.

**Bước 5 — Principal `arn:aws:iam::111122223333:root` có nghĩa là "chỉ root user"?**
**Không.** Trong trust policy, `…:root` đại diện cho **cả tài khoản**. Nghĩa thực tế: "tài khoản này được tin; danh tính nào trong tài khoản **được chính identity policy của nó cho phép** `sts:AssumeRole` trên role này thì nhận được". Vì `phuong-admin` có `AdministratorAccess` (gồm `sts:AssumeRole`), với principal `…:root` thì bất kỳ admin nào khác sau này cũng nhận được role. Thu hẹp về ARN user cụ thể là nguyên tắc quyền tối thiểu.

**Bước 6 — Bảng Policy Simulator:**

| Action | `ap-southeast-1` | `us-east-1` | Statement quyết định |
|---|---|---|---|
| `ec2:DescribeInstances` | allowed | implicitDeny | `Ec2ReadSingaporeOnly` (điều kiện region) |
| `ec2:RunInstances` | implicitDeny | implicitDeny | Không statement nào cho phép (`Describe*` không khớp `Run…`) |
| `s3:ListAllMyBuckets` | allowed | allowed | `ListBucketsGlobal` (không có điều kiện region) |
| `s3:CreateBucket` | implicitDeny | implicitDeny | Không statement nào cho phép |
| `iam:ListUsers` | implicitDeny | implicitDeny | Không statement nào cho phép |

Không có ô nào là `explicitDeny` vì policy không có `Deny`.

**Bước 7 — Vì sao EC2 Dashboard có ô lỗi cả ở Singapore?**
Một trang Console gọi nhiều API cùng lúc: vài ô của Dashboard gọi API ngoài `ec2:Describe*` (ví dụ dịch vụ khác như Compute Optimizer, Service Quotas, hoặc thông tin toàn cục) hoặc gọi sang region khác. Role chỉ có `ec2:Describe*` ở Singapore nên những ô đó lỗi. Đây cũng là lý do ví dụ chính thức trong tài liệu AWS về `aws:RequestedRegion` để `ec2:Describe*` **không** giới hạn region — Console EC2 cần đọc ở nhiều nơi.

**Bước 8d — `"allowed": false, "explicitDeny": false` nghĩa là gì?**
Request bị từ chối do **deny ngầm định**: không có `Allow` nào khớp (role không có `ec2:CreateVpc`), không phải do một `Deny` tường minh. `context.action` cho thấy `ec2:CreateVpc`; `context.conditions` liệt kê giá trị các condition key lúc đó (ví dụ `aws:RequestedRegion = ap-southeast-1`), rất hữu ích khi debug policy có `Condition`.

**Bước 9 — Lệnh `describe-instances --region us-east-1` nằm ở Event history region nào?**
Theo tài liệu CloudTrail, Event history ghi sự kiện **ở region nơi sự kiện xảy ra** → tìm ở **N. Virginia (us-east-1)**, không phải Singapore. Đây là bài học quan trọng: điều tra sự cố phải xem **đúng region**. (Lưu ý thêm: Event history có gồm sự kiện chỉ-đọc như `DescribeInstances`; nếu không thấy, chờ thêm vài phút.)

---

## Mục 13 — Câu hỏi kiểm tra kiến thức

**1.** Authentication = chứng minh danh tính (mật khẩu + MFA, chữ ký request). Authorization = xét policy để quyết định request có được phép. Đăng nhập thành công **chưa** có nghĩa làm được gì — user mới không có policy nào thì mọi thao tác đều bị deny ngầm định.

**2.** Root: danh tính tạo tài khoản (email), quyền tuyệt đối, không giới hạn được bằng IAM policy (chỉ SCP mới giới hạn được, mà SCP cần Organizations). `phuong-admin`: một IAM user, quyền đến từ policy (`AdministratorAccess` qua group), có thể bị thu hẹp, khóa, xóa. Việc bắt buộc dùng root: các tác vụ chỉ root làm được như đóng tài khoản, đổi một số thiết lập tài khoản/hỗ trợ — tham khảo danh sách "tasks that require root user credentials" trong tài liệu IAM. Mọi việc khác dùng `phuong-admin`.

**3.** Group chỉ là tập hợp user để gắn quyền — không có credential nên không đăng nhập được. Gắn quyền vào group: thêm/bớt người chỉ cần đổi thành viên; nhìn group là biết "ai có quyền gì"; tránh mỗi user mang một bộ policy khác nhau khó audit.

**4.** `Sid` "Ec2ReadSingaporeOnly": tên câu lệnh. `Effect: Allow`: cho phép. `Action: ec2:Describe*`: mọi API EC2 bắt đầu bằng `Describe`. `Resource: *`: mọi tài nguyên (đa số `Describe*` không hỗ trợ giới hạn theo resource). `Condition StringEquals aws:RequestedRegion = ap-southeast-1`: chỉ khi request gửi tới endpoint của Singapore.

**5.** **Không xóa được.** Trong cùng tài khoản, AWS xét cả identity-based và resource-based policy; **Deny tường minh ở bất kỳ policy nào thắng mọi Allow**. Allow `s3:*` của user không ghi đè được Deny của bucket policy.

**6.** Implicit deny: không có Allow nào khớp — trạng thái mặc định; **thêm Allow sửa được**. Explicit deny: có statement `Deny` khớp; **thêm Allow không sửa được** — phải sửa/xóa chính statement Deny (hoặc làm request không còn khớp điều kiện của nó).

**7.** Trust policy: **ai** được nhận role (có `Principal`, là resource-based policy gắn vào role). Permission policy: nhận role rồi **được làm gì** (identity-based, không có `Principal`).

**8.** `AccessKeyId`, `SecretAccessKey`, `SessionToken` (và thời điểm `Expiration`). Key tạm thời bắt đầu bằng `ASIA`, key dài hạn của IAM user bắt đầu bằng `AKIA`.

**9.** Instance profile là "vỏ" chứa một role để gắn vào EC2; ứng dụng trên máy lấy credential tạm thời của role qua IMDS. Không chép access key vào `.env` vì: key dài hạn nằm trên đĩa, ai đọc được file (hoặc snapshot đĩa, hoặc backup) là có key; key không tự hết hạn; phải tự xoay vòng. Instance role cho credential tự xoay, không có gì để lộ trên đĩa.

**10.** `sub` xác định **repo nào, nhánh/environment nào** được nhận role. Thiếu `sub`, mọi workflow của **mọi repo trên GitHub** (cùng dùng nhà cung cấp OIDC `token.actions.githubusercontent.com`) đều có thể nhận role của bạn. Theo tài liệu IAM, AWS hiện **từ chối** tạo/cập nhật trust policy cho GitHub OIDC nếu thiếu `sub` hoặc `sub` chỉ là wildcard.

**11.** Tài liệu IAM nêu rõ: không truyền được thông tin MFA của security key/passkey cho STS. Muốn có credential CLI khi dùng passkey: chạy `aws login` — xác thực (kèm passkey) diễn ra trên trình duyệt, CLI nhận credential tạm thời.

**12.** Organization instance cần AWS Organizations → tài khoản Free plan bị **tự động nâng lên Paid plan**. Account instance không hỗ trợ permission set nên không cấp được quyền truy cập tài khoản AWS. IAM user + MFA + `aws login` vẫn đạt mục tiêu "không credential dài hạn trên máy".

**13.** Simulator không gửi request thật, không dùng giá trị condition thật (bạn tự nhập), và theo tài liệu có thể khác thực tế ở vài cấu hình nâng cao (VPC endpoint policy, role chaining, nhiều resource policy…). Vì vậy luôn xác nhận bằng lệnh thật (an toàn nhất là `--dry-run` hoặc lệnh chỉ đọc).

**14.** IAM là dịch vụ toàn cục, endpoint đặt ở N. Virginia nên mọi request IAM có `aws:RequestedRegion = us-east-1` → khớp điều kiện "khác ap-southeast-1" → bị Deny tường minh. Cách sửa (theo tài liệu AWS): dùng `NotAction` để loại trừ các dịch vụ toàn cục (IAM, STS toàn cục, Route 53, CloudFront, Organizations, Support…) khỏi câu Deny.

**15.** Thứ tự:
1. **Vô hiệu hóa** key ngay (Deactivate) — ngắt quyền trước, điều tra sau.
2. **Điều tra** trong CloudTrail Event history (lọc theo *AWS access key*) ở **mọi region** đã có hoạt động: key đã gọi API gì, tạo tài nguyên gì, từ IP nào. Xem cả credential report (`access_key_1_last_used_date`, `…_region`, `…_service`).
3. **Dọn** tài nguyên lạ, kiểm tra IAM có user/role/key mới lạ không (kẻ tấn công thường tạo "cửa sau").
4. **Xóa** key.
5. Đổi mật khẩu, kiểm tra MFA, xem Billing; liên hệ AWS Support nếu có chi phí bất thường.
6. Tìm nguyên nhân gốc (key được tạo khi nào, bởi ai, lộ qua đâu) và ghi postmortem.

---

## Mục 14 — Bài tập tự làm

### Bài 1 — Đọc policy

(a) **Cho phép.** `s3:PutObject` trên `arn:aws:s3:::taskhub-backups-111122223333/pg-dumps/2027-01-10.sql.gz` khớp statement **A** (`s3:*` trên `bucket/*`). Không có Deny nào khớp (C chỉ áp cho `DeleteObject`).

(b) **Cho phép.** `s3:ListBucket` là thao tác trên **bucket** (ARN không có `/*`) → khớp statement **B**. Lưu ý: A không cho phép được vì A chỉ áp cho object (`/*`).

(c) **Từ chối — explicit deny.** Credential tạm thời không có MFA → `aws:MultiFactorAuthPresent = false` → `BoolIfExists … false` khớp → statement **C** Deny. Allow của A không ghi đè được. (Nếu gọi bằng access key dài hạn: key không có condition key này → `BoolIfExists` coi là khớp → cũng bị Deny. Đây chính là lý do tài liệu AWS khuyên dùng `…IfExists` cho kiểu Deny này.)

(d) **Từ chối — implicit deny.** `s3:DeleteBucket` áp cho ARN **bucket**; A chỉ cho phép trên object (`/*`), B chỉ cho phép `s3:ListBucket`. Không có Allow nào khớp.

### Bài 2 — Policy `taskhub-ec2-app` (bản nháp)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadAppParameters",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"],
      "Resource": [
        "arn:aws:ssm:ap-southeast-1:111122223333:parameter/taskhub/dev",
        "arn:aws:ssm:ap-southeast-1:111122223333:parameter/taskhub/dev/*"
      ]
    },
    {
      "Sid": "DecryptSecureStringViaSsm",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEquals": { "kms:ViaService": "ssm.ap-southeast-1.amazonaws.com" }
      }
    },
    {
      "Sid": "WriteAppLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"],
      "Resource": [
        "arn:aws:logs:ap-southeast-1:111122223333:log-group:/taskhub/dev/*",
        "arn:aws:logs:ap-southeast-1:111122223333:log-group:/taskhub/dev/*:log-stream:*"
      ]
    }
  ]
}
```

Giải thích các lựa chọn:

- **Hai ARN cho parameter:** `GetParametersByPath` dùng ARN của **chính đường dẫn** (`parameter/taskhub/dev`), còn `GetParameter` dùng ARN của từng parameter (`parameter/taskhub/dev/postgres-password`). Chỉ ghi `…/dev/*` thì `GetParametersByPath --path /taskhub/dev` sẽ bị từ chối. Lưu ý ARN parameter **không** có dấu `/` trước `taskhub` sau chữ `parameter`.
- **`kms:Decrypt` + `kms:ViaService`:** SecureString được mã hóa bằng KMS. Điều kiện `kms:ViaService` giới hạn: chỉ giải mã khi request đi **qua dịch vụ SSM**, không cho máy gọi KMS trực tiếp để giải mã thứ khác. Với khóa AWS managed `aws/ssm`, key policy của AWS vốn đã cho principal trong tài khoản dùng khóa qua SSM — câu lệnh này làm quyền **tường minh** và vẫn đúng nếu sau này đổi sang customer managed key. Kiểm tra lại trong tài liệu *Systems Manager — Parameter Store* khi làm dự án v2.
- **Log:** `CreateLogStream`/`PutLogEvents` là những gì Docker `awslogs` driver cần khi log group đã tồn tại (dự án v3 tạo sẵn log group `/taskhub/dev/app` có retention 7 ngày). Không cấp `logs:CreateLogGroup` để máy không tự tạo log group **không có retention** (lưu mãi, tốn tiền dần).
- **Không có S3 ở đây — vì sao tách?** Quyền backup nằm trong inline policy riêng `taskhub-ec2-s3-backup` ([bài 05](../05-s3.md)): `s3:ListBucket` giới hạn prefix `pg-dumps/*`, `s3:PutObject`/`s3:GetObject` trên `pg-dumps/*`, **không** có quyền xóa. Lợi ích của việc tách: mỗi policy một mục đích → đọc nhanh, audit dễ; gỡ riêng quyền backup (hoặc chỉ quyền app) mà không đụng phần kia; inline policy bị xóa cùng role nên không bị gắn nhầm sang role khác. Không có quyền xóa nghĩa là server bị chiếm cũng không xóa được backup (kết hợp versioning ở bài 05).
- Tra *Service Authorization Reference* để kiểm tra cột "Resource types" của từng action.

### Bài 3 — Trust policy

(a) `taskhub-ec2-role`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

(b) `taskhub-github-deploy`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:phuong-dev/taskhub:environment:production"
        }
      }
    }
  ]
}
```

Vì sao khác action: EC2 là **dịch vụ AWS** — AWS tự xác thực dịch vụ của chính mình, dùng `sts:AssumeRole`. GitHub là **bên ngoài**: nó chứng minh danh tính bằng một **web identity token** (JWT do GitHub ký); STS kiểm tra token với nhà cung cấp OIDC đã đăng ký rồi mới cấp credential → `sts:AssumeRoleWithWebIdentity`. Giá trị `sub` dạng `…:environment:production` là định dạng GitHub dùng khi job khai báo `environment` (xem ví dụ trong tài liệu GitHub về OIDC với AWS).

### Bài 4 — Profile role

```ini
[profile taskhub-ro]
role_arn = arn:aws:iam::111122223333:role/taskhub-readonly-demo
source_profile = taskhub
mfa_serial = arn:aws:iam::111122223333:mfa/phuong-authenticator
role_session_name = phuong-cli
region = ap-southeast-1
```

```bash
aws sts get-caller-identity --profile taskhub-ro
```

CLI hỏi `Enter MFA code for arn:aws:iam::111122223333:mfa/phuong-authenticator:` (không hiện ký tự gõ), rồi trả `Arn` dạng `…:assumed-role/taskhub-readonly-demo/phuong-cli`. Credential của role được cache ở `~/.aws/cli/cache/` đến khi hết hạn — lần chạy sau trong vòng 1 giờ không hỏi lại MFA.

> Nếu CLI báo không dùng được profile `taskhub` (loại `login_session`) làm `source_profile`, dùng cách được tài liệu `aws login` mô tả: tạo profile trung gian với `credential_process = aws configure export-credentials --profile taskhub --format process`, rồi trỏ `source_profile` vào profile trung gian đó. Ghi lại kết quả thực tế vào nhật ký — đây là chi tiết giáo trình chưa kiểm chứng trên máy thật.

Dọn dẹp: xóa role và policy demo như Bước 11 của bài; xóa khối `[profile taskhub-ro]` trong `~/.aws/config`; `rm -r ~/.aws/cli/cache`.

### Bài 5 — ADR (khung đáp án)

```markdown
# ADR-NNNN: Dùng IAM user + MFA + aws login thay vì IAM Identity Center

- Trạng thái: Đã chấp nhận
- Ngày: YYYY-MM-DD

## Bối cảnh
Tài khoản AWS cá nhân ở Free plan, một người dùng. Mục tiêu: không có credential dài hạn
trên laptop, có MFA, chi phí 0.

## Các lựa chọn đã cân nhắc
1. IAM Identity Center (organization instance) — cần AWS Organizations.
2. IAM Identity Center (account instance).
3. IAM user + MFA (passkey + authenticator) + `aws login`.
4. IAM user + access key + `aws configure`.

## Quyết định
Chọn (3):
- (1) làm tài khoản Free plan tự động nâng lên Paid plan.
- (2) không hỗ trợ permission set → không cấp được quyền vào tài khoản AWS.
- (4) tạo credential dài hạn trên đĩa — trái mục tiêu.
- (3) cho credential CLI tạm thời (làm mới 15 phút, phiên ≤ 12 giờ), MFA đi theo phiên đăng nhập.

## Hệ quả
- Tích cực: 0 access key dài hạn; MFA cho mọi phiên; không tốn tiền.
- Tiêu cực: không có SSO nhiều tài khoản; phải `aws login` lại sau tối đa 12 giờ;
  công cụ cũ chưa hỗ trợ console credentials phải dùng `credential_process`.
- Khi chuyển sang Paid plan và có nhiều tài khoản: bật Organizations + Identity Center
  organization instance, chuyển `phuong-admin` sang permission set, xóa IAM user,
  viết ADR mới thay thế ADR này.
```

### Bài 6 — Điều tra bằng CloudTrail

- Sự kiện IAM (`CreatePolicy`, `CreateRole`, `DeleteRole`…) là sự kiện của **dịch vụ toàn cục**; Event history ghi chúng ở **US East (N. Virginia)**. Chuyển Console sang `us-east-1` → CloudTrail → Event history → *Event name* = `CreatePolicy`.
- Trong JSON sự kiện: `userIdentity.arn` (ai), `eventTime` (UTC), `sourceIPAddress` (IP), `userAgent` — chứa chuỗi kiểu `aws-cli/2.x …` nếu tạo bằng CLI, hoặc chuỗi của Console/trình duyệt nếu tạo qua Console.
- Bằng CLI:

```bash
aws cloudtrail lookup-events --region us-east-1 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreatePolicy \
  --max-results 5 --query 'Events[].CloudTrailEvent' --output text \
  | python3 -c 'import sys, json
for line in sys.stdin:
    e = json.loads(line)
    print(e["eventTime"], e["userIdentity"].get("arn"), e["sourceIPAddress"], e["userAgent"][:60])'
```
