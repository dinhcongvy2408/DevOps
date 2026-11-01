# Lời giải — Bài 06: Container registry

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; username `phuong-dev` là ví dụ.

Quay lại bài: [06-registry.md](../06-registry.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Registry, repository, tag, digest — so với Git?**
Registry là server lưu image (giống GitHub là nơi lưu repo). Repository là tập các phiên bản của một image (giống một repo). Digest `sha256:...` là định danh theo nội dung, bất biến (giống commit hash). Tag là tên dễ đọc trỏ tới một digest, có thể bị dời (giống Git tag/branch — tag Git cũng có thể bị force-push, dù không nên).

**2. `docker pull nginx` kéo gì?**
`docker.io/library/nginx:latest` — registry mặc định Docker Hub, namespace `library` (image chính thức), tag mặc định `latest`.

**3. `latest` và 3 lý do không deploy bằng nó?**
`latest` chỉ là tên tag mặc định khi không ghi tag; nó trỏ tới thứ mà người push gắn nhãn `latest` lần cuối — không đảm bảo là bản mới nhất. Lý do: (1) không biết code nào đang chạy; (2) các máy pull ở thời điểm khác nhau chạy phiên bản khác nhau; (3) không rollback được vì tag cũ đã bị ghi đè; (4) Compose/Docker thấy đã có `latest` trên máy thì không pull lại → chạy code cũ.

**4. `docker tag` có sao chép không?**
Không. Nó chỉ thêm một tên trỏ tới cùng image. Chứng minh: `docker image ls` thấy hai dòng cùng `IMAGE ID`; `docker system df` không tăng dung lượng.

**5. Vì sao push lần hai gần như tức thì?**
Registry đã có mọi layer (cùng digest) → Docker chỉ gửi manifest với tag mới (`Layer already exists`).

**6. Token cho GHCR?**
Personal access token **(classic)** — GitHub Packages chỉ hỗ trợ loại này cho xác thực từ ngoài workflow. Push: `write:packages`. Server chỉ pull image private: `read:packages`. Nếu image public thì server không cần token.

**7. `--password-stdin` và nơi lưu thông tin đăng nhập?**
`-p <token>` để lộ token trong lịch sử shell và danh sách process. `--password-stdin` đọc từ stdin, không lưu ở đâu cả. Sau khi đăng nhập, Docker ghi vào `~/.docker/config.json`: nếu có credential helper (`credsStore`), token nằm trong kho bảo mật của hệ điều hành; nếu không, token nằm trong file dạng base64 (đọc được ngay).

**8. Visibility mặc định và liên kết repo?**
Mặc định **private** ở lần publish đầu. Liên kết bằng nhãn `LABEL org.opencontainers.image.source="https://github.com/<user>/<repo>"` trong Dockerfile; push từ GitHub Actions bằng `GITHUB_TOKEN` tự liên kết.

**9. Chiến lược tag của taskhub và rollback?**
Mỗi image có tag SHA ngắn của commit (bất biến) và tag SemVer khi phát hành. Deploy bằng một trong hai — không bao giờ `latest`. Rollback = đổi tag trong `.env` trên server về tag của bản trước, `docker compose pull && docker compose up -d`. Không cần build lại vì image cũ vẫn còn trên registry với tên chính xác.

**10. Rate limit và CI?**
Runner CI dùng chung IP (NAT) hoặc chạy nhiều lần → nhiều lần pull không đăng nhập từ một IP → chạm 100 lần/6 giờ → build lỗi `toomanyrequests`. Giảm thiểu: đăng nhập Docker Hub trong CI (200 lần/6 giờ cho tài khoản miễn phí, hoặc gói trả phí); cache image/layer; dùng mirror hoặc registry khác cho image nền.

**11. ECR khác GHCR khi xác thực?**
ECR dùng IAM: lấy mật khẩu tạm thời qua AWS CLI. EC2 có IAM role được cấp quyền pull → không cần lưu bất kỳ token dài hạn nào trên server. GHCR dùng PAT dài hạn (trừ `GITHUB_TOKEN` trong workflow) — phải lưu và xoay vòng thủ công.

**12. `manifest unknown` — kiểm tra gì?**
Tên đầy đủ (registry, namespace, chữ thường, tên repo đúng); tag có thực sự được push không (xem danh sách version trên trang package, hoặc lịch sử push); có gõ nhầm `v0.2.0` thành `0.2.0` không; kiến trúc CPU của image (🟨 — image chỉ có `arm64` mà máy là `amd64` cho lỗi tương tự `no matching manifest`).

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Giải phẫu tên

| Bạn viết | Registry | Namespace | Repository | Tag |
|---|---|---|---|---|
| `redis` | `docker.io` | `library` | `redis` | `latest` |
| `postgres:17` | `docker.io` | `library` | `postgres` | `17` |
| `grafana/grafana:11.0.0` | `docker.io` | `grafana` | `grafana` | `11.0.0` |
| `ghcr.io/phuong-dev/taskhub` | `ghcr.io` | `phuong-dev` | `taskhub` | `latest` |
| `123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/taskhub:a1b2c3d` | `123456789012.dkr.ecr.ap-southeast-1.amazonaws.com` | (không có) | `taskhub` | `a1b2c3d` |

Bị kéo bằng `latest`: `redis` và `ghcr.io/phuong-dev/taskhub`. Cách Docker biết phần đầu là registry: nó chứa dấu `.` hoặc `:` (hoặc là `localhost`).

### Bài 2 — Script tag & push an toàn

`scripts/push-image.sh`:

```bash
#!/usr/bin/env bash
# Tag và push image taskhub lên GHCR với tag SemVer + SHA ngắn.
# Dùng: GH_USER=phuong-dev scripts/push-image.sh v0.2.1
# Yêu cầu: đã `docker login ghcr.io` từ trước. Script KHÔNG chứa và không đọc token.
set -euo pipefail

VERSION="${1:-}"
GH_USER="${GH_USER:?Hãy đặt GH_USER (username GitHub, chữ thường)}"
LOCAL_IMAGE="${LOCAL_IMAGE:-taskhub:local}"

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Lỗi: phiên bản phải có dạng vX.Y.Z (ví dụ v0.2.1), nhận được: '${VERSION}'" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Lỗi: working tree còn thay đổi chưa commit — image sẽ không khớp với SHA." >&2
  git status --short >&2
  exit 1
fi

GH_USER="${GH_USER,,}"                      # ép chữ thường
REPO="ghcr.io/${GH_USER}/taskhub"
SHA="$(git rev-parse --short HEAD)"

docker image inspect "$LOCAL_IMAGE" > /dev/null   # dừng nếu chưa build image

for TAG in "$VERSION" "$SHA"; do
  docker tag "$LOCAL_IMAGE" "${REPO}:${TAG}"
  docker push "${REPO}:${TAG}"
done

echo "Đã push: ${REPO}:${VERSION} và ${REPO}:${SHA}"
docker image inspect --format '{{json .RepoDigests}}' "${REPO}:${VERSION}"
```

Điểm chấm:

- `set -euo pipefail`: push lỗi → script dừng ngay, không in "Đã push" sai sự thật.
- Kiểm tra định dạng bằng regex `[[ =~ ]]` ([Linux bài 06](../../01-LINUX/06-bash-scripting.md)).
- Từ chối khi có thay đổi chưa commit: nếu không, tag SHA sẽ "nói dối" — image chứa code chưa nằm trong commit đó.
- `${GH_USER,,}`: chuyển chữ thường (Bash 4+).
- Không có token trong script — đăng nhập là bước riêng, do người hoặc CI làm.
- Nâng cao (🟨): kiểm tra image `taskhub:local` được build từ đúng HEAD (ví dụ bằng label chứa SHA) — Module 05 sẽ giải quyết triệt để bằng cách build trong pipeline.

### Bài 3 — Tag dời

```bash
mkdir -p ~/devops-lab/04-docker/tag-demo && cd ~/devops-lab/04-docker/tag-demo
printf 'FROM busybox:1.36\nCMD ["echo", "v1"]\n' > Dockerfile
docker build -t ghcr.io/phuong-dev/tag-demo:demo .
docker push ghcr.io/phuong-dev/tag-demo:demo          # ghi lại digest: sha256:AAA...

printf 'FROM busybox:1.36\nCMD ["echo", "v2"]\n' > Dockerfile
docker build -t ghcr.io/phuong-dev/tag-demo:demo .
docker push ghcr.io/phuong-dev/tag-demo:demo          # digest mới: sha256:BBB...

docker image rm ghcr.io/phuong-dev/tag-demo:demo
docker run --rm ghcr.io/phuong-dev/tag-demo:demo      # in: v2
docker run --rm ghcr.io/phuong-dev/tag-demo@sha256:AAA...   # in: v1
```

(Package mới là private → đăng nhập hoặc đặt public trước khi pull "như máy khác".)

Giải thích: tag `demo` đã bị **dời** sang image mới; ai pull `demo` sau thời điểm đó nhận `v2` mà không hề biết có thay đổi. Digest gắn với nội dung nên `@sha256:AAA...` vẫn luôn là `v1` — miễn là registry chưa xóa phiên bản đó. Bài học: tag dùng để deploy phải **bất biến theo quy ước** (SHA, SemVer — không bao giờ push đè); cần tuyệt đối chắc chắn thì tham chiếu bằng digest. Một số registry (ECR) có tùy chọn **tag immutability** để chặn push đè.

Dọn dẹp: xóa package `tag-demo` trong Package settings.

### Bài 4 — Token chỉ đọc

```bash
docker logout ghcr.io
read -rsp "PAT read-only: " RO_PAT && echo
echo "$RO_PAT" | docker login ghcr.io -u phuong-dev --password-stdin && unset RO_PAT
docker pull ghcr.io/phuong-dev/taskhub:v0.2.0          # thành công
docker tag ghcr.io/phuong-dev/taskhub:v0.2.0 ghcr.io/phuong-dev/taskhub:ro-test
docker push ghcr.io/phuong-dev/taskhub:ro-test          # bị từ chối
```

Thông báo minh họa khi push:

```text
denied: permission_denied: The token provided does not match expected scopes.
```

(Chữ có thể khác; ý chính là `denied` → nhóm lỗi **xác thực/phân quyền**: đăng nhập thành công nhưng không đủ quyền ghi.)

Kết luận: tách token theo vai trò — máy build có `write:packages`, máy chạy chỉ có `read:packages` (hoặc image public). Token của server bị lộ thì kẻ tấn công cũng không ghi đè được image. Nhớ: `docker image rm ...:ro-test`, đặt lại public, **xóa token thử nghiệm** trên GitHub, đăng nhập lại bằng token chính nếu cần.

### Bài 5 — Nghiên cứu rate limit

Ý chính cần có:

- 30 build × 3 image = 90 lần pull/ngày từ một IP NAT. Nếu các build dồn vào giờ làm việc (ví dụ 6 giờ) và **cùng IP** đó còn có máy của đồng nghiệp/runner khác pull, rất dễ vượt 100 lần pull/6 giờ của người dùng không đăng nhập → build thất bại ngẫu nhiên với `toomanyrequests` (khó chẩn đoán vì "lúc được lúc không").
- Giải pháp (chọn 2): đăng nhập Docker Hub trong pipeline bằng access token lưu trong secret của CI (giới hạn cao hơn và tính theo tài khoản, không theo IP); cache image nền trên runner hoặc dùng cache layer của công cụ build; đẩy image nền vào registry riêng (GHCR/ECR, hoặc pull-through cache của ECR) và kéo từ đó; giảm số image nền (dùng chung một image build).
- Trích nguồn: trang Docker Hub usage and limits (ngày đọc).
