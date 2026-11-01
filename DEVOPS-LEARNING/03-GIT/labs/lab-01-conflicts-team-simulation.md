# Lab 01 — Ba loại conflict & mô phỏng làm việc nhóm

> ⏱️ ~2 giờ · Tuần 6 · Mức độ: 🟥 Bắt buộc · Môi trường: `[WSL]`
> Kiến thức cần có trước: [01. Git internals](../01-git-fundamentals-internals.md), [02. Branching, merging & conflicts](../02-branching-merging-conflicts.md)

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Bối cảnh](#2-bối-cảnh)
- [3. Sơ đồ](#3-sơ-đồ)
- [4. Phần A — Dựng "GitHub giả" và hai đồng nghiệp](#4-phần-a--dựng-github-giả-và-hai-đồng-nghiệp)
- [5. Phần B — Conflict loại 1: cùng dòng, sửa khác nhau](#5-phần-b--conflict-loại-1-cùng-dòng-sửa-khác-nhau)
- [6. Phần C — Conflict loại 2: một bên sửa, một bên xóa](#6-phần-c--conflict-loại-2-một-bên-sửa-một-bên-xóa)
- [7. Phần D — Conflict loại 3: conflict khi rebase](#7-phần-d--conflict-loại-3-conflict-khi-rebase)
- [8. Phần E — Push bị từ chối và force-with-lease](#8-phần-e--push-bị-từ-chối-và-force-with-lease)
- [9. Kết quả mong đợi](#9-kết-quả-mong-đợi)
- [10. Lỗi thường gặp](#10-lỗi-thường-gặp)
- [11. Câu hỏi sau lab](#11-câu-hỏi-sau-lab)
- [12. Dọn dẹp](#12-dọn-dẹp)

Lời giải: [../solutions/lab-01-solutions.md](../solutions/lab-01-solutions.md) — chỉ mở sau khi đã tự làm.

---

## 1. Mục tiêu

- Tự tạo và giải quyết **3 loại conflict** hay gặp nhất: nội dung (cùng dòng), modify/delete, và conflict trong lúc rebase.
- Trải nghiệm cảm giác **làm việc nhóm thật**: hai người cùng đẩy lên một remote, bị từ chối push, phải fetch và tích hợp.
- Không cần GitHub: dùng một **bare repository** (kho trần) trên chính máy bạn làm "server".

**Bare repository** là repo **không có working directory** — chỉ có phần dữ liệu (nội dung thường nằm trong `.git/`). GitHub lưu repo của bạn dưới dạng này. Bạn không sửa file trực tiếp trong đó, chỉ `push` và `fetch` tới nó.

---

## 2. Bối cảnh

Bạn đóng **cả hai vai**: **An** (thư mục `an/`) và **Bình** (thư mục `binh/`), cùng làm dự án cấu hình cho một dịch vụ. "GitHub" là thư mục `remote.git`. Mỗi lần đổi vai, bạn chỉ cần `cd` sang thư mục của người kia.

Để dễ theo dõi, mỗi người cấu hình tên tác giả riêng **chỉ trong repo đó** (không đổi cấu hình global của bạn).

---

## 3. Sơ đồ

```text
                 ~/devops-lab/03-git/team/
                ┌──────────────────────────┐
                │ remote.git  (bare repo)  │  ← đóng vai GitHub
                └─────▲──────────────▲─────┘
             push/fetch│              │push/fetch
        ┌──────────────┴───┐   ┌──────┴───────────┐
        │ an/   (clone)    │   │ binh/  (clone)   │
        │ user.name = An   │   │ user.name = Binh │
        └──────────────────┘   └──────────────────┘
```

---

## 4. Phần A — Dựng "GitHub giả" và hai đồng nghiệp

```bash
mkdir -p ~/devops-lab/03-git/team && cd ~/devops-lab/03-git/team
git init --bare --initial-branch=main remote.git
ls remote.git
```

`--initial-branch=main` đặt nhánh mặc định của remote là `main` (có từ Git 2.28; Ubuntu 24.04 có Git 2.43).

An khởi tạo dự án:

```bash
git clone remote.git an
cd an
git config user.name "An"
git config user.email "an@example.com"
cat > app.conf <<'EOF'
# taskhub service config
port=8080
timeout=30
log_level=INFO
EOF
cat > legacy.conf <<'EOF'
# old settings, still used by deploy script
retries=3
EOF
git add . && git commit -m "chore: initial service config"
git push -u origin main
```

Bình clone về:

```bash
cd ~/devops-lab/03-git/team
git clone remote.git binh
cd binh
git config user.name "Binh"
git config user.email "binh@example.com"
git log --oneline
```

❓ Ghi lại: `ls remote.git` có thư mục nào? Có file `app.conf` trong `remote.git` không? Vì sao?

> Gợi ý theo dõi: mở **hai terminal**, một cho An, một cho Bình. Alias đồ thị: `git config --global alias.lg "log --oneline --graph --all --decorate"` (nếu chưa tạo ở bài 02).

---

## 5. Phần B — Conflict loại 1: cùng dòng, sửa khác nhau

**An** giảm timeout và đẩy lên trước:

```bash
cd ~/devops-lab/03-git/team/an
sed -i 's/^timeout=30/timeout=10/' app.conf
git commit -am "fix: lower timeout to 10s to fail fast"
git push
```

**Bình** (chưa biết An đã đẩy) tăng timeout:

```bash
cd ~/devops-lab/03-git/team/binh
sed -i 's/^timeout=30/timeout=60/' app.conf
git commit -am "perf: raise timeout to 60s for slow reports"
git push
```

❓ Lệnh `git push` của Bình báo gì? Chép nguyên văn.

Bình tích hợp thay đổi của An bằng **merge**:

```bash
git fetch
git lg
git merge origin/main
git status
cat app.conf
```

Giải quyết: sau khi "trao đổi" với An, hai người thống nhất `timeout=30` nhưng thêm `report_timeout=60` cho báo cáo chậm. Sửa `app.conf` thành:

```text
# taskhub service config
port=8080
timeout=30
report_timeout=60
log_level=INFO
```

```bash
git grep -n -E '^(<<<<<<<|=======|>>>>>>>)' && echo "CÒN SÓT MARKER!" || echo "OK, sạch marker"
git add app.conf
git commit --no-edit
git push
git lg
```

**An** cập nhật:

```bash
cd ~/devops-lab/03-git/team/an
git pull --ff-only
cat app.conf
```

❓ Vì sao `git pull --ff-only` của An thành công mà không cần merge?

---

## 6. Phần C — Conflict loại 2: một bên sửa, một bên xóa

**An** dọn dẹp, xóa file cũ:

```bash
cd ~/devops-lab/03-git/team/an
git rm legacy.conf
git commit -m "chore: remove legacy.conf (no longer used)"
git push
```

**Bình** (chưa pull) sửa file đó:

```bash
cd ~/devops-lab/03-git/team/binh
sed -i 's/^retries=3/retries=5/' legacy.conf
git commit -am "fix: increase retries for flaky network"
git pull --no-rebase
git status
```

❓ `git status` ghi nhãn gì cho `legacy.conf`? File đó còn trong thư mục làm việc của Bình không?

Tình huống: Bình kiểm tra lại và thấy script deploy **vẫn còn dùng** `retries`. Quyết định: **không** xóa file, mà chuyển `retries=5` vào `app.conf` rồi mới xóa `legacy.conf`.

```bash
echo "retries=5" >> app.conf
git rm legacy.conf
git add app.conf
git status
git commit -m "Merge origin/main: move retries into app.conf, drop legacy.conf"
git push
git lg
```

> Nếu quyết định ngược lại — **giữ** file — thì thay `git rm legacy.conf` bằng `git add legacy.conf`. Điều quan trọng: đây là **quyết định nghiệp vụ** (script nào còn dùng file?), không phải thao tác cơ học.

---

## 7. Phần D — Conflict loại 3: conflict khi rebase

Lần này Bình làm việc trên **nhánh feature của riêng mình** và cập nhật bằng **rebase** trước khi "mở PR".

**Bình** tạo nhánh từ `main` hiện tại, làm 2 commit và đẩy nhánh lên:

```bash
cd ~/devops-lab/03-git/team/binh
git pull --ff-only
git switch -c feature/debug-logging
sed -i 's/^log_level=INFO/log_level=DEBUG/' app.conf
git commit -am "feat: enable debug logging"
echo "log_format=json" >> app.conf
git commit -am "feat: structured json logs"
git push -u origin feature/debug-logging
```

Trong lúc đó **An** cập nhật và đổi log level ngay trên `main`:

```bash
cd ~/devops-lab/03-git/team/an
git pull --ff-only
sed -i 's/^log_level=INFO/log_level=WARN/' app.conf
git commit -am "chore: reduce log noise in production"
git push
```

Quay lại **Bình** và xem đồ thị:

```bash
cd ~/devops-lab/03-git/team/binh
git fetch
git lg
```

Bình rebase nhánh của mình lên `main` mới nhất:

```bash
git log --oneline -2                # ghi lại 2 SHA trước rebase
git rebase origin/main
git status
cat app.conf
```

❓ Trong vùng conflict, phần nằm dưới `<<<<<<<` là của ai (An hay Bình)? Đọc kỹ nhãn bên cạnh marker.

Giải quyết: Bình chấp nhận `WARN` cho production (ý của An) — debug chỉ bật bằng biến môi trường lúc chạy, không ghi cứng vào file.

```bash
nano app.conf                       # giữ log_level=WARN, xóa 3 dòng marker
git add app.conf
git rebase --continue
```

Nếu commit thứ hai cũng conflict, lặp lại: sửa → `git add` → `git rebase --continue`.

> Khi rebase dừng giữa chừng, Git có thể mở editor để bạn xác nhận lời nhắn commit — lưu và thoát là được (nano: `Ctrl+O`, `Enter`, `Ctrl+X`).

```bash
git log --oneline -3                # so SHA với trước rebase
git lg
git push                            # bị từ chối — vì sao?
git push --force-with-lease
```

❓ Ghi lại: SHA của 2 commit trên nhánh có đổi không? Vì sao `git push` thường bị từ chối, còn `--force-with-lease` thì được? Rebase nhánh này có vi phạm quy tắc vàng không?

**An** "duyệt PR" và merge vào `main`:

```bash
cd ~/devops-lab/03-git/team/an
git fetch
git lg
git merge --ff-only origin/feature/debug-logging
git push
git push origin --delete feature/debug-logging
```

---

## 8. Phần E — Push bị từ chối và force-with-lease

Phần này cho thấy vì sao `--force-with-lease` an toàn hơn `--force`.

**Bình** tạo nhánh dùng chung tạm thời với An:

```bash
cd ~/devops-lab/03-git/team/binh
git switch main && git pull --ff-only
git switch -c feature/shared
echo "max_connections=50" >> app.conf
git commit -am "feat: add max_connections"
git push -u origin feature/shared
```

**An** cũng thêm một commit vào nhánh đó:

```bash
cd ~/devops-lab/03-git/team/an
git fetch
git switch feature/shared
echo "keepalive=true" >> app.conf
git commit -am "feat: enable keepalive"
git push
```

**Bình** (chưa fetch) sửa lại commit của mình rồi cố ghi đè:

```bash
cd ~/devops-lab/03-git/team/binh
sed -i 's/max_connections=50/max_connections=100/' app.conf
git commit --amend -am "feat: add max_connections (100)"
git push --force-with-lease
```

❓ `--force-with-lease` báo gì? Nếu Bình dùng `git push --force` thì commit của An sẽ ra sao?

Cách đúng: Bình fetch, xem An đã làm gì, tích hợp, rồi mới đẩy:

```bash
git fetch
git lg
git rebase origin/feature/shared       # giải quyết conflict nếu có
git push                                # giờ là fast-forward → push thường được
```

---

## 9. Kết quả mong đợi

- **Phần A:** `remote.git` chứa `HEAD`, `config`, `objects/`, `refs/`… — giống nội dung `.git/` — và **không có** `app.conf` vì bare repo không có working directory.
- **Phần B:** Push của Bình bị từ chối `! [rejected] main -> main (fetch first)`. Sau merge, `app.conf` có `timeout=30` và `report_timeout=60`. Pull của An là fast-forward vì merge commit của Bình đã chứa sẵn commit của An.
- **Phần C:** Nhãn `deleted by them: legacy.conf`; file **vẫn còn** trong thư mục của Bình (phiên bản đã sửa) để Bình quyết định.
- **Phần D:** Trong lúc rebase, phần dưới `<<<<<<<` (nhãn `HEAD` hoặc SHA của `origin/main`) là của **An**; phần trên `>>>>>>>` (nhãn là commit của Bình) là của **Bình**. SHA của 2 commit **đổi** sau rebase. `git push` thường bị từ chối vì lịch sử nhánh trên remote không còn là tổ tiên của nhánh local. Không vi phạm quy tắc vàng vì nhánh chỉ Bình làm việc.
- **Phần E:** `--force-with-lease` báo `! [rejected] feature/shared -> feature/shared (stale info)` — remote có commit Bình chưa thấy. Nếu dùng `--force`, commit `feat: enable keepalive` của An **biến khỏi nhánh trên remote**.

---

## 10. Lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `fatal: ... does not appear to be a git repository` khi clone | Sai đường dẫn tới `remote.git` | Chạy clone từ thư mục `team/`, kiểm tra `ls` |
| Commit hiện tác giả là bạn thay vì An/Bình | Quên `git config user.name` trong repo đó | Cấu hình lại; sửa commit cuối: `git commit --amend --reset-author --no-edit` |
| `warning: You did not specify ... initial branch` hoặc nhánh tên `master` | Git cũ hoặc thiếu `--initial-branch` | Tạo lại remote với `--initial-branch=main` |
| Editor mở ra khi `git pull` / `git merge` | Git cần lời nhắn cho merge commit | Lưu và thoát; hoặc dùng `--no-edit` |
| Quên `git add` sau khi sửa conflict, chạy `git rebase --continue` | Git chưa biết file đã giải quyết | Thông báo sẽ nhắc: `git add` rồi `--continue` |
| Lỡ `git commit` trong lúc rebase | Thói quen | Không sao: commit đó được tính vào rebase. `git rebase --continue` tiếp. Nếu rối: `git rebase --abort` và làm lại |

---

## 11. Câu hỏi sau lab

1. Trong Phần B, nếu Bình dùng `git pull --rebase` thay vì `fetch` + `merge`, đồ thị lịch sử sẽ khác thế nào?
2. Vì sao conflict modify/delete không có marker `<<<<<<<` trong file?
3. Vì sao trong Phần D ours/theirs "đảo ngược" so với Phần B?
4. Bare repo khác repo thường thế nào? Vì sao không nên `push` vào nhánh đang được checkout của một repo thường?
5. Trong Phần E, `--force-with-lease` dựa vào thông tin nào để biết "remote đã thay đổi"?

---

## 12. Dọn dẹp

```bash
cd ~/devops-lab/03-git
rm -rf team        # ⚠️ xóa toàn bộ lab — chỉ chạy khi đã ghi xong câu trả lời
```

Ghi câu trả lời các câu ❓ và mục 11 vào `~/devops-journey/week06/lab-01-conflicts.md`, rồi commit:

```bash
cd ~/devops-journey
git add week06/lab-01-conflicts.md
git commit -m "docs(git): lab 01 - conflicts and team simulation"
git push
```
