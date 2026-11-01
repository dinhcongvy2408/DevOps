# 02. Branching, merging & conflicts

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Git fundamentals & internals](01-git-fundamentals-internals.md)
> Môi trường: `[WSL]` Ubuntu 24.04

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

- Tạo, chuyển, xóa nhánh local và remote.
- Giải thích bằng sơ đồ **fast-forward merge** và **3-way merge**, khi nào xảy ra loại nào.
- Hiểu **rebase** làm gì, và thuộc lòng **quy tắc vàng**: không rebase commit đã chia sẻ.
- Đọc **conflict markers**, tự giải quyết conflict bằng tay và bằng công cụ của VS Code / IntelliJ, biết cách hủy giữa chừng.
- Phân biệt `git fetch` và `git pull`, hiểu remote-tracking branch (`origin/main`) và upstream.
- 🟨 Dùng `cherry-pick` để mang một commit sang nhánh khác.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống thật | Bạn cần biết |
|---|---|
| Hai người cùng sửa `compose.yaml` → PR báo "This branch has conflicts" | Giải quyết conflict, hiểu vì sao nó xảy ra |
| Bản vá khẩn cấp đã merge vào `main`, cần đưa sang nhánh release cũ | `cherry-pick` |
| "Tôi pull về thì xuất hiện một merge commit lạ" | `pull` = `fetch` + `merge`; cấu hình `pull.rebase` |
| Đồng nghiệp rebase nhánh chung rồi force push, cả nhóm loạn | Quy tắc vàng của rebase |
| Pipeline báo lỗi trên nhánh `feature/x` nhưng `main` vẫn xanh | Hiểu nhánh tách khỏi `main` từ commit nào, đã lệch bao xa |

Conflict là chuyện **hằng ngày**, không phải sự cố. Người làm DevOps thường sửa các file dùng chung nhiều nhất (cấu hình CI, Dockerfile, Terraform), nên gặp conflict nhiều hơn ai hết.

---

## 3. Kiến thức nền tảng cần hiểu

Từ [bài 01](01-git-fundamentals-internals.md) bạn đã biết:

- Commit trỏ tới commit cha → lịch sử là một **đồ thị** (graph) các commit.
- Branch chỉ là **con trỏ** tới một commit; HEAD trỏ tới branch hiện tại.

Thêm một khái niệm: **common ancestor** (tổ tiên chung, còn gọi merge base) — commit gần nhất mà **cả hai nhánh** cùng có trong lịch sử. Mọi phép merge đều xoay quanh commit này.

```text
        C ── D        ← feature
       /
A ── B ── E ── F      ← main

Tổ tiên chung của feature và main: B
```

Git so sánh **ba** snapshot khi merge: tổ tiên chung (B), đầu nhánh hiện tại (F), đầu nhánh được merge (D). Đó là lý do có tên **3-way merge**.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Tạo và chuyển nhánh

Tạo nhánh = tạo con trỏ mới tại commit hiện tại. Khi commit trên nhánh mới, chỉ con trỏ của nhánh đó di chuyển; `main` đứng yên.

Đặt tên nhánh theo quy ước sẽ dùng cho dự án taskhub ([bài 04](04-team-workflows.md)):

| Tiền tố | Dùng cho | Ví dụ |
|---|---|---|
| `feature/` | Tính năng mới | `feature/task-crud` |
| `fix/` | Sửa lỗi | `fix/db-timeout` |
| `docs/` | Tài liệu | `docs/network-plan` |
| `chore/` | Việc vặt: cấu hình, dependency | `chore/update-gitignore` |

### 4.2. 🟥 Fast-forward merge

Nếu `main` **không có commit mới nào** kể từ khi tách nhánh, thì `feature` chỉ đơn giản là "đi trước" `main`. Merge lúc này chỉ cần **dời con trỏ `main` tới trước** — không tạo commit mới. Gọi là **fast-forward** (tua nhanh).

```text
Trước:  A ── B          ← main
              \
               C ── D   ← feature

Sau git merge feature (đang ở main):
        A ── B ── C ── D   ← main, feature
```

### 4.3. 🟥 3-way merge và merge commit

Nếu cả hai nhánh đều có commit mới (lịch sử **rẽ nhánh**, diverged), Git không thể chỉ dời con trỏ. Nó:

1. Tìm tổ tiên chung.
2. So sánh thay đổi của mỗi bên so với tổ tiên chung.
3. Ghép hai bộ thay đổi lại. Nếu không đụng nhau → tự động thành công.
4. Tạo **merge commit** — commit đặc biệt có **hai cha**.

```text
Trước:        C ── D        ← feature
             /
      A ── B ── E ── F      ← main

Sau git merge feature (đang ở main):
             C ── D
            /      \
      A ── B ── E ── F ── M  ← main     (M có 2 cha: F và D)
```

Git hiện đại (từ 2.33) dùng chiến lược merge tên **ort**, nên bạn sẽ thấy dòng `Merge made by the 'ort' strategy.` Tài liệu cũ ghi `'recursive'` — ý nghĩa như nhau với bạn.

Muốn **luôn** có merge commit kể cả khi fast-forward được (để lịch sử ghi rõ "nhánh này đã được merge"), dùng `git merge --no-ff`.

### 4.4. 🟥 Rebase — "chuyển gốc" nhánh

**Rebase** lấy các commit của nhánh bạn và **phát lại** (replay) chúng lên trên một gốc mới:

```text
Trước:        C ── D        ← feature
             /
      A ── B ── E ── F      ← main

Sau git rebase main (đang ở feature):
      A ── B ── E ── F               ← main
                      \
                       C' ── D'      ← feature
```

`C'` và `D'` có **cùng nội dung thay đổi** với C và D nhưng là **commit mới, SHA mới** (vì cha khác → nội dung commit object khác → hash khác — nhớ lại [bài 01, mục 3.2](01-git-fundamentals-internals.md#32-hàm-băm-hash-và-sha)). Sau đó merge `feature` vào `main` sẽ là fast-forward → lịch sử thẳng một đường.

| | Merge | Rebase |
|---|---|---|
| Lịch sử | Giữ nguyên, có merge commit | Thẳng, gọn, **viết lại** commit của nhánh |
| SHA commit cũ | Giữ nguyên | **Đổi** |
| An toàn với nhánh chung | ✅ | ❌ nếu commit đã được người khác dùng |
| Khi nào dùng | Mặc định, nhất là nhánh chung | Cập nhật nhánh **của riêng bạn** trước khi mở PR |

> ### ⚠️ Quy tắc vàng của rebase
> **Không rebase những commit đã tồn tại ngoài repo của bạn và có người khác có thể đã làm việc dựa trên chúng.**
> (Nguyên văn Pro Git: *"Do not rebase commits that exist outside your repository and that people may have based work on."*)
>
> Rebase nhánh feature **chỉ mình bạn dùng**, kể cả đã push lên GitHub để mở PR, thường vẫn ổn — bạn chỉ cần `git push --force-with-lease` sau đó. **Không bao giờ** rebase `main`.

### 4.5. 🟨 Interactive rebase — dọn commit trước khi mở PR

`git rebase -i HEAD~3` mở editor liệt kê 3 commit cuối, cho phép bạn:

- `squash` / `fixup`: gộp commit "sửa typo", "sửa lại lần nữa" vào commit chính.
- `reword`: sửa lời nhắn commit.
- `drop`: bỏ một commit.
- Đổi thứ tự commit.

Đây là thao tác tương tác trong editor (nano/vim) — bạn tự làm trên máy mình. Khi dự án taskhub dùng **squash merge** trên GitHub ([bài 04](04-team-workflows.md)), mọi commit của PR sẽ tự gộp thành một khi merge, nên interactive rebase là **nên biết** chứ không bắt buộc.

### 4.6. 🟥 Merge conflict

**Conflict** xảy ra khi **cả hai nhánh đều sửa cùng một vùng** của cùng một file (so với tổ tiên chung), hoặc một bên sửa file mà bên kia xóa file đó. Git không đoán ý bạn — nó dừng lại và đánh dấu:

```text
<<<<<<< HEAD
  connection-timeout: 30000
=======
  connection-timeout: 10000
>>>>>>> fix/db-timeout
```

| Phần | Ý nghĩa |
|---|---|
| `<<<<<<< HEAD` … `=======` | Phiên bản của **nhánh bạn đang đứng** (ours) |
| `=======` … `>>>>>>> fix/db-timeout` | Phiên bản của **nhánh đang được merge vào** (theirs) |

Cách giải quyết:

1. `git status` — xem file nào đang conflict (`both modified`, `deleted by them`…).
2. Mở file, **quyết định nội dung cuối cùng** (giữ một bên, giữ cả hai, hoặc viết lại), **xóa cả ba dòng đánh dấu**.
3. `git add <file>` — báo cho Git "file này đã giải quyết xong".
4. `git commit` (với merge) hoặc `git rebase --continue` (với rebase).

Đổi ý giữa chừng? `git merge --abort` (hoặc `git rebase --abort`) đưa mọi thứ về trước lúc merge. **Không có gì mất cả.**

> ⚠️ Chú ý chiều ours/theirs **đảo ngược khi rebase**: trong lúc rebase, `HEAD` là nhánh gốc mới (ví dụ `main`) còn commit của bạn mới là "theirs". Đọc kỹ tên nhánh sau `<<<<<<<` và `>>>>>>>` thay vì dựa vào chữ ours/theirs.

**Giải quyết conflict là một quyết định nghiệp vụ, không phải thao tác cơ học.** Ở ví dụ trên, chọn 30000 hay 10000 phụ thuộc vào lý do của từng thay đổi — hãy đọc lời nhắn commit và PR của cả hai bên, hỏi đồng nghiệp nếu cần.

### 4.7. 🟥 Remote, remote-tracking branch và upstream

Khi clone, Git tạo:

- **Remote** tên `origin` trỏ tới URL repo GitHub.
- **Remote-tracking branch** `origin/main`: bản sao **chỉ đọc** của "nhánh main trên GitHub **lần cuối bạn hỏi**". Nó không tự cập nhật.
- Nhánh local `main` với **upstream** là `origin/main` — nhờ đó `git status` báo được "ahead 2, behind 1".

```text
Your branch is ahead of 'origin/main' by 2 commits.     ← bạn có 2 commit chưa push
Your branch is behind 'origin/main' by 1 commit.        ← GitHub có 1 commit bạn chưa có (theo lần fetch gần nhất)
Your branch and 'origin/main' have diverged.            ← cả hai
```

### 4.8. 🟥 `fetch` vs `pull`

- `git fetch`: tải commit mới từ remote, **cập nhật `origin/*`**, **không đụng** vào nhánh local và file của bạn. Luôn an toàn.
- `git pull`: = `git fetch` + tích hợp `origin/main` vào nhánh hiện tại. Tích hợp bằng **merge** (mặc định cũ) hoặc **rebase** tùy cấu hình.

Từ Git 2.27, nếu lịch sử rẽ nhánh mà bạn chưa cấu hình, `git pull` sẽ hỏi bạn muốn merge hay rebase. Khuyến nghị cho người mới:

```bash
git config --global pull.rebase false   # pull = fetch + merge (dễ hiểu, an toàn)
```

hoặc nếu nhóm thống nhất lịch sử thẳng:

```bash
git config --global pull.rebase true    # pull = fetch + rebase commit local lên origin/main
```

Với taskhub, mọi thay đổi vào `main` đều qua PR, nên bạn hiếm khi có commit local trên `main` — cấu hình nào cũng ổn. Thói quen tốt: **`git fetch` rồi nhìn `git log --oneline --graph --all` trước khi `pull`**.

### 4.9. 🟨 Cherry-pick

`git cherry-pick <sha>` lấy **thay đổi của một commit** và tạo commit mới tương ứng trên nhánh hiện tại. Dùng khi cần mang một bản vá cụ thể sang nhánh khác mà không merge cả nhánh. Dùng tiết kiệm: lạm dụng cherry-pick làm cùng một thay đổi xuất hiện với nhiều SHA khác nhau, khó theo dõi.

### 4.10. Gặp lại ở đâu

| Khái niệm ở bài này | Gặp lại ở |
|---|---|
| Nhánh feature + merge vào main | Pull Request (bài 03), GitHub Flow (bài 04) |
| Conflict | PR báo "This branch has conflicts that must be resolved" (bài 03) |
| `fetch` / `origin/main` | Pipeline CI checkout đúng commit của PR (Module 05) |
| `--force-with-lease` | Branch protection chặn force push vào `main` (bài 03) |
| Cherry-pick bản vá | Hotfix cho phiên bản đang chạy trên production (bài 05) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Hai người cùng sửa `compose.yaml`

- An mở PR `feature/add-redis` thêm service `redis` vào cuối `compose.yaml`.
- Bình mở PR `chore/pin-postgres` đổi `image: postgres:16` → `image: postgres:17`.

Hai thay đổi ở **hai vùng khác nhau** của cùng file → Git tự merge, **không conflict**. Conflict chỉ xảy ra nếu cả hai cùng sửa dòng `image:` của postgres, hoặc cùng thêm service vào **cùng một vị trí** (cuối file).

### Ví dụ 2: Cập nhật nhánh trước khi mở PR

Bạn làm `feature/task-crud` 3 ngày, trong lúc đó `main` có 5 commit mới. Trước khi mở PR:

```bash
git fetch origin
git switch feature/task-crud
git rebase origin/main            # nhánh của riêng bạn → rebase được
# giải quyết conflict nếu có, chạy test lại
git push --force-with-lease       # cập nhật nhánh trên GitHub
```

`--force-with-lease` chỉ ghi đè nếu nhánh trên GitHub **vẫn đúng như lần cuối bạn thấy** — nếu ai đó đã đẩy thêm commit, lệnh sẽ từ chối thay vì xóa mất công của họ. Luôn dùng nó thay cho `--force`.

### Ví dụ 3: Hotfix cần có ở hai nơi

Lỗi bảo mật được sửa bằng commit `a1b2c3d` trên `main`. Production đang chạy bản `v0.3.x` từ nhánh `release/0.3`:

```bash
git switch release/0.3
git cherry-pick a1b2c3d
git push
```

---

## 6. Sơ đồ kiến trúc

### 6.1. Ba cách đưa `feature` vào `main`

```text
Ban đầu:           C ── D            ← feature
                  /
           A ── B ── E               ← main

① merge (3-way):          C ── D
                         /      \
                  A ── B ── E ── M   ← main          lịch sử thật, có merge commit

② rebase rồi fast-forward:
                  A ── B ── E ── C' ── D'   ← main   thẳng, C', D' là commit mới

③ squash merge (GitHub "Squash and merge"):
                  A ── B ── E ── S          ← main   S = C + D gộp thành 1 commit
```

### 6.2. Local, remote-tracking và remote

```text
  GitHub (origin)                    Máy bạn
 ┌───────────────┐    git fetch    ┌────────────────────────────────┐
 │ main: F       │ ──────────────► │ origin/main: F  (chỉ đọc)      │
 └───────────────┘                 │        │ git merge / rebase    │
        ▲                          │        ▼                       │
        │          git push        │ main: D  (nhánh local của bạn) │
        └───────────────────────── │                                │
                                   └────────────────────────────────┘
  git pull = git fetch + (merge hoặc rebase) origin/main vào main
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `git branch`, `git branch -a`, `-vv` | Liệt kê nhánh local / mọi nhánh / kèm upstream | 🟥 |
| `git switch -c <nhánh>` | Tạo và chuyển sang nhánh mới | 🟥 |
| `git merge <nhánh>`, `--no-ff`, `--abort` | Merge / luôn tạo merge commit / hủy | 🟥 |
| `git rebase <gốc>`, `--continue`, `--abort` | Rebase / tiếp tục sau khi giải quyết conflict / hủy | 🟥 |
| `git rebase -i HEAD~n` | Dọn n commit cuối (tương tác) | 🟨 |
| `git merge-base A B` | Tìm tổ tiên chung | 🟨 |
| `git diff`, `git diff --name-only --diff-filter=U` | Xem conflict / liệt kê file đang conflict | 🟥 |
| `git checkout --ours/--theirs <file>` | Chọn nguyên phiên bản một bên khi conflict | 🟨 |
| `git fetch`, `git fetch --prune` | Tải từ remote / xóa `origin/*` của nhánh đã bị xóa trên remote | 🟥 |
| `git pull` | fetch + merge/rebase | 🟥 |
| `git push -u origin <nhánh>` | Đẩy nhánh mới và đặt upstream | 🟥 |
| `git push --force-with-lease` | Ghi đè nhánh **của bạn** an toàn sau rebase | 🟥 |
| `git branch -d / -D`, `git push origin --delete <nhánh>` | Xóa nhánh local / xóa nhánh remote | 🟥 |
| `git cherry-pick <sha>` | Mang một commit sang nhánh hiện tại | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra dưới đây là **minh họa**; SHA và số dòng trên máy bạn sẽ khác.

### `git branch` và `git switch`

```bash
git switch -c feature/healthcheck
git branch -vv
```

```text
* feature/healthcheck 9f8e7d6 feat: add deploy script
  main                9f8e7d6 [origin/main] feat: add deploy script
```

| Tham số | Ý nghĩa |
|---|---|
| `-a` | Hiện cả remote-tracking branch (`remotes/origin/...`) |
| `-v` / `-vv` | Hiện commit cuối / thêm upstream và ahead-behind |
| `-d` | Xóa nhánh **đã được merge** — Git từ chối nếu chưa merge (an toàn) |
| `-D` | ⚠️ Xóa nhánh dù chưa merge (commit chỉ còn trong reflog) |

### `git merge`

```bash
git switch main
git merge feature/healthcheck
```

Fast-forward:

```text
Updating 9f8e7d6..3a0874c
Fast-forward
 healthcheck.sh | 5 +++++
 1 file changed, 5 insertions(+)
 create mode 100755 healthcheck.sh
```

3-way:

```text
Merge made by the 'ort' strategy.
 README.md | 1 +
 1 file changed, 1 insertion(+)
```

Conflict:

```text
Auto-merging config.yml
CONFLICT (content): Merge conflict in config.yml
Automatic merge failed; fix conflicts and then commit the result.
```

| Tham số | Ý nghĩa |
|---|---|
| `--no-ff` | Luôn tạo merge commit, kể cả khi fast-forward được |
| `--ff-only` | Chỉ merge nếu fast-forward được, nếu không thì từ chối — an toàn khi cập nhật `main` local |
| `--abort` | Hủy merge đang dở, trả về trạng thái trước merge |
| `--squash` | 🟨 Gộp thay đổi của nhánh vào index, không tạo merge commit; bạn tự commit |

### Đọc trạng thái conflict

```bash
git status
```

```text
On branch main
You have unmerged paths.
  (fix conflicts and run "git commit")
  (use "git merge --abort" to abort the merge)

Unmerged paths:
  (use "git add <file>..." to mark resolution)
        both modified:   config.yml
```

| Nhãn | Ý nghĩa |
|---|---|
| `both modified` | Cả hai bên sửa cùng vùng — conflict nội dung |
| `deleted by them` / `deleted by us` | Một bên xóa file, bên kia sửa — conflict modify/delete |
| `both added` | Cả hai bên cùng tạo file trùng tên với nội dung khác |

```bash
git diff                                   # hiện vùng conflict dạng diff kết hợp
git diff --name-only --diff-filter=U       # chỉ liệt kê file đang conflict
```

Xử lý conflict modify/delete:

```bash
git rm old-config.yml        # đồng ý xóa
# hoặc
git add old-config.yml       # giữ file (với nội dung bạn đã chỉnh)
```

Chọn nguyên một phía cho cả file (🟨, chỉ khi chắc chắn):

```bash
git checkout --ours config.yml     # giữ phiên bản nhánh hiện tại
git checkout --theirs config.yml   # giữ phiên bản nhánh được merge vào
git add config.yml
```

### Công cụ giải quyết conflict trong IDE

- **VS Code**: mở file conflict, phía trên mỗi vùng có các nút *Accept Current Change*, *Accept Incoming Change*, *Accept Both Changes*, *Compare Changes*. Có thể mở *Merge Editor* 3 cột (bản của bạn, bản đến, kết quả).
- **IntelliJ IDEA**: *Git → Resolve Conflicts…* mở cửa sổ 3 cột, có nút chấp nhận từng thay đổi.

"Current" = HEAD (nhánh bạn đang đứng), "Incoming" = nhánh đang được merge vào. Dù dùng công cụ nào, **luôn đọc kết quả cuối cùng** và chạy build/test trước khi commit — công cụ không biết logic nghiệp vụ.

### `git rebase`

```bash
git switch feature/healthcheck
git rebase main
```

```text
Successfully rebased and updated refs/heads/feature/healthcheck.
```

Khi conflict:

```text
Auto-merging healthcheck.sh
CONFLICT (content): Merge conflict in healthcheck.sh
error: could not apply 7b8c9d0... feat: add disk check
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
hint: You can instead skip this commit: run "git rebase --skip".
hint: To abort and get back to the state before "git rebase", run "git rebase --abort".
```

Rebase phát lại **từng commit một**, nên có thể phải giải quyết conflict nhiều lần (mỗi commit một lần). Giải quyết → `git add` → `git rebase --continue`. **Không** chạy `git commit` trong lúc rebase.

### `git fetch`, `git pull`, `git push`

```bash
git fetch origin
git log --oneline --graph main origin/main
git pull                                   # theo cấu hình pull.rebase
git push -u origin feature/healthcheck     # lần đầu đẩy nhánh, -u đặt upstream
git push                                   # các lần sau
git push --force-with-lease                # sau khi rebase nhánh của riêng bạn
git fetch --prune                          # dọn origin/* của nhánh đã bị xóa trên remote
```

| Tham số | Ý nghĩa |
|---|---|
| `-u` (`--set-upstream`) | Ghi nhớ nhánh remote tương ứng, sau đó chỉ cần `git push` / `git pull` |
| `--force-with-lease` | Ghi đè nhưng từ chối nếu remote có commit bạn chưa thấy |
| `--force` | ⚠️ Ghi đè vô điều kiện — có thể xóa commit của người khác |
| `--prune` | Xóa remote-tracking branch không còn trên remote |

### Xóa nhánh

```bash
git branch -d feature/healthcheck              # local, đã merge
git push origin --delete feature/healthcheck   # trên remote
```

GitHub có thể tự xóa nhánh sau khi PR được merge (bài 03).

### `git cherry-pick`

```bash
git cherry-pick a1b2c3d
git cherry-pick -x a1b2c3d     # thêm dòng "(cherry picked from commit a1b2c3d...)" vào lời nhắn
```

```text
[release/0.3 5e6f7a8] fix: escape user input in task title
 1 file changed, 2 insertions(+), 1 deletion(-)
```

Dùng `-x` khi cherry-pick sang nhánh release để sau này truy được nguồn gốc.

---

## 9. Bài thực hành từng bước

**Lab: Merge, rebase và conflict đầu tiên** · `[WSL]` · ~60 phút

Lab lớn hơn với 3 loại conflict và mô phỏng 2 người làm việc nằm ở [Lab 01](labs/lab-01-conflicts-team-simulation.md) — làm bài này trước. Ghi câu trả lời ❓ vào `~/devops-journey/week06/lab-git-02.md`.

### Bước 1 — Chuẩn bị

```bash
mkdir -p ~/devops-lab/03-git/branching && cd ~/devops-lab/03-git/branching
git init
printf 'server:\n  port: 8080\n  timeout: 30\n' > config.yml
git add . && git commit -m "chore: initial config"
git config alias.lg "log --oneline --graph --all --decorate"
```

### Bước 2 — Fast-forward

```bash
git switch -c feature/readme
echo "# Branching lab" > README.md
git add . && git commit -m "docs: add README"
git switch main
git merge feature/readme
git lg
```

❓ Có merge commit không? Vì sao?

### Bước 3 — 3-way merge

```bash
git switch -c feature/logging
printf 'logging:\n  level: INFO\n' >> config.yml
git commit -am "feat: add logging config"
git switch main
echo "Run with: java -jar app.jar" >> README.md
git commit -am "docs: add run instruction"
git lg
git merge-base main feature/logging
git merge feature/logging -m "Merge branch 'feature/logging'"
git lg
git cat-file -p HEAD | head -4
```

❓ `merge-base` trả commit nào? Merge commit có mấy dòng `parent`?

### Bước 4 — Conflict đầu tiên

```bash
git switch -c fix/timeout
sed -i 's/timeout: 30/timeout: 10/' config.yml
git commit -am "fix: lower timeout to 10s"
git switch main
sed -i 's/timeout: 30/timeout: 60/' config.yml
git commit -am "perf: raise timeout to 60s"
git merge fix/timeout
git status
cat config.yml
```

❓ Chép lại vùng conflict. Phần nào là của `main`, phần nào của `fix/timeout`?

### Bước 5 — Hủy rồi giải quyết thật

```bash
git merge --abort
git status                    # sạch như trước merge
git merge fix/timeout         # conflict lại
nano config.yml               # quyết định: timeout: 45 — xóa hết 3 dòng đánh dấu
git add config.yml
git commit --no-edit
git lg
```

### Bước 6 — Rebase

```bash
git switch -c feature/metrics HEAD~2     # tách nhánh từ một commit cũ hơn
printf 'metrics:\n  enabled: true\n' > metrics.yml
git add . && git commit -m "feat: add metrics config"
git lg
git log --oneline -1                      # ghi lại SHA trước rebase
git rebase main
git log --oneline -1                      # SHA sau rebase
git lg
git switch main && git merge --ff-only feature/metrics
```

❓ SHA của commit `feat: add metrics config` có đổi sau rebase không? Vì sao `merge --ff-only` thành công?

### Bước 7 — Dọn dẹp nhánh

```bash
git branch --merged            # nhánh đã merge vào HEAD
git branch -d feature/readme feature/logging fix/timeout feature/metrics
git branch
```

### Bước 8 — Commit kết quả

```bash
cd ~/devops-journey
git add week06/lab-git-02.md
git commit -m "docs(git): lab 02 - merge, rebase, first conflict"
git push
```

---

## 10. Kết quả mong đợi

- **Bước 2:** Không có merge commit — `main` chưa có commit mới nên chỉ fast-forward.
- **Bước 3:** `merge-base` trả commit `docs: add README` (điểm tách nhánh). Merge commit có **2 dòng `parent`**.
- **Bước 4:**
  ```text
  <<<<<<< HEAD
    timeout: 60
  =======
    timeout: 10
  >>>>>>> fix/timeout
  ```
  Phần trên là `main` (HEAD), phần dưới là `fix/timeout`.
- **Bước 5:** Sau `--abort`, `git status` sạch. Sau khi giải quyết, `config.yml` có `timeout: 45` và không còn ký tự `<<<<<<<`, `=======`, `>>>>>>>`.
- **Bước 6:** SHA **đổi** sau rebase (commit mới có cha khác). `--ff-only` thành công vì sau rebase `feature/metrics` nằm thẳng phía trước `main`.
- **Bước 7:** Cả 4 nhánh xóa được bằng `-d` vì đều đã merge.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Commit lên nhầm `main` thay vì nhánh feature (chưa push) | Quên tạo nhánh | `git switch -c feature/x` (nhánh mới giữ commit), rồi `git switch main && git reset --hard origin/main` ⚠️ |
| Còn sót `<<<<<<<` trong file đã commit | Giải quyết conflict vội | `git grep -n '^<<<<<<<'` trước khi commit; build/test bắt được lỗi cú pháp |
| `git pull` tạo merge commit "Merge branch 'main' of github.com:..." | `pull` mặc định merge khi lịch sử rẽ nhánh | Cấu hình `pull.rebase`; với `main` dùng `git pull --ff-only` |
| `! [rejected] main -> main (non-fast-forward)` | Remote có commit bạn chưa có | `git fetch` → xem → `git pull`, **không** `--force` vào nhánh chung |
| Rebase xong push bị từ chối | Lịch sử nhánh đã đổi | Nếu là nhánh của riêng bạn: `git push --force-with-lease` |
| Đồng nghiệp rebase `main` rồi force push | Vi phạm quy tắc vàng | Bật branch protection. Khôi phục: tìm SHA cũ trong reflog của người còn bản đúng |
| `error: The branch 'x' is not fully merged.` | `-d` từ chối xóa nhánh chưa merge | Kiểm tra lại; chắc chắn mới dùng `-D` |
| Conflict lặp lại ở mỗi commit khi rebase | Nhiều commit cùng sửa vùng conflict | Bình thường. Hoặc squash commit trước, hoặc dùng merge thay rebase |

---

## 12. Đọc thông báo lỗi và xử lý

```text
To github.com:phuong-dev/taskhub.git
 ! [rejected]        main -> main (fetch first)
error: failed to push some refs to 'github.com:phuong-dev/taskhub.git'
hint: Updates were rejected because the remote contains work that you do
hint: not have locally. This is usually caused by another repository pushing
hint: to the same ref. You may want to first integrate the remote changes
hint: (e.g., 'git pull ...') before pushing again.
```

- **Ai từ chối?** Remote (GitHub) — không phải Git trên máy bạn.
- **Vì sao?** Remote có commit bạn chưa có. Push sẽ làm mất chúng nên bị chặn.
- **Làm gì?** `git fetch` → `git log --oneline --graph main origin/main` để **nhìn** trước → `git pull` → giải quyết conflict nếu có → `git push`.

```text
hint: You have divergent branches and need to specify how to reconcile them.
hint: You can do so by running one of the following commands sometime before
hint: your next pull:
hint:
hint:   git config pull.rebase false  # merge
hint:   git config pull.rebase true   # rebase
hint:   git config pull.ff only       # fast-forward only
fatal: Need to specify how to reconcile divergent branches.
```

- Git chưa biết bạn muốn merge hay rebase. Chọn một cấu hình (mục 4.8) rồi chạy lại.

**Quy trình chung khi bối rối giữa merge/rebase:**

1. `git status` — Git đang ở giữa thao tác nào? (dòng `You are currently rebasing`, `You have unmerged paths`)
2. Muốn thoát an toàn: `git merge --abort` / `git rebase --abort` / `git cherry-pick --abort`.
3. Muốn tiếp tục: sửa file → `git add` → `git commit` (merge) hoặc `--continue` (rebase, cherry-pick).
4. Lạc hoàn toàn: `git reflog` — mọi vị trí trước đó của HEAD vẫn ở đó ([bài 01](01-git-fundamentals-internals.md#46--reflog--hộp-đen-của-repo)).

---

## 13. Câu hỏi kiểm tra kiến thức

1. Tổ tiên chung (merge base) là gì? Vì sao gọi là 3-way merge?
2. Khi nào merge là fast-forward? Khi nào tạo merge commit?
3. Merge commit khác commit thường ở điểm nào (gợi ý: `git cat-file -p`)?
4. Rebase làm gì với commit của bạn? Vì sao SHA thay đổi?
5. Phát biểu quy tắc vàng của rebase. Rebase nhánh feature của riêng bạn đã push để mở PR có vi phạm không?
6. Conflict xảy ra trong những trường hợp nào? Hai thay đổi ở hai dòng cách xa nhau trong cùng file có conflict không?
7. Ý nghĩa từng phần của conflict markers? Chiều "ours/theirs" thay đổi thế nào khi rebase?
8. Đang giải quyết conflict thì muốn bỏ cuộc — lệnh nào? Có mất dữ liệu không?
9. `origin/main` là gì? Nó có tự cập nhật không?
10. `fetch` và `pull` khác nhau thế nào? Lệnh nào luôn an toàn?
11. Vì sao nên dùng `--force-with-lease` thay cho `--force`?
12. Cherry-pick dùng khi nào? Vì sao không nên lạm dụng?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/02-solutions.md](solutions/02-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Dự đoán trước khi chạy.** Cho lịch sử: `main` tại B, `feature` tách từ B có C, D; sau đó `main` có thêm E. Vẽ (bằng chữ) đồ thị sau mỗi thao tác: (a) merge `feature` vào `main`; (b) thay vào đó, rebase `feature` lên `main` rồi `merge --ff-only`; (c) squash merge. Sau đó tái hiện bằng repo thật và so sánh với `git lg`.

**Bài 2 — Merge `--no-ff`.** Tạo tình huống fast-forward được, nhưng merge bằng `--no-ff`. So sánh `git lg` với merge thường. Khi nào một nhóm muốn dùng `--no-ff`?

**Bài 3 — Ba cách giải quyết.** Tạo một conflict trong `config.yml`. Giải quyết 3 lần (dùng `--abort` giữa các lần): giữ bên mình, giữ bên kia, kết hợp cả hai thành một cấu hình mới. Lần thứ ba làm bằng VS Code Merge Editor hoặc IntelliJ.

**Bài 4 — Cherry-pick hotfix.** Tạo nhánh `release/0.1` từ một commit cũ. Trên `main` tạo commit sửa lỗi. Mang bản sửa sang `release/0.1` bằng `cherry-pick -x`. So sánh SHA hai commit và giải thích. Điều gì xảy ra nếu sau này merge `release/0.1` vào `main`?

**Bài 5 — Giải cứu commit nhầm nhánh.** Bạn commit 2 lần lên `main` (chưa push), rồi nhận ra đáng lẽ phải ở nhánh `feature/x`. Đưa 2 commit sang `feature/x` và đưa `main` về như cũ. Viết lại chính xác các lệnh và giải thích vì sao an toàn.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ được ba sơ đồ ở mục 6.1 và nói được ưu nhược điểm từng cách.
- [ ] Giải quyết một conflict mới trong dưới 5 phút, không để sót ký tự đánh dấu.
- [ ] Giải thích được cho người khác vì sao không bao giờ rebase `main`.
- [ ] Nhìn `git status` biết ngay đang ở giữa merge, rebase hay không, và lệnh thoát tương ứng.
- [ ] Hoàn thành [Lab 01](labs/lab-01-conflicts-team-simulation.md) không xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Pro Git 3.2 — Basic Branching and Merging](https://git-scm.com/book/en/v2/Git-Branching-Basic-Branching-and-Merging) | Fast-forward, 3-way merge, conflict markers | 2026-10-31 |
| [Pro Git 3.6 — Rebasing](https://git-scm.com/book/en/v2/Git-Branching-Rebasing) | Rebase, quy tắc vàng | 2026-10-31 |
| [Pro Git (mục lục)](https://git-scm.com/book/en/v2) | Chương 3 Git Branching đầy đủ, chương 5 Distributed Git | 2026-10-31 |
| `git help merge`, `git help rebase`, `git help pull` | Tra cứu trên máy | — |
