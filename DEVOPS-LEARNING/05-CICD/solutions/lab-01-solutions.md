# Lời giải — Lab 01: CI trên mỗi Pull Request và cổng chặn merge

> ⚠️ Chỉ đọc sau khi đã tự làm. Đầu ra mẫu là minh họa — chữ chính xác có thể khác theo phiên bản.

Quay lại lab: [lab-01-ci-pr-gate.md](../labs/lab-01-ci-pr-gate.md) · Bản tham khảo workflow: [reference/workflows/ci.yml](../labs/reference/workflows/ci.yml)

## Mục lục

- [1. Giải thích các bước](#1-giải-thích-các-bước)
- [2. Giải thích các thí nghiệm](#2-giải-thích-các-thí-nghiệm)
- [3. Trả lời câu hỏi sau lab](#3-trả-lời-câu-hỏi-sau-lab)
- [4. Tự chấm](#4-tự-chấm)

---

## 1. Giải thích các bước

### Bước 1 — Phiên bản 1 đỏ vì sao?

`TaskControllerTest` là `@WebMvcTest` với repository được mock (`@MockitoBean`) → không cần database → xanh.

`TaskhubApplicationTests` là `@SpringBootTest` → khởi động toàn bộ ứng dụng. `application.yml` có `password: ${SPRING_DATASOURCE_PASSWORD}` không có giá trị mặc định → Spring không resolve được placeholder → context không khởi động → test **Error** (không phải Failure). Trong log (minh họa):

```text
[ERROR] Tests run: 1, Failures: 0, Errors: 1, Skipped: 0 ... <<< FAILURE! -- in com.taskhub.TaskhubApplicationTests
...
Caused by: ... Could not resolve placeholder 'SPRING_DATASOURCE_PASSWORD' in value "${SPRING_DATASOURCE_PASSWORD}"
```

Nếu bạn đặt biến mà chưa có service, lỗi chuyển thành `Connection to localhost:5432 refused`. Cả hai đều là lỗi **môi trường**, không phải lỗi code — nhận ra điều này là kỹ năng chính của bước 1.

### Bước 2 — Host nào và vì sao

`jdbc:postgresql://localhost:5432/taskhub`. Job không có `container:` → Maven chạy trên VM runner → với tới container PostgreSQL qua port publish `5432:5432` trên `localhost`. Dòng chứng minh healthy trong *Initialize containers* có dạng `postgres service is healthy.` (minh họa).

### Bước 3 — Cache

Lần đầu: `setup-java` báo không tìm thấy cache; bước *Post Set up JDK 21* lưu cache với khóa dạng `setup-java-Linux-x64-maven-<hash>`. Lần chạy kế tiếp **trên cùng PR**: khôi phục cache, bước *Build and test* nhanh hơn rõ rệt vì không tải lại dependency.

### Bước 4 — Đối chiếu với bản tham khảo

Khác biệt hợp lệ duy nhất: bản tham khảo ghim action bằng SHA (`actions/checkout@3d3c42e…  # v7.0.1`) thay vì `@v7`. Mọi khác biệt khác (host, biến, healthcheck, `path:` của artifact, vị trí `permissions`/`concurrency`) — hãy tự giải thích được vì sao bản của bạn vẫn đúng, hoặc sửa theo.

### Bước 5 — Required check

Sau khi lưu, PR hiện `build-test` kèm nhãn **Required**. Điều kiện để luật có tác dụng với chính bạn: **Do not allow bypassing the above settings** đang bật (mặc định admin được bỏ qua).

---

## 2. Giải thích các thí nghiệm

### Thí nghiệm 1 — Đỏ, merge bị chặn

Chuỗi nhân quả: assert `isOk()` (200) nhưng controller trả 201 → JUnit báo **Failure** → Maven trả exit code 1 → shell `bash -e` dừng → bước đỏ → job đỏ → check `build-test` = failure → branch protection (required + không cho bypass) khóa merge.

File `com.taskhub.TaskControllerTest.txt` trong artifact (minh họa):

```text
Tests run: 3, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 2.1 s <<< FAILURE! -- in com.taskhub.TaskControllerTest
com.taskhub.TaskControllerTest.createValidTaskReturns201WithLocation -- Time elapsed: 0.3 s <<< FAILURE!
java.lang.AssertionError: Status expected:<200> but was:<201>
```

### Thí nghiệm 2 — Xanh giả

- `run: ./mvnw -B -ntp verify | tee build.log` không có `shell:` → `bash -e {0}`, không `pipefail` → exit code của pipe = exit code của `tee` = 0 → **xanh**, dù log ghi `BUILD FAILURE`. Nguy hiểm hơn đỏ: mọi người tin là ổn.
- Thêm `shell: bash` → `bash --noprofile --norc -eo pipefail {0}` → pipe trả exit code của `./mvnw` (1) → **đỏ** đúng.
- Quy tắc rút ra: mọi bước `run:` có `|` phải có `shell: bash` (hoặc `set -o pipefail`); tốt hơn nữa là tránh pipe ở lệnh quyết định kết quả.

### Thí nghiệm 3 — Merge và chạy lại trên `main`

Squash merge tạo **một commit mới** trên `main` (SHA khác mọi commit trong PR). Event `push` vào `main` kích hoạt `CI` cho commit đó. Dấu ✅ trên trang chủ repo thuộc về commit squash này.

### Thí nghiệm 4 — Kẹt vì `paths:`

Workflow `pull_request` được đọc từ merge commit của PR, nên bộ lọc mới có hiệu lực ngay trên chính PR đó. PR chỉ sửa `.github/workflows/ci.yml`, không khớp `app/**` → workflow **bị bỏ qua hoàn toàn** → không có check `build-test` nào được tạo → branch protection chờ mãi → *Waiting for status to be reported*. Khác với job bị skip do `if:` (báo *Success*), workflow bị bỏ qua do filter để check ở trạng thái chờ.

### Thí nghiệm 5 — Concurrency

Hai lần chạy cùng `group` = `CI-refs/pull/<N>/merge`; event là `pull_request` nên `cancel-in-progress` = `true` → lần chạy mới hủy lần cũ. Trên `main`, biểu thức cho `false` → các lần chạy xếp hàng, không hủy nhau (mỗi commit `main` cần image riêng ở bài 03).

---

## 3. Trả lời câu hỏi sau lab

**1. Vì sao admin cũng không merge được?**
Hai thiết lập cùng lúc: *Require status checks to pass before merging* với check `build-test`, và *Do not allow bypassing the above settings*. Thiếu cái thứ hai, admin thấy tùy chọn merge bỏ qua luật.

**2. Rủi ro của việc chỉ nhìn màu?**
Màu chỉ phản ánh exit code của từng bước. Nếu bước được viết sai (pipe không `pipefail`, `|| true`, `continue-on-error` đặt nhầm), màu xanh không có nghĩa là test xanh. Quy tắc: bước có `|` phải có `shell: bash`; không dùng `|| true`/`continue-on-error` cho bước kiểm tra; thỉnh thoảng cố ý làm hỏng test để chứng minh pipeline biết đỏ (đúng như thí nghiệm 1–2).

**3. PR chỉ sửa tài liệu vẫn merge được?**
Xem [lời giải bài tập 6 của bài 02](02-solutions.md): bỏ `paths:` (đơn giản nhất cho `taskhub`); hoặc chuyển điều kiện xuống cấp job (`if:` dựa trên output của job phát hiện thay đổi — job skip do `if:` báo *Success*); hoặc dùng job tổng hợp luôn chạy làm required check duy nhất.

**4. Vì sao CI chạy lại trên `main`?**
Commit trên `main` sau squash merge là commit **mới**, chưa từng được test. Merge commit thử của PR (`refs/pull/N/merge`) được tạo với `main` **tại thời điểm chạy CI**; nếu giữa lúc đó và lúc bấm merge, `main` có commit khác (từ PR khác), code cuối cùng trên `main` khác thứ đã test. Ngoài ra từ bài 03, lần chạy trên `main` là lần **build và push image** — PR không push image.

**5. Lần chạy đầu trên `main` có dùng được cache của PR không?**
Không. Theo docs GitHub, cache tạo trong lần chạy của PR thuộc phạm vi merge ref của PR đó; nhánh đích và các PR khác không khôi phục được. Lần chạy đầu tiên trên `main` thường là cache miss (log bước *Set up JDK 21* báo không tìm thấy cache) và lưu cache cho `main`. Từ đó, mọi PR vào `main` khôi phục được cache của `main`.

---

## 4. Tự chấm

| Tiêu chí | Đạt khi |
|---|---|
| Workflow | Job `build-test` tương đương bản tham khảo, actionlint sạch, giải thích được từng dòng |
| Cổng chặn | Thí nghiệm 1 có ảnh chụp/link chứng minh merge bị chặn |
| Hiểu shell | Thí nghiệm 2: dự đoán đúng trước khi chạy, giải thích bằng `-e`/`pipefail` |
| Hiểu required check | Thí nghiệm 4: giải thích được vì sao kẹt và đề xuất ít nhất một cách sửa |
| Nhật ký | Đủ 5 thí nghiệm và số liệu cache |

Chưa đạt tiêu chí nào → làm lại thí nghiệm đó trước khi sang [bài 03](../03-github-actions-docker-registry.md).
