# Lời giải — Bài 04: Secrets, quyền và môi trường triển khai

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; username `phuong-dev` là ví dụ.

Quay lại bài: [04-secrets-environments.md](../04-secrets-environments.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Secret, variable, `GITHUB_TOKEN`?**

| | Secret | Variable | `GITHUB_TOKEN` |
|---|---|---|---|
| Tạo ở đâu | Bạn tạo (Settings → Secrets and variables → Actions, hoặc trong environment) | Bạn tạo (cùng trang, tab Variables) | GitHub **tự tạo** đầu mỗi job |
| Che trong log | Có (so khớp chuỗi) | Không | Có |
| Sống bao lâu | Tới khi bạn xóa/đổi | Tới khi bạn xóa/đổi | **Hết hạn khi job kết thúc** (tối đa 6 giờ trên runner hosted) |

**2. `DB_PASSWORD` ở cả repo và environment?**
Job có `environment: production` nhận giá trị **của environment** (cấp thấp hơn thắng). Job không khai báo environment nhận giá trị **cấp repo** — nó không bao giờ thấy secret của environment.

**3. Masking hoạt động thế nào? Hai cách vẫn lộ?**
Runner thay **đúng chuỗi** giá trị secret bằng `***` trước khi ghi log. Lộ khi: (1) in giá trị **đã biến đổi** — `rev`, `base64`, cắt một phần chuỗi, mã hóa URL; (2) secret là dữ liệu có cấu trúc (JSON nhiều dòng) và in từng phần; (3) quan trọng nhất: code độc hại **gửi thẳng secret qua mạng** — masking chỉ áp dụng cho log.

**4. Vì sao không viết `if: secrets.API_TOKEN != ''`?**
GitHub không cho tham chiếu `secrets` trực tiếp trong `if:`. Cách làm: gán vào `env` cấp job (`env: API_TOKEN: ${{ secrets.API_TOKEN }}`) rồi `if: env.API_TOKEN != ''` ở bước; hoặc kiểm tra trong script (`[[ -z "$API_TOKEN" ]]`).

**5. Job chỉ có `permissions: packages: write`?**
Mọi quyền không ghi ra thành `none`, kể cả `contents`. `actions/checkout` không đọc được repo → bước checkout lỗi (repo private chắc chắn lỗi; đừng dựa vào việc repo public "có thể vẫn đọc được"). Phải ghi thêm `contents: read`.

**6. PR từ fork chạy `on: pull_request`?**
Có: code của PR, `GITHUB_TOKEN` **chỉ đọc**. Không có: mọi secret khác, quyền ghi. Người đóng góp lần đầu còn có thể phải chờ chủ repo duyệt. An toàn vì dù người lạ sửa workflow hay `pom.xml` để chạy lệnh tùy ý, lệnh đó không có gì để đánh cắp và không ghi được gì vào repo/registry.

**7. `pull_request_target` + checkout `head.sha` + `./mvnw verify`?**
`pull_request_target` chạy trong ngữ cảnh nhánh đích: **có secret, token có quyền ghi**. Checkout `head.sha` lấy **code của người lạ**; `./mvnw verify` chạy plugin Maven, test, script trong code đó → người lạ chạy được lệnh tùy ý với secret và token ghi của bạn = chiếm repo. (Từ `actions/checkout` v7.0.0, bước checkout này bị chặn với PR từ fork — nhưng đừng dựa vào đó; viết đúng từ đầu.)

**8. Viết lại `run: echo "Branch: ${{ github.head_ref }}"`**

```yaml
- env:
    HEAD_REF: ${{ github.head_ref }}
  run: |
    echo "Branch: $HEAD_REF"
```

(Lệnh chứa `: ` nên phải dùng `run: |` — viết trên một dòng là lỗi cú pháp YAML; xem bẫy YAML ở bài 02.)

Bản cũ: GitHub dán tên nhánh vào **mã nguồn** script trước khi bash chạy → tên nhánh chứa `"; lệnh; "` trở thành lệnh. Bản mới: tên nhánh nằm trong **biến môi trường**, bash chỉ coi là dữ liệu.

**9. `@0.34.2` và SHA commit của bản đó trong sự cố Trivy?**
`@0.34.2` là tag → bị force-push sang commit độc hại → lần chạy sau ngày 19/3/2026 tải mã độc. SHA commit cũ vẫn trỏ tới đúng code sạch → code **của action** không đổi. Không tuyệt đối: advisory liệt kê cả SHA pin tới commit cũ (trước 2025-04-09) trong phạm vi ảnh hưởng; nguyên tắc chung là SHA chỉ khóa code của chính action, những gì nó tải/gọi theo tag hoặc "latest" vẫn có thể bị đổi. Vì vậy cần thêm quyền tối thiểu và secret chỉ ở job cần.

**10. `git ls-remote` trả hai dòng?**
Tag đó là annotated tag. Dòng `refs/tags/X` là SHA **đối tượng tag**; dòng `refs/tags/X^{}` là SHA **commit** tag trỏ tới. Ghim bằng SHA **commit** (dòng `^{}`) — đó là thứ runner checkout và thứ Dependabot so sánh.

**11. Dependabot với action đã ghim?**
Với `package-ecosystem: github-actions`, `directory: /`, Dependabot đọc các dòng `uses:`, so với bản phát hành mới nhất, mở PR thay SHA mới. Ghi chú phiên bản (`# v7.0.1`) được cập nhật theo **khi nằm cùng dòng** với `uses:`.

**12. Environment với required reviewers cho repo một người? Điều kiện gói?**
Tạo một nhịp dừng có chủ đích trước khi chạm production; job không thể tự chạy dù ai đó (hoặc một workflow bị chiếm) kích hoạt nó; secret production chỉ vào job đã được duyệt; có bản ghi ai duyệt lúc nào. Trên GitHub Free: required reviewers, wait timer, environment secrets chỉ có cho **repo public** (`taskhub` public nên dùng được).

**13. Vì sao không có `AWS_SECRET_ACCESS_KEY`?**
v3 dùng **OIDC**: job xin GitHub một JWT ngắn hạn mô tả repo/nhánh/environment; AWS kiểm tra JWT theo điều kiện của IAM role rồi cấp credential **tạm thời cho một job**. Không có key dài hạn nào để lộ. Quyền cần: `id-token: write` (kèm `contents: read` để checkout).

**14. `persist-credentials: false` chống gì?**
Mặc định `actions/checkout` ghi token vào `.git/config` → mọi bước sau (action bên thứ ba, plugin Maven, script) đọc được token từ file. Tắt đi thì token không nằm lại trên đĩa sau bước checkout. `taskhub` không `git push` từ CI nên không mất gì.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Rà soát workflow lạ

Vấn đề, xếp theo mức độ nghiêm trọng:

| # | Vấn đề | Mức | Vì sao |
|---|---|---|---|
| 1 | `pull_request_target` + checkout `head.sha` + chạy `./scripts/lint.sh` (script **từ PR**) | 🔴 Nghiêm trọng | Người lạ sửa `lint.sh` → chạy lệnh tùy ý với secret và token ghi |
| 2 | `permissions: write-all` | 🔴 | Token bị đánh cắp làm được mọi thứ trên repo |
| 3 | Script injection: `${{ github.event.pull_request.title }}` trong `run:` | 🔴 | Tiêu đề PR thành lệnh — kể cả khi không checkout code PR |
| 4 | `echo "${{ secrets.SLACK_WEBHOOK }}" \| base64` | 🔴 | Lộ secret trong log (base64 không bị che), repo public ai cũng đọc |
| 5 | `some-user/fancy-lint@main` | 🟠 Cao | Action bên thứ ba theo **nhánh** — mỗi lần chạy là một code khác, chủ action đẩy gì bạn chạy nấy |
| 6 | `${{ secrets.SLACK_WEBHOOK }}` dán thẳng vào lệnh `curl` | 🟡 | Nên qua `env` + `"$VAR"`; giá trị có ký tự đặc biệt sẽ phá lệnh |
| 7 | `actions/checkout@v4` theo tag, không `persist-credentials: false` | 🟡 | Không ghim SHA; token nằm lại trong `.git/config` |
| 8 | `runs-on: ubuntu-latest`, không `timeout-minutes` | ⚪ Thấp | Môi trường đổi bất ngờ; job treo chạy tới 6 giờ |

Bản an toàn — tách làm hai: kiểm tra PR **không có gì để mất**, và thông báo Slack chỉ chạy trên code đã vào `main`:

```yaml
name: PR helper

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # Thay some-user/fancy-lint@main bằng: đọc code action, ghim SHA đã đọc (hoặc bỏ hẳn)
      - name: Lint
        env:
          PR_TITLE: ${{ github.event.pull_request.title }}
        run: |
          echo "Checking PR: ${PR_TITLE:-<push vào main>}"
          ./scripts/lint.sh

  notify:
    needs: check
    if: github.event_name == 'push'
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions: {}
    steps:
      - name: Thông báo Slack
        env:
          SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
        run: curl -fsS -X POST -d "main ok" "$SLACK_WEBHOOK"
```

Điểm chính: `pull_request` (fork không có secret), quyền `contents: read`, injection qua `env`, secret chỉ ở job `notify` chạy trên `main`, không in secret, ghim SHA. Và việc cần làm ngay vì bản cũ đã từng chạy: **xoay vòng `SLACK_WEBHOOK`** (đã lộ qua base64 trong log).

### Bài 2 — Kiểm tra secret sớm

```yaml
- name: Kiểm tra secret bắt buộc
  env:
    REGISTRY_USER: ${{ secrets.REGISTRY_USER }}
    REGISTRY_PASSWORD: ${{ secrets.REGISTRY_PASSWORD }}
    NOTIFY_URL: ${{ secrets.NOTIFY_URL }}
  run: |
    missing=0
    for name in REGISTRY_USER REGISTRY_PASSWORD NOTIFY_URL; do
      if [[ -z "${!name:-}" ]]; then
        echo "::error::Thiếu secret ${name} (chưa tạo, sai tên, hoặc job thiếu environment:)"
        missing=1
      fi
    done
    exit "$missing"
```

- `${!name}` là **indirect expansion**: lấy giá trị của biến có tên nằm trong `name`.
- Chỉ in **tên**, không bao giờ in giá trị.
- Kiểm tra hết rồi mới thoát → một lần chạy thấy mọi secret thiếu, không phải sửa từng cái.

### Bài 3 — Script ghim SHA

```bash
#!/usr/bin/env bash
# In "owner/repo@<sha-commit> # <tag>" cho một tag của GitHub Action.
set -euo pipefail

repo="${1:?Cách dùng: $0 <owner/repo> <tag>}"
tag="${2:?Cách dùng: $0 <owner/repo> <tag>}"

# Repo không tồn tại → git sẽ hỏi username/password; tắt prompt để lỗi ngay
out="$(GIT_TERMINAL_PROMPT=0 git ls-remote "https://github.com/${repo}" \
        "refs/tags/${tag}" "refs/tags/${tag}^{}")" || {
  echo "Không truy cập được https://github.com/${repo}" >&2
  exit 1
}

if [[ -z "$out" ]]; then
  echo "Không tìm thấy tag '${tag}' trong ${repo}" >&2
  exit 1
fi

# Annotated tag: dùng dòng ^{} (SHA commit). Lightweight tag: chỉ có một dòng.
sha="$(awk -v peeled="refs/tags/${tag}^{}" '$2 == peeled { print $1 }' <<<"$out")"
if [[ -z "$sha" ]]; then
  sha="$(awk -v ref="refs/tags/${tag}" '$2 == ref { print $1 }' <<<"$out")"
fi

echo "${repo}@${sha} # ${tag}"
```

```text
$ scripts/action-sha.sh actions/checkout v7.0.1
actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
$ scripts/action-sha.sh aquasecurity/trivy-action v0.36.0
aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
$ scripts/action-sha.sh actions/checkout 7.0.1
Không tìm thấy tag '7.0.1' trong actions/checkout
```

Vì sao so khớp chính xác bằng `awk '$2 == ...'` mà không `head -1`: `ls-remote` so khớp mẫu theo **phần đuôi** ref, và thứ tự dòng không phải là thứ bạn nên dựa vào. So khớp chính xác tên ref là cách chắc chắn.

### Bài 4 — Bảng quyền

```yaml
# (a) actionlint: chỉ cần đọc code
permissions:
  contents: read

# (b) build + push GHCR
permissions:
  contents: read      # checkout
  packages: write     # push image

# (c) tạo GitHub Release
permissions:
  contents: write     # release gắn với tag, thuộc phạm vi contents

# (d) deploy AWS qua OIDC
permissions:
  contents: read      # checkout (compose file, script deploy)
  id-token: write     # xin JWT OIDC để đổi lấy credential AWS tạm thời
```

Không job nào cần `write-all`. Với (a), nếu job không checkout (ví dụ chỉ gọi một API công khai) thì `permissions: {}`.

### Bài 5 — Kế hoạch ứng phó (mẫu)

```markdown
# Kế hoạch: docker/login-action bị chiếm quyền (tag bị dời 6 giờ đêm qua)

## 1. Mình có dùng không, dùng thế nào?
- grep -n 'docker/login-action' .github/workflows/*.yml
- Dòng uses: ghim SHA hay tag? SHA đó có nằm trong danh sách độc hại của advisory không?

## 2. Có lần chạy nào trong khoảng thời gian bị tấn công?
- Tab Actions: lọc workflow CI (job image) và Release (job promote) trong 6 giờ đó.
- Mở "Set up job" từng lần chạy: dòng `Download action repository 'docker/login-action@...' (SHA:...)`
  cho biết CHÍNH XÁC commit đã chạy → so với SHA độc hại.

## 3. Nếu bị ảnh hưởng — credential nào có thể lộ?
- GITHUB_TOKEN của job đó: đã hết hạn khi job kết thúc, quyền contents:read + packages:write
  → kiểm tra GHCR có tag lạ/bị ghi đè không (so digest với log CI), xóa image lạ.
- Secret repo: CI không dùng secret nào → không có gì để xoay vòng.
- Không có PAT, không có AWS key (v3 dùng OIDC).

## 4. Vì sao danh sách ngắn
- Job image không có secret repo; job build-test không có quyền ghi; token sống theo job;
  persist-credentials: false; không có credential dài hạn trong pipeline.

## 5. Ngăn tái diễn
- Ghim SHA (nếu chưa), merge PR Dependabot sau khi đọc release notes, cân nhắc bật
  "Require actions to be pinned to a full-length commit SHA".
```
