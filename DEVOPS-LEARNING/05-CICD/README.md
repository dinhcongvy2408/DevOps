# Module 05 — CI/CD với GitHub Actions

> Tuần 9–10 (+ Jenkins ở tuần 22) · ~32 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 03 — Git](../03-GIT/README.md), [Module 04 — Docker](../04-DOCKER/README.md), dự án [taskhub v0](../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md) đã xong

## Mục lục

- [1. Vì sao DevOps phải biết CI/CD?](#1-vì-sao-devops-phải-biết-cicd)
- [2. Vì sao chọn GitHub Actions?](#2-vì-sao-chọn-github-actions)
- [3. Junior cần biết CI/CD đến mức nào?](#3-junior-cần-biết-cicd-đến-mức-nào)
- [4. Chuẩn bị trước khi học](#4-chuẩn-bị-trước-khi-học)
- [5. Thứ tự bài học](#5-thứ-tự-bài-học)
- [6. Lab bắt buộc, break-fix, checkpoint và dự án](#6-lab-bắt-buộc-break-fix-checkpoint-và-dự-án)
- [7. Chi phí: GitHub Actions có miễn phí không?](#7-chi-phí-github-actions-có-miễn-phí-không)
- [8. Nguyên tắc an toàn của module](#8-nguyên-tắc-an-toàn-của-module)
- [9. CI/CD trong các module sau](#9-cicd-trong-các-module-sau)
- [10. Checklist hoàn thành module](#10-checklist-hoàn-thành-module)
- [11. Nguồn học](#11-nguồn-học)

---

## 1. Vì sao DevOps phải biết CI/CD?

Đến hết tuần 8, mỗi lần đưa `taskhub` lên một phiên bản mới, bạn phải tự làm tay: chạy `./mvnw verify`, chờ test xong, `docker build`, `docker tag`, `docker login`, `docker push`, rồi tạo tag Git và Release. Có hơn mười bước, và chỉ cần quên một bước là hỏng:

- Quên chạy test → đẩy code lỗi lên `main`.
- Build image từ thư mục còn file chưa commit → image không khớp với bất kỳ commit nào.
- Push nhầm tag → không biết production đang chạy code nào.

**CI/CD** (Continuous Integration / Continuous Delivery — tích hợp liên tục / chuyển giao liên tục) là việc giao toàn bộ chuỗi đó cho một **pipeline** (đường ống tự động) chạy trên máy chủ sạch, theo đúng một kịch bản nằm trong repo, mỗi khi có thay đổi.

| Bạn sẽ làm ở công việc thật | Cần kiến thức của module này |
|---|---|
| "Viết pipeline cho service mới của team" | Bài 02, 03 |
| "PR của dev bị đỏ CI, họ nhờ bạn xem vì sao" | Bài 02 (đọc log job), [break-fix](labs/break-fix-01/README.md) |
| "Build image trong CI chậm quá, 15 phút một lần" | Bài 02 (cache Maven), bài 03 (cache layer Docker) |
| "Đừng để mật khẩu registry nằm trong YAML" | Bài 04 (secrets, `GITHUB_TOKEN`) |
| "Bản mới lỗi, quay về bản trước ngay" | Bài 05 (rollback bằng tag image bất biến) |
| "Công ty dùng Jenkins/GitLab, bạn đọc hiểu được không?" | Bài 06 |
| Phỏng vấn: "Mô tả pipeline của dự án bạn" | Toàn module + dự án [v1](../12-PRACTICAL-PROJECT/milestones/v1-ci.md) |

> **Công cụ thay đổi, khái niệm thì không.** Bài 01 học khái niệm trước (pipeline, artifact, build một lần triển khai nhiều nơi…). Sau đó GitHub Actions chỉ là một cách viết các khái niệm đó bằng YAML.

---

## 2. Vì sao chọn GitHub Actions?

Quyết định này đã được thống nhất ở [Lộ trình §5.1](../00-ROADMAP/learning-roadmap.md#51-cicd-chính-github-actions-jenkins-ở-mức-nhận-biết). Tóm tắt:

| Tiêu chí | GitHub Actions | Jenkins | GitLab CI |
|---|---|---|---|
| Chi phí khi học | Runner chuẩn **miễn phí cho repo public** | Phải tự chạy và bảo trì server | Phải chuyển repo sang GitLab |
| Gắn với nơi lưu code | Có sẵn trong GitHub, gắn với PR và branch protection | Tích hợp qua plugin | Có sẵn trong GitLab |
| Xác thực AWS không cần access key (OIDC) | Có sẵn (dùng ở v3, tuần 13) | Cấu hình thêm | Có sẵn |
| Phổ biến trong JD Việt Nam | Có | **Rất phổ biến** | Có, nhất là công ty tự host GitLab |
| Học ở module này | 🟥 Sâu (bài 02–05) | 🟨 Đọc hiểu `Jenkinsfile` (bài 06, tuần 22) | 🟦 Đọc hiểu `.gitlab-ci.yml` (bài 06, tuần 10) |

Lý do được ghi thành ADR mẫu trong dự án: xem [ADR-0001 ở 12-PRACTICAL-PROJECT §7](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr). Bạn sẽ viết ADR của chính mình cho `taskhub` ở dự án v1.

---

## 3. Junior cần biết CI/CD đến mức nào?

| Chủ đề | Mức cần cho Junior | Có thể học sau |
|---|---|---|
| CI, Continuous Delivery, Continuous Deployment | 🟥 Phân biệt được ba khái niệm, vẽ được pipeline | — |
| Workflow, event, job, step, runner | 🟥 **Tự viết** workflow build + test cho app Java, không copy | Reusable workflow, composite action tự viết |
| Đọc log job, tìm bước lỗi | 🟥 Từ log đỏ → tìm ra nguyên nhân gốc | — |
| Cache, artifact, service container | 🟥 Cache Maven, tải báo cáo test khi đỏ, PostgreSQL tạm cho test | Cache nâng cao, self-hosted runner |
| Build và push image, tag theo SHA/SemVer | 🟥 Pipeline đẩy image lên GHCR, không dùng `latest` | Build đa kiến trúc (amd64 + arm64) |
| Secrets, `GITHUB_TOKEN`, permissions | 🟥 Không để secret trong YAML; cấp quyền tối thiểu | Secret manager ngoài (Vault…) |
| Ghim action bằng SHA, Dependabot | 🟨 Hiểu vì sao và làm được | Tự host action nội bộ |
| Environments, required reviewers | 🟨 Hiểu khái niệm, cấu hình được trên repo public | Quy trình phê duyệt nhiều cấp |
| Deployment strategies, rollback | 🟥 Giải thích recreate, rolling, blue-green, canary; rollback bằng tag | Progressive delivery tự động |
| Matrix build | 🟨 Nhận biết, đọc hiểu | Matrix phức tạp |
| Jenkins / GitLab CI | 🟨 / 🟦 Đọc hiểu file pipeline, ánh xạ sang khái niệm đã học | Quản trị Jenkins, viết shared library |

**Quy tắc vàng:** bạn phải **tự viết** được `ci.yml` cho `taskhub` (build, test với PostgreSQL, build image, quét lỗ hổng, push GHCR) và khi pipeline đỏ, **tự đọc log để tìm ra bước lỗi và nguyên nhân** — không dán log vào AI rồi làm theo.

---

## 4. Chuẩn bị trước khi học

| Cần có | Kiểm tra | Nếu chưa có |
|---|---|---|
| Repo `taskhub` **public** trên GitHub, `main` được bảo vệ | `[GitHub]` Settings → Branches (hoặc Rules) có luật cho `main` | [Git bài 03](../03-GIT/03-github-pull-request-code-review.md) |
| `./mvnw verify` xanh trên máy | `[WSL]` `cd ~/projects/taskhub/app && ./mvnw -B verify` (PostgreSQL dev đang chạy) | [Hướng dẫn tạo app tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md) |
| `docker/Dockerfile` build được từ gốc repo | `[WSL]` `cd ~/projects/taskhub && docker build -f docker/Dockerfile -t taskhub:local .` | [Docker bài 03](../04-DOCKER/03-dockerfile-multistage.md) |
| Tag `v0.2.0` đã có | `git tag --list 'v*'` | [Dự án v0](../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md) |
| Hiểu `set -euo pipefail`, exit code | Giải thích được vì sao lệnh lỗi phải làm script dừng | [Linux bài 06](../01-LINUX/06-bash-scripting.md) |

Thư mục làm việc cho bài tập ngoài repo:

```bash
mkdir -p ~/devops-lab/05-cicd && cd ~/devops-lab/05-cicd
```

**Nhãn môi trường dùng trong module:**

| Nhãn | Nghĩa |
|---|---|
| `[WSL]` | Gõ trong terminal Ubuntu của bạn |
| `[GitHub]` | Thao tác trên giao diện web github.com |
| `[Runner]` | Lệnh chạy **bên trong** workflow, trên máy ảo của GitHub — bạn không gõ trực tiếp, mà viết vào file YAML |

---

## 5. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 01 | [Khái niệm CI/CD](01-cicd-concepts.md) | 9 | 3h | 🟥 |
| 02 | [GitHub Actions cơ bản](02-github-actions-basics.md) — workflow, job, step, runner, cache, artifact, service container | 9 | 5h | 🟥 |
| 03 | [GitHub Actions + Docker + registry](03-github-actions-docker-registry.md) — build, quét, push GHCR, release | 10 | 4h | 🟥 |
| 04 | [Secrets, permissions, environments](04-secrets-environments.md) — `GITHUB_TOKEN`, ghim SHA, Dependabot | 10 | 3h | 🟥 |
| 05 | [Deployment strategies & rollback](05-deployment-strategies-rollback.md) | 10 | 3h | 🟥 |
| 06 | [Jenkins & GitLab CI — mức nhận biết](06-jenkins-gitlab-overview.md) | 10 (phần GitLab) · 22 (phần Jenkins) | 1h + 4h | 🟨 / 🟦 |

Lời giải câu hỏi và bài tập: thư mục [solutions/](solutions/) — **chỉ mở sau khi đã tự làm**. Thuật ngữ: [glossary.md](glossary.md).

---

## 6. Lab bắt buộc, break-fix, checkpoint và dự án

| Hạng mục | Tuần | Mô tả |
|---|---|---|
| [Lab 01 — CI chặn PR](labs/lab-01-ci-pr-gate.md) | 9 | **Lab bắt buộc:** pipeline build + test chạy trên mỗi PR; PR chỉ merge được khi CI xanh |
| [Lab 02 — Release lên GHCR](labs/lab-02-release-ghcr.md) | 10 | **Lab bắt buộc:** tạo tag `v*` → image được gắn tag SemVer trên GHCR → GitHub Release |
| [Break-fix CI #1](labs/break-fix-01/README.md) | 10 | Pipeline có lỗi cài sẵn — đọc log, tìm và sửa |
| [Checkpoint Giai đoạn 5](checkpoint.md) | 10 | Lý thuyết + thực hành mới + break-fix, không dùng AI |
| [Bản tham khảo workflow](labs/reference/README.md) | 9–10 | `ci.yml`, `release.yml`, `dependabot.yml` hoàn chỉnh — **chỉ mở sau khi tự viết** |
| [Dự án: taskhub v1](../12-PRACTICAL-PROJECT/milestones/v1-ci.md) | 9–10 | CI build, test, quét, push GHCR; release `v0.3.0` |

Quy ước dùng chung cho mọi bài trong module (khớp với [bản tham khảo](labs/reference/README.md)):

| Thành phần | Giá trị |
|---|---|
| File workflow | `.github/workflows/ci.yml` (tên `CI`, job `build-test` và `image`) · `.github/workflows/release.yml` (tên `Release`, job `promote`) |
| Runner | `ubuntu-24.04` — không dùng `ubuntu-latest` (lý do ở bài 02) |
| Java | Temurin 21 qua `actions/setup-java`, build bằng `./mvnw -B -ntp verify` trong `app/` |
| Database cho test | Service container `postgres:17` |
| Image | `ghcr.io/<github-user>/taskhub:<sha7>` — push khi merge vào `main` |
| Phát hành | Tag Git `vX.Y.Z` → gắn thêm tag `:vX.Y.Z` cho **chính image đó**, không build lại. Không dùng `latest` |
| Phiên bản action (kiểm tra 2026-10-31) | `actions/checkout@v7`, `actions/setup-java@v6`, `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `docker/setup-buildx-action@v4`, `docker/metadata-action@v6`, `docker/build-push-action@v7`, `docker/login-action@v4`, `aquasecurity/trivy-action@v0.36.0` |
| Tên GitHub trong đầu ra mẫu | `phuong-dev` — thay bằng tên của bạn |

> Bài 02–03 viết action theo tag (`@v7`) cho dễ đọc. Bài 04 giải thích vì sao bản cuối của dự án phải **ghim bằng SHA commit đầy đủ**, và bản tham khảo đã làm như vậy.

---

## 7. Chi phí: GitHub Actions có miễn phí không?

Theo [trang billing GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions) (kiểm tra 2026-10-31):

| Trường hợp | Chi phí |
|---|---|
| **Repo public**, runner chuẩn do GitHub cung cấp | **Miễn phí**, không trừ vào hạn mức |
| Repo private, gói GitHub Free | Được tặng **$12 giá trị compute mỗi tháng** (tính theo đơn giá $0.006/phút của runner Linux 2 nhân thì khoảng 2.000 phút — con số này là phép tính, trang chính thức ghi theo USD) |
| Dung lượng artifact + GitHub Packages (gói Free) | 500 MB, dùng chung |
| Cache | 10 GB mỗi repo |
| Self-hosted runner (runner bạn tự chạy) | Trang billing ghi là **miễn phí**. GitHub từng công bố (12/2025) sẽ thu $0.002/phút từ 03/2026, sau đó đã hoãn — hãy đọc lại trang billing nếu bạn định dùng |

Vì repo `taskhub` là **public** (đã quyết định ở [v-pre](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md)), toàn bộ module này **không tốn tiền**. Image public trên GHCR cũng miễn phí.

> ⚠️ Nếu bạn thử nghiệm trên repo **private**: workflow chạy vòng lặp lỗi hoặc `schedule` quá dày có thể tiêu hết hạn mức. Xem mức đã dùng tại `[GitHub]` avatar → **Settings** → **Billing and licensing**.

---

## 8. Nguyên tắc an toàn của module

- **Không bao giờ** viết mật khẩu, token, access key thật vào file YAML. Dùng **Secrets** (bài 04). Repo public nghĩa là cả thế giới đọc được workflow **và log** của bạn.
- Log của workflow trên repo public cũng **public**. Đừng `echo` biến chứa secret, đừng `cat` file cấu hình có mật khẩu, đừng bật chế độ debug in toàn bộ môi trường.
- Mật khẩu PostgreSQL trong CI (`ci-only-password`) được ghi thẳng vào YAML **có chủ đích**: database đó chỉ sống vài phút trong một máy ảo dùng một lần, không chứa dữ liệu thật. Mật khẩu của môi trường thật luôn là secret.
- Action của bên thứ ba là **code của người khác chạy với quyền của bạn**. Bài 04 kể sự cố tháng 3/2026: 76/77 tag của `aquasecurity/trivy-action` bị thay bằng mã độc đánh cắp secret. Cách phòng: ghim SHA, cấp `permissions` tối thiểu.
- ⚠️ Không chạy workflow `pull_request_target` với code từ fork khi chưa hiểu rủi ro (bài 04).
- Không có tài nguyên AWS nào trong module này. AWS bắt đầu từ tuần 11.

---

## 9. CI/CD trong các module sau

| Khái niệm ở đây | Gặp lại ở |
|---|---|
| Image tag theo SHA, GHCR | EC2 pull image chạy bằng Compose (Module 06, v2) |
| Workflow deploy, environment | CD tự động lên EC2 qua OIDC, không lưu access key (Module 06, v3) |
| `paths:` filter, job theo thư mục | Workflow `terraform plan` chỉ chạy khi `infra/` đổi (Module 07, v4) |
| Rollback bằng tag bất biến | Runbook rollback + diễn tập < 5 phút (Module 08, v5) |
| Build image trong CI | Helm chart dùng image từ GHCR (Module 09, v6) |
| Quét image, secret, dependency | DevSecOps tổng hợp (Module 10) |
| Jenkins | Lab Jenkins chạy bằng Docker (tuần 22) |

---

## 10. Checklist hoàn thành module

- [ ] 🟥 Phân biệt được Continuous Integration, Continuous Delivery, Continuous Deployment bằng ví dụ `taskhub`.
- [ ] 🟥 Giải thích được workflow, event, job, step, runner, action và vẽ được luồng chạy của `ci.yml`.
- [ ] 🟥 Tự viết job `build-test`: checkout, JDK 21 + cache Maven, PostgreSQL service container, `./mvnw verify`.
- [ ] 🟥 PR chỉ merge được khi CI xanh (required status check đã bật).
- [ ] 🟥 Pipeline build image, quét bằng Trivy, push `ghcr.io/<user>/taskhub:<sha7>` khi merge vào `main`.
- [ ] 🟥 Tạo tag `v0.3.0` → image được gắn tag `:v0.3.0` (cùng digest với `:<sha7>`) → GitHub Release.
- [ ] 🟥 Không có secret trong YAML hay log; `permissions` khai báo tối thiểu.
- [ ] 🟨 Action được ghim bằng SHA; Dependabot được bật.
- [ ] 🟥 Giải thích được recreate, rolling, blue-green, canary và cách rollback `taskhub`.
- [ ] 🟨 Đọc hiểu một `Jenkinsfile` và một `.gitlab-ci.yml` đơn giản.
- [ ] 🟥 Pipeline đỏ → tìm ra bước lỗi và nguyên nhân gốc từ log ([break-fix](labs/break-fix-01/README.md)).
- [ ] 🟥 Đạt [Checkpoint Giai đoạn 5](checkpoint.md).
- [ ] 🟥 Hoàn thành [taskhub v1](../12-PRACTICAL-PROJECT/milestones/v1-ci.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#cicd).

---

## 11. Nguồn học

| Vai trò | Nguồn | Ghi chú | Kiểm tra ngày |
|---|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt | — |
| Chính | [GitHub Docs — Understanding GitHub Actions](https://docs.github.com/en/actions/get-started/understand-github-actions) | Workflow, event, job, action, runner | 2026-10-31 |
| Chính | [GitHub Docs — Publishing Docker images](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images) | Workflow mẫu đẩy image lên GHCR | 2026-10-31 |
| Khái niệm | [Martin Fowler — Continuous Integration](https://martinfowler.com/articles/continuousIntegration.html) | Bài kinh điển về CI, cập nhật lớn 01/2024 | 2026-10-31 |
| Khái niệm | [continuousdelivery.com](https://continuousdelivery.com/) | Trang của Jez Humble — định nghĩa Continuous Delivery | 2026-10-31 |
| Đo lường | [DORA — Software delivery performance metrics](https://dora.dev/guides/dora-metrics/) | Các chỉ số đo hiệu quả chuyển giao phần mềm | 2026-10-31 |
| Tra cứu | [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) | Chi phí, hạn mức | 2026-10-31 |

Thuật ngữ của module: [glossary.md](glossary.md).
