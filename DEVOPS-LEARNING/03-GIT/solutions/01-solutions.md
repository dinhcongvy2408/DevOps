# Lời giải — Bài 01: Git fundamentals & internals

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [01-git-fundamentals-internals.md](../01-git-fundamentals-internals.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Mỗi commit trỏ tới một tree mô tả **toàn bộ** dự án tại thời điểm đó (file không đổi thì dùng lại blob cũ). Git không lưu "bản vá". `git diff` **tính** khác biệt ngay lúc chạy bằng cách so hai snapshot (hai tree, hoặc tree với index/working directory).

**2.** blob, tree, commit, tag (annotated). Tên file nằm trong **tree** (mỗi dòng của tree: mode, loại, SHA, tên). Blob chỉ chứa nội dung.

**3.** Một blob. SHA được tính từ nội dung (kèm header loại + kích thước) — cùng nội dung → cùng SHA → cùng một object. Hai dòng trong tree với hai tên khác nhau cùng trỏ tới blob đó.

**4.** Branch là một ref: file `.git/refs/heads/<tên>` chứa SHA của commit đầu nhánh (hoặc một dòng trong `packed-refs`). Tạo nhánh chỉ là ghi 41 byte — không chép file nào — nên gần như tức thì.

**5.** HEAD cho biết bạn đang đứng ở đâu. Bình thường `.git/HEAD` chứa `ref: refs/heads/main` (trỏ tới **tên nhánh**). Ở detached HEAD, nó chứa **SHA trần** của một commit.

**6.** Tạo nhánh ngay tại chỗ: `git switch -c save-work` (hoặc `git branch save-work`). Nếu đã lỡ chuyển nhánh: `git reflog` tìm SHA commit cuối cùng làm ở trạng thái detached → `git branch save-work <sha>`.

**7.** `--soft`: chỉ dời nhánh, thay đổi vẫn đã stage. `--mixed` (mặc định): dời nhánh + reset index, thay đổi còn trong file nhưng chưa stage. `--hard`: dời nhánh + reset index + ghi đè working directory. Chỉ `--hard` có thể làm mất dữ liệu **không cứu được** — cụ thể là những thay đổi chưa từng commit (và chưa từng `git add` — blob đã add thì về lý thuyết còn lơ lửng trong objects nhưng rất khó tìm lại).

**8.** `reset` trên commit đã push viết lại lịch sử → phải `push --force` → đồng nghiệp đã có commit cũ bị lệch lịch sử, khi họ push lại có thể đưa commit "đã xóa" quay về hoặc làm mất commit của người khác. `revert` chỉ thêm commit mới, push bình thường, không ai bị ảnh hưởng, và lịch sử ghi rõ việc hoàn tác.

**9.** Reflog ghi mọi lần HEAD/nhánh di chuyển trên máy bạn. Giới hạn: (1) chỉ có ở local, không push/clone được; (2) mục cũ hết hạn và bị `git gc` dọn; (3) không cứu được thay đổi chưa từng commit; (4) clone mới có reflog trống.

**10.** Không. Mặc định chỉ cất file đã được Git theo dõi (tracked). Dùng `git stash -u` (hoặc `--include-untracked`) để cất cả file mới.

**11.** `git log -S "<chuỗi>"` (thêm `-p` để xem diff, thêm `-- <file>` để giới hạn file).

**12.** Lấy SHA ngắn của commit đang build để gắn tag cho Docker image, ghi vào log/artifact → về sau biết chính xác image chứa code của commit nào, và rollback được về đúng commit đó.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Đếm object

```bash
git init count && cd count
echo "hello" > a.txt
git add . && git commit -m "first"
mkdir docs && echo "guide" > docs/guide.md
git add . && git commit -m "second"
find .git/objects -type f | wc -l
```

Dự đoán: **7 object**.

| Commit | Object mới | Số lượng |
|---|---|---|
| first | blob `a.txt`, tree gốc, commit | 3 |
| second | blob `docs/guide.md`, tree `docs/`, tree gốc **mới** (vì có thêm dòng `docs`), commit | 4 |

Blob của `a.txt` không đổi nên **dùng lại**. Tree gốc phải tạo mới vì nội dung danh sách thay đổi. Tổng 7. (Nếu thấy số khác, kiểm tra xem có file nào ngoài `.git/objects/xx/...` bị đếm không — thư mục `info/` và `pack/` trống ở repo mới.)

### Bài 2 — Tự tạo branch bằng tay

```bash
git rev-parse HEAD > .git/refs/heads/manual
git branch
git log --oneline manual
```

Cách chính thống:

```bash
git update-ref refs/heads/manual2 HEAD
```

Vì sao nên dùng `update-ref`: nó kiểm tra SHA hợp lệ, ghi **nguyên tử** (không để file dở dang nếu bị ngắt), ghi vào **reflog**, xử lý đúng khi ref nằm trong `packed-refs`, và hỗ trợ kiểm tra giá trị cũ trước khi ghi (`git update-ref <ref> <mới> <cũ>`). Sửa file tay bỏ qua tất cả những điều này.

### Bài 3 — Undo đúng cách

| Tình huống | Lệnh | Lý do |
|---|---|---|
| (a) Quên thêm 1 file, chưa push | `git add file && git commit --amend --no-edit` | Amend thay commit cuối bằng commit mới — an toàn vì chưa chia sẻ |
| (b) Commit nhầm `.env`, chưa push | `git rm --cached .env`, thêm `.env` vào `.gitignore`, `git commit --amend` (hoặc `git reset --soft HEAD~1` rồi commit lại) | File không còn trong lịch sử trước khi rời máy. Kiểm tra `git show --stat HEAD` |
| (c) Commit lỗi đã push 2 ngày, nhiều người đã pull | `git revert <sha>` rồi `git push` | Không viết lại lịch sử chung |
| (d) `git add .` nhầm file log lớn, chưa commit | `git restore --staged app.log` (+ thêm `*.log` vào `.gitignore`) | Chỉ bỏ khỏi index, file vẫn còn |
| (e) Commit `.env` và **đã push public** | **Coi mật khẩu đã lộ: xoay vòng (rotate) ngay mọi secret trong file**. Sau đó xóa khỏi repo (commit mới, hoặc viết lại lịch sử theo hướng dẫn GitHub nếu cần) | Bot quét GitHub liên tục; xóa commit không thu hồi được bản đã bị sao chép. Xem bài ôn tập Git, mục về secret |

### Bài 4 — Điều tra

Không có đáp án duy nhất. Đạt khi bạn có: dòng được chọn, lệnh dùng (ví dụ `git blame -L 120,125 Java.gitignore`, `git log -S "*.class" --oneline -- Java.gitignore`, `git show <sha>`), SHA, ngày, và tóm tắt lý do lấy từ lời nhắn commit/PR. Điểm cộng nếu bạn phát hiện `git blame` chỉ ra commit **sửa cuối cùng** dòng đó, chưa chắc là commit **tạo ra** dòng đó — muốn tìm commit tạo ra thì dùng `git log -S` hoặc `git blame <sha>^ -- file` để lùi tiếp.

### Bài 5 — Reflog có giới hạn

Ví dụ thí nghiệm:

```bash
echo "important work" >> notes.txt     # file đã được theo dõi, sửa nhưng KHÔNG add, KHÔNG commit
git reset --hard HEAD
git reflog                              # không có mục nào chứa thay đổi này
```

Thay đổi chưa từng thành object (chưa `add`, chưa `commit`) nên không có gì để reflog trỏ tới — mất vĩnh viễn. Các biến thể đúng khác: clone repo sang thư mục mới rồi thấy reflog trống; hoặc chạy `git reflog expire --expire=now --all && git gc --prune=now` ⚠️ rồi thấy commit "mất" không còn cứu được.
