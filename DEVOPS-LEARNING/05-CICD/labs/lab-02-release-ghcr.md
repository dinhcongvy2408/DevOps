# Lab 02 — Build image trong CI, đẩy lên GHCR và phát hành bằng tag

> Tuần 10 · ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Môi trường: `[WSL]`, `[GitHub]`, `[Runner]`
> Kiến thức cần có: [03. Build image, quét và đẩy lên registry](../03-github-actions-docker-registry.md) (đã làm xong mục 9 — job `image` và `release.yml` đã viết sẵn trên nhánh `ci/build-push-image`, chưa push), [04. Secrets & environments](../04-secrets-environments.md), [Lab 01 — CI chặn PR](lab-01-ci-pr-gate.md)

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc lab](#2-kiến-trúc-lab)
- [3. Chuẩn bị](#3-chuẩn-bị)
- [4. Các bước thực hiện](#4-các-bước-thực-hiện)
- [5. Kết quả mong đợi](#5-kết-quả-mong-đợi)
- [6. Lỗi thường gặp](#6-lỗi-thường-gặp)
- [7. Dọn dẹp](#7-dọn-dẹp)
- [8. Câu hỏi sau lab](#8-câu-hỏi-sau-lab)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu

Đưa job `image` và workflow `Release` vào repo `taskhub` thật, và kiểm chứng bằng mắt từng lời hứa của bài 03:

- PR **không** push image; merge vào `main` thì push `ghcr.io/<user>/taskhub:<sha7>`.
- Job `image` trở thành **required status check**: Trivy đỏ thì không merge được.
- Push tag `v*.*.*` → image **có sẵn** được gắn thêm tag SemVer, **không build lại** — chứng minh bằng digest.
- Tự tạo và tự xử lý tình huống "tag trước khi CI xong".
- Chạy image lấy từ GHCR trên máy bạn như server sẽ chạy.

Lab dùng tag **`v0.3.0-rc.1`** (release candidate — bản ứng viên phát hành) làm buổi **diễn tập**. Mẫu trigger `v*.*.*` khớp cả tag này (bài 03, mục 4.8), nên bạn thử được toàn bộ luồng mà chưa "đốt" số phiên bản thật. Bản chính thức `v0.3.0` được phát hành ở [milestone v1](../../12-PRACTICAL-PROJECT/milestones/v1-ci.md), sau khi đạt mọi tiêu chí.

> Đầu ra mẫu là **minh họa**: SHA, digest, thời gian trên repo của bạn sẽ khác. Username minh họa: `phuong-dev`.

---

## 2. Kiến trúc lab

```text
 Phần A                    Phần B                     Phần C                         Phần D
 PR ci/build-push-image    PR ci/release-workflow     tag v0.3.0-rc.1 (cố ý sớm)     WSL
   │ CI: build-test ✅        │ CI ✅ (image required)    │ Release: promote ❌            │ docker compose pull
   │     image ✅ (no push)   ▼ merge                     │   "Không tìm thấy :<sha7>"     │   ghcr.io/<user>/taskhub
   ▼ merge                 main: CI ──push :<sha7-B>──►  │ ... chờ CI main xanh ...       │   :v0.3.0-rc.1
 main: CI ──push :<sha7-A>                                │ Re-run failed jobs ✅          │ so digest với :<sha7-B>
                                                          └► :v0.3.0-rc.1 = :<sha7-B>     ▼
                                                             GitHub Release rc.1         curl /actuator/health
```

---

## 3. Chuẩn bị

| Kiểm tra | Lệnh / nơi xem | Mong đợi |
|---|---|---|
| Lab 01 xong: `ci.yml` có job `build-test`, `main` được bảo vệ, `build-test` là required check | GitHub → Settings → Branches (hoặc Rules) | Có luật cho `main` |
| Nhánh `ci/build-push-image` có job `image` + `release.yml`, actionlint sạch | `git log --oneline main..ci/build-push-image` | Có commit của bạn |
| Package `taskhub` từ tuần 8 | `https://github.com/<user>?tab=packages` | Có, visibility **Public** |
| Docker Desktop đang chạy | `docker info --format '{{.ServerVersion}}'` | In ra phiên bản |

**Quan sát trước (không sửa):** mở package `taskhub` → **Package settings** → mục **Manage Actions access**. Ghi lại: repo `taskhub` đã có trong danh sách chưa, role gì? Đừng sửa gì lúc này — nếu Phần A gặp lỗi `403`, bạn sẽ biết ngay vì sao.

---

## 4. Các bước thực hiện

### Phần A — Job `image` qua Pull Request

**A1. Tách `release.yml` ra khỏi nhánh này.** Mỗi PR một mục đích ([Git 03](../../03-GIT/03-github-pull-request-code-review.md)). Nếu `release.yml` đang nằm trên `ci/build-push-image`, chuyển nó sang nhánh riêng:

```bash
cd ~/projects/taskhub
git switch ci/build-push-image
git log --oneline --stat main..HEAD          # release.yml nằm trong commit nào?
```

Nếu `release.yml` đã được commit cùng job `image`: gỡ nó khỏi nhánh này bằng một commit mới (`git rm --cached .github/workflows/release.yml`, lưu bản sao ra ngoài repo trước), để Phần B đưa vào lại. Nếu chưa commit: để nguyên, chưa `git add`.

❓ Vì sao trộn hai thay đổi khác mục đích trong một PR làm việc review và rollback khó hơn?

**A2. Push và mở PR.**

```bash
git push -u origin ci/build-push-image
```

Mở PR vào `main`, tiêu đề theo Conventional Commits, ví dụ `ci: build and scan image, push to GHCR on main`.

**A3. Đọc lần chạy trên PR.** Tab **Checks** của PR → workflow `CI`:

| Job / bước | Mong đợi trên PR |
|---|---|
| `build-test` | ✅ |
| `image` → `Image metadata` | Tag 7 ký tự — mở log, ghi lại SHA trong `Context info` |
| `image` → `Build image` | ✅ — đếm các dòng `CACHED` (lần đầu gần như không có) |
| `image` → `Scan image (Trivy)` | ✅ hoặc ❌ — đọc bảng |
| `image` → `Log in to GHCR`, `Push image` | ⏭ **skipped** |

❓ SHA trong `Context info` có trùng commit cuối nhánh `ci/build-push-image` (`git rev-parse HEAD`) không? Vì sao (bài 03, mục 4.3)?

Nếu Trivy đỏ: **không** tắt cổng. Đọc cột Library và Fixed Version, xử lý theo [Docker 07](../../04-DOCKER/07-docker-security.md) (thường là build lại với base image mới hơn), ghi vào nhật ký debug.

**A4. Biến `image` thành required check.** GitHub → **Settings** → **Branches** → sửa luật của `main` → **Require status checks to pass before merging** → ô tìm kiếm gõ `image` → chọn. Giữ `build-test`. **Save changes**. (Repo dùng Rulesets thì làm tương tự trong luật tương ứng.)

Ô tìm kiếm thường chỉ gợi ý những check **đã từng chạy** trong repo — đó là lý do phải chạy PR ở A3 trước.

❓ Nếu chỉ yêu cầu `build-test` mà không yêu cầu `image`, một PR làm Trivy đỏ có merge được không?

**A5. Merge và theo dõi `main`.** Squash merge PR. Tab **Actions** → lần chạy `CI` mới với sự kiện `push` trên `main`.

```bash
git switch main && git pull
git rev-parse --short=7 HEAD                 # ghi lại: <sha7-A>
```

Khi job `image` xong:

- ✅ → bước `Push image` có dòng `pushing ... ghcr.io/<user>/taskhub:<sha7-A>`.
- ❌ ở `Push image` với `denied: permission_denied: write_package` → đối chiếu với điều bạn quan sát ở mục 3, sửa theo bài 03 mục 4.6 (Manage Actions access → Add repository → Role **Write**), rồi **Re-run jobs → Re-run failed jobs**.

❓ `<sha7-A>` là SHA của commit nào — commit cuối trên nhánh PR hay commit squash mới trên `main`?

**A6. Kiểm tra registry từ máy.**

```bash
GH_USER=<username-chữ-thường>
docker buildx imagetools inspect "ghcr.io/${GH_USER}/taskhub:<sha7-A>"
```

Mở trang package trên GitHub: version mới có tag `<sha7-A>`; mục platform có `linux/amd64` và `unknown/unknown`.

❓ `MediaType` là gì? So với image `v0.2.0` push tay ở tuần 8 (bạn đã xem ở bài 03, Bước 4) — khác ở đâu và vì sao?

### Phần B — Workflow `Release`

**B1. Nhánh mới, đưa `release.yml` vào.**

```bash
git switch -c ci/release-workflow
# đặt lại file .github/workflows/release.yml bạn đã viết ở bài 03
docker run --rm -v "$(pwd)":/repo --workdir /repo rhysd/actionlint:latest -color
git add .github/workflows/release.yml
git commit -m "ci: promote image and create GitHub Release on version tags"
git push -u origin ci/release-workflow
```

Mở PR. Trên tab Checks chỉ có workflow `CI`.

❓ Vì sao workflow `Release` không chạy trên PR này? Vậy thứ gì đang "kiểm tra" `release.yml` của bạn trước khi merge?

**B2. Chuẩn bị diễn tập "tag quá sớm".** Đọc hết bước này trước khi làm — các thao tác phải nhanh.

1. Mở sẵn một terminal ở `~/projects/taskhub`.
2. Squash merge PR `ci/release-workflow`.
3. **Ngay lập tức** (trong vòng ~30 giây, khi CI trên `main` vừa bắt đầu):

```bash
git switch main && git pull
git rev-parse --short=7 HEAD                 # ghi lại: <sha7-B>
git log -1 --format='%H %s'                  # đúng commit squash của PR release?
git tag -a v0.3.0-rc.1 -m "taskhub v0.3.0-rc.1 — diễn tập release"
git push origin v0.3.0-rc.1
```

❓ Vì sao commit được tag phải là commit **sau** khi `release.yml` đã vào `main` (bài 03, mục 4.8)?

**B3. Quan sát thất bại.** Tab **Actions**: hai lần chạy song song — `CI` (push trên `main`, đang chạy) và `Release` (tag `v0.3.0-rc.1`).

- Job `promote` → bước `Promote image` ❌.
- Trang tóm tắt lần chạy, mục **Annotations**: dòng lỗi `Không tìm thấy ghcr.io/<user>/taskhub:<sha7-B>...`.
- Bước `Create GitHub Release`: ⏭ không chạy.

Kiểm chứng từ máy, trong lúc CI chưa xong:

```bash
docker buildx imagetools inspect "ghcr.io/${GH_USER}/taskhub:<sha7-B>"
```

❓ Đây là lỗi của workflow hay hành vi đúng? Nếu job `promote` **không** có bước kiểm tra `imagetools inspect` mà gọi thẳng `imagetools create`, điều gì xảy ra?

**B4. Sửa mà không tạo tag mới.** Chờ `CI` trên `main` xanh (job `image` đã push `<sha7-B>`). Mở lần chạy `Release` bị đỏ → **Re-run jobs** → **Re-run failed jobs**.

❓ Lần re-run dùng `GITHUB_SHA` nào — của commit mới nhất trên `main` lúc re-run, hay của sự kiện push tag ban đầu? Dẫn chứng tài liệu.

**B5. Đọc lần chạy thành công.** Log bước `Promote image` in kết quả `imagetools inspect` cho tag `v0.3.0-rc.1`. Tab **Releases** của repo có release `v0.3.0-rc.1` với ghi chú tự sinh.

❓ Release `v0.3.0-rc.1` có nhãn **Pre-release** hay **Latest**? Vì sao (bài 03, mục 4.10)? Đây là lỗ hổng của workflow — ghi lại, bạn sẽ sửa ở [bài tập 2 của bài 03](../03-github-actions-docker-registry.md#14-bài-tập-tự-làm).

### Phần C — Chứng minh "build một lần"

**C1. So digest trên registry.**

```bash
docker buildx imagetools inspect "ghcr.io/${GH_USER}/taskhub:<sha7-B>"     | head -3
docker buildx imagetools inspect "ghcr.io/${GH_USER}/taskhub:v0.3.0-rc.1" | head -3
```

❓ Hai dòng `Digest:` có trùng nhau không? Điều đó chứng minh gì về image được phát hành?

**C2. Truy ngược về commit.**

```bash
docker pull "ghcr.io/${GH_USER}/taskhub:v0.3.0-rc.1"
docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' \
  "ghcr.io/${GH_USER}/taskhub:v0.3.0-rc.1"
git rev-parse v0.3.0-rc.1^{commit}
```

❓ Hai giá trị có trùng không? Ai đã gắn label `revision` vào image?

**C3. Đếm lần build.** Mở log job `promote`: có dòng nào giống `#N [build ...]` hay `exporting layers` không?

### Phần D — Chạy image từ GHCR như một server

**D1.** Dùng lại thư mục `~/devops-lab/04-docker/registry-test/` từ [Docker 06, Bước 8](../../04-DOCKER/06-registry.md#9-bài-thực-hành-từng-bước) (compose chỉ có `image:`, không có `build:`, tag lấy từ `TASKHUB_IMAGE_TAG`). Nếu đã xóa, tạo lại theo bước đó.

```bash
cd ~/devops-lab/04-docker/registry-test
sed -i 's/^TASKHUB_IMAGE_TAG=.*/TASKHUB_IMAGE_TAG=v0.3.0-rc.1/' .env
grep TASKHUB_IMAGE_TAG .env
docker compose pull
docker compose up -d
docker compose ps
```

**D2.** Chờ `taskhub` healthy (`start_period` 60s), rồi:

```bash
docker compose exec taskhub curl -fsS http://localhost:8080/actuator/health
echo
docker compose images
```

❓ Máy bạn có cần mã nguồn, Maven hay JDK để chạy bản này không? Server EC2 ở tuần 12 cần gì?

**D3.** Ghi tất cả câu trả lời ❓ và các SHA/digest thật vào `~/devops-journey/week10/lab02-answers.md`, kèm link lần chạy Release đỏ và lần re-run xanh.

---

## 5. Kết quả mong đợi

| Bước | Kết quả |
|---|---|
| A3 | Trên PR, job `image` build và quét; hai bước login/push **skipped**. SHA trong `Context info` **khác** commit cuối nhánh — đó là merge commit tạm `refs/pull/<số>/merge` |
| A4 | PR làm Trivy đỏ sẽ **không merge được** chỉ khi `image` là required check |
| A5 | `<sha7-A>` là SHA của **commit squash mới** trên `main`, không phải commit trên nhánh PR. Nếu gặp `write_package` thì sau khi thêm repo với role Write và re-run, push thành công |
| A6 | `MediaType: application/vnd.oci.image.index.v1+json`, có `linux/amd64` + `unknown/unknown` (attestation provenance — repo public nên `mode=max`) |
| B1 | `Release` chỉ chạy khi push tag. Trước khi merge, chỉ actionlint (trên máy) và review của bạn kiểm tra file này — vì vậy actionlint quan trọng |
| B3 | `promote` đỏ với chú thích lỗi; `imagetools inspect` từ máy báo `not found`. Đây là **hành vi đúng**: không phát hành thứ chưa build và quét. Không có bước kiểm tra, `imagetools create` cũng lỗi nhưng với thông báo khó hiểu hơn |
| B4 | Re-run dùng **đúng `GITHUB_SHA` và `GITHUB_REF` của sự kiện ban đầu** (tài liệu GitHub) → tìm `<sha7-B>` → xanh |
| B5 | Release được tạo là release **thường**, có thể được gắn **Latest** — vì `gh release create` không tự đánh dấu pre-release theo tên tag |
| C1 | Hai digest **trùng nhau**: `imagetools create` sao chép y hệt index → image phát hành chính là image CI đã build và quét |
| C2 | Hai giá trị trùng: label do `metadata-action` gắn lúc CI build |
| C3 | Không có bước build nào trong job `promote` |
| D2 | `{"status":"UP"}`. Không cần mã nguồn/Maven/JDK — chỉ cần Docker, file compose, `.env` và quyền pull image (image public: không cần đăng nhập) |

---

## 6. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Không tìm thấy `image` trong ô chọn required check | Job chưa chạy lần nào; hoặc `name:` của job khác `image` | Chạy PR trước (A3); dùng đúng tên hiện trong tab Checks |
| PR treo ở "Expected — Waiting for status to be reported" | Required check có tên không khớp tên job thật, hoặc workflow không chạy cho PR này | Sửa tên trong luật bảo vệ cho khớp; kiểm tra `on: pull_request: branches: [main]` |
| `denied: permission_denied: write_package` | Package có sẵn chưa cấp quyền cho repo | Package settings → Manage Actions access → Add repository → **Write** → re-run |
| Push tag nhưng không thấy lần chạy `Release` | Tag sai mẫu (`v0.3-rc1`); tag commit cũ chưa có `release.yml`; dùng `git push --tags` với hơn 3 tag | `git show v0.3.0-rc.1 --stat`; xóa tag sai (mục 7) và tạo tag đúng **tên mới** |
| Re-run vẫn báo `Không tìm thấy` | CI trên `main` cho `<sha7-B>` đỏ hoặc chưa xong; hoặc tag nhầm commit không thuộc `main` | Xem lần chạy CI của commit đó; `git branch -r --contains v0.3.0-rc.1` phải có `origin/main` |
| `a release with the same tag name already exists` | Bạn tạo Release tay trước khi workflow chạy | Xóa Release tay (giữ tag), re-run |
| `docker compose pull`: `manifest unknown` | Sai tag trong `.env`, hoặc gõ sai username | `grep TASKHUB_IMAGE_TAG .env`; `imagetools inspect` tên đầy đủ |
| `docker compose pull`: `unauthorized` | Package đang private | Đặt lại Public (Docker 06), hoặc đăng nhập bằng token `read:packages` |

---

## 7. Dọn dẹp

**Trên máy** `[WSL]`:

```bash
cd ~/devops-lab/04-docker/registry-test
docker compose down -v                       # ⚠️ -v xóa volume database của thư mục thử nghiệm này
docker image rm "ghcr.io/${GH_USER}/taskhub:v0.3.0-rc.1" taskhub:ci-local
```

`-v` chỉ xóa volume của project compose **thử nghiệm** này, không đụng tới volume `pgdata` của project `taskhub` chính.

**Trên GitHub** — đọc kỹ trước khi làm:

| Thứ | Làm gì | Vì sao |
|---|---|---|
| Release `v0.3.0-rc.1` | **Edit** → tick **Set as a pre-release** → Update (hoặc xóa Release nếu muốn) | Release ứng viên không được mang nhãn Latest |
| Tag Git `v0.3.0-rc.1` | **Giữ lại** | Tag là lịch sử. Một tag rc đã đẩy lên là bình thường trong SemVer |
| Version trên GHCR chứa `:v0.3.0-rc.1` | ⚠️ **Không xóa** | Xem cảnh báo bên dưới |
| Nhánh `ci/build-push-image`, `ci/release-workflow` | Xóa sau khi merge (nút *Delete branch* trên PR, `git branch -d` ở máy) | Nhánh ngắn hạn |

> ⚠️ **Vì sao không xóa version trên GHCR?** Trên GHCR, một *version* ứng với **một digest**, và mọi tag trỏ cùng digest được liệt kê chung trong version đó. `:v0.3.0-rc.1` và `:<sha7-B>` cùng digest (Phần C) → xóa version là **mất cả hai tag**, kể cả image của một commit trên `main` — thứ có thể cần để rollback. Theo tài liệu GitHub, version đã xóa chỉ khôi phục được **trong 30 ngày**, và chỉ khi tên/version chưa bị dùng lại. Trước khi xóa bất kỳ version nào sau này, luôn xem danh sách tag của nó.

> ⚠️ **Nếu bạn vẫn muốn xóa tag Git** (ví dụ tag sai tên): `git push origin --delete <tag>` rồi `git tag -d <tag>`. Người khác đã fetch tag đó vẫn giữ bản của họ. **Không bao giờ tạo lại cùng tên tag cho commit khác** — lần sau dùng `v0.3.0-rc.2`.

---

## 8. Câu hỏi sau lab

1. Trên PR, vì sao SHA trong log metadata không trùng commit cuối nhánh? Điều đó có gây hại gì cho thiết kế "PR không push" không?
2. Bạn cần những gì để biến một Trivy đỏ thành "không merge được"? Thiếu một trong hai thứ đó thì sao?
3. Kể lại tình huống ở Phần B bằng ngôn ngữ của một postmortem ngắn: điều gì xảy ra, vì sao, phát hiện thế nào, sửa thế nào, phòng ngừa thế nào.
4. Digest trùng nhau ở C1 chứng minh điều gì mà "cùng tên tag" không chứng minh được?
5. Nếu một ngày CI trên `main` bị đỏ ở bước Trivy cho commit bạn muốn phát hành, `release.yml` sẽ làm gì? Đó là ưu điểm hay nhược điểm?
6. Vì sao không xóa version GHCR của bản rc? Nêu một tình huống xóa nhầm gây sự cố thật.

> Lời giải: [solutions/lab-02-solutions.md](../solutions/lab-02-solutions.md) — chỉ mở sau khi đã tự làm.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — Configuring a package's access control](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility) | Manage Actions access, role Write | 2026-10-31 |
| [GitHub Docs — Managing a branch protection rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/managing-a-branch-protection-rule) | Require status checks | 2026-10-31 |
| [GitHub Docs — Re-running workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs) | Re-run failed jobs, cùng `GITHUB_SHA`/`GITHUB_REF`, giới hạn 30 ngày | 2026-10-31 |
| [GitHub Docs — Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) | Push tag, giới hạn 3 tag | 2026-10-31 |
| [GitHub Docs — Deleting and restoring a package](https://docs.github.com/en/packages/learn-github-packages/deleting-and-restoring-a-package) | Khôi phục version đã xóa trong 30 ngày | 2026-10-31 |
| [Docker Docs — `buildx imagetools create`](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/) | Carbon copy khi nguồn là index | 2026-10-31 |
| [GitHub CLI — `gh release create`](https://cli.github.com/manual/gh_release_create) | `--verify-tag`, `--generate-notes`, nhãn Latest | 2026-10-31 |
