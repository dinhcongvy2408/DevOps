# 00. Ôn tập Git nhanh (tuần 1)

> ⏱️ ~2 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Kiến trúc Linux & Filesystem](../01-LINUX/01-linux-architecture-filesystem.md)
> Môi trường: `[WSL]` Ubuntu 24.04 · Trình duyệt (GitHub)

> **Đây là bài ôn nhanh**, không phải bài Git đầy đủ. Bạn đã từng dùng Git, nên bài này chỉ làm 3 việc: (1) dựng lại đúng mô hình tư duy về Git, (2) cấu hình Git **bên trong WSL** cho đúng, (3) tạo repo nhật ký học tập `devops-journey` để dùng từ tuần 1. Branching, conflict, Pull Request, workflow nhóm, tag/release học đầy đủ ở **tuần 6** (các bài 01–05 của module này).

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

- Giải thích được 3 vùng của Git: **working directory**, **staging area**, **repository** — và lệnh nào chuyển thay đổi giữa chúng.
- Cấu hình Git trong WSL đúng chuẩn (tên, email, nhánh mặc định `main`, xử lý xuống dòng CRLF/LF, editor).
- Kết nối WSL với GitHub bằng **SSH key**.
- Tạo repo `devops-journey` và làm vòng lặp hằng ngày: `status → add → commit → push`.
- Viết `.gitignore` và commit message rõ ràng; biết phải làm gì nếu lỡ commit **secret** (thông tin bí mật).

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Với DevOps, Git không chỉ là nơi lưu code:

| Trong công việc | Git đóng vai trò |
|---|---|
| CI/CD (Module 05) | Mỗi `push` hoặc Pull Request **kích hoạt pipeline** |
| Infrastructure as Code (Module 07) | Hạ tầng AWS được mô tả bằng file Terraform, lưu và review trong Git |
| Sự cố production | `git log` trả lời câu hỏi "ai đổi gì, lúc nào" — thường là manh mối đầu tiên |
| Rollback (Module 05, 08) | Quay về phiên bản trước = quay về một commit/tag cụ thể |
| Bảo mật (Module 10) | Secret lọt vào Git là một trong những sự cố bảo mật phổ biến nhất |

Nguyên tắc DevOps: **mọi thứ đều nằm trong Git** — code, cấu hình, hạ tầng, tài liệu, pipeline.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Git lưu "ảnh chụp", không lưu "danh sách thay đổi"

Mỗi **commit** (lần ghi nhận) là một **ảnh chụp toàn bộ dự án** tại thời điểm đó, kèm thông tin: ai tạo, lúc nào, lời nhắn gì, và commit cha là commit nào. Các commit nối với nhau thành một chuỗi lịch sử.

Mỗi commit có một mã định danh duy nhất (**hash**, chuỗi 40 ký tự hex, thường chỉ hiển thị 7 ký tự đầu, ví dụ `a1b2c3d`).

### 3.2. Git là hệ thống phân tán

**Repository** (kho mã — repo) trên máy bạn là một bản **đầy đủ** lịch sử, không phải bản sao phụ. GitHub chỉ là một repo khác nằm trên server, gọi là **remote** (kho từ xa), thường tên `origin`. Bạn làm việc offline được hoàn toàn; chỉ cần mạng khi `push` (đẩy lên) hoặc `pull`/`fetch` (kéo về).

### 3.3. Git ≠ GitHub

- **Git**: phần mềm quản lý phiên bản, chạy trên máy bạn.
- **GitHub**: dịch vụ lưu repo Git trên mạng, thêm các tính năng cộng tác (Pull Request, Issues, GitHub Actions).

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Ba vùng của Git

| Vùng | Tiếng Việt | Là gì | Ví von |
|---|---|---|---|
| **Working directory** | Thư mục làm việc | Các file bạn đang thấy và sửa | Bàn làm việc |
| **Staging area** (index) | Vùng chuẩn bị | Danh sách thay đổi sẽ vào commit **tiếp theo** | Hộp đồ đã chọn để gửi đi |
| **Repository** (`.git/`) | Kho lịch sử | Tất cả commit đã tạo | Kho lưu trữ đã niêm phong |

Vì sao cần staging area? Vì bạn có thể sửa 5 file nhưng chỉ muốn commit 2 file liên quan đến cùng một việc. Staging cho phép tạo **commit nhỏ, đúng một mục đích** — dễ review, dễ rollback.

Trạng thái một file:

- **Untracked**: file mới, Git chưa theo dõi.
- **Modified**: đã sửa nhưng chưa `add`.
- **Staged**: đã `add`, chờ commit.
- **Committed**: đã nằm an toàn trong repository.

### 4.2. 🟥 Cấu hình Git: ba cấp

| Cấp | Lưu ở đâu | Áp dụng cho |
|---|---|---|
| `--system` | `/etc/gitconfig` | Mọi user trên máy |
| `--global` | `~/.gitconfig` | Mọi repo của user hiện tại |
| `--local` (mặc định) | `<repo>/.git/config` | Chỉ repo hiện tại |

Cấp hẹp hơn ghi đè cấp rộng hơn.

> ⚠️ **Git trên Windows và Git trong WSL là hai chương trình riêng, cấu hình riêng.** Nếu IntelliJ trên Windows đã cấu hình Git, điều đó **không** áp dụng cho Git trong WSL. Bài này cấu hình Git trong WSL.

### 4.3. 🟥 CRLF và LF — nối với bài 01

Windows xuống dòng bằng 2 ký tự `\r\n` (CRLF), Linux chỉ dùng `\n` (LF). Script có CRLF sẽ lỗi `bad interpreter` trên Linux (xem [bài 01, mục 11](../01-LINUX/01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp)).

Thiết lập `core.autocrlf input` trong WSL nghĩa là: khi commit, Git **đổi CRLF thành LF**; khi checkout, Git **không đổi gì**. Kết quả: repo luôn lưu LF.

🟨 Cách chắc chắn hơn, áp dụng cho mọi người trong nhóm bất kể họ cấu hình gì: thêm file `.gitattributes` vào repo:

```text
* text=auto eol=lf
*.bat text eol=crlf
```

### 4.4. 🟥 SSH key — mức tối thiểu để dùng được

GitHub cần xác minh "bạn là bạn" khi `push`. Cách được khuyến nghị là **SSH key** — một cặp khóa:

- **Private key** (khóa bí mật, `~/.ssh/id_ed25519`): ở lại trên máy bạn, **không bao giờ chia sẻ**.
- **Public key** (khóa công khai, `~/.ssh/id_ed25519.pub`): đưa cho GitHub.

Bài này chỉ hướng dẫn tạo và dùng. Vì sao cặp khóa này an toàn, `ssh-agent` là gì, `~/.ssh/config` dùng thế nào — học ở [bài 05: Package management & SSH](../01-LINUX/05-packages-ssh.md).

### 4.5. 🟥 `.gitignore` — những thứ không được vào Git

File `.gitignore` liệt kê mẫu tên file Git sẽ bỏ qua. Ba nhóm luôn phải có:

1. **Sản phẩm build**: `target/` (Maven), `build/` (Gradle), `*.class`, `*.jar`.
2. **File của IDE/hệ điều hành**: `.idea/`, `*.iml`, `.vscode/`, `.DS_Store`, `Thumbs.db`.
3. **Secret và cấu hình cục bộ**: `.env`, `*.pem`, `*.key`, `application-local.yml`.

> `.gitignore` chỉ có tác dụng với file **chưa được theo dõi**. File đã commit rồi thì thêm vào `.gitignore` không làm nó biến mất khỏi lịch sử.

GitHub duy trì bộ mẫu `.gitignore` cho nhiều ngôn ngữ: [github/gitignore](https://github.com/github/gitignore) (có `Java.gitignore`, `Maven.gitignore`).

### 4.6. 🟥 Commit message tốt

Commit message được đọc **nhiều hơn rất nhiều** so với lúc viết — nhất là khi đang xử lý sự cố. Quy ước **Conventional Commits** (phiên bản 1.0.0) được nhiều nhóm dùng:

```text
<type>[(scope)]: <mô tả ngắn>

[thân — giải thích VÌ SAO, không chỉ CÁI GÌ]
```

| Type | Dùng khi |
|---|---|
| `feat` | Thêm tính năng |
| `fix` | Sửa lỗi |
| `docs` | Chỉ sửa tài liệu |
| `chore` | Việc lặt vặt: cấu hình, dọn dẹp, cập nhật dependency |
| `ci` | 🟨 Sửa pipeline CI/CD |
| `refactor` | 🟨 Đổi cấu trúc code, không đổi hành vi |

Ví dụ tốt: `fix(nginx): increase proxy_read_timeout to 60s for report export`
Ví dụ tệ: `update`, `fix bug`, `asdf`.

### 4.7. 🟥 Secret trong Git: coi như đã lộ

Nếu bạn lỡ commit mật khẩu, access key, token… và **đã push**:

1. **Việc đầu tiên: thu hồi/xoay vòng (revoke/rotate) secret** — đổi mật khẩu, vô hiệu hóa key, tạo key mới. Đây cũng là bước đầu tiên GitHub khuyến nghị.
2. Sau đó mới tính đến chuyện xóa khỏi lịch sử. Chỉ tạo commit mới xóa file **không đủ** — secret vẫn nằm trong các commit cũ, và có thể đã bị bot quét repo public thu thập trong vài phút.

Lý do: bạn không kiểm soát được ai đã clone, fork hoặc cache repo. Coi secret đã lộ và vô hiệu hóa nó là cách duy nhất chắc chắn.

---

## 5. Ví dụ thực tế

**Tình huống:** Sau khi deploy, ứng dụng trả lỗi 502. Kỹ sư trực ca làm:

```bash
git log --oneline -5
```

```text
9f3e2a1 (HEAD -> main, origin/main) fix(nginx): change upstream port to 8081
4c7d0b8 feat(api): add task filter by status
...
```

Commit mới nhất đổi port upstream của Nginx sang `8081`, trong khi app vẫn nghe ở `8080` → nguyên nhân lỗi 502. Commit message rõ ràng giúp tìm ra trong vài giây. Hãy tưởng tượng nếu message là `update`.

---

## 6. Sơ đồ luồng hoạt động

```text
  WORKING DIRECTORY         STAGING AREA            LOCAL REPOSITORY          REMOTE (GitHub)
  (file đang sửa)           (chuẩn bị commit)       (.git — lịch sử)          (origin)
        │                         │                        │                        │
        │──── git add ───────────►│                        │                        │
        │                         │──── git commit ───────►│                        │
        │                         │                        │──── git push ─────────►│
        │                         │                        │◄─── git fetch ─────────│
        │◄──────────── git pull (= fetch + merge) ─────────┴────────────────────────│
        │                         │                        │                        │
        │◄─ git restore <file> ───│  (bỏ thay đổi chưa add, lấy lại bản đã stage)   │
        │                         │◄─ git restore --staged <file> (bỏ khỏi staging) │
        │                                                                           │
  git diff: working ↔ staging          git diff --staged: staging ↔ commit cuối
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `git config` | Cấu hình Git | 🟥 |
| `ssh-keygen`, `ssh -T git@github.com` | Tạo SSH key, kiểm tra kết nối GitHub | 🟥 |
| `git init`, `git clone` | Tạo repo mới / sao chép repo có sẵn | 🟥 |
| `git status` | Xem trạng thái các vùng | 🟥 |
| `git add` | Đưa thay đổi vào staging | 🟥 |
| `git commit` | Tạo commit | 🟥 |
| `git push`, `git pull` | Đẩy lên / kéo về remote | 🟥 |
| `git log --oneline --graph` | Xem lịch sử | 🟥 |
| `git diff`, `git diff --staged` | Xem thay đổi | 🟥 |
| `git restore`, `git restore --staged` | Bỏ thay đổi / bỏ khỏi staging | 🟥 |
| `git remote -v` | Xem remote | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

### `git config` — cấu hình trong WSL

```bash
git config --global user.name "Phuong Nguyen"
git config --global user.email "you@example.com"     # dùng email gắn với tài khoản GitHub của bạn
git config --global init.defaultBranch main
git config --global core.autocrlf input
git config --global core.editor nano
git config --global --list
```

```text
user.name=Phuong Nguyen
user.email=you@example.com
init.defaultbranch=main
core.autocrlf=input
core.editor=nano
```

| Thiết lập | Ý nghĩa |
|---|---|
| `user.name`, `user.email` | Ghi vào **mọi commit** — xác định tác giả. Email phải khớp với email trên GitHub để commit được gắn với tài khoản |
| `init.defaultBranch main` | Repo mới tạo bằng `git init` có nhánh đầu tiên tên `main` (khớp với GitHub) |
| `core.autocrlf input` | Đổi CRLF → LF khi commit (xem mục 4.3) |
| `core.editor nano` | Editor mở ra khi Git cần bạn nhập nội dung (ví dụ `git commit` không có `-m`). `nano` dễ dùng hơn `vim` cho người mới |

> 🟨 Muốn ẩn email thật trên commit public: GitHub cung cấp địa chỉ dạng `<id>+<username>@users.noreply.github.com` trong phần cài đặt Email của tài khoản.

### `ssh-keygen` — tạo SSH key

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

```text
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/phuong/.ssh/id_ed25519):
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /home/phuong/.ssh/id_ed25519
Your public key has been saved in /home/phuong/.ssh/id_ed25519.pub
```

| Tham số | Ý nghĩa |
|---|---|
| `-t ed25519` | Loại khóa. Ed25519 là loại GitHub khuyến nghị: ngắn, nhanh, an toàn |
| `-C "..."` | Comment (chú thích) gắn vào khóa để nhận biết — không ảnh hưởng bảo mật |

- **Enter file**: nhấn Enter để dùng đường dẫn mặc định.
- **Passphrase** (mật khẩu bảo vệ khóa): nên đặt. Nếu ai lấy được file private key, họ vẫn cần passphrase.

> ⚠️ Nếu đã có file `~/.ssh/id_ed25519`, `ssh-keygen` sẽ hỏi có ghi đè không. **Trả lời `n`** trừ khi bạn chắc chắn — ghi đè sẽ làm mất khóa cũ và mọi nơi đang dùng nó sẽ không đăng nhập được nữa. Kiểm tra trước bằng `ls -l ~/.ssh/`.

Thêm public key vào GitHub:

```bash
cat ~/.ssh/id_ed25519.pub
```

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@example.com
```

Copy **toàn bộ một dòng** này → GitHub → ảnh đại diện → **Settings** → **SSH and GPG keys** → **New SSH key** → dán vào ô *Key*, đặt *Title* như `LEGION-WSL`, loại *Authentication Key* → **Add SSH key**.

> Chỉ copy file **`.pub`**. File không có đuôi `.pub` là private key — không bao giờ dán ở đâu cả.

### `ssh -T git@github.com` — kiểm tra kết nối

```bash
ssh -T git@github.com
```

```text
The authenticity of host 'github.com (20.205.243.166)' can't be established.
ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Hi phuong-dev! You've successfully authenticated, but GitHub does not provide shell access.
```

- Lần đầu SSH hỏi xác nhận **fingerprint** (dấu vân tay) của server. Fingerprint chính thức của GitHub được công bố tại [GitHub's SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints) — đối chiếu trước khi gõ `yes`. Ý nghĩa sâu hơn học ở bài 05.
- Dòng `Hi <username>!` = thành công. Lệnh này trả exit code `1` dù thành công — vì GitHub không cấp shell. Đây là bình thường.
- `-T`: không yêu cầu cấp terminal (vì GitHub không cho đăng nhập shell).

### `git status`

```bash
git status
```

```text
On branch main
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        new file:   week01/lab01-answers.md

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   README.md

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        notes.tmp
```

Đọc từ trên xuống: **staged** (sẽ vào commit) → **modified chưa stage** → **untracked**. Git còn gợi ý lệnh ngay trong ngoặc — hãy đọc chúng. `git status -s` cho bản rút gọn.

### `git add`

```bash
git add week01/lab01-answers.md     # một file
git add week01/                     # cả thư mục
git add -p                          # 🟨 chọn từng đoạn thay đổi (patch) — rất hữu ích để commit nhỏ
```

> Tránh thói quen `git add .` mù quáng — đó là cách phổ biến nhất để vô tình commit file `.env`. Luôn chạy `git status` trước khi commit.

### `git commit`

```bash
git commit -m "docs(linux): add lab 01 answers"
```

```text
[main 3f9a1c2] docs(linux): add lab 01 answers
 1 file changed, 42 insertions(+)
 create mode 100644 week01/lab01-answers.md
```

`3f9a1c2` là hash rút gọn của commit vừa tạo. Không có `-m`, Git mở editor (`nano`) để bạn viết message nhiều dòng.

### `git log`

```bash
git log --oneline --graph --decorate -10
```

```text
* 3f9a1c2 (HEAD -> main) docs(linux): add lab 01 answers
* a71be04 (origin/main) chore: add .gitignore
* 0d2c9e1 docs: init devops-journey README
```

| Tham số | Ý nghĩa |
|---|---|
| `--oneline` | Mỗi commit một dòng |
| `--graph` | Vẽ nhánh dạng cây (thấy rõ khi có nhiều nhánh — tuần 6) |
| `--decorate` | Hiện tên nhánh/tag (`HEAD`, `origin/main`) |
| `-10` | Chỉ 10 commit gần nhất |

`HEAD -> main` = bạn đang ở nhánh `main`. `origin/main` ở commit cũ hơn = commit `3f9a1c2` **chưa được push**.

### `git diff` và `git diff --staged`

```bash
git diff              # working directory so với staging: những gì CHƯA add
git diff --staged     # staging so với commit cuối: những gì SẼ vào commit
```

```text
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1,3 +1,4 @@
 # devops-journey
+Nhật ký học DevOps 24 tuần.
```

Dòng `+` là thêm, `-` là xóa. Thói quen tốt: chạy `git diff --staged` ngay trước `git commit`.

### `git restore`

```bash
git restore --staged README.md   # bỏ README.md khỏi staging, GIỮ thay đổi trong file
git restore README.md            # ⚠️ BỎ thay đổi chưa add trong file — không lấy lại được
```

> ⚠️ `git restore <file>` xóa vĩnh viễn những thay đổi **chưa từng được add hoặc commit**. Git không có bản sao nào của chúng.

### `git push` và `git remote`

```bash
git remote add origin git@github.com:<username>/devops-journey.git
git remote -v
git push -u origin main
```

```text
origin  git@github.com:<username>/devops-journey.git (fetch)
origin  git@github.com:<username>/devops-journey.git (push)
...
branch 'main' set up to track 'origin/main'.
```

- URL dạng `git@github.com:...` = dùng **SSH**. URL `https://github.com/...` = dùng HTTPS (cần token, không dùng SSH key).
- `-u` (set upstream): ghi nhớ `main` ở máy tương ứng `origin/main`. Từ lần sau chỉ cần `git push`.

---

## 9. Bài thực hành từng bước

**Lab: Thiết lập Git trong WSL và tạo repo `devops-journey`** · `[WSL]` + trình duyệt · ~60 phút

Repo này là **nhật ký học tập** của bạn trong 24 tuần: câu trả lời lab, ghi chú, nhật ký debug. Đây cũng là bằng chứng quá trình học khi đi phỏng vấn.

### Bước 1 — Kiểm tra Git và cấu hình hiện có

```bash
git --version
git config --global --list
ls -l ~/.ssh/ 2>/dev/null || echo "Chưa có thư mục ~/.ssh"
```

❓ Git trong WSL đã có `user.name`/`user.email` chưa? Đã có SSH key chưa?

### Bước 2 — Cấu hình Git

Chạy các lệnh `git config --global` ở [mục 8](#git-config--cấu-hình-trong-wsl), thay tên và email của bạn.

### Bước 3 — Tạo SSH key và thêm vào GitHub

Chỉ tạo key mới nếu Bước 1 cho thấy chưa có `~/.ssh/id_ed25519`. Làm theo [mục 8](#ssh-keygen--tạo-ssh-key), sau đó kiểm tra bằng `ssh -T git@github.com`.

### Bước 4 — Tạo repo trên GitHub

Trên GitHub: **New repository** → tên `devops-journey` → Public hoặc Private tùy bạn → **không** tick "Add a README" (ta sẽ tạo từ máy) → **Create repository**.

### Bước 5 — Tạo repo ở máy

```bash
mkdir -p ~/devops-journey && cd ~/devops-journey
git init
mkdir -p week01
```

Tạo `README.md`:

```bash
cat > README.md <<'EOF'
# devops-journey

Nhật ký học DevOps / Cloud Engineer — 24 tuần.

## Cấu trúc
- `weekNN/` — câu trả lời lab, ghi chú theo tuần
- `troubleshooting-journal.md` — nhật ký debug: mọi lỗi đã gặp và cách xử lý
EOF
```

Tạo `troubleshooting-journal.md` theo [mẫu nhật ký debug](../00-ROADMAP/templates/troubleshooting-journal-template.md).

Tạo `.gitignore`:

```bash
cat > .gitignore <<'EOF'
# Secret & cấu hình cục bộ
.env
*.pem
*.key

# IDE / hệ điều hành
.idea/
*.iml
.vscode/
Thumbs.db

# File tạm
*.tmp
*.log
EOF
```

### Bước 6 — Commit đầu tiên và push

```bash
git status
git add README.md .gitignore troubleshooting-journal.md
git diff --staged --stat
git commit -m "docs: init devops-journey"
git remote add origin git@github.com:<username>/devops-journey.git
git push -u origin main
```

### Bước 7 — Luyện staging area

```bash
echo "Tuần 1: Linux filesystem + Git" >> README.md
echo "ghi chú tạm" > notes.tmp
echo "SECRET=abc123" > .env
git status
```

❓ `notes.tmp` và `.env` có xuất hiện trong `git status` không? Vì sao?

```bash
git add README.md
echo "Dòng thêm sau khi add" >> README.md
git status
git diff
git diff --staged
```

❓ Vì sao `README.md` xuất hiện **cả** ở "Changes to be committed" **và** "Changes not staged"? `git diff` và `git diff --staged` hiển thị dòng nào?

```bash
git restore --staged README.md
git status
git add README.md
git commit -m "docs: add week 1 progress"
git push
rm notes.tmp .env
```

### Bước 8 — Đưa câu trả lời lab 01 vào repo

Làm Bước 8 của [lab bài 01](../01-LINUX/01-linux-architecture-filesystem.md#9-bài-thực-hành-từng-bước). Sau đó mở repo trên GitHub, kiểm tra file đã lên và tác giả commit hiển thị đúng tài khoản của bạn.

---

## 10. Kết quả mong đợi

- `ssh -T git@github.com` in ra `Hi <username>! You've successfully authenticated...`.
- Repo `devops-journey` trên GitHub có `README.md`, `.gitignore`, `troubleshooting-journal.md`, `week01/`.
- `git log --oneline` có ít nhất 3 commit với message theo Conventional Commits.
- Bước 7: `notes.tmp` và `.env` **không** xuất hiện trong `git status` vì khớp mẫu trong `.gitignore`. `README.md` xuất hiện ở cả hai mục vì **staging lưu nội dung file tại thời điểm `git add`** — phần sửa sau đó là một thay đổi mới, chưa stage. `git diff` chỉ hiện "Dòng thêm sau khi add"; `git diff --staged` hiện dòng "Tuần 1...".
- Trên GitHub, commit hiển thị avatar tài khoản của bạn (email khớp).

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `git@github.com: Permission denied (publickey).` | Chưa thêm public key lên GitHub; dùng nhầm key; chạy git bằng `sudo` (dùng key của root) | Không dùng `sudo` với git. Chạy `ssh -vT git@github.com` xem key nào được thử. Kiểm tra key đã có trên GitHub (so fingerprint bằng `ssh-add -l -E sha256` hoặc `ssh-keygen -lf ~/.ssh/id_ed25519.pub`) |
| `! [rejected] main -> main (fetch first)` / `non-fast-forward` | Remote có commit mà máy bạn chưa có (ví dụ bạn sửa file trên web GitHub, hoặc tạo repo kèm README) | `git pull` rồi `git push`. ⚠️ **Không** dùng `git push --force` trên nhánh dùng chung — nó ghi đè lịch sử của người khác |
| `warning: in the working copy of 'x', CRLF will be replaced by LF` | File có CRLF (thường do sửa trên Windows), `autocrlf input` đang chuyển đổi | Thông báo này vô hại — Git đang làm đúng việc. Đổi editor sang LF để hết hẳn |
| Commit trên GitHub hiện tên lạ / không có avatar | `user.email` trong WSL không khớp email trên GitHub | Sửa `git config --global user.email`. Commit cũ giữ nguyên tác giả cũ (sửa commit cũ là chủ đề nâng cao) |
| Lỡ commit `.env` | Thiếu `.gitignore` hoặc dùng `git add .` | Chưa push: `git rm --cached .env`, thêm vào `.gitignore`, sửa commit. **Đã push: rotate secret ngay** (mục 4.7) |
| `fatal: not a git repository` | Chạy lệnh git ngoài thư mục repo | `pwd`, `cd` vào đúng repo |
| `src refspec main does not match any` | Chưa có commit nào, hoặc nhánh tên `master` | `git status` xem tên nhánh; tạo commit trước khi push |
| Mở editor `vim` không biết thoát | `core.editor` chưa đặt | Gõ `Esc` rồi `:q!` Enter. Đặt `core.editor nano` |

---

## 12. Đọc thông báo lỗi và xử lý

Thông báo của Git dài, nhưng thường **đã chứa sẵn gợi ý sửa**. Ví dụ:

```text
To github.com:phuong-dev/devops-journey.git
 ! [rejected]        main -> main (fetch first)
error: failed to push some refs to 'github.com:phuong-dev/devops-journey.git'
hint: Updates were rejected because the remote contains work that you do
hint: not have locally. This is usually caused by another repository pushing
hint: to the same ref. You may want to first integrate the remote changes
hint: (e.g., 'git pull ...') before pushing again.
```

Đọc theo thứ tự:

1. Dòng `!` → **cái gì** bị từ chối: nhánh `main` local → `main` remote.
2. Trong ngoặc → **lý do ngắn**: `fetch first` (phải lấy về trước).
3. Các dòng `hint:` → **giải thích và cách sửa**.

Với lỗi SSH, thêm `-v` (verbose — chi tiết) để xem từng bước:

```bash
ssh -vT git@github.com 2>&1 | grep -E "Offering|Authenticated|denied"
```

```text
debug1: Offering public key: /home/phuong/.ssh/id_ed25519 ED25519 SHA256:...
debug1: Authenticated to github.com ([20.205.243.166]:22) using "publickey".
```

Dòng `Offering public key` cho biết key nào đang được thử — nếu không có dòng này, SSH không tìm thấy key của bạn.

Ghi mọi lỗi Git gặp phải vào `troubleshooting-journal.md`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Ba vùng của Git là gì? Lệnh nào chuyển thay đổi từ vùng này sang vùng kia?
2. Vì sao Git cần staging area thay vì commit thẳng mọi thay đổi?
3. Repo trên máy bạn và repo trên GitHub, cái nào là "bản chính"? Giải thích theo tính phân tán của Git.
4. Cấu hình Git của IntelliJ trên Windows có áp dụng cho Git trong WSL không? Vì sao?
5. `core.autocrlf input` làm gì? Nó giải quyết lỗi nào ở bài 01?
6. Private key và public key, cái nào đưa lên GitHub? Nếu lộ cái còn lại thì sao?
7. `git diff` và `git diff --staged` khác nhau thế nào?
8. `git restore --staged file` và `git restore file` khác nhau thế nào? Lệnh nào có thể làm mất dữ liệu?
9. Vì sao thêm `.env` vào `.gitignore` sau khi đã commit nó không giải quyết được vấn đề?
10. Bạn lỡ push một AWS access key lên repo public. Liệt kê các bước theo đúng thứ tự ưu tiên.
11. Viết lại commit message `fixed stuff` cho tình huống: sửa lỗi Nginx trả 502 do sai port upstream.

---

## 14. Bài tập tự làm

> Lời giải ngắn ở cuối mục này, trong các khối thu gọn. Tự làm trước, ghi câu trả lời vào `week01/git-exercises.md`, rồi mới mở.

**Bài 1 — Ba vùng.** Tạo file `a.txt` với nội dung `v1`, commit. Sửa thành `v2`, `git add`. Sửa thành `v3`, không add. Dự đoán trước, rồi kiểm tra: (a) `git diff` hiện gì, (b) `git diff --staged` hiện gì, (c) nếu `git commit` ngay bây giờ thì commit chứa `v2` hay `v3`, (d) sau đó `git restore a.txt` thì file còn nội dung gì?

**Bài 2 — `.gitignore`.** Viết `.gitignore` cho một dự án Spring Boot dùng Maven và IntelliJ, có file `.env` và thư mục `logs/`. Kiểm tra bằng `git status` và `git check-ignore -v <file>` (đọc `git help check-ignore`).

**Bài 3 — Điều tra lỗi push.** Trên web GitHub, sửa trực tiếp `README.md` của `devops-journey` và commit. Ở máy, sửa một file khác, commit, rồi `git push`. Đọc lỗi theo [mục 12](#12-đọc-thông-báo-lỗi-và-xử-lý), xử lý mà **không dùng `--force`**. Ghi một mục vào `troubleshooting-journal.md`.

**Bài 4 — Commit message.** Viết commit message theo Conventional Commits cho 4 tình huống: (a) thêm script healthcheck, (b) sửa lỗi script backup không xóa file cũ, (c) cập nhật README, (d) thêm workflow GitHub Actions chạy test.

**Bài 5 — Sự cố secret (chỉ suy nghĩ, không làm thật với secret thật).** Viết một runbook ngắn (5–8 bước) cho tình huống: phát hiện file `.env` chứa mật khẩu database production đã nằm trên repo public 2 ngày.

<details>
<summary>Lời giải Bài 1</summary>

(a) `git diff`: `-v2` / `+v3` (working so với staging). (b) `git diff --staged`: `-v1` / `+v2` (staging so với commit cuối). (c) Commit chứa **`v2`** — commit lấy nội dung từ staging, không phải từ file. (d) Sau khi commit, staging = `v2`; `git restore a.txt` lấy nội dung từ staging nên file trở về **`v2`**, `v3` mất vĩnh viễn.
</details>

<details>
<summary>Lời giải Bài 2</summary>

```text
target/
*.class
*.jar
.idea/
*.iml
.env
logs/
*.log
```

`git check-ignore -v .env` in ra dòng nào trong `.gitignore` đã khớp, ví dụ `.gitignore:6:.env	.env`. Lưu ý: nếu muốn commit Maven Wrapper thì cần ngoại lệ `!.mvn/wrapper/maven-wrapper.jar` vì nó bị `*.jar` chặn.
</details>

<details>
<summary>Lời giải Bài 3</summary>

Lỗi `! [rejected] main -> main (fetch first)`. Cách xử lý: `git pull` (Git merge commit trên web với commit ở máy; nếu mở editor để nhập message merge thì lưu lại), sau đó `git push`. Nếu hai bên sửa cùng một dòng sẽ có conflict — học ở tuần 6. Nhật ký cần có: triệu chứng (thông báo rejected), nguyên nhân (remote có commit mới tạo trên web), cách sửa (pull rồi push), phòng ngừa (pull trước khi bắt đầu làm việc).
</details>

<details>
<summary>Lời giải Bài 4</summary>

(a) `feat(scripts): add healthcheck script for disk, memory and app status`
(b) `fix(scripts): delete backups older than 7 days in backup.sh`
(c) `docs: update README with setup instructions`
(d) `ci: add GitHub Actions workflow to run tests on pull requests`
</details>

<details>
<summary>Lời giải Bài 5</summary>

1. **Đổi mật khẩu database ngay** (rotate) và cập nhật cho ứng dụng — đây là bước quan trọng nhất.
2. Kiểm tra log truy cập database trong 2 ngày qua để tìm đăng nhập bất thường.
3. Thông báo cho trưởng nhóm/bộ phận bảo mật theo quy trình công ty.
4. Xóa file khỏi repo, thêm `.env` vào `.gitignore`.
5. (Cân nhắc) xóa khỏi lịch sử theo hướng dẫn "Removing sensitive data from a repository" của GitHub — phối hợp với cả nhóm vì việc này viết lại lịch sử.
6. Bật cơ chế phòng ngừa: secret scanning, pre-commit hook quét secret (Module 10).
7. Viết postmortem: nguyên nhân gốc, vì sao không phát hiện sớm, cách phòng ngừa.
</details>

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ lại sơ đồ mục 6 mà không nhìn tài liệu, giải thích từng mũi tên.
- [ ] Làm đúng Bài tập 1 **trước khi** chạy lệnh để kiểm tra.
- [ ] Repo `devops-journey` đã có trên GitHub, push bằng SSH, tác giả commit đúng.
- [ ] Không bao giờ dùng `git add .` mà không `git status` trước.
- [ ] Giải thích được vì sao lộ secret thì phải rotate trước, xóa lịch sử sau.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Pro Git — 2.2 Recording Changes to the Repository](https://git-scm.com/book/en/v2/Git-Basics-Recording-Changes-to-the-Repository) | status, add, diff, commit, `.gitignore` | 2026-10-31 |
| [Pro Git (toàn bộ sách)](https://git-scm.com/book/en/v2) | Đọc chương 1–2 để ôn | 2026-10-31 |
| [GitHub Docs — Generating a new SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) | `ssh-keygen -t ed25519` | 2026-10-31 |
| [GitHub Docs — Adding a new SSH key to your GitHub account](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account) | Thêm public key | 2026-10-31 |
| [GitHub Docs — Testing your SSH connection](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection) | `ssh -T git@github.com` | 2026-10-31 |
| [GitHub Docs — GitHub's SSH key fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints) | Đối chiếu fingerprint khi SSH lần đầu | 2026-10-31 |
| [GitHub Docs — Error: Permission denied (publickey)](https://docs.github.com/en/authentication/troubleshooting-ssh/error-permission-denied-publickey) | Xử lý lỗi SSH | 2026-10-31 |
| [GitHub Docs — Removing sensitive data from a repository](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) | Xử lý secret bị lộ | 2026-10-31 |
| [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) | Quy ước commit message | 2026-10-31 |
| [github/gitignore](https://github.com/github/gitignore) | Mẫu `.gitignore` (Java, Maven…) | 2026-10-31 |
