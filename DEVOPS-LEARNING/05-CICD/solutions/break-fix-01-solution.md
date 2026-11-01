# Lời giải — Break-fix CI #1

> Đề bài: [labs/break-fix-01/README.md](../labs/break-fix-01/README.md). Chỉ đọc khi đã làm xong hoặc bị kẹt quá 30 phút sau khi xem hết gợi ý.
>
> Các dòng log dưới đây là **minh họa** — chữ chính xác có thể khác theo phiên bản runner, Maven, driver PostgreSQL. Hãy tìm **ý chính** in đậm trong log thật của bạn.

## Mục lục

- [1. Bảng tổng hợp](#1-bảng-tổng-hợp)
- [2. Lời giải từng lỗi](#2-lời-giải-từng-lỗi)
- [3. File workflow sau khi sửa](#3-file-workflow-sau-khi-sửa)
- [4. Phương pháp debug CI rút ra từ bài này](#4-phương-pháp-debug-ci-rút-ra-từ-bài-này)
- [5. Tiêu chí chấm nhật ký](#5-tiêu-chí-chấm-nhật-ký)

---

## 1. Bảng tổng hợp

| # | Lỗi | Trạng thái trên GitHub | actionlint bắt được trước khi push? | Tái hiện được trên laptop? |
|---|---|---|---|---|
| 1 | `pull-request:` thay vì `pull_request:` | Lần chạy thất bại, **không có job** | ✅ | — (lỗi của GitHub, không phải của lệnh) |
| 2 | `runs-on: ubuntu-24.4` | Job **chờ mãi**, không bao giờ bắt đầu | ✅ | — |
| 3 | `app/mvnw` mất quyền thực thi trong commit | Đỏ, exit code `126` | ❌ (actionlint chỉ đọc YAML) — `git ls-files -s` bắt được | ✅ `./mvnw` → Permission denied |
| 4 | `java-version: '17'` | Đỏ ở bước compile | ❌ | ✅ nếu chạy bằng JDK 17 |
| 5 | Service `postgres` thiếu `ports` | Đỏ ở test, `Connection refused` | ❌ | ✅ container không `-p` |
| 6 | Mật khẩu lấy từ secret chưa tạo | Đỏ ở test, xác thực thất bại | ❌ | ✅ biến mật khẩu rỗng |
| 7 | `path:` của upload-artifact sai gốc | Bước **xanh** kèm cảnh báo vàng, không có artifact | ❌ | — |

Hai lỗi đầu là lỗi **cấu hình nền tảng** (GitHub không hiểu file / không tìm được máy), bốn lỗi giữa là **khác biệt giữa runner và laptop**, lỗi cuối là **lỗi im lặng** — loại nguy hiểm nhất vì không làm gì đỏ.

---

## 2. Lời giải từng lỗi

### Lỗi 1 — Tên sự kiện sai: `pull-request`

**Triệu chứng:** ngay sau `git push`, tab Actions có một lần chạy màu đỏ, không có job nào. Trang tóm tắt có annotation kiểu (minh họa):

```text
Invalid workflow file: .github/workflows/ci.yml#L4
The workflow is not valid. .github/workflows/ci.yml (Line: 4, Col: 3): Unexpected value 'pull-request'
```

actionlint (minh họa):

```text
.github/workflows/ci.yml:4:3: unknown Webhook event "pull-request". see https://docs.github.com/... for list of all Webhook event names [events]
```

**Nguyên nhân gốc:** tên sự kiện của GitHub Actions dùng dấu gạch dưới: `pull_request`. Một khóa không hợp lệ làm **cả file** không hợp lệ — kể cả trigger `push` đúng cũng không chạy.

**Sửa:**

```diff
 on:
-  pull-request:
+  pull_request:
     branches: [main]
```

**Phòng tránh:** chạy actionlint trước khi push (về sau: chạy actionlint ngay trong CI hoặc pre-commit hook). Dùng extension YAML có schema GitHub Actions trong VS Code.

**Gặp lại:** mọi workflow bạn viết; `on: push: tags:` của release (v1), `workflow_dispatch` (v3).

---

### Lỗi 2 — Nhãn runner không tồn tại: `ubuntu-24.4`

**Triệu chứng:** job `build-test` hiện vòng tròn vàng; log chỉ có một dòng kiểu *Waiting for a runner to pick up this job...* và đứng yên. `timeout-minutes: 15` **không** cứu được vì nó chỉ tính thời gian job **đang chạy**, không tính thời gian chờ.

Bẫy kèm theo: file có `concurrency` theo `github.ref`, và trên `main` thì `cancel-in-progress: false`. Lần chạy kẹt vẫn được tính là "đang chạy" → push bản sửa lên `main` thì lần chạy mới nằm **chờ (pending)** sau lần kẹt. Phải **Cancel workflow** lần kẹt.

actionlint (minh họa): `label "ubuntu-24.4" is unknown. available labels are ...`.

**Nguyên nhân gốc:** `runs-on` là **bộ lọc chọn máy**: GitHub tìm runner mang nhãn đó. Không có runner nào mang nhãn `ubuntu-24.4` (nhãn đúng: `ubuntu-24.04`) → không ai nhận job. GitHub không báo lỗi ngay vì về nguyên tắc một self-hosted runner mang nhãn đó có thể online sau.

**Sửa:** `runs-on: ubuntu-24.04` → commit, push → hủy lần chạy kẹt.

**Vì sao không đổi sang `ubuntu-latest` cho nhanh:** `ubuntu-latest` là nhãn **di động** — GitHub đang chuyển nó từ 24.04 sang 26.04 (19/10–19/11/2026); image mới đổi phiên bản công cụ và bỏ một số gói. Build hôm nay xanh, tuần sau đỏ mà không ai sửa code. Ghim phiên bản = build lặp lại được; nâng cấp là một PR có chủ đích.

**Gặp lại:** self-hosted runner (Module 05 bài 06), job chạy trên runner riêng ở công ty có nhãn tùy chỉnh.

---

### Lỗi 3 — `app/mvnw` mất quyền thực thi trong commit

**Triệu chứng** (step *Build and test*, minh họa):

```text
/home/runner/work/_temp/1b2c....sh: line 1: ./mvnw: Permission denied
Error: Process completed with exit code 126.
```

**Cách tìm:** exit code **126** = "tìm thấy file nhưng không thực thi được" (127 mới là "không tìm thấy lệnh"). Runner checkout **commit**, nên câu hỏi là: commit lưu `mvnw` với quyền gì?

```bash
git ls-files -s app/mvnw
# 100644 4e1a... 0	app/mvnw      ← 644: file thường, không có bit x
```

**Nguyên nhân gốc:** Git lưu đúng một thông tin quyền cho file: thực thi (`100755`) hay không (`100644`). Trong bài, file mất bit `x` trước khi commit — tình huống thật hay gặp khi file đi qua Windows/NTFS hoặc được tạo bằng công cụ không giữ quyền.

**Sửa:**

```bash
chmod +x app/mvnw
git add app/mvnw                         # hoặc: git update-index --chmod=+x app/mvnw
git commit -m "fix(ci): make maven wrapper executable"
git ls-files -s app/mvnw                 # phải là 100755
```

> ⚠️ Bẫy khi dùng cách `git update-index --chmod=+x`: nếu file trên đĩa vẫn **không** có quyền `x` mà sau đó bạn commit bằng `git commit -a` (hoặc `git add app/mvnw`), Git lấy lại mode từ file trên đĩa → index quay về `100644`, công sức vừa rồi mất (đã kiểm chứng khi chạy thử lab). Cách chắc chắn: `chmod +x` trên đĩa trước, rồi `git add`, rồi kiểm tra bằng `git ls-files -s`.

> Không sửa bằng cách đổi lệnh thành `sh mvnw` hay thêm `chmod +x` vào workflow: đó là **che triệu chứng** — mọi người clone repo đều gặp lại lỗi.

**Gặp lại:** script trong `scripts/` (healthcheck, backup) chạy bằng cron/systemd trên EC2; entrypoint script trong Dockerfile.

---

### Lỗi 4 — JDK trên runner là 17, project cần 21

**Triệu chứng** (minh họa):

```text
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin:...:compile (default-compile) on project taskhub:
        Fatal error compiling: error: release version 21 not supported
```

Step *Set up JDK* trước đó **xanh** — nó cài đúng thứ bạn yêu cầu, chỉ là yêu cầu sai.

**Cách tìm:** dòng `release version 21 not supported` nói thẳng: trình biên dịch đang chạy **cũ hơn** 21. Mở log step *Set up JDK* xem phiên bản đã cài; mở `app/pom.xml` thấy `<java.version>21</java.version>`.

**Nguyên nhân gốc:** `java-version: '17'`. Trên laptop bạn dùng JDK 21 nên không bao giờ gặp.

**Sửa:** `java-version: '21'`. (Giữ dấu nháy: YAML hiểu `21` là số; với các phiên bản như `'8.0'` hay `'21.0'` thiếu nháy sẽ thành số thực — thói quen tốt là luôn để nháy.)

**Phòng tránh:** một nguồn sự thật cho phiên bản Java: `pom.xml`, Dockerfile (`eclipse-temurin:21-...`) và workflow phải khớp — Dependabot/PR review kiểm tra cả ba khi nâng cấp.

---

### Lỗi 5 — Service container không publish port

**Triệu chứng** (minh họa, đã rút gọn — đọc dòng `Caused by:` **cuối cùng**):

```text
[ERROR] Tests run: 1, Failures: 0, Errors: 1 ... TaskhubApplicationTests
...
Caused by: org.postgresql.util.PSQLException: Connection to localhost:5432 refused. Check that the hostname and port are correct and that the postmaster is accepting TCP/IP connections.
Caused by: java.net.ConnectException: Connection refused
```

Đồng thời step *Initialize containers* báo PostgreSQL **healthy** — dễ khiến bạn nghĩ "database ổn rồi".

**Cách tìm:** `healthy` chỉ chứng minh PostgreSQL chạy **bên trong** container (`pg_isready` chạy trong chính container). Câu hỏi đúng: từ chỗ **bước job đang chạy** có tới được port đó không? Các step `run:` chạy **trực tiếp trên máy runner**, còn PostgreSQL chạy trong một container trên Docker network riêng. `localhost:5432` của máy runner chỉ dẫn tới container khi port được **publish** — giống hệt `-p 5432:5432` ở [Docker bài 04](../../04-DOCKER/04-volumes-networks-env.md).

**Sửa:**

```diff
     services:
       postgres:
         image: postgres:17
         env:
           ...
+        ports:
+          - 5432:5432
         options: >-
```

**Đối chiếu:** nếu job chạy **trong container** (`jobs.<id>.container:`), job và service chung một network → kết nối bằng tên service `postgres:5432`, không cần `ports`. Docs GitHub mô tả rõ cả hai trường hợp.

**Gặp lại:** Compose trên EC2 (v2), Service/port trong Kubernetes (v6) — luôn hỏi "process gọi đang đứng ở network nào".

---

### Lỗi 6 — Secret chưa tồn tại → mật khẩu rỗng

**Triệu chứng** (minh họa — tùy phiên bản driver, bạn sẽ thấy **một trong hai** dòng):

```text
Caused by: org.postgresql.util.PSQLException: FATAL: password authentication failed for user "taskhub"
Caused by: org.postgresql.util.PSQLException: The server requested SCRAM-based authentication, but no password was provided.
```

Cả hai đều có nghĩa "mật khẩu ứng dụng gửi không khớp mật khẩu database được khởi tạo". Dòng thứ nhất cũng là thứ bạn thấy khi mật khẩu **có** nhưng **sai**.

**Cách tìm:** `SPRING_DATASOURCE_PASSWORD: ${{ secrets.DB_PASSWORD }}`. Repo `taskhub-ci-breakfix` mới tạo → **Settings → Secrets and variables → Actions** trống. Theo docs GitHub, expression tham chiếu secret chưa được tạo trả về **chuỗi rỗng** — không có cảnh báo nào. Trong log, giá trị secret luôn hiện `***`, nên bạn không thể nhìn log để biết nó rỗng.

**Nguyên nhân gốc:** người bàn giao "chuyển mật khẩu sang secrets" ở **một phía** (ứng dụng), quên phía database, và quên tạo secret.

**Sửa — hai cách đều đạt, chọn và giải thích:**

| Cách | Thay đổi | Khi nào hợp lý |
|---|---|---|
| A (khớp bản tham khảo) | Cả `POSTGRES_PASSWORD` và `SPRING_DATASOURCE_PASSWORD` dùng cùng một hằng `ci-only-password` | Database tạm sống vài phút trong runner dùng một lần, không có dữ liệu thật, không ai từ ngoài kết nối tới. Mật khẩu này không bảo vệ gì nên không phải secret |
| B | Tạo secret `DB_PASSWORD`, dùng `${{ secrets.DB_PASSWORD }}` ở **cả hai** chỗ | Team có quy định "không có chuỗi giống mật khẩu trong repo" (máy quét secret sẽ không báo nhầm) |

Điều sai không nằm ở việc dùng hay không dùng secret, mà ở chỗ **hai phía phải cùng một nguồn giá trị**.

**Phòng tránh:** khi chuyển cấu hình sang secrets, kiểm tra theo cặp "ai đặt — ai dùng". Với workflow dùng secret bắt buộc, thêm một bước kiểm tra sớm, ví dụ:

```yaml
      - name: Check required secrets
        env:
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
        run: test -n "$DB_PASSWORD" || { echo "::error::Thiếu secret DB_PASSWORD"; exit 1; }
```

**Gặp lại:** secret của workflow deploy (v3); PR từ fork **không** nhận được secret của repo → cùng triệu chứng "rỗng" (bài 04).

---

### Lỗi 7 — `path` của upload-artifact tính sai gốc (ticket #6002)

**Triệu chứng:** trong các lần chạy đỏ ở lỗi 5–6, step *Upload test reports* có dấu tích **xanh**, nhưng output có dòng vàng:

```text
Warning: No files were found with the provided path: target/surefire-reports/. No artifacts will be uploaded.
```

Trang tóm tắt không có mục `test-reports`. (Ở lỗi 4, compile thất bại nên chưa có báo cáo nào — cảnh báo khi đó là hợp lý; ở lỗi 5–6 test đã chạy, báo cáo **có** trong `app/target/surefire-reports/` mà vẫn không upload được → đó mới là manh mối.)

**Nguyên nhân gốc:** `defaults.run.working-directory: app` chỉ áp dụng cho step **`run:`**. Step **`uses:`** chạy với thư mục làm việc là gốc workspace (thư mục checkout). README của action nói đường dẫn tương đối tính từ thư mục làm việc hiện tại → nó tìm `<gốc repo>/target/surefire-reports/` — không tồn tại. Giá trị mặc định `if-no-files-found: warn` khiến bước này **không đỏ**.

**Sửa:**

```diff
       - name: Upload test reports
         if: failure()
         uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
         with:
           name: test-reports
-          path: target/surefire-reports/
+          path: app/target/surefire-reports/
           retention-days: 7
```

🟨 Có thể thêm `if-no-files-found: error` — nhưng cân nhắc: ở lỗi 4 (compile hỏng, chưa có báo cáo) bước này sẽ đỏ thêm và gây nhiễu. Bản tham khảo giữ mặc định; điều quan trọng là bạn **đọc cảnh báo**.

**Kiểm chứng:** phép thử PR cố ý làm sai một test (README mục 7) → artifact `test-reports` xuất hiện, trong đó có `TEST-com.taskhub....TaskControllerTest.xml` và file `.txt` ghi rõ assertion sai.

---

## 3. File workflow sau khi sửa

Khác bản tham khảo [reference/workflows/ci.yml](../labs/reference/workflows/ci.yml) ở chỗ không có job `image` (xem lý do trong đề bài):

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
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Set up JDK
        uses: actions/setup-java@b843ebf9b913146b38da2eaa7aeddf76074ae1ad # v6.1.0
        with:
          distribution: temurin
          java-version: '21'
          cache: maven

      - name: Build and test
        run: ./mvnw -B -ntp verify

      - name: Upload test reports
        if: failure()
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: test-reports
          path: app/target/surefire-reports/
          retention-days: 7
```

Cộng với thay đổi ngoài YAML: `app/mvnw` ở mode `100755` trong commit.

---

## 4. Phương pháp debug CI rút ra từ bài này

1. **Xác định tầng lỗi trước khi đọc log chi tiết.**

   | Bạn thấy | Tầng | Nhìn vào |
   |---|---|---|
   | Lần chạy đỏ, không có job | GitHub không đọc được workflow | Annotations, actionlint |
   | Job vàng mãi, log trống | Không có runner nhận job | `runs-on`, concurrency đang chặn |
   | Step đỏ, có exit code | Lệnh trong step thất bại | Log step, exit code |
   | Mọi thứ xanh nhưng thiếu kết quả | Lỗi im lặng | Cảnh báo vàng, output của step |

2. **Đọc lỗi đầu tiên, không phải lỗi cuối cùng của log.** Một lỗi gốc kéo theo nhiều lỗi phụ (test hỏng → upload cảnh báo → job đỏ). Trong stack trace Java thì ngược lại: tìm `Caused by:` **cuối cùng**.
3. **Sửa từng lỗi một, mỗi lần một commit.** Commit message nói rõ sửa gì → lịch sử Git chính là nhật ký debug. Sửa năm thứ cùng lúc mà vẫn đỏ thì không biết cái nào có tác dụng.
4. **Tái hiện trên máy bằng đúng lệnh và đúng giá trị của workflow.** Copy nguyên lệnh trong `run:` và biến trong `env:`. Lỗi tái hiện được trên laptop thì sửa nhanh gấp nhiều lần so với vòng push–chờ–đọc log.
5. **Liệt kê khác biệt giữa runner và laptop** — gần như mọi lỗi "máy tôi chạy được" nằm ở đây:

   | Khía cạnh | Laptop | Runner |
   |---|---|---|
   | Code | Thư mục làm việc (cả file chưa commit, quyền file trên đĩa) | **Commit** được checkout |
   | Công cụ | JDK, Maven, Docker bạn đã cài | Thứ có trong image runner + thứ workflow cài (setup-java) |
   | Biến môi trường, secret | `.env`, shell của bạn | Chỉ những gì khai báo trong `env:` / secrets của repo |
   | Mạng | `localhost` = máy bạn, có thể đang có PostgreSQL dev | Máy sạch; service container ở network riêng |
   | Trạng thái | Cache, database cũ còn dữ liệu | Mỗi job bắt đầu từ máy mới |

6. **Bắt lỗi trước khi push** bằng thứ rẻ nhất: actionlint cho YAML, `git ls-files -s` cho quyền file, chạy `./mvnw verify` trên máy.
7. **Đọc cả cảnh báo.** Dấu tích xanh chỉ nói "bước không trả exit code khác 0", không nói "bước làm đúng việc".

---

## 5. Tiêu chí chấm nhật ký

| Mức | Mô tả |
|---|---|
| ✅ Đạt | Đủ 7 lỗi đúng thứ tự gặp; mỗi lỗi có dòng log gốc, nguyên nhân, cách sửa; có lần chạy xanh trên `main` và lần chạy đỏ trên PR có artifact |
| ⭐ Tốt | Thêm: giải thích được vì sao lỗi 3–6 không xảy ra trên laptop; giải thích vì sao lần chạy mới nằm chờ khi lần cũ kẹt (concurrency); lập luận chọn cách A hay B ở lỗi 6 |
| ❌ Chưa đạt | Có dùng cách lách (`-DskipTests`, `continue-on-error`, xóa service/test), đổi sang `ubuntu-latest`, hoặc không giải thích được một thay đổi nào đó |
