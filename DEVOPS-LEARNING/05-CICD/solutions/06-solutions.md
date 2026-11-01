# Lời giải — Bài 06: Jenkins và GitLab CI (mức nhận biết)

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Username `phuong-dev` là ví dụ.

Quay lại bài: [06-jenkins-gitlab-overview.md](../06-jenkins-gitlab-overview.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài thực hành (mục 9)](#phần-b--bài-thực-hành-mục-9)
- [Phần C — Bài tập tự làm (mục 14)](#phần-c--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. GitLab phân biệt job với từ khóa thế nào?**
GitLab có danh sách **từ khóa toàn cục** (`stages`, `variables`, `default`, `workflow`, `include`…). Mọi khóa cấp cao nhất **không** thuộc danh sách đó được coi là một job. Khóa bắt đầu bằng `.` là job ẩn (dùng làm mẫu, không chạy). Hệ quả: đặt nhầm tên job trùng từ khóa (ví dụ một job tên `variables`) sẽ không chạy như bạn nghĩ.

**2. `postgres:5432` vs `localhost:5432`?**
GitLab (Docker executor): job chạy **trong container**, service là **container khác** nối chung mạng; hostname của service là tên image (`postgres`). `localhost` trong job là chính container job — không có PostgreSQL ở đó. GitHub Actions: job chạy **thẳng trên VM** runner; service container được map cổng `5432:5432` ra VM → `localhost:5432`. Cùng nguyên lý namespace mạng ở [Docker bài 04](../../04-DOCKER/04-volumes-networks-env.md).

**3. `only`/`except` vs `rules`?**
Tài liệu GitLab ghi `only`/`except` đã **deprecated**, khuyên dùng `rules`. Gặp trong dự án cũ: đọc hiểu, không viết thêm cấu hình mới bằng nó; khi có dịp sửa pipeline thì chuyển sang `rules` trong một MR riêng, kiểm tra pipeline vẫn được tạo đúng các trường hợp (MR, main, tag).

**4. `CI_REGISTRY_PASSWORD` sống bao lâu?**
Bằng `CI_JOB_TOKEN` — chỉ hợp lệ **trong lúc job chạy**. Bị lộ trong log thì cửa sổ lợi dụng rất ngắn. PAT tạo tay (Docker bài 06) sống tới khi hết hạn bạn đặt (có thể hàng tháng) → lộ là kẻ xấu push/pull được suốt thời gian đó cho tới khi bạn thu hồi. Cùng lý do GitHub Actions dùng `GITHUB_TOKEN` tự sinh, tự hết hạn.

**5. Controller vs agent; vì sao executor của built-in node = 0?**
Controller: process Jenkins chính — UI, cấu hình, credential, lập lịch. Agent: nơi chạy build. Build chạy trên built-in node có **cùng quyền file** với process Jenkins → script build (do bất kỳ ai sửa được `Jenkinsfile` viết) có thể đọc `$JENKINS_HOME`, gồm credential đã mã hóa và khóa giải mã. Đặt executor = 0 buộc mọi build ra agent riêng.

**6. `stages`/`steps`/`post` ↔ GitHub Actions?**
`stages` ~ danh sách job (nhưng chạy tuần tự theo thứ tự viết, giống job nối nhau bằng `needs`). Mỗi `stage` ~ một job. `steps` ~ các step (`run:`). `post { always/failure/success }` ~ step có `if: always()` / `if: failure()` / `if: success()`.

**7. Nháy đơn vs nháy kép trong `sh`?**
Nháy kép: Groovy thay `${GHCR_PSW}` **trước** khi gọi shell → mật khẩu nằm trong chuỗi lệnh Groovy (Jenkins còn cảnh báo về việc này), có thể lộ qua log, danh sách process, và nếu giá trị chứa ký tự đặc biệt thì phá vỡ lệnh. Nháy đơn: Groovy để nguyên `$GHCR_PSW`, **shell** đọc từ biến môi trường lúc chạy. Cùng bản chất với lỗi chèn `${{ }}` vào `run:` trong GitHub Actions.

**8. Ba việc phải tự làm với Jenkins?** (bất kỳ 3)
Cập nhật Jenkins core + Java + plugin (vá lỗ hổng); sao lưu `$JENKINS_HOME`; dọn dẹp và giữ agent sạch (agent dùng lại giữa các build); bảo vệ web UI (TLS, không phơi ra Internet, phân quyền); theo dõi dung lượng đĩa, RAM của controller; cấp và xoay vòng credential dài hạn.

**9. Vì sao Docker trong CI nguy hiểm?**
dind cần container `--privileged` (gần như bỏ hết cô lập); mount `/var/run/docker.sock` cho process trong container điều khiển Docker daemon của host → `docker run -v /:/host …` là có root trên host. Server CI chứa credential deploy → bị chiếm là mất cả hệ thống. GitHub-hosted runner: mỗi job một **VM riêng, dùng một lần**, xóa sau khi xong; `docker build` chạy thẳng trên VM đó, không có gì để "thoát" sang job khác hay sang hạ tầng của bạn.

**10. Hai khác biệt hành vi khi chuyển GitHub Actions → GitLab** (bất kỳ 2)
- Hostname service: `localhost` → tên service.
- Độ dài short SHA: 7 (quy ước taskhub) → `CI_COMMIT_SHORT_SHA` 8 → tag image không khớp, bước release "không tìm thấy image".
- Build image cần dind + runner privileged.
- `default:` của GitLab **thay thế** chứ không gộp với giá trị của job; `needs` và `stages` tương tác khác với `needs` của Actions.
- Pipeline có được tạo hay không do `workflow: rules`, không phải `on:` — thiếu một dòng `if` là MR không có pipeline.

---

## Phần B — Bài thực hành (mục 9)

### Phần A của lab — đọc hiểu GitLab

| Job | Chạy khi | Container / service | Biến, secret | Tương ứng `ci.yml` |
|---|---|---|---|---|
| `build-test` | Mọi pipeline được tạo (MR hoặc main) — do `workflow: rules` | `eclipse-temurin:21-jdk-noble` + service `postgres:17` | `POSTGRES_*`, `SPRING_DATASOURCE_*` (bạn khai báo; mật khẩu chỉ dùng cho DB tạm), `MAVEN_OPTS` | Job `build-test` |
| `image` | Mọi pipeline; **push chỉ khi** `CI_COMMIT_BRANCH == CI_DEFAULT_BRANCH` (dòng `if` trong `script`) | `docker:24.0.5-cli` + service `docker:24.0.5-dind` | `CI_REGISTRY_USER/PASSWORD` (GitLab định nghĩa sẵn, sống theo job), `IMAGE` | Job `image` (bước build + push) |
| `scan` | Chỉ main (`rules`) | `aquasec/trivy:0.76.1`, ghi đè entrypoint | `TRIVY_USERNAME/PASSWORD` lấy từ `CI_REGISTRY_*` để kéo image | Bước Trivy trong job `image` |

**3 khác biệt hành vi** (ví dụ): (1) GitLab push **trước** rồi mới quét → image có lỗ hổng CRITICAL vẫn nằm trên registry dù pipeline đỏ; GitHub quét trước, đỏ thì không push. (2) Trên MR, bản GitLab **không quét** (job `scan` chỉ chạy ở main); bản GitHub quét cả trên PR → phát hiện sớm hơn. (3) Tag image 8 ký tự vs 7 ký tự.

**MR từ `feat/x`:** pipeline được tạo (dòng `merge_request_event`). `build-test` chạy. `image` chạy nhưng `CI_COMMIT_BRANCH` **không được đặt** trong pipeline MR (theo tài liệu biến định nghĩa sẵn) → so sánh `"" = "main"` sai → không push. `scan` không được tạo vì `rules` chỉ khớp nhánh mặc định. Kết luận: không push.

### Phần B của lab — Jenkins

Bảng ánh xạ mong đợi (theo `Jenkinsfile` của tutorial): `agent` ~ `runs-on`; `stage('Build')`, `stage('Test')`, `stage('Deliver')` ~ ba job/nhóm step; `sh 'mvn …'` ~ `run:`; `post { always { junit … } }` ~ step upload báo cáo với `if: always()`.

Bằng chứng nơi chạy: dòng `Running on <tên node> in <workspace>` trong Console Output. Nếu thấy `Running on Jenkins` (built-in node) → build đang chạy trên controller — điều tài liệu bảo mật khuyên tránh; tutorial dùng agent riêng nên thường thấy tên agent.

Build đỏ ở bước 4: dòng `Tests run: …, Failures: 1`, kèm tên test và giá trị expected/actual; các stage sau bị `skipped due to earlier failure(s)` — là hệ quả.

---

## Phần C — Bài tập tự làm (mục 14)

**1. Khảo sát thị trường.** Không có đáp án — kết quả phụ thuộc thời điểm và nguồn. Đạt khi: có bảng 20 tin (link hoặc tên công ty + ngày), đếm rõ ràng, kết luận chỉ nói điều dữ liệu cho thấy ("8/20 tin nhắc Jenkins") và nêu giới hạn (mẫu nhỏ, một thời điểm, có tin ghi nhiều công cụ).

**2. Dịch ngược `release.yml` sang GitLab.** Một bản đạt:

```yaml
promote:
  stage: release
  image: docker:24.0.5-cli
  services:
    - docker:24.0.5-dind
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: "/certs"
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login $CI_REGISTRY -u $CI_REGISTRY_USER --password-stdin
  script:
    - docker buildx imagetools inspect "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
    - docker buildx imagetools create --tag "$CI_REGISTRY_IMAGE:$CI_COMMIT_TAG" "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
```

Điểm chấm: điều kiện tag đúng; dùng cùng độ dài SHA với job đã push image (8 ký tự nếu job build cũng dùng `CI_COMMIT_SHORT_SHA`); ghi rõ phần chưa kiểm chứng (image `docker:*-cli` có kèm buildx hay không; tạo GitLab Release dùng `release-cli`/từ khóa `release:` — cần tra thêm). Bài trung thực về chỗ chưa chắc được điểm cao hơn bài "trông đầy đủ" nhưng bịa.

**3. Đọc Jenkinsfile lạ.** Đạt khi chú thích được mọi khối, chỉ ra nơi gọi credential (`credentials()`, `withCredentials`), và kiểm tra chèn chuỗi: bất kỳ `sh "…${SECRET}…"` (nháy kép + biến secret) là phát hiện cần ghi lại.

**4. Câu trả lời phỏng vấn — khung mẫu (diễn đạt bằng lời của bạn):**
"Khái niệm CI tôi đã làm thật: pipeline chạy mỗi PR, test với database tạm, build image, quét lỗ hổng, push theo tag SHA, release bằng tag SemVer. Sang Jenkins, tôi ánh xạ: workflow → Jenkinsfile, job → stage, runner → agent, `secrets` → Credentials store, `if: failure()` → `post { failure }`. Tôi đã chạy Jenkins bằng Docker theo tutorial chính thức và đọc được Console Output. Tuần đầu tôi sẽ đọc Jenkinsfile hiện có, hỏi agent chạy ở đâu và credential quản lý thế nào. Một điểm tôi sẽ để ý là bảo mật: build không chạy trên controller, không chèn secret bằng nháy kép, và cẩn thận với Docker socket trên agent."
Đạt khi có ≥ 3 ánh xạ, ≥ 1 rủi ro riêng của Jenkins, và không nói quá kinh nghiệm thật.
