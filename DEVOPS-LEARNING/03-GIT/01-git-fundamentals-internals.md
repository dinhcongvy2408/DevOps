# 01. Git fundamentals & internals

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Ôn tập Git nhanh](00-git-quick-review.md), [Linux 01 — Filesystem](../01-LINUX/01-linux-architecture-filesystem.md)
> Môi trường: `[WSL]` Ubuntu 24.04, Git đã cấu hình ở bài ôn tập

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
12. [Đọc thông báo lỗi và xử lý](#12-đọc-thông-báo-lỗi-và-xử-lý)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Giải thích Git lưu dữ liệu thế nào: **snapshot** (ảnh chụp), không phải danh sách thay đổi.
- Kể tên và đọc được 4 loại object: **blob, tree, commit, tag** bằng `git cat-file`.
- Chứng minh bằng lệnh rằng **branch chỉ là một file chứa mã SHA** và **HEAD chỉ là con trỏ tới branch**.
- Hiểu trạng thái **detached HEAD** và thoát ra an toàn.
- Dùng đúng `reset --soft / --mixed / --hard` và `revert`; biết lệnh nào an toàn trên nhánh dùng chung.
- Cứu một commit "đã mất" bằng `git reflog`.
- Tìm thông tin trong lịch sử bằng `git log` nâng cao, `git show`, `git blame`; cất thay đổi dở dang bằng `git stash`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| "Em lỡ `reset --hard`, mất hết commit sáng nay rồi!" | Commit chưa mất ngay — `git reflog` cứu được |
| "Bản deploy tối qua gây lỗi, cần gỡ commit đó khỏi `main` ngay" | Trên nhánh chung dùng `git revert`, **không** dùng `reset` + `push --force` |
| "Image trên production được build từ commit nào?" | Mỗi image gắn tag là **commit SHA** — phải hiểu SHA là gì |
| "Ai đổi dòng cấu hình timeout này, vì sao?" | `git blame` + `git show` |
| "Từ khi nào biến `DB_HOST` biến mất khỏi file cấu hình?" | `git log -S DB_HOST` |
| "Đang sửa dở thì có sự cố, phải chuyển nhánh khẩn cấp" | `git stash` |

Hiểu bên trong Git giúp bạn **bình tĩnh** khi có sự cố: bạn biết dữ liệu nằm đâu và cái gì thực sự bị mất.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Snapshot, không phải diff

Nhiều hệ thống cũ lưu "file A ban đầu + thay đổi lần 1 + thay đổi lần 2…". Git thì khác: **mỗi commit là một ảnh chụp toàn bộ dự án** tại thời điểm đó. File nào không đổi thì Git không chép lại mà trỏ tới bản đã có — nên vẫn tiết kiệm dung lượng.

Khi bạn chạy `git diff`, Git **tính** sự khác biệt giữa hai snapshot ngay lúc đó, chứ không đọc ra một "bản diff" đã lưu.

### 3.2. Hàm băm (hash) và SHA

**Hash** (hàm băm) biến một nội dung bất kỳ thành một chuỗi cố định độ dài, ví dụ:

```text
"hello"   →  ce013625030ba8dba906f756967f9e9ca394464a
"hello!"  →  hoàn toàn khác
```

Tính chất quan trọng: **cùng nội dung → luôn cùng hash; đổi 1 ký tự → hash khác hẳn**. Git dùng **SHA-1** (40 ký tự hex) làm "tên" của mọi object. Vì vậy người ta nói Git là một **content-addressable filesystem** (hệ thống file đánh địa chỉ theo nội dung): muốn lấy dữ liệu, bạn hỏi bằng hash của nó.

> 🟦 Git đang dần chuyển sang SHA-256 an toàn hơn, nhưng các repo thông thường hiện nay vẫn dùng SHA-1. Bạn không cần làm gì khác.

Hệ quả thực tế: **commit SHA là định danh duy nhất, không thể giả mạo** của một trạng thái code. Đó là lý do DevOps gắn tag Docker image bằng commit SHA.

### 3.3. Ba "cây" bạn đã biết từ tuần 1

Bài ôn tập đã giới thiệu working directory, staging area (index) và repository. Ở bài này chúng có tên chính xác hơn — **ba cây** (three trees) mà `git reset` thao tác:

| Cây | Là gì |
|---|---|
| **HEAD** | Snapshot của commit hiện tại — "lần chụp gần nhất" |
| **Index** (staging area) | Snapshot **dự kiến** cho commit tiếp theo |
| **Working directory** | Các file bạn đang thấy và sửa |

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Bốn loại object

Mọi thứ Git lưu nằm trong `.git/objects/` dưới dạng object, được nén bằng zlib và đặt tên bằng SHA:

| Object | Chứa gì | Tương đương |
|---|---|---|
| **blob** | **Chỉ nội dung** một file — không có tên file, không có quyền | Nội dung file |
| **tree** | Danh sách: quyền + loại + SHA + **tên** của từng file/thư mục con | Một thư mục |
| **commit** | SHA của tree gốc + SHA commit cha + tác giả + thời gian + lời nhắn | Một lần chụp |
| **tag** (annotated) | Trỏ tới một commit + người gắn tag + lời nhắn | Nhãn phiên bản (bài 05) |

Vì blob không chứa tên file, **hai file khác tên nhưng cùng nội dung chỉ lưu một blob**. Đổi tên file không tạo blob mới, chỉ tạo tree mới.

Mỗi commit trỏ tới commit **cha** (parent). Chuỗi commit nối nhau qua parent chính là **lịch sử**. Commit đầu tiên không có cha; merge commit có hai cha (bài 02).

### 4.2. 🟥 Refs, branch và HEAD

Nhớ SHA 40 ký tự là không thể, nên Git có **ref** (tham chiếu) — tên dễ nhớ trỏ tới một SHA:

- **Branch** (nhánh): file `.git/refs/heads/<tên-nhánh>` chứa **đúng một SHA** của commit cuối cùng trên nhánh, cộng ký tự xuống dòng — tổng **41 byte**. Không hơn.
- **HEAD**: file `.git/HEAD` cho biết bạn đang đứng ở đâu. Bình thường nó chứa `ref: refs/heads/main` — tức "tôi đang ở nhánh main".

Khi bạn commit trên `main`:

1. Git tạo blob/tree/commit mới, commit mới có cha là commit cũ.
2. Git ghi SHA commit mới vào `.git/refs/heads/main`.
3. HEAD vẫn trỏ tới `main`, nên tự động "đi theo".

**Tạo branch mới = tạo một file 41 byte.** Đó là lý do tạo nhánh trong Git gần như tức thì, và vì sao Git khuyến khích dùng nhiều nhánh.

> 🟨 Sau khi Git dọn dẹp (`git gc`) hoặc với remote branch, ref có thể được gom vào file `.git/packed-refs` thay vì nằm thành từng file. Ý nghĩa không đổi: tên → SHA.

### 4.3. 🟥 Detached HEAD

Nếu bạn checkout thẳng một commit (hoặc một tag), HEAD chứa **SHA** thay vì tên nhánh:

```text
.git/HEAD:  a1b2c3d...      ← không còn "ref: refs/heads/..."
```

Đây là **detached HEAD** (HEAD bị tách rời). Bạn vẫn xem code, chạy thử, thậm chí commit được — nhưng commit mới **không thuộc nhánh nào**. Khi bạn chuyển sang nhánh khác, các commit đó chỉ còn được tham chiếu bởi reflog và sẽ bị dọn sau một thời gian.

Cách an toàn: nếu muốn giữ những gì vừa làm, tạo nhánh ngay tại chỗ: `git switch -c ten-nhanh-moi`.

Khi nào DevOps gặp detached HEAD? Rất thường: **pipeline CI** và lệnh `git checkout v1.2.0` để build lại đúng một phiên bản đều đưa repo vào trạng thái này. Đó là bình thường.

### 4.4. 🟥 `reset` — di chuyển nhánh và đồng bộ ba cây

`git reset <commit>` làm tối đa 3 bước, dừng ở bước bạn chọn:

| Bước | Việc làm | `--soft` | `--mixed` (mặc định) | `--hard` ⚠️ |
|---|---|---|---|---|
| 1 | Di chuyển **nhánh hiện tại** về `<commit>` | ✅ | ✅ | ✅ |
| 2 | Làm **index** giống `<commit>` | — | ✅ | ✅ |
| 3 | Làm **working directory** giống index | — | — | ✅ |
| Kết quả | | Thay đổi vẫn **đã stage** | Thay đổi **chưa stage**, file vẫn còn | Thay đổi **chưa commit bị xóa** |

Ví dụ dễ nhớ với `git reset HEAD~1` (quay về commit trước đó):

- `--soft`: "bỏ commit, giữ nguyên mọi thứ đã add" → dùng để **gộp/viết lại commit cuối**.
- `--mixed`: "bỏ commit và bỏ add" → dùng khi muốn chia lại commit.
- `--hard`: "về y như commit trước, xóa hết thay đổi" → **lệnh duy nhất thực sự xóa công việc chưa commit**.

> ⚠️ `reset --hard` xóa vĩnh viễn những thay đổi **chưa commit** — reflog không cứu được chúng vì chúng chưa từng là object. Commit đã có thì reflog vẫn cứu được (mục 4.6). Chạy `git status` trước mỗi lần `--hard`.

### 4.5. 🟥 `revert` — hoàn tác bằng một commit mới

`git revert <commit>` tạo **commit mới** có nội dung ngược với commit chỉ định. Lịch sử cũ giữ nguyên, chỉ thêm một commit.

| | `reset` (trên commit đã push) | `revert` |
|---|---|---|
| Lịch sử | **Viết lại** — commit biến mất khỏi nhánh | **Giữ nguyên**, thêm commit đảo ngược |
| Đẩy lên remote | Phải `push --force` | `push` bình thường |
| Ảnh hưởng đồng nghiệp | Họ đã có commit cũ → lịch sử hai bên lệch nhau, gây rối | Không ảnh hưởng |
| Dùng khi | Commit **chỉ có ở máy bạn**, chưa push | Commit **đã push lên nhánh chung** (`main`) |

**Quy tắc:** trên nhánh dùng chung, **chỉ dùng `revert`**. `reset` chỉ dành cho commit chưa rời khỏi máy bạn. Đây cũng là lý do bài 03 sẽ bật branch protection chặn `push --force` vào `main`.

### 4.6. 🟥 Reflog — "hộp đen" của repo

Mỗi lần HEAD hoặc một nhánh di chuyển (commit, reset, checkout, merge, rebase), Git ghi lại vào **reflog** (reference log — nhật ký tham chiếu):

```text
a1b2c3d HEAD@{0}: reset: moving to HEAD~2
9f8e7d6 HEAD@{1}: commit: feat: add healthcheck
5c4b3a2 HEAD@{2}: commit: docs: update README
```

`HEAD@{1}` nghĩa là "vị trí của HEAD một bước trước". Commit `9f8e7d6` dù không còn thuộc nhánh nào vẫn **nằm nguyên trong `.git/objects/`**. Chỉ cần tạo lại một ref trỏ tới nó là cứu được.

Giới hạn cần nhớ:

- Reflog **chỉ có trên máy của bạn**, không được push lên GitHub.
- Mục cũ hết hạn sau một thời gian (mặc định cỡ vài tháng) rồi bị `git gc` dọn đi.
- Không cứu được thay đổi chưa từng commit.

### 4.7. 🟥 `stash` — cất tạm thay đổi dở dang

`git stash` lấy mọi thay đổi chưa commit (đã stage và chưa stage) cất vào một "ngăn kéo", trả working directory về sạch như HEAD. Sau đó bạn chuyển nhánh, xử lý việc khẩn cấp, quay lại và `git stash pop` để lấy ra.

Mặc định stash **không** cất file mới chưa từng `add` (untracked). Dùng `git stash -u` để cất cả chúng.

### 4.8. 🟨 Đọc lịch sử: `log`, `show`, `blame`

- `git log` có nhiều bộ lọc mạnh: theo tác giả, theo thời gian, theo nội dung thay đổi (`-S`).
- `git show <commit>` hiện metadata + diff của một commit.
- `git blame <file>` cho biết **từng dòng** được sửa lần cuối bởi commit nào, ai, khi nào.

`blame` không nhằm "đổ lỗi" — mục đích là tìm **commit và lý do** (lời nhắn commit, PR liên quan) đằng sau một dòng code.

### 4.9. Gặp lại ở đâu

| Khái niệm ở bài này | Gặp lại ở |
|---|---|
| Commit SHA là định danh duy nhất | Tag Docker image `taskhub:<sha>` (Module 04, 05) |
| Detached HEAD | Pipeline GitHub Actions checkout đúng một commit (Module 05) |
| `revert` thay vì `reset` trên nhánh chung | Rollback cấu hình, Terraform (Module 05, 07) |
| Branch chỉ là con trỏ | Hiểu vì sao CI chạy được trên mọi nhánh, mọi PR (Module 05) |
| Content-addressable (đặt tên theo hash nội dung) | Docker image layer cũng được đặt tên theo hash (Module 04) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Commit lỗi đã lên `main` và đã deploy

Commit `4e5f6a7` đổi timeout kết nối DB từ 30s xuống 3s, gây lỗi hàng loạt trên production. Hai cách:

```bash
# ❌ Sai: viết lại lịch sử nhánh chung
git reset --hard HEAD~1
git push --force          # đồng nghiệp đang có 4e5f6a7 → lịch sử lệch, có thể mất commit của người khác

# ✅ Đúng: thêm commit đảo ngược
git revert 4e5f6a7
git push                  # pipeline deploy lại bản có timeout 30s
```

Commit revert tự ghi lời nhắn `Revert "..."` kèm SHA gốc — 6 tháng sau người khác đọc log vẫn hiểu chuyện gì đã xảy ra.

### Ví dụ 2: Image nào đang chạy?

Pipeline của bạn gắn tag image bằng 7 ký tự đầu của commit SHA: `ghcr.io/<github-user>/taskhub:3a0874c`. Khi production lỗi:

```bash
git show 3a0874c --stat      # commit này thay đổi những file nào
git log --oneline 3a0874c..main   # những commit nào đã có trên main nhưng CHƯA được deploy
```

### Ví dụ 3: "Ai xóa biến `DB_POOL_SIZE`?"

```bash
git log -S DB_POOL_SIZE --oneline -- src/main/resources/application.yml
```

`-S` tìm những commit làm **thay đổi số lần xuất hiện** của chuỗi đó — tức là commit thêm vào hoặc xóa đi nó.

---

## 6. Sơ đồ kiến trúc

### 6.1. Object và ref sau 2 commit

```text
 .git/HEAD ──► "ref: refs/heads/main"
                        │
 .git/refs/heads/main ──► "9f8e7d6…"   (file 41 byte)
                        │
                        ▼
              ┌───────────────────┐   parent   ┌───────────────────┐
              │ commit 9f8e7d6    │──────────► │ commit 5c4b3a2    │──► (không có cha)
              │ tree: 7a1b…       │            │ tree: 2d3e…       │
              │ author, message   │            │ author, message   │
              └────────┬──────────┘            └────────┬──────────┘
                       ▼                                ▼
              ┌───────────────────┐            ┌───────────────────┐
              │ tree 7a1b…        │            │ tree 2d3e…        │
              │ 100644 blob e69d… README.md ◄──┼── dùng chung blob │
              │ 100755 blob 8c2f… deploy.sh    │ 100644 blob e69d… README.md
              └───────────────────┘            └───────────────────┘
```

README.md không đổi giữa hai commit → **cả hai tree trỏ tới cùng một blob**. Chỉ `deploy.sh` mới tạo blob mới.

### 6.2. `reset` di chuyển cái gì

```text
Trước:   A ── B ── C   ← main ← HEAD          (working dir & index = C)

git reset --soft  B :  main → B ; index = C ; working = C   → thay đổi của C "đã stage"
git reset --mixed B :  main → B ; index = B ; working = C   → thay đổi của C "chưa stage"
git reset --hard  B :  main → B ; index = B ; working = B   → thay đổi của C biến khỏi file

Commit C vẫn còn trong .git/objects → cứu được bằng reflog (HEAD@{1}).
```

### 6.3. `revert` không viết lại lịch sử

```text
Trước:   A ── B ── C   ← main
Sau:     A ── B ── C ── C'  ← main      (C' = đảo ngược nội dung của C)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `git cat-file -t / -p <sha>` | Xem loại / nội dung một object | 🟨 |
| `git rev-parse <ref>` | Đổi tên (branch, tag, HEAD~1) thành SHA đầy đủ | 🟨 |
| `git switch`, `git switch -c` | Chuyển nhánh / tạo nhánh mới và chuyển sang | 🟥 |
| `git checkout <commit>` | Xem code ở một commit (detached HEAD) | 🟥 |
| `git reset --soft/--mixed/--hard` | Di chuyển nhánh, đồng bộ index/working dir | 🟥 |
| `git revert <commit>` | Hoàn tác bằng commit mới | 🟥 |
| `git reflog` | Xem lịch sử di chuyển của HEAD | 🟥 |
| `git stash`, `stash list`, `stash pop` | Cất / xem / lấy lại thay đổi dở dang | 🟥 |
| `git log --oneline --graph --all` | Xem lịch sử dạng đồ thị mọi nhánh | 🟥 |
| `git log -p`, `--author`, `--since`, `-S` | Lọc lịch sử | 🟨 |
| `git show <commit>` | Chi tiết một commit | 🟥 |
| `git blame <file>` | Ai sửa dòng nào, commit nào | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Mọi SHA và ngày giờ dưới đây là **minh họa**. Trên máy bạn chúng sẽ khác — hãy so cấu trúc, không so con số.

### `git cat-file` — nhìn vào bên trong object

```bash
git cat-file -t HEAD          # loại object mà HEAD trỏ tới
git cat-file -p HEAD          # nội dung commit
```

```text
commit
tree 7a1b2c3d4e5f60718293a4b5c6d7e8f901234567
parent 5c4b3a2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b
author phuong <you@example.com> 1761904800 +0700
committer phuong <you@example.com> 1761904800 +0700

feat: add deploy script
```

| Tham số | Ý nghĩa |
|---|---|
| `-t` | In **loại** object: `blob`, `tree`, `commit`, `tag` |
| `-p` | In **nội dung** đẹp (pretty-print), tự nhận diện loại |
| `-s` | In kích thước (byte) |

Đi tiếp xuống tree và blob:

```bash
git cat-file -p 'HEAD^{tree}'     # tree gốc của commit HEAD
```

```text
100644 blob e69de29bb2d1d6434b8b29ae775ad8c2e48c5391    README.md
100755 blob 8c2f0a1b3c4d5e6f708192a3b4c5d6e7f8091a2b    deploy.sh
```

Cột đầu là **mode**: `100644` file thường, `100755` file có quyền thực thi (nối với chmod ở [Linux 03](../01-LINUX/03-permissions-users-groups.md)), `040000` thư mục con. Git chỉ lưu đúng hai trạng thái quyền này cho file — không lưu owner hay quyền chi tiết khác.

```bash
git cat-file -p 8c2f0a1        # đủ 4+ ký tự đầu không trùng là Git hiểu
```

```text
#!/usr/bin/env bash
echo "deploying..."
```

### `git rev-parse` — tên → SHA

```bash
git rev-parse HEAD
git rev-parse --short HEAD
git rev-parse main~1
cat .git/refs/heads/main
cat .git/HEAD
```

```text
9f8e7d6c5b4a39281706f5e4d3c2b1a098f7e6d5
9f8e7d6
5c4b3a2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b
9f8e7d6c5b4a39281706f5e4d3c2b1a098f7e6d5
ref: refs/heads/main
```

Dòng 1 và dòng 4 giống hệt nhau — **chứng minh branch `main` chỉ là file chứa SHA**.

| Cú pháp | Nghĩa |
|---|---|
| `HEAD~1` (hoặc `HEAD~`) | Cha của HEAD |
| `HEAD~3` | Ông cố — đi lùi 3 bước theo cha thứ nhất |
| `HEAD^2` | Cha **thứ hai** (chỉ có ở merge commit) |
| `--short` | SHA rút gọn (thường 7 ký tự) |

> `git rev-parse --short HEAD` là lệnh pipeline CI hay dùng để lấy tag cho Docker image.

### `git switch` và `git checkout`

```bash
git switch main              # chuyển sang nhánh có sẵn
git switch -c fix/timeout    # tạo nhánh mới từ vị trí hiện tại và chuyển sang
git checkout 5c4b3a2         # xem code ở một commit → detached HEAD
git switch -                 # quay về nhánh vừa ở trước đó
```

```text
Note: switching to '5c4b3a2'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.
...
HEAD is now at 5c4b3a2 docs: update README
```

`git checkout` là lệnh cũ làm quá nhiều việc (chuyển nhánh, khôi phục file, xem commit). Git 2.23+ tách thành `git switch` (chuyển nhánh) và `git restore` (khôi phục file). Ubuntu 24.04 có Git 2.43 nên dùng được cả hai. Hãy dùng `switch`/`restore` cho rõ ràng, nhưng vẫn cần đọc hiểu `checkout` vì tài liệu cũ và script CI dùng rất nhiều.

### `git reset`

```bash
git reset --soft HEAD~1      # bỏ commit cuối, giữ thay đổi đã stage
git reset HEAD~1             # = --mixed: bỏ commit cuối, thay đổi về trạng thái chưa stage
git reset --hard HEAD~1      # ⚠️ bỏ commit cuối VÀ xóa thay đổi khỏi file
git reset --hard origin/main # ⚠️ làm nhánh local giống hệt remote, bỏ mọi thứ local
```

Kiểm tra sau mỗi lần reset: `git status` và `git log --oneline -3`.

```text
$ git reset --soft HEAD~1
$ git status
On branch main
Changes to be committed:
  (use "git restore --staged <file>..." to unstage)
        new file:   deploy.sh
```

### `git revert`

```bash
git revert 4e5f6a7                 # mở editor để sửa lời nhắn, rồi tạo commit
git revert --no-edit 4e5f6a7       # dùng lời nhắn mặc định, không mở editor
```

```text
[main 1d2c3b4] Revert "perf: reduce db timeout to 3s"
 1 file changed, 1 insertion(+), 1 deletion(-)
```

Nếu commit cần revert đã bị các commit sau sửa tiếp cùng dòng, revert có thể **conflict** — cách giải quyết giống merge conflict ([bài 02](02-branching-merging-conflicts.md)).

### `git reflog`

```bash
git reflog                  # lịch sử của HEAD
git reflog show main        # lịch sử của riêng nhánh main
git reflog -5               # 5 mục gần nhất
```

```text
5c4b3a2 (HEAD -> main) HEAD@{0}: reset: moving to HEAD~1
9f8e7d6 HEAD@{1}: commit: feat: add deploy script
5c4b3a2 (HEAD -> main) HEAD@{2}: commit (initial): docs: update README
```

Cứu commit:

```bash
git branch rescue 9f8e7d6        # tạo nhánh mới trỏ tới commit "mất" — an toàn, không đụng main
# hoặc, nếu chắc chắn muốn đưa main quay lại:
git reset --hard HEAD@{1}        # ⚠️ chỉ khi working directory không có thay đổi cần giữ
```

> Luôn **tạo nhánh cứu hộ trước**, suy nghĩ sau. Tạo nhánh không bao giờ làm mất gì.

### `git stash`

```bash
git stash push -m "wip: refactor config"   # cất, có ghi chú
git stash -u                               # cất cả file untracked
git stash list
git stash show -p stash@{0}                # xem nội dung một stash
git stash pop                              # lấy ra stash mới nhất và xóa nó khỏi danh sách
git stash apply stash@{1}                  # lấy ra nhưng vẫn giữ trong danh sách
git stash drop stash@{1}                   # ⚠️ xóa một stash
```

```text
stash@{0}: On main: wip: refactor config
stash@{1}: WIP on fix/timeout: 5c4b3a2 docs: update README
```

`pop` có thể conflict nếu bạn đã sửa cùng chỗ trong lúc stash đang cất — khi đó stash **không bị xóa** khỏi danh sách, bạn giải quyết conflict rồi `git stash drop` bằng tay.

### `git log` nâng cao

```bash
git log --oneline --graph --all --decorate
git log -p -2                               # 2 commit gần nhất kèm diff
git log --author="phuong" --since="2 weeks ago" --oneline
git log -S "DB_POOL_SIZE" --oneline         # commit thêm/xóa chuỗi này
git log --oneline -- compose.yaml           # chỉ commit đụng tới file này
git log main..fix/timeout --oneline         # commit có trên fix/timeout mà main chưa có
```

```text
* 1d2c3b4 (HEAD -> main) Revert "perf: reduce db timeout to 3s"
* 4e5f6a7 perf: reduce db timeout to 3s
| * 7b8c9d0 (fix/timeout) fix: handle timeout exception
|/
* 9f8e7d6 feat: add deploy script
* 5c4b3a2 docs: update README
```

| Tham số | Ý nghĩa |
|---|---|
| `--oneline` | Mỗi commit một dòng: SHA ngắn + tiêu đề |
| `--graph` | Vẽ đồ thị nhánh bằng ký tự |
| `--all` | Hiện mọi nhánh, không chỉ nhánh hiện tại |
| `--decorate` | Hiện tên nhánh/tag cạnh commit (thường mặc định đã bật) |
| `-p` | Kèm diff |
| `-S <chuỗi>` | Commit làm thay đổi số lần xuất hiện của chuỗi ("pickaxe") |
| `-- <đường dẫn>` | Chỉ commit đụng tới file/thư mục đó |
| `A..B` | Commit có trong B mà không có trong A |

> Mẹo: tạo alias `git config --global alias.lg "log --oneline --graph --all --decorate"` rồi dùng `git lg`.

### `git show` và `git blame`

```bash
git show 4e5f6a7              # metadata + diff
git show 4e5f6a7 --stat       # chỉ danh sách file thay đổi
git show HEAD:compose.yaml    # nội dung file compose.yaml ở commit HEAD
git blame -L 10,20 src/main/resources/application.yml
```

```text
4e5f6a7c (phuong 2026-11-14 21:03:11 +0700 12)     connection-timeout: 3000
9f8e7d6c (phuong 2026-11-10 20:15:42 +0700 13)     maximum-pool-size: 10
```

`-L 10,20`: chỉ xem dòng 10–20. Mỗi dòng: SHA commit sửa cuối, tác giả, thời gian, số dòng, nội dung.

---

## 9. Bài thực hành từng bước

**Lab: Mổ xẻ repo và cứu commit bằng reflog** · `[WSL]` · ~60 phút

Ghi câu trả lời các câu ❓ vào `~/devops-journey/week06/lab-git-01.md`.

### Bước 1 — Tạo repo nhỏ

```bash
mkdir -p ~/devops-lab/03-git/internals && cd ~/devops-lab/03-git/internals
git init
echo "# Internals demo" > README.md
git add README.md
git commit -m "docs: add README"
ls .git
find .git/objects -type f
```

❓ Sau commit đầu tiên có bao nhiêu file trong `.git/objects`? Đoán xem mỗi file là loại object gì (gợi ý: 3 file = 1 blob + 1 tree + 1 commit).

### Bước 2 — Đọc từng object

```bash
git cat-file -p HEAD
git cat-file -p 'HEAD^{tree}'
git cat-file -p <sha-của-blob-README>     # lấy từ dòng trên
for f in $(find .git/objects -type f | sed 's|.git/objects/||; s|/||'); do
  echo "$f $(git cat-file -t $f)"
done
```

❓ Commit đầu tiên có dòng `parent` không? Tên file `README.md` nằm trong object nào — blob hay tree?

### Bước 3 — Chứng minh branch là con trỏ

```bash
cat .git/HEAD
cat .git/refs/heads/main
git rev-parse main
wc -c .git/refs/heads/main
git branch feature-x
ls .git/refs/heads/
cat .git/refs/heads/feature-x
```

❓ `wc -c` cho bao nhiêu byte? Vì sao `feature-x` chứa đúng SHA của `main`?

### Bước 4 — Blob dùng chung

```bash
printf '#!/usr/bin/env bash\necho "deploying..."\n' > deploy.sh
chmod +x deploy.sh
cp README.md README-copy.md
git add . && git commit -m "feat: add deploy script"
git cat-file -p 'HEAD^{tree}'
```

❓ `README.md` và `README-copy.md` có cùng SHA blob không? Vì sao? Mode của `deploy.sh` là gì?

### Bước 5 — Detached HEAD

```bash
git log --oneline
git checkout HEAD~1
cat .git/HEAD
git status | head -3
git switch main
```

❓ Nội dung `.git/HEAD` khác gì ở trạng thái detached?

### Bước 6 — Thử ba kiểu reset

```bash
echo "v3" >> README.md && git commit -am "docs: v3"
git reset --soft HEAD~1 && git status --short && git commit -m "docs: v3 (again)"
git reset --mixed HEAD~1 && git status --short && git commit -am "docs: v3 (third time)"
git log --oneline
```

❓ Ghi lại `git status --short` sau `--soft` và sau `--mixed`. Ký tự `M ` (cột 1) và ` M` (cột 2) khác nhau thế nào?

### Bước 7 — "Thảm họa" và cứu hộ

```bash
git log --oneline                 # ghi lại SHA của commit trên cùng
git reset --hard HEAD~2           # ⚠️ cố tình "làm mất" 2 commit
git log --oneline                 # 2 commit đã biến mất khỏi nhánh
git reflog -6
git branch rescue HEAD@{1}
git log --oneline rescue
git switch main && git reset --hard rescue && git branch -d rescue
git log --oneline
```

❓ Commit "mất" có thực sự bị xóa khỏi `.git/objects` không? Bạn chứng minh bằng lệnh nào?

### Bước 8 — Revert

```bash
git log --oneline
git revert --no-edit HEAD
git log --oneline
git show HEAD --stat
```

❓ Số commit tăng hay giảm sau revert? Nội dung `README.md` có còn dòng `v3` không?

### Bước 9 — Stash

```bash
echo "work in progress" >> README.md
echo "new file" > notes.txt
git stash
git status --short                 # notes.txt vẫn còn — vì sao?
git stash pop
git stash -u && git status --short && git stash pop
```

### Bước 10 — Commit kết quả

```bash
cd ~/devops-journey
git add week06/lab-git-01.md
git commit -m "docs(git): lab 01 - git internals and reflog rescue"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 1:** 3 object sau commit đầu: 1 blob (nội dung README), 1 tree (thư mục gốc), 1 commit.
- **Bước 2:** Commit đầu tiên **không có** dòng `parent`. Tên `README.md` nằm trong **tree**, blob chỉ có nội dung.
- **Bước 3:** `wc -c` = **41** byte (40 ký tự hex + xuống dòng). `feature-x` chứa SHA giống `main` vì tạo nhánh chỉ là tạo con trỏ mới tới commit hiện tại.
- **Bước 4:** `README.md` và `README-copy.md` **cùng SHA blob** vì cùng nội dung — Git lưu một lần. `deploy.sh` có mode `100755`.
- **Bước 5:** `.git/HEAD` chứa SHA trần thay vì `ref: refs/heads/main`.
- **Bước 6:** Sau `--soft`: `M  README.md` (cột 1 = đã stage). Sau `--mixed`: ` M README.md` (cột 2 = đã sửa, chưa stage).
- **Bước 7:** Commit vẫn còn: `git cat-file -t <sha>` vẫn trả `commit`. Nhánh `rescue` khôi phục đầy đủ lịch sử.
- **Bước 8:** Số commit **tăng 1**. Nội dung README quay về như trước commit bị revert.
- **Bước 9:** `notes.txt` còn lại sau `git stash` thường vì là file untracked; `stash -u` mới cất nó.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Mất công việc sau `reset --hard` | Thay đổi **chưa commit** — không có object nào để cứu | Phòng ngừa: `git status` trước khi `--hard`; commit hoặc `stash` trước. Nếu đã commit → reflog |
| Commit trong detached HEAD rồi "biến mất" khi chuyển nhánh | Commit không thuộc nhánh nào | `git reflog` tìm SHA → `git branch <tên> <sha>` |
| `reset` + `push --force` lên `main` làm đồng nghiệp lỗi | Viết lại lịch sử đã chia sẻ | Dùng `revert`. Bật branch protection chặn force push (bài 03) |
| `git stash pop` báo conflict và stash không biến mất | Pop thất bại giữa chừng thì Git giữ stash lại để an toàn | Giải quyết conflict, `git add`, rồi `git stash drop` |
| `error: pathspec 'xyz' did not match any file(s) known to git` | Gõ sai tên nhánh/file, hoặc nhánh chỉ có trên remote chưa fetch | `git branch -a`, `git fetch` |
| `fatal: ambiguous argument 'HEAD~1': unknown revision` | Repo mới chỉ có 1 commit, không có cha | Bình thường với commit đầu tiên |
| `git log` không thấy commit vừa revert ở nhánh khác | `git log` mặc định chỉ hiện nhánh hiện tại | Thêm `--all` |

---

## 12. Đọc thông báo lỗi và xử lý

Thông báo của Git thường có cấu trúc **"điều gì sai" + "gợi ý làm gì"** (dòng `hint:` hoặc `(use "git ..." to ...)`). Đọc hết phần gợi ý — Git rất hay chỉ đúng lệnh cần chạy.

```text
error: Your local changes to the following files would be overwritten by checkout:
        README.md
Please commit your changes or stash them before you switch branches.
Aborting
```

- **Điều gì sai:** bạn có thay đổi chưa commit trong `README.md`, và nhánh đích có phiên bản khác của file này.
- **Gợi ý:** commit hoặc stash.
- **Điều quan trọng:** `Aborting` — Git **chưa làm gì cả**, dữ liệu của bạn an toàn.

```text
fatal: bad object 9f8e7d6
```

- Object không tồn tại trong repo này: có thể gõ sai SHA, SHA thuộc repo khác, hoặc commit chỉ có trên remote chưa fetch.

**Công cụ chẩn đoán khi Git hành xử lạ:**

```bash
git status                    # luôn chạy đầu tiên — Git nói bạn đang ở trạng thái gì
git log --oneline --graph --all -10
git reflog -10                # vừa xảy ra chuyện gì với HEAD
GIT_TRACE=1 git <lệnh>        # 🟦 in chi tiết Git đang làm gì bên dưới
```

Ghi lại mỗi lần "suýt mất dữ liệu" vào `troubleshooting-journal.md` theo [mẫu nhật ký debug](../00-ROADMAP/templates/troubleshooting-journal-template.md) — đây là câu chuyện rất hay để kể khi phỏng vấn.

---

## 13. Câu hỏi kiểm tra kiến thức

1. "Git lưu snapshot chứ không phải diff" nghĩa là gì? Vậy `git diff` lấy đâu ra kết quả?
2. Kể tên 4 loại object. Tên file được lưu trong object nào?
3. Hai file khác tên, cùng nội dung — Git lưu mấy blob? Vì sao?
4. Branch thực chất là gì? Vì sao tạo nhánh trong Git gần như tức thì?
5. HEAD là gì? Nội dung `.git/HEAD` khác nhau thế nào giữa trạng thái bình thường và detached?
6. Bạn đang ở detached HEAD và đã commit 2 lần. Làm sao để giữ lại 2 commit đó?
7. So sánh `reset --soft`, `--mixed`, `--hard`. Lệnh nào có thể làm mất dữ liệu không cứu được?
8. Vì sao trên `main` đã push nên dùng `revert` thay vì `reset`?
9. Reflog là gì? Kể 3 giới hạn của nó.
10. `git stash` mặc định có cất file mới chưa `add` không?
11. Lệnh nào tìm được commit đã xóa một chuỗi cụ thể khỏi code?
12. Vì sao DevOps hay dùng `git rev-parse --short HEAD` trong pipeline?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/01-solutions.md](solutions/01-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Đếm object.** Tạo repo mới, commit 1 file. Sau đó tạo thư mục `docs/` chứa 1 file, commit lần 2. Dự đoán **trước** tổng số object sẽ có, rồi kiểm chứng bằng `find .git/objects -type f | wc -l`. Giải thích từng object.

**Bài 2 — Tự tạo branch bằng tay.** Không dùng `git branch`, hãy tạo nhánh `manual` trỏ tới commit hiện tại chỉ bằng lệnh shell (gợi ý: `.git/refs/heads/`). Kiểm chứng bằng `git branch` và `git log --oneline manual`. Sau đó tìm lệnh Git "chính thống" làm việc tương tự (gợi ý: `git update-ref`) và giải thích vì sao nên dùng nó thay vì sửa file tay.

**Bài 3 — Undo đúng cách.** Với mỗi tình huống, chọn lệnh phù hợp và giải thích:
(a) Vừa commit nhưng quên thêm 1 file, chưa push.
(b) Vừa commit nhầm file `.env` chứa mật khẩu, **chưa push**.
(c) Commit lỗi đã push lên `main` 2 ngày trước, nhiều người đã pull.
(d) Lỡ `git add .` nhầm file log 200 MB, chưa commit.
(e) Commit nhầm `.env` và **đã push** lên GitHub public.

**Bài 4 — Điều tra.** Clone một repo mã nguồn mở bất kỳ bạn quan tâm (ví dụ repo `github/gitignore` đã giới thiệu ở bài ôn tập). Dùng `git log -S`, `git blame`, `git show` để trả lời: một dòng cụ thể bạn chọn được thêm vào khi nào, bởi commit nào, và lời nhắn commit giải thích lý do gì?

**Bài 5 — Reflog có giới hạn.** Thiết kế một thí nghiệm cho thấy reflog **không** cứu được dữ liệu trong một trường hợp cụ thể. Viết lại các bước và giải thích vì sao.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ lại được sơ đồ mục 6.1 cho repo của chính bạn bằng output của `git cat-file`.
- [ ] Chứng minh được "branch là file 41 byte" cho người khác xem.
- [ ] Chọn đúng `reset`/`revert` cho cả 5 tình huống ở Bài tập 3 mà không do dự.
- [ ] Cứu được commit sau `reset --hard` trong dưới 2 phút.
- [ ] Giải thích được vì sao CI pipeline thường ở trạng thái detached HEAD và vì sao điều đó không sao.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Pro Git 10.2 — Git Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects) | Blob, tree, commit, `cat-file` | 2026-10-31 |
| [Pro Git 10.3 — Git References](https://git-scm.com/book/en/v2/Git-Internals-Git-References) | HEAD, refs, detached HEAD | 2026-10-31 |
| [Pro Git 7.7 — Reset Demystified](https://git-scm.com/book/en/v2/Git-Tools-Reset-Demystified) | Ba cây và `reset` | 2026-10-31 |
| [Pro Git 7.1 — Revision Selection](https://git-scm.com/book/en/v2/Git-Tools-Revision-Selection) | Reflog, `HEAD@{n}`, `HEAD~n` | 2026-10-31 |
| [MIT Missing Semester — Version Control and Git](https://missing.csail.mit.edu/) | Mô hình dữ liệu Git | 2026-10-31 |
| `git help reset`, `git help revert`, `git help reflog` | Tra cứu trên máy | — |
