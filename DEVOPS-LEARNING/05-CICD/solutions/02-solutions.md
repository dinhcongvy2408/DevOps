# Lời giải — Bài 02: GitHub Actions cơ bản

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; username `phuong-dev` là ví dụ.

Quay lại bài: [02-github-actions-basics.md](../02-github-actions-basics.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Workflow, job, step, runner?**
Workflow là một file YAML trong `.github/workflows/`, được kích hoạt bởi event. Workflow gồm các job; mỗi job chạy trên một runner (VM mới) và gồm các step chạy tuần tự. Hai job **không** chung ổ đĩa (hai VM khác nhau) — muốn chuyển dữ liệu phải dùng job output hoặc artifact. Hai step trong cùng job **chung** filesystem và chung VM, nên step sau thấy file step trước tạo (ví dụ `app/target/`).

**2. `GITHUB_SHA` của `pull_request`?**
Merge commit mà GitHub tạo thử giữa đầu nhánh PR và `main` hiện tại (`refs/pull/N/merge`). Lý do: thứ sẽ vào `main` là **kết quả merge**, không phải nhánh đứng riêng. Nếu `main` có thay đổi mới làm code của bạn hỏng (dù không có conflict dòng), CI trên merge commit phát hiện ngay. SHA đầu nhánh nằm ở `github.event.pull_request.head.sha`.

**3. Vì sao `push: branches: [main]`?**
Không có bộ lọc, mỗi lần push nhánh `feat/*` đã có PR thì workflow chạy hai lần (event `push` của nhánh + event `pull_request`) — tốn thời gian và gây nhiễu. Giới hạn `push` vào `main` giữ đúng hai trường hợp cần: kiểm tra PR trước khi merge và chạy lại trên `main` sau khi merge (để có kết quả và, từ bài 03, image cho đúng commit của `main`).

**4. `paths:` + required check?**
Workflow có `paths: ['app/**']` không chạy khi PR không sửa file nào trong `app/`. Không chạy → check `build-test` không bao giờ được báo cáo → branch protection chờ check đó mãi (*Waiting for status to be reported*) → không merge được. Docs GitHub khuyên không dùng `paths`/`branches` filter cho workflow được đặt làm required.

**5. `./mvnw verify | tee log.txt` khi test lỗi?**
**Xanh.** Không ghi `shell:` → `bash -e {0}`, không có `pipefail` → exit code của pipe là của lệnh cuối (`tee`, luôn 0) → `-e` không kích hoạt → bước xanh. Sửa: thêm `shell: bash` (GitHub chạy `bash --noprofile --norc -eo pipefail {0}`), hoặc `set -o pipefail` đầu script, hoặc bỏ `| tee` và giữ log bằng artifact.

**6. `localhost:5432` hay `postgres:5432`?**
Job `build-test` không có `container:` nên process Java chạy thẳng trên VM runner. VM không nằm trong Docker network của service, nên không phân giải được tên `postgres`; nó với tới container qua port đã publish (`ports: - 5432:5432`) trên `localhost`. Khi job chạy trong container (`jobs.<id>.container`), job container và service container cùng network do runner tạo → dùng tên nhãn service `postgres:5432`, không cần `ports:` — giống Compose.

**7. `--health-cmd`?**
Biến `pg_isready` thành healthcheck của container; runner chờ service **healthy** rồi mới chạy step đầu tiên. Không có nó, Maven có thể kết nối khi PostgreSQL còn đang khởi tạo → lỗi lúc có lúc không (race condition). Tương đương `healthcheck:` + `depends_on: condition: service_healthy` trong Compose.

**8. Vì sao `path: app/...` ở bước upload?**
`defaults.run.working-directory` chỉ áp dụng cho bước `run:`. Bước `uses:` (action) chạy với thư mục làm việc là gốc workspace (`$GITHUB_WORKSPACE`), nên đường dẫn phải tính từ gốc repo.

**9. Khóa cache Maven?**
Hash của `**/pom.xml`, `**/.mvn/wrapper/maven-wrapper.properties`, `**/.mvn/extensions.xml`. Thêm dependency → `pom.xml` đổi → khóa mới → lần chạy sau là cache miss: Maven tải lại các thư viện cần, và cuối job (bước *Post*) lưu cache mới với khóa mới. Từ lần sau nữa lại nhanh.

**10. Cache và artifact?**
Cache để **tăng tốc** lần chạy sau, có thể mất bất cứ lúc nào mà không làm kết quả sai — ví dụ `~/.m2/repository`. Artifact để **giữ kết quả** của một lần chạy cho người xem/tải hoặc cho job khác — ví dụ `app/target/surefire-reports/` khi test đỏ.

**11. `failure()`, `always()`, `!cancelled()`?**
Mặc định mỗi step có `if: success()` (mọi bước trước xanh). `failure()`: chỉ khi có bước trước đỏ. `always()`: luôn chạy, kể cả khi workflow bị hủy — docs khuyên tránh cho việc quan trọng. `!cancelled()`: chạy cả khi xanh lẫn đỏ, trừ khi bị hủy — hợp cho thu log, dọn dẹp. Nhớ viết `if: ${{ !cancelled() }}` vì `!` đầu giá trị YAML là cú pháp tag.

**12. `ubuntu-24.04` vs `ubuntu-latest`?**
`ubuntu-latest` là nhãn trôi, đang được chuyển sang 26.04 (19/10–19/11/2026); công cụ cài sẵn có thể đổi hoặc bị gỡ → build có thể hỏng đột ngột mà code không đổi. Ghim `ubuntu-24.04` cho kết quả lặp lại được. Đánh đổi: phải chủ động nâng cấp khi image cũ bị GitHub ngừng hỗ trợ — nhưng đó là việc có kế hoạch, làm trên một PR và có CI kiểm tra.

**13. Mật khẩu PostgreSQL trong `ci.yml`?**
Secret là thứ bảo vệ một tài nguyên có giá trị. Database CI chỉ tồn tại vài phút trong một VM dùng một lần, không có dữ liệu thật, không ai bên ngoài kết nối được → lộ mật khẩu không gây hại gì. Database production chứa dữ liệu thật và tồn tại lâu dài → mật khẩu phải là secret (GitHub Secrets, AWS Secrets Manager…), không bao giờ nằm trong repo.

**14. Re-run chạy code nào?**
Code **cũ**: re-run dùng đúng `GITHUB_SHA` và `GITHUB_REF` của lần chạy ban đầu. Muốn test code mới phải push commit mới. Re-run chỉ hợp cho lỗi tạm thời (mạng, registry) hoặc để bật debug logging.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Matrix

```yaml
name: Matrix experiment
on:
  workflow_dispatch:
  push:
jobs:
  java:
    strategy:
      matrix:
        java: ['21', '25']
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/setup-java@v6
        with:
          distribution: temurin
          java-version: ${{ matrix.java }}
      - run: java -version
```

Tên hiển thị: `java (21)` và `java (25)`. Nếu là required check, phải chọn **từng** tên `java (21)`, `java (25)` — tên `java` không còn tồn tại. Đây là lý do thêm matrix vào job đã required sẽ làm PR kẹt cho tới khi cập nhật luật.

### Bài 2 — `workflow_dispatch` có input

```yaml
name: Dispatch experiment
on:
  workflow_dispatch:
    inputs:
      environment:
        description: Môi trường đích
        type: choice
        options: [dev, staging]
        default: dev
      dry_run:
        description: Chỉ in ra, không làm gì
        type: boolean
        default: true
jobs:
  show:
    runs-on: ubuntu-24.04
    steps:
      - env:
          TARGET_ENV: ${{ inputs.environment }}
          DRY_RUN: ${{ inputs.dry_run }}
        run: echo "environment=$TARGET_ENV dry_run=$DRY_RUN"
```

Điểm cần thấy: file phải nằm trên nhánh mặc định thì nút *Run workflow* mới hiện; giá trị input được đưa qua `env:` rồi đọc như biến môi trường (thói quen an toàn — bài 04).

### Bài 3 — Tìm lỗi

| # | Lỗi | Hậu quả | Sửa |
|---|---|---|---|
| 1 | `branches: [master]` | Repo dùng `main` → workflow không bao giờ chạy | `branches: [main]` |
| 2 | `setup-java` đứng trước `checkout` | `cache: maven` không tìm thấy `pom.xml` để tính khóa → lỗi | Đưa `checkout` lên đầu |
| 3 | `SPRING_DATASOURCE_URL` dùng host `postgres`, và **không có** khối `services:` | Không có database; kể cả có service thì job trên runner phải dùng `localhost` | Thêm `services: postgres` + `ports`, dùng `localhost:5432` |
| 4 | Thiếu `SPRING_DATASOURCE_USERNAME`/`PASSWORD` | `Could not resolve placeholder 'SPRING_DATASOURCE_PASSWORD'` (username có giá trị mặc định trong `application.yml`, password thì không) | Thêm vào `env:` |
| 5 | `./mvnw ... \| tee build.log` không có `pipefail` | Test đỏ vẫn xanh | Bỏ `tee` hoặc `shell: bash` |
| 6 | `needs: build_test` | ID job là `build-test` → lỗi workflow | `needs: build-test` |
| (thêm) | Không có `name:` cho job | Không sai, nhưng tên check = ID job; nên ghi rõ để khớp branch protection | `name: build-test` |

actionlint bắt được lỗi 6 (job không tồn tại) và có thể cảnh báo `| tee` qua ShellCheck tùy phiên bản; lỗi 1–5 là lỗi **ngữ nghĩa** — chỉ người hiểu hệ thống mới thấy. Công cụ không thay được hiểu biết.

### Bài 4 — Đo hiệu quả cache

Không có đáp án số cố định. Bằng chứng cần có trong nhật ký (chữ chính xác có thể khác theo phiên bản `setup-java`, minh họa):

- Lần 1, bước *Set up JDK 21*: dòng kiểu `maven cache is not found`; bước *Post Set up JDK 21*: dòng `Cache saved with the key: setup-java-Linux-x64-maven-<hash>`.
- Lần 2: dòng `Cache restored from key: setup-java-Linux-x64-maven-<hash>`; bước *Post* báo cache đã tồn tại nên không lưu lại.
- Phép tính: `(t1 - t2) / t1 × 100%`. Thường phần tải dependency chiếm phần lớn thời gian lần đầu.

### Bài 5 — Job summary

```yaml
      - name: Test summary
        if: ${{ !cancelled() }}
        run: |
          shopt -s nullglob
          files=(target/surefire-reports/TEST-*.xml)
          if [ ${#files[@]} -eq 0 ]; then
            echo "Không có báo cáo test (build lỗi trước khi chạy test?)" >> "$GITHUB_STEP_SUMMARY"
            exit 0
          fi
          sum() { grep -ho "$1=\"[0-9]*\"" "${files[@]}" | awk -F'"' '{s+=$2} END {print s+0}'; }
          {
            echo "## Kết quả test"
            echo ""
            echo "| Tests | Failures | Errors | Skipped |"
            echo "|---|---|---|---|"
            echo "| $(sum tests) | $(sum failures) | $(sum errors) | $(sum skipped) |"
          } >> "$GITHUB_STEP_SUMMARY"
```

Giải thích:

- Bước chạy trong `app/` nhờ `defaults.run.working-directory`, nên đường dẫn là `target/...`.
- `if: ${{ !cancelled() }}` để có bảng cả khi test đỏ; phải bọc vì `!` đứng đầu.
- `nullglob`: không có file nào khớp thì mảng rỗng thay vì chứa chuỗi `TEST-*.xml` nguyên văn.
- Thuộc tính `tests`, `failures`, `errors`, `skipped` nằm trên thẻ `<testsuite>` của mỗi file XML Surefire; `awk` cộng dồn.
- Kiểm tra trên runner xong mới đưa vào PR thật.

### Bài 6 — Thiết kế: sửa `docs/` không phải chờ build Java

**Cách 1 — Điều kiện ở cấp job thay vì `paths:` ở cấp workflow.** Workflow luôn chạy. Job nhỏ đầu tiên xác định có file trong `app/` thay đổi không (ví dụ `git diff --name-only` giữa base và head, hoặc một action lọc đường dẫn — nhớ ghim SHA), xuất ra output `app_changed`. Job `build-test` có `if: needs.changes.outputs.app_changed == 'true'`. Khi PR chỉ sửa `docs/`, `build-test` bị **skipped do điều kiện** → báo *Success* cho required check → PR merge được.
- Ưu: rõ ràng, tiết kiệm thời gian.
- Nhược: logic phát hiện thay đổi có thể sai (quên file dùng chung như `pom.xml` gốc, `docker/`, `.github/`) → bỏ sót test. Phải liệt kê cẩn thận.

**Cách 2 — Job tổng hợp luôn chạy.** Thêm job `ci-ok` với `needs: [build-test, ...]` và `if: ${{ !cancelled() }}`, chỉ kiểm tra `needs.*.result` không có `failure`. Branch protection chỉ yêu cầu `ci-ok`. Các job con được tự do có điều kiện/matrix/đổi tên mà không phải sửa luật.
- Ưu: luật bảo vệ ổn định; thêm/bớt job không làm kẹt PR.
- Nhược: thêm một job; viết sai điều kiện trong `ci-ok` (ví dụ coi `skipped` của một job đáng lẽ phải chạy là ổn) sẽ mở cổng cho code lỗi.

**Cách đơn giản nhất cho `taskhub`:** không dùng `paths:` gì cả, chấp nhận vài phút CI cho PR sửa tài liệu. Repo nhỏ, một người — sự đơn giản đáng giá hơn vài phút.
