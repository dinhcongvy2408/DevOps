# 01. Khái niệm CI/CD

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Git 04 — Quy trình nhóm](../03-GIT/04-team-workflows.md), [Docker 03 — Dockerfile & multi-stage](../04-DOCKER/03-dockerfile-multistage.md), [Linux 06 — Bash scripting](../01-LINUX/06-bash-scripting.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop đang chạy. Bài này **chưa dùng GitHub Actions** — bạn tự đóng vai "máy chủ CI" trên máy mình để hiểu pipeline làm gì trước khi viết YAML ở bài 02.

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

- Giải thích **Continuous Integration**, **Continuous Delivery** và **Continuous Deployment** khác nhau ở đâu, kèm ví dụ bằng chính dự án `taskhub`.
- Kể tên các giai đoạn của một pipeline (build → test → package → scan → publish → deploy → verify) và giải thích vì sao chúng xếp theo thứ tự đó.
- Phân biệt **pipeline, stage, job, step**; hiểu **artifact** là gì và vì sao phải **build một lần, triển khai nhiều nơi**.
- Hiểu vì sao CI chạy trên **máy sạch dùng một lần** (ephemeral runner) và hệ quả: CI **chỉ thấy những gì đã commit**.
- Biết các chỉ số **DORA** dùng để đo hiệu quả chuyển giao phần mềm, và tự tính được từ dữ liệu.
- Tự viết một script mô phỏng pipeline của `taskhub` trên máy, đo thời gian từng giai đoạn, và thiết kế pipeline thật trên giấy để bài 02–03 hiện thực hóa.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Trên máy em chạy được mà, sao CI đỏ?" | CI chạy trên máy **sạch**, chỉ có code đã commit. Khác biệt nằm ở thứ gì đó chỉ có trên máy dev (file chưa commit, cache, biến môi trường) |
| Team merge code cả tuần rồi mới ghép thử vào thứ Sáu → cả buổi chiều sửa conflict và lỗi | Đây là lý do CI ra đời: **tích hợp nhỏ, thường xuyên** |
| Sếp hỏi: "Mình đang Continuous Delivery hay Continuous Deployment?" | Khác nhau ở một điểm: bước đưa lên production có cần người bấm duyệt hay không |
| Image chạy trên staging ổn, lên production lại lỗi, vì production build lại từ code | Vi phạm nguyên tắc **build một lần** — artifact ở hai môi trường thực chất là hai thứ khác nhau |
| Pipeline mất 40 phút, dev bắt đầu "merge trước, xem CI sau" | Pipeline chậm làm hỏng chính mục đích của CI. Cần biết cách xếp thứ tự và cache |
| Phỏng vấn: "Làm sao biết quy trình chuyển giao của team đang tốt lên?" | Các chỉ số DORA: tần suất deploy, lead time, tỉ lệ lỗi, thời gian khôi phục |

Không hiểu khái niệm, bạn sẽ chép YAML từ mạng mà không biết vì sao job này đứng trước job kia, vì sao image không được build lại khi release, vì sao CI đỏ còn máy mình thì xanh.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Vấn đề "tích hợp muộn"

Giả sử 4 người cùng làm `taskhub`, mỗi người một nhánh, **hai tuần** mới merge vào `main` một lần:

- Mỗi nhánh đã lệch khỏi `main` hàng trăm dòng → conflict lớn, khó gỡ ([Git bài 02](../03-GIT/02-branching-merging-conflicts.md)).
- Hai thay đổi riêng lẻ đều đúng, nhưng ghép lại thì sai (người A đổi tên cột, người B viết query dùng tên cũ). Lỗi chỉ lộ ra khi ghép.
- Ghép xong có lỗi, nhưng có tới hàng chục commit từ 4 người → không biết commit nào gây lỗi.

Martin Fowler gọi hiện tượng này là "integration hell" trong bài [Continuous Integration](https://martinfowler.com/articles/continuousIntegration.html). Cách chữa ngược với trực giác: **tích hợp thường xuyên hơn**, mỗi lần một lượng nhỏ, và để **máy** kiểm tra mỗi lần tích hợp.

### 3.2. Những thứ bạn đã có và sẽ dùng lại

| Đã học | Vai trò trong CI/CD |
|---|---|
| Exit code, `set -euo pipefail` ([Linux bài 06](../01-LINUX/06-bash-scripting.md)) | Pipeline quyết định **xanh/đỏ** hoàn toàn dựa vào exit code của từng lệnh. Exit 0 = xanh, khác 0 = đỏ |
| `./mvnw verify` ([hướng dẫn app tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)) | Lệnh build + test mà CI sẽ chạy |
| Nhánh ngắn hạn, Pull Request ([Git bài 03](../03-GIT/03-github-pull-request-code-review.md), [bài 04](../03-GIT/04-team-workflows.md)) | CI chạy trên mỗi PR; branch protection chặn merge khi CI đỏ |
| Dockerfile, layer cache ([Docker bài 03](../04-DOCKER/03-dockerfile-multistage.md)) | Bước **package** của pipeline |
| Tag image theo SHA và SemVer ([Docker bài 06](../04-DOCKER/06-registry.md)) | Bước **publish** — artifact có tên bất biến |
| Quét lỗ hổng bằng Trivy ([Docker bài 07](../04-DOCKER/07-docker-security.md)) | Bước **scan** — cổng chặn image có lỗ hổng nghiêm trọng |

> **Ý quan trọng nhất của bài:** pipeline không làm điều gì "thần kỳ". Nó chỉ chạy **đúng những lệnh bạn đã biết**, theo một thứ tự cố định, trên một máy sạch, mỗi khi có thay đổi — và dừng lại ngay khi một lệnh trả exit code khác 0.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Continuous Integration (CI) — tích hợp liên tục

**Continuous Integration** là thực hành: mọi người **đưa thay đổi vào nhánh chính thường xuyên** (ít nhất mỗi ngày), và **mỗi lần đưa vào đều được build và test tự động**.

Bài viết của Martin Fowler (cập nhật lớn 01/2024) liệt kê các thực hành của CI. Những ý chính, và cách `taskhub` áp dụng:

| Thực hành (theo Fowler) | Ở `taskhub` |
|---|---|
| Mọi thứ nằm trong version control, có một nhánh chính | Repo `taskhub`, nhánh `main` |
| Tự động hóa việc build | `./mvnw -B verify`, `docker build` — không có bước làm tay |
| Build tự kiểm tra (self-testing) | Test JUnit chạy trong `verify`; test đỏ → build đỏ |
| Mọi người đưa commit vào nhánh chính mỗi ngày | Nhánh `feat/*` ngắn, PR nhỏ, squash merge |
| Mỗi lần đẩy lên nhánh chính đều kích hoạt build | Workflow chạy khi `push` vào `main` **và** khi mở/cập nhật PR |
| Sửa build hỏng ngay lập tức | `main` đỏ là việc ưu tiên số một của cả team |
| Giữ build nhanh | Cache Maven, cache layer Docker, xếp bước rẻ lên trước |
| Mọi người thấy được chuyện gì đang xảy ra | Trạng thái CI hiện ngay trên PR và trang Actions |
| Tự động hóa việc triển khai | Từ v3 (tuần 13) |

CI **không phải là một công cụ**. Jenkins, GitHub Actions, GitLab CI chỉ là công cụ giúp thực hiện CI. Một team có GitHub Actions nhưng mỗi nhánh sống ba tuần thì **không** làm CI.

### 4.2. 🟥 Continuous Delivery và Continuous Deployment

Cả hai đều viết tắt là **CD**, nên rất dễ lẫn:

| | Continuous Delivery (chuyển giao liên tục) | Continuous Deployment (triển khai liên tục) |
|---|---|---|
| Định nghĩa | Mọi thay đổi qua được pipeline đều **ở trạng thái sẵn sàng** đưa lên production bất cứ lúc nào | Mọi thay đổi qua được pipeline **tự động được đưa lên** production |
| Bước lên production | **Con người quyết định** (bấm duyệt, tạo tag) | **Không có người** ở giữa |
| Điều kiện | Pipeline đáng tin, artifact sẵn sàng | Như bên trái, **cộng** test tự động đủ tốt để tin tuyệt đối, cộng giám sát và rollback tự động |
| Phổ biến ở | Hầu hết công ty, đặc biệt ngân hàng, outsource có khách hàng duyệt | Công ty sản phẩm có văn hóa kỹ thuật mạnh |

Trang [continuousdelivery.com](https://continuousdelivery.com/) của Jez Humble định nghĩa Continuous Delivery là khả năng đưa mọi loại thay đổi (tính năng, cấu hình, sửa lỗi, thử nghiệm) tới production hoặc người dùng **một cách an toàn, nhanh và bền vững**. Chữ "khả năng" là then chốt: Continuous Delivery không bắt buộc deploy liên tục, mà bắt buộc **lúc nào cũng deploy được**.

Áp vào `taskhub`:

| Phiên bản | Pipeline làm đến đâu | Thuộc loại |
|---|---|---|
| **v1** (tuần 9–10) | Build, test, quét, push image lên GHCR. **Không** deploy | CI + bước đầu của Continuous Delivery (artifact luôn sẵn sàng) |
| **v3** (tuần 13) | Thêm bước tự deploy lên EC2 | Delivery hay Deployment phụ thuộc vào thiết kế: có cổng người duyệt hay không (sẽ quyết định ở v3) |

### 4.3. 🟥 Các giai đoạn của một pipeline

| Giai đoạn | Câu hỏi nó trả lời | Ở `taskhub` | Kết quả khi lỗi |
|---|---|---|---|
| **Checkout** | Lấy đúng commit nào? | Clone repo, đúng SHA của commit/PR | — |
| **Build** (biên dịch) | Code có biên dịch được không? | `mvnw` compile | Lỗi cú pháp, thiếu thư viện |
| **Test** | Code có làm đúng điều nó hứa không? | Unit test + test cần PostgreSQL | Test đỏ |
| **Package** (đóng gói) | Tạo ra thứ triển khai được | `app.jar` → Docker image | Dockerfile sai, thiếu file trong context |
| **Scan** (quét) | Có lỗ hổng hoặc secret không? | Trivy quét image | Lỗ hổng CRITICAL đã có bản vá |
| **Publish** (phát hành) | Đưa artifact tới nơi lưu trữ có tên bất biến | Push `ghcr.io/<user>/taskhub:<sha7>` | Sai quyền registry |
| **Deploy** (triển khai) | Chạy artifact ở môi trường đích | v3: EC2 pull image và chạy | Server không pull được, container không khỏe |
| **Verify** (kiểm tra sau triển khai) | Bản mới có thật sự chạy tốt không? | v3: `curl /actuator/health` (smoke test) | Health `DOWN` → rollback |

Thứ tự không tùy ý. Nguyên tắc: **bước rẻ và hay lỗi chạy trước, bước đắt và ít lỗi chạy sau**. Biên dịch lỗi thì không cần tốn 3 phút build image. Test đỏ thì không được push image.

### 4.4. 🟥 Pipeline, stage, job, step

| Khái niệm | Nghĩa | Ví dụ ở `taskhub` |
|---|---|---|
| **Pipeline** (đường ống) | Toàn bộ chuỗi tự động chạy khi có một sự kiện | "Mọi thứ chạy khi mở PR" |
| **Stage** (giai đoạn) | Nhóm logic các việc cùng mục đích; stage sau chỉ chạy khi stage trước xanh | Build & test → Image |
| **Job** (công việc) | Một đơn vị chạy trên **một máy** (runner). Các job có thể chạy **song song** hoặc **nối tiếp** | Job `build-test`, job `image` |
| **Step** (bước) | Một lệnh hoặc một action trong job, chạy **tuần tự** trên cùng máy | `./mvnw -B verify` |

Hai điểm hay nhầm:

- **Job khác nhau = máy khác nhau.** File tạo ra trong job `build-test` **không tự có** trong job `image`. Muốn chuyển, phải dùng **artifact** (bài 02) hoặc build lại.
- **Step trong cùng job chia sẻ máy và thư mục**, nên step sau thấy file step trước tạo ra.

Mỗi công cụ gọi tên hơi khác nhau, nhưng khái niệm giống nhau (chi tiết ở [bài 06](06-jenkins-gitlab-overview.md)):

| Khái niệm | GitHub Actions | GitLab CI | Jenkins |
|---|---|---|---|
| File định nghĩa pipeline | `.github/workflows/*.yml` | `.gitlab-ci.yml` | `Jenkinsfile` |
| Pipeline | workflow | pipeline | pipeline |
| Stage | không có từ khóa riêng — dùng `needs:` nối các job | `stages:` | `stage('...')` |
| Job | `jobs.<id>` | job | (một `stage` thường tương ứng) |
| Step | `steps:` | `script:` | `steps { ... }` |
| Máy chạy | runner | runner | agent |

### 4.5. 🟥 Artifact và nguyên tắc "build một lần, triển khai nhiều nơi"

**Artifact** (sản phẩm build) là **thứ được tạo ra** bởi pipeline để dùng ở bước sau hoặc để triển khai: file `.jar`, Docker image, báo cáo test, file SBOM.

Với `taskhub` có hai loại artifact:

| Artifact | Sống ở đâu | Dùng để |
|---|---|---|
| `app.jar` | Chỉ trong lúc build image (stage `build` của Dockerfile) | Trung gian — không triển khai trực tiếp |
| **Docker image** `ghcr.io/<user>/taskhub:<sha7>` | Registry GHCR | **Artifact triển khai** — thứ duy nhất chạy trên mọi môi trường |
| Báo cáo test (`surefire-reports`) | Lưu kèm lần chạy pipeline vài ngày | Đọc khi test đỏ |

**Build một lần, triển khai nhiều nơi** (build once, deploy many — đã gặp ở [Git bài 04](../03-GIT/04-team-workflows.md#49--nhánh-tag-và-môi-trường-báo-trước-module-05)):

```text
 SAI: build lại ở mỗi môi trường              ĐÚNG: build một lần, chuyển tiếp artifact
 code ──build──► image A ──► staging          code ──build──► image :9f8e7d6 ──► staging
 code ──build──► image B ──► production                            │ (cùng digest)
 (A và B có thể khác nhau!)                                       └──────────► production
```

Vì sao build lại là sai, dù cùng một commit:

- Base image `eclipse-temurin:21-jre-noble` có thể đã được cập nhật giữa hai lần build.
- Thư viện Maven có thể tải phiên bản khác (nếu dùng dải phiên bản).
- Thứ đã được test và quét là image A. Thứ chạy production là image B — **chưa ai test B**.

Hệ quả cho thiết kế `taskhub` v1: khi bạn tạo tag `v0.3.0`, workflow release **không build lại**, mà gắn thêm tag `:v0.3.0` cho chính image `:<sha7>` mà CI đã build, test và quét ([bài 03](03-github-actions-docker-registry.md)).

Đi kèm là tính **bất biến** (immutability): một tag artifact, một khi đã push, **không bao giờ** bị ghi đè. Đó là lý do không dùng `latest` ([Docker bài 06](../04-DOCKER/06-registry.md#47--chiến-lược-đặt-tag)).

### 4.6. 🟥 Runner: máy sạch, dùng một lần

**Runner** là máy thực thi pipeline. Theo [tài liệu GitHub](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners), mỗi GitHub-hosted runner (trừ loại 1 CPU) là **một máy ảo mới**. Workflow chạy xong, máy ảo đó bị bỏ đi.

Máy sạch dùng một lần (**ephemeral**) mang lại:

| Lợi ích | Vì sao |
|---|---|
| **Tái lập được** (reproducible) | Không có "rác" từ lần chạy trước: file tạm, process còn sót, cache hỏng |
| **Phát hiện phụ thuộc ngầm** | Code cần một file chỉ có trên máy bạn → CI đỏ ngay, thay vì lỗi trên server |
| **An toàn hơn** | Một lần chạy bị chiếm quyền cũng không để lại gì cho lần chạy sau (so với server Jenkins dùng lâu năm — xem kịch bản ở [Docker bài 07](../04-DOCKER/07-docker-security.md)) |

Cái giá phải trả:

| Đánh đổi | Cách giảm |
|---|---|
| Mỗi lần đều phải tải lại thư viện Maven, base image | **Cache** (bài 02, 03) |
| Không có database sẵn cho test | **Service container** — bật PostgreSQL tạm trong lúc chạy (bài 02) |
| Không giữ được file giữa các job | **Artifact** (bài 02) |

Hệ quả quan trọng nhất: **CI chỉ thấy những gì đã commit và push.** File bạn quên `git add`, biến môi trường bạn `export` trong terminal, thư viện bạn cài tay trên WSL — runner không có gì trong số đó. Phần thực hành sẽ chứng minh điều này.

### 4.7. 🟥 Pipeline as code — pipeline là code

Pipeline được định nghĩa trong **file nằm trong repo** (`.github/workflows/ci.yml`), không phải bằng cách bấm trong giao diện web.

| Lợi ích | Ví dụ |
|---|---|
| Có lịch sử, biết ai đổi gì, khi nào | `git log .github/workflows/` |
| Được review như code | Đổi pipeline cũng phải qua PR |
| Đi cùng phiên bản code | Commit cũ được build bằng đúng pipeline của thời điểm đó |
| Khôi phục được | Xóa nhầm → `git revert` |

Đây cũng là lý do workflow chạy trên PR là **workflow của chính nhánh PR**: bạn sửa `ci.yml` trong PR thì PR đó chạy bằng `ci.yml` mới, trước khi merge. (Ngoại lệ an toàn liên quan tới fork sẽ học ở [bài 04](04-secrets-environments.md).)

### 4.8. 🟥 Phản hồi nhanh (fast feedback)

Giá trị của CI tỉ lệ nghịch với thời gian chạy. Pipeline 5 phút: dev chờ kết quả rồi sửa ngay khi còn nhớ code. Pipeline 40 phút: dev chuyển sang việc khác, quay lại thì quên ngữ cảnh, hoặc merge luôn khi CI chưa xong.

Các cách giữ pipeline nhanh:

| Kỹ thuật | Ở `taskhub` |
|---|---|
| **Fail fast** — bước rẻ, hay lỗi chạy trước | Test (~1 phút) trước build image (~2–4 phút) |
| **Cache** những thứ ít đổi | Thư viện Maven (`~/.m2`), layer Docker |
| **Song song** các job độc lập | 🟨 Ví dụ quét Dockerfile bằng Hadolint chạy song song với test |
| Chỉ chạy job khi phần liên quan thay đổi | 🟨 `paths:` — job Terraform chỉ chạy khi `infra/` đổi (Module 07) |
| Hủy lần chạy cũ khi có commit mới trên cùng PR | `concurrency` (bài 02) |

### 4.9. 🟨 Shift-left security — đưa bảo mật về sớm

Trên trục thời gian (trái = lúc viết code, phải = production), **shift-left** nghĩa là kiểm tra bảo mật **càng sớm càng tốt**. Lỗ hổng phát hiện trong PR chỉ tốn vài phút sửa. Phát hiện trên production thì tốn cả một sự cố.

| Kiểm tra | Giai đoạn | Học ở |
|---|---|---|
| Quét lỗ hổng image (Trivy) | Pipeline, trước khi push | Bài 03 |
| Không để secret trong code và YAML | Lúc viết + pipeline | Bài 04, Module 10 |
| Quyền tối thiểu cho token của pipeline | Cấu hình workflow | Bài 04 |
| Cập nhật thư viện, base image, action có lỗ hổng | Dependabot mở PR tự động | Bài 04 |

### 4.10. 🟥 CI và quy trình nhánh

CI hoạt động tốt nhất với **nhánh ngắn hạn** ([Git bài 04](../03-GIT/04-team-workflows.md)):

| Quy trình | Quan hệ với CI |
|---|---|
| **Trunk-based** / **GitHub Flow** (nhánh sống vài giờ – vài ngày) | Mỗi PR nhỏ → CI chạy nhanh, lỗi dễ khoanh vùng. Đây là cách `taskhub` dùng |
| **Git Flow** với nhánh `develop` và nhánh feature sống lâu | Có CI trên từng nhánh nhưng tích hợp thật (merge vào `develop`) vẫn muộn → vẫn gặp "integration hell" ở mức nhỏ hơn |

Quy trình ở `taskhub` sau v1:

```text
 feat/xyz ─PR─► CI chạy trên PR ─xanh─► merge vào main ─► CI chạy trên main ─► image :<sha7>
                                                            │
 tag v0.3.0 trên commit đó ─────────────────────────────────┴─► gắn tag :v0.3.0 cho chính image đó
```

### 4.11. 🟨 Đo lường: các chỉ số DORA

**DORA** (DevOps Research and Assessment) là nhóm nghiên cứu nhiều năm về hiệu quả chuyển giao phần mềm. Trang [dora.dev](https://dora.dev/guides/dora-metrics/) hiện mô tả **5 chỉ số**, chia hai nhóm:

| Nhóm | Chỉ số | Đo cái gì |
|---|---|---|
| **Tốc độ** (throughput) | **Change lead time** | Thời gian từ khi thay đổi được commit vào version control tới khi chạy trên production |
| | **Deployment frequency** | Bao lâu deploy một lần |
| | **Failed deployment recovery time** | Mất bao lâu để khôi phục sau một lần deploy hỏng cần can thiệp ngay |
| **Độ ổn định** (instability) | **Change fail rate** | Tỉ lệ lần deploy cần can thiệp ngay (rollback, hotfix) |
| | **Deployment rework rate** | Tỉ lệ lần deploy **ngoài kế hoạch**, phát sinh do sự cố production |

Lịch sử ngắn (theo [dora.dev](https://dora.dev/insights/dora-metrics-history/)): ban đầu là **"four keys"** (4 chỉ số). Năm 2023, MTTR được thay bằng *failed deployment recovery time*. Năm 2024 thêm *deployment rework rate*. Tài liệu cũ và nhiều câu hỏi phỏng vấn vẫn nói "4 chỉ số DORA" — bạn nên biết cả hai cách gọi.

Ý chính rút ra từ nghiên cứu của DORA: **tốc độ và độ ổn định không đánh đổi nhau.** Team giỏi deploy thường xuyên **và** ít lỗi hơn, vì mỗi lần thay đổi nhỏ, dễ kiểm tra, dễ quay lại.

> CI/CD tác động trực tiếp lên các chỉ số này: pipeline nhanh → lead time ngắn; artifact bất biến + rollback bằng tag → recovery time ngắn. Bài tập 2 ở mục 14 cho bạn tự tính.

### 4.12. 🟥 Một pipeline tốt cho `taskhub` trông thế nào?

| Tiêu chí | Ý nghĩa cụ thể |
|---|---|
| **Kích hoạt đúng sự kiện** | PR vào `main`: kiểm tra. Merge vào `main`: kiểm tra + publish image. Tag `v*`: phát hành |
| **Nhanh** | Mục tiêu dưới 10 phút cho một PR |
| **Tái lập được** | Phiên bản runner, JDK, base image được chỉ định rõ, không phụ thuộc "bản mới nhất" |
| **Chặn được** | Test đỏ hoặc lỗ hổng CRITICAL → pipeline đỏ → không merge được, không push image |
| **Truy vết được** | Image tag = SHA commit → từ image biết ngay code nào |
| **An toàn** | Không có secret trong YAML/log; token chỉ có quyền tối thiểu |
| **Đọc được log** | Mỗi bước có tên rõ ràng; khi đỏ, lưu báo cáo test để tải về |

Bạn sẽ tự thiết kế pipeline này trên giấy ở Bước 7 của phần thực hành, rồi hiện thực hóa ở [bài 02](02-github-actions-basics.md) và [bài 03](03-github-actions-docker-registry.md).

### 4.13. Gặp lại ở đâu

| Khái niệm | Gặp lại ở |
|---|---|
| Job, step, runner, artifact, cache | [Bài 02](02-github-actions-basics.md) — viết bằng YAML |
| Build một lần, tag bất biến | [Bài 03](03-github-actions-docker-registry.md) — release gắn tag, không build lại; [bài 05](05-deployment-strategies-rollback.md) — rollback |
| Shift-left security | [Bài 04](04-secrets-environments.md), Module 10 |
| Continuous Delivery vs Deployment | Dự án v3 — CD lên EC2 (tuần 13) |
| DORA | Phỏng vấn (Module 13), postmortem (Module 08) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Tuần nào cũng mất chiều thứ Sáu"

Một team outsource 5 người làm một hệ thống đặt lịch. Quy trình: mỗi người làm nhánh riêng cả tuần, chiều thứ Sáu trưởng nhóm merge tất cả vào `develop` rồi build tay, gửi khách test.

- Chiều thứ Sáu luôn có conflict. Build thành công lúc 19h.
- Thứ Hai khách báo lỗi. Không ai biết lỗi do thay đổi nào trong 60 commit.

Sau khi áp dụng CI: nhánh tối đa 2 ngày, PR nhỏ, pipeline chạy test trên mỗi PR, `develop` lúc nào cũng xanh. Khách test bản mới bất cứ ngày nào. Khi có lỗi, `git log` chỉ có vài commit từ lần build xanh gần nhất để khoanh vùng.

**Bài học:** công cụ chỉ là một phần. Thay đổi lớn nhất là **thói quen tích hợp nhỏ và thường xuyên**.

### Ví dụ 2: Pipeline 40 phút

Một team có pipeline: build image (8 phút) → chạy toàn bộ test end-to-end (25 phút) → unit test (5 phút) → lint (2 phút). Dev phàn nàn, bắt đầu merge khi CI chưa xong.

Phân tích:

- Lint và unit test rẻ và **hay lỗi nhất**, nhưng lại chạy cuối. Một lỗi chính tả mất 40 phút mới phát hiện.
- Build image không cần chờ lint.

Sắp xếp lại: lint + unit test (song song, ~5 phút) → build image (8 phút, có cache còn ~2 phút) → test end-to-end chỉ chạy trên `main` và hằng đêm. PR giờ có kết quả trong khoảng 7 phút. Bạn sẽ làm bài tập tương tự ở mục 14.

### Ví dụ 3: Staging chạy tốt, production lỗi

Team build image riêng cho staging và production từ cùng một commit, cách nhau 3 ngày. Trong 3 ngày đó, base image có bản cập nhật đổi phiên bản một thư viện hệ thống. Production lỗi, staging không. Mất nửa ngày để nhận ra hai image khác nhau.

Sửa: build một lần, tag theo SHA, đưa **chính image đó** từ staging lên production. So sánh digest ở hai môi trường phải trùng nhau.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Pipeline tổng quát

```text
  Sự kiện (push, PR, tag)
          │
          ▼
  ┌──────────────── Runner (máy ảo mới, sạch) ─────────────────┐
  │ checkout ─► build ─► test ─► package ─► scan ─► publish    │──► Registry (artifact bất biến)
  │    │          │        │        │         │                │          │
  │    └── bất kỳ bước nào exit ≠ 0 → DỪNG, pipeline ĐỎ ───────┘          │
  └────────────────────────────────────────────────────────────┘          ▼
                                                  deploy ─► verify ─► (lỗi → rollback về tag cũ)
                                                  └─── từ v3 (tuần 13) ───┘
```

### 6.2. CI, Continuous Delivery, Continuous Deployment trên cùng một trục

```text
 commit ─► build ─► test ─► package/publish ─► deploy staging ─► [người duyệt] ─► deploy production
 └──────── Continuous Integration ─────────┘
 └─────────────────────── Continuous Delivery (dừng ở cổng duyệt) ───────────────┘
 └──────────────────── Continuous Deployment (không có cổng duyệt) ──────────────────────────────┘
```

### 6.3. Script mô phỏng của bài này

```text
 ~/projects/taskhub (có thể có file chưa commit)
          │ git clone  → chỉ lấy commit HEAD
          ▼
 /tmp/ci-local.XXXXXX/src  ("runner" sạch)
          │
   ┌──────┴──────────────────────────────────────────────────┐
   │ STAGE checkout   : clone, in SHA                        │
   │ STAGE services   : docker run postgres:17 (port 55432)  │
   │ STAGE build-test : ./mvnw -B -ntp verify                │
   │ STAGE package    : docker build → taskhub:ci-local-<sha>│
   └──────┬──────────────────────────────────────────────────┘
          │ trap EXIT: xóa container PostgreSQL + thư mục tạm, in XANH/ĐỎ
          ▼
   image taskhub:ci-local-<sha7> trên Docker của bạn
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Dùng để |
|---|---|
| `./mvnw -B -ntp verify` | Build + test như CI (không tương tác, không in tiến trình tải) |
| `./mvnw ... -Dmaven.repo.local=<dir>` | Dùng thư mục cache Maven riêng — giả lập runner không có `~/.m2` |
| `git clone <đường-dẫn-repo-local> <đích>` | Lấy bản sạch, chỉ gồm commit, không có file chưa commit |
| `git rev-parse --short=7 HEAD` | SHA rút gọn 7 ký tự — tên tag image |
| `git status --porcelain` | Kiểm tra working directory có thay đổi chưa commit không (rỗng = sạch) |
| `docker build -f docker/Dockerfile -t <tag> <context>` | Bước package |
| `docker run -d --rm --name ... -p 127.0.0.1:55432:5432 postgres:17` | Database tạm cho test |
| `pg_isready -h 127.0.0.1 -U taskhub -d taskhub` | Chờ PostgreSQL nhận kết nối TCP |
| `time <lệnh>` / biến `$SECONDS` | Đo thời gian |
| `echo $?` | Exit code của lệnh vừa chạy — cơ sở của xanh/đỏ |
| `trap '...' EXIT` | Luôn dọn dẹp khi script kết thúc, dù xanh hay đỏ |

---

## 8. Giải thích câu lệnh và tham số

### `./mvnw -B -ntp verify` `[WSL]`

```bash
cd ~/projects/taskhub/app
./mvnw -B -ntp verify
```

| Phần | Ý nghĩa |
|---|---|
| `./mvnw` | Maven Wrapper — tải đúng phiên bản Maven ghi trong `.mvn/wrapper/maven-wrapper.properties`. Mọi máy (kể cả runner) dùng cùng phiên bản |
| `-B` (`--batch-mode`) | Chế độ không tương tác: không hỏi gì, không in màu. Bắt buộc trong CI vì không có ai trả lời câu hỏi |
| `-ntp` (`--no-transfer-progress`) | Không in từng dòng "Downloading... / Downloaded..." — log CI ngắn và dễ đọc hơn rất nhiều |
| `verify` | Chạy các phase: compile → test → package → các bước kiểm tra sau đó. Test đỏ → dừng, exit code khác 0 |

Đầu ra cuối (minh họa, rút gọn):

```text
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
[INFO] Total time:  38.512 s
```

```bash
echo $?
```

```text
0
```

Khi test đỏ:

```text
[ERROR] Tests run: 4, Failures: 1, Errors: 0, Skipped: 0
[INFO] BUILD FAILURE
[ERROR] There are test failures.
[ERROR] Please refer to /tmp/ci-local.Ab12Cd/src/app/target/surefire-reports for the individual test results.
```

`echo $?` → `1`. Pipeline thấy `1` → đánh dấu đỏ, không chạy bước sau.

### `-Dmaven.repo.local=<thư-mục>`

```bash
./mvnw -B -ntp -Dmaven.repo.local="$HOME/devops-lab/05-cicd/m2-cache" verify
```

Bình thường Maven lưu thư viện đã tải ở `~/.m2/repository`. Trên máy bạn thư mục này đã đầy thư viện từ tuần 6, nên build nhanh. Runner mới tinh **không có** thư mục này. Chỉ định một thư mục riêng, ban đầu rỗng, giúp bạn thấy runner "lạnh" chậm thế nào, và **cache** trong bài 02 tiết kiệm được bao nhiêu.

### `git clone` từ repo trên máy

```bash
git clone --quiet ~/projects/taskhub /tmp/ci-test/src
git -C /tmp/ci-test/src log -1 --oneline
```

```text
9f8e7d6 feat(api): filter tasks by status (#12)
```

| Phần | Ý nghĩa |
|---|---|
| `~/projects/taskhub` | Nguồn là repo trên máy — Git chấp nhận đường dẫn thư mục như một remote |
| `--quiet` | Không in tiến trình |
| `-C <dir>` | Chạy lệnh git như thể đang đứng trong `<dir>` |

Bản clone chứa **commit HEAD của nhánh đang checkout** ở repo nguồn. File sửa nhưng chưa commit, file chưa `git add`, file bị `.gitignore` (như `.env`) **không** có trong bản clone — đúng như runner.

### Đo thời gian bằng `$SECONDS`

```bash
start=$SECONDS
sleep 2
echo "Mất $((SECONDS - start)) giây"
```

```text
Mất 2 giây
```

`SECONDS` là biến đặc biệt của Bash: số giây kể từ khi shell khởi động. Lấy hiệu hai thời điểm để đo một đoạn.

### `trap ... EXIT`

```bash
trap cleanup EXIT
```

Hàm `cleanup` luôn chạy khi script kết thúc, dù kết thúc bình thường, do `set -e` dừng giữa chừng hay do Ctrl+C. Đây là cách script không bỏ lại container PostgreSQL chạy ngầm. Trong hàm, `$?` ở dòng đầu tiên chính là exit code của script. Runner của GitHub không cần bước dọn dẹp này vì cả máy ảo bị bỏ đi, nhưng máy của bạn thì cần.

### `pg_isready -h 127.0.0.1`

```bash
docker exec ci-local-pg-1234 pg_isready -h 127.0.0.1 -U taskhub -d taskhub
```

```text
127.0.0.1:5432 - accepting connections
```

Exit code `0` khi sẵn sàng, khác 0 khi chưa. 🟦 Vì sao thêm `-h 127.0.0.1`: khi khởi tạo database lần đầu, script của image `postgres` bật một server tạm **chỉ nghe qua Unix socket** (`listen_addresses=''` trong `docker-entrypoint.sh` của image chính thức), chạy các bước init, rồi tắt và bật lại server thật. Kiểm tra qua TCP đảm bảo bạn chờ **server thật**, không phải server tạm.

---

## 9. Bài thực hành từng bước

Mục tiêu: tự viết một "pipeline" bằng Bash, chạy trên máy, để thấy tận mắt từng giai đoạn, thời gian của nó, và hành vi dừng khi lỗi. Bài 02 sẽ chuyển chính các bước này sang GitHub Actions.

### Bước 1 — Kiểm tra điều kiện `[WSL]`

```bash
docker version --format '{{.Server.Version}}'    # phải in ra phiên bản, không báo lỗi
cd ~/projects/taskhub
git status --porcelain                            # tốt nhất là rỗng
git log -1 --oneline
ls app/mvnw docker/Dockerfile
```

Nếu `docker version` báo lỗi kết nối → mở Docker Desktop ([Docker README §3](../04-DOCKER/README.md#3-môi-trường-docker-desktop--wsl-hoạt-động-thế-nào)).

### Bước 2 — Viết script `ci-local.sh` `[WSL]`

Script đặt **ngoài** repo `taskhub` (đây là công cụ học tập, không phải một phần dự án):

```bash
mkdir -p ~/devops-lab/05-cicd && cd ~/devops-lab/05-cicd
```

Tạo file `ci-local.sh` với nội dung sau. **Gõ lại, đừng chỉ copy** — vừa gõ vừa đọc chú thích:

```bash
#!/usr/bin/env bash
# ci-local.sh — mô phỏng pipeline CI của taskhub trên máy (Module 05, bài 01)
set -euo pipefail

REPO="${REPO:-$HOME/projects/taskhub}"
M2_DIR="${M2_DIR:-$HOME/devops-lab/05-cicd/m2-cache}"   # cache Maven riêng, giả lập runner
PG_PORT="${PG_PORT:-55432}"
DB_PASSWORD="ci-only-password"                          # database tạm, không chứa dữ liệu thật
APP_DB_PASSWORD="${APP_DB_PASSWORD:-$DB_PASSWORD}"      # đổi biến này để giả lập lỗi

WORK="$(mktemp -d /tmp/ci-local.XXXXXX)"
PG_NAME="ci-local-pg-$$"                                # $$ = PID của script → tên không trùng
CURRENT_STAGE="(chưa bắt đầu)"

cleanup() {
  local rc=$?
  docker rm -f "$PG_NAME" > /dev/null 2>&1 || true
  rm -rf "$WORK"
  echo
  if [ "$rc" -eq 0 ]; then
    echo "PIPELINE XANH — tổng ${SECONDS}s"
  else
    echo "PIPELINE ĐỎ tại stage '${CURRENT_STAGE}' (exit ${rc}) — tổng ${SECONDS}s"
  fi
  exit "$rc"
}
trap cleanup EXIT

run_stage() {
  CURRENT_STAGE="$1"; shift
  echo
  echo "=== STAGE: ${CURRENT_STAGE} ==="
  local start=$SECONDS
  "$@"
  echo "=== ${CURRENT_STAGE}: OK sau $((SECONDS - start))s ==="
}

stage_checkout() {
  git clone --quiet "$REPO" "$WORK/src"
  SHA7="$(git -C "$WORK/src" rev-parse --short=7 HEAD)"
  git -C "$WORK/src" log -1 --oneline
}

stage_services() {
  docker run -d --rm --name "$PG_NAME" \
    -e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -p "127.0.0.1:${PG_PORT}:5432" postgres:17 > /dev/null
  for _ in $(seq 1 30); do
    if docker exec "$PG_NAME" pg_isready -h 127.0.0.1 -U taskhub -d taskhub > /dev/null 2>&1; then
      echo "PostgreSQL sẵn sàng ở localhost:${PG_PORT}"
      return 0
    fi
    sleep 1
  done
  echo "PostgreSQL không sẵn sàng sau 30 giây" >&2
  return 1
}

stage_build_test() {
  cd "$WORK/src/app"
  SPRING_DATASOURCE_URL="jdbc:postgresql://localhost:${PG_PORT}/taskhub" \
  SPRING_DATASOURCE_USERNAME=taskhub \
  SPRING_DATASOURCE_PASSWORD="$APP_DB_PASSWORD" \
    ./mvnw -B -ntp -Dmaven.repo.local="$M2_DIR" verify
}

stage_package() {
  docker build -f "$WORK/src/docker/Dockerfile" -t "taskhub:ci-local-${SHA7}" "$WORK/src"
  docker image ls "taskhub:ci-local-${SHA7}"
}

run_stage checkout   stage_checkout
run_stage services   stage_services
run_stage build-test stage_build_test
run_stage package    stage_package
```

```bash
chmod +x ci-local.sh
bash -n ci-local.sh && echo "Cú pháp OK"
```

Trước khi chạy, tự trả lời (viết vào nhật ký):

1. Vì sao `services` đứng trước `build-test`?
2. Nếu `build-test` đỏ, `package` có chạy không? Dòng nào trong script đảm bảo điều đó?
3. Vì sao biến môi trường `SPRING_DATASOURCE_*` được đặt ngay trước `./mvnw` thay vì `export` ở đầu script?

### Bước 3 — Chạy lần 1: runner "lạnh" `[WSL]`

```bash
cd ~/devops-lab/05-cicd
./ci-local.sh 2>&1 | tee run-1.log
```

Lần đầu, `M2_DIR` rỗng → Maven tải toàn bộ thư viện; Docker có thể phải kéo `postgres:17` và base image. Ghi lại thời gian từng stage:

```bash
grep -E '^=== .*OK sau|PIPELINE' run-1.log
```

Đầu ra minh họa (số giây trên máy bạn sẽ khác):

```text
=== checkout: OK sau 0s ===
=== services: OK sau 6s ===
=== build-test: OK sau 151s ===
=== package: OK sau 204s ===
PIPELINE XANH — tổng 361s
```

### Bước 4 — Chạy lần 2: có cache `[WSL]`

```bash
./ci-local.sh 2>&1 | tee run-2.log
grep -E '^=== .*OK sau|PIPELINE' run-2.log
```

Đầu ra minh họa:

```text
=== checkout: OK sau 0s ===
=== services: OK sau 3s ===
=== build-test: OK sau 34s ===
=== package: OK sau 9s ===
PIPELINE XANH — tổng 46s
```

Điền bảng vào nhật ký:

| Stage | Lần 1 (lạnh) | Lần 2 (có cache) | Cache nào giúp? |
|---|---|---|---|
| build-test | | | |
| package | | | |

Gợi ý quan sát: lần 2 `build-test` nhanh nhờ `M2_DIR` đã có thư viện; `package` nhanh nhờ **layer cache** của Docker (log có nhiều dòng `CACHED`). Runner GitHub mới tinh thì **không** có cả hai — đó là lý do bài 02 và 03 cấu hình cache.

> Lưu ý: bên trong `docker build`, stage `build` của Dockerfile chạy Maven **lần nữa** với kho thư viện riêng trong layer. Nghĩa là thư viện Maven được tải hai nơi. Đây là đánh đổi có chủ đích của thiết kế ở Docker bài 03: image tự build được từ source, không phụ thuộc máy build.

### Bước 5 — Thí nghiệm: CI chỉ thấy những gì đã commit `[WSL]`

Sửa **tạm** một test để nó đỏ, **không commit**:

```bash
cd ~/projects/taskhub/app
grep -n 'isCreated()' src/test/java/com/taskhub/TaskControllerTest.java
```

Mở file trong editor, đổi `status().isCreated()` thành `status().isOk()`, lưu lại. Rồi:

```bash
./mvnw -B -ntp test -Dtest=TaskControllerTest ; echo "exit=$?"
```

Kết quả mong đợi: test **đỏ**, `exit=1`. Giờ chạy "CI":

```bash
cd ~/devops-lab/05-cicd && ./ci-local.sh 2>&1 | tail -3
```

Kết quả mong đợi: **XANH**. Vì sao? Bản clone chỉ có commit HEAD, không có thay đổi chưa commit của bạn.

Trường hợp ngược lại phổ biến hơn nhiều ngoài đời: máy bạn **xanh** nhờ một file chưa commit, còn CI **đỏ**. Cả hai chiều đều có chung một nguyên nhân.

Hoàn tác thay đổi — chỉ đúng file đã sửa:

```bash
cd ~/projects/taskhub
git diff --stat                                              # chỉ thấy đúng 1 file
git restore app/src/test/java/com/taskhub/TaskControllerTest.java
git status --porcelain                                       # rỗng
```

> ⚠️ `git restore <file>` **xóa vĩnh viễn** thay đổi chưa commit của file đó. Luôn xem `git diff --stat` trước để chắc chỉ có thay đổi thí nghiệm.

### Bước 6 — Thí nghiệm: fail fast `[WSL]`

Giả lập ứng dụng dùng sai mật khẩu database:

```bash
cd ~/devops-lab/05-cicd
APP_DB_PASSWORD=sai-mat-khau ./ci-local.sh 2>&1 | tee run-fail.log ; echo "exit=${PIPESTATUS[0]}"
```

Vì sao `PIPESTATUS[0]` mà không phải `$?`: lệnh cuối của pipe là `tee`, luôn thành công. `PIPESTATUS[0]` là exit code của lệnh **đầu** trong pipe ([Linux bài 06](../01-LINUX/06-bash-scripting.md)).

Kiểm tra:

```bash
grep -E '^=== STAGE|PIPELINE' run-fail.log
grep -m1 -E 'password authentication failed' run-fail.log
docker ps --filter name=ci-local-pg --format '{{.Names}}'   # rỗng — trap đã dọn
```

Đầu ra minh họa:

```text
=== STAGE: checkout ===
=== STAGE: services ===
=== STAGE: build-test ===
PIPELINE ĐỎ tại stage 'build-test' (exit 1) — tổng 41s
```

Không có `=== STAGE: package ===`: pipeline **dừng ở bước lỗi đầu tiên**, không tốn thời gian build image cho code chưa qua test.

### Bước 7 — Thiết kế pipeline thật cho `taskhub` trên giấy

Không mở file tham khảo. Điền bảng sau vào nhật ký (hoặc `docs/` của repo journal):

| Sự kiện | Stage chạy (theo thứ tự) | Có push image không? Tag gì? | Thời gian mục tiêu |
|---|---|---|---|
| Mở hoặc cập nhật PR vào `main` | | | |
| Merge PR vào `main` (push lên `main`) | | | |
| Push tag `v0.3.0` | | | |
| 🟨 Hằng đêm (lịch cố định) | | | |

Và trả lời:

1. Release `v0.3.0` có nên build lại image không? Vì sao?
2. Job nào cần quyền ghi vào registry? Job nào không cần?
3. PR từ người lạ (fork) có nên được push image không?

Giữ lại bảng này. Sau bài 03, bạn sẽ đối chiếu với [bản tham khảo](labs/reference/README.md).

### Bước 8 — Dọn dẹp `[WSL]`

```bash
docker image ls taskhub --format '{{.Repository}}:{{.Tag}}  {{.Size}}'
docker image ls --filter 'reference=taskhub:ci-local-*' --format '{{.Repository}}:{{.Tag}}' \
  | xargs -r docker image rm                 # xóa theo tên:tag, chỉ các image do script tạo
docker ps -a --filter name=ci-local-pg       # không còn container nào
ls -d /tmp/ci-local.* 2>/dev/null || echo "Không còn thư mục tạm"
```

Giữ lại `~/devops-lab/05-cicd/m2-cache` nếu muốn chạy lại cho nhanh. Muốn giả lập runner lạnh lần nữa: `rm -rf ~/devops-lab/05-cicd/m2-cache` (chỉ xóa cache của bài này, không đụng `~/.m2`).

Ghi vào `troubleshooting-journal.md` mọi lỗi bạn gặp trong bài ([mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md)).

---

## 10. Kết quả mong đợi

- [ ] `ci-local.sh` chạy xanh, in thời gian từng stage và tạo image `taskhub:ci-local-<sha7>`.
- [ ] Có bảng so sánh thời gian lần lạnh và lần có cache, giải thích được cache nào giúp stage nào.
- [ ] Bước 5: giải thích được vì sao máy đỏ mà "CI" xanh (và ngược lại).
- [ ] Bước 6: pipeline đỏ đúng ở `build-test`, không chạy `package`, không còn container PostgreSQL sót lại.
- [ ] Có bảng thiết kế pipeline cho 3–4 sự kiện, trả lời 3 câu hỏi ở Bước 7.
- [ ] Phân biệt được Continuous Integration / Delivery / Deployment bằng ví dụ `taskhub`.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `Cannot connect to the Docker daemon` ở stage `services` | Docker Desktop chưa chạy | Mở Docker Desktop, chờ *Engine running* |
| `Bind for 127.0.0.1:55432 failed: port is already allocated` | Lần chạy trước bị dừng đột ngột còn container, hoặc process khác dùng port | `docker ps --filter name=ci-local-pg`; xóa container sót; hoặc `PG_PORT=55433 ./ci-local.sh` |
| `fatal: repository '/home/.../projects/taskhub' does not exist` | Repo không ở đường dẫn mặc định | `REPO=/đường/dẫn/thật ./ci-local.sh` |
| `./mvnw: Permission denied` ở `build-test` | `mvnw` bị commit **không có** quyền thực thi — máy bạn chạy được vì bạn đã `chmod +x` tay sau đó | `git update-index --chmod=+x app/mvnw` rồi commit. Đây chính là lỗi kiểu "máy chạy được, CI không" |
| `Connection to localhost:55432 refused` | PostgreSQL chưa sẵn sàng hoặc port publish không tới được WSL | Xem `docker logs <tên container>`; tăng số vòng chờ; thử bỏ `127.0.0.1:` trong `-p` |
| `password authentication failed for user "taskhub"` | Cố ý ở Bước 6, hoặc gõ sai `DB_PASSWORD` | Đúng như mong đợi ở Bước 6; nếu không phải Bước 6 thì kiểm tra biến |
| `package` báo `COPY failed: ... not found` | File cần cho image chưa được commit | `git status` ở repo gốc; commit file thiếu |
| Lần 2 vẫn chậm như lần 1 | Đã xóa `m2-cache`, hoặc đổi `M2_DIR`; Docker cache bị `docker builder prune` | Kiểm tra `ls ~/devops-lab/05-cicd/m2-cache` |

---

## 12. Đọc log và xử lý lỗi

Log pipeline thật (bài 02) dài hàng nghìn dòng. Kỹ năng quan trọng nhất: **tìm ra bước lỗi đầu tiên và dòng lỗi gốc**, không đọc từ trên xuống.

### Quy trình 4 bước

1. **Bước nào đỏ?** Script này in `PIPELINE ĐỎ tại stage '...'`. GitHub Actions đánh dấu bước đỏ bằng dấu ✗.
2. **Trong bước đó, lỗi đầu tiên ở đâu?** Tìm từ khóa theo công cụ:

   | Công cụ | Từ khóa |
   |---|---|
   | Maven | `BUILD FAILURE`, `[ERROR]`, `Tests run: ..., Failures: [1-9]` |
   | Spring Boot | `APPLICATION FAILED TO START`, dòng `Caused by:` **cuối cùng** |
   | Docker build | `ERROR [stage x/y]`, `failed to solve` |
   | Bash | `command not found`, `Permission denied`, `No such file` |

3. **Nguyên nhân gốc là gì?** Phân biệt **triệu chứng** ("test đỏ") với **nguyên nhân** ("app không kết nối được database vì sai mật khẩu").
4. **Vì sao máy mình không bị?** Câu hỏi này thường dẫn thẳng tới đáp án: file chưa commit, biến môi trường chỉ có trên máy, cache, phiên bản khác.

### Ví dụ: đọc `run-fail.log` của Bước 6

```bash
grep -n -E 'BUILD FAILURE|Tests run:.*(Failures|Errors): [1-9]|Caused by:' run-fail.log | head
```

Đầu ra minh họa (rút gọn):

```text
212:Caused by: org.postgresql.util.PSQLException: FATAL: password authentication failed for user "taskhub"
240:[ERROR] Tests run: 4, Failures: 0, Errors: 1, Skipped: 0
251:[INFO] BUILD FAILURE
```

Đọc ngược lên: `BUILD FAILURE` (triệu chứng) ← có 1 test **Errors** (không phải Failures: test không chạy xong được, khác với chạy xong mà sai kết quả) ← `Caused by: ... password authentication failed` (nguyên nhân gốc). Sửa ở cấu hình, không phải ở code test.

> **Failures** = test chạy xong nhưng kết quả sai (assert không đạt). **Errors** = test ném exception, không chạy xong (thường do môi trường: database, cấu hình). Phân biệt hai loại này giúp bạn biết nên nhìn vào code hay vào môi trường.

### Khi CI đỏ còn máy bạn xanh — checklist

- [ ] `git status` ở máy: có file chưa commit không?
- [ ] File có trong `.gitignore` nhưng code cần (ví dụ `.env`)?
- [ ] Quyền thực thi (`mvnw`, script `.sh`) có được commit không?
- [ ] Biến môi trường nào máy có mà CI không có?
- [ ] Phiên bản Java/Maven/base image có giống nhau không?
- [ ] Test có phụ thuộc thứ tự chạy, giờ hệ thống, múi giờ không?

---

## 13. Câu hỏi kiểm tra kiến thức

1. "Integration hell" là gì? Vì sao tích hợp **thường xuyên hơn** lại giảm rủi ro, dù nghe như phải làm nhiều việc hơn?
2. Một team dùng GitHub Actions nhưng mỗi nhánh feature sống 3 tuần. Họ có đang làm Continuous Integration không? Vì sao?
3. Phân biệt Continuous Delivery và Continuous Deployment. `taskhub` v1 thuộc loại nào?
4. Artifact là gì? Kể các artifact của pipeline `taskhub` và chỉ ra artifact nào là **artifact triển khai**.
5. Giải thích nguyên tắc "build một lần, triển khai nhiều nơi". Nêu một cách vi phạm nguyên tắc này dù vẫn build từ cùng một commit.
6. Vì sao GitHub-hosted runner là máy ảo mới cho mỗi lần chạy? Nêu 2 lợi ích và 2 cái giá phải trả.
7. Job và step khác nhau thế nào? File tạo ra ở job A có dùng được ở job B không?
8. Trong `ci-local.sh`, vì sao phải `git clone` sang thư mục tạm thay vì chạy thẳng trong `~/projects/taskhub`?
9. Exit code quyết định trạng thái xanh/đỏ của pipeline thế nào? Vì sao script pipeline phải có `set -e` (hoặc tương đương)?
10. "Fail fast" là gì? Vì sao test chạy trước build image?
11. Pipeline mất 40 phút gây hại gì cho team? Nêu 3 kỹ thuật rút ngắn.
12. Shift-left security nghĩa là gì? Nêu 2 ví dụ trong pipeline `taskhub`.
13. Pipeline as code có lợi gì so với cấu hình pipeline bằng giao diện web?
14. Kể tên các chỉ số DORA hiện tại, chỉ ra chỉ số nào đo tốc độ và chỉ số nào đo độ ổn định. "Four keys" cũ khác gì?
15. Trong log Maven, `Failures` và `Errors` khác nhau thế nào? Mỗi loại gợi ý bạn nên nhìn vào đâu?

---

## 14. Bài tập tự làm

> Lời giải ở [solutions/01-solutions.md](solutions/01-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Phân loại.** Mỗi tình huống dưới đây là CI, Continuous Delivery, Continuous Deployment hay không phải cái nào? Giải thích ngắn.

a) Mỗi PR chạy unit test tự động; merge xong, trưởng nhóm build tay file jar gửi khách.
b) Merge vào `main` → pipeline test, build image, push registry, tự deploy lên production, không ai duyệt.
c) Merge vào `main` → pipeline test, build image, deploy staging. Lên production khi PO bấm nút "Approve" trên pipeline.
d) Dev chạy `./mvnw test` trên máy trước khi push. Không có pipeline nào.
e) Pipeline chạy test **hằng đêm** trên nhánh `develop`; các nhánh feature sống 2–3 tuần.
f) Merge vào `main` → pipeline test, build image, push registry. Deploy do một script chạy tay trên server mỗi thứ Năm.

**Bài 2 — Tính chỉ số DORA.** Dữ liệu deploy production của một team trong 2 tuần (10 ngày làm việc):

| # | Merge vào `main` | Deploy production | Kết quả |
|---|---|---|---|
| 1 | T2 tuần 1, 09:00 | T2, 11:00 | OK |
| 2 | T2 tuần 1, 14:00 | T3, 10:00 | OK |
| 3 | T4 tuần 1, 10:00 | T4, 11:00 | Lỗi → rollback về bản trước xong lúc 11:30 |
| 4 | T4 tuần 1, 13:00 | T4, 14:00 | OK |
| 5 | T5 tuần 1, 09:00 | T6, 09:00 | OK |
| 6 | T2 tuần 2, 10:00 | T2, 12:00 | OK |
| 7 | T3 tuần 2, 15:00 | T4, 09:00 | Lỗi → khắc phục bằng hotfix #8 |
| 8 | T4 tuần 2, 12:00 | T4, 13:00 | OK — hotfix ngoài kế hoạch cho sự cố của #7 |
| 9 | T5 tuần 2, 10:00 | T5, 11:00 | OK |
| 10 | T6 tuần 2, 09:00 | T6, 10:00 | OK |

Tính (coi "merge vào `main`" là thời điểm commit cho đơn giản): deployment frequency, change lead time (cả **trung bình** và **trung vị** — giải thích vì sao khác nhau nhiều), change fail rate, failed deployment recovery time của từng lần lỗi, deployment rework rate. Sau đó đề xuất **một** thay đổi quy trình có tác động lớn nhất và giải thích dựa trên số liệu.

**Bài 3 — Sắp xếp lại pipeline chậm.** Một pipeline hiện chạy tuần tự:

| Bước | Thời gian | Tỉ lệ làm pipeline đỏ |
|---|---|---|
| Build Docker image | 6 phút | 2% |
| Test tích hợp (cần database) | 8 phút | 10% |
| Push image lên registry | 1 phút | 1% |
| Unit test | 2 phút | 15% |
| Lint code | 1 phút | 20% |
| Quét lỗ hổng image | 2 phút | 5% |

Đề xuất thứ tự mới (được phép chạy song song), tính thời gian tối thiểu cho một PR, và chỉ ra bước nào **không nên** chạy trên PR. Giải thích từng quyết định.

**Bài 4 — Tìm vi phạm.** Đọc quy trình sau và chỉ ra ít nhất **4** vấn đề so với nội dung bài học:

> "Mỗi tối, server Jenkins (chạy 2 năm chưa cài lại) pull nhánh `develop`, build image và push với tag `latest`. Muốn lên production, anh Nam SSH vào server production, `git pull`, rồi `docker build` và `docker compose up -d`. Mật khẩu registry được ghi trong file cấu hình job Jenkins để tiện."

**Bài 5 — Mở rộng `ci-local.sh`.** Thêm stage `scan` sau `package`: quét image `taskhub:ci-local-<sha7>` bằng Trivy chạy trong container (cách chạy như [Docker bài 07](../04-DOCKER/07-docker-security.md)), sao cho **pipeline đỏ** khi có lỗ hổng mức `CRITICAL` **đã có bản vá**. Gợi ý: tra `trivy image --help` để tìm cờ đặt exit code và cờ bỏ qua lỗ hổng chưa có bản vá. Chạy thử và ghi lại thời gian của stage mới ở lần đầu và lần sau.

**Bài 6 — Trình bày.** Viết đoạn trình bày khoảng 1 phút (150–200 từ) trả lời câu phỏng vấn: *"CI/CD là gì, và vì sao một team nhỏ 3 người cũng nên có?"*. Không dùng thuật ngữ nào mà bạn không giải thích được nếu bị hỏi lại.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Giải thích được cho người không biết kỹ thuật: CI giải quyết vấn đề gì, trong 2 phút.
- [ ] Vẽ được trục "CI → Continuous Delivery → Continuous Deployment" và đặt `taskhub` v1, v3 lên đó.
- [ ] Giải thích được vì sao release không build lại image, và hậu quả nếu build lại.
- [ ] Giải thích được bằng ví dụ của chính bạn (Bước 5) vì sao "máy tôi chạy được" không có nghĩa CI sẽ xanh.
- [ ] Đọc một log đỏ, chỉ ra bước lỗi, dòng lỗi gốc, phân biệt được `Failures` với `Errors`.
- [ ] Tính được các chỉ số DORA từ một bảng dữ liệu và rút ra nhận xét.
- [ ] Có bảng thiết kế pipeline `taskhub` sẵn sàng để hiện thực hóa ở bài 02–03.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Martin Fowler — Continuous Integration](https://martinfowler.com/articles/continuousIntegration.html) | Định nghĩa CI, danh sách thực hành, "integration hell" | 2026-10-31 |
| [continuousdelivery.com](https://continuousdelivery.com/) (Jez Humble) | Định nghĩa Continuous Delivery | 2026-10-31 |
| [DORA — Software delivery performance metrics](https://dora.dev/guides/dora-metrics/) | 5 chỉ số hiện tại, nhóm throughput/instability | 2026-10-31 |
| [DORA — History of the metrics](https://dora.dev/insights/dora-metrics-history/) | Thay đổi năm 2023 (recovery time) và 2024 (rework rate) | 2026-10-31 |
| [GitHub Docs — Understanding GitHub Actions](https://docs.github.com/en/actions/get-started/understand-github-actions) | Workflow, event, job, action, runner | 2026-10-31 |
| [GitHub Docs — GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners) | Mỗi runner là một máy ảo mới | 2026-10-31 |
| [docker-library/postgres — docker-entrypoint.sh (bản 17)](https://github.com/docker-library/postgres/blob/master/17/bookworm/docker-entrypoint.sh) | Server tạm lúc init với `listen_addresses=''` | 2026-10-31 |
