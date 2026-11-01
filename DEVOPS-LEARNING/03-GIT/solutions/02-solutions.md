# Lời giải — Bài 02: Branching, merging & conflicts

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [02-branching-merging-conflicts.md](../02-branching-merging-conflicts.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Merge base là commit gần nhất có trong lịch sử của cả hai nhánh. "3-way" vì Git dùng 3 snapshot: merge base, đầu nhánh hiện tại, đầu nhánh được merge — so từng bên với gốc chung để biết bên nào đã thay đổi gì.

**2.** Fast-forward khi nhánh hiện tại **không có commit mới** kể từ merge base (tức nhánh hiện tại chính là tổ tiên của nhánh kia) — Git chỉ dời con trỏ. Khi cả hai bên đều có commit mới (rẽ nhánh) thì tạo merge commit (hoặc khi dùng `--no-ff`).

**3.** Merge commit có **từ 2 cha trở lên** (2 dòng `parent` trong `git cat-file -p`). Commit thường có đúng 1 cha (commit đầu tiên có 0).

**4.** Rebase lấy từng commit của nhánh bạn (kể từ merge base), tính thay đổi của nó, rồi áp dụng lại lên gốc mới, tạo commit mới. SHA đổi vì commit object chứa SHA của cha (và thời điểm committer) — cha đổi thì nội dung object đổi → hash đổi.

**5.** "Không rebase commit đã tồn tại ngoài repo của bạn mà người khác có thể đã dựa vào." Rebase nhánh feature **chỉ mình bạn làm** dù đã push để mở PR thường **không** vi phạm, miễn là không ai khác đã lấy nhánh đó về làm tiếp; sau đó cần `push --force-with-lease`.

**6.** Khi cả hai bên sửa cùng vùng (cùng dòng hoặc các dòng liền kề) của cùng file so với merge base; khi một bên sửa, bên kia xóa file; khi cả hai tạo file cùng tên khác nội dung. Hai thay đổi ở hai dòng **cách xa nhau** → Git tự merge, không conflict.

**7.** `<<<<<<< X` đến `=======`: phiên bản của X (khi merge, X = HEAD = nhánh bạn đang đứng). `=======` đến `>>>>>>> Y`: phiên bản của Y (nhánh/commit đang được đưa vào). Khi **rebase**, HEAD là gốc mới (ví dụ `origin/main`) đang được dựng dần, còn commit của bạn là thứ "đang được đưa vào" → phần của bạn nằm **dưới** `=======`. Ours/theirs đảo ngược so với cảm giác.

**8.** `git merge --abort` (hoặc `git rebase --abort`, `git cherry-pick --abort`). Không mất gì: trở về đúng trạng thái trước khi bắt đầu. (Lưu ý: nên bắt đầu merge khi working directory sạch; nếu có thay đổi chưa commit lẫn vào, `--abort` có thể không khôi phục hoàn hảo — đó là lý do Git thường từ chối merge khi có thay đổi đè lên file liên quan.)

**9.** `origin/main` là remote-tracking branch: bản sao chỉ đọc vị trí của `main` trên remote **tại lần fetch/pull/push gần nhất**. Không tự cập nhật — chỉ thay đổi khi bạn `fetch`, `pull`, hoặc `push`.

**10.** `fetch` chỉ tải dữ liệu và cập nhật `origin/*`; không đụng nhánh local hay file → luôn an toàn. `pull` = `fetch` + merge (hoặc rebase) vào nhánh hiện tại → có thể tạo merge commit hoặc conflict.

**11.** `--force` ghi đè vô điều kiện, có thể xóa commit người khác vừa đẩy. `--force-with-lease` chỉ ghi đè nếu nhánh trên remote vẫn ở đúng vị trí mà `origin/<nhánh>` của bạn ghi nhận; nếu ai đó đã đẩy thêm, lệnh từ chối (`stale info`).

**12.** Khi cần mang **một** thay đổi cụ thể (thường là hotfix) sang nhánh khác (ví dụ nhánh release đang chạy production) mà không muốn merge cả nhánh. Lạm dụng làm cùng một thay đổi tồn tại dưới nhiều SHA, lịch sử khó đọc, dễ conflict khi về sau merge các nhánh với nhau.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Dự đoán trước khi chạy

```text
Ban đầu:        C ── D        ← feature
               /
      A ── B ── E             ← main

(a) merge:      C ── D
               /      \
      A ── B ── E ──── M      ← main   (M: cha là E và D)

(b) rebase + ff:
      A ── B ── E ── C' ── D'  ← main, feature

(c) squash merge (git merge --squash feature && git commit):
      A ── B ── E ── S        ← main   (feature vẫn trỏ tới D, không liên quan lịch sử main)
```

Lệnh tái hiện (c): `git switch main && git merge --squash feature && git commit -m "feat: ..."`. Lưu ý sau squash, `git branch -d feature` sẽ báo "not fully merged" vì Git không thấy C, D trong lịch sử `main` — phải dùng `-D`. GitHub cũng hành xử tương tự, đó là lý do nên bật tự xóa nhánh sau khi merge PR.

### Bài 2 — Merge `--no-ff`

```bash
git switch -c feature/x && echo x > x.txt && git add . && git commit -m "feat: x"
git switch main && git merge --no-ff feature/x -m "Merge branch 'feature/x'"
git lg
```

Có một merge commit dù fast-forward được, và đồ thị cho thấy rõ "bong bóng" của nhánh. Nhóm dùng `--no-ff` khi muốn lịch sử `main` ghi lại **ranh giới của từng tính năng** (dễ revert cả tính năng bằng `git revert -m 1 <merge-commit>`). Nhóm ưu tiên lịch sử thẳng thì chọn rebase/squash.

### Bài 3 — Ba cách giải quyết

Đạt khi cả ba lần: file cuối không còn marker, `git log` có merge commit, và bạn ghi lại được lần nào chọn gì và vì sao. Với lần dùng IDE: VS Code "Accept Current" = giữ HEAD, "Accept Incoming" = giữ nhánh đang merge vào, "Accept Both" = giữ cả hai (thường phải sửa tay tiếp để file hợp lệ, ví dụ YAML không được có hai khóa `timeout`).

### Bài 4 — Cherry-pick hotfix

```bash
git switch -c release/0.1 HEAD~3
git switch main
echo "escape=true" >> config.yml && git commit -am "fix: escape input"
git switch release/0.1
git cherry-pick -x main
git log -1
```

Hai commit có **SHA khác nhau** (cha khác, committer time khác, lời nhắn có thêm dòng `cherry picked from commit ...`) dù **thay đổi** giống nhau. Nếu sau này merge `release/0.1` vào `main`: Git thường tự nhận ra hai bên có cùng thay đổi và merge sạch (cùng nội dung dòng); nhưng nếu một bên đã sửa tiếp vùng đó, có thể conflict. Lịch sử sẽ có "cùng một sửa lỗi" xuất hiện hai lần — đó là cái giá của cherry-pick.

### Bài 5 — Giải cứu commit nhầm nhánh

```bash
git switch -c feature/x          # nhánh mới trỏ tới commit hiện tại → 2 commit được giữ ở đây
git switch main
git reset --hard origin/main     # ⚠️ đưa main về đúng như remote (2 commit vẫn an toàn ở feature/x)
git log --oneline --graph --all
```

An toàn vì: (1) tạo nhánh trước — 2 commit đã có ref giữ; (2) commit chưa push nên reset `main` không ảnh hưởng ai; (3) nếu sai, reflog vẫn còn. Nếu không có remote, thay `origin/main` bằng `HEAD~2`. Kiểm tra `git status` sạch trước khi `reset --hard`.
