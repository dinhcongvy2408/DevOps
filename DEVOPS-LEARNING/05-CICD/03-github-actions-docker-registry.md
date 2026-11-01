# 03. GitHub Actions: build image, quét lỗ hổng và đẩy lên registry

> ⏱️ ~3–4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [02. GitHub Actions cơ bản](02-github-actions-basics.md), [Docker 03 — Dockerfile & multi-stage](../04-DOCKER/03-dockerfile-multistage.md), [Docker 06 — Registry](../04-DOCKER/06-registry.md), [Docker 07 — Bảo mật](../04-DOCKER/07-docker-security.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop · `[GitHub]` repo `taskhub` · `[Runner]` máy ảo `ubuntu-24.04` do GitHub cấp
> Phiên bản khi viết (2026-10-31): `docker/setup-buildx-action@v4`, `docker/metadata-action@v6`, `docker/build-push-action@v7`, `docker/login-action@v4`, `aquasecurity/trivy-action@v0.36.0`, Trivy `0.76.1`

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

- Giải thích vì sao image dùng để triển khai phải được **build trong CI**, không build trên laptop.
- Viết job `image` trong `ci.yml`: build image từ `docker/Dockerfile`, **quét bằng Trivy trước khi push**, chỉ push lên GHCR khi code đã vào `main`.
- Dùng `docker/metadata-action` để sinh tag **SHA 7 ký tự** và label OCI, giải thích được từng loại tag (`type=sha`, `type=semver`, `type=ref`).
- Dùng **cache của GitHub Actions** (`type=gha`) để build image nhanh hơn.
- Cấp quyền `packages: write` cho `GITHUB_TOKEN` đúng chỗ, và xử lý lỗi `403 permission_denied: write_package`.
- Viết `release.yml`: khi push tag `v*.*.*`, **gắn thêm tag SemVer cho đúng image CI đã build** (không build lại) và tạo GitHub Release.
- Đọc được cấu trúc **image index** trên registry, giải thích vì sao GHCR hiện thêm một "platform" `unknown/unknown`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Ở [Docker 06](../04-DOCKER/06-registry.md) bạn đã tự tay `docker build`, `docker tag`, `docker push` từ laptop. Cách đó đủ để học, nhưng không dùng được trong team:

| Tình huống thật | Vấn đề khi build trên laptop | Khi build trong CI |
|---|---|---|
| "Image `v0.3.0` được build từ code nào?" | Không ai chắc: có thể laptop đang có file chưa commit, đang ở nhánh khác | Build từ **đúng một commit**, log ghi lại toàn bộ |
| Laptop của bạn có file `.env` thật | Lỡ thiếu `.dockerignore` là secret vào image | Runner checkout sạch từ Git — file không có trong Git thì không có trong image |
| Người khác cần phát hành khi bạn nghỉ phép | Họ cần token PAT của bạn, hoặc cài đặt giống máy bạn | Ai có quyền tạo tag là phát hành được, không ai cầm token cá nhân |
| Image có lỗ hổng CRITICAL | Không ai nhớ chạy Trivy trước khi push | Pipeline **chặn**: quét đỏ thì không push |
| Production lỗi, cần biết bản đang chạy | Tag `v0.3.0` có thể đã bị ai đó push đè từ laptop | Tag được tạo tự động, theo quy ước bất biến |

Câu hỏi phỏng vấn rất hay gặp: *"Pipeline của bạn build image thế nào, tag ra sao, làm sao chắc image chạy production đúng là image đã test?"* Bài này cho bạn câu trả lời cụ thể, có file thật trong repo.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Build trong CI = build có thể lặp lại và truy vết được

Một runner GitHub Actions là **máy ảo mới tinh** cho mỗi job, bị xóa sau khi job xong ([bài 02](02-github-actions-basics.md)). Hệ quả:

- **Không có trạng thái thừa**: không có file rác, không có image cũ, không có `.env`.
- **Build context = nội dung commit**: bước `actions/checkout` lấy đúng commit, `docker build` chỉ thấy những file đó.
- **Truy vết**: mỗi lần chạy có log, có commit SHA, có người kích hoạt.

Đây là ý nghĩa thực tế của câu "build có thể lặp lại" (reproducible build) ở mức Junior: cùng commit + cùng pipeline → cùng kết quả, và ai cũng kiểm tra lại được.

### 3.2. BuildKit, Buildx và builder

Từ [Docker 03](../04-DOCKER/03-dockerfile-multistage.md) bạn đã dùng **BuildKit** — bộ máy build hiện đại của Docker (chạy các stage song song, cache thông minh). **Buildx** là lệnh `docker buildx` để điều khiển BuildKit.

BuildKit chạy bên trong một **builder** (trình build). Có hai loại builder bạn sẽ gặp:

| Driver của builder | Ở đâu | Làm được |
|---|---|---|
| `docker` (mặc định) | BuildKit nằm trong Docker daemon | Build và để image ngay trong Docker. Không xuất được cache ra GitHub Actions cache (trừ khi bật containerd image store) |
| `docker-container` | BuildKit chạy trong một container riêng | Xuất cache ra nhiều nơi (`type=gha`), tạo attestation, build nhiều kiến trúc |

`docker/setup-buildx-action` tạo một builder `docker-container` trên runner. Đó là lý do mọi workflow build image đều có bước này.

### 3.3. Load hay push

Builder `docker-container` nằm **ngoài** Docker daemon, nên sau khi build, image phải được **xuất** (export) đi đâu đó:

| Tùy chọn | Image đi đâu | Dùng khi |
|---|---|---|
| `load: true` | Nạp vào Docker daemon của runner (như `docker build` bình thường) | Cần chạy/quét image ngay trên runner |
| `push: true` | Đẩy thẳng lên registry | Phát hành image |
| Không cả hai | Chỉ còn trong cache của builder | Chỉ kiểm tra "build được không" |

### 3.4. Manifest, image index và attestation

Ở [Docker 06](../04-DOCKER/06-registry.md) bạn biết tag trỏ tới **digest**. Digest đó có thể là của một trong hai loại tài liệu JSON:

- **Image manifest** (bản kê image): danh sách layer + config của **một** image cho **một** nền tảng (ví dụ `linux/amd64`).
- **Image index** (danh mục image, còn gọi manifest list): danh sách **nhiều** manifest. Dùng cho image đa kiến trúc (`eclipse-temurin` có bản amd64, arm64…), và để đính kèm **attestation**.

**Attestation** (chứng thực) là thông tin đi kèm image, ví dụ **provenance** (nguồn gốc: build từ repo nào, commit nào, bằng workflow nào). Theo tài liệu Docker, attestation được lưu như một manifest riêng trong image index, có `platform` là **`unknown/unknown`** để container runtime không bao giờ kéo nhầm nó về chạy.

### 3.5. Build một lần, triển khai nhiều nơi

Bạn đã gặp nguyên tắc **build once, deploy many** ở [Git 04](../03-GIT/04-team-workflows.md). Áp dụng cho image:

- **Sai:** khi phát hành `v0.3.0`, pipeline **build lại** từ code. Base image `eclipse-temurin:21-jre-noble` có thể vừa được cập nhật, Maven có thể tải thư viện khác → image phát hành **khác** image đã test.
- **Đúng:** image được build **một lần** khi code vào `main` (tag `:<sha7>`). Phát hành chỉ là **gắn thêm tên** `:v0.3.0` cho đúng image đó — giống `docker tag` ở Docker 06, nhưng làm trực tiếp trên registry.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Bức tranh tổng thể

Repo `taskhub` sẽ có hai workflow:

| Workflow | Kích hoạt | Job | Làm gì |
|---|---|---|---|
| `CI` (`ci.yml`) | `pull_request` và `push` vào `main` | `build-test` ([bài 02](02-github-actions-basics.md)) | `./mvnw verify` với PostgreSQL tạm |
| | | `image` (bài này) | Build image → quét Trivy → **chỉ khi push vào `main`**: đăng nhập GHCR và push `:<sha7>` |
| `Release` (`release.yml`) | Push tag `v*.*.*` | `promote` (bài này) | Tìm `:<sha7>` của commit được tag → gắn thêm `:vX.Y.Z` → tạo GitHub Release |

Thứ tự các bước trong job `image`:

```text
checkout → setup-buildx → metadata (tính tên + tag) → build (load) → Trivy (cổng chặn)
        → [chỉ khi push vào main] login GHCR → build lại từ cache với push: true
```

> 📌 Bài này dùng tag phiên bản chính (`@v4`, `@v7`…) cho dễ đọc. [Bài 04](04-secrets-environments.md) giải thích vì sao bản cuối cùng trong repo phải **ghim bằng SHA commit** (như [bản tham khảo](labs/reference/workflows/ci.yml)).

### 4.2. 🟥 `docker/setup-buildx-action` — tạo builder

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v4
```

Không cần tham số. Action này tạo builder driver `docker-container` và đặt làm mặc định cho các bước sau. Quên bước này → bước build báo lỗi khi xuất cache `type=gha` (xem mục 11).

### 4.3. 🟥 `docker/metadata-action` — tính tên, tag và label

Thay vì tự ghép chuỗi tag bằng shell, ta dùng `docker/metadata-action`:

```yaml
- name: Image metadata
  id: meta
  uses: docker/metadata-action@v6
  with:
    images: ghcr.io/${{ github.repository_owner }}/taskhub
    tags: |
      type=sha,prefix=
    flavor: |
      latest=false
```

| Tham số | Ý nghĩa | Vì sao chọn vậy |
|---|---|---|
| `id: meta` | Đặt tên cho bước để bước sau đọc output bằng `steps.meta.outputs.*` | Kiến thức từ bài 02 |
| `images` | Tên image gốc (chưa có tag) | `github.repository_owner` là username GitHub của bạn. Action **tự chuyển sang chữ thường** (tài liệu ghi rõ) → username `Phuong-Dev` vẫn ra `ghcr.io/phuong-dev/taskhub` |
| `type=sha` | Tag = SHA commit dạng ngắn | Mặc định dài **7 ký tự** và có tiền tố `sha-` (ví dụ `sha-860c190`) |
| `prefix=` | Bỏ tiền tố `sha-` | Khớp quy ước Docker 06: tag là `:9f8e7d6` |
| `latest=false` | Không bao giờ sinh tag `latest` | Mặc định `latest=auto` sẽ tự thêm `latest` khi chạy trên tag Git. Dự án không dùng `latest` ([Docker 06 §4.7](../04-DOCKER/06-registry.md#47--chiến-lược-đặt-tag)) |

**Độ dài SHA.** Tài liệu metadata-action: SHA ngắn mặc định 7 ký tự, đổi bằng biến môi trường `DOCKER_METADATA_SHORT_SHA_LENGTH` khi repo rất lớn (nhiều commit trùng 7 ký tự đầu). `git rev-parse --short` trên máy bạn thì **có thể** trả về nhiều hơn 7 ký tự khi repo lớn — vì vậy khi cần so sánh, hãy dùng `git rev-parse --short=7 HEAD` cho chắc.

**SHA nào?** Với sự kiện `push`, đó là commit vừa vào `main`. Với `pull_request`, GitHub chạy workflow trên một **merge commit tạm** (`refs/pull/<số>/merge`) — SHA này không tồn tại trên nhánh nào ([bài 02](02-github-actions-basics.md)). Không sao, vì trên PR ta **không push** image. (Nếu muốn dùng SHA của commit đầu nhánh PR, metadata-action có biến `DOCKER_METADATA_PR_HEAD_SHA=true` — 🟨.)

**Các loại tag khác bạn sẽ thấy trong tài liệu:**

| Khai báo | Tag Git `v0.3.0` cho ra | Ghi chú |
|---|---|---|
| `type=semver,pattern={{version}}` | `0.3.0` | **Bỏ chữ `v`** |
| `type=semver,pattern={{major}}.{{minor}}` | `0.3` | Tag "dời" — không bất biến |
| `type=ref,event=tag` | `v0.3.0` | **Giữ nguyên** tên tag Git |
| `type=ref,event=pr` | `pr-12` | Mặc định trên `pull_request` |
| `type=sha,prefix=` | `9f8e7d6` | Dùng trong `ci.yml` |

Dự án giữ chữ `v` trong tag image (`:v0.3.0`) cho khớp [Git 05](../03-GIT/05-tags-releases-versioning.md) và [Docker 06](../04-DOCKER/06-registry.md). Vì `release.yml` không build lại image (mục 4.8), ta không cần metadata-action ở đó — tag lấy thẳng từ tên tag Git.

**Output quan trọng:**

| Output | Nội dung | Dùng ở |
|---|---|---|
| `tags` | Danh sách tag đầy đủ, **mỗi tag một dòng** | `tags:` của build-push-action |
| `labels` | Label OCI: `org.opencontainers.image.source`, `revision` (SHA đầy đủ), `created`… | `labels:` của build-push-action |
| `json` | Tag + label dạng JSON | Lấy một tag cụ thể: `fromJSON(steps.meta.outputs.json).tags[0]` |

Vì `tags` có thể nhiều dòng, khi cần **đúng một** tên image (ví dụ cho Trivy), lấy phần tử đầu của mảng `tags` trong output `json` — an toàn hơn dùng thẳng chuỗi nhiều dòng.

### 4.4. 🟥 `docker/build-push-action` — build image

```yaml
- name: Build image
  uses: docker/build-push-action@v7
  with:
    context: .
    file: docker/Dockerfile
    load: true
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

| Tham số | Ý nghĩa | Liên hệ |
|---|---|---|
| `context: .` | Build context = **gốc repo** (sau checkout) | Giống `docker build -f docker/Dockerfile .` ở [Docker 03](../04-DOCKER/03-dockerfile-multistage.md) — `COPY app/...` cần thấy thư mục `app/` |
| `file: docker/Dockerfile` | Đường dẫn Dockerfile, tính từ gốc repo | Bỏ dòng này → action tìm `./Dockerfile` → lỗi |
| `load: true` | Nạp image vào Docker của runner | Để bước Trivy quét được |
| `tags`, `labels` | Lấy từ metadata-action | Label `revision` giúp tra "image này từ commit nào" bằng `docker image inspect` |
| `cache-from: type=gha` | Đọc cache layer từ GitHub Actions cache | Lần build sau chỉ build lại layer thay đổi |
| `cache-to: type=gha,mode=max` | Ghi cache | `mode=max` ghi cache cho **mọi** stage (cả stage `build` có Maven dependency), không chỉ layer của image cuối |

**Cache hoạt động thế nào?** Đúng nguyên lý layer cache ở [Docker 03](../04-DOCKER/03-dockerfile-multistage.md): Dockerfile copy `pom.xml` và tải dependency **trước**, copy `src/` **sau**. Sửa một file Java → layer `dependency:go-offline` vẫn lấy từ cache → build nhanh hơn nhiều. Sửa `pom.xml` → tải lại dependency.

Hai giới hạn cần biết (tài liệu Docker và GitHub):

- Một lần chạy chỉ đọc được cache của **nhánh hiện tại, nhánh base và nhánh mặc định**. PR mới mở dùng được cache của `main`, nhưng hai nhánh feature không dùng cache của nhau.
- Cache của GitHub Actions có giới hạn dung lượng mỗi repo (10 GB trên gói Free theo trang billing của GitHub) và cache cũ bị xóa dần. Cache là **tăng tốc**, không bao giờ là thứ build phụ thuộc vào.

> `build-push-action` tự lấy token và URL cần cho `type=gha` từ môi trường runner. Nếu bạn tự gõ `docker buildx build --cache-to type=gha` trong bước `run:`, nó sẽ không có các biến đó (tài liệu Docker có nói) — một lý do nữa để dùng action.

### 4.5. 🟥 Quét trước khi push — Trivy làm cổng chặn

```yaml
- name: Scan image (Trivy)
  uses: aquasecurity/trivy-action@v0.36.0
  with:
    image-ref: ${{ fromJSON(steps.meta.outputs.json).tags[0] }}
    format: table
    severity: CRITICAL
    ignore-unfixed: true
    exit-code: '1'
```

| Tham số | Ý nghĩa |
|---|---|
| `image-ref` | Image cần quét — chính image vừa `load` vào Docker của runner |
| `format: table` | In bảng giống khi bạn chạy Trivy ở [Docker 07](../04-DOCKER/07-docker-security.md) |
| `severity: CRITICAL` | Chỉ xét lỗ hổng mức CRITICAL |
| `ignore-unfixed: true` | Bỏ qua lỗ hổng **chưa có bản vá** (theo tài liệu Trivy: chỉ hiện lỗ hổng đã có fix) |
| `exit-code: '1'` | Tìm thấy lỗ hổng thỏa điều kiện → Trivy thoát mã 1 → bước đỏ → job dừng → **các bước push phía sau không chạy** |

Mặc định `exit-code` là `0` — tức Trivy chỉ **báo cáo**, không chặn gì. Quên `exit-code: '1'` là lỗi rất phổ biến: pipeline "có quét" nhưng không bao giờ đỏ.

**Vì sao cổng chặn chỉ là CRITICAL, không phải HIGH?**

[Docker 07](../04-DOCKER/07-docker-security.md) đặt mục tiêu: *không còn CRITICAL/HIGH có bản vá mà chưa vá*. Mục tiêu vẫn giữ nguyên, nhưng **cổng chặn tự động** ở v1 chỉ đặt ở CRITICAL vì:

- Lỗ hổng mới được công bố **mỗi ngày**. Một sáng thứ Hai, Ubuntu công bố bản vá cho một lỗi HIGH trong gói của base image → **mọi PR** đều đỏ, dù không ai sửa gì liên quan. Pipeline đỏ vì lý do ngoài tầm kiểm soát của PR → mọi người quen bỏ qua màu đỏ — tệ hơn không có cổng.
- Lỗi HIGH vẫn được xử lý, nhưng bằng **quy trình**: Dependabot mở PR cập nhật base image ([bài 04](04-secrets-environments.md)), rebuild định kỳ, và bước báo cáo HIGH (bài tập 1 ở mục 14).
- [Module 10](../00-ROADMAP/curriculum-structure.md) (tuần 21) siết dần khi quy trình cập nhật đã chạy ổn.

Đây là một **đánh đổi có ý thức** — loại câu trả lời người phỏng vấn muốn nghe, thay vì "em chặn hết cho an toàn".

**Khi phải bỏ qua một lỗ hổng: `.trivyignore`.** Chỉ dùng khi đã xác minh là dương tính giả hoặc đã chấp nhận rủi ro có thời hạn. Theo tài liệu Trivy, mỗi dòng một mã, có thể thêm hạn `exp:`:

```text
# .trivyignore (ở gốc repo)
# Dương tính giả: Trivy nhận diện sai phiên bản thư viện X trong jar — đã kiểm tra bằng mvn dependency:tree.
# Người duyệt: phuong-dev · Xem lại trước 2026-12-31
CVE-2026-12345 exp:2026-12-31
```

Quy tắc của dự án: mỗi dòng bỏ qua phải có **lý do + người duyệt + hạn**. Hết hạn → Trivy lại báo → buộc phải xem lại. Trong trivy-action, trỏ tới file bằng tham số `trivyignores: .trivyignore`.

### 4.6. 🟥 Đăng nhập GHCR bằng `GITHUB_TOKEN`

```yaml
image:
  permissions:
    contents: read
    packages: write
  steps:
    # ...
    - name: Log in to GHCR
      if: github.event_name == 'push'
      uses: docker/login-action@v4
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
```

| Thành phần | Ý nghĩa |
|---|---|
| `permissions: packages: write` | Cho `GITHUB_TOKEN` của job này quyền ghi package. Khai báo `permissions` ở job **thay thế** quyền ở đầu file cho job đó, nên phải ghi lại cả `contents: read` (để checkout) |
| `if: github.event_name == 'push'` | Chỉ đăng nhập khi sự kiện là push vào `main`. Trên PR, bước này hiện **skipped** |
| `username: ${{ github.actor }}` | Người kích hoạt workflow |
| `password: ${{ secrets.GITHUB_TOKEN }}` | Token tự động, hết hạn khi job kết thúc. **Không cần tạo PAT** như ở Docker 06 |

Tài liệu GitHub khuyến nghị dùng `GITHUB_TOKEN` thay cho PAT để publish package từ workflow, và package publish bằng `GITHUB_TOKEN` được **tự liên kết** với repo chứa workflow. [Bài 04](04-secrets-environments.md) giải thích kỹ `GITHUB_TOKEN` và nguyên tắc quyền tối thiểu.

> **Đánh đổi nhỏ:** `packages: write` được cấp cho cả job, kể cả khi chạy trên PR (dù bước push bị skip). PR từ **fork** luôn nhận token chỉ đọc nên không đáng lo; PR trong repo chỉ do người có quyền ghi repo mở. Tách job push riêng là cách chặt hơn — bài 04 bàn thêm.

**Trường hợp đặc biệt của bạn: package `taskhub` đã tồn tại từ tuần 8.**

Ở [Docker 06](../04-DOCKER/06-registry.md) bạn đã push `ghcr.io/<user>/taskhub:v0.2.0` bằng PAT từ laptop. Tài liệu GitHub nói rõ: workflow **không có quyền push** vào một package đã được push trước đó mà **chưa kết nối với repo**; với package có sẵn, phải **cấp quyền tường minh** cho repo chứa workflow.

- Nếu tuần 8 bạn đã thêm `LABEL org.opencontainers.image.source` và package hiện trên trang repo → nhiều khả năng đã kết nối, workflow push được ngay.
- Nếu push báo `denied: permission_denied: write_package` (hoặc `403 Forbidden`):
  1. Mở trang package `taskhub` → **Package settings**.
  2. Mục **Manage Actions access** → **Add repository** → chọn repo `taskhub`.
  3. Ở menu **Role** chọn **Write** (theo bảng quyền của GitHub, Write là mức thấp nhất được upload).
  4. Quay lại workflow → **Re-run failed jobs**.

### 4.7. 🟥 Push đúng image vừa quét

```yaml
- name: Push image
  if: github.event_name == 'push'
  uses: docker/build-push-action@v7
  with:
    context: .
    file: docker/Dockerfile
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    cache-from: type=gha
```

"Build lại để push" nghe có vẻ trái với nguyên tắc build một lần. Thực tế:

- Cùng builder, cùng context, cùng Dockerfile, cùng `tags`/`labels` (lấy từ **cùng** một bước `meta`, nên cả label thời gian `created` cũng giống) → BuildKit lấy **toàn bộ** layer từ cache của chính lần build trước. Log sẽ thấy hầu hết các dòng `CACHED`.
- Image được push có **cùng layer và config** với image vừa được Trivy quét. Bước này chỉ đổi nơi xuất (từ "nạp vào Docker" sang "đẩy lên registry").

Một khác biệt bạn sẽ thấy: image trên registry là **image index**, không phải manifest đơn. Theo tài liệu Docker:

- Khi image được **push** từ `build-push-action`, attestation **provenance** được tự động thêm: repo **public** dùng `mode=max`, repo private dùng `mode=min`.
- Với `load: true`, **không** có attestation (Docker daemon không lưu được) — nên image trong bước Trivy là manifest đơn.
- Attestation nằm trong image index dưới dạng manifest có platform `unknown/unknown`.

Vì vậy trang package trên GHCR hiện **hai** dòng: `linux/amd64` (image thật) và `unknown/unknown` (attestation). Đây **không phải lỗi**. Nhiều người hỏi trên GitHub Community vì tưởng image bị hỏng; một số chọn tắt (`provenance: false`) — đổi lại mất thông tin nguồn gốc. Dự án giữ mặc định.

### 4.8. 🟥 `release.yml` — phát hành bằng cách gắn tag, không build lại

```yaml
name: Release

on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  promote:
    name: promote
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    permissions:
      contents: write   # tạo GitHub Release
      packages: write   # gắn thêm tag cho image trên GHCR
    steps:
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v4

      - name: Log in to GHCR
        uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Promote image
        env:
          TAG: ${{ github.ref_name }}
        run: |
          owner="${GITHUB_REPOSITORY_OWNER,,}"
          image="ghcr.io/${owner}/taskhub"
          sha="${GITHUB_SHA::7}"

          if ! docker buildx imagetools inspect "${image}:${sha}" > /dev/null 2>&1; then
            echo "::error::Không tìm thấy ${image}:${sha}. Commit này đã nằm trên main và CI đã xanh chưa?"
            exit 1
          fi

          docker buildx imagetools create --tag "${image}:${TAG}" "${image}:${sha}"
          docker buildx imagetools inspect "${image}:${TAG}"

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ github.ref_name }}
        run: gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --generate-notes
```

Đi từng phần:

**Trigger `tags: ['v*.*.*']`.** Mẫu lọc dùng glob: `*` khớp một chuỗi bất kỳ (không chứa `/`). Vậy:

| Tag Git | Khớp `v*.*.*`? | Vì sao |
|---|---|---|
| `v0.3.0` | ✅ | |
| `v0.3.0-rc.1` | ✅ | `*` cuối khớp `0-rc.1` — tag tiền phát hành **cũng** kích hoạt release |
| `v1.2` | ❌ | Chỉ có một dấu chấm |
| `0.3.0` | ❌ | Thiếu `v` |

Lưu ý quan trọng từ tài liệu GitHub: *push hơn ba tag cùng lúc thì không tạo sự kiện cho các tag đó* → `git push --tags` với nhiều tag cũ sẽ **không** kích hoạt release. Luôn push từng tag: `git push origin v0.3.0`.

**Workflow chạy file nào?** Với sự kiện push tag, GitHub dùng file workflow **trong commit được tag**. Tag một commit cũ, từ trước khi có `release.yml` → không có gì chạy.

**`concurrency` không hủy.** Một lần release đang gắn tag và tạo Release mà bị hủy giữa chừng sẽ để lại trạng thái dở dang. Release chạy tuần tự, không hủy.

**`permissions` riêng cho job.** `contents: write` để tạo GitHub Release, `packages: write` để ghi tag mới vào package. Không job nào trong `ci.yml` có `contents: write`.

**Không có `actions/checkout`.** Job này không cần mã nguồn — nó chỉ làm việc với registry và API GitHub. Ít bước = ít thứ có thể hỏng, ít quyền bị dùng.

**Script `Promote image`:**

| Dòng | Giải thích |
|---|---|
| `TAG: ${{ github.ref_name }}` trong `env:` | Tên tag (ví dụ `v0.3.0`). Đưa vào biến môi trường thay vì viết `${{ github.ref_name }}` thẳng trong script — tránh lỗi chèn mã (script injection), [bài 04](04-secrets-environments.md) giải thích |
| `${GITHUB_REPOSITORY_OWNER,,}` | Bash: `,,` chuyển toàn bộ giá trị biến sang **chữ thường**. Ở đây không có metadata-action tự làm việc đó, mà tên repository trên registry bắt buộc chữ thường ([Docker 06 §4.4](../04-DOCKER/06-registry.md#44--docker-tag--đặt-thêm-tên-không-sao-chép)) |
| `${GITHUB_SHA::7}` | Bash: lấy 7 ký tự đầu. Với push tag, `GITHUB_SHA` là commit mà tag trỏ tới (tài liệu: *tip commit pushed to the ref*). **Phải cùng độ dài** với `type=sha` của metadata-action (7) — đổi một bên mà quên bên kia → không bao giờ tìm thấy image |
| `docker buildx imagetools inspect ... > /dev/null 2>&1` | Hỏi registry xem tag có tồn tại không. Chỉ quan tâm mã thoát |
| `echo "::error::..."` | **Workflow command**: GitHub hiện dòng này thành chú thích lỗi màu đỏ ở trang tóm tắt lần chạy — người đọc thấy ngay lý do, không phải mở log |
| `imagetools create --tag <đích> <nguồn>` | Tạo tag mới trên registry từ image có sẵn. Tài liệu Docker: nguồn là **image index** → tạo **bản sao y hệt** (carbon copy). Không tải layer về runner, không build |
| `imagetools inspect "${image}:${TAG}"` | In kết quả vào log làm bằng chứng — đối chiếu digest với tag SHA |

**Tạo GitHub Release.** `gh` (GitHub CLI) có sẵn trên runner. Theo tài liệu `gh release create`:

- `--verify-tag`: **hủy** nếu tag chưa tồn tại trên remote. Không có cờ này, `gh` sẽ **tự tạo tag** từ nhánh mặc định nếu tag không có — hành vi nguy hiểm trong pipeline.
- `--generate-notes`: sinh tiêu đề và ghi chú từ API Release Notes của GitHub (danh sách PR đã merge từ release trước).
- `GH_TOKEN`: `gh` đọc token từ biến này.

### 4.9. 🟥 Chỉ tag sau khi CI trên `main` đã xanh

Release **phụ thuộc** vào image mà CI tạo ra. Thứ tự đúng:

```text
merge PR → CI trên main chạy (≈ vài phút) → ✅ image :<sha7> đã có trên GHCR → git tag + push tag → Release
```

Nếu bạn tag ngay sau khi merge, lúc job `promote` chạy CI có thể chưa push xong → `::error::Không tìm thấy ...`. Đó là **hành vi đúng**: pipeline từ chối phát hành thứ chưa được kiểm chứng. Cách xử lý:

1. Chờ CI trên `main` xanh.
2. Mở lần chạy Release bị đỏ → **Re-run jobs** → **Re-run failed jobs**.

Re-run dùng lại **đúng `GITHUB_SHA` và `GITHUB_REF`** của sự kiện ban đầu (tài liệu GitHub), nên nó tìm đúng image vừa được CI push. Bạn sẽ tự tạo tình huống này trong [Lab 02](labs/lab-02-release-ghcr.md).

Hệ quả khác của thiết kế: tag một commit **không nằm trên `main`** (ví dụ commit trên nhánh feature) → CI không bao giờ push image cho commit đó → release luôn thất bại. Đây là một **hàng rào an toàn**: chỉ code đã vào `main` mới phát hành được.

### 4.10. 🟨 Tag tiền phát hành và nhãn "Latest" của GitHub Release

Vì `v0.3.0-rc.1` cũng khớp trigger, workflow trên sẽ tạo một GitHub Release **bình thường** cho nó. Theo tài liệu `gh release create`, nhãn "Latest" mặc định được chọn **tự động theo ngày và phiên bản**, và `gh` **không** tự đánh dấu pre-release chỉ vì tên tag có dấu `-`. Muốn đúng nghĩa SemVer, phải tự thêm cờ `--prerelease` khi tag có phần tiền phát hành. Bạn sẽ quan sát điều này trong Lab 02 và tự sửa ở [bài tập 2](#14-bài-tập-tự-làm).

### 4.11. 🟦 Attestation ký số, SBOM, đa kiến trúc

- **`actions/attest@v4`**: ví dụ chính thức của GitHub về publish image có thêm bước tạo **artifact attestation** — một chứng thực được ký, ai pull image cũng kiểm tra được image được build bởi workflow nào. Cần thêm quyền `attestations: write` và `id-token: write`. Học kỹ ở Module 10.
- **SBOM**: `build-push-action` không tự thêm SBOM; bật bằng `sbom: true` (tài liệu Docker).
- **Đa kiến trúc** (`platforms: linux/amd64,linux/arm64`): cần khi chạy trên máy ARM (ví dụ EC2 Graviton). Dự án dùng amd64 nên chưa cần.

### 4.12. Gặp lại ở đâu

| Ở đây | Gặp lại |
|---|---|
| Image `:<sha7>` trên GHCR | CD tự động lên EC2 — dự án v3 (Module 06) |
| Gắn tag thay vì build lại, rollback bằng tag cũ | [Bài 05 — Deployment strategies & rollback](05-deployment-strategies-rollback.md), runbook rollback (Module 08) |
| `permissions`, `GITHUB_TOKEN`, ghim SHA | [Bài 04 — Secrets & environments](04-secrets-environments.md) |
| Trivy trong CI | DevSecOps (Module 10): quét dependency, secret, cấu hình |
| Image index, platform | Kubernetes kéo image theo kiến trúc node (Module 09) |
| ECR thay cho GHCR | Module 06 — đăng nhập bằng IAM/OIDC, không dùng `GITHUB_TOKEN` |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Image phát hành chứa code chưa ai review

Một team để kỹ sư trưởng build và push image phát hành từ laptop. Một hôm anh ấy đang thử nghiệm một thay đổi chưa commit, quên `git stash`, rồi build `v2.4.0`. Production chạy code không có trong Git, không có PR, không có test. Mất hai ngày mới tìm ra vì không ai tái hiện được lỗi từ mã nguồn. Bài học: image triển khai chỉ được tạo bởi pipeline, từ một commit cụ thể — label `org.opencontainers.image.revision` do metadata-action gắn cho bạn tra ngược ngay.

### Ví dụ 2: "Build lại khi phát hành" kéo về base image mới

Pipeline của một team build lại image ở bước release. Đêm trước, base image cùng tag được cập nhật một bản vá có thay đổi hành vi TLS. Image `v1.8.0` khác hoàn toàn image đã chạy staging cả tuần, và lỗi chỉ xuất hiện trên production. Gắn tag cho image đã test (như `release.yml` của bạn) loại bỏ hẳn loại lỗi này.

### Ví dụ 3: Cổng quét quá chặt

Một team đặt cổng `HIGH,CRITICAL` không kèm `ignore-unfixed`. Base image có vài lỗi HIGH **chưa có bản vá** → pipeline đỏ vĩnh viễn → team thêm `continue-on-error: true` cho bước quét "tạm thời". Sáu tháng sau, một lỗi CRITICAL có bản vá lọt qua vì không ai còn nhìn bước đó. Cổng chặn phải **đỏ hiếm nhưng đỏ thật**.

---

## 6. Sơ đồ kiến trúc

### 6.1. Luồng từ PR đến release

```text
 [GitHub] nhánh ci/... ──PR──►  CI ─┬─ build-test ✅
                                    └─ image: build(load) → Trivy ✅ → login ⏭ skipped → push ⏭ skipped
                                         │ branch protection: cả hai check phải xanh
                                         ▼
 merge (squash) vào main ──────►  CI ─┬─ build-test ✅
                                    └─ image: build(load) → Trivy ✅ → login GHCR → push
                                                                                   │
                                                                                   ▼
                                                    ghcr.io/phuong-dev/taskhub:4c1d9e2  ──► sha256:77ab… (index)
                                                                                   ▲
 git tag -a v0.3.0 4c1d9e2 ; git push origin v0.3.0                                │ imagetools create
                                ──────────────►  Release: promote ──────────────────┘ (gắn :v0.3.0, không build)
                                                         └─► gh release create v0.3.0 --generate-notes
```

### 6.2. Trạng thái registry sau release

```text
ghcr.io/phuong-dev/taskhub
  :a1b2c3d  ─┐                               (tuần 8, push tay từ laptop)
  :v0.2.0   ─┴─► sha256:4f9c…
  :4c1d9e2  ─┐                               (CI push khi merge vào main)
  :v0.3.0   ─┴─► sha256:77ab…  image index
                    ├── linux/amd64        → manifest: config + layers (image chạy được)
                    └── unknown/unknown    → attestation manifest (provenance)
```

`:4c1d9e2` và `:v0.3.0` có **cùng digest** — đó là bằng chứng "image phát hành chính là image đã test và quét".

---

## 7. Các câu lệnh cần biết

| Lệnh / khai báo | Mục đích | Mức |
|---|---|---|
| `docker/setup-buildx-action` | Tạo builder `docker-container` trên runner | 🟥 |
| `docker/metadata-action` | Sinh tag + label OCI | 🟥 |
| `docker/build-push-action` (`load` / `push`, `cache-from/to`) | Build, nạp hoặc đẩy image | 🟥 |
| `aquasecurity/trivy-action` (`severity`, `ignore-unfixed`, `exit-code`) | Quét lỗ hổng, chặn pipeline | 🟥 |
| `docker/login-action` + `permissions: packages: write` | Đăng nhập GHCR bằng `GITHUB_TOKEN` | 🟥 |
| `docker buildx ls` | Xem các builder trên máy | 🟨 |
| `docker buildx build -f ... --load .` | Build như CI, ngay trên máy | 🟥 |
| `docker buildx imagetools inspect <image>` | Xem manifest/index trên registry, không cần pull | 🟥 |
| `docker buildx imagetools create --tag <đích> <nguồn>` | Gắn thêm tag trên registry, không build | 🟥 |
| `git rev-parse --short=7 HEAD` | SHA 7 ký tự — khớp tag image | 🟥 |
| `git tag -a v0.3.0 -m "..."` · `git push origin v0.3.0` | Tạo và đẩy **một** tag | 🟥 (ôn [Git 05](../03-GIT/05-tags-releases-versioning.md)) |
| `gh release create <tag> --verify-tag --generate-notes` | Tạo GitHub Release từ tag có sẵn | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa** (đã rút gọn; digest và SHA là giả). Username minh họa: `phuong-dev`.

### `docker buildx ls` `[WSL]`

```bash
docker buildx ls
```

```text
NAME/NODE             DRIVER/ENDPOINT   STATUS    BUILDKIT   PLATFORMS
default               docker
 \_ default            \_ default       running   v0.2x.x    linux/amd64, linux/arm64, ...
desktop-linux*        docker
 \_ desktop-linux      \_ desktop-linux running   v0.2x.x    linux/amd64, linux/arm64, ...
```

- Trên Docker Desktop, các builder mặc định dùng driver `docker`. Dấu `*` là builder đang được chọn.
- Trên runner, sau `setup-buildx-action`, bạn sẽ thấy trong log một builder mới driver `docker-container`.

### Build giống hệt CI `[WSL]`

```bash
cd ~/projects/taskhub
docker buildx build -f docker/Dockerfile -t taskhub:ci-local --load .
```

| Phần | Tương ứng trong workflow |
|---|---|
| `-f docker/Dockerfile` | `file: docker/Dockerfile` |
| `-t taskhub:ci-local` | `tags:` (CI dùng tên GHCR) |
| `--load` | `load: true` |
| `.` (cuối lệnh) | `context: .` — **gốc repo** |

### Log của bước `Image metadata` `[Runner]`

```text
Context info
  eventName: push
  sha: 4c1d9e2f0b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d
  ref: refs/heads/main
Docker tags
  ghcr.io/phuong-dev/taskhub:4c1d9e2
Docker labels
  org.opencontainers.image.created=2026-11-10T03:21:07.000Z
  org.opencontainers.image.revision=4c1d9e2f0b8a7c6d5e4f3a2b1c0d9e8f7a6b5c4d
  org.opencontainers.image.source=https://github.com/phuong-dev/taskhub
  ...
```

Đọc ba thứ: `eventName` (push hay pull_request), tag sinh ra có đúng 7 ký tự và chữ thường không, label `revision` có đúng commit không.

### Log của bước `Build image` — lần thứ hai, chỉ sửa code Java `[Runner]`

```text
#5 importing cache manifest from gha:...
#10 [build 4/7] COPY app/mvnw app/pom.xml ./
#10 CACHED
#11 [build 5/7] RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline
#11 CACHED
#12 [build 6/7] COPY app/src/ src/
#12 DONE 0.1s
#13 [build 7/7] RUN ./mvnw -B -q package -DskipTests && cp target/*.jar app.jar
#13 DONE 41.3s
#16 exporting to docker image format
#16 DONE 4.2s
```

- `CACHED` ở bước tải dependency = cache `type=gha` đang hoạt động.
- Từ `COPY app/src/` trở đi chạy lại vì code đổi — đúng như [Docker 03](../04-DOCKER/03-dockerfile-multistage.md) dự đoán.

### Log của bước Trivy khi có lỗi chặn `[Runner]`

```text
ghcr.io/phuong-dev/taskhub:4c1d9e2 (ubuntu 24.04)
Total: 1 (CRITICAL: 1)

┌──────────┬────────────────┬──────────┬────────┬───────────────────┬────────────────┬───────────────┐
│ Library  │ Vulnerability  │ Severity │ Status │ Installed Version │ Fixed Version  │ Title         │
├──────────┼────────────────┼──────────┼────────┼───────────────────┼────────────────┼───────────────┤
│ libexamp │ CVE-2026-XXXXX │ CRITICAL │ fixed  │ 1.2.3-1ubuntu1    │ 1.2.3-1ubuntu2 │ ...           │
└──────────┴────────────────┴──────────┴────────┴───────────────────┴────────────────┴───────────────┘
Error: Process completed with exit code 1.
```

`Status: fixed` + có `Fixed Version` → bản vá đã có. Thường chỉ cần base image mới: Dependabot PR cập nhật base image, hoặc build lại với base image mới nhất cùng tag.

### `docker buildx imagetools inspect` `[WSL]`

```bash
docker buildx imagetools inspect ghcr.io/phuong-dev/taskhub:4c1d9e2
```

```text
Name:      ghcr.io/phuong-dev/taskhub:4c1d9e2
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:77ab...

Manifests:
  Name:        ghcr.io/phuong-dev/taskhub:4c1d9e2@sha256:1e5f...
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    linux/amd64

  Name:        ghcr.io/phuong-dev/taskhub:4c1d9e2@sha256:9c0d...
  MediaType:   application/vnd.oci.image.manifest.v1+json
  Platform:    unknown/unknown
  Annotations:
    vnd.docker.reference.digest: sha256:1e5f...
    vnd.docker.reference.type:   attestation-manifest
```

| Dòng | Ý nghĩa |
|---|---|
| `MediaType: ...image.index...` | Tag trỏ tới một **image index** |
| `Digest` (đầu tiên) | Digest của index — giá trị cần so sánh giữa `:4c1d9e2` và `:v0.3.0` |
| `Platform: linux/amd64` | Image chạy được |
| `Platform: unknown/unknown` + `attestation-manifest` | Attestation provenance, trỏ tới image amd64 qua `reference.digest` |

- Lệnh này đọc thẳng từ registry, **không pull** image. Image public không cần đăng nhập.
- Xem riêng provenance (🟨): thêm `--format '{{ json .Provenance }}'`.

### `docker buildx imagetools create` `[Runner]` (hoặc `--dry-run` trên `[WSL]`)

```bash
docker buildx imagetools create --tag ghcr.io/phuong-dev/taskhub:v0.3.0 ghcr.io/phuong-dev/taskhub:4c1d9e2
```

| Phần | Ý nghĩa |
|---|---|
| `--tag <đích>` | Tên sẽ được tạo trên registry |
| `<nguồn>` | Image có sẵn. Nguồn là index → bản sao y hệt, cùng digest |
| `--dry-run` | Chỉ in kết quả, **không push** — dùng để học an toàn trên máy |

> Theo tài liệu Docker: nếu nguồn là **manifest đơn** (không phải index), mặc định lệnh sẽ tạo ra một **index mới** bọc manifest đó (`--prefer-index=true`) → digest **khác** nguồn. Image do CI push luôn là index (có attestation), nên trong `release.yml` digest được giữ nguyên.

### `git tag` + `git push` một tag `[WSL]`

```bash
git switch main && git pull
git rev-parse --short=7 HEAD                 # 4c1d9e2 — phải trùng tag image CI vừa push
git tag -a v0.3.0 -m "taskhub v0.3.0 — CI/CD v1"
git push origin v0.3.0
```

- Tag **annotated** (`-a`) như quy ước ở [Git 05](../03-GIT/05-tags-releases-versioning.md).
- `git push origin v0.3.0` — đẩy **một** tag. Không dùng `--tags`.

---

## 9. Bài thực hành từng bước

**Lab tại chỗ: hiểu và viết job `image` + `release.yml` trước khi chạy thật** · `[WSL]` · ~75 phút

Phần chạy thật trên GitHub (push, required check, tag, release) nằm ở [Lab 02 — Release lên GHCR](labs/lab-02-release-ghcr.md). Ở đây bạn làm mọi thứ có thể làm **trên máy**, không tạo gì trên GitHub.

Điều kiện: repo `~/projects/taskhub` đã có `ci.yml` với job `build-test` ([Lab 01](labs/lab-01-ci-pr-gate.md)); Docker Desktop đang chạy; image `ghcr.io/<user>/taskhub:v0.2.0` từ tuần 8 đã ở chế độ public.

### Bước 1 — Kiểm tra Buildx

```bash
docker buildx version
docker buildx ls
```

❓ Builder đang chọn dùng driver gì? Driver đó có xuất cache `type=gha` được không (mục 3.2)?

### Bước 2 — Build giống CI

```bash
cd ~/projects/taskhub
git status --short                      # phải sạch — vì sao quan trọng?
docker buildx build -f docker/Dockerfile -t taskhub:ci-local --load .
docker image inspect --format '{{json .Config.Labels}}' taskhub:ci-local
```

❓ Image build trên máy có label `org.opencontainers.image.revision` không? Ai sẽ gắn label đó trong CI?

### Bước 3 — Thử cổng chặn của Trivy

Dùng cùng cách chạy Trivy như [Docker 07](../04-DOCKER/07-docker-security.md), nhưng với **đúng điều kiện của CI**:

```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.cache/trivy:/root/.cache/" \
  aquasec/trivy:0.76.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 taskhub:ci-local
echo "exit=$?"
```

Chạy lại lần hai với `--severity HIGH,CRITICAL` (vẫn `--exit-code 1`, bỏ `--ignore-unfixed`).

❓ Mã thoát của hai lần chạy là gì? Nếu dùng cấu hình lần hai làm cổng chặn, pipeline sẽ xanh hay đỏ hôm nay? Còn tuần sau?

### Bước 4 — Đọc cấu trúc image trên registry

```bash
docker buildx imagetools inspect eclipse-temurin:21-jre-noble
docker buildx imagetools inspect ghcr.io/<user>/taskhub:v0.2.0
```

❓ `eclipse-temurin` có bao nhiêu platform? Image `v0.2.0` bạn push tay ở tuần 8 là index hay manifest đơn (xem `MediaType`)? Có dòng `unknown/unknown` không?

### Bước 5 — Thử "promote" mà không push

```bash
GITHUB_REPOSITORY_OWNER=Phuong-Dev          # giả lập có chữ hoa
echo "${GITHUB_REPOSITORY_OWNER,,}"
GITHUB_SHA=$(git rev-parse HEAD)
echo "${GITHUB_SHA::7}  vs  $(git rev-parse --short=7 HEAD)"

docker buildx imagetools create --dry-run \
  --tag ghcr.io/<user>/taskhub:v0.2.0-copy ghcr.io/<user>/taskhub:v0.2.0
```

❓ JSON in ra có `mediaType` là gì? So với `MediaType` của nguồn ở Bước 4 — đây là bản sao y hệt hay một index mới bọc lấy? Dựa vào mục 8, digest đích có trùng nguồn không?

### Bước 6 — Viết job `image`

Tạo nhánh và mở `ci.yml`:

```bash
git switch -c ci/build-push-image
```

Thêm job `image` sau job `build-test`. **Tự viết**, dùng khung sau và trả lời từng ❓ bằng comment ngay trong file:

```yaml
  image:
    name: image
    needs: ???                 # ❓ vì sao image phải chờ job này?
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    permissions:
      ???                      # ❓ hai quyền nào? vì sao phải ghi lại cả quyền đọc code?
    steps:
      # 1. checkout (persist-credentials: false)
      # 2. setup-buildx
      # 3. metadata: tag SHA 7 ký tự không tiền tố, không latest
      # 4. build: load vào Docker, cache gha mode=max
      # 5. Trivy: chặn CRITICAL có bản vá
      # 6. login GHCR — chỉ khi sự kiện là push
      # 7. build lại với push: true — chỉ khi sự kiện là push
```

### Bước 7 — Viết `release.yml`

Tạo `.github/workflows/release.yml` theo mục 4.8 — gõ lại, **không copy-paste**, và chú thích từng dòng của script `Promote image` bằng lời của bạn.

### Bước 8 — Kiểm tra cú pháp bằng actionlint

```bash
docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:latest -color
```

Lệnh lấy từ tài liệu chính thức của actionlint (dùng tag `latest` như tài liệu; đây là công cụ chạy trên máy, không phải image triển khai). Sửa đến khi không còn lỗi. **Chưa push** — Lab 02 sẽ làm tiếp.

### Bước 9 — So với bản tham khảo

Chỉ sau khi đã xong Bước 6–8: mở [bản tham khảo ci.yml](labs/reference/workflows/ci.yml) và [release.yml](labs/reference/workflows/release.yml). Ghi lại mọi chỗ khác nhau và **lý do** vào `~/devops-journey/week10/lesson03-notes.md`.

---

## 10. Kết quả mong đợi

- **Bước 1:** builder mặc định trên Docker Desktop dùng driver `docker`. Driver này chỉ xuất được cache `type=gha` khi bật containerd image store — trên runner ta không phụ thuộc vào điều đó, `setup-buildx-action` tạo builder `docker-container`.
- **Bước 2:** working tree phải sạch vì build context lấy file **trên đĩa**, kể cả file chưa commit — đúng lý do CI tốt hơn laptop. Image local **không** có label `revision` (trừ khi bạn tự thêm); trong CI metadata-action gắn nó.
- **Bước 3:** lần một thường thoát `0` (hiếm khi có CRITICAL đã có bản vá trong base image vừa cập nhật). Lần hai dễ thoát `1` vì có HIGH chưa có bản vá — cổng như vậy sẽ đỏ vì thứ bạn không sửa được. Kết quả cụ thể phụ thuộc ngày bạn chạy; điều quan trọng là bạn giải thích được.
- **Bước 4:** `eclipse-temurin:21-jre-noble` là index nhiều platform (amd64, arm64…). Image `v0.2.0` push tay: tùy cấu hình Docker Desktop (có dùng containerd image store hay không) mà có thể là manifest đơn hoặc index — ghi lại bạn thấy gì.
- **Bước 5:** `phuong-dev`; hai chuỗi SHA trùng nhau. Nếu nguồn là manifest đơn → dry-run in ra một **index mới** (digest khác nguồn). Nếu nguồn là index → bản sao y hệt. Image CI push luôn là index, nên `release.yml` giữ nguyên digest.
- **Bước 6–7:** `needs: build-test` (không build image cho code test đỏ); `permissions` gồm `contents: read` + `packages: write` — khai báo ở job **thay thế** quyền mặc định của file nên thiếu `contents: read` là checkout lỗi.
- **Bước 8:** actionlint không báo lỗi.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `denied: permission_denied: write_package` / `403 Forbidden` khi push | Package có từ trước (push tay tuần 8) chưa cấp quyền cho repo; hoặc job thiếu `packages: write` | Package settings → **Manage Actions access** → Add repository → Role **Write**; kiểm tra `permissions` của job |
| `Cache export is not supported for the docker driver` | Quên `setup-buildx-action` → dùng builder driver `docker` | Thêm bước setup-buildx trước bước build |
| `failed to read dockerfile: open Dockerfile: no such file or directory` | Thiếu `file: docker/Dockerfile` | Thêm `file:` |
| `"/app/pom.xml": not found` khi `COPY` | `context` sai (ví dụ `context: app`) — Dockerfile cần thấy thư mục `app/` từ gốc repo | `context: .` |
| `invalid reference format: repository name must be lowercase` | Tự ghép tên image trong script mà không chuyển chữ thường | `${GITHUB_REPOSITORY_OWNER,,}` hoặc dùng metadata-action |
| Trivy đỏ: `Total: 1 (CRITICAL: 1)` | Có lỗ hổng CRITICAL đã có bản vá | Đọc cột Library: base image → cập nhật base image; thư viện Java → nâng dependency. Không tắt cổng |
| Trivy luôn xanh dù có CRITICAL | Thiếu `exit-code: '1'` (mặc định `0`) | Thêm `exit-code: '1'` |
| PR xanh nhưng không thấy image trên GHCR | Đúng thiết kế: PR không push | Image chỉ xuất hiện sau khi merge vào `main` |
| Push tag nhưng không có lần chạy Release | Tag không khớp `v*.*.*`; push hơn 3 tag một lúc; commit được tag chưa có `release.yml` | Kiểm tra tên tag; push từng tag; tag commit mới hơn |
| `::error::Không tìm thấy ghcr.io/.../taskhub:<sha>` | Tag trước khi CI trên `main` xong; hoặc tag commit không nằm trên `main` | Chờ CI xanh → Re-run failed jobs; chỉ tag commit trên `main` |
| `HTTP 403: Resource not accessible by integration` ở bước `gh release create` | Job thiếu `contents: write` | Thêm vào `permissions` của job `promote` |
| `a release with the same tag name already exists` | Đã tạo Release tay cho tag đó | Xóa Release tay (giữ tag) rồi Re-run; từ v0.3.0 để workflow tạo |
| GHCR hiện `unknown/unknown` | Attestation provenance (mục 4.7) | Không phải lỗi |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Đọc từ ngoài vào trong

1. **Trang tóm tắt lần chạy** (Summary): job nào đỏ, chú thích `::error::` hiện ở mục *Annotations*. Bước build-push-action còn ghi **build summary** vào trang này.
2. **Mở job đỏ → bước đỏ đầu tiên.** Các bước sau thường đỏ/skip **vì** bước đầu.
3. Trong bước build, tìm dòng `ERROR:` và **dòng `#N` ngay trước nó** — đó là lệnh Dockerfile bị lỗi. Cuộn lên các dòng `#N` cùng số để xem output của lệnh đó.

### 12.2. Xếp nhóm lỗi trong job `image`

| Bước đỏ | Nhóm | Hỏi |
|---|---|---|
| `Build image` | Dockerfile / context | Build trên máy bằng đúng lệnh ở mục 8 có lỗi giống không? `context`/`file` đúng chưa? |
| `Scan image (Trivy)` | Lỗ hổng | Lỗ hổng ở gói hệ điều hành hay thư viện Java? Có Fixed Version không? |
| `Log in to GHCR` | Xác thực | `permissions` có `packages: write`? |
| `Push image` | Phân quyền package | `403`/`write_package` → Manage Actions access. `denied` khác → tên image, chữ thường |
| `Promote image` | Thứ tự / tên | Đọc dòng `::error::`. Tag SHA có tồn tại không (`imagetools inspect` từ máy bạn)? |

### 12.3. Tự kiểm tra registry từ máy

Khi nghi ngờ "image có lên không", đừng đoán — hỏi registry:

```bash
docker buildx imagetools inspect ghcr.io/<user>/taskhub:$(git rev-parse --short=7 origin/main)
```

```text
ERROR: ghcr.io/<user>/taskhub:4c1d9e2: not found
```

→ CI cho commit đó **chưa push** (chưa chạy xong, đỏ, hoặc commit không thuộc `main`).

### 12.4. Bật log chi tiết

Khi log không đủ: **Re-run jobs** → tick **Enable debug logging** (cách bật và ý nghĩa ở [bài 02](02-github-actions-basics.md)). Log debug dài gấp nhiều lần — chỉ bật khi cần.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Nêu 3 lý do image triển khai nên được build trong CI thay vì trên laptop.
2. `setup-buildx-action` tạo builder driver gì? Vì sao cần nó cho `cache-to: type=gha`?
3. `load: true` và `push: true` khác nhau thế nào? Trong job `image`, mỗi cái được dùng ở bước nào và vì sao?
4. `type=sha,prefix=` sinh ra tag gì? Mặc định có độ dài bao nhiêu? Vì sao `release.yml` phải dùng cùng độ dài?
5. `type=semver,pattern={{version}}` và `type=ref,event=tag` cho tag Git `v0.3.0` ra kết quả gì? Dự án chọn cái nào và vì sao?
6. `cache-to: type=gha,mode=max` — `max` có lợi gì với Dockerfile multi-stage của taskhub?
7. Vì sao bước Trivy phải đứng **trước** bước push? Điều gì xảy ra nếu quên `exit-code: '1'`?
8. Giải thích đánh đổi khi chọn cổng chặn `CRITICAL` + `ignore-unfixed` thay vì `HIGH,CRITICAL`.
9. Bạn merge PR đầu tiên có job `image` và nhận `denied: permission_denied: write_package`. Nguyên nhân có thể là gì và sửa thế nào?
10. Vì sao trang package GHCR hiện `unknown/unknown`? Image có hỏng không?
11. Job `promote` không build lại image. Nó làm gì, và vì sao cách đó tốt hơn build lại?
12. Bạn tag `v0.3.0` ngay sau khi merge và Release đỏ. Vì sao? Sửa thế nào mà không cần tạo tag mới?
13. `v0.3.0-rc.1` có kích hoạt `release.yml` không? Release tạo ra có được đánh dấu pre-release không?
14. Vì sao không dùng `git push --tags` để kích hoạt release?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Báo cáo HIGH không chặn.** Thêm một bước Trivy thứ hai vào job `image`, đặt **trước** bước cổng chặn: báo cáo `HIGH,CRITICAL` (kể cả chưa có bản vá) nhưng **không** làm job đỏ. Giải thích vì sao tách thành hai bước thay vì một.

**Bài 2 — Pre-release đúng nghĩa.** Sửa bước `Create GitHub Release` trong `release.yml` của bạn: tag có phần tiền phát hành (chứa `-`, ví dụ `v0.3.0-rc.1`) phải được tạo với `--prerelease`. Chỉ dùng Bash, không thêm action mới. Kiểm tra bằng actionlint.

**Bài 3 — Hadolint trong CI.** [Docker 07](../04-DOCKER/07-docker-security.md) hẹn "Hadolint trong CI — tuần 10". Thêm bước lint Dockerfile vào job `image` (trước bước build) mà **không** dùng action của bên thứ ba. Gợi ý: Hadolint đọc Dockerfile từ stdin. Quyết định: lint có nên chặn pipeline không? Ghi lý do.

**Bài 4 — Đo hiệu quả cache.** Sau khi Lab 02 xong, tạo hai PR thử: (a) chỉ sửa một file Java, (b) chỉ thêm một dòng comment vào `app/pom.xml`. Ghi thời gian của bước `Build image` ở mỗi PR và giải thích chênh lệch bằng các dòng `CACHED` trong log.

**Bài 5 — SHA của PR.** Trong một lần chạy CI trên PR, đọc log bước `Image metadata`: SHA trong `Context info` có trùng commit cuối của nhánh PR không? Giải thích bằng khái niệm merge commit `refs/pull/<số>/merge`. Nếu một ngày bạn muốn push image cho PR (môi trường preview), bạn cần đổi gì?

**Bài 6 — ADR.** Viết `docs/adr/0002-promote-image-instead-of-rebuild.md` trong repo `taskhub` theo [mẫu ADR](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr): bối cảnh, các lựa chọn (build lại khi release / gắn tag image có sẵn), quyết định, hệ quả (gồm cả nhược điểm: release phụ thuộc thứ tự "CI xanh trước, tag sau").

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Giải thích được từng dòng của job `image` và `release.yml` mà không nhìn tài liệu.
- [ ] Nói được vì sao image push lên registry chính là image đã quét, dù có hai bước build-push.
- [ ] Vẽ được sơ đồ 6.2 cho repo của bạn, với digest thật đọc bằng `imagetools inspect`.
- [ ] Phân biệt được image index, manifest, attestation; giải thích `unknown/unknown`.
- [ ] Tự xử lý được lỗi `write_package` và lỗi "tag trước khi CI xong" mà không cần tra.
- [ ] Bảo vệ được lựa chọn cổng chặn `CRITICAL` + `ignore-unfixed` trước câu hỏi "sao không chặn cả HIGH?".
- [ ] Đã làm xong [Lab 02](labs/lab-02-release-ghcr.md).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Publishing Docker images](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images) | Workflow mẫu chính thức: `permissions`, login GHCR bằng `GITHUB_TOKEN`, metadata, build-push, `actions/attest@v4` | 2026-10-31 |
| [GitHub Docs — Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) | `GITHUB_TOKEN`, tự liên kết repo, package có sẵn không push được, visibility mặc định private | 2026-10-31 |
| [GitHub Docs — Configuring a package's access control](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility) | Manage Actions access, Add repository, Role Write | 2026-10-31 |
| [GitHub Docs — Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) | `GITHUB_SHA` của push, giới hạn 3 tag | 2026-10-31 |
| [GitHub Docs — Re-running workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs) | Re-run dùng lại `GITHUB_SHA`/`GITHUB_REF`, Re-run failed jobs | 2026-10-31 |
| [docker/metadata-action](https://github.com/docker/metadata-action) | `type=sha` (7 ký tự, `DOCKER_METADATA_SHORT_SHA_LENGTH`), `type=semver`, `type=ref`, `latest=auto`, tự chữ thường, outputs, `DOCKER_METADATA_PR_HEAD_SHA` | 2026-10-31 |
| [docker/build-push-action releases](https://github.com/docker/build-push-action/releases) | Phiên bản v7 | 2026-10-31 |
| [Docker Docs — GitHub Actions cache backend](https://docs.docker.com/build/cache/backends/gha/) | `type=gha`, `mode`, phạm vi nhánh, token tự điền bởi build-push-action | 2026-10-31 |
| [Docker Docs — Attestations with GitHub Actions](https://docs.docker.com/build/ci/github-actions/attestations/) | Provenance mặc định (`mode=max` public, `mode=min` private), không có với `load: true`, `sbom: true` | 2026-10-31 |
| [Docker Docs — Attestation storage](https://docs.docker.com/build/metadata/attestations/attestation-storage/) | Attestation manifest, `unknown/unknown`, `vnd.docker.reference.type` | 2026-10-31 |
| [Docker Docs — `buildx imagetools create`](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/) | Carbon copy khi nguồn là index, `--prefer-index`, `--dry-run` | 2026-10-31 |
| [Docker Docs — `buildx imagetools inspect`](https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/) | Định dạng output, `--format` | 2026-10-31 |
| [aquasecurity/trivy-action](https://github.com/aquasecurity/trivy-action) | Tham số `image-ref`, `severity`, `ignore-unfixed`, `exit-code` (mặc định 0), `trivyignores` | 2026-10-31 |
| [Trivy — Filtering](https://trivy.dev/latest/docs/configuration/filtering/) | `.trivyignore`, hạn `exp:`, `--ignore-unfixed` | 2026-10-31 |
| [GitHub CLI — `gh release create`](https://cli.github.com/manual/gh_release_create) | `--verify-tag`, `--generate-notes`, `--prerelease`, `--latest` | 2026-10-31 |
| [GitHub Docs — Billing for GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions) | Giới hạn cache 10 GB mỗi repo | 2026-10-31 |
| [actionlint — usage](https://github.com/rhysd/actionlint/blob/main/docs/usage.md) | Chạy actionlint bằng Docker | 2026-10-31 |
| [GitHub Community — unknown/unknown trên GHCR](https://github.com/orgs/community/discussions/45969) | Câu hỏi thực tế của người dùng về platform `unknown/unknown` | 2026-10-31 |
