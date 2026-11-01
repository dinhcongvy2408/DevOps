# Lời giải — Lab 01: Ba loại conflict & mô phỏng làm việc nhóm

> ⚠️ Chỉ đọc sau khi đã tự làm. Đầu ra là **minh họa**; SHA trên máy bạn sẽ khác.

Quay lại lab: [lab-01-conflicts-team-simulation.md](../labs/lab-01-conflicts-team-simulation.md)

## Mục lục

- [Phần A](#phần-a)
- [Phần B — Conflict cùng dòng](#phần-b--conflict-cùng-dòng)
- [Phần C — Modify/delete](#phần-c--modifydelete)
- [Phần D — Conflict khi rebase](#phần-d--conflict-khi-rebase)
- [Phần E — force-with-lease](#phần-e--force-with-lease)
- [Câu hỏi sau lab (mục 11)](#câu-hỏi-sau-lab-mục-11)

---

## Phần A

```text
$ ls remote.git
HEAD  branches  config  description  hooks  info  objects  refs
```

Không có `app.conf`: bare repo chỉ có cơ sở dữ liệu Git (objects, refs), không có working directory. Nội dung file nằm dưới dạng blob nén trong `objects/`.

---

## Phần B — Conflict cùng dòng

Push của Bình:

```text
To /home/phuong/devops-lab/03-git/team/remote.git
 ! [rejected]        main -> main (fetch first)
error: failed to push some refs to '/home/phuong/devops-lab/03-git/team/remote.git'
hint: Updates were rejected because the remote contains work that you do
hint: not have locally. ...
```

Merge:

```text
Auto-merging app.conf
CONFLICT (content): Merge conflict in app.conf
Automatic merge failed; fix conflicts and then commit the result.
```

```text
<<<<<<< HEAD
timeout=60
=======
timeout=10
>>>>>>> origin/main
```

HEAD = commit của Bình (60), `origin/main` = commit của An (10).

`git pull --ff-only` của An thành công vì merge commit của Bình có commit của An là **tổ tiên** — `main` của An chỉ cần dời tới trước.

---

## Phần C — Modify/delete

```text
CONFLICT (modify/delete): legacy.conf deleted in 3c4d5e6 and modified in HEAD.
Version HEAD of legacy.conf left in tree.
Automatic merge failed; fix conflicts and then commit the result.
```

```text
Unmerged paths:
  (use "git add/rm <file>..." as appropriate to mark resolution)
        deleted by them: legacy.conf
```

File **vẫn còn** trong working directory của Bình (phiên bản `retries=5`) — Git để lại để bạn quyết định giữ (`git add`) hay xóa (`git rm`). Không có marker vì không có "hai phiên bản nội dung" để đặt cạnh nhau: một bên là "không có file".

Kết quả sau khi giải quyết theo lab: `app.conf` có thêm `retries=5`, `legacy.conf` không còn, merge commit có lời nhắn giải thích quyết định.

---

## Phần D — Conflict khi rebase

```text
Auto-merging app.conf
CONFLICT (content): Merge conflict in app.conf
error: could not apply 8a9b0c1... feat: enable debug logging
hint: Resolve all conflicts manually, mark them as resolved with
hint: "git add/rm <conflicted_files>", then run "git rebase --continue".
```

```text
<<<<<<< HEAD
log_level=WARN
=======
log_level=DEBUG
>>>>>>> 8a9b0c1 (feat: enable debug logging)
```

- Phần trên (`HEAD`) là `origin/main` — thay đổi của **An**. Trong lúc rebase, HEAD là gốc mới đang được dựng.
- Phần dưới (`8a9b0c1 ...`) là commit **của Bình** đang được phát lại.

Commit thứ hai (`log_format=json`) thường áp dụng sạch vì thêm dòng ở cuối file, cách dòng `log_level` một dòng (`retries=5`). Nếu trên máy bạn nó vẫn conflict, giải quyết tương tự — điều đó cũng đúng.

SHA cả hai commit **đổi** sau rebase. `git push` thường bị từ chối:

```text
 ! [rejected]        feature/debug-logging -> feature/debug-logging (non-fast-forward)
```

vì commit cũ trên remote không còn là tổ tiên của nhánh local. `--force-with-lease` được chấp nhận vì `origin/feature/debug-logging` của Bình khớp với remote (không ai khác đẩy vào nhánh này). Không vi phạm quy tắc vàng: chỉ Bình làm việc trên nhánh đó.

An: `git merge --ff-only origin/feature/debug-logging` thành công vì sau rebase nhánh nằm thẳng phía trước `main`.

---

## Phần E — force-with-lease

```text
To /home/phuong/devops-lab/03-git/team/remote.git
 ! [rejected]        feature/shared -> feature/shared (stale info)
error: failed to push some refs to '/home/phuong/devops-lab/03-git/team/remote.git'
```

`stale info`: `origin/feature/shared` trên máy Bình (vị trí cũ) **không khớp** vị trí thật trên remote (đã có commit của An). Nếu Bình dùng `--force`, remote sẽ trỏ tới commit đã amend của Bình, và commit `feat: enable keepalive` của An **không còn thuộc nhánh nào trên remote** — An chỉ cứu được nếu máy An còn commit đó.

Sau `git fetch` + `git rebase origin/feature/shared`: conflict ở cuối `app.conf` (cả hai cùng thêm dòng ở cuối file). Kết quả hợp lý:

```text
max_connections=100
keepalive=true
```

Rồi `git add app.conf && git rebase --continue && git push` (fast-forward, không cần force).

> Lưu ý: `--force-with-lease` chỉ bảo vệ khi bạn **chưa fetch** sau khi người khác đẩy. Nếu bạn fetch rồi mới force-with-lease mà không xem gì, `origin/*` đã cập nhật nên lệnh vẫn ghi đè. Thói quen đúng: fetch → **nhìn** `git lg` → tích hợp.

---

## Câu hỏi sau lab (mục 11)

**1.** Với `git pull --rebase`, commit của Bình được phát lại lên trên commit của An → lịch sử thẳng `... → An(10s) → Bình(60s→sửa)`, không có merge commit. Conflict vẫn xảy ra (cùng dòng) nhưng giải quyết trong lúc rebase rồi `git rebase --continue`.

**2.** Marker dùng để đặt **hai phiên bản nội dung** cạnh nhau. Ở modify/delete, một phía là "file không tồn tại" — không có nội dung để chèn, nên Git để nguyên file phía còn lại và đánh dấu bằng trạng thái `deleted by them/us`.

**3.** Merge: bạn đứng trên nhánh của mình (HEAD = của bạn) và kéo nhánh kia vào. Rebase: Git checkout gốc mới (HEAD = upstream) rồi phát lại commit của bạn lên trên → commit của bạn trở thành phía "được đưa vào".

**4.** Bare repo không có working directory, chỉ có dữ liệu Git — dùng làm server trung tâm. Push vào nhánh đang được checkout của một repo thường sẽ làm working directory và index bên đó lệch với nhánh (file trên đĩa không còn khớp HEAD); Git mặc định từ chối (`receive.denyCurrentBranch`) để tránh điều này.

**5.** So sánh vị trí remote-tracking branch `origin/<nhánh>` trên máy bạn (lần cuối bạn thấy) với vị trí thật của nhánh trên remote ngay lúc push. Khác nhau → từ chối.
