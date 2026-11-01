# 02. GitHub Actions cơ bản

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. CI/CD là gì](01-cicd-concepts.md), [Linux 06 — Bash scripting](../01-LINUX/06-bash-scripting.md), [Git 03 — Pull Request & bảo vệ nhánh](../03-GIT/03-github-pull-request-code-review.md), [Docker 05 — Compose](../04-DOCKER/05-docker-compose.md)
> Môi trường: `[WSL]` Ubuntu 24.04 · `[GitHub]` giao diện web · `[Runner]` máy ảo GitHub chạy workflow · Phiên bản khi viết: runner `ubuntu-24.04`, `actions/checkout@v7`, `actions/setup-java@v6`, `actions/upload-artifact@v7`, actionlint 1.7.12 (kiểm tra 2026-10-31)

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ luồng hoạt động](#6-sơ-đồ-luồng-hoạt-động)
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

- Giải thích được **workflow, event, job, step, runner** là gì và chúng liên hệ với nhau thế nào.
- Đọc và viết file workflow YAML mà không mắc các lỗi YAML phổ biến.
- Chọn đúng **event** (`push`, `pull_request`, `workflow_dispatch`, `schedule`), biết `GITHUB_SHA` của mỗi event trỏ tới commit nào.
- Dùng `needs`, `if`, step output, context và expression để điều khiển luồng chạy.
- Chạy test cần PostgreSQL bằng **service container**, tăng tốc bằng **cache Maven**, giữ lại báo cáo test bằng **artifact**.
- Tự tay viết job `build-test` của `taskhub` và giải thích được **từng dòng**.
- Đọc log của một lần chạy, tìm đúng bước lỗi, chạy lại có bật debug, kiểm tra workflow trên máy bằng **actionlint** trước khi push.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần |
|---|---|
| "PR này có làm hỏng gì không?" | Workflow chạy build + test tự động trên **mỗi PR** — con người không phải nhớ chạy `./mvnw verify` |
| Test cần database thật | Service container: PostgreSQL tạm, chết cùng job, không ảnh hưởng ai |
| Pipeline mất 8 phút, cả team chờ | Cache, concurrency, chia job hợp lý |
| Pipeline đỏ lúc 2 giờ sáng | Đọc log, tìm đúng step lỗi, phân biệt lỗi code với lỗi môi trường CI |
| Phỏng vấn: "Giải thích file workflow này" | Giải thích được event, job, runner, vì sao `localhost:5432` chạy được |

Trong công việc Junior DevOps, **viết và sửa pipeline** là việc hằng tuần. Người viết pipeline giỏi không phải người thuộc nhiều action, mà là người hiểu **workflow chạy ở đâu, với quyền gì, trên commit nào**.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. GitHub Actions là gì?

**GitHub Actions** là dịch vụ CI/CD tích hợp trong GitHub. Bạn viết file YAML trong repo. Khi một **sự kiện** xảy ra (push, mở PR…), GitHub cấp một **máy ảo** sạch, tải code của bạn xuống và chạy các lệnh trong file đó. Kết quả (xanh/đỏ) gắn vào commit và PR.

### 3.2. Năm khái niệm cốt lõi

| Khái niệm | Nghĩa tiếng Việt | Giải thích | Ví dụ trong `taskhub` |
|---|---|---|---|
| **Workflow** | Quy trình tự động | Một file YAML trong `.github/workflows/`. Một repo có thể có nhiều workflow | `ci.yml` (tên hiển thị `CI`), `release.yml` |
| **Event** | Sự kiện kích hoạt | Điều làm workflow chạy | `pull_request` vào `main`, `push` vào `main` |
| **Job** | Công việc | Nhóm step chạy trên **cùng một runner**. Các job mặc định chạy **song song**, trên các máy **khác nhau** | `build-test`, `image` |
| **Step** | Bước | Một lệnh shell (`run:`) hoặc một action dựng sẵn (`uses:`). Các step trong job chạy **tuần tự**, chung filesystem | Checkout → cài JDK → `./mvnw verify` |
| **Runner** | Máy chạy | Máy thực thi job. **GitHub-hosted runner** là VM mới tinh cho mỗi job, xóa sau khi xong | `ubuntu-24.04` |

Còn một khái niệm nữa: **Action** (hành động dựng sẵn) — một đoạn code đóng gói để tái sử dụng, gọi bằng `uses: owner/repo@phiên-bản`. Ví dụ `actions/checkout` tải code về runner. Action thực chất là **code của người khác chạy trong pipeline của bạn** — vì thế bài [04](04-secrets-environments.md) sẽ dạy cách ghim phiên bản an toàn.

### 3.3. Runner là một VM dùng một lần

Mỗi job nhận một VM Ubuntu **mới**. Hệ quả:

- Không có gì từ lần chạy trước còn lại: không file, không cache, không process. Muốn giữ gì phải dùng **cache** hoặc **artifact**.
- Hai job trong cùng workflow **không chung ổ đĩa**. Job `image` không thấy file `target/*.jar` do job `build-test` tạo.
- Bạn có `sudo` không cần mật khẩu, và Docker đã cài sẵn. Đây là lý do chạy được service container.
- Bạn đã gặp ý này ở [Docker 07](../04-DOCKER/07-docker-security.md): runner dùng một lần giảm rủi ro so với server build chạy mãi.

### 3.4. Ôn lại: nối với kiến thức cũ

| Kiến thức cũ | Gặp lại trong bài này |
|---|---|
| Exit code, `set -e`, `pipefail` ([Linux 06](../01-LINUX/06-bash-scripting.md)) | Step đỏ khi lệnh trả exit code ≠ 0; shell mặc định của step có `-e` nhưng **không** có `pipefail` |
| Biến môi trường, relaxed binding ([Docker 04](../04-DOCKER/04-volumes-networks-env.md)) | `SPRING_DATASOURCE_URL` khai báo trong `env:` của job |
| Healthcheck, `depends_on: service_healthy` ([Docker 05](../04-DOCKER/05-docker-compose.md)) | `--health-cmd` của service container — runner chờ PostgreSQL healthy rồi mới chạy step |
| Port publish, DNAT ([Docker 02](../04-DOCKER/02-images-containers.md)) | `ports: - 5432:5432` để job trên runner gọi `localhost:5432` |
| Detached HEAD, merge commit ([Git 01](../03-GIT/01-git-fundamentals-internals.md)) | `pull_request` checkout **merge commit** ở trạng thái detached HEAD |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 File workflow nằm ở đâu?

```text
taskhub/
└── .github/
    └── workflows/
        ├── ci.yml        ← GitHub chỉ đọc workflow trong đúng thư mục này
        └── release.yml   (bài 03)
```

- Đuôi `.yml` hoặc `.yaml` đều được. Sai thư mục (ví dụ `.github/workflow/` thiếu `s`) → **không có gì xảy ra, không báo lỗi**.
- Workflow cho sự kiện `pull_request` được đọc **từ chính commit đang được test** (merge commit của PR). Nghĩa là bạn sửa `ci.yml` trong nhánh PR thì PR đó chạy bản đã sửa — rất tiện để thử nghiệm.

### 4.2. 🟥 YAML — các bẫy hay gặp

GitHub Actions dùng YAML ([đã gặp ở Docker 05](../04-DOCKER/05-docker-compose.md)). Các bẫy:

| Bẫy | Ví dụ sai | Hậu quả | Cách đúng |
|---|---|---|---|
| Thụt lề bằng Tab | `⇥runs-on: ...` | YAML không hợp lệ | Chỉ dùng dấu cách (2 dấu cách mỗi cấp) |
| Thụt lề lệch | `steps:` thụt ít hơn `runs-on:` | Khóa bị gắn sai cấp, lỗi khó hiểu | Dùng VS Code + actionlint |
| Số bị hiểu sai | `python-version: 3.10` | YAML đọc thành số `3.1` | Bọc nháy: `'3.10'`. Với Java tập thói quen viết `'21'` |
| Khóa `on` | Đọc file bằng thư viện YAML 1.1 (PyYAML) thấy khóa `True:` | Không ảnh hưởng GitHub, chỉ gây bối rối khi bạn tự parse | Biết để không hoảng |
| Chuỗi chứa `: ` (hai chấm + dấu cách) hoặc bắt đầu bằng `*`, `&`, `{` | `run: echo "Tag: $TAG"` — dấu nháy kép nằm **giữa** giá trị nên không có tác dụng với YAML | Lỗi *mapping values are not allowed here* → GitHub báo *Invalid workflow file* | Dùng `run: \|` rồi viết lệnh ở dòng dưới (cách an toàn nhất), hoặc bọc **cả** giá trị trong nháy đơn |
| `\|` và `>` | `run: >` cho script nhiều dòng | `>` **gộp các dòng thành một** → script sai | Script dùng `\|` (giữ xuống dòng). `>-` chỉ hợp cho chuỗi tham số dài như `options:` |

### 4.3. 🟥 Cấu trúc tối thiểu của một workflow

```yaml
name: CI                      # tên hiển thị trong tab Actions

on:                           # event nào kích hoạt
  pull_request:
    branches: [main]

jobs:
  build-test:                 # ID của job (dùng trong needs:)
    name: build-test          # tên hiển thị = tên status check trên PR
    runs-on: ubuntu-24.04     # loại runner
    steps:
      - name: Checkout
        uses: actions/checkout@v7      # action dựng sẵn
      - name: Xem có gì
        run: ls -la                    # lệnh shell
```

**Thứ tự cấp:** `workflow` → `jobs` → `<job-id>` → `steps` → từng step. Mỗi step là một phần tử danh sách (dấu `-`).

### 4.4. 🟥 Event: khi nào workflow chạy và chạy trên commit nào?

| Event | Kích hoạt khi | `GITHUB_SHA` là | `GITHUB_REF` là |
|---|---|---|---|
| `push` | Push commit (hoặc tag) lên repo | Commit cuối cùng được push | `refs/heads/main` hoặc `refs/tags/v0.3.0` |
| `pull_request` | Mở PR, push thêm commit vào PR, mở lại PR | **Merge commit** do GitHub tạo thử: "nhánh PR + `main` hiện tại" | `refs/pull/<số PR>/merge` |
| `workflow_dispatch` | Bấm nút **Run workflow** (hoặc API) | Commit cuối của nhánh được chọn | Nhánh được chọn |
| `schedule` | Theo lịch cron (giờ UTC) | Commit cuối của **nhánh mặc định** | Nhánh mặc định |

**Điều quan trọng nhất của bảng:** với `pull_request`, CI test **kết quả sau khi merge**, không phải đầu nhánh của bạn. Nếu `main` vừa có commit mới xung đột ngầm với code của bạn, CI phát hiện được ngay trên PR. SHA của đầu nhánh PR nằm ở `github.event.pull_request.head.sha` — khác với `github.sha`. Bạn sẽ tự quan sát ở [mục 9](#9-bài-thực-hành-từng-bước).

Một số quy tắc đã kiểm chứng trên docs GitHub:

- `workflow_dispatch` chỉ hoạt động khi file workflow **đã có trên nhánh mặc định** — nút *Run workflow* chỉ hiện khi đó.
- `schedule` chỉ chạy trên nhánh mặc định, khoảng cách ngắn nhất 5 phút, có thể bị **trễ** lúc GitHub quá tải. Ở repo **public**, workflow định kỳ **tự bị tắt sau 60 ngày repo không có hoạt động**.
- Cron dùng giờ **UTC**: `0 1 * * *` là 08:00 giờ Việt Nam (UTC+7). Cú pháp cron đã học ở [Linux 08](../01-LINUX/08-cron-scheduling.md).

### 4.5. 🟥 Bộ lọc nhánh và đường dẫn

```yaml
on:
  pull_request:
    branches: [main]          # chỉ PR có nhánh ĐÍCH là main
  push:
    branches: [main]          # chỉ push vào main (không chạy khi push nhánh feat/*)
    # paths: ['app/**']       # 🟨 chỉ chạy khi có file trong app/ thay đổi
```

- `branches` của `pull_request` lọc theo **nhánh đích** (base), không phải nhánh nguồn.
- Không có `push: branches: [main]` thì mỗi lần bạn push nhánh `feat/*` đã có PR, workflow chạy **hai lần** (một cho `push`, một cho `pull_request`). Cấu hình của `taskhub` tránh điều này.

⚠️ **Bẫy `paths:` + required status check.** Giả sử bạn bắt buộc check `build-test` phải xanh mới merge, và workflow có `paths: ['app/**']`. Một PR chỉ sửa `README.md` → workflow **không chạy** → check `build-test` không bao giờ được báo cáo → PR kẹt ở trạng thái **"Waiting for status to be reported"**, không merge được. Docs GitHub khuyên **không** dùng bộ lọc `paths`/`branches` cho workflow đã được đặt làm required. Bạn sẽ tái hiện lỗi này trong [Lab 01](labs/lab-01-ci-pr-gate.md).

### 4.6. 🟥 Job, runner và `needs`

```yaml
jobs:
  build-test:
    runs-on: ubuntu-24.04
    steps: [...]
  image:
    needs: build-test         # chỉ bắt đầu khi build-test XANH
    runs-on: ubuntu-24.04
    steps: [...]
```

- Không có `needs` → các job chạy **song song**.
- `needs: build-test` → `image` chờ `build-test` thành công. `build-test` đỏ → `image` bị **skipped**.
- Mỗi job là một VM riêng. Muốn chuyển dữ liệu giữa job: **job output** (giá trị nhỏ) hoặc **artifact** (file).

**Vì sao `runs-on: ubuntu-24.04` mà không phải `ubuntu-latest`?** `ubuntu-latest` là **nhãn trôi**: GitHub đang chuyển nó từ Ubuntu 24.04 sang 26.04, dần dần trong khoảng 19/10–19/11/2026. Trong thời gian đó, hai lần chạy liên tiếp có thể rơi vào hai hệ điều hành khác nhau, công cụ cài sẵn khác nhau. Giống lý do không deploy image bằng tag `latest` ([Docker 06](../04-DOCKER/06-registry.md)): **ghim phiên bản để kết quả lặp lại được**, nâng cấp khi bạn chủ động chọn.

### 4.7. 🟥 Step: `run` và `uses`, và shell mặc định

```yaml
steps:
  - name: Checkout
    uses: actions/checkout@v7     # gọi action
    with:                         # tham số cho action
      persist-credentials: false
  - name: Build
    run: ./mvnw -B -ntp verify    # chạy lệnh shell
```

**Shell của bước `run:` trên runner Linux** (trích docs GitHub, kiểm tra 2026-10-31):

| Bạn viết | Lệnh thật GitHub chạy | Có `-e`? | Có `pipefail`? |
|---|---|---|---|
| Không ghi `shell:` | `bash -e {0}` | ✅ | ❌ |
| `shell: bash` | `bash --noprofile --norc -eo pipefail {0}` | ✅ | ✅ |
| `shell: sh` | `sh -e {0}` | ✅ | ❌ |

`{0}` là file script tạm chứa nội dung `run:`. Hệ quả — đây là phần xác minh đã hẹn ở [Linux 06](../01-LINUX/06-bash-scripting.md):

- Một lệnh lỗi giữa script → bước dừng ngay và đỏ (nhờ `-e`).
- Nhưng `false | true` khi **không** ghi `shell: bash` → exit code của pipe là của lệnh cuối (`true`) → bước **xanh**. Ví dụ nguy hiểm: `./mvnw verify | tee build.log` sẽ xanh dù test đỏ.
- Cách an toàn: ghi `shell: bash` (cho một step, hoặc cho cả job qua `defaults.run.shell`), hoặc viết `set -euo pipefail` ở đầu script dài.

### 4.8. 🟥 Context và expression

**Expression** là phần trong `${{ ... }}`, được GitHub tính **trước khi** gửi lệnh tới runner. **Context** là các object chứa thông tin về lần chạy.

| Context | Ví dụ | Giá trị minh họa |
|---|---|---|
| `github` | `github.event_name`, `github.ref`, `github.sha`, `github.actor`, `github.repository_owner` | `pull_request`, `refs/pull/12/merge`, `9f8e7d6...`, `phuong-dev` |
| `env` | `env.SPRING_DATASOURCE_URL` | biến khai báo trong `env:` |
| `secrets` | `secrets.GITHUB_TOKEN` | luôn bị che thành `***` trong log (bài 04) |
| `steps` | `steps.vars.outputs.short_sha` | output của step có `id: vars` |
| `needs` | `needs.build-test.result` | `success`, `failure`, `skipped` |
| `runner` | `runner.os`, `runner.debug` | `Linux` |
| `job` | `job.services.postgres.ports['5432']` | port host được gán |

Quy tắc cần nhớ:

- Chuỗi trong expression dùng **nháy đơn**: `github.ref == 'refs/heads/main'`. Nháy kép gây lỗi.
- `if:` có thể bỏ `${{ }}`: `if: github.event_name == 'push'`.
- Không phải context nào cũng dùng được ở mọi nơi. Ví dụ `env` **không** dùng được trong `runs-on` hay `jobs.<id>.if`. actionlint sẽ báo lỗi này.
- Mỗi step còn có sẵn **biến môi trường mặc định** như `GITHUB_SHA`, `GITHUB_REF`, `GITHUB_EVENT_NAME`, `GITHUB_REPOSITORY_OWNER`. Trong script, ưu tiên đọc biến môi trường (`"$GITHUB_SHA"`) thay vì nhúng `${{ github.sha }}` vào giữa lệnh. Lý do bảo mật (script injection) được giải thích ở bài [04](04-secrets-environments.md).

### 4.9. 🟥 `if` và các hàm trạng thái

Mặc định mỗi step có điều kiện ngầm `if: success()` — chỉ chạy khi mọi bước trước đều thành công.

| Điều kiện | Step chạy khi | Dùng cho |
|---|---|---|
| (không ghi) = `success()` | Mọi bước trước xanh | Hầu hết các bước |
| `failure()` | Có bước trước đỏ | Tải báo cáo test, gửi thông báo lỗi |
| `always()` | Luôn chạy, kể cả khi bị hủy | Hiếm khi cần. Docs khuyên dùng `!cancelled()` thay thế |
| `!cancelled()` | Mọi trường hợp trừ khi bị hủy | Dọn dẹp, thu log |
| `github.event_name == 'push'` | Event là push | Chỉ push image khi đã merge vào main (bài 03) |

⚠️ Biểu thức bắt đầu bằng `!` phải bọc: viết `if: ${{ !cancelled() }}`, không viết `if: !cancelled()`. Trong YAML, `!` ở đầu giá trị là cú pháp đặc biệt (tag), file sẽ bị đọc sai. Docs GitHub ghi rõ quy tắc này ở mục `jobs.<job_id>.if`.

🟨 Job bị bỏ qua do `if:` ở **cấp job** vẫn báo trạng thái *Success* cho required status check — khác với cả workflow bị bỏ qua do `paths:` (check chờ mãi, mục 4.5). Đây là chìa khóa cho bài tập 6 ở mục 14.

### 4.10. 🟨 Step output và job output

Step ghi giá trị vào file có đường dẫn trong biến `$GITHUB_OUTPUT`:

```yaml
jobs:
  produce:
    runs-on: ubuntu-24.04
    outputs:
      short_sha: ${{ steps.vars.outputs.short_sha }}   # đưa ra cấp job
    steps:
      - id: vars                                         # bắt buộc có id
        run: echo "short_sha=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
      - run: echo "Tag sẽ là ${{ steps.vars.outputs.short_sha }}"

  consume:
    needs: produce
    runs-on: ubuntu-24.04
    steps:
      - run: |
          echo "Nhận từ job trước: ${{ needs.produce.outputs.short_sha }}"
```

Vì sao bước cuối dùng `run: |`? Lệnh chứa `: ` (sau chữ "trước"). Viết trên một dòng không có nháy bao ngoài → YAML báo lỗi (bẫy cuối trong bảng ở [mục 4.2](#42--yaml--các-bẫy-hay-gặp)).

`${GITHUB_SHA::7}` là cú pháp cắt chuỗi của bash (lấy 7 ký tự đầu). Bài 03 dùng đúng kỹ thuật này để tạo tag image.

### 4.11. 🟥 Service container: PostgreSQL cho test

Nhắc lại vấn đề ở [tuần 6 §8.2](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md#82-test-khởi-động-context--cần-database): `TaskhubApplicationTests` (`@SpringBootTest`) khởi động toàn bộ ứng dụng, gồm Flyway và kết nối database. Không có PostgreSQL → test đỏ.

GitHub Actions có **service container**: container phụ chạy cạnh job, sống và chết cùng job.

```yaml
services:
  postgres:                          # nhãn của service
    image: postgres:17
    env:
      POSTGRES_DB: taskhub
      POSTGRES_USER: taskhub
      POSTGRES_PASSWORD: ci-only-password
    ports:
      - 5432:5432                    # host:container — giống docker run -p
    options: >-
      --health-cmd "pg_isready -U taskhub -d taskhub"
      --health-interval 5s
      --health-timeout 3s
      --health-retries 10
```

**Ứng dụng kết nối bằng host nào?** Đây là câu hỏi phỏng vấn hay gặp:

| Job chạy ở đâu | Kết nối tới | Cần `ports:`? | Vì sao |
|---|---|---|---|
| **Trực tiếp trên runner** (không có `container:` — trường hợp của `taskhub`) | `localhost:5432` | ✅ Có | Process Java chạy trên VM; port container được publish ra VM giống `docker run -p` |
| Trong một container (`jobs.<id>.container:`) | `postgres:5432` (tên nhãn service) | Không | Job container và service container cùng một Docker network; DNS nội bộ phân giải tên service — giống Compose |

Vì thế job `build-test` khai báo `SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/taskhub`. Ở [Docker 05](../04-DOCKER/05-docker-compose.md) bạn dùng `postgres:5432` vì app chạy trong container cùng network — cùng nguyên lý mạng, khác vị trí process.

**`options` là gì?** Tham số truyền thêm cho `docker create`. `--health-cmd` biến thành healthcheck; runner **chờ service healthy** rồi mới chạy step đầu tiên — tương đương `depends_on: condition: service_healthy` trong Compose. Thiếu healthcheck, Maven có thể kết nối khi PostgreSQL còn đang khởi tạo → lỗi lúc có lúc không (race condition).

**Mật khẩu ghi thẳng trong YAML có sao không?** Database này chỉ tồn tại vài phút trong một VM dùng một lần, không chứa dữ liệu thật, không ai từ Internet kết nối được. Nó không bảo vệ gì cả → không cần là secret. Mật khẩu của database **thật** luôn là secret (bài 04). Phân biệt được hai trường hợp này là dấu hiệu bạn hiểu secret là gì, chứ không chỉ học thuộc quy tắc.

### 4.12. 🟥 `env` và `defaults.run.working-directory`

```yaml
env:                                 # biến cho mọi step của job
  SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/taskhub
  SPRING_DATASOURCE_USERNAME: taskhub
  SPRING_DATASOURCE_PASSWORD: ci-only-password

defaults:
  run:
    working-directory: app           # mọi bước run: chạy trong app/
```

`env:` đặt được ở 3 cấp: workflow, job, step. Cấp hẹp hơn ghi đè cấp rộng hơn.

⚠️ `working-directory` của `defaults.run` **chỉ áp dụng cho bước `run:`**, không áp dụng cho bước `uses:`. Action như `upload-artifact` vẫn tính đường dẫn **từ gốc repo** (`$GITHUB_WORKSPACE`). Vì vậy:

```yaml
- run: ./mvnw -B -ntp verify                 # chạy trong app/
- uses: actions/upload-artifact@v7
  with:
    path: app/target/surefire-reports/       # PHẢI có app/ ở đầu
```

Viết `path: target/surefire-reports/` → action cảnh báo *No files were found with the provided path* và không tải lên gì.

### 4.13. 🟥 Cache Maven với `setup-java`

Lần đầu `./mvnw verify` tải hàng trăm thư viện vào `~/.m2/repository` (vài phút). Runner bị xóa sau job → lần sau tải lại từ đầu. **Cache** lưu thư mục này lên GitHub và khôi phục ở lần chạy sau.

```yaml
- uses: actions/setup-java@v6
  with:
    distribution: temurin
    java-version: '21'
    cache: maven
```

`cache: maven` tạo **khóa cache** từ hash của `**/pom.xml`, `**/.mvn/wrapper/maven-wrapper.properties` và `**/.mvn/extensions.xml` (theo README của `setup-java`). Hệ quả:

- `pom.xml` không đổi → cùng khóa → **cache hit**, không tải lại.
- Thêm một dependency → hash đổi → cache miss lần đầu, lưu cache mới ở cuối job.
- Glob `**/` nên tìm được `app/pom.xml` dù project nằm trong `app/`.
- `setup-java` phải chạy **sau** `checkout`: chưa checkout thì chưa có `pom.xml` để tính hash → lỗi.
- 🟨 **Phạm vi cache:** một lần chạy chỉ khôi phục được cache của **nhánh hiện tại** hoặc **nhánh mặc định** (`main`); lần chạy của PR dùng thêm được cache của nhánh đích. Cache tạo trong PR **không** dùng được cho `main` → lần chạy đầu trên `main` sau khi merge vẫn có thể là cache miss. Cache không được dùng quá 7 ngày bị GitHub xóa.

**Cache khác artifact thế nào?**

| | Cache | Artifact |
|---|---|---|
| Mục đích | Tăng tốc lần chạy **sau** | Giữ **kết quả** của lần chạy này (báo cáo, file build) |
| Có thể mất bất cứ lúc nào? | Có — mất cache chỉ làm chậm, không làm sai | Không — giữ tới hết thời hạn |
| Người xem | Không ai tải về xem | Tải về từ trang lần chạy |
| Ví dụ | `~/.m2/repository` | `surefire-reports/`, file `.jar` |

### 4.14. 🟥 Artifact: giữ báo cáo test khi đỏ

```yaml
- name: Upload test reports
  if: failure()
  uses: actions/upload-artifact@v7
  with:
    name: test-reports
    path: app/target/surefire-reports/
    retention-days: 7
```

- Maven Surefire ghi kết quả từng test class vào `target/surefire-reports/` (file `.txt` dễ đọc và `.xml`).
- `if: failure()`: chỉ tải lên khi có bước đỏ — lúc xanh không cần, đỡ tốn dung lượng.
- `retention-days: 7`: mặc định GitHub giữ artifact và log **90 ngày** (repo public chỉnh được trong khoảng 1–90 ngày). Báo cáo test cũ không có giá trị lâu, 7 ngày là đủ.

### 4.15. 🟨 Concurrency và timeout

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

- Các lần chạy cùng `group` không chạy đồng thời. `cancel-in-progress: true` → lần chạy mới **hủy** lần cũ đang dở.
- Với PR: bạn push 3 commit liên tiếp → chỉ commit cuối đáng test → hủy các lần cũ, tiết kiệm thời gian.
- Với `main`: **không** hủy, vì mỗi commit trên `main` cần một image riêng (bài 03).
- `timeout-minutes: 15`: mặc định một job được chạy tới **360 phút**. Một test treo (chờ database mãi) sẽ giữ runner 6 tiếng. Đặt giới hạn sát với thời gian thật × 2–3.

### 4.16. 🟨 Matrix — chạy một job với nhiều cấu hình

```yaml
build-test:
  strategy:
    matrix:
      java: ['21', '25']
  runs-on: ubuntu-24.04
  steps:
    - uses: actions/setup-java@v6
      with:
        distribution: temurin
        java-version: ${{ matrix.java }}
```

GitHub tạo **2 job** song song, tên dạng `build-test (21)`, `build-test (25)`. Dùng khi thư viện cần hỗ trợ nhiều phiên bản. `taskhub` là ứng dụng chạy trên đúng một JRE (21 trong image) nên **không** dùng matrix — biết để đọc hiểu workflow của người khác. Chú ý: tên check đổi thành `build-test (21)` → required status check phải chọn lại.

### 4.17. 🟥 Dựng job `build-test` của `taskhub` từng bước

Đây là con đường bạn sẽ tự đi trong [Lab 01](labs/lab-01-ci-pr-gate.md). Mỗi phiên bản thêm một thứ và **giải quyết đúng một lỗi** của phiên bản trước.

**Phiên bản 1 — chỉ build.**

```yaml
name: CI
on:
  pull_request:
    branches: [main]
jobs:
  build-test:
    name: build-test
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v6
        with:
          distribution: temurin
          java-version: '21'
      - run: cd app && ./mvnw -B -ntp verify
```

Kết quả: **đỏ**. `TaskControllerTest` xanh, nhưng `TaskhubApplicationTests` lỗi vì `application.yml` có `password: ${SPRING_DATASOURCE_PASSWORD}` không có giá trị mặc định ([tuần 6 §5.2](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md#52-applicationyml)) → `Could not resolve placeholder 'SPRING_DATASOURCE_PASSWORD'`. Đặt biến rồi vẫn đỏ với `Connection refused` vì không có PostgreSQL.

**Phiên bản 2 — thêm PostgreSQL và biến môi trường.** Thêm khối `services:` (mục 4.11) và `env:` (mục 4.12). Kết quả: **xanh**, nhưng mất vài phút tải thư viện mỗi lần.

**Phiên bản 3 — tăng tốc và dễ debug.** Thêm `cache: maven`, `defaults.run.working-directory`, `timeout-minutes`, bước upload báo cáo khi đỏ.

**Phiên bản 4 — chạy cả trên `main`, an toàn hơn.** Thêm `push: branches: [main]`, `concurrency`, `permissions: contents: read`, `persist-credentials: false`. Hai dòng cuối được giải thích kỹ ở bài [04](04-secrets-environments.md); tóm tắt: token của workflow chỉ được đọc code, và không bị lưu lại trong `.git/config` sau bước checkout.

**Kết quả cuối** — job `build-test` hoàn chỉnh, khớp với [bản tham khảo](labs/reference/workflows/ci.yml) (bản tham khảo ghim action bằng SHA; bài 04 dạy cách làm):

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  build-test:
    name: build-test
    runs-on: ubuntu-24.04
    timeout-minutes: 15

    services:
      postgres:
        image: postgres:17
        env:
          POSTGRES_DB: taskhub
          POSTGRES_USER: taskhub
          POSTGRES_PASSWORD: ci-only-password
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U taskhub -d taskhub"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10

    env:
      SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/taskhub
      SPRING_DATASOURCE_USERNAME: taskhub
      SPRING_DATASOURCE_PASSWORD: ci-only-password

    defaults:
      run:
        working-directory: app

    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          persist-credentials: false

      - name: Set up JDK 21
        uses: actions/setup-java@v6
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Build and test
        run: ./mvnw -B -ntp verify

      - name: Upload test reports
        if: failure()
        uses: actions/upload-artifact@v7
        with:
          name: test-reports
          path: app/target/surefire-reports/
          retention-days: 7
```

Job thứ hai (`image`) được thêm ở bài [03](03-github-actions-docker-registry.md).

### 4.18. 🟨 Kiểm tra workflow trên máy trước khi push: actionlint

Mỗi lần sửa YAML rồi push lên mới biết sai thì rất chậm. **actionlint** là công cụ kiểm tra tĩnh (static checker) cho file workflow: lỗi cú pháp YAML, khóa không tồn tại, `needs` trỏ tới job không có, context sai chỗ, lỗi shell (tích hợp ShellCheck — công cụ bạn đã dùng ở [Linux 06](../01-LINUX/06-bash-scripting.md)).

Không cần cài: chạy bằng image Docker chính thức, **ghim phiên bản** thay vì `latest` (tag `1.7.12` có trên Docker Hub, kiểm tra 2026-10-31):

```bash
docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:1.7.12 -color
```

### 4.19. 🟦 Chạy workflow trên máy bằng `act`

[`act`](https://github.com/nektos/act) chạy workflow trên máy bằng Docker, mô phỏng môi trường của GitHub. Tiện cho workflow dài, nhưng môi trường không giống runner thật 100% (image khác, không có một số dịch vụ của GitHub). Giáo trình không dùng `act`: push lên nhánh PR là cách kiểm tra chính xác nhất và miễn phí với repo public.

### 4.20. Gặp lại ở đâu

| Kiến thức bài này | Gặp lại ở |
|---|---|
| Job `build-test`, `needs` | Job `image` build + quét + push image (bài 03) |
| `secrets`, `permissions`, script injection | Bài 04 |
| `push: tags`, `github.ref_name` | Workflow `Release` (bài 03) |
| `if: github.event_name == 'push'` | Chỉ push image sau khi merge (bài 03) |
| Service container | Test tích hợp với database ở mọi dự án Java/Spring |
| `workflow_dispatch`, `schedule` | Deploy thủ công lên EC2, quét lỗ hổng định kỳ (v3, Module 10) |
| Đọc log, chạy lại có debug | Mọi pipeline bạn sẽ gặp khi đi làm |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Pipeline xanh nhưng test đỏ

Một team có bước:

```yaml
- run: ./mvnw verify | tee build.log
```

Test đỏ suốt 2 tuần mà pipeline vẫn xanh. Nguyên nhân: không ghi `shell:` → shell là `bash -e`, **không** có `pipefail` → exit code của pipe là exit code của `tee` (luôn 0). Sửa: thêm `shell: bash` (có `-o pipefail`), hoặc bỏ `| tee` và dùng artifact để giữ log.

### Ví dụ 2: PR không merge được dù chẳng có gì sai

Một developer sửa lỗi chính tả trong `README.md`. PR kẹt: *build-test — Waiting for status to be reported*. Workflow có `paths: ['app/**']`, còn `build-test` là required check. Workflow không chạy nên check không bao giờ được báo cáo. Sửa: bỏ `paths:` khỏi workflow required (chấp nhận chạy thêm vài phút), hoặc thiết kế lại (xem bài tập ở mục 14).

### Ví dụ 3: "Trên máy em chạy được"

Test truy vấn có `ORDER BY` thiếu cột phụ, trên máy dev luôn ra đúng thứ tự, trên CI thỉnh thoảng sai. Runner là môi trường **sạch và khác máy bạn** (dữ liệu, timezone, locale, tốc độ). CI đỏ kiểu này không phải "CI bị lỗi" — nó đang tìm ra giả định ngầm trong code. Ghi vào nhật ký debug và sửa code.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Từ `git push` đến dấu ✅ trên PR

```text
[WSL] git push origin ci/add-build-workflow
        │
        ▼
[GitHub] PR #12 (base: main) ── event pull_request ──► đọc .github/workflows/ci.yml
        │                                               từ merge commit refs/pull/12/merge
        ▼
[GitHub] Xếp job vào hàng đợi ──► cấp VM ubuntu-24.04 mới
        │
        ▼
[Runner] Set up job          (in phiên bản image, quyền GITHUB_TOKEN)
         Initialize containers  (docker pull postgres:17, chờ healthy)
         Checkout            (merge commit, detached HEAD)
         Set up JDK 21       (khôi phục cache ~/.m2 nếu khớp khóa)
         Build and test      (./mvnw -B -ntp verify ──JDBC──► localhost:5432 ──► service postgres)
         Upload test reports (chỉ khi có bước đỏ)
         Post Set up JDK 21  (lưu cache nếu là cache miss)
         Stop containers · Complete job
        │ exit code của từng bước
        ▼
[GitHub] Check "build-test" = ✅ / ❌ gắn vào commit ──► PR: nút Merge mở / khóa (nếu là required check)
        │
        ▼
VM bị xóa — không còn gì
```

### 6.2. Mạng của service container khi job chạy trên runner

```text
┌──────────────────── VM runner (ubuntu-24.04) ─────────────────────┐
│                                                                   │
│  java (Maven test) ──► localhost:5432                             │
│                           │ port publish (DNAT) 5432 → 5432       │
│                           ▼                                       │
│              ┌── Docker network do runner tạo ──┐                 │
│              │  container "postgres" :5432      │                 │
│              └──────────────────────────────────┘                 │
└───────────────────────────────────────────────────────────────────┘
Nếu job chạy TRONG container (jobs.<id>.container), job container cũng nằm
trong network đó → gọi thẳng postgres:5432, không cần ports:.
```

---

## 7. Các câu lệnh cần biết

| Lệnh / cú pháp | Chạy ở | Mục đích |
|---|---|---|
| `mkdir -p .github/workflows` | `[WSL]` | Tạo đúng thư mục workflow |
| `docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:1.7.12 -color` | `[WSL]` | Kiểm tra workflow trước khi push |
| `git ls-files -s app/mvnw` | `[WSL]` | Xem quyền thực thi của `mvnw` trong Git |
| `git update-index --chmod=+x app/mvnw` | `[WSL]` | Ghi quyền thực thi vào Git (sửa lỗi `Permission denied` trên runner) |
| `./mvnw -B -ntp verify` | `[Runner]` / `[WSL]` | Build + test như CI |
| `echo "key=value" >> "$GITHUB_OUTPUT"` | `[Runner]` | Tạo step output |
| `echo "## Tiêu đề" >> "$GITHUB_STEP_SUMMARY"` | `[Runner]` | Ghi Markdown vào trang tóm tắt của lần chạy |
| `echo "::error file=app/pom.xml,line=1::Thông báo"` | `[Runner]` | Tạo annotation lỗi hiển thị trên PR |
| `echo "::group::Tên"` … `echo "::endgroup::"` | `[Runner]` | Gộp log thành khối thu gọn được |
| Actions → chọn lần chạy → **Re-run jobs** → ☑ **Enable debug logging** | `[GitHub]` | Chạy lại với log chi tiết |

---

## 8. Giải thích câu lệnh và tham số

### `./mvnw -B -ntp verify`

```bash
cd ~/projects/taskhub/app
./mvnw -B -ntp verify
```

| Phần | Ý nghĩa | Vì sao dùng trong CI |
|---|---|---|
| `./mvnw` | Maven Wrapper — tải đúng phiên bản Maven ghi trong `.mvn/wrapper/maven-wrapper.properties` | Runner và máy bạn dùng **cùng** phiên bản Maven |
| `-B` (`--batch-mode`) | Không hỏi tương tác, không in màu | CI không có người gõ phím; log sạch |
| `-ntp` (`--no-transfer-progress`) | Không in tiến trình tải từng file | Log ngắn hơn hàng nghìn dòng, dễ tìm lỗi |
| `verify` | compile → test → package → các bước kiểm tra sau package | Một lệnh kiểm tra đầy đủ — đúng lệnh đã thống nhất từ [tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md) |

Đầu ra cuối khi xanh (minh họa, rút gọn):

```text
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
[INFO] Total time:  41.512 s
```

### `git ls-files -s` và `git update-index --chmod=+x`

```bash
git ls-files -s app/mvnw
```

```text
100755 3f2a9c... 0	app/mvnw          ← 100755 = có quyền thực thi (minh họa)
100644 3f2a9c... 0	app/mvnw          ← 100644 = KHÔNG có → runner báo Permission denied
```

| Phần | Ý nghĩa |
|---|---|
| `ls-files -s` | Liệt kê file trong index kèm **mode** (quyền), hash blob, stage |
| `100755` / `100644` | Git chỉ lưu đúng hai mode cho file thường: có/không có quyền thực thi |
| `update-index --chmod=+x` | Đổi mode trong index thành `100755` mà không cần `chmod` trên đĩa (hữu ích khi làm từ Windows) |

Trên WSL, bạn `chmod +x` thì `git status` cũng thấy thay đổi mode. Nhưng nếu file từng được commit từ Windows, mode có thể là `100644` dù trên máy bạn vẫn chạy được.

### actionlint qua Docker

```bash
cd ~/projects/taskhub
docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:1.7.12 -color
```

| Phần | Ý nghĩa |
|---|---|
| `--rm` | Xóa container sau khi chạy xong |
| `-v "$(pwd)":/repo` | Bind mount thư mục repo hiện tại vào `/repo` trong container. Dấu nháy để đường dẫn có dấu cách không vỡ |
| `--workdir /repo` | Chạy actionlint từ gốc repo → nó tự tìm `.github/workflows/` |
| `rhysd/actionlint:1.7.12` | Image ghim phiên bản (không dùng `latest`) |
| `-color` | Tô màu đầu ra |

Không in gì và exit code 0 = không tìm thấy lỗi. Có lỗi (minh họa):

```text
.github/workflows/ci.yml:30:3: job "image" needs job "biuld-test" which does not exist in this workflow [job-needs]
   |
30 |   image:
   |   ^~~~~~
```

Đọc: `file:dòng:cột: mô tả [tên luật]`. Tên luật trong ngoặc vuông dùng để tra tài liệu actionlint. Với lỗi `[job-needs]`, actionlint chỉ vào **tên job** đang khai báo `needs`, không chỉ vào dòng `needs:` (đã kiểm chứng với 1.7.12).

> ⚠️ actionlint 1.7.12 (03/2026) ra đời trước khi GitHub phát hành `ubuntu-26.04`, nên nó báo `label "ubuntu-26.04" is unknown [runner-label]` dù nhãn đó có thật. Đây là **báo động giả** do danh sách nhãn của công cụ đã cũ — kiểm tra lại bảng nhãn trong tài liệu GitHub, hoặc dùng bản actionlint mới hơn. Dự án taskhub ghim `ubuntu-24.04` nên không gặp.

### Lệnh workflow (workflow commands)

```bash
echo "::error file=app/src/main/resources/application.yml,line=12::Thiếu biến SPRING_DATASOURCE_PASSWORD"
echo "::warning::Cache miss — lần chạy này sẽ chậm"
echo "::group::Thông tin môi trường"
java -version
echo "::endgroup::"
```

| Lệnh | Tác dụng |
|---|---|
| `::error file=...,line=...::msg` | Tạo **annotation** đỏ; trên PR hiện ngay tại file/dòng đó trong tab *Files changed* |
| `::warning::msg` / `::notice::msg` | Annotation vàng / xanh |
| `::group::` / `::endgroup::` | Gộp đoạn log thành khối thu gọn |
| `::add-mask::giá-trị` | Thay giá trị bằng `***` trong log từ đó trở đi (bài 04) |

---

## 9. Bài thực hành từng bước

> Bài thực hành này dùng một repo **thử nghiệm** để bạn thoải mái làm hỏng. Workflow thật của `taskhub` được viết ở [Lab 01](labs/lab-01-ci-pr-gate.md).

### Bước 1 — Tạo repo thử nghiệm `[GitHub]` `[WSL]`

1. Trên GitHub tạo repo **public** `actions-playground`, tick *Add a README file*. Repo public → phút chạy runner chuẩn miễn phí.
2. Clone về:

```bash
mkdir -p ~/devops-lab/05-cicd && cd ~/devops-lab/05-cicd
git clone git@github.com:<github-user>/actions-playground.git
cd actions-playground
mkdir -p .github/workflows
```

### Bước 2 — Thí nghiệm shell: `-e` và `pipefail` `[WSL]`

Tạo `.github/workflows/shell.yml`:

```yaml
name: Shell experiment

on:
  push:
  workflow_dispatch:

jobs:
  shell:
    runs-on: ubuntu-24.04
    steps:
      - name: A — shell mặc định, lệnh lỗi giữa script
        continue-on-error: true
        run: |
          echo "A: trước"
          false
          echo "A: sau — dòng này có in không?"

      - name: B — shell mặc định, lỗi nằm trong pipe
        run: |
          set -o | grep -E 'errexit|pipefail'
          false | true
          echo "B: pipe có lệnh lỗi nhưng bước vẫn chạy tiếp"

      - name: C — shell bash tường minh
        continue-on-error: true
        shell: bash
        run: |
          set -o | grep -E 'errexit|pipefail'
          false | true
          echo "C: dòng này có in không?"
```

`continue-on-error: true` để bước đỏ không làm dừng job — bạn xem được cả ba bước trong một lần chạy.

```bash
git add .github/workflows/shell.yml
git commit -m "ci: add shell experiment"
git push
```

Mở tab **Actions** → lần chạy *Shell experiment* → job `shell`. Trước khi xem, **viết dự đoán** cho A, B, C vào nhật ký. Sau đó mở từng bước, chú ý dòng đầu của mỗi bước có dạng `shell: /usr/bin/bash -e {0}` (minh họa).

### Bước 3 — Thí nghiệm event và SHA `[WSL]` `[GitHub]`

Tạo `.github/workflows/context.yml`:

```yaml
name: Context experiment

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  show:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - name: Event và commit
        env:
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
        run: |
          echo "event      = $GITHUB_EVENT_NAME"
          echo "ref        = $GITHUB_REF"
          echo "GITHUB_SHA = $GITHUB_SHA"
          echo "PR head    = ${HEAD_SHA:-<không phải PR>}"
          echo "HEAD local = $(git rev-parse HEAD)"
          git log --oneline -3
```

Commit, push lên `main`, xem kết quả. Sau đó:

```bash
git switch -c feat/try-pr
echo "thử PR" >> README.md
git commit -am "docs: try pull request event"
git push -u origin feat/try-pr
```

Mở PR `feat/try-pr` → `main`. So sánh log của lần chạy `pull_request` với lần chạy `push`:

- `GITHUB_REF` là gì?
- `GITHUB_SHA` có bằng `PR head` không? `git log` cho thấy commit trên cùng là commit gì?

Cuối cùng, vào **Actions → Context experiment → Run workflow** để thử `workflow_dispatch`.

### Bước 4 — Thí nghiệm `needs`, output, `if` `[WSL]`

Tạo `.github/workflows/flow.yml`:

```yaml
name: Flow experiment

on:
  push:
  workflow_dispatch:

jobs:
  produce:
    runs-on: ubuntu-24.04
    outputs:
      short_sha: ${{ steps.vars.outputs.short_sha }}
    steps:
      - id: vars
        run: echo "short_sha=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

  consume:
    needs: produce
    runs-on: ubuntu-24.04
    steps:
      - run: echo "Tag image sẽ là :${{ needs.produce.outputs.short_sha }}"

      - name: Chỉ khi push vào main
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        run: echo "Đây là main"

      - name: Bước cố ý lỗi
        run: exit 3

      - name: Chạy khi có lỗi
        if: failure()
        run: echo "Thu log, gửi thông báo..."

      - name: Bước bình thường sau lỗi
        run: echo "Dòng này có chạy không?"
```

Push lên `main`, rồi push lên nhánh `feat/try-pr`. Quan sát: bước nào chạy, bước nào **skipped**, exit code nào được in ở bước lỗi.

### Bước 5 — Thí nghiệm concurrency `[WSL]`

Tạo `.github/workflows/slow.yml`:

```yaml
name: Slow experiment

on:
  push:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  slow:
    runs-on: ubuntu-24.04
    timeout-minutes: 2
    steps:
      - run: sleep 60 && echo "xong"
```

Push, rồi trong vòng 30 giây tạo thêm một commit và push tiếp:

```bash
git commit --allow-empty -m "chore: trigger again" && git push
```

Quan sát lần chạy thứ nhất bị **Canceled**. Sau đó đổi `sleep 60` thành `sleep 180` và push: job bị hủy sau 2 phút vì `timeout-minutes`. Đọc thông báo ở cuối log.

### Bước 6 — actionlint bắt lỗi trước khi push `[WSL]`

> Cần Docker Desktop đang chạy.

Cố ý làm hỏng `flow.yml`: đổi `needs: produce` thành `needs: prodcue`, và `github.event_name` thành `github.evnet_name`. **Chưa push.** Chạy:

```bash
cd ~/devops-lab/05-cicd/actions-playground
docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:1.7.12 -color
echo "exit code: $?"
```

Đọc từng lỗi, sửa, chạy lại tới khi không còn lỗi.

### Bước 7 — Đọc log có debug `[GitHub]`

Vào lần chạy *Flow experiment* bị đỏ → **Re-run jobs** → **Re-run failed jobs** → tick **Enable debug logging**. So sánh log mới (các dòng `##[debug]`) với log cũ.

### Bước 8 — Dọn dẹp

- Đóng PR `feat/try-pr` (không merge), xóa nhánh trên GitHub.
- Xóa `slow.yml` (để không chạy mỗi lần push): `git rm .github/workflows/slow.yml && git commit -m "chore: remove slow experiment" && git push`.
- Giữ repo `actions-playground` để thử nghiệm cho các bài sau, hoặc xóa trong **Settings → Danger Zone**.

---

## 10. Kết quả mong đợi

| Thí nghiệm | Bạn phải thấy (và giải thích được) |
|---|---|
| Shell A | In "A: trước", **không** in dòng "sau" → bước đỏ (exit 1) nhưng job tiếp tục nhờ `continue-on-error` |
| Shell B | `errexit on`, `pipefail off`; in dòng "B: ..." → bước **xanh** dù có `false` |
| Shell C | `errexit on`, `pipefail on`; **không** in dòng "C: ..." → bước đỏ |
| Context — push | `ref = refs/heads/main`, `GITHUB_SHA` = commit bạn vừa push |
| Context — PR | `ref = refs/pull/<số>/merge`; `GITHUB_SHA` **khác** `PR head`; `git log` trên cùng là commit *Merge ... into ...* |
| Flow | `consume` in tag 7 ký tự; trên nhánh feat bước "Chỉ khi push vào main" bị skipped; bước "Chạy khi có lỗi" chạy; bước "bình thường sau lỗi" skipped; job đỏ với `exit code 3` |
| Concurrency | Lần chạy đầu *Canceled*; job `sleep 180` bị hủy với thông báo vượt thời gian tối đa |
| actionlint | Hai lỗi có số dòng/cột; sau khi sửa: không in gì, exit code 0 |
| Debug log | Xuất hiện thêm nhiều dòng `##[debug]` |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| Push xong không thấy workflow nào chạy | File không nằm trong `.github/workflows/`; bộ lọc `branches` không khớp (ví dụ ghi `master`); repo tắt Actions | Kiểm tra đường dẫn và tên nhánh; **Settings → Actions → General** |
| Tab Actions hiện *Invalid workflow file* kèm số dòng | YAML sai (Tab, thụt lề lệch, khóa sai) | Đọc dòng được chỉ ra; chạy actionlint |
| `./mvnw: Permission denied` (exit code 126) | `mvnw` có mode `100644` trong Git | `git update-index --chmod=+x app/mvnw`, commit |
| `./mvnw: No such file or directory` | Quên `working-directory: app` hoặc `cd app` | Thêm `defaults.run.working-directory: app` |
| `Could not resolve placeholder 'SPRING_DATASOURCE_PASSWORD'` | Thiếu `env:` của job | Khai báo 3 biến `SPRING_DATASOURCE_*` |
| `Connection to localhost:5432 refused` | Thiếu `ports: - 5432:5432`, hoặc dùng host `postgres` khi job chạy trên runner | Thêm `ports`; dùng `localhost` |
| `password authentication failed for user "taskhub"` | `POSTGRES_PASSWORD` của service khác `SPRING_DATASOURCE_PASSWORD` | Hai giá trị phải giống nhau |
| `setup-java` báo không tìm thấy file nào khớp `**/pom.xml` | `setup-java` chạy **trước** `checkout` | Đặt `checkout` lên đầu |
| *No files were found with the provided path* ở bước upload | `path:` viết theo `working-directory` | Đường dẫn của bước `uses:` tính từ gốc repo: `app/target/...` |
| Pipeline xanh dù test đỏ | Lệnh dạng `cmd \| tee` không có `pipefail` | `shell: bash` hoặc bỏ pipe |
| PR kẹt *Waiting for status to be reported* | Workflow required có `paths`/`branches` filter nên không chạy; hoặc tên job đổi (ví dụ thêm matrix) | Bỏ filter; chọn lại tên check trong branch protection |
| Expression lỗi *got unexpected character '"'* | Dùng nháy kép trong `${{ }}` | Dùng nháy đơn |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Cấu trúc trang một lần chạy

```text
Actions → CI → lần chạy "#7 ci: add build-test workflow"
├── Summary          ← sơ đồ job, annotations, artifacts, job summary
└── Jobs
    └── build-test
        ├── Set up job               ← image runner (ubuntu-24.04, phiên bản), quyền GITHUB_TOKEN
        ├── Initialize containers    ← pull postgres:17, chờ health
        ├── Checkout
        ├── Set up JDK 21            ← "Cache restored" hay "Cache not found"
        ├── Build and test           ← log Maven
        ├── Upload test reports      ← skipped khi xanh
        ├── Post Set up JDK 21       ← "Cache saved" khi là cache miss
        ├── Stop containers
        └── Complete job
```

### 12.2. Quy trình khi pipeline đỏ

1. **Bước nào đỏ?** Mở job → tìm bước có dấu ❌. Đừng đọc từ dòng đầu của log.
2. **Dòng nào báo lỗi?** Trong bước đó, tìm dòng `Error: Process completed with exit code N` ở cuối, rồi đọc **ngược lên**.
3. **Lỗi code hay lỗi môi trường?**
   - `[ERROR] Tests run: ..., Failures: 1` → lỗi code/test. Chạy lại trên máy để tái hiện.
   - `Connection refused`, `Permission denied`, `No such file` → lỗi môi trường/cấu hình workflow.
   - `Unable to resolve action`, lỗi mạng khi tải dependency → có thể lỗi tạm thời. Chạy lại **một** lần; lỗi lặp lại thì không phải tạm thời.
4. **Tái hiện trên máy** với cùng lệnh (`./mvnw -B -ntp verify`) và cùng biến môi trường.
5. Vẫn chưa rõ → **Re-run failed jobs** + **Enable debug logging**. Lưu ý: chạy lại dùng **đúng `GITHUB_SHA` và `GITHUB_REF` cũ** (không lấy code mới), và chỉ chạy lại được trong 30 ngày.
6. Muốn bật debug lâu dài cho repo: tạo **variable** (hoặc secret) `ACTIONS_STEP_DEBUG=true` (log chi tiết của step) hoặc `ACTIONS_RUNNER_DEBUG=true` (log chẩn đoán của runner) trong **Settings → Secrets and variables → Actions**. Nhớ xóa khi xong.

### 12.3. Đọc log Maven khi test đỏ (minh họa)

```text
[ERROR] Tests run: 3, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 2.1 s <<< FAILURE! -- in com.taskhub.TaskControllerTest
[ERROR] com.taskhub.TaskControllerTest.createValidTaskReturns201WithLocation -- Time elapsed: 0.3 s <<< FAILURE!
java.lang.AssertionError: Status expected:<200> but was:<201>
...
[ERROR] Failures:
[ERROR]   TaskControllerTest.createValidTaskReturns201WithLocation:58 Status expected:<200> but was:<201>
[ERROR] Tests run: 4, Failures: 1, Errors: 0, Skipped: 0
[INFO] BUILD FAILURE
Error: Process completed with exit code 1.
```

| Dòng | Đọc ra |
|---|---|
| `Failures: 1` vs `Errors: 1` | *Failure* = assert sai (test chạy, kết quả khác mong đợi). *Error* = test ném exception (thường do môi trường: không kết nối được DB, thiếu cấu hình) |
| `TaskControllerTest...:58` | Class, tên test, **dòng 58** trong file test |
| `expected:<200> but was:<201>` | Test mong 200, code trả 201 — xem lại test hay code sai |
| `exit code 1` | Maven trả 1 → shell `-e` dừng → bước đỏ → job đỏ |

Với `Errors`, mở artifact `test-reports` → file `com.taskhub.TaskhubApplicationTests.txt` chứa stack trace đầy đủ; đọc theo cách ở [Linux 07 — Đọc stack trace Java](../01-LINUX/07-logs-monitoring-troubleshooting.md#43--đọc-stack-trace-java): tìm dòng `Caused by:` **cuối cùng**.

### 12.4. Log service container (minh họa)

```text
Initialize containers
  ...
  /usr/bin/docker create --name 3c1f..._postgres17_a1b2 --label ... --network github_network_... --network-alias postgres -p 5432:5432 --health-cmd "pg_isready -U taskhub -d taskhub" ... postgres:17
  ...
  postgres service is healthy.
```

Thấy `--network-alias postgres`: đó là lý do job **chạy trong container** gọi được `postgres:5432`. Thấy `-p 5432:5432`: đó là lý do job **trên runner** gọi được `localhost:5432`. Không thấy dòng `is healthy` mà job vẫn chờ rồi lỗi → healthcheck sai (sai tên user/database trong `pg_isready`).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Workflow, job, step, runner khác nhau thế nào? Hai job trong cùng workflow có chung ổ đĩa không? Hai step trong cùng job thì sao?
2. Với event `pull_request`, `GITHUB_SHA` trỏ tới commit nào? Vì sao GitHub test commit đó thay vì đầu nhánh PR?
3. Vì sao cấu hình `taskhub` có `push: branches: [main]` thay vì chỉ `push:`?
4. Giải thích vì sao `paths:` trên một workflow required có thể khiến PR không merge được.
5. Không ghi `shell:`, bước `run: ./mvnw verify | tee log.txt` xanh hay đỏ khi test lỗi? Vì sao? Sửa thế nào?
6. Vì sao job `build-test` kết nối `localhost:5432` mà không phải `postgres:5432`? Khi nào thì dùng `postgres:5432`?
7. `--health-cmd` trong `options` của service container giải quyết vấn đề gì? Tương đương với gì trong Docker Compose?
8. Vì sao `path:` của bước upload artifact phải bắt đầu bằng `app/` dù đã có `defaults.run.working-directory: app`?
9. `cache: maven` tạo khóa cache từ những file nào? Thêm một dependency vào `pom.xml` thì lần chạy sau chuyện gì xảy ra?
10. Cache và artifact khác nhau thế nào? Cho mỗi loại một ví dụ trong `taskhub`.
11. `if: failure()`, `if: always()`, `if: !cancelled()` khác nhau thế nào? Mặc định một step có điều kiện gì?
12. Vì sao dùng `runs-on: ubuntu-24.04` thay vì `ubuntu-latest`? Đánh đổi là gì?
13. Mật khẩu PostgreSQL trong `ci.yml` ghi thẳng trong file. Vì sao chấp nhận được ở đây nhưng không chấp nhận được với database production?
14. "Re-run failed jobs" chạy trên code nào: commit cũ hay commit mới nhất của nhánh?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/02-solutions.md](solutions/02-solutions.md) — chỉ mở sau khi đã tự làm.

1. **Matrix.** Trong `actions-playground`, viết job chạy `java -version` với matrix Java `21` và `25` (Temurin). Ghi lại tên hai job hiển thị trên GitHub. Nếu đây là required check, bạn phải chọn tên nào trong branch protection?
2. **workflow_dispatch có input.** Viết workflow có nút *Run workflow* với input `environment` kiểu lựa chọn (`dev`, `staging`) và input `dry_run` kiểu boolean. Step in ra hai giá trị. Tự tra docs mục `on.workflow_dispatch.inputs`.
3. **Tìm 5 lỗi.** Không chạy, chỉ đọc và tìm lỗi trong đoạn sau; sau đó kiểm chứng bằng actionlint:

   ```yaml
   name: CI
   on:
     pull_request:
       branches: [master]
   jobs:
     build-test:
       runs-on: ubuntu-24.04
       env:
         SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/taskhub
       steps:
         - uses: actions/setup-java@v6
           with:
             distribution: temurin
             java-version: '21'
             cache: maven
         - uses: actions/checkout@v7
         - run: ./mvnw -B -ntp verify | tee build.log
           working-directory: app
     image:
       needs: build_test
       runs-on: ubuntu-24.04
       steps:
         - run: echo "build image"
   ```

4. **Đo hiệu quả cache.** Trong Lab 01, ghi lại thời gian bước *Build and test* ở lần chạy đầu (cache miss) và lần thứ hai (cache hit). Tính phần trăm tiết kiệm. Tìm trong log dòng chứng minh cache được khôi phục/lưu.
5. **Job summary.** Thêm vào workflow `taskhub` (trên một nhánh thử) một bước luôn chạy (trừ khi bị hủy) để ghi vào `$GITHUB_STEP_SUMMARY` một bảng Markdown: số test chạy, số lỗi (gợi ý: đọc từ các file `TEST-*.xml` trong `app/target/surefire-reports/` bằng `grep`). Không merge nếu chưa hài lòng.
6. **Thiết kế.** Một repo có `app/` (Java) và `docs/` (Markdown). Team muốn: sửa `docs/` không phải chờ build Java 5 phút, nhưng `build-test` vẫn là required check. Đề xuất **hai** cách thiết kế không gây kẹt PR, nêu ưu nhược điểm. (Gợi ý: điều kiện ở cấp step/job thay vì `paths:` ở cấp workflow; hoặc một job "tổng hợp" luôn chạy.)

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đạt bài này khi, **không nhìn tài liệu**:

- [ ] Viết lại được job `build-test` của `taskhub` và giải thích từng dòng.
- [ ] Giải thích được `GITHUB_SHA` của `push` và `pull_request` khác nhau thế nào, và đã tự quan sát điều đó.
- [ ] Dự đoán đúng kết quả của ba bước shell A/B/C trước khi chạy, và giải thích bằng `-e`/`pipefail`.
- [ ] Giải thích được `localhost:5432` và `postgres:5432` — khi nào dùng cái nào, vì sao.
- [ ] Phân biệt cache và artifact, biết khóa cache Maven được tính từ đâu.
- [ ] Gặp một lần chạy đỏ, tìm ra bước lỗi và nguyên nhân trong ≤ 10 phút bằng quy trình ở mục 12.2.
- [ ] Chạy actionlint trên máy và đọc hiểu được thông báo lỗi.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) | Cấu trúc file, shell mặc định (`bash -e {0}`, `bash --noprofile --norc -eo pipefail {0}`), `defaults.run`, `concurrency`, `timeout-minutes` (mặc định 360), `services` | 2026-10-31 |
| [GitHub Docs — Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) | `GITHUB_SHA`/`GITHUB_REF` của `pull_request`; `schedule` (nhánh mặc định, có thể trễ, tắt sau 60 ngày ở repo public); `workflow_dispatch` | 2026-10-31 |
| [GitHub Docs — Contexts](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts) | Context `github`, `runner`, `job`; giới hạn context theo từng khóa | 2026-10-31 |
| [GitHub Docs — Expressions](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions) | `success()`, `failure()`, `always()`, `cancelled()`; nháy đơn | 2026-10-31 |
| [GitHub Docs — Workflow commands](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands) | `::error`, `::group`, `::add-mask`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY` | 2026-10-31 |
| [GitHub Docs — Creating PostgreSQL service containers](https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers) | `localhost` khi job trên runner, tên service khi job trong container, healthcheck | 2026-10-31 |
| [GitHub Docs — Storing and sharing data from a workflow](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-what-your-workflow-does/storing-and-sharing-data-from-a-workflow) | Artifact, `retention-days` | 2026-10-31 |
| [GitHub Docs — Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository) | Artifact/log giữ mặc định 90 ngày (repo public: 1–90 ngày) | 2026-10-31 |
| [GitHub Docs — Re-running workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs) | Re-run dùng cùng `GITHUB_SHA`/`GITHUB_REF`, trong 30 ngày, tùy chọn debug | 2026-10-31 |
| [GitHub Docs — Enabling debug logging](https://docs.github.com/en/actions/how-tos/monitor-workflows/enable-debug-logging) | `ACTIONS_STEP_DEBUG`, `ACTIONS_RUNNER_DEBUG` | 2026-10-31 |
| [GitHub Docs — Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks) | Workflow bị bỏ qua do filter → check ở trạng thái chờ, chặn merge | 2026-10-31 |
| [GitHub Changelog — Ubuntu 26 GA và chuyển `ubuntu-latest`](https://github.blog/changelog/2026-09-17-ubuntu-26-generally-available-and-latest-migration) | `ubuntu-latest` chuyển sang 26.04 từ 19/10 đến 19/11/2026; khuyên ghim `ubuntu-24.04` nếu chưa sẵn sàng | 2026-10-31 |
| [actions/setup-java (README)](https://github.com/actions/setup-java) | `cache: maven`, các file dùng để tính khóa cache | 2026-10-31 |
| [GitHub Docs — Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) | Phạm vi truy cập cache theo nhánh, xóa sau 7 ngày không dùng, giới hạn 10 GB | 2026-10-31 |
| [actions/upload-artifact — Releases](https://github.com/actions/upload-artifact/releases) | Phiên bản v7 | 2026-10-31 |
| [actionlint — Usage](https://github.com/rhysd/actionlint/blob/main/docs/usage.md) · [Docker Hub tags](https://hub.docker.com/r/rhysd/actionlint/tags) | Cách chạy bằng Docker; tag `1.7.12` | 2026-10-31 |
| [nektos/act](https://github.com/nektos/act) | Chạy workflow trên máy (nhận biết) | 2026-10-31 |
