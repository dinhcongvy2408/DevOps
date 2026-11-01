# 06. Container registry

> ⏱️ ~2 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [02. Images & Containers](02-images-containers.md), [03. Dockerfile & multi-stage build](03-dockerfile-multistage.md), [Ôn tập Git nhanh](../03-GIT/00-git-quick-review.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop, tài khoản GitHub

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

- Giải thích được **container registry** là gì và vì sao mọi quy trình triển khai container đều cần nó.
- So sánh **Docker Hub**, **GitHub Container Registry (GHCR)** và **Amazon ECR**, biết khi nào dùng cái nào.
- Đọc hiểu **tên đầy đủ** của một image: `registry/namespace/repository:tag@digest`.
- Đăng nhập GHCR bằng **personal access token (classic)** đúng quyền, an toàn, rồi `tag`, `push`, `pull` image `taskhub`.
- Áp dụng **chiến lược đặt tag** cho triển khai: tag bất biến theo commit SHA + tag SemVer, không triển khai bằng `latest`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Đến giờ, image `taskhub:local` chỉ nằm trên laptop của bạn. Nhưng:

| Tình huống thật | Cần registry vì |
|---|---|
| Server EC2 cần chạy `taskhub` (dự án v2, tuần 12) | Server phải **kéo** image từ đâu đó — không ai build lại trên server production |
| Pipeline CI build image (Module 05) | Build xong phải **đẩy** đi đâu đó để bước deploy dùng |
| Rollback khi bản mới lỗi | Phải còn **image cũ có tên rõ ràng** để chạy lại |
| Kubernetes chạy 3 bản sao trên 3 node (Module 09) | Mỗi node tự kéo cùng một image |
| "Bản đang chạy production là code nào?" | Tag theo commit SHA trả lời ngay |

Registry là **cầu nối giữa "build" và "deploy"**. Hiểu sai về tag là nguyên nhân của rất nhiều sự cố kiểu "tôi deploy rồi mà server vẫn chạy code cũ".

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Registry, repository, tag

- **Registry** (kho image): một server lưu và phân phối image qua HTTPS. Ví dụ: `docker.io` (Docker Hub), `ghcr.io` (GitHub), `<account>.dkr.ecr.<region>.amazonaws.com` (AWS ECR).
- **Repository** (kho chứa một image): tập hợp các phiên bản của **cùng một** image. Ví dụ `ghcr.io/phuong-dev/taskhub`.
- **Tag** (nhãn): tên dễ đọc gắn với một phiên bản. Ví dụ `v0.2.0`, `a1b2c3d`.
- **Digest** (mã băm nội dung): `sha256:...` — định danh **theo nội dung** của image, đã học ở [bài 02](02-images-containers.md).

Quan hệ giống Git: repository ≈ repo, digest ≈ commit hash (bất biến), tag ≈ tag/branch (một cái tên trỏ tới digest, **có thể bị dời đi**).

### 3.2. Giải phẫu tên image

```text
ghcr.io/phuong-dev/taskhub:v0.2.0@sha256:4f9c...
└──┬──┘ └───┬────┘ └──┬──┘ └──┬─┘ └────┬─────┘
registry namespace  repository tag     digest (tùy chọn)
```

Khi bạn viết tắt, Docker tự điền phần thiếu:

| Bạn viết | Docker hiểu là |
|---|---|
| `nginx` | `docker.io/library/nginx:latest` |
| `nginx:1.30-alpine` | `docker.io/library/nginx:1.30-alpine` |
| `bitnami/redis` | `docker.io/bitnami/redis:latest` |
| `ghcr.io/phuong-dev/taskhub:v0.2.0` | (đầy đủ rồi) |

Hai điều rút ra: (1) không ghi registry = **Docker Hub**; (2) không ghi tag = **`latest`** — chỉ là một tag bình thường, **không** có nghĩa "mới nhất".

### 3.3. Tag có thể dời, digest thì không

Người phát hành có thể push image mới lên **cùng tag** — tag `1.30-alpine` của nginx hôm nay và tháng sau có thể trỏ tới hai image khác nhau (bản vá bảo mật). Digest thì gắn với nội dung: cùng digest = cùng từng byte.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 So sánh ba registry bạn sẽ gặp

| Tiêu chí | Docker Hub | GHCR | Amazon ECR |
|---|---|---|---|
| Địa chỉ | `docker.io` | `ghcr.io` | `<account-id>.dkr.ecr.<region>.amazonaws.com` |
| Gắn với | Tài khoản Docker | Tài khoản/tổ chức GitHub, liên kết được với repo | Tài khoản AWS, phân quyền bằng IAM |
| Xác thực | Tài khoản Docker / access token | **Personal access token (classic)** hoặc `GITHUB_TOKEN` trong GitHub Actions | IAM (lấy mật khẩu tạm thời qua AWS CLI) |
| Image chính thức (nginx, postgres…) | **Có** — nơi bạn kéo image nền | Không phải nơi chính | ECR Public có bản sao một số image |
| Dùng trong khóa học | Kéo image nền | **Lưu image `taskhub`** (Module 04–05) | Nhận biết; học kỹ khi cần IAM (Module 06) |
| Tính năng thêm | — | Gắn package vào repo GitHub | Lifecycle policy (tự xóa image cũ), scan lỗ hổng khi push, replication |

**Vì sao dự án chọn GHCR?** Code đã ở GitHub, pipeline sẽ chạy bằng GitHub Actions (Module 05) và dùng được `GITHUB_TOKEN` để push mà không cần tạo thêm secret. Image public trên GHCR miễn phí. Không cần tài khoản AWS (bạn chỉ tạo ở tuần 11).

### 4.2. 🟥 Docker Hub pull rate limit (giới hạn số lần kéo)

Docker Hub giới hạn số lần kéo image:

| Người dùng | Giới hạn (theo tài liệu Docker, 2026-10-31) |
|---|---|
| Không đăng nhập | 100 lần kéo / 6 giờ, tính theo địa chỉ IPv4 (hoặc subnet IPv6 /64) |
| Đăng nhập tài khoản cá nhân miễn phí | 200 lần kéo / 6 giờ |

Trên laptop thì hiếm khi chạm giới hạn. Nhưng trên **CI runner** hay **server dùng chung IP** (NAT — [Networking bài 04](../02-NETWORKING/04-routing-nat-switching.md)), nhiều người cùng kéo qua một IP → dễ dính lỗi `toomanyrequests`. Cách giảm thiểu: đăng nhập Docker Hub trên CI, cache image, hoặc dùng registry khác/mirror.

### 4.3. 🟥 Xác thực với GHCR

Theo tài liệu GitHub, GitHub Packages **chỉ hỗ trợ xác thực bằng personal access token (classic)** (ngoài `GITHUB_TOKEN` trong workflow). Chọn **scope** (phạm vi quyền) theo nguyên tắc đặc quyền tối thiểu:

| Scope | Cho phép |
|---|---|
| `read:packages` | Tải image, đọc metadata |
| `write:packages` | Tải lên và tải về image, đọc/ghi metadata (bao gồm quyền đọc) |
| `delete:packages` | Xóa image |

Cho bài này: tạo token với `write:packages`, đặt **thời hạn ngắn** (ví dụ 30 ngày). Server chỉ cần kéo image → token riêng chỉ có `read:packages` (hoặc để image public).

> 🔐 **PAT là mật khẩu.** Ai có token `write:packages` có thể ghi đè image của bạn bằng image độc hại. Không dán vào chat, không commit, không ghi vào script, không để trong lịch sử shell.

**Docker lưu thông tin đăng nhập ở đâu?** Sau `docker login`, Docker ghi vào `~/.docker/config.json`. Nếu có **credential helper** (trình lưu thông tin đăng nhập) — Docker Desktop thường cấu hình sẵn để dùng kho bảo mật của Windows — file chỉ ghi tên helper, không ghi token. Nếu không có helper, token được ghi dạng **base64** (mã hóa, **không phải** mã hóa bảo mật — ai đọc được file là có token). Kiểm tra: `cat ~/.docker/config.json` và tìm key `credsStore`.

### 4.4. 🟥 `docker tag` — đặt thêm tên, không sao chép

```bash
docker tag taskhub:local ghcr.io/phuong-dev/taskhub:v0.2.0
```

`docker tag` **không tạo image mới**, chỉ thêm một tên nữa trỏ tới **cùng image ID** (giống tạo thêm Git tag). Kiểm chứng: `docker images` cho thấy hai dòng có cùng `IMAGE ID`.

Phần trước dấu `/` đầu tiên của tên quyết định **image được push đi đâu**. Tên `taskhub:local` không có registry → nếu push sẽ đi Docker Hub (và thất bại). Muốn push lên GHCR, tên phải bắt đầu bằng `ghcr.io/<tên-người-dùng>/`.

> ⚠️ Tên repository trên GHCR (và hầu hết registry) phải là **chữ thường**. Username GitHub `Phuong-Dev` → dùng `ghcr.io/phuong-dev/taskhub`.

### 4.5. 🟥 `docker push` và `docker pull` — chỉ gửi layer còn thiếu

Image gồm nhiều layer ([bài 02](02-images-containers.md)). Khi push, Docker hỏi registry layer nào đã có, chỉ gửi layer **chưa có**:

```text
a1b2c3d4e5f6: Layer already exists     ← layer của eclipse-temurin, registry đã có
9f8e7d6c5b4a: Pushed                    ← layer chứa app.jar của bạn
v0.2.0: digest: sha256:4f9c... size: 1574
```

Đây là lý do thứ tự lệnh trong Dockerfile ([bài 03](03-dockerfile-multistage.md)) không chỉ ảnh hưởng tốc độ build mà còn tốc độ **push/pull**: layer phụ thuộc (ít đổi) được tái sử dụng, chỉ layer code (nhỏ) phải truyền lại.

### 4.6. 🟥 Visibility — package public hay private

Theo tài liệu GitHub, **lần đầu publish, package mặc định là private**. Image private: muốn pull phải đăng nhập bằng token có `read:packages`.

Đổi visibility: GitHub → avatar → **Your profile** → tab **Packages** → chọn package → **Package settings** → **Change visibility**.

Với `taskhub` (dự án đưa vào CV): để **public** cho tiện — nhà tuyển dụng kéo về chạy thử được, server EC2 pull không cần token. Điều kiện: image **không chứa secret** (lý do để [bài 07](07-docker-security.md) dạy kỹ).

**Liên kết package với repo:** image push từ dòng lệnh **không** tự gắn với repository. Thêm nhãn sau vào Dockerfile để GitHub liên kết (trang repo sẽ hiện package, README hiện trên trang package):

```dockerfile
LABEL org.opencontainers.image.source="https://github.com/phuong-dev/taskhub"
```

Push từ GitHub Actions bằng `GITHUB_TOKEN` thì repo được liên kết tự động (Module 05).

### 4.7. 🟥 Chiến lược đặt tag

| Loại tag | Ví dụ | Bất biến? | Dùng để |
|---|---|---|---|
| **Commit SHA** | `a1b2c3d` | Có (theo quy ước — không bao giờ push đè) | **Triển khai**: biết chính xác code nào đang chạy, rollback chính xác |
| **SemVer** | `v0.2.0` | Có (theo quy ước) | Phiên bản phát hành, khớp Git tag/release ([Module 03](../03-GIT/05-tags-releases-versioning.md)) |
| **SemVer rút gọn** 🟨 | `v0.2`, `v0` | Không — dời theo bản vá mới nhất | Người dùng muốn "luôn bản vá mới nhất của 0.2" |
| **`latest`** | `latest` | Không | Tiện cho thử nghiệm. **Không dùng để triển khai** |
| **Tên nhánh** 🟨 | `main` | Không | Môi trường dev/staging tự cập nhật |

**Vì sao không triển khai bằng `latest`?**

1. Không biết `latest` lúc này là code nào → không trả lời được "production đang chạy bản gì".
2. Hai server pull vào hai thời điểm khác nhau → chạy **hai phiên bản khác nhau** dù cùng tên.
3. Rollback "về bản trước" là không thể: `latest` cũ đã bị ghi đè.
4. `docker compose up -d` thấy image `latest` đã có trên máy → **không pull lại** → chạy code cũ dù registry đã có bản mới.

Quy ước dự án `taskhub`: mỗi image được push với **hai tag** — SHA ngắn của commit (7 ký tự, `git rev-parse --short HEAD`) và SemVer khi phát hành. Triển khai bằng tag SHA hoặc SemVer. Module 05 sẽ tự động hóa việc này trong pipeline, và rollback = triển khai lại tag cũ.

🟨 Muốn tuyệt đối chắc chắn, tham chiếu bằng digest: `ghcr.io/phuong-dev/taskhub@sha256:4f9c...`.

### 4.8. 🟨 Dọn image cũ trên registry

Mỗi lần push tạo thêm phiên bản → dung lượng tăng dần.

- **GHCR:** xóa phiên bản trong trang Package settings, hoặc qua API (cần `delete:packages`). Có thể tự động hóa bằng workflow (Module 05).
- **ECR:** có **lifecycle policy** — quy tắc tự xóa image, ví dụ "chỉ giữ 20 image gần nhất". Học khi đến Module 06.
- Nguyên tắc: **không xóa** image đang chạy ở bất kỳ môi trường nào và vài bản gần nhất (để rollback).

### 4.9. 🟦 ECR sẽ khác gì?

Quy trình giống hệt (`tag` → `push` → `pull`), chỉ khác:

- Tên image: `<account-id>.dkr.ecr.ap-southeast-1.amazonaws.com/taskhub:v0.2.0`.
- Đăng nhập bằng mật khẩu **tạm thời** lấy qua AWS CLI, quyền được kiểm soát bằng **IAM**. EC2 có IAM role phù hợp thì pull được mà không cần lưu mật khẩu nào — một lợi thế bảo mật lớn.

### 4.10. Gặp lại ở đâu

| Khái niệm | Gặp lại ở |
|---|---|
| Push image từ pipeline, `GITHUB_TOKEN` | GitHub Actions (Module 05) |
| Tag theo SHA, rollback bằng tag | Deployment strategies & rollback (Module 05), dự án v3 |
| Server pull image | Triển khai lên EC2 (Module 06) |
| ECR + IAM role | Module 06 |
| Quét lỗ hổng image trên registry | ECR scan on push, DevSecOps (Module 10) |
| `image:` trong Pod spec | Kubernetes (Module 09) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: "Đã deploy mà server vẫn chạy code cũ"

Một team deploy bằng `docker compose pull && docker compose up -d` với `image: myapp:latest`. Một hôm server không pull được (token hết hạn), lệnh `pull` báo lỗi nhưng script không kiểm tra exit code → `up -d` vẫn chạy với `latest` **cũ** có sẵn trên máy. Mọi người tin là đã deploy. Hai bài học: (1) deploy bằng tag cụ thể — tag không tồn tại thì `up` thất bại rõ ràng; (2) script phải dừng khi có lỗi (`set -euo pipefail` — [Linux bài 06](../01-LINUX/06-bash-scripting.md)).

### Ví dụ 2: Rollback trong 1 phút

Bản `v0.3.0` (tag SHA `9f8e7d6`) gây lỗi 500. Vì mọi bản đều có tag SHA trên GHCR, kỹ sư trực ca chỉ cần đổi `TASKHUB_IMAGE_TAG=a1b2c3d` (bản trước) trong `.env` trên server và `docker compose up -d`. Không build lại, không chờ pipeline. Đây là lý do tag bất biến quan trọng hơn nhiều so với vẻ ngoài của nó.

### Ví dụ 3: Token bị lộ trong lịch sử shell

Một kỹ sư gõ `docker login ghcr.io -u me -p ghp_xxxx` trên server dùng chung. Token nằm trong `~/.bash_history`, và Docker còn cảnh báo `Using --password via the CLI is insecure`. Cách đúng: `--password-stdin` (mục 8), và nếu lỡ lộ → **thu hồi token ngay** trên GitHub rồi tạo token mới (giống nguyên tắc xử lý secret bị lộ ở [Ôn tập Git](../03-GIT/00-git-quick-review.md)).

---

## 6. Sơ đồ kiến trúc

### 6.1. Registry ở giữa quy trình

```text
 Laptop (tuần 8)                       GHCR                         Server / máy khác
 ┌──────────────────┐   docker push   ┌──────────────────────┐  docker pull  ┌──────────────┐
 │ docker build     │ ──────────────► │ ghcr.io/phuong-dev/  │ ────────────► │ docker       │
 │ docker tag       │                 │   taskhub            │               │ compose up   │
 └──────────────────┘                 │   :a1b2c3d  ─┐       │               └──────────────┘
                                      │   :v0.2.0   ─┴► sha256:4f9c…        (EC2 — tuần 12)
 GitHub Actions (Module 05) ─────────►│   :9f8e7d6  ──► sha256:77ab…│
                                      └──────────────────────┘
```

Hai tag `a1b2c3d` và `v0.2.0` cùng trỏ tới **một** digest — cùng một image.

### 6.2. Push chỉ gửi layer còn thiếu

```text
 Image taskhub:v0.2.0                       Registry
 ┌─────────────────────────────┐
 │ layer 4: app.jar  (~50MB)   │ ── Pushed ──────────►  (mới)
 │ layer 3: user taskhub       │ ── Pushed ──────────►  (mới)
 │ layer 2: JRE 21  (~150MB)   │ ── Layer already exists (của eclipse-temurin)
 │ layer 1: Ubuntu 24.04       │ ── Layer already exists
 └─────────────────────────────┘
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `docker login <registry>` | Đăng nhập registry | 🟥 |
| `docker logout <registry>` | Xóa thông tin đăng nhập | 🟥 |
| `docker tag <nguồn> <đích>` | Gắn thêm tên cho image | 🟥 |
| `docker push <tên:tag>` | Đẩy image lên registry | 🟥 |
| `docker pull <tên:tag>` | Kéo image về | 🟥 |
| `docker image ls <repo>` | Xem các tag của một repository trên máy | 🟥 |
| `docker image inspect --format '{{.RepoDigests}}'` | Xem digest của image | 🟨 |
| `docker image push --all-tags <repo>` | Push mọi tag của một repository | 🟨 |
| `git rev-parse --short HEAD` | Lấy SHA ngắn của commit hiện tại để làm tag | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa**. Username GitHub minh họa: `phuong-dev`. Thay bằng username **chữ thường** của bạn.

### `docker login` với `--password-stdin`

Cách an toàn, không để token trong lịch sử shell:

```bash
read -rsp "Dán GitHub PAT: " CR_PAT && echo
echo "$CR_PAT" | docker login ghcr.io -u phuong-dev --password-stdin
unset CR_PAT
```

```text
Login Succeeded
```

| Thành phần | Ý nghĩa |
|---|---|
| `read -rsp "..." CR_PAT` | Đọc từ bàn phím vào biến: `-s` không hiện ký tự gõ, `-r` không xử lý `\`, `-p` in lời nhắc ([Linux bài 06](../01-LINUX/06-bash-scripting.md)) |
| `ghcr.io` | Registry cần đăng nhập. Bỏ trống = Docker Hub |
| `-u phuong-dev` | Username GitHub |
| `--password-stdin` | Đọc mật khẩu từ stdin thay vì tham số dòng lệnh |
| `unset CR_PAT` | Xóa biến khỏi shell sau khi dùng |

> Vì sao không `docker login -p <token>`? Tham số dòng lệnh nằm trong `~/.bash_history` và hiện trong `ps` cho user khác thấy. Docker cũng in cảnh báo khi dùng `-p`.

Kiểm tra nơi lưu thông tin đăng nhập:

```bash
cat ~/.docker/config.json
```

```text
{
  "auths": {
    "ghcr.io": {}
  },
  "credsStore": "desktop.exe"
}
```

`"ghcr.io": {}` rỗng + có `credsStore` = token nằm trong credential helper, không nằm trong file. Nếu thấy `"auth": "cGh1b25n..."` → token đang được lưu dạng base64 trong file — bảo vệ file đó (`chmod 600`) và cân nhắc cấu hình credential helper.

### `docker tag`

```bash
SHA=$(git -C ~/projects/taskhub rev-parse --short HEAD)
echo "$SHA"
docker tag taskhub:local ghcr.io/phuong-dev/taskhub:v0.2.0
docker tag taskhub:local "ghcr.io/phuong-dev/taskhub:${SHA}"
docker image ls ghcr.io/phuong-dev/taskhub
```

```text
a1b2c3d
REPOSITORY                   TAG       IMAGE ID       CREATED          SIZE
ghcr.io/phuong-dev/taskhub   a1b2c3d   3f2a9c81d0e4   20 minutes ago   312MB
ghcr.io/phuong-dev/taskhub   v0.2.0    3f2a9c81d0e4   20 minutes ago   312MB
```

- Cú pháp: `docker tag <image-nguồn> <tên-mới>`.
- Cùng `IMAGE ID` → cùng một image, không tốn thêm dung lượng.
- `git -C <thư mục>`: chạy lệnh Git như thể đang đứng trong thư mục đó.

### `docker push`

```bash
docker push ghcr.io/phuong-dev/taskhub:v0.2.0
docker push "ghcr.io/phuong-dev/taskhub:${SHA}"
```

```text
The push refers to repository [ghcr.io/phuong-dev/taskhub]
5d1c0f7a2b3e: Pushed
8a9b0c1d2e3f: Pushed
c4d5e6f7a8b9: Pushed
f1e2d3c4b5a6: Pushed
v0.2.0: digest: sha256:4f9c2e7d... size: 1789

The push refers to repository [ghcr.io/phuong-dev/taskhub]
5d1c0f7a2b3e: Layer already exists
...
a1b2c3d: digest: sha256:4f9c2e7d... size: 1789
```

- Lần push thứ hai: mọi layer `already exists` — chỉ thêm tag mới trỏ tới cùng digest.
- Dòng cuối cho biết **digest** — ghi lại nếu muốn tham chiếu tuyệt đối.
- `docker image push --all-tags ghcr.io/phuong-dev/taskhub`: push tất cả tag của repo này trong một lệnh.

### `docker pull`

```bash
docker pull ghcr.io/phuong-dev/taskhub:v0.2.0
```

```text
v0.2.0: Pulling from phuong-dev/taskhub
Digest: sha256:4f9c2e7d...
Status: Downloaded newer image for ghcr.io/phuong-dev/taskhub:v0.2.0
ghcr.io/phuong-dev/taskhub:v0.2.0
```

- `Status: Image is up to date` = máy đã có đúng digest đó, không tải gì.
- Pull theo digest: `docker pull ghcr.io/phuong-dev/taskhub@sha256:4f9c2e7d...`.

### Xem digest của image trên máy

```bash
docker image inspect --format '{{json .RepoDigests}}' ghcr.io/phuong-dev/taskhub:v0.2.0
```

```text
["ghcr.io/phuong-dev/taskhub@sha256:4f9c2e7d..."]
```

`RepoDigests` chỉ có sau khi image đã được push lên hoặc pull từ registry — image build tại chỗ chưa có.

### Dùng tag trong `compose.yaml`

```yaml
services:
  taskhub:
    image: ghcr.io/phuong-dev/taskhub:${TASKHUB_IMAGE_TAG:?set TASKHUB_IMAGE_TAG in .env}
```

Trên server: không có `build:`, chỉ có `image:` với tag lấy từ `.env`. Deploy = đổi tag trong `.env` → `docker compose pull taskhub` → `docker compose up -d`. Đây là nền móng cho dự án v2/v3.

---

## 9. Bài thực hành từng bước

**Lab: Đưa `taskhub` lên GHCR** · `[WSL]` · ~60 phút

Điều kiện: đã có image `taskhub:local` từ [lab bắt buộc Spring Boot + PostgreSQL](labs/lab-springboot-postgres-compose/README.md) (hoặc build bằng Dockerfile ở [bài 03](03-dockerfile-multistage.md)). Repo `taskhub` trên GitHub đã có ít nhất một commit.

### Bước 1 — Tạo personal access token (classic)

Trên GitHub: avatar → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**.

- Note: `ghcr-push-laptop`
- Expiration: **30 days**
- Scope: chỉ tick **`write:packages`** (GitHub có thể tự tick thêm `read:packages`)

Copy token (bắt đầu bằng `ghp_`) — GitHub chỉ hiện **một lần**. Không lưu vào file nào.

❓ Vì sao không tick `repo`, `delete:packages` hay `admin:org`?

### Bước 2 — Đăng nhập an toàn

```bash
read -rsp "Dán GitHub PAT: " CR_PAT && echo
echo "$CR_PAT" | docker login ghcr.io -u <username-chữ-thường> --password-stdin
unset CR_PAT
history | tail -5
cat ~/.docker/config.json
```

❓ Token có xuất hiện trong `history` không? Trong `config.json`, token được lưu ở đâu (`credsStore` hay `auth`)?

### Bước 3 — Thêm nhãn liên kết repo vào Dockerfile

Trong `~/projects/taskhub/docker/Dockerfile`, thêm vào **stage runtime** (stage cuối):

```dockerfile
LABEL org.opencontainers.image.source="https://github.com/<username>/taskhub"
```

Build lại: `cd ~/projects/taskhub && docker compose build taskhub`.

### Bước 4 — Gắn hai tag

```bash
cd ~/projects/taskhub
GH_USER=<username-chữ-thường>
SHA=$(git rev-parse --short HEAD)
docker tag taskhub:local "ghcr.io/${GH_USER}/taskhub:v0.2.0"
docker tag taskhub:local "ghcr.io/${GH_USER}/taskhub:${SHA}"
docker image ls "ghcr.io/${GH_USER}/taskhub"
```

❓ Hai tag có cùng `IMAGE ID` không? Dung lượng ổ đĩa có tăng gấp đôi không?

### Bước 5 — Push

```bash
docker push "ghcr.io/${GH_USER}/taskhub:v0.2.0"
docker push "ghcr.io/${GH_USER}/taskhub:${SHA}"
```

❓ Ở lần push thứ hai, những layer nào được gửi lại? Ghi lại digest.

### Bước 6 — Kiểm tra trên GitHub và đặt public

Mở `https://github.com/<username>?tab=packages` → package `taskhub` → **Package settings** → **Change visibility** → **Public**.

❓ Trước khi đổi, visibility mặc định là gì? Trang repo `taskhub` có hiện package ở cột bên phải không (nhờ nhãn ở Bước 3)?

### Bước 7 — Pull như một máy khác

Giả lập một máy chưa từng có image và chưa đăng nhập:

```bash
docker logout ghcr.io
docker image rm "ghcr.io/${GH_USER}/taskhub:v0.2.0" "ghcr.io/${GH_USER}/taskhub:${SHA}"
docker pull "ghcr.io/${GH_USER}/taskhub:v0.2.0"
docker image inspect --format '{{json .RepoDigests}}' "ghcr.io/${GH_USER}/taskhub:v0.2.0"
```

❓ Pull có thành công khi đã logout không? Digest có khớp với digest ở Bước 5 không?

> `docker image rm` với tên có registry chỉ xóa **tag** đó. Image `taskhub:local` vẫn còn vì còn tag khác trỏ tới cùng ID (Docker in `Untagged:` thay vì `Deleted:`).

### Bước 8 — Chạy từ image trên registry

Tạo `~/devops-lab/04-docker/registry-test/compose.yaml` chỉ dùng image từ GHCR (không `build:`), gồm `taskhub` + `postgres` (copy phần `postgres` từ lab bắt buộc), với:

```yaml
    image: ghcr.io/<username>/taskhub:${TASKHUB_IMAGE_TAG:?set TASKHUB_IMAGE_TAG}
```

Tạo `.env` với `TASKHUB_IMAGE_TAG=v0.2.0` và `POSTGRES_PASSWORD=...`, chạy `docker compose up -d`, kiểm tra `docker compose ps`. Sau đó `docker compose down -v`.

### Bước 9 — Ghi lại

Ghi câu trả lời vào `~/devops-journey/week08/lab06-answers.md`, kèm link package GHCR. Commit Dockerfile có nhãn vào repo `taskhub`.

---

## 10. Kết quả mong đợi

- **Bước 1:** chỉ cần `write:packages` (đã bao gồm đọc). Thêm `repo`/`delete:packages` là vi phạm least privilege — token lộ thì thiệt hại lớn hơn.
- **Bước 2:** token **không** có trong `history`. Trên Docker Desktop + WSL, `config.json` thường có `credsStore` và mục `ghcr.io` rỗng.
- **Bước 4:** cùng `IMAGE ID`, dung lượng không tăng — tag chỉ là tên.
- **Bước 5:** lần push thứ hai: mọi layer `Layer already exists`, cùng digest với lần đầu.
- **Bước 6:** mặc định **private**. Có nhãn `org.opencontainers.image.source` → package hiện trên trang repo.
- **Bước 7:** sau khi đặt public, pull thành công **không cần đăng nhập**, digest khớp — chứng minh image trên registry đúng là image bạn build.
- **Bước 8:** `taskhub` chạy được từ image GHCR mà không cần mã nguồn — đúng cách server EC2 sẽ chạy ở tuần 12.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `denied: denied` hoặc `unauthorized` khi push | Chưa đăng nhập, token thiếu `write:packages`, token hết hạn | `docker login ghcr.io` lại; kiểm tra scope và hạn của token |
| `invalid reference format: repository name must be lowercase` | Username/tên repo có chữ hoa | Dùng chữ thường: `ghcr.io/phuong-dev/...` |
| Push lên Docker Hub thay vì GHCR (`denied: requested access to the resource is denied`) | Tên image thiếu `ghcr.io/` | `docker tag` lại với tên đầy đủ |
| `manifest unknown` / `not found` khi pull | Sai tag, tag chưa được push, gõ sai tên | `docker image ls` trên máy build; xem danh sách version trên trang package |
| Pull image private báo `unauthorized` trên máy khác | Package private, máy đó chưa đăng nhập | Đăng nhập bằng token `read:packages`, hoặc đặt public |
| `toomanyrequests: You have reached your pull rate limit` | Vượt giới hạn Docker Hub | Đăng nhập Docker Hub; giảm số lần pull; dùng cache |
| Deploy xong vẫn chạy code cũ | Dùng tag `latest`, máy đã có `latest` cũ nên không pull | Deploy bằng tag SHA/SemVer; `docker compose pull` trước `up -d` |
| `WARNING! Using --password via the CLI is insecure` | Dùng `-p <token>` | Dùng `--password-stdin`; nếu đã lộ, thu hồi token |
| `Error saving credentials: error storing credentials` | Credential helper không hoạt động (Docker Desktop chưa chạy, cấu hình `credsStore` sai) | Mở Docker Desktop; kiểm tra `credsStore` trong `config.json` |

---

## 12. Đọc log và xử lý lỗi

Lỗi registry gần như luôn rơi vào một trong ba nhóm — đọc thông báo để xếp nhóm trước khi sửa:

| Thông báo chứa | Nhóm | Hỏi |
|---|---|---|
| `unauthorized`, `denied`, `authentication required` | **Xác thực / phân quyền** | Đã login đúng registry chưa? Token còn hạn, đủ scope? Package của ai, mình có quyền ghi không? |
| `manifest unknown`, `not found`, `name unknown` | **Tên / tag sai** | Tên đầy đủ đúng chưa (registry, namespace, chữ thường)? Tag đã thật sự được push chưa? |
| `toomanyrequests`, `timeout`, `connection refused`, `TLS handshake` | **Mạng / giới hạn** | Có mạng không? Bị rate limit? Proxy/firewall chặn `ghcr.io:443`? ([Networking bài 08](../02-NETWORKING/08-network-troubleshooting-tools.md)) |

Ví dụ đọc một lỗi:

```text
denied: permission_denied: The token provided does not match expected scopes.
```

→ Nhóm **xác thực**: đăng nhập được nhưng token **thiếu scope**. Tạo token mới có `write:packages`, đăng nhập lại.

```text
Error response from daemon: manifest for ghcr.io/phuong-dev/taskhub:v0.2.1 not found: manifest unknown
```

→ Nhóm **tên/tag**: registry đúng, repo đúng, nhưng **tag `v0.2.1` không tồn tại**. Kiểm tra lại tag đã push.

Debug mạng tới registry khi nghi ngờ:

```bash
curl -sI https://ghcr.io/v2/ | head -3
```

Trả về `HTTP/2 401` là **tốt**: mạng và TLS ổn, registry trả lời "cần đăng nhập". Timeout hoặc lỗi TLS → vấn đề nằm ở mạng.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Registry, repository, tag, digest khác nhau thế nào? So sánh với các khái niệm của Git.
2. `docker pull nginx` thực chất kéo image có tên đầy đủ là gì?
3. Vì sao tag `latest` không có nghĩa là "mới nhất"? Nêu 3 lý do không nên deploy bằng `latest`.
4. `docker tag` có sao chép image không? Chứng minh bằng lệnh nào?
5. Vì sao lần push thứ hai (cùng image, tag khác) gần như tức thì?
6. Để push lên GHCR cần token loại nào, scope nào? Server chỉ pull thì cần scope nào?
7. Vì sao dùng `--password-stdin` thay vì `-p`? Docker lưu thông tin đăng nhập ở đâu?
8. Package mới push lên GHCR mặc định public hay private? Làm sao liên kết package với repository?
9. Chiến lược tag của dự án `taskhub` là gì và nó giúp rollback thế nào?
10. Docker Hub pull rate limit ảnh hưởng tới CI như thế nào? Nêu một cách giảm thiểu.
11. ECR khác GHCR ở cách xác thực như thế nào? Vì sao điều đó có lợi cho EC2?
12. Bạn nhận lỗi `manifest unknown` khi pull. Bạn kiểm tra những gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/06-solutions.md](solutions/06-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Giải phẫu tên.** Viết tên đầy đủ (registry, namespace, repository, tag) mà Docker hiểu cho từng tên sau: `redis`, `postgres:17`, `grafana/grafana:11.0.0`, `ghcr.io/phuong-dev/taskhub`, `123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/taskhub:a1b2c3d`. Tên nào sẽ bị kéo bằng tag `latest`?

**Bài 2 — Script tag & push an toàn.** Viết `scripts/push-image.sh` cho repo `taskhub` nhận tham số là phiên bản SemVer (ví dụ `v0.2.1`), rồi: kiểm tra tham số đúng định dạng `vX.Y.Z`; **từ chối chạy** nếu working tree có thay đổi chưa commit (gợi ý: `git status --porcelain`); gắn tag SemVer + SHA ngắn; push cả hai; in ra digest. Dùng `set -euo pipefail`. Script không được chứa token.

**Bài 3 — Tag dời.** Push một image thử nghiệm (ví dụ build từ Dockerfile tối giản `FROM busybox` + `CMD echo v1`) với tag `demo`. Sửa thành `echo v2`, build và push lại **cùng tag** `demo`. Trên một "máy khác" (xóa image local trước), pull `demo` và chạy. Sau đó pull theo **digest** của lần push đầu tiên. Giải thích kết quả và rút ra bài học về tag bất biến.

**Bài 4 — Token chỉ đọc.** Đặt package `taskhub` về private. Tạo token thứ hai chỉ có `read:packages`, đăng nhập bằng nó và chứng minh: pull được, nhưng push bị từ chối. Ghi lại thông báo lỗi khi push. Sau đó đặt lại public và **xóa** token thử nghiệm trên GitHub.

**Bài 5 — Nghiên cứu.** Đọc tài liệu Docker Hub về giới hạn sử dụng và tài liệu GitHub về GHCR. Viết một đoạn ngắn (5–8 câu) trong `week08/` trả lời: nếu pipeline CI của team build 30 lần/ngày, mỗi lần kéo 3 image nền từ Docker Hub mà không đăng nhập, từ cùng một IP NAT, có nguy cơ gì? Đề xuất 2 cách giải quyết.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Đọc tên một image bất kỳ và nói được nó nằm ở registry nào, tag nào.
- [ ] Push/pull `taskhub` lên GHCR mà không để token trong lịch sử shell hay trong file nào trong repo.
- [ ] Giải thích được cho người khác vì sao không deploy bằng `latest`, kèm một ví dụ sự cố.
- [ ] Xếp được một lỗi registry vào đúng nhóm (xác thực / tên-tag / mạng) chỉ bằng cách đọc thông báo.
- [ ] Làm xong Bài tập 2 và 3 không xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) | PAT classic, scope, `docker login ghcr.io`, visibility mặc định, nhãn liên kết repo | 2026-10-31 |
| [Docker Docs — Docker Hub usage and limits](https://docs.docker.com/docker-hub/usage/) | Pull rate limit | 2026-10-31 |
| [AWS — What is Amazon ECR?](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html) | ECR, IAM, lifecycle policy, scan on push | 2026-10-31 |
| [Docker Docs — Get started workshop: Share the image](https://docs.docker.com/get-started/workshop/) | Quy trình tag & push chính thức | 2026-10-31 |
