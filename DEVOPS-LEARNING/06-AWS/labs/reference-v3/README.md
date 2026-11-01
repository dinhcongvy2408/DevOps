# Bản tham khảo cho `taskhub` v2–v3 (EC2 + CD tự động)

> ⚠️ **Chỉ mở sau khi đã tự viết.** Mục tiêu của tuần 12–13 là bạn tự viết được từng dòng và giải thích được vì sao. File ở đây để **so sánh**, không phải để chép.
> Mọi ARN dùng account id ví dụ `111122223333` và user GitHub `phuong-dev` — thay bằng giá trị của bạn.

| File ở đây | Đặt vào | Dùng từ | Ghi chú |
|---|---|---|---|
| [compose.yaml](compose.yaml) | gốc repo `taskhub` (thay `compose.yaml` của v0) | v2 | Bản **triển khai**: `image: ghcr.io/<user>/taskhub:${TASKHUB_IMAGE_TAG}`, không `build:` |
| [compose.override.yaml](compose.override.yaml) | gốc repo | v2 | Chỉ cho laptop: thêm lại `build:` — Compose tự gộp khi không dùng `-f` |
| [compose.aws.yaml](compose.aws.yaml) | gốc repo | v3 | Chỉ cho EC2: log driver `awslogs` → CloudWatch Logs |
| [scripts/deploy.sh](scripts/deploy.sh) | `scripts/deploy.sh` (nhớ `git update-index --chmod=+x`) | v2 | Lấy mật khẩu từ Parameter Store, đổi tag, pull, `up --wait`, smoke test, tự rollback |
| [user-data.sh](user-data.sh) | dùng khi `run-instances --user-data file://...` | v2 | Cài Docker (repo apt chính thức) + AWS CLI (snap). Không chứa secret |
| [iam/taskhub-ec2-trust.json](iam/taskhub-ec2-trust.json) | `aws iam create-role --assume-role-policy-document` | v2 | Cho phép **dịch vụ EC2** nhận role |
| [iam/taskhub-ec2-app-policy.json](iam/taskhub-ec2-app-policy.json) | inline policy `taskhub-ec2-app` của `taskhub-ec2-role` | v2 (Parameter Store), v3 (Logs) | Ở v2 chỉ cần statement đầu. Quyền S3 cho backup **không** nằm ở đây mà ở inline policy riêng `taskhub-ec2-s3-backup` ([bài 05 — S3](../../05-s3.md)): chỉ prefix `pg-dumps/*`, không có `DeleteObject` |
| [iam/taskhub-github-deploy-trust.json](iam/taskhub-github-deploy-trust.json) | trust policy của `taskhub-github-deploy` | v3 | Chỉ workflow chạy trong environment `production` của đúng repo mới nhận được role |
| [iam/taskhub-github-deploy-policy.json](iam/taskhub-github-deploy-policy.json) | inline policy của `taskhub-github-deploy` | v3 | Chỉ được gửi `AWS-RunShellScript` tới instance có tag `Project=taskhub` |
| [deploy.yml](deploy.yml) | `.github/workflows/deploy.yml` | v3 | Workflow `Deploy`, job `deploy` |

Dùng trong: [Lab 02 — Triển khai taskhub lên EC2](../lab-02-ec2-deploy-taskhub.md) · [Milestone v2](../../../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) · [Milestone v3](../../../12-PRACTICAL-PROJECT/milestones/v3-cd.md)

## Luồng tổng thể (v3)

```text
 merge PR vào main ─► CI (build-test → image: push :<sha7>)
                         │ completed + success + event=push + đúng repo
                         ▼
                      Deploy (workflow_run)  ── hoặc Run workflow tay với image_tag (rollback)
                         │ environment production → chờ bạn bấm Approve
                         │ OIDC: GitHub cấp JWT ─► STS AssumeRoleWithWebIdentity ─► quyền tạm ~1 giờ
                         ▼
                      ssm send-command AWS-RunShellScript ──► EC2 (SSM Agent, kết nối RA ngoài qua 443)
                                                               └─ /opt/taskhub/scripts/deploy.sh <tag>
                                                                    ├─ Parameter Store → POSTGRES_PASSWORD
                                                                    ├─ compose pull + up --wait
                                                                    └─ lỗi → quay về tag trước
                         ▼
                      smoke test: curl $APP_URL/actuator/health từ runner (đi qua Internet + SG)
```

## Các quyết định trong file và lý do

| Quyết định | Lý do | Đánh đổi |
|---|---|---|
| Deploy qua **SSM Run Command**, không SSH | Không mở port 22, không có SSH key nào nằm trong GitHub; mọi lệnh được ghi lại trong lịch sử Run Command | Phụ thuộc SSM Agent + đường ra Internet của EC2 (public subnet có IGW) |
| **OIDC**, không access key | Không có secret AWS dài hạn nào để lộ; quyền tự hết hạn | Trust policy phải viết đúng `sub` — sai một ký tự là `AccessDenied` (thử nghiệm ở v3) |
| `sub` = `repo:<user>/taskhub:environment:production` | Chỉ job khai báo `environment: production` (có người duyệt) mới đổi được token lấy quyền | Muốn thêm môi trường `staging` → thêm điều kiện/role riêng |
| `ssm:resourceTag/Project` = `taskhub` | Role deploy **không** chạy được lệnh trên instance khác trong account, kể cả khi bị lạm dụng | Quên gắn tag `Project=taskhub` cho EC2 mới → deploy báo `AccessDenied` |
| Chỉ document `AWS-RunShellScript` | Không cho dùng các document khác (vd tạo user, cài phần mềm) | — |
| Kiểm tra định dạng tag ở **cả** workflow **và** deploy.sh | `image_tag` do người gõ tay; chuỗi kiểu `v1; rm -rf /` không bao giờ được tới shell của EC2 | — |
| `if:` kiểm tra `event == 'push'` và `head_repository.full_name` | `branches: [main]` của `workflow_run` so **tên** nhánh — PR từ fork có nhánh tên `main` cũng khớp | — |
| Mật khẩu ở **Parameter Store SecureString** (tầng Standard) | Không nằm trong Git, user data, AMI hay GitHub; đổi mật khẩu ở một chỗ | Vẫn hiện trong `.env` (quyền 600) và `docker inspect` trên host — xem thử nghiệm ở Lab 02 |
| **Không** có `kms:Decrypt` trong policy của EC2 | Tài liệu KMS: không thể đặt chính sách truy cập riêng cho key mặc định `aws/ssm`; quyền đọc được kiểm soát bằng `ssm:GetParameter` | Nếu sau này dùng customer managed key thì phải thêm `kms:Decrypt` (kèm điều kiện) |
| `mem_limit: 768m` cho service `taskhub` | JVM chạy với `-XX:MaxRAMPercentage=75.0`: có giới hạn cgroup thì heap tính theo 768 MiB; không có thì tính theo cả 2 GiB của `t3.small` và giành RAM của postgres + nginx ([bài 04 — EC2](../../04-ec2.md)) | Ứng dụng lớn lên cần nâng giới hạn — đo bằng `docker stats` trước |
| IMDSv2 bắt buộc, **hop limit = 1** | Container (sau thêm một bước mạng qua bridge) không lấy được token IMDS → không lấy được quyền của instance role. Docker daemon chạy trên host vẫn dùng được (log `awslogs`) | Nếu sau này có container **cần** quyền AWS thì phải nâng lên 2 và chấp nhận rủi ro |
| Tự hỏi trạng thái SSM thay vì `aws ssm wait command-executed` | Waiter của CLI chỉ chờ khoảng 100 giây; `deploy.sh` có thể cần tới 3 phút (healthcheck `start_period: 60s`) | Vòng lặp dài hơn một dòng lệnh |
| `vars.APP_URL` là IP public | Không cần domain, không tốn tiền Route 53 | IP đổi mỗi lần stop/start → phải cập nhật biến (hoặc dùng Elastic IP / Route 53) |

## Phiên bản đã ghim (kiểm tra 2026-10-31)

| Action | Phiên bản | SHA commit |
|---|---|---|
| `aws-actions/configure-aws-credentials` | v6.3.0 | `e1253824e5c10ff9df46874f81ed3ec929e19cfd` |

Tự kiểm tra lại:

```bash
git ls-remote https://github.com/aws-actions/configure-aws-credentials 'refs/tags/v6.3.0' 'refs/tags/v6.3.0^{}'
```

Nhớ thêm SHA này vào phạm vi Dependabot (`package-ecosystem: github-actions` đã có ở v1 — nó tự quét file mới trong `.github/workflows`).

## Đã kiểm tra những gì

- `deploy.yml`: actionlint 1.7.12 (cùng thư mục với `ci.yml` của v1) — không báo lỗi; PyYAML đọc được.
- `compose*.yaml`: `docker compose config` cho hai cách gộp (EC2: `-f compose.yaml -f compose.aws.yaml`; laptop: tự gộp override) ra đúng image/driver mong đợi; thiếu `TASKHUB_IMAGE_TAG` → Compose từ chối với thông báo rõ ràng.
- `deploy.sh`, `user-data.sh`: `bash -n`.
- `iam/*.json`: JSON hợp lệ. Khóa điều kiện `ssm:resourceTag/<key>` lấy từ ví dụ chính thức trong tài liệu Run Command.
- **Chưa** chạy trên AWS thật — lần chạy thật đầu tiên là của bạn ở Lab 02 / v3. Gặp khác biệt thì ghi vào nhật ký debug.

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Configuring OpenID Connect in AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws) | Provider URL, audience, `sub` với environment, `id-token: write` | 2026-10-31 |
| [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials/releases) | Phiên bản v6.3.0 | 2026-10-31 |
| [AWS Systems Manager — Setting up Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command-setting-up.html) | Giới hạn `SendCommand` theo tag bằng `ssm:resourceTag/<key>` | 2026-10-31 |
| [AWS KMS — Parameter Store SecureString](https://docs.aws.amazon.com/kms/latest/developerguide/services-parameter-store.html) | `aws/ssm`, quyền giải mã | 2026-10-31 |
| [Docker Docs — awslogs logging driver](https://docs.docker.com/engine/logging/drivers/awslogs/) | Quyền IAM, `awslogs-create-group` mặc định false, stream mặc định = container ID | 2026-10-31 |
| [Docker Docs — Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/) | Lệnh trong `user-data.sh` | 2026-10-31 |
| [AWS CLI — Install (snap)](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | `snap install aws-cli --classic` | 2026-10-31 |
