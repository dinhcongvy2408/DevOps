# Milestone v1 — CI với GitHub Actions (tuần 9–10)

> Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 05 — CI/CD](../../05-CICD/README.md), milestone [v0 — Docker Compose](v0-docker-compose.md) (release `v0.2.0`)
> Môi trường: `[WSL]` (git, docker), `[GitHub]` (giao diện web: Settings, Actions, Packages), `[Runner]` (máy ảo GitHub chạy workflow, bạn chỉ đọc log)
> Đây là **việc cần nộp + tiêu chí chấp nhận**. Các bước làm chi tiết nằm ở [Lab 01 — CI chặn PR](../../05-CICD/labs/lab-01-ci-pr-gate.md) (tuần 9) và [Lab 02 — Release lên GHCR](../../05-CICD/labs/lab-02-release-ghcr.md) (tuần 10). Làm lab trước, rồi đưa kết quả vào repo `taskhub`.

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc v1](#2-kiến-trúc-v1)
- [3. File phải có trong repo](#3-file-phải-có-trong-repo)
- [4. Cấu hình trên GitHub](#4-cấu-hình-trên-github)
- [5. Yêu cầu chất lượng](#5-yêu-cầu-chất-lượng)
- [6. Thử nghiệm bắt buộc](#6-thử-nghiệm-bắt-buộc)
- [7. Xử lý sự cố thường gặp](#7-xử-lý-sự-cố-thường-gặp)
- [8. Câu hỏi tự kiểm](#8-câu-hỏi-tự-kiểm)
- [9. Definition of Done và release v0.3.0](#9-definition-of-done-và-release-v030)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

Từ v1, **không còn ai build image bằng tay**. Mọi thay đổi đi theo một con đường duy nhất:

```text
nhánh feat/* → Pull Request → CI xanh → merge main → CI push image :<sha7> → git tag v* → Release gắn :vX.Y.Z
```

Cụ thể, sau milestone này:

1. Mỗi Pull Request vào `main` tự động **build, test (với PostgreSQL thật), build image, quét lỗ hổng**. PR đỏ thì **không merge được**.
2. Mỗi commit vào `main` có một image trên GHCR: `ghcr.io/<github-user>/taskhub:<sha7>`.
3. Push một tag `v0.3.0` → image **đã được test và quét** của commit đó được gắn thêm tag `:v0.3.0`, và một GitHub Release được tạo tự động.
4. Bạn giải thích được **từng dòng** trong `ci.yml`, `release.yml`, `dependabot.yml`.

Vì sao milestone này quan trọng: từ v2 (EC2) trở đi, server chỉ **kéo image về và chạy**. Nếu image không đáng tin (chưa test, chưa quét, không biết build từ commit nào) thì mọi thứ phía sau cũng không đáng tin. Câu hỏi phỏng vấn kinh điển "Pipeline của bạn gồm những bước nào, vì sao theo thứ tự đó?" được trả lời bằng chính milestone này.

---

## 2. Kiến trúc v1

```text
 [WSL] git push nhánh feat/*                    [GitHub] mở Pull Request vào main
              │                                              │
              ▼                                              ▼
 ┌──────────────────────── Workflow "CI" (.github/workflows/ci.yml) ────────────────────────┐
 │  job build-test  (runner ubuntu-24.04, dùng một lần rồi bỏ)                              │
 │    ├─ service container postgres:17  ◄── localhost:5432                                  │
 │    ├─ setup-java 21 + cache Maven                                                        │
 │    └─ ./mvnw -B -ntp verify   ── đỏ → upload test-reports, dừng                          │
 │                │ needs                                                                   │
 │                ▼                                                                         │
 │  job image                                                                               │
 │    ├─ buildx build docker/Dockerfile (cache type=gha) → load vào Docker của runner       │
 │    ├─ Trivy: CRITICAL đã có bản vá → exit 1 → DỪNG, không push                           │
 │    └─ chỉ khi event = push vào main: login GHCR (GITHUB_TOKEN) → push :<sha7>            │
 └──────────────────────────────────────────────────────────────────────────────────────────┘
              │ PR: chỉ kết quả xanh/đỏ (status check)          │ main: image trên registry
              ▼                                                  ▼
   Branch protection: bắt buộc build-test + image      ghcr.io/<github-user>/taskhub:9f8e7d6

 [WSL] git tag -a v0.3.0 && git push origin v0.3.0
              │
              ▼
 ┌──────────── Workflow "Release" (.github/workflows/release.yml) ────────────┐
 │  job promote                                                               │
 │    ├─ tìm :<sha7> của commit được tag  ── không có → báo lỗi rõ ràng, dừng │
 │    ├─ imagetools create: gắn thêm :v0.3.0 cho CHÍNH image đó (không build) │
 │    └─ gh release create v0.3.0 --generate-notes                            │
 └────────────────────────────────────────────────────────────────────────────┘
```

| Workflow | Kích hoạt bởi | Job | Quyền `GITHUB_TOKEN` | Kết quả |
|---|---|---|---|---|
| `CI` | `pull_request` vào `main` | `build-test` → `image` | `contents: read` (+ `packages: write` ở job `image`, nhưng bước push bị bỏ qua) | Status check xanh/đỏ trên PR. **Không push image** |
| `CI` | `push` vào `main` | `build-test` → `image` | như trên | Image `:<sha7>` trên GHCR |
| `Release` | `push` tag `v*.*.*` | `promote` | `contents: write`, `packages: write` | Tag `:vX.Y.Z` + GitHub Release |

**Vì sao PR không push image?** Image của PR là code **chưa được duyệt**. Đẩy nó lên registry nghĩa là registry chứa thứ có thể không bao giờ được merge — và một người lỡ tay `docker pull` nhầm tag là chạy code chưa review. Hơn nữa, PR từ fork chỉ nhận `GITHUB_TOKEN` chỉ-đọc (học ở [bài 04](../../05-CICD/04-secrets-environments.md)), nên thiết kế "PR chỉ build và quét" chạy đúng cho mọi loại PR.

**Vì sao release không build lại?** Build lại từ cùng một commit **vẫn có thể ra image khác**: base image `eclipse-temurin:21-jre-noble` có thể đã được cập nhật, dependency có thể đổi, thời điểm build khác. Image chạy production phải là **đúng image đã qua test và Trivy** — nguyên tắc *build once, deploy many* ở [Git bài 04](../../03-GIT/04-team-workflows.md) và [CI/CD bài 01](../../05-CICD/01-cicd-concepts.md).

---

## 3. File phải có trong repo

Theo [cấu trúc repo](../README.md#4-cấu-trúc-repo-taskhub):

```text
taskhub/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml              # MỚI — job build-test, image
│   │   └── release.yml         # MỚI — job promote
│   └── dependabot.yml          # MỚI — KHÔNG nằm trong workflows/
├── docs/
│   ├── adr/0003-scan-before-push-promote-image.md   # MỚI (xem bên dưới)
│   └── experiments/v1-tests.md # MỚI — ghi kết quả T1–T8
├── compose.yaml                # CẬP NHẬT 🟨 — thêm image: cho service taskhub (dùng ở T7)
└── README.md                   # CẬP NHẬT — badge CI + mục "CI/CD"
```

**Bản tham khảo:** [05-CICD/labs/reference/](../../05-CICD/labs/reference/README.md) có `ci.yml`, `release.yml`, `dependabot.yml` hoàn chỉnh, đã ghim SHA. ⚠️ **Chỉ mở sau khi bạn đã tự viết xong phiên bản của mình** và nó đã chạy (xanh hoặc đỏ). Khi so sánh, mỗi chỗ khác nhau hãy tự hỏi: "bản của mình sai, hay chỉ là một lựa chọn khác có lý do?" — ghi lại câu trả lời.

### 3.1. `ci.yml` — những gì phải có

| Phần | Yêu cầu | Học ở |
|---|---|---|
| Trigger | `pull_request` và `push`, cả hai giới hạn `branches: [main]` | [Bài 02](../../05-CICD/02-github-actions-basics.md) |
| `permissions` cấp workflow | `contents: read` | [Bài 04](../../05-CICD/04-secrets-environments.md) |
| `concurrency` | Hủy lần chạy cũ của **cùng PR**; **không** hủy trên `main` | Bài 02 |
| Job `build-test` | Service container `postgres:17` có healthcheck `pg_isready`; biến `SPRING_DATASOURCE_*` trỏ `localhost:5432`; `setup-java` Temurin 21 + `cache: maven`; `./mvnw -B -ntp verify` trong `app/`; upload `app/target/surefire-reports/` **khi thất bại** | Bài 02 |
| Job `image` | `needs: build-test`; buildx; metadata-action sinh tag `:<sha7>` (không tiền tố `sha-`, không `latest`); build với `load: true` + cache `type=gha`; Trivy chặn CRITICAL; login + push **chỉ khi** `github.event_name == 'push'` | [Bài 03](../../05-CICD/03-github-actions-docker-registry.md) |

**Tên job chính là tên status check.** Đặt `name: build-test` và `name: image` đúng như vậy — branch protection (mục 4) chọn check theo tên này. Đổi tên job sau khi đã bật bảo vệ → PR bị treo ở *Expected — Waiting for status to be reported* (xem mục 7).

### 3.2. `release.yml` — những gì phải có

- Trigger `push: tags: ['v*.*.*']` — không chạy với tag thử nghiệm kiểu `test-1`.
- Job `promote` với quyền `contents: write` (tạo Release) và `packages: write` (gắn tag image).
- Tên image chữ thường: `${GITHUB_REPOSITORY_OWNER,,}` (registry từ chối chữ hoa; `metadata-action` tự chuyển, còn script bash của bạn thì không).
- Kiểm tra `:<sha7>` **tồn tại** trước khi gắn tag; không có thì in `::error::` giải thích nguyên nhân khả dĩ và `exit 1`.
- `docker buildx imagetools create --tag <image>:<tag> <image>:<sha7>` — không có `docker build` nào trong file.
- `gh release create "$TAG" --verify-tag --generate-notes`.
- Giá trị từ `${{ github.ref_name }}` được đưa vào script qua `env:` chứ không nhúng thẳng vào `run:` (chống script injection — [bài 04](../../05-CICD/04-secrets-environments.md)).

### 3.3. `dependabot.yml`

Ba ecosystem: `github-actions` (`directory: /` — Dependabot tự tìm trong `.github/workflows`), `maven` (`directory: /app`), `docker` (`directory: /docker`). Lịch `weekly`. Xử lý PR của Dependabot như mọi PR khác: đọc release notes, chờ CI xanh, rồi mới merge (thử nghiệm T8).

### 3.4. README — badge và mục "CI/CD"

Badge trạng thái theo [định dạng trong docs GitHub](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge) (thay `phuong-dev` bằng user của bạn):

```markdown
[![CI](https://github.com/phuong-dev/taskhub/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/phuong-dev/taskhub/actions/workflows/ci.yml)
```

`?branch=main` để badge phản ánh **main**, không bị đỏ chỉ vì một PR đang làm dở.

Mục **"CI/CD"** trong README gồm: sơ đồ luồng (rút gọn từ mục 2), bảng "workflow nào chạy khi nào, làm gì", quy ước tag image (`:<sha7>` cho mỗi commit main, `:vX.Y.Z` cho bản phát hành, **không có `latest`**), và cách release: *"merge vào main → chờ CI xanh → `git tag -a vX.Y.Z -m ...` → `git push origin vX.Y.Z`"*.

### 3.5. ADR

ADR-0001 (chọn GitHub Actions) là ví dụ trong [README dự án §7](../README.md#7-ghi-lại-quyết-định-adr); ADR-0002 là quy trình Git (bài tập ở [Git bài 04](../../03-GIT/04-team-workflows.md)). Nếu repo của bạn chưa có hai ADR đó, viết luôn — ADR-0001 giờ đã có đủ dữ kiện thật.

Milestone này thêm **`docs/adr/0003-scan-before-push-promote-image.md`**, ghi lại hai quyết định:

1. **Quét trước khi push** (Trivy chặn CRITICAL đã có bản vá trong job `image`) — lựa chọn khác: push rồi mới quét; quét định kỳ trên registry.
2. **Release gắn tag cho image có sẵn thay vì build lại** — lựa chọn khác: build lại khi có tag (đơn giản hơn, nhưng image release ≠ image đã test).

Phần *Hệ quả* phải nêu cả nhược điểm bạn chấp nhận, ví dụ: phải chờ CI trên `main` xanh rồi mới tag được (T5); một CVE CRITICAL mới công bố ở base image có thể làm đỏ **mọi** PR dù code không đổi; chỉ chặn CRITICAL nghĩa là HIGH vẫn lọt qua.

---

## 4. Cấu hình trên GitHub

Làm `[GitHub]` sau khi workflow `CI` đã chạy **ít nhất một lần** trên repo — ô tìm status check chỉ gợi ý những check đã từng báo kết quả gần đây.

| Ở đâu | Cài đặt | Giá trị | Vì sao |
|---|---|---|---|
| Settings → Branches → luật cho `main` (hoặc Rulesets) | *Require status checks to pass before merging* | Bật, chọn **`build-test`** và **`image`** | Đây là ô bạn để "⏳ Tuần 9" ở [Git bài 03](../../03-GIT/03-github-pull-request-code-review.md) |
| cùng chỗ | *Require branches to be up to date before merging* | 🟨 Nên bật | Chế độ "strict": PR phải chứa commit mới nhất của `main` → CI chạy trên đúng thứ sẽ được merge. Đánh đổi: phải cập nhật nhánh nhiều hơn |
| Settings → Actions → General → *Workflow permissions* | Quyền mặc định của `GITHUB_TOKEN` | *Read repository contents and packages permissions* | Phòng khi một workflow quên khai báo `permissions:` |
| Package `taskhub` → Package settings | *Manage Actions access* | Repo `taskhub`, Role **Write** — **chỉ cần nếu** package được tạo bằng PAT ở tuần 8 (T6) | Package có từ trước không tự cấp quyền cho workflow |
| Package `taskhub` → Package settings | Visibility | Public | Như [Docker bài 06](../../04-DOCKER/06-registry.md): EC2 ở v2 pull không cần token. Điều kiện: image không chứa secret |

---

## 5. Yêu cầu chất lượng

| # | Yêu cầu | Vì sao | Học ở |
|---|---|---|---|
| Q1 | **Quyền tối thiểu**: `permissions: contents: read` ở cấp workflow; chỉ job cần ghi mới khai báo thêm (`packages: write`, `contents: write`) | `GITHUB_TOKEN` bị lộ (qua một action độc hại) thì thiệt hại chỉ bằng quyền nó có | [Bài 04](../../05-CICD/04-secrets-environments.md) |
| Q2 | **Mọi action ghim bằng SHA commit đầy đủ (40 ký tự) kèm ghi chú phiên bản**, ví dụ `uses: docker/login-action@<40-ký-tự> # v4.7.0`. Tự lấy SHA bằng `git ls-remote` — với tag có chú thích (annotated) phải lấy dòng `^{}` | Tag có thể bị push đè: tháng 3/2026, 76/77 tag của `aquasecurity/trivy-action` bị đổi thành mã đánh cắp secret. SHA thì không đổi được | Bài 04 |
| Q3 | `runs-on: ubuntu-24.04`, **không** `ubuntu-latest` | `ubuntu-latest` đang được chuyển từ 24.04 sang 26.04 (19/10–19/11/2026) — hai lần chạy cùng commit có thể ra hai image runner khác nhau | [Bài 02](../../05-CICD/02-github-actions-basics.md) |
| Q4 | Mọi job có **`timeout-minutes`** (gợi ý: 15 cho `build-test`, 20 cho `image`, 10 cho `promote`) | Mặc định một job được chạy tới 6 giờ; test treo vì chờ database sẽ "đốt" thời gian vô ích | Bài 02 |
| Q5 | **`concurrency`** đúng như mục 3.1 | Push 3 commit liên tiếp lên PR thì chỉ lần cuối cần kết quả; nhưng mỗi commit của `main` đều phải có image | Bài 02 |
| Q6 | **Không có secret trong YAML.** Ngoại lệ duy nhất được phép: mật khẩu PostgreSQL của service container CI, kèm comment giải thích vì sao không phải secret | Database tạm sống trong runner dùng một lần, không chứa dữ liệu thật. Mật khẩu **thật** (v2 trở đi) luôn là secret | Bài 04 |
| Q7 | **Tag image chỉ có hai dạng**: `:<sha7>` (mỗi commit `main`) và `:vX.Y.Z` (bản phát hành). Không `latest`, không `main`, không `pr-N` | Tag bất biến = biết chính xác đang chạy code nào, rollback được ([Docker bài 06](../../04-DOCKER/06-registry.md)). Nhớ `flavor: latest=false` — mặc định `metadata-action` tự thêm `latest` cho sự kiện tag | [Bài 03](../../05-CICD/03-github-actions-docker-registry.md) |
| Q8 | **Trivy là cổng chặn**: `severity: CRITICAL`, `ignore-unfixed: true`, `exit-code: '1'`, chạy **trước** bước push | Image có lỗ hổng nghiêm trọng đã có bản vá thì không bao giờ lên registry | Bài 03, [Docker bài 07](../../04-DOCKER/07-docker-security.md) |
| Q9 | **PR không bao giờ push image**: bước login và push có `if: github.event_name == 'push'` | Xem mục 2 | Bài 03 |
| Q10 | **Release không bao giờ build lại**: `release.yml` không có `docker build`/`build-push-action` | Xem mục 2 | Bài 03, [bài 05](../../05-CICD/05-deployment-strategies-rollback.md) |
| Q11 | **Thời gian CI** 🟨 — mục tiêu: một lần chạy CI trên PR (cả hai job) dưới **8 phút** khi cache đã nóng. Ghi lại số đo thực tế vào README | Pipeline chậm → người ta bắt đầu "merge đại cho nhanh". Con số 8 phút là mục tiêu của dự án này, không phải chuẩn chung — đo, rồi giải thích chỗ nào tốn thời gian nhất | Bài 02, 03 |
| Q12 | `actions/checkout` dùng `persist-credentials: false` | Không để token nằm lại trong `.git/config` cho các bước sau đọc được | Bài 04 |

**Kiểm tra nhanh Q2, Q3, Q7** `[WSL]` trong repo `taskhub`:

```bash
grep -nE 'uses: ' .github/workflows/*.yml | grep -vE '@[0-9a-f]{40} # v'   # phải KHÔNG in ra dòng nào
grep -n 'ubuntu-latest' .github/workflows/*.yml                           # phải KHÔNG in ra dòng nào
grep -n 'latest' .github/workflows/*.yml                                  # chỉ được thấy latest=false
```

🟨 Kiểm tra cú pháp trước khi push bằng **actionlint** chạy trong container (cách chạy và ý nghĩa cảnh báo ở [bài 02](../../05-CICD/02-github-actions-basics.md)).

---

## 6. Thử nghiệm bắt buộc

Làm từng thử nghiệm, ghi **thao tác + kết quả quan sát (kèm link tới lần chạy workflow) + giải thích** vào `docs/experiments/v1-tests.md`.

| # | Thử nghiệm | Cách làm | Kết quả mong đợi — bạn phải giải thích được |
|---|---|---|---|
| T1 | **Test đỏ chặn merge** | Nhánh `feat/ci-red-test`: sửa một assertion trong `TaskControllerTest` cho sai (ví dụ mong `isOk()` thay vì `isCreated()`) → mở PR | Job `build-test` đỏ, job `image` **bị bỏ qua** (vì `needs`), nút merge bị chặn, artifact `test-reports` xuất hiện. Tìm đúng dòng lỗi trong log và trong file báo cáo surefire. Đóng PR, xóa nhánh |
| T2 | **Cache Maven: lần đầu vs lần sau** | So thời gian bước *Set up JDK 21* + *Build and test* ở lần chạy đầu tiên và lần chạy thứ hai (không đổi `pom.xml`). Sau đó thêm/bớt một dependency trong `pom.xml` rồi chạy lại | Lần đầu log báo không tìm thấy cache; lần sau báo khôi phục cache và build nhanh hơn. Đổi `pom.xml` → khóa cache đổi → tải lại. Giải thích: khóa cache được tính từ gì? (gợi ý: hash của `**/pom.xml` và `**/.mvn/wrapper/maven-wrapper.properties`) |
| T3 | **PostgreSQL service bị gỡ** | Nhánh nháp: xóa khối `services:` → mở PR | `build-test` đỏ với `Connection refused` ở test `contextLoads`. Nối với [tuần 6, mục 8.2](v-pre-week6-springboot-app.md#82-test-khởi-động-context--cần-database): vì sao test này cần database? Khôi phục lại, đóng PR |
| T4 | **Cổng Trivy hoạt động** | Nhánh nháp **không bao giờ merge**: tạm đổi `FROM` của stage runtime trong `docker/Dockerfile` sang một tag `eclipse-temurin:21-jre-...` **cũ** (tự chọn trên trang tags của Docker Hub, phát hành cách đây 1–2 năm) → mở PR | Job `image` đỏ ở bước Trivy, bảng liệt kê CVE CRITICAL kèm *Fixed Version*; bước push không chạy (đây là PR). Nếu vẫn xanh: tag bạn chọn chưa đủ cũ — ghi lại, chọn tag cũ hơn, **hoặc** tạm thêm `HIGH` vào `severity` và giải thích khác biệt. Không `docker run` image cũ đó. Đóng PR, xóa nhánh |
| T5 | **Tag trước khi CI xong (race)** | Merge một PR nhỏ vào `main`, **ngay lập tức** `git pull`, `git tag -a v0.3.0-rc.1 -m "test race"`, `git push origin v0.3.0-rc.1` | Workflow `Release` đỏ: *Không tìm thấy …:<sha7>* (CI chưa push xong). Chờ CI trên `main` xanh → vào lần chạy `Release` đỏ → **Re-run failed jobs** → xanh. Vì sao chạy lại được mà không cần tạo tag mới? (gợi ý: `GITHUB_SHA` của lần chạy). Sau thử nghiệm: xóa Release và tag `v0.3.0-rc.1` trên GitHub nếu không muốn giữ |
| T6 | **403 khi push package có từ tuần 8** | Chỉ xảy ra nếu ở [Docker bài 06](../../04-DOCKER/06-registry.md) bạn đã push `ghcr.io/<user>/taskhub` bằng PAT. Quan sát lần push đầu tiên từ CI trên `main` | Nếu đỏ với lỗi dạng `denied: permission_denied: write_package` (minh họa): package có từ trước **không** tự cấp quyền cho workflow. Sửa: Package settings → **Manage Actions access** → **Add repository** → `taskhub` → Role **Write** → Re-run. Nếu không lỗi: ghi lại vì sao (package được tạo bởi chính workflow, hoặc đã được liên kết và cấp quyền) |
| T7 | **Diễn tập rollback (khái niệm)** | 🟨 Thêm `image: ${TASKHUB_IMAGE:-taskhub:local}` vào service `taskhub` trong `compose.yaml` (giữ `build:`). Sau khi có `v0.3.0`: `TASKHUB_IMAGE=ghcr.io/<user>/taskhub:v0.3.0 docker compose up -d --no-build` → kiểm tra → đổi sang tag cũ hơn (`:v0.2.0` nếu bạn đã push tay ở tuần 8, hoặc một `:<sha7>` cũ hơn từ trang Packages) → `up -d --no-build` lại | Container `taskhub` được tạo lại với image khác, dữ liệu trong `pgdata` còn nguyên. Ghi lại thời gian từ lúc quyết định đến lúc API trả lời lại. Vì sao lần này rollback an toàn? (gợi ý: hai phiên bản dùng **cùng** schema Flyway V1). Khi nào rollback bằng image **không** đủ? → [bài 05](../../05-CICD/05-deployment-strategies-rollback.md) (migration không tương thích ngược) |
| T8 | **Xử lý PR của Dependabot** | Sau khi merge `dependabot.yml`, chờ (hoặc vào Insights → Dependency graph → Dependabot để kích hoạt kiểm tra) PR đầu tiên | Mở một PR Dependabot: nó đổi gì (với action đã ghim SHA: SHA **và** ghi chú phiên bản có cùng được cập nhật không — tự kiểm chứng)? Đọc release notes của bản mới. CI có chạy trên PR đó không? Merge hoặc đóng, **ghi lý do** |

---

## 7. Xử lý sự cố thường gặp

Cách đọc log workflow: Actions → chọn lần chạy → chọn job → mở bước đỏ, đọc **từ dưới lên** tìm dòng `Error`/`##[error]` đầu tiên có ý nghĩa ([bài 02](../../05-CICD/02-github-actions-basics.md)). Thông báo dưới đây là minh họa — chữ chính xác có thể khác, hãy tìm **ý chính** in đậm.

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra | Cách sửa |
|---|---|---|---|
| Workflow **không chạy** sau khi push | File không nằm đúng `.github/workflows/`; YAML sai cú pháp; trigger không khớp (nhánh tên khác `main`, tag không khớp `v*.*.*`) | Tab Actions có báo lỗi file không? actionlint | Sửa đường dẫn/cú pháp/trigger |
| `./mvnw: **Permission denied**` | Mất bit thực thi khi commit từ Windows | `git ls-files -s app/mvnw` (mode phải là `100755`) | `git update-index --chmod=+x app/mvnw`, commit |
| `**Connection refused**` ở `contextLoads` | Thiếu service container, sai port mapping, hoặc URL không phải `localhost:5432` | Khối `services:` và `env:` của job; log bước *Initialize containers* | Xem T3 |
| `Could not resolve placeholder '**SPRING_DATASOURCE_PASSWORD**'` | Thiếu biến trong `env:` của job | `env:` đặt ở cấp job hay nhầm vào một bước khác? | Đặt ở cấp job `build-test` |
| `upload-artifact`: **No files were found** | `working-directory: app` **không** áp dụng cho bước `uses:` | Đường dẫn `path:` | Dùng `app/target/surefire-reports/` |
| PR treo ở **Expected — Waiting for status to be reported** | Tên check trong branch protection không khớp tên job (đã đổi `name:`), hoặc workflow không chạy cho PR đó | So tên job với danh sách check bắt buộc | Sửa tên cho khớp hoặc cập nhật branch protection |
| Trivy đỏ trên PR **không đổi gì ở Dockerfile** | CVE mới được công bố cho base image, hoặc base image chưa được rebuild | Bảng Trivy: gói nào, *Fixed Version* là gì | Rebuild lấy base mới (cache có thể giữ base cũ — thử đổi tag base cụ thể hơn); nếu chưa có cách sửa và đã đánh giá rủi ro: `.trivyignore` **kèm lý do và ngày hết hạn** ([Docker bài 07](../../04-DOCKER/07-docker-security.md)) |
| `denied: **permission_denied: write_package**` | Package có từ trước, repo chưa được cấp quyền Write; hoặc thiếu `packages: write` trong job | Khối `permissions:` của job; Package settings | Xem T6 |
| `**invalid reference format: repository name must be lowercase**` | User GitHub có chữ hoa, script tự ghép tên image | Tên image trong log | `${GITHUB_REPOSITORY_OWNER,,}` hoặc để `metadata-action` sinh tên |
| Release: **Không tìm thấy …:<sha7>** | Tag commit chưa qua CI trên `main` (T5), hoặc tag một commit nằm trên nhánh khác | `git branch -a --contains vX.Y.Z` | Chờ CI xanh rồi Re-run; hoặc xóa tag, tag lại commit trên `main` |
| Release: **a release with the same tag name already exists** (minh họa) | Bạn đã tạo Release bằng tay cho tag này trên giao diện | Trang Releases | Xóa Release tạo tay rồi Re-run. Từ v0.3.0 **chỉ** để workflow tạo Release |
| Trang package hiện thêm mục `unknown/unknown` | Không phải lỗi: buildx đính kèm *attestation* (provenance) dạng một manifest phụ trong image index | `docker buildx imagetools inspect <image>:<tag>` | Không cần sửa. Hiểu vì sao image là *index* — cũng chính vì vậy `imagetools create` sao chép y hệt được |

Ghi mọi lỗi bạn gặp vào `troubleshooting-journal.md` theo [mẫu](../../00-ROADMAP/templates/troubleshooting-journal-template.md). Muốn luyện thêm: [Break-fix CI #1](../../05-CICD/labs/break-fix-01/README.md).

---

## 8. Câu hỏi tự kiểm

1. Vì sao `image` có `needs: build-test`? Nếu bỏ `needs`, hai job chạy thế nào và rủi ro là gì?
2. Trong một lần chạy do `pull_request` kích hoạt, `GITHUB_SHA` là commit nào? Vì sao điều đó quan trọng khi bạn so tag `:<sha7>` với `git log` trên nhánh của mình?
3. `GITHUB_TOKEN` ở job `image` có `packages: write` cả khi chạy cho PR. Điều gì ngăn PR push image? Với PR từ fork thì sao?
4. Ghim action bằng SHA bảo vệ bạn khỏi điều gì? Nó **không** bảo vệ khỏi điều gì? (gợi ý: action mà bạn ghim tự tải thứ khác lúc chạy)
5. Image `:v0.3.0` và `:<sha7>` của cùng commit có cùng digest không? Kiểm chứng bằng lệnh nào? Nếu release build lại thì sao?
6. Một CVE CRITICAL mới được công bố cho `eclipse-temurin:21-jre-noble` sáng nay. Chuyện gì xảy ra với các PR mở trong ngày? Bạn xử lý thế nào mà không tắt cổng Trivy?
7. Vì sao `cancel-in-progress` bật cho PR nhưng tắt cho `main`?
8. Vì sao badge dùng `?branch=main`?
9. T7: rollback bằng đổi tag image mất bao lâu? Liệt kê một tình huống mà cách này **không** cứu được.

---

## 9. Definition of Done và release v0.3.0

- [ ] `ci.yml`, `release.yml`, `dependabot.yml` nằm đúng chỗ; đạt đủ Q1–Q12; ba lệnh kiểm tra nhanh ở mục 5 không in ra gì sai.
- [ ] Branch protection của `main` bắt buộc `build-test` và `image`; một PR đỏ (T1) đã thực sự bị chặn merge.
- [ ] Trang Packages có `ghcr.io/<github-user>/taskhub:<sha7>` cho commit `main` gần nhất; package ở chế độ public; **không** có tag `latest`.
- [ ] Trong repo không có `docker build`/`docker push` chạy tay nào được mô tả như cách phát hành — README nói rõ con đường duy nhất là PR → CI → tag.
- [ ] Hoàn thành T1–T8 và ghi lại trong `docs/experiments/v1-tests.md` (có link tới các lần chạy workflow).
- [ ] README có badge CI (trỏ `main`) và mục **"CI/CD"**; thời gian CI thực tế được ghi lại (Q11).
- [ ] ADR-0003 đã merge (và ADR-0001, ADR-0002 nếu trước đó chưa có).
- [ ] Code vào `main` qua Pull Request (ví dụ nhánh `ci/github-actions` hoặc `feat/ci`), CI xanh.
- [ ] **Release `v0.3.0` do workflow `Release` tạo**, không tạo bằng tay: sau khi CI trên `main` xanh, `git tag -a v0.3.0 -m "v1: CI với GitHub Actions"` → `git push origin v0.3.0`. Kiểm tra: trang Releases có `v0.3.0` với ghi chú tự sinh; `docker buildx imagetools inspect ghcr.io/<github-user>/taskhub:v0.3.0` cho cùng digest với `:<sha7>` của commit đó. ⚠️ Nếu đã có Release `v0.3.0` tạo tay, xóa nó trước, nếu không bước `gh release create` sẽ đỏ.
- [ ] Ít nhất một lỗi gặp phải trong lúc làm đã được ghi vào nhật ký debug.
- [ ] Kiểm tra bản thân: [Checkpoint Module 05](../../05-CICD/checkpoint.md).

➡️ Tiếp theo: [**v2 — Triển khai thủ công lên AWS EC2**](v2-aws-ec2.md) (tuần 11–12): một EC2 trong VPC tự tạo sẽ `docker compose pull` chính image `:v0.3.0` này từ GHCR.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Adding a workflow status badge](https://docs.github.com/en/actions/how-tos/monitor-workflows/add-a-status-badge) | Định dạng URL badge, tham số `?branch=` | 2026-10-31 |
| [GitHub Docs — About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) | Required status checks, chế độ strict/loose | 2026-10-31 |
| [GitHub Docs — Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) | `GITHUB_TOKEN` với GHCR, package mặc định private, package có từ trước | 2026-10-31 |
| [GitHub Docs — Configuring a package's access control and visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility) | *Manage Actions access*, role Write | 2026-10-31 |
| [GitHub Docs — Keeping your actions up to date with Dependabot](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot) | Vị trí `.github/dependabot.yml`, `directory: "/"` cho workflow | 2026-10-31 |
| [GitHub Changelog — Ubuntu 26 GA và chuyển `ubuntu-latest`](https://github.blog/changelog/2026-09-17-ubuntu-26-generally-available-and-latest-migration) | Lý do ghim `ubuntu-24.04` (Q3) | 2026-10-31 |
| [docker/metadata-action](https://github.com/docker/metadata-action) | `type=sha` (7 ký tự, tiền tố `sha-` mặc định), `flavor: latest`, tự chuyển chữ thường | 2026-10-31 |
| [Docker Docs — `docker buildx imagetools create`](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/) | Nguồn là index → bản sao y hệt (*carbon copy*) | 2026-10-31 |
| [aquasecurity/trivy-action](https://github.com/aquasecurity/trivy-action) | Input `severity`, `ignore-unfixed`, `exit-code` | 2026-10-31 |
| [CVE-2026-33634 (CIRCL)](https://cve.circl.lu/cve/CVE-2026-33634) | Sự cố chuỗi cung ứng `trivy-action` tháng 3/2026 (lý do Q2) | 2026-10-31 |
