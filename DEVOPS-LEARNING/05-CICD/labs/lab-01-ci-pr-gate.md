# Lab 01 — CI trên mỗi Pull Request và cổng chặn merge

> ⏱️ ~3–4 giờ · Tuần 9 · Mức độ: 🟥 Bắt buộc
> Kiến thức cần có trước: [02. GitHub Actions cơ bản](../02-github-actions-basics.md), [Git 03 — Pull Request & bảo vệ nhánh](../../03-GIT/03-github-pull-request-code-review.md)
> Môi trường: `[WSL]` repo `~/projects/taskhub` · `[GitHub]` repo `taskhub` (public) · `[Runner]` `ubuntu-24.04`

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Bức tranh tổng thể](#2-bức-tranh-tổng-thể)
- [3. Chuẩn bị](#3-chuẩn-bị)
- [4. Các bước thực hiện](#4-các-bước-thực-hiện)
- [5. Thí nghiệm bắt buộc](#5-thí-nghiệm-bắt-buộc)
- [6. Kết quả mong đợi](#6-kết-quả-mong-đợi)
- [7. Lỗi thường gặp](#7-lỗi-thường-gặp)
- [8. Checklist xác nhận hoàn thành](#8-checklist-xác-nhận-hoàn-thành)
- [9. Dọn dẹp](#9-dọn-dẹp)
- [10. Câu hỏi sau lab](#10-câu-hỏi-sau-lab)

---

## 1. Mục tiêu

Kết thúc lab, repo `taskhub` của bạn có:

1. File `.github/workflows/ci.yml` (workflow `CI`) với job `build-test` do **bạn tự viết**: build + chạy toàn bộ test (kể cả test cần PostgreSQL) trên mỗi Pull Request vào `main` và mỗi lần push vào `main`.
2. Luật bảo vệ `main` bắt buộc check **`build-test`** xanh mới được merge — áp dụng cả với bạn (admin).
3. Bằng chứng bạn đã **thấy** cổng chặn hoạt động: một PR đỏ không merge được, một "xanh giả" do thiếu `pipefail`, một PR kẹt do `paths:`.

Đây là bước đầu của [dự án v1](../../12-PRACTICAL-PROJECT/milestones/v1-ci.md). Job `image` (build + quét + push image) được thêm ở [bài 03](../03-github-actions-docker-registry.md) và [Lab 02](lab-02-release-ghcr.md).

> **Luật của lab:** gõ workflow bằng tay theo hiểu biết từ bài 02. [Bản tham khảo](reference/workflows/ci.yml) chỉ mở khi đã xong, để đối chiếu.

---

## 2. Bức tranh tổng thể

```text
[WSL] nhánh ci/add-build-workflow ──push──► [GitHub] PR → main
                                                │ event pull_request
                                                ▼
                                    [Runner] job build-test
                                      service postgres:17 (localhost:5432)
                                      ./mvnw -B -ntp verify
                                                │ ✅ / ❌
                                                ▼
                         Branch protection: "Require status checks" = build-test
                              ❌ → nút Merge bị khóa (kể cả admin)
                              ✅ → Squash and merge
                                                │ event push (main)
                                                ▼
                                    [Runner] job build-test chạy lại trên main
```

---

## 3. Chuẩn bị

### 3.1. Điều kiện

- [ ] Đã xong [v0](../../12-PRACTICAL-PROJECT/milestones/v0-docker-compose.md): tag `v0.2.0` có trên GitHub.
- [ ] `main` đã được bảo vệ theo [Git 03 §4.7](../../03-GIT/03-github-pull-request-code-review.md#47--bảo-vệ-nhánh-main): bắt buộc PR, **Do not allow bypassing** đang bật.
- [ ] Trên máy, `./mvnw verify` xanh khi PostgreSQL dev đang chạy ([tuần 6 §8.2](../../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md#82-test-khởi-động-context--cần-database)).
- [ ] Đã làm phần thực hành ở [bài 02 §9](../02-github-actions-basics.md) trên repo `actions-playground`.
- [ ] 🟨 Docker Desktop đang chạy (để dùng actionlint). Không có cũng làm được lab, nhưng bạn sẽ mất thời gian push để tìm lỗi YAML.

### 3.2. Tạo nhánh

```bash
cd ~/projects/taskhub
git switch main
git pull --ff-only
git switch -c ci/add-build-workflow
```

Tiền tố `ci/` dành cho thay đổi pipeline — quy ước đặt ở [Git 04](../../03-GIT/04-team-workflows.md).

### 3.3. Kiểm tra quyền thực thi của `mvnw` trong Git

```bash
git ls-files -s app/mvnw
```

Phải thấy `100755`. Nếu là `100644`, runner sẽ báo `Permission denied`:

```bash
git update-index --chmod=+x app/mvnw
git commit -m "build: make maven wrapper executable"
```

---

## 4. Các bước thực hiện

### Bước 1 — Phiên bản 1: chỉ build, chưa có database

Tạo `.github/workflows/ci.yml` với **phiên bản 1** ở [bài 02 §4.17](../02-github-actions-basics.md): event `pull_request` vào `main`, một job `build-test` (có `name: build-test`), checkout → setup JDK 21 → `cd app && ./mvnw -B -ntp verify`.

Kiểm tra trước khi push:

```bash
docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:1.7.12 -color
echo "actionlint exit code: $?"
```

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add build-test workflow"
git push -u origin ci/add-build-workflow
```

Mở PR `ci/add-build-workflow` → `main`, tiêu đề `ci: add build-test workflow`. Trong phần mô tả PR, ghi rõ PR này **cố ý đỏ ở các commit đầu** để học.

**Dự đoán trước khi xem:** test nào sẽ đỏ, thông báo lỗi là gì? Ghi vào nhật ký. Sau đó mở tab **Checks** của PR (hoặc **Actions**), đọc log theo quy trình ở [bài 02 §12](../02-github-actions-basics.md).

<details>
<summary>Gợi ý cấp 1 — không thấy workflow chạy</summary>

Kiểm tra: file có nằm đúng `.github/workflows/` không? Nhánh đích của PR có đúng là `main` không? Tab Actions có hiện *Invalid workflow file* không?
</details>

### Bước 2 — Phiên bản 2: thêm PostgreSQL

Thêm vào job:

- khối `services: postgres:` (image `postgres:17`, `POSTGRES_DB/USER/PASSWORD`, `ports`, healthcheck bằng `pg_isready`);
- khối `env:` với `SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`.

Tự quyết định host trong `SPRING_DATASOURCE_URL` và **viết lý do** vào nhật ký trước khi push.

```bash
git commit -am "ci: run tests against postgres service container"
git push
```

Kết quả mong đợi: **xanh**. Mở bước *Initialize containers*, tìm dòng chứng minh PostgreSQL đã healthy trước khi Maven chạy.

<details>
<summary>Gợi ý cấp 1 — Connection refused</summary>

Job chạy trực tiếp trên VM runner, không chạy trong container. Từ VM, container PostgreSQL chỉ với tới được qua port đã publish.
</details>

<details>
<summary>Gợi ý cấp 2 — password authentication failed</summary>

So sánh từng ký tự `POSTGRES_PASSWORD` (của service) và `SPRING_DATASOURCE_PASSWORD` (của job). Chúng là hai biến ở hai nơi khác nhau nhưng phải cùng giá trị.
</details>

<details>
<summary>Gợi ý cấp 3 — job treo ở Initialize containers rồi lỗi</summary>

Healthcheck không bao giờ thành công. `pg_isready -U <user> -d <db>` phải dùng đúng user/database đã khai báo trong `POSTGRES_USER`/`POSTGRES_DB`. Đọc log container trong bước *Initialize containers*.
</details>

### Bước 3 — Phiên bản 3: cache, thư mục làm việc, báo cáo khi đỏ

Thêm:

- `cache: maven` cho `setup-java`;
- `defaults.run.working-directory: app` (bỏ `cd app &&`);
- `timeout-minutes: 15`;
- bước upload `app/target/surefire-reports/` khi `failure()`, giữ 7 ngày.

Push, chờ xanh. Ghi lại **thời gian của bước *Build and test*** và tìm trong bước *Set up JDK 21* dòng cho biết cache có được khôi phục không; trong bước *Post Set up JDK 21* dòng cho biết cache có được lưu không.

Tạo một commit rỗng để chạy lần nữa:

```bash
git commit --allow-empty -m "ci: re-run to check maven cache"
git push
```

So sánh thời gian hai lần chạy. Ghi số liệu vào nhật ký (dùng cho [bài tập 4 của bài 02](../02-github-actions-basics.md)).

### Bước 4 — Phiên bản 4: chạy trên main, concurrency, quyền tối thiểu

Thêm:

- `push: branches: [main]` vào `on:`;
- `permissions: contents: read` ở cấp workflow;
- khối `concurrency` (hủy lần chạy cũ chỉ khi là PR);
- `persist-credentials: false` cho bước checkout.

Chạy actionlint, commit `ci: harden build-test workflow`, push. Kết quả: xanh.

Lúc này job `build-test` của bạn phải tương đương job `build-test` trong [bản tham khảo](reference/workflows/ci.yml) (trừ việc bản tham khảo ghim action bằng SHA — bài 04).

### Bước 5 — Bật cổng chặn: required status check `[GitHub]`

1. Repo `taskhub` → **Settings** → **Branches** → luật của `main` → **Edit**.
2. Tick **Require status checks to pass before merging**.
3. Ô tìm kiếm: gõ `build-test` → chọn check **build-test** (nguồn: GitHub Actions).
4. 🟨 *Require branches to be up to date before merging*: để **tắt** với repo một người (bật thì mỗi lần `main` có commit mới, mọi PR phải cập nhật nhánh rồi chạy CI lại).
5. Kiểm tra **Do not allow bypassing the above settings** vẫn đang bật → **Save changes**.

> Nếu repo dùng **Rulesets** (Settings → Rules → Rulesets), luật tương ứng là *Require status checks to pass*, thêm check `build-test`.
>
> Không tìm thấy `build-test` trong ô tìm kiếm? Check chỉ xuất hiện sau khi đã chạy ít nhất một lần trong repo. Kiểm tra tên job (`name:`) trùng chính xác với chữ bạn gõ.

Quay lại PR: check `build-test` giờ có nhãn **Required**.

---

## 5. Thí nghiệm bắt buộc

Làm **tất cả**, mỗi thí nghiệm ghi vào nhật ký: dự đoán → kết quả thật → giải thích.

### Thí nghiệm 1 — PR đỏ không merge được, kể cả bạn là admin

Trên nhánh `ci/add-build-workflow`, sửa `app/src/test/java/com/taskhub/TaskControllerTest.java`: trong test `createValidTaskReturns201WithLocation`, đổi `status().isCreated()` thành `status().isOk()`.

```bash
git commit -am "test: break controller test on purpose"
git push
```

Quan sát:

1. Check `build-test` đỏ. Hộp merge ở cuối PR báo merge bị chặn; nút merge không bấm được.
2. Trang **Summary** của lần chạy có artifact `test-reports`. Tải về, giải nén, mở file `com.taskhub.TaskControllerTest.txt`: tìm tên test lỗi, dòng lỗi, giá trị mong đợi/thực tế.
3. Trong log bước *Build and test*, tìm dòng `Tests run: ..., Failures: ...` và `exit code`.

**Chưa sửa test** — giữ nguyên để làm thí nghiệm 2.

### Thí nghiệm 2 — "Xanh giả" do thiếu `pipefail`

Vẫn giữ test hỏng, đổi bước build thành:

```yaml
      - name: Build and test
        run: ./mvnw -B -ntp verify | tee build.log
```

Push. Dự đoán: xanh hay đỏ? Quan sát kết quả, mở log thấy `BUILD FAILURE` không?

Sau đó thêm `shell: bash` vào bước này, push lại, quan sát. Giải thích chênh lệch bằng bảng shell ở [bài 02 §4.7](../02-github-actions-basics.md).

Cuối cùng **hoàn tác** về `run: ./mvnw -B -ntp verify` (không `tee`, không cần `shell: bash`).

### Thí nghiệm 3 — Sửa test, merge

```bash
# đổi lại status().isOk() → status().isCreated()
git commit -am "test: restore controller test"
git push
```

Xanh → nút merge mở. Chọn **Squash and merge**. Commit message gợi ý: `ci: add build-test workflow (#<số PR>)` — các commit thử nghiệm được gộp, lịch sử `main` sạch.

Sau khi merge, mở tab **Actions**: phải thấy một lần chạy `CI` với event **push** trên `main`. Trang chủ repo: commit mới nhất trên `main` có dấu ✅.

Đồng bộ local:

```bash
git switch main
git pull --ff-only
git branch -d ci/add-build-workflow
```

### Thí nghiệm 4 — PR kẹt vì `paths:`

```bash
git switch -c ci/try-paths-filter
```

Sửa `.github/workflows/ci.yml`, thêm bộ lọc chỉ cho `pull_request`:

```yaml
on:
  pull_request:
    branches: [main]
    paths: ['app/**']
```

Commit, push, mở PR. Commit này chỉ sửa `.github/workflows/ci.yml` — không có file nào trong `app/`.

Quan sát: workflow **không chạy**; check `build-test` hiện trạng thái chờ báo cáo (*Waiting for status to be reported*) và PR không merge được. Giải thích chuỗi nhân quả.

**Không merge.** Đóng PR, xóa nhánh:

```bash
git switch main
git push origin --delete ci/try-paths-filter
git branch -D ci/try-paths-filter
```

> ⚠️ `git branch -D` xóa nhánh local kể cả khi chưa merge. Ở đây đúng ý muốn: nhánh thử nghiệm bị bỏ.

### Thí nghiệm 5 — Hủy lần chạy cũ khi push liên tiếp (concurrency)

Tạo nhánh `ci/try-concurrency`, push một commit rỗng, mở PR, rồi trong vòng 20 giây push thêm commit rỗng thứ hai:

```bash
git switch -c ci/try-concurrency
git commit --allow-empty -m "chore: concurrency test 1" && git push -u origin ci/try-concurrency
# mở PR trên GitHub, sau đó:
git commit --allow-empty -m "chore: concurrency test 2" && git push
```

Quan sát lần chạy của commit 1 bị **Canceled**. Đóng PR, xóa nhánh như thí nghiệm 4.

---

## 6. Kết quả mong đợi

| Thời điểm | Bạn phải thấy |
|---|---|
| Bước 1 (phiên bản 1) | Đỏ; `TaskhubApplicationTests` lỗi vì thiếu `SPRING_DATASOURCE_PASSWORD` (hoặc không kết nối được database); `TaskControllerTest` xanh |
| Bước 2 | Xanh; *Initialize containers* có dòng báo service postgres healthy |
| Bước 3 | Lần đầu: cache không tìm thấy, cuối job lưu cache. Lần sau: cache được khôi phục, *Build and test* nhanh hơn rõ rệt |
| Bước 5 | Check `build-test` có nhãn **Required** trên PR |
| Thí nghiệm 1 | Đỏ, merge bị chặn dù bạn là admin; artifact `test-reports` có file `.txt` chỉ ra `expected:<200> but was:<201>` (minh họa) |
| Thí nghiệm 2 | Có `tee`, không `shell: bash`: **xanh** dù log có `BUILD FAILURE`. Thêm `shell: bash`: đỏ |
| Thí nghiệm 3 | Xanh → merge; lần chạy event `push` trên `main` xanh |
| Thí nghiệm 4 | Workflow không chạy, PR kẹt chờ check `build-test` |
| Thí nghiệm 5 | Lần chạy cũ *Canceled* |

---

## 7. Lỗi thường gặp

| Triệu chứng | Nguyên nhân thường gặp | Cách kiểm tra / sửa |
|---|---|---|
| Không có lần chạy nào sau khi mở PR | File sai thư mục; `branches: [master]`; YAML không hợp lệ | Tab Actions; actionlint; sửa tên nhánh |
| `./mvnw: Permission denied`, exit code 126 | Mode `100644` trong Git | [Mục 3.3](#33-kiểm-tra-quyền-thực-thi-của-mvnw-trong-git) |
| `./mvnw: No such file or directory` | Chạy ở gốc repo, không phải `app/` | `defaults.run.working-directory: app` |
| `Could not resolve placeholder 'SPRING_DATASOURCE_PASSWORD'` | Thiếu `env:` | Thêm 3 biến `SPRING_DATASOURCE_*` |
| `Connection to localhost:5432 refused` | Thiếu `ports:`; hoặc URL dùng `postgres` | Thêm `ports: - 5432:5432`; dùng `localhost` |
| `UnknownHostException: postgres` | URL dùng `postgres:5432` trong khi job chạy trên runner | Dùng `localhost:5432` |
| `password authentication failed` | Hai mật khẩu không khớp | So sánh `POSTGRES_PASSWORD` và `SPRING_DATASOURCE_PASSWORD` |
| `setup-java` lỗi không tìm thấy file khớp `**/pom.xml` | `setup-java` đứng trước `checkout` | Đổi thứ tự |
| Bước upload cảnh báo *No files were found* | `path: target/...` thiếu `app/` | `path: app/target/surefire-reports/` |
| Không thấy `build-test` khi thêm required check | Check chưa từng chạy; gõ sai tên; dùng ID job thay vì `name` | Chạy workflow ít nhất một lần; dùng đúng tên hiển thị |
| Vẫn merge được khi đỏ | Chưa tick required check, hoặc **Do not allow bypassing** đang tắt (admin bỏ qua được) | Kiểm tra lại luật ở bước 5 |
| PR kẹt *Waiting for status to be reported* | `paths:`/`branches:` khiến workflow không chạy; đổi `name:` của job sau khi đã đặt required | Bỏ filter; cập nhật tên check trong luật |

---

## 8. Checklist xác nhận hoàn thành

Tự kiểm tra (đánh dấu khi có bằng chứng — ảnh chụp hoặc link lần chạy trong nhật ký):

- [ ] `git ls-files -s app/mvnw` → `100755`.
- [ ] actionlint không báo lỗi trên `.github/workflows/ci.yml`.
- [ ] Trên GitHub, `main` có commit `ci: add build-test workflow (#N)` với dấu ✅.
- [ ] Tab Actions có ít nhất một lần chạy `CI` event `push` trên `main` xanh.
- [ ] Settings → Branches: `main` yêu cầu check `build-test`; *Do not allow bypassing* bật.
- [ ] Nhật ký có đủ 5 thí nghiệm (dự đoán → kết quả → giải thích) và số liệu thời gian cache miss/hit.
- [ ] Giải thích được từng dòng của `ci.yml` cho một người khác (hoặc tự nói thành tiếng).

---

## 9. Dọn dẹp

- Đóng các PR thử nghiệm (`ci/try-paths-filter`, `ci/try-concurrency`) mà không merge; xóa nhánh local và remote.
- `git fetch --prune` để xóa các remote-tracking branch đã bị xóa trên GitHub.
- Artifact `test-reports` tự hết hạn sau 7 ngày — không cần xóa tay.
- **Giữ nguyên** required check `build-test` — từ giờ mọi PR của `taskhub` đều phải qua cổng này. Sau [Lab 02](lab-02-release-ghcr.md), thêm check `image` vào danh sách required.

---

## 10. Câu hỏi sau lab

1. Thí nghiệm 1: bạn là admin repo. Điều gì trong cấu hình khiến chính bạn cũng không merge được?
2. Thí nghiệm 2 cho thấy rủi ro gì nếu chỉ nhìn màu xanh/đỏ mà không đọc log? Bạn sẽ áp dụng quy tắc gì cho mọi bước `run:` có dấu `|` trong tương lai?
3. Thí nghiệm 4: đề xuất cách để PR chỉ sửa tài liệu vẫn merge được mà `build-test` vẫn là required.
4. Vì sao sau khi merge, CI chạy **lại** trên `main` dù PR đã xanh? Hai lần chạy test cùng một code phải không?
5. Lần chạy đầu tiên trên `main` sau khi merge có được hưởng cache Maven từ các lần chạy trên PR không? Tìm bằng chứng trong log.

Lời giải và giải thích: [solutions/lab-01-solutions.md](../solutions/lab-01-solutions.md) — chỉ mở sau khi đã làm.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule) | Bật *Require status checks to pass before merging*, tìm và chọn check | 2026-10-31 |
| [GitHub Docs — Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks) | Workflow bị bỏ qua do filter → check chờ mãi, chặn merge | 2026-10-31 |
| [GitHub Docs — Creating PostgreSQL service containers](https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers) | Service container, `localhost` khi job chạy trên runner | 2026-10-31 |
| [GitHub Docs — Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) | Shell mặc định, `concurrency`, `defaults.run` | 2026-10-31 |
| [actions/setup-java (README)](https://github.com/actions/setup-java) | `cache: maven` | 2026-10-31 |
| [actionlint — Usage](https://github.com/rhysd/actionlint/blob/main/docs/usage.md) | Chạy bằng Docker | 2026-10-31 |
