# Milestone v3 — CD tự động lên EC2 qua OIDC + SSM, CloudWatch cơ bản (tuần 13–14)

> Mức độ: 🟥 Bắt buộc (Route 53 là 🟦 tùy chọn) · Kiến thức cần có trước: milestone [v2 — EC2](v2-aws-ec2.md) (release `v0.4.0` đang chạy trên EC2), [Module 06](../../06-AWS/README.md) bài 09–11, [CI/CD bài 04 — environments](../../05-CICD/04-secrets-environments.md) (environment `production` có người duyệt)
> Môi trường: `[WSL]`, `[AWS Console]`, `[GitHub]` (Settings, Actions), `[Runner]` (đọc log), `[EC2]`
> Đây là **việc cần nộp + tiêu chí chấp nhận**. Kiến thức nền: [bài 09 — Route 53](../../06-AWS/09-route53.md), [bài 10 — CloudWatch](../../06-AWS/10-cloudwatch.md), [bài 11 — Ghép các dịch vụ thành hệ thống](../../06-AWS/11-putting-it-together.md). Tuần 14 còn có lab ngắn RDS + ALB + ASG trong module — không thuộc dự án chính.

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc v3](#2-kiến-trúc-v3)
- [3. Chi phí](#3-chi-phí)
- [4. File phải có trong repo](#4-file-phải-có-trong-repo)
- [5. Cấu hình trên AWS và GitHub](#5-cấu-hình-trên-aws-và-github)
- [6. Yêu cầu chất lượng](#6-yêu-cầu-chất-lượng)
- [7. Thử nghiệm bắt buộc](#7-thử-nghiệm-bắt-buộc)
- [8. Xử lý sự cố thường gặp](#8-xử-lý-sự-cố-thường-gặp)
- [9. Câu hỏi tự kiểm](#9-câu-hỏi-tự-kiểm)
- [10. Definition of Done và release v0.5.0](#10-definition-of-done-và-release-v050)
- [11. Dọn dẹp](#11-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

Từ v3, **không ai vào máy chủ để triển khai nữa**. Con đường duy nhất:

```text
PR → CI xanh → merge main → CI push :<sha7> → Deploy chờ bạn duyệt → SSM chạy deploy.sh → smoke test từ Internet
```

Cụ thể:

1. Mỗi lần CI xanh trên `main`, workflow **`Deploy`** tự khởi chạy, dừng chờ **người duyệt** (environment `production`), rồi triển khai đúng image `:<sha7>` vừa build lên EC2.
2. GitHub **không giữ access key AWS nào**: quyền AWS đến từ **OIDC** — token ngắn hạn, chỉ cấp cho job chạy trong environment `production` của đúng repo.
3. Deploy đi qua **SSM Run Command** — không SSH, không port 22. Role deploy chỉ được chạy `AWS-RunShellScript` trên instance có tag `Project=taskhub`.
4. **Rollback < 5 phút**: Actions → Deploy → *Run workflow* → nhập tag cũ → duyệt. Đã diễn tập và có số đo.
5. **Quan sát được** hệ thống: log container `taskhub` lên **CloudWatch Logs** (giữ 7 ngày); **alarm** khi EC2 hỏng status check hoặc CPU cao, gửi **email** qua SNS.
6. 🟦 Nếu có domain: bản ghi Route 53 trỏ về EC2.

Vì sao quan trọng: đây là phần "CD" trong mọi JD DevOps, và là câu chuyện phỏng vấn mạnh nhất của dự án: *"Merge xong, 5 phút sau code chạy trên AWS, không ai cầm access key, không mở SSH, rollback bằng một nút bấm."*

---

## 2. Kiến trúc v3

```text
[GitHub] merge PR ──► CI (build-test → image) ── push ghcr.io/<user>/taskhub:<sha7>
                         │ workflow_run: completed + success + event=push + đúng repo
                         ▼
          ┌──────────── Deploy (.github/workflows/deploy.yml) ────────────────────────┐
          │ job deploy · environment production → ⏸ chờ Approve                       │
          │  1. tag = sha7 (hoặc input image_tag khi chạy tay) → kiểm tra định dạng   │
          │  2. OIDC: JWT (sub = repo:<user>/taskhub:environment:production)          │
          │       └─► STS AssumeRoleWithWebIdentity ─► role taskhub-github-deploy     │
          │  3. ec2 describe-instances (tag Name=taskhub-app, Project=taskhub)        │
          │  4. ssm send-command AWS-RunShellScript ─────────────┐                    │
          │  5. hỏi trạng thái, in stdout/stderr của deploy.sh   │                    │
          │  6. curl $APP_URL/actuator/health  (từ Internet)     │                    │
          └──────────────────────────────────────────────────────│────────────────────┘
                                                                 ▼
 [AWS ap-southeast-1]   EC2 taskhub-app ── SSM Agent nhận lệnh (kết nối RA ngoài 443)
                          └─ /opt/taskhub/scripts/deploy.sh <tag>
                               ├─ Parameter Store → POSTGRES_PASSWORD
                               ├─ compose -f compose.yaml -f compose.aws.yaml pull + up --wait
                               └─ lỗi → quay về tag trước
                          container taskhub ──log driver awslogs──► CloudWatch Logs /taskhub/dev/app (7 ngày)
                          metric EC2 (StatusCheckFailed, CPUUtilization) ──► Alarm ──► SNS taskhub-alerts ──► email
```

| Workflow | Kích hoạt | Job | Quyền | Kết quả |
|---|---|---|---|---|
| `CI` | PR / push `main` | `build-test` → `image` | như v1 | Image `:<sha7>` |
| `Release` | push tag `v*.*.*` | `promote` | như v1 | `:vX.Y.Z` + GitHub Release |
| `Deploy` | `workflow_run` (CI xong trên `main`) hoặc `workflow_dispatch` (`image_tag`) | `deploy` | `contents: read`, `id-token: write`; environment `production` | Image đó chạy trên EC2 |

**Vì sao `workflow_run` cần thêm điều kiện `event == 'push'` và `head_repository.full_name == github.repository`?** Bộ lọc `branches: [main]` của `workflow_run` so **tên nhánh** của lần chạy CI. Một PR từ fork có nhánh tên `main` cũng làm CI chạy với tên nhánh đó. Hai điều kiện thêm bảo đảm chỉ CI do **push vào main của chính repo** mới dẫn tới deploy. (Dù sao người lạ cũng không qua được bước duyệt của environment — nhưng phòng thủ nhiều lớp.)

**Vì sao vẫn cần người duyệt?** Đây là *Continuous Delivery* (sẵn sàng triển khai, người quyết định), không phải *Continuous Deployment* ([CI/CD bài 01](../../05-CICD/01-cicd-concepts.md)). Với một dự án không có test end-to-end và không có môi trường staging, một cú bấm Approve là hàng rào hợp lý. Ghi lựa chọn này vào ADR.

---

## 3. Chi phí

Hạ tầng của v2 giữ nguyên (EC2, EBS, IPv4 — xem [v2 §3](v2-aws-ec2.md#3-chi-phí-và-nguyên-tắc-tiết-kiệm)). v3 thêm:

| Khoản | Đơn giá | Ghi chú |
|---|---|---|
| IAM OIDC provider, IAM role | 0 | |
| SSM Run Command | 0 với EC2 | |
| CloudWatch Logs | Tính theo GB ghi vào và GB lưu trữ — tra [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) | Log của 1 app nhỏ, giữ 7 ngày → rất nhỏ. **Bắt buộc** đặt retention, nếu không log giữ **mãi mãi** và tiền tăng dần |
| CloudWatch Alarms (2 alarm) | Tra trang pricing (có hạn mức miễn phí cho số alarm nhỏ — kiểm tra con số hiện tại) | Metric EC2 cơ bản (5 phút) và status check không tốn thêm |
| SNS email | Tra [SNS pricing](https://aws.amazon.com/sns/pricing/) | Vài email/tháng |
| GitHub Actions | 0 (repo public, runner chuẩn) | |
| 🟦 Route 53 hosted zone | **0,50 USD/zone/tháng** + 0,40 USD/triệu truy vấn ([Route 53 pricing](https://aws.amazon.com/route53/pricing/)) | Zone xóa trong 12 giờ đầu không bị tính. Domain tính riêng (mua ở đâu cũng được). **Credit Free plan có áp dụng cho Route 53 không — tự kiểm tra trong Billing** |

Tiếp tục ghi `docs/cost.md` mỗi buổi. Ghi riêng dòng CloudWatch sau một tuần chạy để thấy con số thật.

---

## 4. File phải có trong repo

```text
taskhub/
├── .github/workflows/
│   ├── ci.yml                   # (v1) không đổi
│   ├── release.yml              # (v1) không đổi
│   └── deploy.yml               # MỚI — workflow Deploy, job deploy
├── compose.aws.yaml             # MỚI — chỉ EC2: logging driver awslogs cho taskhub
├── scripts/deploy.sh            # (v2) không đổi — đã tự gộp compose.aws.yaml nếu có
├── infra/aws-manual/
│   ├── github-deploy-trust.json     # MỚI
│   ├── github-deploy-policy.json    # MỚI
│   ├── ec2-app-policy.json          # CẬP NHẬT — thêm quyền ghi log /taskhub/dev/*
│   └── commands.md                  # CẬP NHẬT — lệnh tạo OIDC provider, role, log group, SNS, alarm
├── docs/
│   ├── architecture.md          # CẬP NHẬT — sơ đồ v3
│   ├── runbooks/rollback.md     # MỚI — rollback bằng workflow_dispatch, có số phút đã đo
│   ├── runbooks/deploy-manual.md    # (v2) giữ làm phương án dự phòng khi GitHub/OIDC hỏng
│   ├── adr/0007-cd-oidc-ssm-run-command.md   # MỚI (0006 là "PostgreSQL trong container" ở bài AWS 11)
│   └── experiments/v3-tests.md  # MỚI — kết quả T1–T10
└── README.md                    # CẬP NHẬT — badge Deploy, mục CI/CD thêm luồng triển khai, link tới runbook rollback
```

**Bản tham khảo:** [06-AWS/labs/reference-v3/](../../06-AWS/labs/reference-v3/README.md) — `deploy.yml`, `compose.aws.yaml`, các file IAM, kèm bảng "quyết định và lý do". ⚠️ Chỉ mở sau khi bạn đã tự viết và workflow đã chạy (xanh hoặc đỏ).

### 4.1. `deploy.yml` — những gì phải có

| Phần | Yêu cầu |
|---|---|
| Trigger | `workflow_run` (`workflows: [CI]`, `types: [completed]`, `branches: [main]`) **và** `workflow_dispatch` với input bắt buộc `image_tag` |
| Điều kiện job | dispatch, **hoặc** CI `conclusion == 'success'` + `event == 'push'` + `head_repository.full_name == github.repository` |
| `permissions` | Cấp workflow `contents: read`; job `deploy` thêm `id-token: write` — **không** quyền nào khác |
| `environment` | `name: production`, `url: ${{ vars.APP_URL }}` |
| `concurrency` | Một nhóm cố định (vd `deploy-production`), `cancel-in-progress: false` — không bao giờ hủy một lần deploy đang dở |
| Kiểm tra tag | Chỉ nhận `^[0-9a-f]{7}$` hoặc `^v[0-9]+\.[0-9]+\.[0-9]+(-...)?$`; input đi vào script **qua `env:`** ([CI/CD bài 04](../../05-CICD/04-secrets-environments.md)) |
| AWS | `aws-actions/configure-aws-credentials` ghim SHA (v6.3.0), `role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}`, region `ap-southeast-1` |
| Deploy | Tìm **đúng 1** instance đang chạy theo tag; `ssm send-command` document `AWS-RunShellScript`; hỏi trạng thái tới khi xong (tự viết vòng lặp — waiter mặc định của CLI quá ngắn); **in stdout/stderr** của `deploy.sh` vào log; trạng thái khác `Success` → job đỏ |
| Smoke test | `curl -fsS --retry ...` tới `$APP_URL/actuator/health` từ runner, kiểm tra `"status":"UP"` |
| Chung | `runs-on: ubuntu-24.04`, `timeout-minutes`, mọi action ghim SHA (như Q2 của v1) |

Đừng quên: workflow có trigger `workflow_run` chỉ chạy khi **file đó đã nằm trên nhánh mặc định** — merge `deploy.yml` vào `main` trước, rồi mới thấy nó tự chạy.

### 4.2. ADR — CD qua OIDC + SSM

Các lựa chọn để so sánh: (1) SSH từ runner với private key trong GitHub Secrets; (2) access key IAM trong Secrets + SSM; (3) **OIDC + SSM Run Command**; (4) CodeDeploy. Hệ quả phải nêu: phụ thuộc SSM Agent và đường ra Internet của EC2; `APP_URL` là IP đổi khi stop/start; deploy chỉ đổi **image tag** — thay đổi `compose.yaml` vẫn phải cập nhật tay trên máy (v4 Ansible giải quyết); cần người duyệt mỗi lần.

---

## 5. Cấu hình trên AWS và GitHub

### 5.1. AWS (⚠️ tự chạy, không tính phí trừ CloudWatch/SNS rất nhỏ)

| Việc | Cách làm | Kiểm tra |
|---|---|---|
| **OIDC provider** cho GitHub | `[AWS Console]` IAM → Identity providers → Add provider → OpenID Connect · Provider URL `https://token.actions.githubusercontent.com` · Audience `sts.amazonaws.com` (theo [tài liệu GitHub](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)) | `aws iam list-open-id-connect-providers` |
| **Role** `taskhub-github-deploy` | Trust policy: `Federated` = ARN của provider; `token.actions.githubusercontent.com:aud` = `sts.amazonaws.com`; `...:sub` = `repo:<user>/taskhub:environment:production` (StringEquals, **không** dùng `*`). Inline policy: chỉ `ssm:SendCommand` trên document `AWS-RunShellScript` + instance có `ssm:resourceTag/Project` = `taskhub`; `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`, `ec2:DescribeInstances` | `aws iam get-role --role-name taskhub-github-deploy --query Role.AssumeRolePolicyDocument` |
| **Quyền ghi log cho EC2** | Thêm vào inline `taskhub-ec2-app`: `logs:CreateLogStream`, `logs:PutLogEvents` trên `arn:aws:logs:ap-southeast-1:<account>:log-group:/taskhub/dev/*:*` (quyền S3 backup vẫn ở inline policy riêng `taskhub-ec2-s3-backup` từ [bài 05](../../06-AWS/05-s3.md), không gộp vào đây) | `aws iam get-role-policy --role-name taskhub-ec2-role --policy-name taskhub-ec2-app` |
| **Log group** | `aws logs create-log-group --log-group-name /taskhub/dev/app` + `aws logs put-retention-policy --log-group-name /taskhub/dev/app --retention-in-days 7` (driver `awslogs` **không** tự tạo group — mặc định `awslogs-create-group=false`) | `aws logs describe-log-groups --log-group-name-prefix /taskhub` → `retentionInDays: 7` |
| **SNS** | Topic `taskhub-alerts` + subscription email → **bấm link xác nhận trong email** (chưa xác nhận = không nhận được gì) | `aws sns list-subscriptions-by-topic ...` → không còn `PendingConfirmation` |
| **Alarm 1** | `StatusCheckFailed` của `taskhub-app` ≥ 1 trong 2 chu kỳ liên tiếp → SNS | `aws cloudwatch describe-alarms --alarm-name-prefix taskhub` |
| **Alarm 2** | `CPUUtilization` > 80% trong 3 chu kỳ 5 phút → SNS (`t3` là loại burstable — CPU cao kéo dài sẽ tiêu hết CPU credit, [bài 04](../../06-AWS/04-ec2.md)) | như trên |
| Tag `Project=taskhub` trên EC2 | Đã có từ v2 — **bắt buộc** cho điều kiện của role deploy | `describe-instances --query '...Tags'` |

Thứ tự gợi ý và lệnh CLI chi tiết: xem [bài 10 — CloudWatch](../../06-AWS/10-cloudwatch.md) và [bài 02 — IAM](../../06-AWS/02-iam.md); ghi lại những gì bạn thực sự chạy vào `infra/aws-manual/commands.md`.

Trên EC2: kéo phiên bản repo có `compose.aws.yaml` về `/opt/taskhub` (`sudo git -C /opt/taskhub fetch --tags && sudo git -C /opt/taskhub checkout <tag-mới>`), rồi chạy `deploy.sh` một lần bằng tay để container được tạo lại với log driver mới. Đây chính là giới hạn "thay đổi compose phải làm tay" ghi trong ADR.

### 5.2. GitHub

| Ở đâu | Cài đặt | Giá trị |
|---|---|---|
| Settings → Environments → `production` | Required reviewers | Bạn (đã có từ CI/CD bài 04) |
| cùng chỗ | Deployment branches and tags | Chỉ `main` (chạy tay Deploy từ nhánh khác sẽ bị từ chối) |
| cùng chỗ → Environment variables | `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::<account>:role/taskhub-github-deploy` |
| cùng chỗ → Environment variables | `APP_URL` | `http://<IP-public-hiện-tại>` (không có `/` ở cuối). **Cập nhật mỗi lần stop/start** EC2, hoặc dùng domain (🟦) |
| Settings → Secrets and variables → Actions | Secrets | **Không có** secret AWS nào. Role ARN không phải bí mật — để ở *variables* |

---

## 6. Yêu cầu chất lượng

| # | Yêu cầu | Vì sao | Học ở |
|---|---|---|---|
| Q1 | **Không có access key AWS** trong GitHub (Secrets, Variables, code, log) và không có IAM user nào dành cho CI | Key dài hạn bị lộ = kẻ tấn công dùng được tới khi bạn phát hiện | [CI/CD bài 04](../../05-CICD/04-secrets-environments.md), [bài 02](../../06-AWS/02-iam.md) |
| Q2 | Trust policy dùng `StringEquals` với `sub` chính xác `repo:<user>/taskhub:environment:production` và `aud` = `sts.amazonaws.com` | `sub` có `*` (vd `repo:<user>/*`) cho **mọi** repo/nhánh/PR của bạn đổi token lấy quyền deploy | [GitHub OIDC in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) |
| Q3 | Policy của role deploy: đúng 4 nhóm quyền ở mục 5.1; `SendCommand` bị giới hạn theo document **và** `ssm:resourceTag/Project` | Role bị lạm dụng cũng không chạy được lệnh trên máy khác hay document khác | [Run Command — tag-based access](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-setting-up.html) |
| Q4 | `deploy.yml` đạt mọi dòng ở mục 4.1 (quyền tối thiểu, ghim SHA, timeout, concurrency không hủy, kiểm tra tag, điều kiện `workflow_run`) | Xem lý do từng dòng ở [reference-v3](../../06-AWS/labs/reference-v3/README.md) | Bài 04 Module 05 |
| Q5 | Mỗi lần deploy cần **Approve** trong environment `production`; chạy tay từ nhánh ≠ `main` bị chặn | Continuous Delivery có kiểm soát; dấu vết ai duyệt, lúc nào | CI/CD bài 04 |
| Q6 | Log của bước SSM trong Actions **in ra output của `deploy.sh`** — đọc được lỗi mà không cần vào máy | Người trực sự cố cần thấy nguyên nhân ngay trong lần chạy | [bài 10](../../06-AWS/10-cloudwatch.md) |
| Q7 | Smoke test chạy **từ runner** (ngoài AWS) qua `APP_URL` | Chứng minh cả đường mạng (SG, IGW, nginx) chứ không chỉ "container healthy" | [CI/CD bài 05](../../05-CICD/05-deployment-strategies-rollback.md) |
| Q8 | Log group `/taskhub/dev/app` có retention **7 ngày**; tìm được log của một request cụ thể bằng Logs Insights | Không có retention = log giữ mãi, tiền tăng dần | Bài 10 |
| Q9 | 2 alarm đã **thử bắn** (T8) và email đã tới | Alarm chưa từng bắn thử = không biết nó có chạy không | Bài 10 |
| Q10 | Runbook rollback có **số phút đo thật** < 5 phút (từ lúc quyết định tới khi `/actuator/health` của bản cũ trả `UP`) | Mục tiêu trong [tiêu chí CV](../README.md#8-tiêu-chí-đủ-tốt-để-đưa-vào-cv) | Bài 05 Module 05 |

**Kiểm tra nhanh** `[WSL]` trong repo:

```bash
grep -nE 'uses: ' .github/workflows/*.yml | grep -vE '@[0-9a-f]{40} # v'     # KHÔNG in gì
grep -nE 'AWS_ACCESS_KEY|aws-access-key-id|aws-secret-access-key' -r .github  # KHÔNG in gì
grep -n 'id-token: write' .github/workflows/*.yml                           # chỉ trong deploy.yml, cấp job
```

---

## 7. Thử nghiệm bắt buộc

Ghi **thao tác → quan sát (link tới lần chạy) → giải thích** vào `docs/experiments/v3-tests.md`.

| # | Thử nghiệm | Cách làm | Kết quả mong đợi — bạn phải giải thích được |
|---|---|---|---|
| T1 | **Luồng chuẩn + đo lead time** | Merge một PR nhỏ (vd đổi một dòng log khởi động) → theo dõi CI → Deploy (chờ duyệt) → Approve | Deploy xanh; `deploy.sh` output hiện trong log; app trả lời phiên bản mới. Ghi **lead time** (từ lúc merge tới khi production chạy commit đó) — một chỉ số DORA ([CI/CD bài 01](../../05-CICD/01-cicd-concepts.md)). Thời gian chờ duyệt chiếm bao nhiêu? |
| T2 | **Trust policy sai `sub`** | Tạm sửa trust policy thành `...:environment:prod` → chạy Deploy | Bước configure-aws-credentials đỏ, lỗi kiểu *Not authorized to perform sts:AssumeRoleWithWebIdentity* (minh họa). Sửa lại. Vì sao lỗi xảy ra ở **AWS** chứ không ở GitHub? Token chứa claim gì (tra tài liệu GitHub về OIDC token claims)? |
| T3 | **Role deploy bị giới hạn theo tag** | Tạm đổi giá trị điều kiện trong policy thành `taskhub-x` → chạy Deploy → khôi phục | `ssm send-command` bị `AccessDeniedException` (minh họa). Giải thích: tại sao tag trên EC2 là một phần của **ranh giới bảo mật**, và ai có quyền sửa tag đó? |
| T4 | **Tag không tồn tại → tự rollback** | Run workflow tay với `image_tag` = `v9.9.9` → Approve | Job đỏ ở bước SSM (deploy.sh exit 1); log ghi pull lỗi + "Rollback về ..."; trong suốt quá trình app **vẫn trả lời** (chạy vòng `curl` từ laptop để chứng minh) |
| T5 | **Diễn tập rollback < 5 phút** | Production đang chạy `:<sha7>` mới nhất. Bấm giờ: Run workflow với tag bản trước (vd `v0.4.0`) → Approve → đợi smoke test xanh. Rồi triển khai lại bản mới | Số phút thực tế (mục tiêu < 5). Bước nào tốn thời gian nhất? Ghi vào `docs/runbooks/rollback.md`. Khi nào cách này **không** cứu được (migration không tương thích ngược, lỗi cấu hình — [CI/CD bài 05](../../05-CICD/05-deployment-strategies-rollback.md))? |
| T6 | **Hai lần deploy chồng nhau** | Run workflow tay hai lần liên tiếp (hai tag khác nhau) | Lần thứ hai ở trạng thái *Pending/Waiting* cho tới khi lần đầu xong (`concurrency`, không hủy). Vì sao không được để hai `deploy.sh` chạy song song trên cùng máy? |
| T7 | **Log trên CloudWatch** | Gọi vài request (có một request lỗi 404) → `[AWS Console]` CloudWatch → Logs Insights, chọn `/taskhub/dev/app`: `fields @timestamp, @message \| sort @timestamp desc \| limit 20` | Thấy log khởi động Spring Boot và request của bạn. `sudo docker compose -f compose.yaml -f compose.aws.yaml logs taskhub` trên máy **có còn chạy không** khi dùng driver `awslogs`? Ghi lại kết quả thật và tìm trong tài liệu Docker vì sao (từ khóa: *dual logging*) |
| T8 | **Alarm bắn thử** | `aws cloudwatch set-alarm-state --alarm-name <tên> --state-value ALARM --state-reason "test v3"` cho từng alarm | Email tới trong vài phút; alarm tự quay về `OK` ở chu kỳ đánh giá sau. Vì sao nên thử bằng `set-alarm-state` thay vì làm EC2 hỏng thật? |
| T9 | **Stop/start và `APP_URL`** | Stop + start EC2 → chạy Deploy mà **chưa** cập nhật `APP_URL` | SSM vẫn deploy được (đi theo instance ID, không theo IP) nhưng **smoke test đỏ** (IP cũ). Cập nhật biến → chạy lại xanh. Hai cách loại bỏ bước tay này và chi phí của chúng |
| T10 | **Mất đường ra Internet của EC2** (tùy chọn, ⚠️ nhớ khôi phục) | Tạm gỡ route `0.0.0.0/0` của `taskhub-public-rt` → chạy Deploy → **thêm lại route ngay** | Bước SSM không bao giờ thành công (Agent không nhận được lệnh — trạng thái kiểu *Pending/Undeliverable/TimedOut*, ghi lại chữ thật). Bài học: CD qua SSM phụ thuộc mạng của máy đích; phương án dự phòng là runbook tay của v2 |

---

## 8. Xử lý sự cố thường gặp

Đọc log theo thứ tự các bước của job: lỗi ở **bước nào** đã khoanh vùng được nguyên nhân. Thông báo dưới đây là minh họa — tìm **ý chính** in đậm.

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra | Cách sửa |
|---|---|---|---|
| Deploy **không tự chạy** sau CI xanh | `deploy.yml` chưa nằm trên `main`; tên trong `workflows: [CI]` không khớp `name:` của ci.yml; CI chạy do PR chứ không phải push | Tab Actions: có lần chạy Deploy bị *skipped* không? Điều kiện `if:` nào sai? | Merge deploy.yml trước; sửa tên cho khớp |
| configure-aws-credentials: **Could not load credentials / unable to get ID token** | Thiếu `id-token: write` ở job | Khối `permissions:` của job | Thêm `id-token: write` (chỉ ở job deploy) |
| **Not authorized to perform sts:AssumeRoleWithWebIdentity** | `sub` trong trust policy không khớp (sai user, sai tên repo, sai tên environment, hoặc job không khai báo `environment`); sai ARN provider; `aud` sai | So từng ký tự `sub`; job có `environment: production`? | Sửa trust policy (T2) |
| send-command: **AccessDeniedException** | Policy của role thiếu quyền; instance thiếu tag `Project=taskhub`; document không phải `AWS-RunShellScript` | `aws iam get-role-policy ...`; tag của instance | Sửa policy/tag (T3) |
| send-command: **InvalidInstanceId** | SSM Agent không online (máy vừa start, mất đường ra Internet, instance profile bị gỡ) | `aws ssm describe-instance-information` | Chờ Agent online; kiểm tra route/role (v2 §8) |
| Trạng thái SSM **Failed** | `deploy.sh` exit khác 0 — đọc **stderr** in trong log: pull lỗi, healthcheck, Parameter Store | Phần stderr trong log bước SSM | Sửa theo lỗi; app vẫn chạy bản cũ nhờ rollback |
| Trạng thái SSM **Failed**, stderr: `Permission denied` (exit 126) | `scripts/deploy.sh` mất bit thực thi trong bản đã checkout trên EC2 | `git ls-files -s scripts/deploy.sh` → phải `100755` | `git update-index --chmod=+x`, release mới, cập nhật máy |
| Container `taskhub` không chạy: **failed to initialize logging driver** ... log group does not exist | Chưa tạo log group (`awslogs-create-group` mặc định `false`) | `aws logs describe-log-groups --log-group-name-prefix /taskhub` | Tạo log group + retention |
| **failed to initialize logging driver** ... AccessDenied | Instance role thiếu `logs:CreateLogStream`/`PutLogEvents` hoặc ARN sai | Policy `taskhub-ec2-app` | Sửa ARN `log-group:/taskhub/dev/*:*` |
| Smoke test đỏ, nhưng log SSM báo `>> OK` | `APP_URL` cũ (IP đổi), hoặc SG/route chặn từ ngoài | `curl` từ laptop; IP hiện tại | Cập nhật `APP_URL` (T9) |
| Email alarm không tới | Subscription chưa xác nhận; email vào thư rác | `list-subscriptions-by-topic` | Xác nhận lại |

Ghi mọi lỗi vào `troubleshooting-journal.md` theo [mẫu](../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 9. Câu hỏi tự kiểm

1. Mô tả từng bước của OIDC: ai ký token, token chứa những claim nào bạn dùng, AWS kiểm tra gì trước khi cấp quyền, quyền đó sống bao lâu.
2. Vì sao `sub` chứa `environment:production` an toàn hơn `ref:refs/heads/main`?
3. Role deploy có `ec2:DescribeInstances` trên `*`. Đó có phải vi phạm quyền tối thiểu không? Vì sao chấp nhận được?
4. Vì sao workflow kiểm tra định dạng tag **và** `deploy.sh` cũng kiểm tra lại?
5. `workflow_run` + điều kiện `head_repository.full_name`: kịch bản tấn công nào bị chặn?
6. So sánh deploy qua SSM Run Command với SSH từ runner: bảo mật, mạng, dấu vết kiểm toán, độ phức tạp.
7. Log driver `awslogs` chạy ở đâu và lấy quyền AWS từ đâu? Vì sao điều đó không mâu thuẫn với hop limit IMDS = 1?
8. Production đang lỗi. Bạn có 5 phút. Đọc to runbook rollback của mình — có bước nào phụ thuộc vào trí nhớ không?
9. Liệt kê những gì vẫn phải làm **tay** trên máy chủ ở v3. Cái nào nguy hiểm nhất khi quên?

---

## 10. Definition of Done và release v0.5.0

- [ ] OIDC provider, role `taskhub-github-deploy` (trust + policy đúng Q2, Q3), log group (retention 7), SNS (đã xác nhận), 2 alarm — tạo xong, ghi lệnh vào `infra/aws-manual/commands.md`.
- [ ] Environment `production`: người duyệt + chỉ `main` + 2 variables; **không** có secret AWS (Q1).
- [ ] `deploy.yml` đạt mục 4.1 và Q4; actionlint không báo lỗi; ba lệnh kiểm tra nhanh ở mục 6 ra đúng.
- [ ] Một lần merge vào `main` đã tự dẫn tới Deploy → Approve → production chạy đúng `:<sha7>` (T1).
- [ ] Hoàn thành T1–T9 (T10 tùy chọn), ghi trong `docs/experiments/v3-tests.md` có link các lần chạy.
- [ ] `docs/runbooks/rollback.md` có số phút đo thật < 5 (T5); `docs/architecture.md` có sơ đồ v3; ADR CD đã merge.
- [ ] README: badge workflow Deploy, mục CI/CD có luồng triển khai, link runbook rollback, cảnh báo chi phí.
- [ ] Code vào `main` qua PR (ví dụ `feat/cd-oidc-ssm`), CI xanh.
- [ ] **Release `v0.5.0`**: sau khi CI trên `main` xanh, `git tag -a v0.5.0 -m "v3: CD tự động qua OIDC + SSM"` → `git push origin v0.5.0` (workflow `Release` gắn `:v0.5.0`) → Actions → **Deploy** → *Run workflow* `image_tag = v0.5.0` → Approve. Kiểm tra: `sudo grep TASKHUB_IMAGE_TAG /opt/taskhub/.env` = `v0.5.0`; digest của `:v0.5.0` trùng `:<sha7>` vừa được deploy tự động (cùng một image — [v1](v1-ci.md)).
- [ ] 🟦 Nếu có domain: bản ghi A trong Route 53 trỏ về IP hiện tại, `APP_URL` dùng domain; ghi chi phí hosted zone vào `docs/cost.md`.
- [ ] Kiểm tra bản thân: [Checkpoint Module 06](../../06-AWS/checkpoint.md) (tuần 14).

➡️ Tiếp theo: [**v4 — Hạ tầng bằng Terraform, cài đặt máy chủ bằng Ansible**](v4-terraform.md) (tuần 15–16): toàn bộ VPC, SG, IAM, EC2, log group, alarm bạn vừa tạo tay sẽ được mô tả bằng code, dựng bằng `terraform apply` và xóa bằng `terraform destroy`.

---

## 11. Dọn dẹp

Trong tuần 13–14: **stop** EC2 sau mỗi buổi (nhớ cập nhật `APP_URL` khi start lại).

⚠️ Trước khi bắt đầu v4 (để Terraform dựng lại từ đầu, không trùng lặp và không tốn gấp đôi), xóa toàn bộ tài nguyên `ManagedBy=manual`, **trừ bucket `taskhub-backups-<account-id>`**: bucket này chứa dữ liệu (dùng tiếp ở v5) và sẽ được Terraform **import** ở tầng `bootstrap` của v4, không xóa đi tạo lại.

```bash
# CloudWatch + SNS
aws cloudwatch delete-alarms --alarm-names <tên-alarm-1> <tên-alarm-2>
aws logs delete-log-group --log-group-name /taskhub/dev/app
aws sns delete-topic --topic-arn <ARN-topic-taskhub-alerts>

# Role deploy (inline policy trước, role sau) và OIDC provider
aws iam delete-role-policy --role-name taskhub-github-deploy --policy-name <tên-inline-policy>
aws iam delete-role --role-name taskhub-github-deploy
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com

# EC2, SG, instance role, tham số: theo đúng thứ tự ở Lab 02 mục 14
```

Rồi chạy các lệnh kiểm tra "không còn gì sót" ở [Lab 02 mục 14](../../06-AWS/labs/lab-02-ec2-deploy-taskhub.md), thêm:

```bash
aws cloudwatch describe-alarms --alarm-name-prefix taskhub --query 'MetricAlarms[].AlarmName'   # []
aws logs describe-log-groups --log-group-name-prefix /taskhub --query 'logGroups[].logGroupName' # []
aws iam list-open-id-connect-providers                                                           # không còn GitHub
```

Trên GitHub: tạm **disable** workflow `Deploy` (Actions → Deploy → ⋯ → Disable workflow) cho tới khi v4 dựng lại hạ tầng — nếu không, mỗi lần merge sẽ tạo một lần deploy đỏ.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Configuring OpenID Connect in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) | Provider URL, audience, trust policy với environment, `id-token: write` | 2026-10-31 |
| [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials/releases) | v6.3.0 | 2026-10-31 |
| [AWS Systems Manager — Setting up Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-setting-up.html) | Giới hạn `SendCommand` theo tag `ssm:resourceTag/<key>` | 2026-10-31 |
| [Docker Docs — awslogs logging driver](https://docs.docker.com/engine/logging/drivers/awslogs/) | Quyền IAM, `awslogs-create-group`, stream mặc định | 2026-10-31 |
| [Amazon CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) | Logs, alarm | 2026-10-31 |
| [Amazon SNS pricing](https://aws.amazon.com/sns/pricing/) | Email | 2026-10-31 |
| [Amazon Route 53 pricing](https://aws.amazon.com/route53/pricing/) | 0,50 USD/hosted zone/tháng; zone xóa trong 12 giờ không tính | 2026-10-31 |
| [AWS KMS — Parameter Store SecureString](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html) | Mật khẩu trong deploy.sh | 2026-10-31 |
