# 06. AWS CLI — Điều khiển AWS từ terminal

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [02. IAM](02-iam.md), [Linux 06 — Bash scripting](../01-LINUX/06-bash-scripting.md), [Linux 05 — Packages](../01-LINUX/05-packages-ssh.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (chính), `[PowerShell]` (tùy chọn), AWS CloudShell · 💰 Chi phí lab: **0 USD** (chỉ có lệnh đọc và `--dry-run`)

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

- Cài **AWS CLI v2** trên WSL Ubuntu đúng cách, **kiểm chứng chữ ký** gói cài trước khi chạy.
- Đăng nhập CLI bằng **`aws login`** (credential tạm thời, không có access key dài hạn) với profile `taskhub`.
- Giải thích CLI lấy **credential** và **region** từ đâu, theo thứ tự ưu tiên nào.
- Dùng thành thạo `--output`, `--query` (JMESPath), `--filters`, phân trang, `--dry-run`, waiter.
- Đọc và xử lý các lỗi CLI hay gặp: `ExpiredToken`, `AccessDenied`, sai region, lẫn credential cũ.
- Viết script Bash gọi AWS CLI an toàn, gồm script **`find-leftovers.sh`** dùng cho mục dọn dẹp ở mọi lab AWS sau này.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Console tiện để **khám phá**, nhưng công việc DevOps thật diễn ra ở terminal và trong script:

| Tình huống | Vì sao cần CLI |
|---|---|
| Kiểm tra cuối buổi "còn tài nguyên nào đang tốn tiền?" | Một script quét mọi dịch vụ trong 10 giây, thay vì bấm 10 trang Console |
| Pipeline deploy (dự án v3) | GitHub Actions gọi `aws ssm send-command` — không có Console nào trong pipeline |
| Debug "EC2 này có IP gì, SG nào, role nào?" | `aws ec2 describe-instances --query …` trả lời đúng một dòng |
| Ghi lại thao tác vào runbook | Lệnh CLI chép lại được, chạy lại được; ảnh chụp Console thì không |
| Terraform (Module 07) | Dùng **cùng** cơ chế credential/region với CLI — hiểu CLI là hiểu nền của Terraform |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. CLI chỉ là một client gọi API

Mọi thứ trên AWS là **API qua HTTPS**. Console, CLI, SDK, Terraform đều chỉ là các client khác nhau gửi cùng loại request:

```text
aws ec2 describe-vpcs --region ap-southeast-1
        │
        ▼  CLI dịch thành request HTTPS, KÝ bằng credential của bạn (SigV4)
POST https://ec2.ap-southeast-1.amazonaws.com/   Action=DescribeVpcs
        │
        ▼  EC2 xác thực chữ ký → IAM xét policy (bài 02) → trả JSON
```

Hệ quả: lệnh CLI bị `AccessDenied` thì cùng thao tác trên Console cũng bị từ chối (và ngược lại).

### 3.2. Hai thứ CLI luôn cần biết: credential và region

- **Credential**: ký request — "tôi là ai". Ở khóa học này: credential tạm thời từ `aws login`.
- **Region**: gửi request tới endpoint nào. Phần lớn tài nguyên (VPC, EC2, RDS…) **thuộc về một region**. Gọi sai region = "không thấy tài nguyên" dù nó vẫn đang chạy (và tính tiền) ở region khác.

### 3.3. File cấu hình ở `~/.aws/`

| File | Chứa gì | Có bí mật không |
|---|---|---|
| `~/.aws/config` | Profile, region, output, `login_session`, `role_arn`, `mfa_serial`… | Không nên có |
| `~/.aws/credentials` | Access key dài hạn (cách cũ) | **Có** — khóa học này để file này **trống hoặc không tồn tại** |
| `~/.aws/login/cache/` | Credential tạm thời do `aws login` tạo, tự làm mới | **Có** (hết hạn nhanh) |
| `~/.aws/cli/cache/` | Credential tạm thời khi dùng profile có `role_arn` | **Có** (hết hạn nhanh) |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Cài AWS CLI v2 trên WSL — và vì sao phải kiểm chữ ký

Tài liệu AWS đưa ra hai cách cho Linux: script `install.sh` dạng `curl … | bash`, và gói zip `awscli-exe-linux-x86_64.zip`. Khóa học dùng **gói zip + kiểm chữ ký PGP**, vì:

- `curl … | bash` chạy code tải về **ngay lập tức**, bạn không có cơ hội đọc hay kiểm chứng (đã bàn ở [Linux bài 05](../01-LINUX/05-packages-ssh.md)).
- Chữ ký PGP chứng minh file zip **đúng là do AWS CLI Team ký** và không bị sửa trên đường truyền.

Bản `awscli` trong kho apt của Ubuntu là **v1** (hoặc bản cũ) — **không dùng**. Lệnh `aws login` cần **v2 từ 2.32.0 trở lên**.

### 4.2. 🟥 `aws login` — credential tạm thời từ phiên Console

Theo tài liệu AWS CLI:

- Bạn chạy `aws login --profile taskhub`, CLI mở trình duyệt; bạn chọn phiên Console đang đăng nhập (hoặc đăng nhập mới — có MFA/passkey như thường).
- CLI nhận **credential tạm thời**, lưu ở `~/.aws/login/cache/`, **tự làm mới mỗi 15 phút**; cả phiên sống tối đa bằng session duration của principal (**tối đa 12 giờ**), sau đó chạy lại `aws login`.
- File `~/.aws/config` chỉ có tham chiếu tới phiên, **không có bí mật**:

```ini
[profile taskhub]
login_session = arn:aws:iam::111122223333:user/phuong-admin
region = ap-southeast-1
```

- Máy không có trình duyệt (server, hoặc khi callback bị firewall chặn): `aws login --remote` — CLI in một URL, bạn mở trên máy có trình duyệt rồi dán mã ủy quyền trở lại terminal.
- Quyền cần có: managed policy **`SignInLocalDevelopmentAccess`** (gồm `signin:AuthorizeOAuth2Access`, `signin:CreateOAuth2Token`). `phuong-admin` có `AdministratorAccess` nên đã bao gồm.
- Đăng xuất: `aws logout --profile taskhub`, hoặc `aws logout --all`.

**So sánh với cách cũ** `aws configure` + access key:

| | `aws configure` + access key | `aws login` ✅ |
|---|---|---|
| Credential | Dài hạn, nằm trong `~/.aws/credentials` | Tạm thời, tự làm mới 15 phút |
| Laptop bị đánh cắp / lộ file | Kẻ gian dùng được đến khi bạn phát hiện | Hết hạn tối đa sau 12 giờ |
| MFA | Phải tự xử lý bằng `get-session-token` | Đi theo phiên đăng nhập (passkey dùng được) |
| Rotation | Bạn phải tự xoay key | Không có key để xoay |

Bạn sẽ gặp `aws configure` trong rất nhiều tutorial cũ. Hiểu nó, nhưng **đừng tạo access key** cho `phuong-admin`.

### 4.3. 🟥 Thứ tự ưu tiên cấu hình

Theo tài liệu AWS CLI: **tham số dòng lệnh** > **biến môi trường** > **file cấu hình (profile)**.

| Thiết lập | Dòng lệnh | Biến môi trường | File config |
|---|---|---|---|
| Profile | `--profile taskhub` | `AWS_PROFILE` | (mặc định: `[default]`) |
| Region | `--region` | `AWS_REGION` **thắng** `AWS_DEFAULT_REGION` | `region = …` trong profile |
| Định dạng | `--output` | `AWS_DEFAULT_OUTPUT` | `output = …` |
| Pager | `--no-cli-pager` | `AWS_PAGER=""` tắt pager | `cli_pager =` |
| Credential | — | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | profile |

Hai cái bẫy:

1. Biến `AWS_ACCESS_KEY_ID`… còn sót trong shell (ví dụ từ bài 02 Bước 8) **thắng** profile `taskhub` → bạn đang chạy bằng danh tính khác mà không biết.
2. Profile vừa có `login_session` vừa có key cũ trong `~/.aws/credentials` → tài liệu AWS ghi nhận lỗi `ExpiredToken`/`AccessDenied` khó hiểu. Kiểm tra bằng `aws configure list` (cột `TYPE` phải là `login`).

### 4.4. 🟥 `--output`: chọn định dạng cho người đọc hay cho máy đọc

| Định dạng | Dùng khi |
|---|---|
| `json` (mặc định) | Đọc đầy đủ cấu trúc; chuyển cho `python3 -m json.tool` hoặc `jq` |
| `table` | Người đọc trên terminal |
| `text` | **Script Bash**: cột phân cách bằng tab, dễ `read`, `cut`, `while` |
| `yaml` / `yaml-stream` | Đọc dễ hơn JSON |

### 4.5. 🟥 `--filters` (phía server) và `--query` (phía client)

| | `--filters` | `--query` |
|---|---|---|
| Ai lọc | **Dịch vụ AWS** — chỉ trả về bản ghi khớp | **CLI trên máy bạn** — lọc sau khi nhận toàn bộ phản hồi |
| Cú pháp | Riêng từng API: `Name=tag:Project,Values=taskhub` | JMESPath, giống nhau ở mọi lệnh |
| Khi nào dùng | Lọc trước để giảm dữ liệu (tag, state, VPC…) | Chọn cột, đổi tên, sắp xếp, đếm |

Dùng **cả hai**: lọc ở server, định hình ở client.

```bash
aws ec2 describe-instances \
  --filters Name=tag:Project,Values=taskhub Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].{Id:InstanceId,Ip:PublicIpAddress,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

Một điểm tinh tế từ tài liệu AWS: với `--output text`, `--query` chạy **trên từng trang** kết quả; với `json`/`yaml`, nó chạy **một lần** trên toàn bộ. Với danh sách dài, `--output text` + biểu thức kiểu `[0]` có thể trả ra nhiều dòng hơn bạn nghĩ.

**JMESPath tối thiểu cần thuộc:**

| Biểu thức | Nghĩa |
|---|---|
| `Vpcs[]` | Làm phẳng danh sách |
| `Vpcs[0]` | Phần tử đầu |
| `Vpcs[].VpcId` | Lấy một trường từ mọi phần tử |
| `Vpcs[].[VpcId,CidrBlock]` | Nhiều trường (danh sách) — hợp với `--output text` |
| `Vpcs[].{Id:VpcId,Cidr:CidrBlock}` | Nhiều trường có nhãn — hợp với `--output table` |
| `Vpcs[?IsDefault==\`true\`]` | Lọc theo điều kiện; giá trị literal đặt trong dấu backtick |
| `Tags[?Key==\`Name\`]\|[0].Value` | Lấy giá trị tag `Name` (mẫu cực kỳ hay dùng) |
| `length(Vpcs)` | Đếm |
| `sort_by(Subnets,&CidrBlock)` | Sắp xếp |

> **Dấu nháy trong Bash:** bọc cả biểu thức `--query` trong **nháy đơn** `'...'`. Bên trong nháy đơn, dấu backtick `` ` `` không bị Bash hiểu là thay thế lệnh.

### 4.6. 🟥 Phân trang

Theo tài liệu AWS CLI, mặc định CLI **tự gọi nhiều lần** để lấy **toàn bộ** kết quả. Các tùy chọn:

| Tùy chọn | Tác dụng |
|---|---|
| `--page-size N` | Mỗi lần gọi API lấy N bản ghi (vẫn lấy hết) — dùng khi bị timeout |
| `--max-items N` | Chỉ in N bản ghi, kèm `NextToken` để lấy tiếp |
| `--starting-token …` | Tiếp tục từ `NextToken` |
| `--no-paginate` | Chỉ gọi **một** lần, lấy trang đầu |

Đừng nhầm với **pager** phía client: CLI v2 mặc định đẩy đầu ra qua `less`. Trong script luôn đặt `export AWS_PAGER=""` hoặc dùng `--no-cli-pager`, nếu không script có thể "treo" chờ bạn bấm `q`.

### 4.7. 🟥 `--dry-run` — hỏi "tôi có quyền không?" mà không làm gì

Nhiều lệnh EC2 có `--dry-run`: AWS chỉ kiểm tra **quyền** rồi dừng.

| Kết quả | Nghĩa |
|---|---|
| `DryRunOperation: Request would have succeeded, but DryRun flag is set.` | Bạn **có quyền** (không có gì được tạo) |
| `UnauthorizedOperation` | **Không có quyền** |

⚠️ `--dry-run` chỉ có ở một số API (chủ yếu EC2). Quên cờ này trên lệnh tạo tài nguyên = **tạo thật, tính tiền thật**. Trong lab bài này chỉ dùng `create-vpc --dry-run` — kể cả lỡ tạo thật thì VPC rỗng không tính phí và xóa được ngay.

### 4.8. 🟨 Waiter — chờ đến khi đạt trạng thái

```bash
aws ec2 wait instance-running --instance-ids i-0abc123def4567890
```

Theo tài liệu: lệnh này gọi `describe-instances` **mỗi 15 giây** cho đến khi mọi instance ở trạng thái `running`; sau **40 lần** không đạt thì thoát với mã **255**. Trong script, waiter thay cho vòng lặp `sleep` tự viết.

### 4.9. 🟥 Viết script với AWS CLI

Áp dụng [Linux bài 06](../01-LINUX/06-bash-scripting.md):

- `set -euo pipefail` — lệnh `aws` lỗi thì script dừng, không chạy tiếp với dữ liệu rỗng.
- `export AWS_PAGER=""`.
- Luôn ghi `--region` rõ ràng (hoặc kiểm tra `AWS_REGION`) — script chạy ở máy khác vẫn đúng region.
- Dùng `--output text` + `--query` chọn đúng cột; đọc bằng `read`/`while read`.
- **Script dọn dẹp tách làm hai:** script **liệt kê** (chỉ đọc, chạy thoải mái) và thao tác **xóa** (làm tay hoặc script riêng, có xác nhận). Bài này chỉ viết loại đầu.
- 🟨 `jq` là công cụ xử lý JSON mạnh hơn `--query` trong vài trường hợp; khóa học dùng `--query` và `python3 -m json.tool` (có sẵn trên Ubuntu) để không cần cài thêm.

### 4.10. 🟨 AWS CloudShell

Terminal trên trình duyệt, mở từ thanh trên của Console. Theo tài liệu AWS:

- **Không tính thêm phí** (chỉ trả tiền tài nguyên bạn tạo từ đó).
- Đã có sẵn AWS CLI, tự dùng danh tính Console của bạn.
- **1 GB** lưu trữ bền vững trong `$HOME` **mỗi region**; dữ liệu bị xóa nếu không dùng CloudShell ở region đó **120 ngày**.
- Phiên kết thúc sau **20–30 phút** không thao tác; phiên dài tối đa khoảng **12 giờ**.

Dùng khi: máy chưa cài CLI, cần chạy nhanh một lệnh, hoặc đang ở máy lạ. Không thay được WSL cho công việc hằng ngày (không có repo, công cụ của bạn).

### 4.11. Gặp lại ở đâu

| Kiến thức bài này | Gặp lại ở |
|---|---|
| `find-leftovers.sh` | Mục **Dọn dẹp** của mọi lab AWS: [VPC](03-vpc-networking.md), [EC2](04-ec2.md), [S3](05-s3.md), [RDS](07-rds.md), [ELB/ASG](08-elb-autoscaling.md), dự án v2/v3 |
| `--filters` theo tag `Project=taskhub` | Mọi lab AWS; tag `ManagedBy=terraform` ở Module 07 |
| `aws ssm send-command` + `get-command-invocation` | Pipeline deploy dự án v3 |
| Thứ tự ưu tiên credential/region | Terraform AWS provider (Module 07) dùng cùng cơ chế |
| Waiter | Script deploy, Terraform |
| `--dry-run`, `decode-authorization-message` | Debug quyền khi viết policy cho `taskhub-ec2-role`, `taskhub-github-deploy` |

---

## 5. Ví dụ thực tế

**Tình huống 1 — "Instance biến mất".** Một bạn tạo EC2 hôm trước, hôm sau chạy `aws ec2 describe-instances` thì danh sách rỗng, tưởng đã bị xóa. Thật ra hôm trước tạo trên Console ở region **N. Virginia** (mặc định của nhiều tài khoản mới), còn CLI đang ở `ap-southeast-1`. Instance vẫn chạy và tính tiền. Bài học: luôn ghi region; chạy `find-leftovers.sh ap-southeast-1 us-east-1`.

**Tình huống 2 — Script "treo" trong cron.** Script báo cáo chạy tay thì ổn, chạy trong cron thì không bao giờ kết thúc. Nguyên nhân: CLI v2 mở pager `less` và chờ phím bấm. Sửa: `export AWS_PAGER=""`.

**Tình huống 3 — Hai danh tính.** Sau khi thử assume role ở bài 02, bạn quên `unset AWS_ACCESS_KEY_ID…`. Mọi lệnh sau đó chạy bằng role chỉ-đọc, lỗi `AccessDenied` liên tục dù `~/.aws/config` hoàn toàn đúng. `aws configure list` cho thấy cột `TYPE` là `env` thay vì `login`.

---

## 6. Sơ đồ kiến trúc

CLI quyết định danh tính và đích đến của mỗi lệnh như thế nào:

```text
 aws ec2 describe-vpcs [--profile X] [--region Y]
   │
   ├─► Region:      --region  →  AWS_REGION  →  AWS_DEFAULT_REGION  →  region trong profile
   │
   ├─► Profile:     --profile →  AWS_PROFILE →  [default]
   │
   └─► Credential (lấy cái đầu tiên tìm thấy):
         biến môi trường AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN
           → nguồn trong profile:  login_session (aws login)  → ~/.aws/login/cache/
                                   role_arn + source_profile   → ~/.aws/cli/cache/
                                   aws_access_key_id (cũ)      → ~/.aws/credentials
           → trên EC2: instance role qua IMDS 169.254.169.254
   │
   ▼
 Ký request (SigV4) ──HTTPS──► https://ec2.<region>.amazonaws.com ──► IAM xét quyền ──► JSON
                                                                           │
                                                          CloudTrail ghi lại (bài 02)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích |
|---|---|
| `aws --version` | Kiểm tra phiên bản (cần ≥ 2.32.0 cho `aws login`) |
| `aws login --profile taskhub` / `--remote` | Đăng nhập, lấy credential tạm thời |
| `aws logout --profile taskhub` / `--all` | Xóa credential đã cache |
| `aws configure list` | CLI đang lấy profile, credential, region **từ đâu** |
| `aws configure set region ap-southeast-1 --profile taskhub` | Sửa một thiết lập trong profile |
| `aws sts get-caller-identity` | Tôi là ai |
| `aws ec2 describe-regions` / `describe-availability-zones` | Region, AZ |
| `aws ec2 describe-vpcs` / `describe-subnets` / `describe-instances` | Đọc tài nguyên mạng và máy |
| `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true` | Instance type thuộc Free Tier |
| `aws ssm get-parameters --names /aws/service/canonical/…` | Lấy AMI Ubuntu mới nhất từ tham số công khai |
| `aws resourcegroupstaggingapi get-resources --tag-filters …` | Liệt kê tài nguyên theo tag, nhiều dịch vụ một lần |
| `aws ec2 wait …` | Chờ trạng thái |
| `aws <lệnh> help` | Tài liệu ngay trong terminal |
| `aws <lệnh> --debug` | In chi tiết: lấy credential từ đâu, request/response HTTP |

---

## 8. Giải thích câu lệnh và tham số

> Mọi đầu ra là **minh họa**.

### 8.1. `aws configure list`

```bash
aws configure list --profile taskhub
```

```text
NAME       : VALUE                    : TYPE             : LOCATION
profile    : taskhub                  : manual           : --profile
access_key : ****************WXYZ     : login            :
secret_key : ****************abcd     : login            :
region     : ap-southeast-1           : config-file      : ~/.aws/config
```

Cột **TYPE** cho biết nguồn: `login` (đúng ý), `env` (biến môi trường đang ghi đè), `shared-credentials-file` (key cũ trong `~/.aws/credentials` — cần xóa).

### 8.2. Lấy AMI Ubuntu 24.04 mới nhất

```bash
aws ssm get-parameters \
  --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameters[0].Value' --output text
```

```text
ami-0123456789abcdef0
```

Canonical công bố ID AMI dưới dạng **tham số SSM công khai** theo mẫu `/aws/service/canonical/ubuntu/{product}/{release}/stable/{serial}/{arch}/hvm/{vol}/ami-id`. AMI ID **khác nhau giữa các region** và **đổi** mỗi khi có bản build mới — vì thế không bao giờ chép cứng AMI ID vào tài liệu hay script.

### 8.3. Instance type thuộc Free Tier

```bash
aws ec2 describe-instance-types \
  --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[*].[InstanceType]" \
  --output text | sort
```

```text
c7i-flex.large
m7i-flex.large
t3.micro
t3.small
t4g.micro
t4g.small
```

Đây là lệnh trong tài liệu EC2 về Free Tier. Kết quả cho tài khoản tạo từ 15/07/2025 trở đi; với Free plan, mức dùng được **trừ vào credit**, không phải "750 giờ miễn phí" như tài liệu cũ.

### 8.4. `--dry-run`

```bash
aws ec2 create-vpc --cidr-block 10.99.0.0/16 --dry-run
```

```text
An error occurred (DryRunOperation) when calling the CreateVpc operation: Request would have succeeded, but DryRun flag is set.
```

Lệnh "lỗi" (mã thoát khác 0) nhưng nội dung là tin tốt: bạn có quyền. Trong script, phải đọc **nội dung** lỗi chứ không chỉ mã thoát.

### 8.5. Liệt kê tài nguyên theo tag, nhiều dịch vụ

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=taskhub \
  --query 'ResourceTagMappingList[].ResourceARN' --output text
```

Trả về ARN mọi tài nguyên (EC2, VPC, S3, RDS…) mang tag `Project=taskhub` **trong một region**. Đây là lý do khóa học bắt **tag mọi thứ**: một lệnh tìm lại được hết. Giới hạn: không tìm thấy tài nguyên **quên gắn tag** → `find-leftovers.sh` quét thêm theo từng loại tài nguyên.

### 8.6. `--debug`: CLI lấy credential từ đâu?

```bash
aws sts get-caller-identity --debug 2>&1 | grep -i -m3 credential
```

```text
... botocore.credentials - DEBUG - Looking for credentials via: env
... botocore.credentials - DEBUG - Looking for credentials via: login
... botocore.credentials - INFO - Found credentials ...
```

`--debug` in ra stderr rất nhiều — luôn lọc bằng `grep`. Không dán toàn bộ đầu ra `--debug` lên mạng: nó có thể chứa thông tin tài khoản.

---

## 9. Bài thực hành từng bước

> 💰 **Ước tính chi phí: 0 USD.** Chỉ có lệnh đọc (`describe`, `list`, `get`) và `--dry-run`. Không lệnh nào tạo tài nguyên.
> ⏱️ ~90 phút. Chuẩn bị: đã xong [bài 02](02-iam.md) (`phuong-admin` có MFA).

### Bước 1 — Dọn cài đặt cũ (nếu có) `[WSL]`

```bash
which -a aws
aws --version 2>/dev/null
dpkg -l | grep -i awscli
ls -la ~/.aws 2>/dev/null
```

- Có gói apt `awscli` (v1) → ⚠️ gỡ: `sudo apt remove awscli`.
- Có file `~/.aws/credentials` chứa key từ tutorial cũ → mở xem; nếu là key **thật** của tài khoản bạn, vào IAM **vô hiệu hóa và xóa key đó** trước, rồi mới xóa file.

### Bước 2 — Tải, kiểm chữ ký, cài AWS CLI v2 `[WSL]`

```bash
sudo apt update && sudo apt install -y unzip gnupg curl
mkdir -p ~/downloads/awscli && cd ~/downloads/awscli

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig" -o awscliv2.sig
```

**Nhập khóa công khai của AWS CLI Team:** mở trang [Installing or updating the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) → phần Linux → bước *Verify the integrity and authenticity* → chép **toàn bộ** khối `-----BEGIN PGP PUBLIC KEY BLOCK----- … -----END PGP PUBLIC KEY BLOCK-----` vào file `aws-cli-public-key.asc`.

> Vì sao không chép khóa từ giáo trình này? Nguyên tắc: khóa dùng để **kiểm chứng** phải lấy từ **nguồn chính thức** qua HTTPS, không lấy qua một bên trung gian (kể cả giáo trình). Nếu bên trung gian bị sửa, cả khóa lẫn file đều có thể giả.

```bash
nano aws-cli-public-key.asc          # dán khối khóa, lưu
gpg --import aws-cli-public-key.asc
gpg --verify awscliv2.sig awscliv2.zip
```

Kỳ vọng (theo tài liệu AWS, phần chính):

```text
gpg: Good signature from "AWS CLI Team <aws-cli@amazon.com>" [unknown]
gpg: WARNING: This key is not certified with a trusted signature!
Primary key fingerprint: FB5D B77F D5C1 18B8 0511  ADA8 A631 0ACC 4672 475C
```

- `Good signature` + fingerprint **khớp** `FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C` → file hợp lệ.
- Dòng `WARNING: not certified` là **bình thường**: bạn chưa "ký tin cậy" khóa này trong keyring của mình. Điều quan trọng là fingerprint khớp với tài liệu chính thức.
- `BAD signature` → **dừng lại**, xóa file, tải lại.

```bash
unzip -q awscliv2.zip
sudo ./aws/install
aws --version
```

```text
aws-cli/2.3x.x Python/3.x.x Linux/6.x.x-microsoft-standard-WSL2 exe/x86_64.ubuntu.22
```

Phiên bản phải **≥ 2.32.0**. Cập nhật về sau (tải zip mới, kiểm chữ ký, rồi):

```bash
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
```

🟨 **Windows (tùy chọn):** cài bằng MSI từ cùng trang tài liệu, kiểm tra bằng `aws --version` trong `[PowerShell]`. Cấu hình của Windows nằm ở `%USERPROFILE%\.aws\`, **tách biệt** với WSL. Khóa học dùng WSL.

### Bước 3 — `aws login` với profile `taskhub` `[WSL]`

```bash
aws login --profile taskhub
```

- CLI hỏi region → nhập `ap-southeast-1`.
- CLI cố mở trình duyệt. Trong WSL, nếu không tự mở, **chép URL** in ra vào trình duyệt Windows.
- Chọn phiên `phuong-admin` (hoặc đăng nhập bằng passkey) → quay lại terminal.
- Nếu trình duyệt báo không kết nối được về `localhost`, hoặc firewall chặn: `aws login --profile taskhub --remote` rồi dán mã ủy quyền.

```bash
cat ~/.aws/config
ls -la ~/.aws/login/cache/
aws configure list --profile taskhub
aws sts get-caller-identity --profile taskhub
```

Kiểm tra: `~/.aws/config` có `login_session = …user/phuong-admin` và **không có** chuỗi bí mật; cột `TYPE` là `login`.

Đặt profile mặc định cho mọi terminal:

```bash
echo 'export AWS_PROFILE=taskhub' >> ~/.bashrc
source ~/.bashrc
aws sts get-caller-identity --query Arn --output text
```

❓ Quyền của thư mục `~/.aws/login/cache/` và các file bên trong là gì (`ls -la`)? Vì sao như vậy là đúng? (Nhắc lại [Linux bài 03](../01-LINUX/03-permissions-users-groups.md).)

### Bước 4 — Region, AZ, VPC mặc định `[WSL]`

```bash
aws ec2 describe-regions --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort | head -20

aws ec2 describe-availability-zones \
  --query 'AvailabilityZones[].[ZoneName,ZoneId,State]' --output table

aws ec2 describe-vpcs \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,Default:IsDefault}' --output table

aws ec2 describe-vpcs --region us-east-1 \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,Default:IsDefault}' --output table
```

❓ Hai lệnh `describe-vpcs` cuối trả về VPC có cùng ID không? Điều đó nói gì về phạm vi của VPC?

❓ `ZoneName` (`ap-southeast-1a`) và `ZoneId` (`apse1-az…`) khác nhau thế nào? (Đọc tài liệu AWS về AZ ID — đây là câu hỏi bạn sẽ gặp lại ở bài VPC.)

### Bước 5 — Luyện `--output` và `--query` `[WSL]`

Chạy cùng một truy vấn với 4 định dạng và so sánh:

```bash
for fmt in json yaml table text; do
  echo "=== $fmt ==="
  aws ec2 describe-availability-zones --query 'AvailabilityZones[].[ZoneName,State]' --output "$fmt"
done
```

Lấy AMI Ubuntu và instance type Free Tier (mục 8.2, 8.3):

```bash
AMI_ID="$(aws ssm get-parameters \
  --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameters[0].Value' --output text)"
echo "AMI Ubuntu 24.04 mới nhất ở ap-southeast-1: $AMI_ID"

aws ec2 describe-images --image-ids "$AMI_ID" \
  --query 'Images[0].{Name:Name,Created:CreationDate,Owner:OwnerId,Arch:Architecture}' --output table

aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
  --query "InstanceTypes[*].[InstanceType]" --output text | sort
```

Viết **tự mình** (không nhìn lời giải) truy vấn trả về: số lượng AZ ở trạng thái `available` (dùng `length()`).

### Bước 6 — `--filters` theo tag (chưa có tài nguyên → kết quả rỗng là đúng) `[WSL]`

```bash
aws ec2 describe-vpcs --filters Name=tag:Project,Values=taskhub --query 'Vpcs[].VpcId'
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=taskhub \
  --query 'ResourceTagMappingList[].ResourceARN'
```

Kỳ vọng: `[]`. Danh sách rỗng **không phải lỗi** — chỉ là chưa có tài nguyên nào mang tag đó. Từ bài 03 (VPC) trở đi, các lệnh này sẽ có kết quả.

### Bước 7 — `--dry-run`, waiter, phân trang `[WSL]`

```bash
# Kiểm tra quyền tạo VPC — KHÔNG xóa cờ --dry-run
aws ec2 create-vpc --cidr-block 10.99.0.0/16 --dry-run
echo "exit code: $?"

# Waiter trên VPC mặc định: trả về ngay vì VPC đã "available"
DEFAULT_VPC="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
time aws ec2 wait vpc-available --vpc-ids "$DEFAULT_VPC"

# Phân trang: chỉ in 2 AMI của Canonical, xem NextToken
aws ec2 describe-images --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
  --max-items 2 --query '{Images:Images[].Name,Next:NextToken}'
```

> `099720109477` là ID tài khoản AWS mà Canonical dùng để phát hành AMI Ubuntu chính thức (được nêu trong tài liệu Ubuntu trên AWS). Lọc theo `--owners` là cách tránh AMI giả mạo mang tên "ubuntu" do người khác đăng.

❓ Lệnh `create-vpc --dry-run` có exit code bao nhiêu? Vì sao script tự động không thể chỉ dựa vào exit code để biết "có quyền hay không"?

### Bước 8 — Thí nghiệm lỗi có chủ đích `[WSL]`

**8a. Sai region:**

```bash
AWS_REGION=us-east-1 aws configure list | grep region
AWS_REGION=us-east-1 aws ec2 describe-vpcs --query 'Vpcs[].VpcId' --output text
```

❓ `AWS_REGION` đặt ngay trước lệnh chỉ ảnh hưởng lệnh đó hay cả shell? (Nhắc lại biến môi trường ở Linux bài 06.)

**8b. Biến môi trường ghi đè profile:**

```bash
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
aws configure list
aws sts get-caller-identity
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
aws sts get-caller-identity --query Arn --output text
```

Đây là key **ví dụ** công khai trong tài liệu AWS — không thuộc về ai. Ghi lại thông báo lỗi và cột `TYPE` trong `aws configure list`.

**8c. Hết phiên:**

```bash
aws logout --profile taskhub
aws sts get-caller-identity
aws login --profile taskhub
```

Ghi lại thông báo lỗi khi chưa đăng nhập.

### Bước 9 — Script `list-taskhub.sh` (chỉ đọc) `[WSL]`

```bash
mkdir -p ~/devops-lab/06-aws && cd ~/devops-lab/06-aws
nano list-taskhub.sh
```

```bash
#!/usr/bin/env bash
# list-taskhub.sh — liệt kê tài nguyên mang tag Project=taskhub (CHỈ ĐỌC)
set -euo pipefail

export AWS_PAGER=""
region="${1:-${AWS_REGION:-ap-southeast-1}}"
tag_filter="Name=tag:Project,Values=taskhub"

echo "== VPC ($region) =="
aws ec2 describe-vpcs --region "$region" --filters "$tag_filter" \
  --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' --output table

echo "== Subnet =="
aws ec2 describe-subnets --region "$region" --filters "$tag_filter" \
  --query 'sort_by(Subnets,&CidrBlock)[].{Id:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

echo "== Security group =="
aws ec2 describe-security-groups --region "$region" --filters "$tag_filter" \
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId}' --output table

echo "== EC2 instance (chưa terminate) =="
aws ec2 describe-instances --region "$region" \
  --filters "$tag_filter" Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,PublicIp:PublicIpAddress,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

echo "== S3 bucket tên bắt đầu bằng taskhub- (toàn cục) =="
aws s3api list-buckets --query 'Buckets[?starts_with(Name, `taskhub-`)].Name' --output text
```

```bash
chmod +x list-taskhub.sh
bash -n list-taskhub.sh && ./list-taskhub.sh
```

Hiện tại các bảng đều rỗng. Bạn sẽ chạy lại script này sau mỗi lab AWS.

### Bước 10 — Script `find-leftovers.sh` (chỉ đọc) — dùng cho mọi lab sau `[WSL]`

Đây là **công cụ dọn dẹp chuẩn** của khóa học. Mọi lab AWS từ bài 03 trở đi kết thúc bằng: `~/devops-lab/06-aws/find-leftovers.sh`.

```bash
cd ~/devops-lab/06-aws
nano find-leftovers.sh
```

```bash
#!/usr/bin/env bash
# find-leftovers.sh — tìm tài nguyên AWS còn sót có thể đang tốn tiền.
# CHỈ ĐỌC: script chỉ gọi describe/list/get, không tạo, không sửa, không xóa gì.
#
# Cách dùng:
#   ./find-leftovers.sh                      # quét ap-southeast-1
#   ./find-leftovers.sh ap-southeast-1 us-east-1   # quét nhiều region
# Mã thoát: 0 = không thấy gì · 1 = có tài nguyên cần xem · 2 = thiếu điều kiện chạy · 3 = sạch nhưng có mục không kiểm tra được
set -euo pipefail

export AWS_PAGER=""
if [[ $# -gt 0 ]]; then
  regions=("$@")
else
  regions=("${AWS_REGION:-ap-southeast-1}")
fi

found=0
warn_file="$(mktemp)"
trap 'rm -f "$warn_file"' EXIT

# q <region> <lệnh aws...> — chạy lệnh, lỗi thì ghi cảnh báo và trả chuỗi rỗng
q() {
  local region="$1"; shift
  local out
  if ! out="$(aws "$@" --region "$region" --output text 2>&1)"; then
    printf '[%s] aws %s → %s\n' "$region" "$*" "${out%%$'\n'*}" >> "$warn_file"
    return 0
  fi
  [[ "$out" == "None" ]] && out=""
  printf '%s' "$out"
}

# report <tiêu đề> <kết quả> — chỉ in khi kết quả không rỗng
report() {
  local title="$1" output="$2"
  if [[ -n "${output//[[:space:]]/}" ]]; then
    printf '\n== %s ==\n%s\n' "$title" "$output"
    found=$((found + 1))
  fi
}

command -v aws > /dev/null || { echo "Chưa cài AWS CLI (xem bài 06)." >&2; exit 2; }
if ! identity="$(aws sts get-caller-identity --query Arn --output text 2>&1)"; then
  echo "Chưa đăng nhập hoặc credential hết hạn: chạy 'aws login'." >&2
  echo "$identity" >&2
  exit 2
fi
echo "Danh tính: $identity"
echo "Region quét: ${regions[*]}"

for r in "${regions[@]}"; do
  echo
  echo "################ Region $r ################"

  report "[$r] EC2 instance chưa terminate (stopped vẫn tốn tiền EBS)" "$(q "$r" ec2 describe-instances \
    --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]')"

  report "[$r] Elastic IP (mọi tag — kể cả không gắn tag)" "$(q "$r" ec2 describe-addresses \
    --query 'Addresses[].[PublicIp,AllocationId,InstanceId]')"

  report "[$r] EBS volume không gắn vào máy nào (status=available)" "$(q "$r" ec2 describe-volumes \
    --filters Name=status,Values=available \
    --query 'Volumes[].[VolumeId,Size,VolumeType,CreateTime]')"

  report "[$r] EBS snapshot của tài khoản" "$(q "$r" ec2 describe-snapshots --owner-ids self \
    --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime]')"

  # Lưu ý: describe-nat-gateways dùng --filter (số ít), khác các lệnh ec2 khác
  report "[$r] NAT Gateway chưa xóa (~0,045 USD/giờ + phí dữ liệu)" "$(q "$r" ec2 describe-nat-gateways \
    --filter Name=state,Values=pending,available \
    --query 'NatGateways[].[NatGatewayId,VpcId,State]')"

  report "[$r] VPC endpoint" "$(q "$r" ec2 describe-vpc-endpoints \
    --query 'VpcEndpoints[].[VpcEndpointId,VpcEndpointType,ServiceName,State]')"

  report "[$r] Network interface không gắn vào đâu" "$(q "$r" ec2 describe-network-interfaces \
    --filters Name=status,Values=available \
    --query 'NetworkInterfaces[].[NetworkInterfaceId,Description]')"

  report "[$r] VPC tự tạo (không phải default)" "$(q "$r" ec2 describe-vpcs \
    --filters Name=is-default,Values=false \
    --query 'Vpcs[].[VpcId,CidrBlock,Tags[?Key==`Name`]|[0].Value]')"

  report "[$r] Load balancer (ALB/NLB)" "$(q "$r" elbv2 describe-load-balancers \
    --query 'LoadBalancers[].[LoadBalancerName,Type,State.Code]')"

  report "[$r] Auto Scaling group" "$(q "$r" autoscaling describe-auto-scaling-groups \
    --query 'AutoScalingGroups[].[AutoScalingGroupName,DesiredCapacity]')"

  report "[$r] RDS instance" "$(q "$r" rds describe-db-instances \
    --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]')"

  report "[$r] RDS snapshot tạo tay" "$(q "$r" rds describe-db-snapshots --snapshot-type manual \
    --query 'DBSnapshots[].[DBSnapshotIdentifier,AllocatedStorage,SnapshotCreateTime]')"

  report "[$r] CloudWatch log group /taskhub*" "$(q "$r" logs describe-log-groups \
    --log-group-name-prefix /taskhub \
    --query 'logGroups[].[logGroupName,storedBytes,retentionInDays]')"

  report "[$r] Mọi tài nguyên còn tag Project=taskhub" "$(q "$r" resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=taskhub \
    --query 'ResourceTagMappingList[].ResourceARN')"
done

echo
echo "################ Dịch vụ toàn cục ################"
first="${regions[0]}"
report "S3 bucket (lưu trữ tính tiền theo dung lượng)" "$(q "$first" s3api list-buckets \
  --query 'Buckets[].[Name,CreationDate]')"
report "Route 53 hosted zone (tính phí theo tháng)" "$(q "$first" route53 list-hosted-zones \
  --query 'HostedZones[].[Name,Id]')"

echo
if [[ -s "$warn_file" ]]; then
  echo "⚠️  Không kiểm tra được các mục sau (thiếu quyền, dịch vụ chưa bật, hoặc lỗi mạng):"
  cat "$warn_file"
fi

if (( found > 0 )); then
  echo "→ Có $found nhóm tài nguyên cần xem lại. Xóa những gì không còn dùng, rồi chạy lại script."
  exit 1
elif [[ -s "$warn_file" ]]; then
  echo "→ Không thấy tài nguyên sót, nhưng có mục chưa kiểm tra được."
  exit 3
fi
echo "→ Không thấy tài nguyên sót ở các region đã quét. Billing vẫn là nguồn sự thật cuối cùng."
```

```bash
chmod +x find-leftovers.sh
bash -n find-leftovers.sh
./find-leftovers.sh ap-southeast-1 us-east-1; echo "exit code: $?"
```

Kỳ vọng ở tài khoản mới: không có nhóm nào hiện ra, mã thoát `0`. Nếu bạn đã tạo bucket hay tài nguyên nào khi khám phá, chúng sẽ hiện ra — đó chính là mục đích của script.

Đọc kỹ script và trả lời (ghi vào `week11/cli-lab.md`):

1. Vì sao lệnh `q` ghi cảnh báo vào **file** `$warn_file` mà không tăng một biến đếm? (Gợi ý: `$(...)` chạy ở đâu?)
2. `trap 'rm -f "$warn_file"' EXIT` làm gì? Chuyện gì xảy ra nếu bỏ dòng này và script bị Ctrl+C?
3. Vì sao script **không** dừng khi một dịch vụ trả `AccessDenied` dù có `set -e`?
4. Vì sao S3 và Route 53 chỉ quét **một lần** chứ không lặp theo region?
5. Script bỏ sót loại tài nguyên tốn tiền nào mà bạn biết? (Câu trả lời không có đáp án duy nhất — bạn sẽ bổ sung dần.)

Nếu thích, đẩy hai script vào thư mục `scripts/aws/` của repo nhật ký `devops-journey` (không phải repo `taskhub`).

### Bước 11 — CloudShell `[AWS Console]`

Mở CloudShell ở region Singapore:

```bash
aws --version
aws sts get-caller-identity --query Arn --output text
aws configure list
```

So sánh với WSL: danh tính giống, cột `TYPE` của credential khác. Thử tải `find-leftovers.sh` lên (menu **Actions → Upload file**) và chạy.

### Dọn dẹp

Lab không tạo tài nguyên AWS nào. Kiểm tra:

```bash
~/devops-lab/06-aws/find-leftovers.sh ap-southeast-1 us-east-1; echo "exit code: $?"
env | grep '^AWS_'          # chỉ nên còn AWS_PROFILE=taskhub
ls ~/.aws/credentials 2>/dev/null && echo "⚠️ Còn file credentials — kiểm tra lại Bước 1"
```

Xóa thư mục tải về nếu muốn: `rm -rf ~/downloads/awscli`.

---

## 10. Kết quả mong đợi

- [ ] `aws --version` ≥ 2.32.0, cài từ zip **đã kiểm chữ ký**; fingerprint khớp tài liệu.
- [ ] `~/.aws/config` có profile `taskhub` với `login_session` và `region = ap-southeast-1`; **không có** `~/.aws/credentials` chứa key.
- [ ] `AWS_PROFILE=taskhub` trong `~/.bashrc`; `aws sts get-caller-identity` trả `user/phuong-admin`.
- [ ] Giải thích được kết quả 4 định dạng output và 2 lệnh `describe-vpcs` khác region.
- [ ] `list-taskhub.sh` và `find-leftovers.sh` qua `bash -n`, chạy được, mã thoát `0` ở tài khoản sạch.
- [ ] Trả lời được 5 câu hỏi về `find-leftovers.sh` ở Bước 10.
- [ ] Ghi lại thông báo lỗi của 3 thí nghiệm ở Bước 8.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `aws: error: argument command: Invalid choice … login` | CLI v1 hoặc v2 cũ hơn 2.32.0 | `which -a aws`, gỡ bản apt, cài/cập nhật v2 (Bước 1–2) |
| `gpg: BAD signature` | File hỏng hoặc bị sửa | Xóa, tải lại cả `.zip` và `.sig` |
| `gpg: Can't check signature: No public key` | Chưa import khóa | Làm lại bước import, kiểm tra file `.asc` có đủ dòng BEGIN/END |
| `unzip: command not found` | Thiếu gói | `sudo apt install -y unzip` |
| Trình duyệt không mở khi `aws login` trong WSL | WSL không có trình duyệt mặc định | Chép URL thủ công, hoặc `--remote` |
| `ExpiredToken` / `AccessDeniedException` ngay sau `aws login` | Profile lẫn credential cũ (`~/.aws/credentials` hoặc biến môi trường) | `aws configure list` → cột `TYPE`; xóa key cũ, `unset AWS_ACCESS_KEY_ID…` |
| `You must specify a region` | Profile chưa có region, không có `AWS_REGION` | `aws configure set region ap-southeast-1 --profile taskhub` |
| Lệnh trả `[]` dù chắc chắn có tài nguyên | **Sai region** hoặc sai profile | `aws configure list`; thêm `--region`; chạy `find-leftovers.sh` nhiều region |
| Script đứng im ở giữa | Pager `less` đang chờ | `export AWS_PAGER=""` |
| `--query` báo `Bad value for --query` | Nháy kép bao ngoài làm Bash nuốt backtick, hoặc sai cú pháp JMESPath | Bọc biểu thức trong nháy đơn; thử từng phần nhỏ |
| `Unknown options: --filters` với `describe-nat-gateways` | Lệnh này dùng `--filter` (số ít) | Đọc `aws ec2 describe-nat-gateways help` |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Giải phẫu một thông báo lỗi CLI

```text
An error occurred (UnauthorizedOperation) when calling the DescribeInstances operation: You are not authorized to perform this operation. User: arn:aws:sts::111122223333:assumed-role/taskhub-readonly-demo/phuong-lab is not authorized to perform: ec2:DescribeInstances because no identity-based policy allows the ec2:DescribeInstances action
         └──────────┬──────────┘                   └───────┬───────┘
              Mã lỗi (để tra cứu)            Tên API (= action trong policy là ec2:DescribeInstances)
```

| Mã lỗi hay gặp | Nghĩa | Hướng xử lý |
|---|---|---|
| `AccessDenied` / `UnauthorizedOperation` | Thiếu quyền | Quy trình 5 bước ở [bài 02](02-iam.md) |
| `ExpiredToken` / `RequestExpired` | Credential tạm thời hết hạn, hoặc giờ máy lệch | `aws login` lại; kiểm tra giờ WSL `date -u` |
| `InvalidClientTokenId` | Access key không tồn tại/đã xóa (thường là biến môi trường cũ) | `env \| grep AWS_` |
| `Unable to locate credentials` | Không tìm thấy nguồn credential nào | `aws login --profile taskhub`; kiểm tra `AWS_PROFILE` |
| `DryRunOperation` | **Thành công** khi dùng `--dry-run` | Không cần làm gì |
| `InvalidParameterValue` / `ValidationError` | Sai tham số | Đọc phần sau dấu `:`; `aws <lệnh> help` |
| `Throttling` / `RequestLimitExceeded` | Gọi API quá nhanh (vòng lặp) | Thêm `sleep`, dùng `--page-size`, waiter |

### 12.2. WSL: giờ hệ thống lệch

Chữ ký request có thời gian. Nếu đồng hồ WSL lệch nhiều (hay xảy ra sau khi máy ngủ), AWS từ chối với lỗi kiểu `Signature expired` hoặc `RequestExpired`. Kiểm tra:

```bash
date -u
```

So với giờ thật (UTC). Nếu lệch, khởi động lại WSL từ `[PowerShell]`: `wsl --shutdown`, rồi mở lại terminal.

### 12.3. `--debug` khi mọi cách khác đều thất bại

```bash
aws sts get-caller-identity --debug 2>debug.log
grep -iE 'credentials via|Found credentials|region' debug.log | head
rm debug.log
```

Ghi lỗi gặp phải vào `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Vì sao khóa học cài CLI từ zip + kiểm chữ ký thay vì `curl … | bash` hay gói apt?
2. Dòng `WARNING: This key is not certified with a trusted signature!` có nghĩa là file bị giả mạo không? Điều gì mới thực sự chứng minh file hợp lệ?
3. `aws login` lưu gì trong `~/.aws/config`, gì trong `~/.aws/login/cache/`? File nào chứa bí mật?
4. So sánh `aws login` và `aws configure` + access key về: loại credential, rủi ro khi lộ, MFA.
5. Bạn đặt `region = ap-southeast-1` trong profile, nhưng `AWS_REGION=us-east-1` và gõ `--region eu-west-1`. Lệnh gửi tới region nào? Vì sao?
6. `--filters` và `--query` khác nhau ở đâu? Cho ví dụ dùng cả hai trong một lệnh.
7. Viết biểu thức `--query` lấy giá trị tag `Name` của mọi instance.
8. `--max-items` và `--page-size` khác nhau thế nào? Cái nào làm thay đổi đầu ra?
9. `--dry-run` trả về gì khi có quyền? Vì sao exit code khác 0?
10. Waiter `instance-running` chờ tối đa bao lâu trước khi bỏ cuộc? Mã thoát khi thất bại?
11. Vì sao script gọi AWS CLI nên có `export AWS_PAGER=""`?
12. `aws configure list` hiện cột `TYPE` = `env`. Điều đó nghĩa là gì và vì sao có thể gây lỗi khó hiểu?
13. `resourcegroupstaggingapi get-resources` không tìm được loại tài nguyên nào? `find-leftovers.sh` bù lại thế nào?
14. Vì sao không bao giờ chép cứng AMI ID vào script? Cách đúng để lấy AMI Ubuntu là gì?
15. CloudShell có tính phí không? Dữ liệu trong `$HOME` của CloudShell tồn tại bao lâu?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/06-solutions.md](solutions/06-solutions.md) — chỉ mở sau khi tự làm.

**Bài 1 — Truy vấn.** Viết lệnh (mỗi câu một lệnh) trả về:
(a) Danh sách region có tên bắt đầu bằng `ap-`, mỗi dòng một region, đã sắp xếp.
(b) Bảng các subnet của **VPC mặc định**: Subnet ID, CIDR, AZ, số IP còn trống, sắp xếp theo AZ.
(c) Số lượng instance type Free Tier.
(d) Tên và ngày tạo của **3 AMI Ubuntu 24.04 amd64 mới nhất** của Canonical ở ap-southeast-1.

**Bài 2 — Hàm Bash `whoami-aws`.** Thêm vào `~/.bashrc` một hàm in một dòng: `ARN | account | region | nguồn credential` (nguồn lấy từ cột TYPE của `aws configure list`). Hàm phải chạy được khi chưa đăng nhập (in thông báo rõ ràng, không thoát shell).

**Bài 3 — Mở rộng `find-leftovers.sh`.** Thêm 2 loại tài nguyên mà script chưa quét và có thể tốn tiền (tự tìm hiểu trong trang pricing). Gợi ý cân nhắc: Elastic IP đã cấp nhưng chưa gắn, ECR repository, Secrets Manager secret, KMS key do khách hàng quản lý, SNS topic (cái nào thực sự tốn tiền?). Với mỗi loại, ghi: lệnh, lý do, nguồn giá đã kiểm tra.

**Bài 4 — Chạy tự động mỗi ngày.** Viết một systemd timer **người dùng** (hoặc cron) trên WSL chạy `find-leftovers.sh ap-southeast-1 us-east-1` lúc 22:00 và ghi kết quả vào `~/devops-lab/06-aws/leftovers-$(date +%F).log` (xem [Linux bài 08](../01-LINUX/08-cron-scheduling.md)). Điều gì xảy ra khi phiên `aws login` đã hết hạn lúc 22:00? Script xử lý thế nào? Đề xuất cách bạn sẽ được nhắc.

**Bài 5 — Profile role.** Làm Bài 4 của [bài 02](02-iam.md) (profile `taskhub-ro` với `role_arn` + `mfa_serial`). Sau đó chạy `find-leftovers.sh` bằng `AWS_PROFILE=taskhub-ro`. Những dòng cảnh báo nào xuất hiện và vì sao? Dọn role sau khi xong.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đạt bài này khi, **không nhìn tài liệu**:

- [ ] Giải thích được cho người khác vì sao laptop của bạn **không có access key** mà vẫn dùng CLI được.
- [ ] Vẽ được sơ đồ ở mục 6 (CLI chọn region/profile/credential theo thứ tự nào).
- [ ] Viết được `--query` có lọc điều kiện, lấy tag `Name`, đổi nhãn cột.
- [ ] Đọc một thông báo lỗi CLI và nói được ngay: mã lỗi, API, nguyên nhân khả dĩ, lệnh kiểm tra tiếp theo.
- [ ] Giải thích được từng khối trong `find-leftovers.sh` và chạy nó như bước cuối của mọi buổi học AWS.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS CLI — Installing or updating](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Cài zip, kiểm chữ ký PGP, fingerprint, lệnh cập nhật | 2026-10-31 |
| [AWS CLI — Login using console credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html) | `aws login`, `--remote`, cache, 15 phút / 12 giờ, `SignInLocalDevelopmentAccess` | 2026-10-31 |
| [AWS CLI — Troubleshoot aws login](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in-troubleshoot.html) | Firewall, lẫn credential cũ, `aws configure list` cột TYPE | 2026-10-31 |
| [AWS Sign-In — AWS managed policies](https://docs.aws.amazon.com/signin/latest/userguide/security-iam-awsmanpol.html) | `SignInLocalDevelopmentAccess` | 2026-10-31 |
| [AWS CLI — Environment variables](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html) | Thứ tự ưu tiên, `AWS_REGION` thắng `AWS_DEFAULT_REGION`, `AWS_PAGER` | 2026-10-31 |
| [AWS CLI — Filtering output](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html) | `--filters` vs `--query`, JMESPath, hành vi với `--output text` | 2026-10-31 |
| [AWS CLI — Pagination](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-pagination.html) | `--page-size`, `--max-items`, `--starting-token`, pager | 2026-10-31 |
| [AWS CLI — Using an IAM role](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html) | Profile `role_arn`, `source_profile`, `mfa_serial`, cache | 2026-10-31 |
| [AWS CLI — ec2 wait instance-running](https://docs.aws.amazon.com/cli/latest/reference/ec2/wait/instance-running.html) | 15 giây, 40 lần, mã 255 | 2026-10-31 |
| [EC2 — Track Free Tier usage](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html) | Lệnh lọc `free-tier-eligible`, danh sách instance type | 2026-10-31 |
| [Ubuntu on AWS — Find Ubuntu images](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/) | Đường dẫn tham số SSM của AMI Ubuntu | 2026-10-31 |
| [AWS CloudShell — Service quotas](https://docs.aws.amazon.com/cloudshell/latest/userguide/limits.html) | 1 GB/region, 120 ngày, 20–30 phút, 12 giờ | 2026-10-31 |
| [AWS CloudShell — Pricing](https://aws.amazon.com/cloudshell/pricing/) | Không tính thêm phí | 2026-10-31 |
| [JMESPath — Tutorial](https://jmespath.org/tutorial.html) | Cú pháp truy vấn | 2026-10-31 |
