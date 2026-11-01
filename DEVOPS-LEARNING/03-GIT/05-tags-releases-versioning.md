# 05. Tags, Releases & Semantic Versioning

> ⏱️ ~2 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Git fundamentals & internals](01-git-fundamentals-internals.md), [04. Quy trình Git trong đội nhóm](04-team-workflows.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + trình duyệt (GitHub)

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
12. [Đọc thông báo lỗi và xử lý](#12-đọc-thông-báo-lỗi-và-xử-lý)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Phân biệt **lightweight tag** và **annotated tag**, biết vì sao release dùng annotated tag.
- Tạo, xem, push và (khi thật cần) xóa tag — hiểu vì sao **không được sửa tag đã công bố**.
- Đặt số phiên bản theo **Semantic Versioning**: khi nào tăng MAJOR, MINOR, PATCH; `0.y.z` và `-rc.1` nghĩa là gì.
- Tạo **GitHub Release** từ tag, dùng release notes tự sinh, viết **CHANGELOG**.
- Giải thích vì sao Git tag là nền móng của **Docker image tag** và **rollback** ở các module sau.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Liên quan đến tag và phiên bản |
|---|---|
| "Production đang chạy phiên bản nào?" | Trả lời bằng một con số `v0.4.1` truy ngược được về đúng commit |
| Pipeline release | Tạo tag `v*` → CI build image `taskhub:v0.4.1` và deploy (Module 05) |
| Bản mới lỗi, cần quay lại | **Rollback** = deploy lại image của tag trước (`v0.4.0`) — vài phút thay vì sửa gấp (Module 05, 08) |
| Nâng phiên bản PostgreSQL driver hay Spring Boot | Đọc số phiên bản để biết có thay đổi không tương thích (MAJOR) hay không |
| Viết postmortem | "Sự cố bắt đầu từ `v0.5.0`, release notes cho thấy thay đổi X" |

Không có tag và quy ước phiên bản, mọi câu hỏi trên đều phải trả lời bằng "để tôi xem lại commit…".

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Tag là gì?

Từ [bài 01](01-git-fundamentals-internals.md), bạn biết **branch** là một con trỏ **di chuyển** — mỗi commit mới, con trỏ nhánh tiến lên. **Tag** (nhãn) cũng là con trỏ tới một commit, nhưng **đứng yên**: nó đánh dấu vĩnh viễn "commit này là phiên bản 0.1.0".

```text
              tag v0.1.0 (đứng yên)
                 │
main: ──●──●──●──●──●──●   ← nhánh main (tiếp tục di chuyển)
```

### 3.2. Hai loại tag

| | Lightweight tag (tag nhẹ) | Annotated tag (tag có chú thích) |
|---|---|---|
| Bản chất | Chỉ là tên trỏ tới commit | **Đối tượng riêng** trong Git: có người tạo, email, ngày, thông điệp, có thể ký số |
| Tạo | `git tag v0.1.0` | `git tag -a v0.1.0 -m "..."` |
| Dùng cho | Đánh dấu tạm, cá nhân | **Release** |
| `git describe` mặc định | Bỏ qua | Dùng |

**Quy tắc của `taskhub`: mọi release dùng annotated tag.** Pro Git cũng khuyến nghị như vậy.

### 3.3. Phiên bản là một "lời hứa"

Số phiên bản không chỉ là bộ đếm. Với **Semantic Versioning**, nó là lời hứa với người dùng: "nâng từ `1.3.2` lên `1.4.0` thì code của bạn vẫn chạy; nâng lên `2.0.0` thì phải đọc hướng dẫn chuyển đổi".

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Semantic Versioning (SemVer)

Định dạng: **`MAJOR.MINOR.PATCH`**, ví dụ `2.4.1`.

| Phần | Tăng khi | Reset |
|---|---|---|
| **MAJOR** | Thay đổi **không tương thích ngược** với API công khai | MINOR và PATCH về 0 |
| **MINOR** | Thêm tính năng **tương thích ngược** (hoặc đánh dấu một tính năng sắp bị bỏ) | PATCH về 0 |
| **PATCH** | Sửa lỗi tương thích ngược | — |

Ví dụ với API của `taskhub`:

| Thay đổi | Từ `1.2.3` thành |
|---|---|
| Sửa lỗi `updatedAt` không cập nhật | `1.2.4` |
| Thêm endpoint lọc `?status=` | `1.3.0` |
| Đổi tên trường `name` → `title` (client cũ lỗi) | `2.0.0` |

**Các quy tắc quan trọng khác:**

- **`0.y.z`** — giai đoạn phát triển ban đầu: **mọi thứ có thể thay đổi bất cứ lúc nào**, API chưa được coi là ổn định. `taskhub` bắt đầu ở `0.1.0` vì lý do này; khi bạn coi nó là "hoàn chỉnh để đưa vào CV" ở tuần 23 có thể phát hành `1.0.0`.
- **Pre-release** (bản phát hành trước): thêm `-` và định danh sau PATCH: `1.0.0-rc.1`, `1.0.0-alpha.2`. Bản pre-release **xếp trước** bản chính thức: `1.0.0-rc.1 < 1.0.0`.
- **Build metadata**: thêm `+`: `1.0.0+20261031` — bị bỏ qua khi so sánh thứ tự.
- **`v1.2.3` có phải là một semantic version không?** Theo FAQ của SemVer: **không** — phiên bản là `1.2.3`; tiền tố `v` chỉ là quy ước phổ biến khi đặt tên **tag** Git. `taskhub` dùng tag dạng `v0.1.0`.

**Liên hệ với Conventional Commits** ([bài 04](04-team-workflows.md#46--conventional-commits-đầy-đủ-hơn)): `fix` → PATCH, `feat` → MINOR, có `!`/`BREAKING CHANGE` → MAJOR.

### 4.2. 🟥 Làm việc với tag

**Tạo annotated tag** trên commit hiện tại (hoặc chỉ định commit):

```bash
git tag -a v0.1.0 -m "taskhub v0.1.0: task CRUD API, health check"
git tag -a v0.0.9 -m "..." 9fceb02      # gắn tag cho một commit cũ
```

**`git push` mặc định KHÔNG đẩy tag.** Phải đẩy riêng:

| Lệnh | Đẩy gì | Khuyến nghị |
|---|---|---|
| `git push origin v0.1.0` | Đúng một tag | ✅ Rõ ràng nhất |
| `git push origin --tags` | **Mọi** tag local chưa có trên remote | ⚠️ Dễ đẩy nhầm tag thử nghiệm |
| `git push --follow-tags` | Commit + các **annotated** tag trỏ tới commit đang được đẩy | 🟨 Tiện khi đã quen |

**Xem tag:**

```bash
git tag                       # liệt kê
git tag -l "v0.*"             # lọc theo mẫu
git show v0.1.0               # thông tin tag + commit
```

**Checkout một tag** đưa bạn vào trạng thái **detached HEAD** (HEAD không đứng trên nhánh nào — bài 01). Chỉ để xem; muốn sửa thì tạo nhánh: `git switch -c hotfix/0.1.1 v0.1.0`.

### 4.3. 🟥 ⚠️ Xóa và sửa tag — và vì sao không nên

```bash
git tag -d v0.1.0                     # xóa tag local (không ảnh hưởng remote)
git push origin --delete v0.1.0       # ⚠️ xóa tag trên remote
```

**Quy tắc vàng: tag đã push và đã có người/hệ thống dùng thì KHÔNG sửa, KHÔNG di chuyển.** Lý do:

- Máy của người khác và CI có thể đã fetch tag cũ — tag ở máy họ vẫn trỏ commit cũ, Git **không tự cập nhật** tag đã có. Cùng một tên `v0.1.0` trỏ tới hai commit khác nhau ở hai nơi.
- Image `taskhub:v0.1.0` đã build từ commit cũ → "v0.1.0" không còn nghĩa là một thứ duy nhất → rollback không đáng tin.

**Làm gì khi tag sai?** Phát hành phiên bản mới: phát hiện lỗi trong `v0.1.0` → sửa → `v0.1.1`. Chỉ xóa/sửa tag khi **chắc chắn chưa ai dùng** (vừa push nhầm vài phút, chưa có pipeline nào chạy).

### 4.4. 🟥 GitHub Releases

**Release** trên GitHub là một trang gắn với **một tag**, gồm:

- Tiêu đề và **release notes** (ghi chú phát hành).
- **Source code** dạng zip và tar.gz — GitHub tự tạo từ trạng thái repo tại tag.
- **Assets** (tệp đính kèm) tùy chọn: ví dụ file `.jar` đã build. Mỗi release tối đa 1.000 file, mỗi file dưới 2 GiB.
- Đánh dấu **pre-release** (cho `-rc.1`) hoặc **latest**.

Chỉ người có quyền write mới tạo release; ai đọc được repo đều xem được.

**Release notes tự sinh:** khi tạo release, bấm **Generate release notes** — GitHub liệt kê các PR đã merge kể từ release trước, danh sách người đóng góp và link "Full Changelog". Có thể nhóm PR theo label bằng file `.github/release.yml`:

```yaml
# .github/release.yml
changelog:
  categories:
    - title: Breaking Changes 🛠
      labels: [breaking-change]
    - title: Tính năng mới 🎉
      labels: [enhancement]
    - title: Sửa lỗi 🐛
      labels: [bug]
    - title: Khác
      labels: ["*"]
```

Vì `taskhub` dùng squash merge với title PR theo Conventional Commits, release notes tự sinh đã khá dễ đọc ngay cả khi chưa gắn label.

### 4.5. 🟨 CHANGELOG

`CHANGELOG.md` là file trong repo ghi thay đổi qua từng phiên bản, viết **cho con người đọc**. Quy ước phổ biến *Keep a Changelog*:

- Phiên bản mới nhất ở trên cùng, mỗi phiên bản có ngày phát hành.
- Nhóm thay đổi theo loại: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.
- Có mục **Unreleased** ở đầu để gom thay đổi sắp phát hành; khi release thì chuyển các mục đó xuống tiêu đề phiên bản mới.
- Ghi rõ dự án có theo SemVer hay không.

```markdown
# Changelog
Dự án tuân theo [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-12-13
### Added
- CRUD API cho task: `/api/tasks`.
- Health check `/actuator/health` gồm trạng thái database.
- Flyway migration `V1__create_tasks_table.sql`.
```

Release notes trên GitHub và `CHANGELOG.md` có thể cùng tồn tại: release notes tiện cho người xem trên web, CHANGELOG đi theo code.

### 4.6. 🟥 Git tag và Docker image tag — báo trước Module 04, 05

Từ Module 04, mỗi phiên bản `taskhub` sẽ là một **Docker image**. Quy ước gắn tag image của dự án:

| Image tag | Khi nào tạo | Ý nghĩa |
|---|---|---|
| `ghcr.io/<user>/taskhub:<git-sha>` (ví dụ `:3f2a9c1`) | Mỗi lần merge vào `main` | Truy ngược chính xác về một commit |
| `ghcr.io/<user>/taskhub:v0.1.0` | Khi tạo Git tag `v0.1.0` | Phiên bản phát hành, con người đọc được |

Chuỗi liên kết: **Git tag `v0.1.0` → commit `3f2a9c1` → image `:v0.1.0` (cũng là `:3f2a9c1`) → đang chạy trên EC2.** Nhờ chuỗi này:

- Biết production đang chạy code nào.
- **Rollback** = đổi image đang chạy về tag trước (`v0.0.9`) — không build lại, không sửa code vội vàng.

Đây là lý do quy tắc "không sửa tag đã công bố" ở mục 4.3 quan trọng đến vậy: tag phải **bất biến** (immutable) thì rollback mới đáng tin.

> Tránh dựa vào tag image `latest` cho production: nó luôn bị ghi đè, nên không trả lời được "đang chạy phiên bản nào" và không rollback được.

### 4.7. 🟨 `git describe`

```bash
git describe
```

```text
v0.1.0-3-g8c1d2e4
```

Đọc là: "commit hiện tại đi **sau** tag `v0.1.0` **3** commit, mã commit rút gọn `8c1d2e4`" (`g` = git). Nếu đúng tại commit có tag, chỉ in `v0.1.0`. Mặc định chỉ dùng **annotated tag** — thêm `--tags` để tính cả lightweight tag. Hay dùng để gắn phiên bản tự động vào build: `--dirty` thêm hậu tố `-dirty` nếu thư mục làm việc có thay đổi chưa commit.

### 4.8. 🟦 Signed tags

`git tag -s v1.0.0 -m "..."` tạo tag **ký số** bằng khóa GPG (hoặc SSH) — chứng minh tag do đúng bạn tạo, không bị giả mạo. Dùng trong dự án có yêu cầu bảo mật chuỗi cung ứng (supply chain) cao. Liên quan Module 10; Junior chỉ cần biết khái niệm.

### 4.9. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| Tag `v*` | Module 05 — workflow release `on: push: tags: ['v*']` |
| Image tag theo SHA và SemVer | Module 04 (registry), Module 05 (build & push GHCR) |
| Tag bất biến → rollback | Module 05 (chiến lược rollback), Module 08 (runbook rollback) |
| `0.y.z` → `1.0.0` | Tuần 23 — phát hành `taskhub v1.0` |
| Signed tags, chuỗi cung ứng | Module 10 — DevSecOps |
| Đọc SemVer của dependency | Mọi module — nâng Spring Boot, image `postgres:17`, provider Terraform |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Rollback trong 3 phút nhờ tag

Thứ Sáu, `v0.6.0` lên production, 10 phút sau tỉ lệ lỗi 500 tăng. Kỹ sư trực ca không cần đọc code: đổi image đang chạy từ `taskhub:v0.6.0` về `taskhub:v0.5.2`, khởi động lại, lỗi biến mất. Thứ Hai cả team mới tìm nguyên nhân bằng cách so sánh `git diff v0.5.2 v0.6.0` và đọc release notes của `v0.6.0`. Sau khi sửa, phát hành `v0.6.1` — **không** sửa lại tag `v0.6.0`.

### Ví dụ 2: Đọc phiên bản dependency

Bạn thấy Spring Boot có bản `4.1.2` trong khi `taskhub` dùng `4.1.0`: tăng PATCH → sửa lỗi, nâng an toàn. Thấy `5.0.0` → MAJOR → chắc chắn có thay đổi không tương thích, phải đọc migration guide và lên kế hoạch riêng. Cùng logic với image `postgres:17` → `postgres:18` (Module 04 sẽ chỉ ra một thay đổi như vậy: đường dẫn dữ liệu trong image đổi ở bản 18).

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Từ commit đến production

```text
 PR squash merge          git tag -a v0.1.0          GitHub Release v0.1.0
 main: ──●──●──●  ─────────────▶ ● (3f2a9c1) ─────────▶ (notes + source zip)
                                 │
                                 │ Module 05: CI thấy tag v*
                                 ▼
                    image ghcr.io/<user>/taskhub:v0.1.0  (= :3f2a9c1)
                                 │
                                 ▼
                          EC2 production chạy v0.1.0
                                 │  lỗi?
                                 ▼
                    rollback: chạy lại image :v0.0.9 (tag cũ, bất biến)
```

### 6.2. Thứ tự phiên bản theo SemVer

```text
0.1.0 < 0.1.1 < 0.2.0 < 1.0.0-alpha < 1.0.0-rc.1 < 1.0.0-rc.2 < 1.0.0 < 1.0.1 < 1.1.0 < 2.0.0
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `git tag -a <tag> -m "<msg>" [commit]` | Tạo annotated tag | 🟥 |
| `git tag`, `git tag -l "<mẫu>"` | Liệt kê tag | 🟥 |
| `git show <tag>` | Xem chi tiết tag và commit | 🟥 |
| `git push origin <tag>` | Đẩy một tag | 🟥 |
| `git push origin --tags` | Đẩy mọi tag chưa có trên remote | 🟨 |
| `git tag -d <tag>` | Xóa tag local | 🟥 |
| `git push origin --delete <tag>` | ⚠️ Xóa tag trên remote | 🟥 |
| `git switch -c <nhánh> <tag>` | Tạo nhánh từ một tag (hotfix bản cũ) | 🟨 |
| `git log --oneline <tag1>..<tag2>` | Commit giữa hai phiên bản | 🟥 |
| `git describe [--tags] [--dirty]` | Mô tả commit theo tag gần nhất | 🟨 |
| `git ls-remote --tags origin` | Xem tag đang có trên remote | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa** — SHA, ngày giờ trên máy bạn sẽ khác.

### Tạo và xem annotated tag

```bash
git switch main && git pull
git tag -a v0.1.0 -m "taskhub v0.1.0: task CRUD API, health check"
git show v0.1.0 --stat
```

```text
tag v0.1.0
Tagger: Phuong <you@example.com>
Date:   Sat Dec 13 10:02:11 2026 +0700

taskhub v0.1.0: task CRUD API, health check

commit 3f2a9c1e7b... (HEAD -> main, tag: v0.1.0, origin/main)
Author: Phuong <you@example.com>
Date:   Sat Dec 13 09:55:40 2026 +0700

    feat(api): add task CRUD endpoints (#6)

 app/src/main/java/com/taskhub/TaskController.java | 74 ++++++++
 ...
```

| Tham số | Ý nghĩa |
|---|---|
| `-a` | Annotated — tạo đối tượng tag có người tạo, ngày, thông điệp |
| `-m "..."` | Thông điệp của tag (không có `-m` thì mở editor) |
| Phần `tag v0.1.0 / Tagger / Date` | Chỉ annotated tag mới có. Lightweight tag sẽ chỉ hiện thẳng phần `commit ...` |

### Đẩy tag và kiểm tra trên remote

```bash
git push origin v0.1.0
git ls-remote --tags origin
```

```text
To github.com:phuong-dev/taskhub.git
 * [new tag]         v0.1.0 -> v0.1.0
8e41c0d5a2...	refs/tags/v0.1.0
3f2a9c1e7b...	refs/tags/v0.1.0^{}
```

`git ls-remote` hiện 2 dòng cho một annotated tag: dòng đầu là **đối tượng tag**, dòng `^{}` là **commit** mà tag trỏ tới. Lightweight tag chỉ có một dòng (trỏ thẳng commit).

### Xem thay đổi giữa hai phiên bản

```bash
git log --oneline v0.1.0..v0.2.0
```

```text
c71e0a2 feat(api): filter tasks by status (#9)
5b7e9aa chore: bump spring boot to 4.1.2 (#8)
91c03fd fix(db): use env var for datasource url (#7)
```

Danh sách commit thuộc `v0.2.0` mà `v0.1.0` chưa có — nguyên liệu để viết release notes hoặc điều tra sự cố. Có `feat` → đúng là tăng MINOR.

### ⚠️ Xóa tag (chỉ trên repo thử nghiệm)

```bash
git tag -d v9.9.9
git push origin --delete v9.9.9
```

```text
Deleted tag 'v9.9.9' (was 1a2b3c4)
To github.com:phuong-dev/sandbox.git
 - [deleted]         v9.9.9
```

Lưu ý: người khác đã fetch tag này vẫn giữ nó trên máy họ cho đến khi tự xóa.

---

## 9. Bài thực hành từng bước

**Lab: Luyện tag trên repo thử nghiệm, rồi phát hành `taskhub v0.1.0`** · `[WSL]` + trình duyệt · ~60 phút

### Phần A — Repo thử nghiệm local (không push lên đâu cả)

```bash
mkdir -p ~/devops-lab/03-git/tags-lab && cd ~/devops-lab/03-git/tags-lab
git init -b main
for i in 1 2 3; do echo "v$i" > app.txt; git add app.txt; git commit -m "feat: step $i"; done
git log --oneline
```

**Bước A1 — Hai loại tag:**

```bash
git tag -a v0.1.0 -m "first release" HEAD~2     # annotated, trên commit "step 1"
git tag wip-test HEAD~1                          # lightweight, trên commit "step 2"
git show v0.1.0 --no-patch
git show wip-test --no-patch
git cat-file -t v0.1.0
git cat-file -t wip-test
```

❓ Hai lệnh `git cat-file -t` in ra gì? Điều đó chứng minh gì về bản chất hai loại tag (liên hệ bài 01)?

**Bước A2 — `git describe`:**

```bash
git describe
git describe --tags
```

❓ Vì sao hai lệnh cho kết quả khác nhau?

**Bước A3 — Gắn nhầm tag và sửa (khi chưa push):**

```bash
git tag -a v0.2.0 -m "oops, wrong commit" HEAD~1   # gắn nhầm commit
git tag -d v0.2.0
git tag -a v0.2.0 -m "second release"             # gắn lại đúng HEAD
git tag -d wip-test                               # dọn tag thử nghiệm
git log --oneline --decorate
```

**Bước A4 — Hotfix bản cũ từ tag:**

```bash
git switch -c hotfix/0.1.1 v0.1.0
echo "fix" >> app.txt && git commit -am "fix: urgent fix on 0.1.x"
git tag -a v0.1.1 -m "hotfix"
git log --oneline --graph --all --decorate
```

❓ Vẽ lại đồ thị. Commit `v0.1.1` có nằm trên `main` không?

### Phần B — Phát hành taskhub v0.1.0

> Làm phần này **sau khi** ứng dụng tuần 6 đã merge vào `main` và đạt Definition of Done ([milestone v-pre, tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md#tuần-6--đặc-tả-ứng-dụng-spring-boot)).

**Bước B1 — Thêm CHANGELOG qua PR:**

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c docs/changelog-0.1.0
nano CHANGELOG.md          # theo mẫu mục 4.5, liệt kê những gì đã có
git add CHANGELOG.md && git commit -m "docs: add changelog for 0.1.0"
git push -u origin docs/changelog-0.1.0
```

Mở PR, tự review, squash merge (bài 03).

**Bước B2 — Tạo và đẩy tag:**

```bash
git switch main && git pull
git log --oneline -3                       # chắc chắn HEAD là commit bạn muốn phát hành
git tag -a v0.1.0 -m "taskhub v0.1.0: task CRUD API, health check, Flyway"
git push origin v0.1.0
```

**Bước B3 — Tạo GitHub Release:** trên GitHub: **Releases → Draft a new release** → chọn tag `v0.1.0` → title `v0.1.0` → bấm **Generate release notes** → đọc lại và bổ sung 2–3 dòng tóm tắt bằng lời của bạn (có thể dán phần `0.1.0` từ CHANGELOG) → **Publish release**.

**Bước B4 — Ghi lại** vào `~/devops-journey/week06/lab-release.md`: link release, kết quả `git ls-remote --tags origin`, và trả lời: "Nếu ngày mai phát hiện lỗi trong v0.1.0, bạn làm gì?"

---

## 10. Kết quả mong đợi

- **A1:** `git cat-file -t v0.1.0` in `tag`; `git cat-file -t wip-test` in `commit` → annotated tag là một **đối tượng tag** riêng trong cơ sở dữ liệu Git (trỏ tới commit), lightweight tag chỉ là tên trỏ thẳng vào commit. `git show wip-test` không có phần `Tagger:`.
- **A2:** `git describe` → `v0.1.0-2-g<sha>` (bỏ qua lightweight tag, nên tag gần nhất là `v0.1.0`, cách HEAD 2 commit). `git describe --tags` → `wip-test-1-g<sha>` (tính cả lightweight tag, và `wip-test` gần HEAD hơn). Đây là lý do pipeline dựa vào `git describe` chỉ "thấy" tag release nếu release dùng annotated tag.
- **A3:** sau khi gắn lại, `v0.2.0` nằm trên HEAD. Việc này chỉ an toàn vì tag **chưa từng được push**.
- **A4:** `v0.1.1` nằm trên nhánh `hotfix/0.1.1`, **không** nằm trên `main` — đồ thị có một nhánh rẽ ra từ `v0.1.0`. Trong thực tế bản sửa này cũng phải được đưa vào `main` (bằng PR hoặc cherry-pick) để không bị mất ở phiên bản sau.
- **B:** trang Releases có `v0.1.0` (Latest) với release notes; `git ls-remote --tags origin` có 2 dòng cho `v0.1.0` (đối tượng tag và `^{}`).
- **B4:** câu trả lời đúng: sửa trên nhánh `fix/...` → PR → merge → phát hành `v0.1.1`; **không** sửa hay di chuyển tag `v0.1.0`.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Tag có trên máy nhưng không thấy trên GitHub | `git push` không đẩy tag | `git push origin <tag>` |
| `fatal: tag 'v0.1.0' already exists` | Tag đã tồn tại local | Kiểm tra `git show v0.1.0`. Nếu chưa push và gắn nhầm → `git tag -d` rồi tạo lại. Nếu đã push → phát hành phiên bản mới |
| `! [rejected] v0.1.0 -> v0.1.0 (already exists)` khi push | Remote đã có tag cùng tên trỏ commit khác | **Dừng lại.** Đừng `--force`. Tìm hiểu vì sao có hai tag khác nhau; thường đáp án là phát hành số mới |
| Tag gắn vào commit trên nhánh feature chưa merge | Quên `git switch main && git pull` trước khi tag | Luôn tag trên `main` mới nhất; kiểm tra `git log --oneline -3` trước |
| `git describe` báo `fatal: No names found` | Repo chỉ có lightweight tag (hoặc không có tag) | Dùng `git describe --tags`, hoặc tạo annotated tag |
| Release notes tự sinh trống | Không có PR nào được merge giữa hai tag (commit đẩy thẳng), hoặc chọn sai tag trước | Kiểm tra mục *Previous tag* khi tạo release |
| Đẩy nhầm cả loạt tag thử nghiệm | Dùng `git push --tags` | Đẩy từng tag; xóa tag thử nghiệm local trước khi đẩy |

---

## 12. Đọc thông báo lỗi và xử lý

### Push tag bị từ chối

```text
To github.com:phuong-dev/taskhub.git
 ! [rejected]        v0.1.0 -> v0.1.0 (already exists)
error: failed to push some refs to 'github.com:phuong-dev/taskhub.git'
hint: Updates were rejected because the tag already exists in the remote.
```

- `(already exists)` → trên GitHub đã có tag `v0.1.0`. Git **từ chối ghi đè tag** theo mặc định — đây là cơ chế bảo vệ, đúng với nguyên tắc tag bất biến.
- Điều tra: `git ls-remote --tags origin | grep v0.1.0` (commit trên remote) so với `git rev-parse v0.1.0^{}` (commit local). Nếu khác nhau → có hai "v0.1.0" khác nhau, hỏi team trước khi làm gì.

### "Production đang chạy phiên bản nào, khác bản trước ở đâu?"

Chuỗi lệnh điều tra khi có sự cố sau release:

```bash
git fetch --tags
git log --oneline v0.5.2..v0.6.0          # những thay đổi trong bản mới
git diff --stat v0.5.2 v0.6.0              # file nào thay đổi
git show v0.6.0 --no-patch                 # ai tạo tag, khi nào, thông điệp gì
```

Ghi kết quả vào phần "Dòng thời gian" của postmortem (Module 08).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Tag khác branch ở điểm cốt lõi nào?
2. Lightweight tag và annotated tag khác nhau thế nào? Release nên dùng loại nào, vì sao?
3. `git push` có đẩy tag không? Kể hai cách đẩy tag và rủi ro của `--tags`.
4. Phiên bản `1.4.2` thành bao nhiêu khi: (a) sửa lỗi; (b) thêm endpoint mới; (c) xóa một endpoint cũ?
5. `0.y.z` mang ý nghĩa gì theo SemVer? Vì sao `taskhub` bắt đầu ở `0.1.0`?
6. Sắp xếp: `1.0.0`, `1.0.0-rc.2`, `0.9.9`, `1.0.0-rc.1`, `1.0.1`.
7. `v1.2.3` có phải semantic version không?
8. Vì sao không được di chuyển một tag đã push? Kể hai hậu quả cụ thể với DevOps.
9. Phát hiện lỗi trong `v0.3.0` đã phát hành — quy trình đúng là gì?
10. GitHub Release gồm những gì ngoài tag?
11. Giải thích chuỗi "Git tag → commit → image tag → production" và vai trò của nó khi rollback.
12. Đọc kết quả `v0.2.0-5-g1a2b3c4` của `git describe`.
13. Vì sao không nên dùng image tag `latest` cho production?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/05-solutions.md](solutions/05-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Tính phiên bản.** Phiên bản hiện tại `0.4.1`. Các PR được merge theo thứ tự: `docs: update README`, `fix(api): return 404 for missing task`, `feat(api): add pagination`, `chore: bump flyway`, `feat(api)!: change task id from Long to UUID`. Nếu phát hành sau **mỗi** PR (chỉ khi PR đó làm thay đổi phiên bản), liệt kê chuỗi phiên bản. Nếu chỉ phát hành **một lần** sau cả 5 PR thì là bao nhiêu? Lưu ý quy tắc của `0.y.z`.

**Bài 2 — CHANGELOG.** Viết mục `CHANGELOG.md` cho phiên bản phát hành một lần ở Bài 1 theo chuẩn Keep a Changelog (nhóm Added/Changed/Fixed…). Commit nào không cần đưa vào? Vì sao?

**Bài 3 — Pre-release.** Trên repo thử nghiệm local, mô phỏng phát hành `1.0.0` qua hai bản `1.0.0-rc.1`, `1.0.0-rc.2`. Dùng `git tag -l --sort=v:refname` (đọc `man git-tag` phần `--sort`) để liệt kê đúng thứ tự phiên bản. So sánh với `git tag -l` không sắp xếp — có khác không? Vì sao thứ tự chữ cái không phải thứ tự phiên bản (gợi ý: `v0.10.0` và `v0.9.0`)?

**Bài 4 — `release.yml`.** Tạo label `enhancement`, `bug`, `breaking-change` trong repo `taskhub` và file `.github/release.yml` (qua PR) để release notes nhóm theo các label đó. Ở release kế tiếp, gắn label cho các PR và kiểm tra release notes tự sinh có nhóm đúng không.

**Bài 5 — Kịch bản sự cố.** Đồng nghiệp lỡ chạy `git push origin --delete v0.2.0` và tạo lại `v0.2.0` trỏ vào commit mới hơn. CI đã từng build image `taskhub:v0.2.0` từ commit cũ. Liệt kê các vấn đề phát sinh, cách phát hiện (những lệnh nào), và đề xuất biện pháp phòng ngừa (gợi ý: tag protection bằng rulesets trên GitHub — tự tìm trong GitHub Docs và ghi link nguồn).

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] `taskhub` có annotated tag `v0.1.0` trên GitHub và một GitHub Release có release notes.
- [ ] Bạn giải thích được kết quả `git cat-file -t` cho hai loại tag.
- [ ] Bạn tính đúng phiên bản trong Bài tập 1, kể cả trường hợp `0.y.z`.
- [ ] Khi được hỏi "phát hiện lỗi trong bản đã phát hành", bạn trả lời ngay "phát hành bản PATCH mới, không sửa tag".
- [ ] Bạn vẽ được chuỗi Git tag → image tag → production → rollback mà không nhìn tài liệu.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Pro Git — 2.6 Git Basics: Tagging](https://git-scm.com/book/en/v2/Git-Basics-Tagging) | Hai loại tag, push, xóa, checkout tag | 2026-10-31 |
| [git-describe documentation](https://git-scm.com/docs/git-describe) | Định dạng kết quả, `--tags`, `--dirty` | 2026-10-31 |
| [Semantic Versioning 2.0.0](https://semver.org/) | Quy tắc tăng phiên bản, `0.y.z`, pre-release, FAQ về tiền tố `v` | 2026-10-31 |
| [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) | Cấu trúc CHANGELOG | 2026-10-31 |
| [GitHub Docs — About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases) | Release, assets, quyền | 2026-10-31 |
| [GitHub Docs — Automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes) | Release notes tự sinh, `.github/release.yml` | 2026-10-31 |
| [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) | Liên hệ commit với SemVer | 2026-10-31 |
