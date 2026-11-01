# 06. Jenkins và GitLab CI — mức nhận biết

> ⏱️ ~6 giờ, chia hai phần: **Phần GitLab CI ~2 giờ (tuần 10)** · **Phần Jenkins ~4 giờ (tuần 22)**
> Mức độ: 🟨 Nên biết (đọc hiểu được, không cần viết thành thạo) · Kiến thức cần có trước: [02. GitHub Actions cơ bản](02-github-actions-basics.md), [03. Build & push image](03-github-actions-docker-registry.md), [04. Secrets & environments](04-secrets-environments.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop (chỉ phần Jenkins), trình duyệt `[Jenkins UI]`

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

> **Cách học bài này.** Tuần 10 chỉ học **mục 3.1, 4.1–4.4, 5.1 và lab Phần A** (GitLab CI). Phần Jenkins (**mục 3.2, 4.5–4.9, 5.2 và lab Phần B**) để đến **tuần 22**, khi bạn đã có kinh nghiệm thật với GitHub Actions. Lúc đó bạn sẽ nhận ra hầu hết khái niệm đều giống nhau, chỉ khác tên gọi.

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- **Đọc hiểu** một file `.gitlab-ci.yml` và một `Jenkinsfile` (Declarative Pipeline): job nào chạy trước, chạy ở đâu, khi nào, dùng secret gì.
- **Ánh xạ** khái niệm giữa GitHub Actions, GitLab CI và Jenkins: workflow ↔ pipeline, job ↔ job/stage, runner ↔ runner/agent, `secrets` ↔ CI/CD variables/credentials.
- Giải thích **khác biệt kiến trúc** quan trọng nhất: GitHub Actions và GitLab.com cho bạn runner dùng một lần; Jenkins là **server bạn tự vận hành** — kèm toàn bộ trách nhiệm bảo mật, cập nhật, sao lưu.
- Chạy Jenkins **trên máy** bằng Docker theo tutorial chính thức, tạo một Pipeline từ `Jenkinsfile`, rồi dọn dẹp sạch.
- Trả lời câu phỏng vấn "Bạn chỉ biết GitHub Actions, vào công ty dùng Jenkins thì sao?" bằng hiểu biết thật, không phải câu xã giao.

**Không phải mục tiêu:** viết thành thạo Groovy, quản trị plugin Jenkins, dựng GitLab self-hosted. Những việc đó học khi đi làm, trên hệ thống của công ty.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Giáo trình chọn GitHub Actions làm công cụ chính ([README Module 05](README.md) và [ADR-0001 trong dự án](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr)). Nhưng khi đi làm:

| Tình huống thật | Bạn cần |
|---|---|
| Công ty có hạ tầng **on-premises**, code nằm trên **GitLab self-hosted** | Đọc `.gitlab-ci.yml`, hiểu runner của công ty chạy ở đâu |
| Hệ thống cũ có Jenkins chạy nhiều năm, hàng chục job | Đọc `Jenkinsfile`, tìm job đỏ vì sao đỏ, biết credential lưu ở đâu |
| Ngày đầu đi làm được giao "pipeline này fail, xem giúp" | Nhận ra **stage / step / agent / post** tương ứng với cái gì bạn đã biết |
| Phỏng vấn hỏi "Đã dùng Jenkins chưa?" | Trả lời trung thực: "Tôi dùng GitHub Actions cho dự án, đã chạy Jenkins trên máy và đọc hiểu Jenkinsfile; khái niệm X ở Actions tương ứng Y ở Jenkins" |

**Quan sát về thị trường Việt Nam** (hãy tự kiểm chứng, đừng tin con số của ai): khi đọc tin tuyển dụng DevOps trên các trang như ITviec hay TopDev, bạn sẽ thường thấy **Jenkins** và **GitLab CI** xuất hiện bên cạnh GitHub Actions — nhất là ở công ty outsourcing, ngân hàng, công ty có hệ thống on-premises hoặc dùng GitLab tự host. [Bài tập 14.1](#14-bài-tập-tự-làm) yêu cầu bạn tự đếm trên 20 tin tuyển dụng thật.

Tin tốt: **bản chất CI/CD không đổi**. Checkout → build → test → đóng gói → quét → đẩy → deploy. Bạn đã hiểu bản chất ở [bài 01](01-cicd-concepts.md); bài này chỉ dạy bạn "đọc phương ngữ khác".

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. 🟨 GitLab CI/CD — tuần 10

- **GitLab**: nền tảng quản lý mã nguồn tương tự GitHub (repo, Merge Request, issue, registry). Có bản dịch vụ `gitlab.com` và bản **tự host** (self-managed) mà nhiều công ty cài trong mạng nội bộ.
- **`.gitlab-ci.yml`**: **một** file ở gốc repo mô tả toàn bộ pipeline. (GitHub Actions: nhiều file trong `.github/workflows/`.)
- **Pipeline**: một lần chạy, gồm nhiều **job** xếp theo **stage**.
- **Stage** (giai đoạn): các job cùng stage chạy song song; stage sau chỉ bắt đầu khi stage trước xong. Mặc định có `.pre`, `build`, `test`, `deploy`, `.post`.
- **Job**: đơn vị chạy, gồm `script` (các lệnh shell) và chạy trong `image` (container) do bạn chọn.
- **GitLab Runner**: chương trình nhận job và chạy nó. Trên gitlab.com có runner dùng chung; công ty tự host thường tự cài runner trên server của mình.
- **Merge Request (MR)**: tên của Pull Request trong GitLab.

### 3.2. 🟨 Jenkins — tuần 22

- **Jenkins**: server tự động hóa mã nguồn mở, viết bằng Java, ra đời từ khoảng 2011 (tách ra từ dự án Hudson). Bạn **tự cài, tự vận hành**.
- **Controller** (trước đây gọi là *master*): process Jenkins chính — giao diện web, lưu cấu hình, lập lịch build.
- **Agent** (node): máy hoặc container thực sự chạy build. Mỗi agent có một số **executor** (số build chạy đồng thời).
- **Plugin**: gần như mọi tính năng (Git, Pipeline, Docker, credential…) là plugin. Jenkins mạnh nhờ plugin và **cũng rủi ro** vì plugin — mỗi plugin là thêm mã cần cập nhật bản vá.
- **Job / Project**: loại cũ là *Freestyle* (cấu hình bằng giao diện web); loại hiện đại là **Pipeline** — định nghĩa bằng file **`Jenkinsfile`** trong repo (*Pipeline as Code*).
- **Declarative Pipeline** vs **Scripted Pipeline**: Declarative có cấu trúc cố định (`pipeline { agent … stages { … } }`), dễ đọc — **bài này chỉ dạy loại này**. Scripted là Groovy tự do, gặp trong hệ thống cũ.
- **Multibranch Pipeline**: Jenkins tự quét repo, tạo một pipeline cho **mỗi nhánh/PR** có `Jenkinsfile` — gần với cách GitHub Actions chạy trên mọi nhánh.
- **LTS** (Long-Term Support): kênh phát hành ổn định. Theo trang LTS của Jenkins, cứ **12 tuần** chọn một bản làm baseline, sau đó ra các bản vá `.1`, `.2`, `.3`. Tại thời điểm viết (2026-10-31), bản LTS mới nhất là **2.580.2** (phát hành 2026-10-28) và **yêu cầu Java 21** — Java 17 không còn được hỗ trợ từ 2.555.1.

### 3.3. Ba công cụ cùng một bản chất

| Khái niệm (bài 01–02) | GitHub Actions | GitLab CI | Jenkins (Declarative) |
|---|---|---|---|
| File định nghĩa | `.github/workflows/*.yml` | `.gitlab-ci.yml` | `Jenkinsfile` (Groovy DSL) |
| Một lần chạy | Workflow run | Pipeline | Build |
| Nhóm công việc | Job | Job (gom theo `stage`) | `stage` |
| Một lệnh | Step (`run:` / `uses:`) | Dòng trong `script:` | Step (`sh`, `junit`…) trong `steps` |
| Thứ tự | `needs:` | `stages:` (+ `needs:` để bỏ qua thứ tự stage) | Thứ tự viết các `stage` |
| Nơi chạy | Runner (`runs-on:`) | Runner (chọn bằng `tags:`), `image:` | Agent (`agent { … }`) |
| Điều kiện | `if:`, `on:` | `rules:`, `workflow: rules:` | `when { … }` |
| Secret | `secrets.X`, `GITHUB_TOKEN` | CI/CD variables (masked/protected), `CI_JOB_TOKEN` | Credentials store + `credentials()` / `withCredentials` |
| Database tạm cho test | `services:` | `services:` | Docker Pipeline: `withRun` (sidecar) |
| File kết quả | `actions/upload-artifact` | `artifacts:` | `archiveArtifacts`, `junit` |
| Cache | `actions/cache`, `setup-java cache:` | `cache:` | Plugin / volume trên agent |
| Làm việc khi lỗi | `if: failure()` | `artifacts: when: on_failure`, `after_script` | `post { failure { … } }` |
| Registry đi kèm | GHCR | GitLab Container Registry | Không có — dùng registry ngoài |

Ghi bảng này vào sổ tay. 80% việc đọc pipeline lạ là tra bảng này.

---

## 4. Giải thích chi tiết

### 4.1. 🟨 Cấu trúc `.gitlab-ci.yml`

```yaml
stages:          # thứ tự các giai đoạn
  - test
  - image

variables:       # biến dùng chung cho mọi job
  APP_DIR: app

unit-test:       # tên job do bạn đặt (không phải từ khóa)
  stage: test
  image: eclipse-temurin:21-jdk-noble   # job chạy TRONG container này
  script:
    - cd "$APP_DIR"
    - ./mvnw -B -ntp verify
```

Khác biệt đầu tiên cần để ý: **tên job nằm ở cấp cao nhất** của file, cạnh các từ khóa như `stages`, `variables`, `default`, `workflow`. GitLab coi mọi khóa cấp cao **không phải từ khóa** là một job. Khóa bắt đầu bằng dấu chấm (`.template`) là job ẩn, dùng làm mẫu.

| Từ khóa | Ý nghĩa | Tương đương GitHub Actions |
|---|---|---|
| `stages` | Danh sách stage theo thứ tự | Không có — dùng `needs:` |
| `default` | Giá trị mặc định cho mọi job (`image`, `before_script`…) — job tự khai báo thì **thay thế**, không gộp | `defaults:` (chỉ cho `run`) |
| `workflow: rules:` | Quyết định **có tạo pipeline hay không** | `on:` |
| `variables` | Biến môi trường (cấp file hoặc cấp job) | `env:` |
| `image` | Container chạy job | `container:` (ít dùng) — Actions thường chạy thẳng trên VM |
| `services` | Container phụ chạy cạnh job (database…) | `services:` |
| `before_script` / `script` / `after_script` | Lệnh trước / chính / sau. `after_script` chạy cả khi job lỗi hoặc bị hủy | Các step `run:` + `if: always()` |
| `rules` | Điều kiện tạo job | `if:` ở cấp job |
| `needs` | Chạy ngay khi job cụ thể xong, không chờ cả stage | `needs:` |
| `artifacts` | File giữ lại sau job (`paths`, `reports: junit`, `expire_in`, `when`) | `upload-artifact` |
| `cache` | Thư mục tái sử dụng giữa các lần chạy (`key: files:`, `paths`) | `actions/cache` |
| `timeout` | Thời gian tối đa của job | `timeout-minutes:` |
| `interruptible` | Cho phép hủy job khi có pipeline mới hơn | `concurrency: cancel-in-progress` |
| `tags` | Chọn runner có nhãn tương ứng | `runs-on:` |
| `environment` | Môi trường deploy | `environment:` |

⚠️ `only` / `except` là cú pháp **đã bị deprecated** theo tài liệu GitLab — dùng `rules`. Bạn vẫn sẽ gặp `only`/`except` trong dự án cũ; đọc hiểu được là đủ.

### 4.2. 🟨 `rules` và biến có sẵn

GitLab cung cấp nhiều **predefined variables** (biến định nghĩa sẵn). Những biến hay gặp nhất:

| Biến | Ý nghĩa | Gần giống ở GitHub Actions |
|---|---|---|
| `CI_PIPELINE_SOURCE` | Nguồn kích hoạt: `push`, `merge_request_event`, `schedule`… | `github.event_name` |
| `CI_COMMIT_BRANCH` | Nhánh kích hoạt (không có trong pipeline MR và pipeline tag) | `github.ref_name` (khi là nhánh) |
| `CI_DEFAULT_BRANCH` | Nhánh mặc định (thường `main`) | `github.event.repository.default_branch` |
| `CI_COMMIT_TAG` | Tên tag — **chỉ có** trong pipeline tag | `github.ref_name` khi `github.ref_type == 'tag'` |
| `CI_COMMIT_SHORT_SHA` | **8** ký tự đầu của SHA | Không có sẵn — taskhub tự cắt **7** ký tự |
| `CI_REGISTRY`, `CI_REGISTRY_IMAGE` | Registry của GitLab và tên image gốc của project | `ghcr.io/${{ github.repository_owner }}/…` |
| `CI_REGISTRY_USER`, `CI_REGISTRY_PASSWORD` | Thông tin đăng nhập registry, **chỉ sống trong thời gian job chạy** (bằng `CI_JOB_TOKEN`) | `github.actor` + `GITHUB_TOKEN` |
| `CI_PROJECT_DIR` | Thư mục chứa code trong job | `github.workspace` |

Ví dụ: chỉ chạy pipeline cho MR, cho nhánh mặc định và cho tag:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
```

Đọc: GitLab duyệt từ trên xuống, gặp điều kiện **đúng đầu tiên** thì tạo pipeline. Không điều kiện nào đúng → không có pipeline.

> 🟨 Chú ý: `CI_COMMIT_SHORT_SHA` dài 8 ký tự, còn quy ước tag image của taskhub là 7 ký tự (theo `metadata-action`). Hai hệ thống "cùng là short SHA" nhưng khác độ dài — loại khác biệt nhỏ này gây lỗi "không tìm thấy image" khi chuyển đổi công cụ.

### 4.3. 🟨 Services, artifacts, cache trong GitLab

**Services:** biến khai báo ở job được truyền vào cả container service, và service được gọi bằng **tên image** làm hostname (`postgres`). Khác với GitHub Actions — ở đó job chạy trực tiếp trên VM nên dùng `localhost:5432` qua port đã map.

```yaml
build-test:
  image: eclipse-temurin:21-jdk-noble
  services:
    - postgres:17
  variables:
    POSTGRES_DB: taskhub
    POSTGRES_USER: taskhub
    POSTGRES_PASSWORD: ci-only-password
    SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/taskhub   # hostname = tên service
```

**Cache Maven:** GitLab chỉ cache được thư mục **nằm trong** thư mục project, nên phải trỏ Maven local repository vào đó:

```yaml
variables:
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"

build-test:
  cache:
    key:
      files:
        - app/pom.xml          # pom.xml đổi → khóa cache đổi → tải lại dependency
    paths:
      - .m2/repository
```

So sánh: `actions/setup-java` với `cache: maven` làm việc này giúp bạn, khóa là hash của `**/pom.xml`.

**Artifacts + báo cáo test:**

```yaml
  artifacts:
    when: always                                   # giữ cả khi job đỏ — lúc đó mới cần nhất
    reports:
      junit: app/target/surefire-reports/TEST-*.xml  # GitLab hiển thị test lỗi ngay trong MR
    expire_in: 7 days
```

### 4.4. 🟨 Build image trong GitLab: Docker-in-Docker

Job GitLab chạy **bên trong** một container. Muốn chạy `docker build` bên trong đó, cách phổ biến trong tài liệu GitLab là **Docker-in-Docker** (dind): thêm service `docker:<phiên bản>-dind` — một Docker daemon riêng chạy trong container.

Các dòng then chốt (theo ví dụ trong tài liệu GitLab, phiên bản `24.0.5` là của ví dụ đó — dự án thật dùng bản hiện hành):

```yaml
  image: docker:24.0.5-cli
  services:
    - docker:24.0.5-dind
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login $CI_REGISTRY -u $CI_REGISTRY_USER --password-stdin
```

⚠️ **dind cần runner chạy ở chế độ `privileged`** — tài liệu GitLab nói rõ điều này. Còn cách "mount Docker socket của host" thì tài liệu cảnh báo có thể khiến host bị **leo thang đặc quyền**. Đây chính là rủi ro bạn đã học ở [Docker bài 07](../04-DOCKER/07-docker-security.md). So với GitHub-hosted runner: mỗi job có **một VM riêng dùng một lần**, `docker build` chạy thẳng trên VM đó, không cần privileged container.

### 4.5. 🟨 Kiến trúc Jenkins — tuần 22

```text
             ┌───────────────── Controller (Jenkins server, Java 21) ───────────────┐
 Dev ──push──►  Web UI · cấu hình job · credentials store · plugin · lịch build      │
 GitHub ─────►  webhook / quét repo (Multibranch)                                    │
             └───────────────┬───────────────────────────┬──────────────────────────┘
                             │ giao việc                 │ giao việc
                     ┌───────▼───────┐           ┌───────▼───────┐
                     │ Agent linux-1 │           │ Agent docker  │
                     │ 2 executors   │           │ (container)   │
                     └───────────────┘           └───────────────┘
 $JENKINS_HOME (/var/jenkins_home): toàn bộ cấu hình, job, lịch sử build, credential đã mã hóa
```

Những điều **bạn** phải lo khi dùng Jenkins mà GitHub Actions lo hộ:

| Việc | GitHub Actions (hosted runner) | Jenkins tự vận hành |
|---|---|---|
| Server CI | GitHub vận hành | Bạn cài, cập nhật Jenkins + Java + plugin |
| Môi trường build | VM mới cho mỗi job, xóa sau khi xong | Agent dùng lại giữa các build → rác, file cũ, xung đột phiên bản |
| Bảo mật | GitHub vá runner image | Bạn vá. Plugin có lỗ hổng là nguồn sự cố phổ biến |
| Sao lưu | Không cần — cấu hình là YAML trong repo | Phải sao lưu `$JENKINS_HOME` (job, credential, lịch sử) |
| Mở cổng | Không cần mở cổng vào mạng của bạn | Controller có web UI — phải bảo vệ, không phơi ra Internet trần |

🟨 **Controller isolation:** tài liệu bảo mật Jenkins khuyên đặt số executor của **built-in node** (chính controller) về **0** và chạy build trên agent riêng — vì build chạy trên controller có cùng quyền đọc file với process Jenkins, tức là đọc được cấu hình và credential.

### 4.6. 🟨 Declarative Jenkinsfile — đọc từng khối

```groovy
pipeline {                       // bắt buộc: khối ngoài cùng
  agent any                      // chạy trên agent bất kỳ còn executor trống
  options {
    timeout(time: 30, unit: 'MINUTES')         // ~ timeout-minutes
    disableConcurrentBuilds(abortPrevious: true) // ~ concurrency + cancel-in-progress
  }
  environment {
    APP_DIR = 'app'              // ~ env:
  }
  stages {
    stage('Build & test') {      // ~ một job / một nhóm step
      steps {
        sh 'cd "$APP_DIR" && ./mvnw -B -ntp verify'
      }
    }
  }
  post {                         // chạy sau tất cả stage, theo kết quả
    always  { junit 'app/target/surefire-reports/*.xml' }   // ~ if: always()
    failure { echo 'Build đỏ — xem báo cáo test' }           // ~ if: failure()
  }
}
```

Các điều kiện `post` có trong tài liệu: `always`, `changed`, `fixed`, `regression`, `aborted`, `failure`, `success`, `unstable`, `unsuccessful`, `cleanup` (`cleanup` chạy cuối cùng).

**`when` — điều kiện cho stage:**

| Jenkins | Ý nghĩa | GitHub Actions |
|---|---|---|
| `when { branch 'main' }` | Chỉ chạy trên nhánh `main` — **chỉ hoạt động trong Multibranch Pipeline** | `if: github.ref == 'refs/heads/main'` |
| `when { buildingTag() }` | Chỉ chạy khi build cho một tag | `if: github.ref_type == 'tag'` |
| `when { tag "v*" }` | Tag khớp mẫu | `on: push: tags: ['v*']` |

### 4.7. 🟨 Credentials trong Jenkins

Secret được lưu trong **Credentials store** của controller (mã hóa trong `$JENKINS_HOME`), gọi bằng **ID**. Với loại *Username with password*:

```groovy
environment {
  GHCR = credentials('ghcr-pat')   // tạo 3 biến: GHCR = "user:pass", GHCR_USR, GHCR_PSW
}
steps {
  sh 'echo "$GHCR_PSW" | docker login ghcr.io -u "$GHCR_USR" --password-stdin'
}
```

Hai điểm then chốt:

1. **Nháy đơn `'…'`** trong `sh`: Groovy **không** thay biến, shell mới thay → secret không lọt vào chuỗi lệnh Groovy. Viết `sh "… ${GHCR_PSW} …"` (nháy kép) là lỗi bảo mật kinh điển: Groovy chèn mật khẩu vào chuỗi lệnh trước khi chạy. Lỗi tương tự với GitHub Actions là chèn thẳng `${{ … }}` vào `run:` ([bài 04](04-secrets-environments.md)).
2. Không có thứ tương đương `GITHUB_TOKEN` tự sinh, tự hết hạn: muốn push GHCR từ Jenkins bạn phải tạo **PAT dài hạn** và lưu vào Jenkins. Token dài hạn = rủi ro cao hơn, phải nhớ xoay vòng.

### 4.8. 🟨 Multibranch Pipeline

Thay vì tạo tay một job cho mỗi nhánh, bạn tạo một **Multibranch Pipeline** trỏ tới repo. Jenkins quét repo, mỗi nhánh/PR có `Jenkinsfile` → một pipeline con. Biến `BRANCH_NAME`, `CHANGE_ID` (số PR) có sẵn; `when { branch 'main' }` chỉ hoạt động ở loại job này. Đây là mô hình gần nhất với "workflow chạy trên mọi push và PR" của GitHub Actions.

### 4.9. 🟨 Chạy Jenkins bằng Docker — và cái giá của Docker trong Jenkins

Tài liệu cài đặt chính thức dùng image **`jenkins/jenkins`** (ví dụ Compose dùng tag `lts-jdk21`), dữ liệu nằm ở `/var/jenkins_home` gắn vào **named volume**, cổng **8080** (web) và **50000** (agent kết nối vào).

Muốn pipeline chạy được `docker build`, tài liệu chính thức dựng thêm một container **`docker:dind` chạy `--privileged`** để Jenkins gọi tới qua TCP + TLS. Cách "tắt" mà nhiều blog dùng là **mount `/var/run/docker.sock`** vào container Jenkins.

⚠️ Cả hai đều trao quyền rất lớn: `--privileged` gần như bỏ hết cô lập; ai điều khiển được Docker socket là có quyền ngang root trên host. Một plugin Jenkins có lỗ hổng + Docker socket = kẻ tấn công chiếm server build — đúng kịch bản trong [Docker bài 07](../04-DOCKER/07-docker-security.md). **Chỉ làm trên máy học**, không bao giờ trên server thật mà không có thiết kế bảo mật.

Lab Phần B dùng bộ Compose của **tutorial chính thức** (`jenkins-docs/quickstart-tutorials`) nên bạn không phải tự dựng phần này.

---

## 5. Ví dụ thực tế

### 5.1. 🟨 Pipeline CI của taskhub "dịch" sang GitLab CI

Đây là bản dịch **để đọc hiểu**, tương ứng với [ci.yml tham khảo](labs/reference/workflows/ci.yml) (job `build-test` và `image`). Chưa chạy thử trên GitLab — khóa học không dùng GitLab.

```yaml
# .gitlab-ci.yml — bản dịch đọc hiểu, KHÔNG dùng trong repo taskhub
stages:
  - test
  - image
  - scan

workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

variables:
  MAVEN_OPTS: "-Dmaven.repo.local=$CI_PROJECT_DIR/.m2/repository"
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

build-test:
  stage: test
  image: eclipse-temurin:21-jdk-noble
  services:
    - postgres:17
  variables:
    POSTGRES_DB: taskhub
    POSTGRES_USER: taskhub
    POSTGRES_PASSWORD: ci-only-password
    SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/taskhub
    SPRING_DATASOURCE_USERNAME: taskhub
    SPRING_DATASOURCE_PASSWORD: ci-only-password
  cache:
    key:
      files:
        - app/pom.xml
    paths:
      - .m2/repository
  script:
    - cd app
    - ./mvnw -B -ntp verify
  artifacts:
    when: always
    reports:
      junit: app/target/surefire-reports/TEST-*.xml
    expire_in: 7 days
  timeout: 15m
  interruptible: true

image:
  stage: image
  image: docker:24.0.5-cli
  services:
    - docker:24.0.5-dind
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: "/certs"
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login $CI_REGISTRY -u $CI_REGISTRY_USER --password-stdin
  script:
    - docker build -f docker/Dockerfile -t "$IMAGE" .
    - |
      if [ "$CI_COMMIT_BRANCH" = "$CI_DEFAULT_BRANCH" ]; then
        docker push "$IMAGE"
      fi

scan:
  stage: scan
  image:
    name: aquasec/trivy:0.76.1
    entrypoint: [""]
  variables:
    TRIVY_USERNAME: $CI_REGISTRY_USER
    TRIVY_PASSWORD: $CI_REGISTRY_PASSWORD
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  script:
    - trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE"
```

**Khác biệt đáng chú ý so với bản GitHub Actions:**

| Điểm | GitHub Actions (taskhub) | Bản GitLab ở trên |
|---|---|---|
| Kết nối database | `localhost:5432` (job chạy trên VM, port được map) | `postgres:5432` (job và service là container cạnh nhau) |
| Thứ tự quét / push | Quét **trước**, chỉ push khi sạch | Push rồi mới quét (job scan riêng kéo image từ registry). Muốn quét trước phải thêm bước lưu image hoặc dùng tag tạm — đánh đổi độ phức tạp |
| Độ dài short SHA | 7 | 8 |
| Build image | Thẳng trên VM | Docker-in-Docker, runner phải `privileged` |
| Ghim phiên bản | Action ghim bằng SHA | Image ghim bằng tag (muốn chặt hơn: ghim digest `@sha256:…`) |

### 5.2. 🟨 Pipeline CI của taskhub "dịch" sang Jenkinsfile (tuần 22)

Bản để **đọc hiểu**. Cần plugin **Docker Pipeline** (cho `docker.image(...)`), agent có Docker, và credential ID `ghcr-pat` kiểu *Username with password*.

```groovy
// Jenkinsfile — bản dịch đọc hiểu, KHÔNG dùng trong repo taskhub
pipeline {
  agent any
  options {
    timeout(time: 30, unit: 'MINUTES')
    disableConcurrentBuilds(abortPrevious: true)
  }
  environment {
    IMAGE = 'ghcr.io/phuong-dev/taskhub'
  }
  stages {
    stage('Build & test') {
      steps {
        script {
          // Sidecar: chạy PostgreSQL nền, rồi chạy build trong container JDK nối tới nó
          docker.image('postgres:17').withRun('-e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub -e POSTGRES_PASSWORD=ci-only-password') { db ->
            // withRun không chờ database sẵn sàng → tự chờ bằng pg_isready trong chính container postgres
            // (nháy kép ở đây là cố ý: cần Groovy chèn db.id, và chuỗi không chứa secret)
            sh "until docker exec ${db.id} pg_isready -U taskhub -d taskhub; do sleep 1; done"
            docker.image('eclipse-temurin:21-jdk-noble').inside("--link ${db.id}:postgres") {
              withEnv(['SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/taskhub',
                       'SPRING_DATASOURCE_USERNAME=taskhub',
                       'SPRING_DATASOURCE_PASSWORD=ci-only-password']) {
                sh 'cd app && ./mvnw -B -ntp verify'
              }
            }
          }
        }
      }
      post {
        always { junit 'app/target/surefire-reports/*.xml' }
      }
    }
    stage('Image') {
      steps {
        script { env.SHORT_SHA = env.GIT_COMMIT.take(7) }   // Groovy cắt 7 ký tự, khớp quy ước taskhub
        sh 'docker build -f docker/Dockerfile -t "$IMAGE:$SHORT_SHA" .'
        sh 'docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1 image --exit-code 1 --severity CRITICAL --ignore-unfixed "$IMAGE:$SHORT_SHA"'
      }
    }
    stage('Push') {
      when { branch 'main' }                 // chỉ đúng trong Multibranch Pipeline
      environment {
        GHCR = credentials('ghcr-pat')       // GHCR_USR, GHCR_PSW
      }
      steps {
        sh 'echo "$GHCR_PSW" | docker login ghcr.io -u "$GHCR_USR" --password-stdin'
        sh 'docker push "$IMAGE:$SHORT_SHA"'
      }
    }
  }
  post {
    cleanup { sh 'docker logout ghcr.io || true' }
  }
}
```

**Đọc và trả lời được** (đáp án nằm trong mục 4): vì sao các lệnh `sh` dùng nháy đơn? Vì sao phải tự chờ `pg_isready`? Dòng nào cần quyền Docker socket và rủi ro là gì? Vì sao `when { branch 'main' }` không có tác dụng nếu đây là job Pipeline thường?

Đoạn `docker.image(...).withRun(...)` / `.inside("--link ...")` là mẫu **sidecar** trong tài liệu "Using Docker with Pipeline" của Jenkins (ví dụ gốc dùng MySQL). `--link` là tính năng cũ của Docker; ở đây giữ để khớp tài liệu.

---

## 6. Sơ đồ kiến trúc

```text
                   GitHub Actions                 GitLab CI                     Jenkins
 Ai vận hành?      GitHub                         GitLab (gitlab.com)           BẠN
                                                  hoặc công ty (self-managed)
 Định nghĩa        .github/workflows/*.yml        .gitlab-ci.yml                Jenkinsfile + cấu hình UI/plugin
 Nơi chạy          VM dùng một lần                Runner (thường: container     Agent dùng lại giữa các build
                   (ubuntu-24.04)                 theo image: của job)
 Secret ngắn hạn   GITHUB_TOKEN (tự hết hạn)      CI_JOB_TOKEN (tự hết hạn)     Không có sẵn → PAT dài hạn
 Registry          GHCR                           GitLab Container Registry     Ngoài (GHCR, ECR, Harbor…)

           push / MR / PR / tag
 Dev ─────────────────────────► [ Server CI ] ──giao job──► [ Runner / Agent ] ──► build → test → image → quét → push
                                       ▲                                                              │
                                       └──────────────── trạng thái ✔/✘ hiển thị trên PR/MR ──────────┘
```

---

## 7. Các câu lệnh cần biết

| Lệnh / cú pháp | Môi trường | Dùng để |
|---|---|---|
| `git clone https://github.com/jenkins-docs/quickstart-tutorials.git` | `[WSL]` | Lấy bộ Compose chạy Jenkins của tutorial chính thức |
| `docker compose --profile maven up -d` | `[WSL]` | Chạy Jenkins (profile cho tutorial Maven) |
| `docker compose ps` | `[WSL]` | Kiểm tra container Jenkins đã chạy |
| `docker compose logs -f` | `[WSL]` | Xem log khởi động Jenkins |
| ⚠️ `docker compose --profile maven down -v --remove-orphans` | `[WSL]` | Dừng và **xóa cả volume** (mất toàn bộ job, lịch sử build) |
| `docker exec <container> cat /var/jenkins_home/secrets/initialAdminPassword` | `[WSL]` | Lấy mật khẩu admin ban đầu khi tự chạy image `jenkins/jenkins` (không cần trong tutorial Compose) |
| `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest -color` | `[WSL]` | Nhắc lại: kiểm tra tĩnh workflow **GitHub Actions** (actionlint không đọc được GitLab/Jenkins) |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `docker compose --profile maven up -d`

```bash
cd ~/devops-lab/05-cicd/jenkins/quickstart-tutorials
docker compose --profile maven up -d
```

| Phần | Ý nghĩa |
|---|---|
| `--profile maven` | Bật nhóm service gắn nhãn profile `maven` trong file Compose của tutorial ([Docker bài 05](../04-DOCKER/05-docker-compose.md) đã học profile) |
| `up -d` | Tạo và chạy nền |

Đầu ra (minh họa, tên container phụ thuộc file Compose của tutorial):

```text
[+] Running 3/3
 ✔ Network quickstart-tutorials_default   Created
 ✔ Container jenkins-controller           Started
 ✔ Container ...-agent                    Started
```

Kiểm tra: `docker compose ps` → các container ở trạng thái `running`/`healthy`. Mở `http://localhost:8080`. Theo tutorial, tài khoản đăng nhập là `admin` / `admin` — chỉ chấp nhận được vì Jenkins này **chỉ chạy trên máy bạn**.

### 8.2. ⚠️ `docker compose --profile maven down -v --remove-orphans`

| Phần | Ý nghĩa |
|---|---|
| `down` | Dừng và xóa container, network |
| `-v` | ⚠️ **Xóa luôn volume** — mất `$JENKINS_HOME`: job, lịch sử build, credential bạn đã tạo |
| `--remove-orphans` | Xóa cả container thuộc project nhưng không còn khai báo trong file Compose |

Dùng `down` **không** có `-v` nếu bạn muốn giữ lại dữ liệu để học tiếp hôm sau.

---

## 9. Bài thực hành từng bước

### Phần A — Đọc hiểu GitLab CI (tuần 10, ~60 phút, không cần cài gì)

Mục tiêu: chứng minh bạn đọc được pipeline của công cụ khác.

1. Mở bản dịch ở [mục 5.1](#51--pipeline-ci-của-taskhub-dịch-sang-gitlab-ci) cạnh [ci.yml tham khảo](labs/reference/workflows/ci.yml) (hoặc `ci.yml` **của bạn**).
2. Tạo file `~/devops-journey/week10/gitlab-reading.md`. Với **mỗi job** GitLab, ghi:
   - Job chạy khi nào (MR? main?) — chỉ ra dòng `rules` quyết định điều đó.
   - Chạy trong container nào; có service nào.
   - Dùng secret/biến nào, biến đó do ai cung cấp (bạn khai báo hay GitLab định nghĩa sẵn).
   - Job tương ứng trong `ci.yml` của bạn.
3. Ghi ra **3 khác biệt hành vi** (không phải khác biệt cú pháp) giữa hai bản. Gợi ý xem lại bảng cuối mục 5.1.
4. Trả lời: nếu một MR từ nhánh `feat/x` được mở, bản GitLab có push image không? Lần theo từng dòng để chứng minh.

### Phần B — Chạy Jenkins theo tutorial chính thức (tuần 22, ~3 giờ)

> Tutorial: [Build a Java app with Maven](https://www.jenkins.io/doc/tutorials/build-a-java-app-with-maven/) — làm **theo đúng tutorial**; phần dưới chỉ bổ sung những chỗ cần chú ý trên máy bạn.
> Yêu cầu theo tutorial: tối thiểu 2 GB RAM và 2 GB ổ đĩa trống cho Jenkins, Docker + Docker Compose, Git, tài khoản GitHub.

**Bước 0 — Chuẩn bị `[WSL]`**

```bash
docker info > /dev/null && echo "Docker OK"
sudo ss -ltnp | grep ':8080 ' || echo "8080 trống"
```

Nếu 8080 đang bị chiếm (thường là `./mvnw spring-boot:run` của taskhub hoặc server Python từ lab cũ): dừng process đó trước.

**Bước 1 — Fork và clone app mẫu**

Trên GitHub, fork repo `jenkins-docs/simple-java-maven-app` về tài khoản của bạn (repo công khai, miễn phí). Sau đó:

```bash
mkdir -p ~/devops-lab/05-cicd/jenkins && cd ~/devops-lab/05-cicd/jenkins
git clone https://github.com/<github-user>/simple-java-maven-app
git clone https://github.com/jenkins-docs/quickstart-tutorials.git
```

**Bước 2 — Chạy Jenkins**

```bash
cd ~/devops-lab/05-cicd/jenkins/quickstart-tutorials
docker compose --profile maven up -d
docker compose ps
```

Mở `http://localhost:8080`, đăng nhập theo tutorial.

**Bước 3 — Làm theo tutorial**: tạo Pipeline job trỏ tới repo fork của bạn, viết `Jenkinsfile` từng phần (build → test → deliver) đúng như tutorial hướng dẫn, chạy và xem kết quả.

Trong lúc làm, ghi vào `~/devops-journey/week22/jenkins-notes.md`:

- Mỗi khối của `Jenkinsfile` tutorial (`agent`, `stages`, `post`…) tương ứng với gì trong GitHub Actions (dùng bảng [mục 3.3](#33-ba-công-cụ-cùng-một-bản-chất)).
- Màn hình **Console Output** của một build: tìm dòng bắt đầu mỗi stage, dòng lệnh `sh`, dòng kết quả test.
- Build chạy ở đâu — controller hay agent? Bằng chứng là dòng nào trong log (`Running on ...`)?

**Bước 4 — Cố ý làm đỏ**: sửa một test trong repo fork cho sai, push, chạy lại build. Đọc Console Output, tìm dòng báo test lỗi. So sánh với cách bạn đọc log job đỏ trên GitHub Actions. Khôi phục test.

**Bước 5 — 🟨 Thêm** khối `post { always { … } }` hoặc `options { timeout(...) }` vào `Jenkinsfile` của bạn, chạy lại, xác nhận hành vi.

**Bước 6 — Dọn dẹp**

```bash
cd ~/devops-lab/05-cicd/jenkins/quickstart-tutorials
docker compose --profile maven down -v --remove-orphans    # ⚠️ xóa cả volume Jenkins
docker compose ps                                          # không còn container nào
```

Repo fork trên GitHub: giữ lại làm minh chứng hoặc xóa (Settings → Danger Zone) — tùy bạn.

---

## 10. Kết quả mong đợi

| Phần | Kết quả |
|---|---|
| A | `gitlab-reading.md` có phân tích từng job, 3 khác biệt hành vi, câu trả lời về MR từ `feat/x` (không push — chỉ ra được dòng `if` trong job `image` và `rules` của job `scan`) |
| B | Jenkins chạy ở `http://localhost:8080`; pipeline của tutorial có ít nhất một build **xanh** và một build **đỏ** (bước 4) mà bạn giải thích được từ Console Output |
| B | `jenkins-notes.md` có bảng ánh xạ khối `Jenkinsfile` ↔ GitHub Actions |
| B | Sau dọn dẹp: `docker compose ps` rỗng, không còn volume của tutorial (`docker volume ls`) |

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Không mở được `localhost:8080` | Container chưa khởi động xong (Jenkins khởi động mất một lúc) hoặc cổng bị chiếm | `docker compose ps`, `docker compose logs -f`; kiểm tra `ss -ltnp` |
| `Bind for 0.0.0.0:8080 failed: port is already allocated` | Process khác đang dùng 8080 | Dừng process đó (taskhub chạy bằng `mvnw`, server lab cũ) |
| Docker Desktop báo thiếu RAM, container bị kill (exit 137) | Jenkins + agent + Maven khá nặng | Đóng bớt ứng dụng; kiểm tra giới hạn RAM của WSL ([Docker bài 08](../04-DOCKER/08-container-troubleshooting.md)) |
| Build lỗi ngay bước checkout: không tìm thấy repo | Sai URL repo fork, hoặc repo private | Dùng đúng URL `https://github.com/<github-user>/simple-java-maven-app`, repo public |
| Sửa `Jenkinsfile` trên máy nhưng build vẫn chạy bản cũ | Jenkins đọc `Jenkinsfile` **từ repo trên GitHub**, không phải thư mục trên máy | `git push` trước khi bấm Build |
| `when { branch 'main' }` không bao giờ chạy | Đang dùng job Pipeline thường, không phải Multibranch | Dùng Multibranch Pipeline, hoặc điều kiện khác |
| GitLab: job không được tạo dù đã push | `workflow: rules` hoặc `rules` của job không khớp | Đọc lại thứ tự `rules`, kiểm tra biến `CI_PIPELINE_SOURCE`, `CI_COMMIT_BRANCH` |
| GitLab: `Cannot connect to the Docker daemon` trong job build image | Thiếu service dind, sai `DOCKER_HOST`, hoặc runner không bật privileged | Đối chiếu đoạn mẫu mục 4.4 |

---

## 12. Đọc log và xử lý lỗi

**Jenkins Console Output** (minh họa, đã rút gọn):

```text
Started by user admin
[Pipeline] Start of Pipeline
[Pipeline] node
Running on agent-1 in /home/jenkins/agent/workspace/simple-java-maven-app   ← build chạy ở đâu
[Pipeline] { (Build)
[Pipeline] sh
+ mvn -B -DskipTests clean package                                          ← lệnh thật được chạy
...
[Pipeline] { (Test)
[Pipeline] sh
+ mvn test
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0                    ← nguyên nhân
[Pipeline] }
[Pipeline] // stage
[Pipeline] { (Deliver)
Stage "Deliver" skipped due to earlier failure(s)                           ← hệ quả, không phải nguyên nhân
...
ERROR: script returned exit code 1
Finished: FAILURE
```

Cách đọc giống hệt log GitHub Actions ([bài 02](02-github-actions-basics.md)):

1. Bắt đầu từ **cuối** (`Finished: FAILURE`, `exit code 1`) để biết build đỏ.
2. Đi ngược lên tìm **stage đầu tiên** lỗi — các stage sau bị `skipped` chỉ là hệ quả.
3. Trong stage đó, tìm dòng `+ <lệnh>` (Jenkins in lệnh `sh` với dấu `+`, như `set -x` ở [Linux bài 06](../01-LINUX/06-bash-scripting.md)) và đầu ra ngay sau nó.

**GitLab job log** đọc tương tự: mỗi dòng `$ <lệnh>` là một dòng trong `script`, cuối log có `ERROR: Job failed: exit code N`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Trong GitLab CI, làm sao GitLab phân biệt khóa `build-test:` là một job còn `variables:` không phải job?
2. Vì sao job GitLab nối PostgreSQL bằng `postgres:5432` còn job GitHub Actions của taskhub nối bằng `localhost:5432`?
3. `only`/`except` và `rules` khác nhau thế nào về tình trạng hỗ trợ? Khi gặp `only:` trong dự án cũ, bạn làm gì?
4. `CI_REGISTRY_PASSWORD` sống bao lâu? So sánh với PAT bạn tạo ở [Docker bài 06](../04-DOCKER/06-registry.md) về mức rủi ro khi bị lộ.
5. Controller và agent của Jenkins khác nhau thế nào? Vì sao tài liệu bảo mật Jenkins khuyên đặt executor của built-in node về 0?
6. Declarative Pipeline: `stages`, `steps`, `post` tương ứng với gì ở GitHub Actions?
7. Vì sao `sh 'echo "$GHCR_PSW" | docker login …'` (nháy đơn) an toàn hơn `sh "echo ${GHCR_PSW} | docker login …"` (nháy kép)?
8. Kể 3 việc vận hành bạn phải tự làm khi dùng Jenkins mà GitHub-hosted runner làm hộ.
9. Vì sao chạy Docker bên trong CI (dind, mount socket) là vấn đề bảo mật? GitHub-hosted runner tránh vấn đề này bằng cách nào?
10. Một đồng nghiệp nói "chuyển từ GitHub Actions sang GitLab là đổi cú pháp thôi". Nêu 2 khác biệt **hành vi** có thể gây lỗi khi chuyển đổi.

---

## 14. Bài tập tự làm

1. **Khảo sát thị trường (tuần 10).** Đọc 20 tin tuyển dụng DevOps/Cloud Junior–Middle tại Việt Nam (ITviec, TopDev hoặc LinkedIn). Lập bảng: tin nào nhắc GitHub Actions / GitLab CI / Jenkins / công cụ khác. Viết 3 câu kết luận **từ dữ liệu của bạn**, kèm ngày khảo sát.
2. **Dịch ngược (tuần 10).** Dịch [release.yml tham khảo](labs/reference/workflows/release.yml) sang một job GitLab chạy khi có tag (`rules: - if: $CI_COMMIT_TAG`). Gợi ý: image `docker:<phiên bản>-cli` có sẵn plugin buildx (`docker buildx imagetools`) không? Tra tài liệu, và ghi rõ chỗ bạn **chưa chắc chắn**.
3. **Đọc Jenkinsfile lạ (tuần 22).** Tìm một `Jenkinsfile` thật trên GitHub (tìm `filename:Jenkinsfile` trong một dự án mã nguồn mở bạn biết). Chú thích từng khối; chỉ ra credential được dùng thế nào, có chỗ nào chèn secret bằng nháy kép không.
4. **Câu trả lời phỏng vấn (tuần 22).** Viết câu trả lời 60–90 giây cho: "Dự án của bạn dùng GitHub Actions. Công ty tôi dùng Jenkins. Bạn mất bao lâu để làm việc được và bắt đầu từ đâu?" — phải nêu được ít nhất 3 ánh xạ khái niệm và 1 rủi ro bảo mật riêng của Jenkins.

Lời giải tham khảo: [solutions/06-solutions.md](solutions/06-solutions.md) — chỉ mở sau khi đã làm.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Nhìn một `.gitlab-ci.yml` bất kỳ, nói được job nào chạy khi nào, trong container nào, dùng secret gì.
- [ ] Nhìn một `Jenkinsfile` Declarative, nói được stage nào chạy, chạy ở agent nào, `post` làm gì, credential lấy từ đâu.
- [ ] Giải thích được khác biệt "dịch vụ được vận hành hộ" (GitHub Actions, gitlab.com) và "server tự vận hành" (Jenkins) bằng ít nhất 3 hệ quả cụ thể.
- [ ] Chỉ ra được rủi ro bảo mật của Docker-in-Docker / Docker socket trong CI.
- [ ] Đã chạy Jenkins trên máy bằng tutorial chính thức, có một build đỏ đọc được nguyên nhân từ log, và đã dọn dẹp sạch.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitLab — CI/CD YAML syntax reference](https://docs.gitlab.com/ci/yaml/) | Từ khóa `stages`, `rules`, `services`, `artifacts`, `cache`, `interruptible`… | 2026-10-31 |
| [GitLab — Deprecated keywords](https://docs.gitlab.com/ci/yaml/deprecated_keywords/) | `only`/`except` đã deprecated, dùng `rules` | 2026-10-31 |
| [GitLab — Predefined CI/CD variables](https://docs.gitlab.com/ci/variables/predefined_variables/) | `CI_COMMIT_SHORT_SHA` (8 ký tự), `CI_REGISTRY_*`, `CI_JOB_TOKEN` | 2026-10-31 |
| [GitLab — Using PostgreSQL](https://docs.gitlab.com/ci/services/postgres/) | Service `postgres`, hostname `postgres` | 2026-10-31 |
| [GitLab — Build and push container images](https://docs.gitlab.com/user/packages/container_registry/build_and_push_images/) | Mẫu Docker-in-Docker, `docker login` bằng `CI_REGISTRY_PASSWORD` | 2026-10-31 |
| [GitLab — Use Docker to build Docker images](https://docs.gitlab.com/ci/docker/using_docker_build/) | dind cần privileged; cảnh báo mount socket | 2026-10-31 |
| [GitHub Docs — Migrating from GitLab CI/CD to GitHub Actions](https://docs.github.com/en/actions/tutorials/migrate-to-github-actions/manual-migrations/migrate-from-gitlab-cicd) | Ánh xạ stage → `needs`, `rules` → `if` | 2026-10-31 |
| [GitHub Docs — Migrating from Jenkins to GitHub Actions](https://docs.github.com/en/actions/tutorials/migrate-to-github-actions/manual-migrations/migrate-from-jenkins) | Ánh xạ `agent` → `runs-on`, stage → job | 2026-10-31 |
| [Jenkins — LTS Changelog](https://www.jenkins.io/changelog-stable/) | LTS 2.580.2 (2026-10-28), yêu cầu Java 21 | 2026-10-31 |
| [Jenkins — LTS Release Line](https://www.jenkins.io/download/lts/) | Chu kỳ 12 tuần, bản vá `.1/.2/.3` | 2026-10-31 |
| [Jenkins — Installing Jenkins: Docker](https://www.jenkins.io/doc/book/installing/docker/) | Image `jenkins/jenkins`, `lts-jdk21`, `docker:dind --privileged`, volume `/var/jenkins_home`, cổng 8080/50000 | 2026-10-31 |
| [Jenkins — Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/) | Declarative: `agent`, `options`, `when`, `post`, `credentials()` (`_USR`/`_PSW`) | 2026-10-31 |
| [Jenkins — Using Docker with Pipeline](https://www.jenkins.io/doc/book/pipeline/docker/) | Plugin Docker Pipeline, mẫu sidecar `withRun` / `inside` | 2026-10-31 |
| [Jenkins — Controller Isolation](https://www.jenkins.io/doc/book/security/controller-isolation/) | Đặt executor của built-in node về 0 | 2026-10-31 |
| [Jenkins — Build a Java app with Maven (tutorial)](https://www.jenkins.io/doc/tutorials/build-a-java-app-with-maven/) | Lab Phần B: `quickstart-tutorials`, `docker compose --profile maven` | 2026-10-31 |

**Gặp lại ở đâu:** tuần 22 (lab Phần B, ôn tập sự cố) · [Module 04 bài 07](../04-DOCKER/07-docker-security.md) (Docker socket) · Module 11 — Hybrid Cloud (hạ tầng on-premises thường đi cùng GitLab self-managed / Jenkins) · Module 13 — câu hỏi phỏng vấn về công cụ CI/CD.
