# Lời giải — Bài 03: GitHub, Pull Request & Code Review

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [03-github-pull-request-code-review.md](../03-github-pull-request-code-review.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Của GitHub (và các nền tảng tương tự), không phải của Git. GitLab gọi là **Merge Request**.

**2.** Branch trong cùng repo khi bạn có quyền ghi (thành viên team, repo của mình). Fork khi đóng góp cho repo mà bạn không có quyền ghi — thường là mã nguồn mở.

**3.** Tạo nhánh → commit & push → mở PR → trả lời review (push thêm commit) → merge → xóa nhánh.

**4.** Thay đổi gì? Vì sao (liên kết issue)? Kiểm tra thế nào? Rủi ro/ảnh hưởng (migration, biến môi trường mới…)?

**5.** Merge commit giữ mọi commit + thêm merge commit; squash gộp cả PR thành một commit mới; rebase viết lại từng commit lên đầu `main`, lịch sử thẳng. `taskhub` chọn **squash**: 1 PR = 1 commit trên `main`, dễ đọc và dễ `revert` cả tính năng; được commit tự do trên nhánh; title PR (theo Conventional Commits) trở thành title commit.

**6.** Squash tạo một commit **mới** có SHA khác; các commit gốc của nhánh không nằm trong lịch sử `main`, nên Git kết luận nhánh "chưa được merge". Không nguy hiểm **nếu** bạn đã xác nhận PR ở trạng thái *Merged* trên GitHub — lúc đó `git branch -D` an toàn.

**7.** Các commit cũ của nhánh (đã bị gộp thành commit squash với SHA khác) vẫn còn trên nhánh. PR mới từ nhánh đó sẽ mang lại các commit này, Git coi chúng là thay đổi chưa có ở `main` → diff lặp, conflict lặp đi lặp lại. Merge xong thì xóa nhánh, tạo nhánh mới từ `main`.

**8.** GitHub không cho tác giả tự approve PR của mình; repo một người đặt 1 approval sẽ không merge được. Bật bắt buộc PR vẫn đảm bảo: mọi thay đổi có diff để tự review, có mô tả và lịch sử, và từ tuần 9 có CI chạy và chặn trước khi merge.

**9.** Mặc định người có quyền admin **được bỏ qua** luật bảo vệ nhánh. Repo của bạn → bạn là admin → luật vô dụng với chính bạn. Bật tùy chọn này để luật áp dụng cho cả admin.

**10.** Đúng, dễ hiểu, test, bảo mật, vận hành, phạm vi. Với DevOps, **bảo mật** và **vận hành** quan trọng nhất: secret bị lộ hay port mở rộng là sự cố thật, còn thiếu cập nhật README/biến môi trường sẽ làm deploy thất bại.

**11.** Ví dụ: "blocking: khi `title` rỗng, `POST /api/tasks` đang trả 500 (NullPointerException trong `TaskService.create`). Đặc tả yêu cầu 400. Đề xuất thêm `@NotBlank` cho `title` và `@Valid` ở controller, kèm một test cho trường hợp này. Bạn thấy sao?" — Có mức độ, mô tả hiện tượng, chỉ ra kỳ vọng, đề xuất cụ thể, giọng hợp tác.

**12.** `Closes #8` (hoặc `Fixes #8`, `Resolves #8`…) trong mô tả PR. Không tự đóng nếu PR không nhắm vào nhánh mặc định, nếu từ khóa chỉ nằm trong một comment, hoặc viết sai cú pháp.

**13.** `git diff main...HEAD` so sánh `HEAD` với **điểm rẽ nhánh chung** của hai nhánh → chỉ những thay đổi của nhánh bạn (đúng như PR). `git diff main HEAD` so sánh trực tiếp hai đầu nhánh → nếu `main` đã có commit mới, diff sẽ lẫn cả các thay đổi đó (hiện như thể bạn đang "xóa" chúng).

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Đọc lịch sử

`main` chỉ nhận commit qua **squash merge** — mỗi PR thành một commit nằm thẳng trên đầu `main` (fast-forward). Không có merge commit nên không có điểm gộp hai nhánh → đồ thị là một đường thẳng. Các nhánh làm việc đã bị xóa, commit gốc của chúng không thuộc lịch sử `main`.

### Bài 2 — So sánh kiểu merge

```bash
mkdir -p ~/devops-lab/03-git/merge-styles && cd ~/devops-lab/03-git/merge-styles
git init -b main && echo base > f.txt && git add f.txt && git commit -m "base"
for n in 1 2 3; do
  git switch -c b$n main
  for c in A B C; do echo "$n$c" >> f$n.txt; git add f$n.txt; git commit -m "b$n: $c"; done
done
git switch main

git merge --no-ff b1 -m "Merge b1"                 # kiểu merge commit
git merge --squash b2 && git commit -m "b2 squashed" # kiểu squash
git switch b3 && git rebase main && git switch main && git merge --ff-only b3   # kiểu rebase
git log --oneline --graph
```

Kết quả (rút gọn, minh họa):

```text
* 7d1f0aa b3: C
* 6c2e9b1 b3: B
* 5a3d8c2 b3: A          ← rebase: 3 commit được viết lại, nằm thẳng
* 4b4c7d3 b2 squashed     ← squash: 1 commit duy nhất
*   3c5b6e4 Merge b1      ← merge commit
|\
| * 2d6a5f5 b1: C
| * 1e7f4a6 b1: B
| * 0f8e3b7 b1: A
|/
* 9a9d2c8 base
```

Khớp với sơ đồ mục 6.2. Lưu ý `git branch -d b2` sẽ báo "not fully merged" — đúng hiện tượng đã học.

### Bài 3 — Review một PR có vấn đề

Ít nhất các comment sau:

1. **blocking (bảo mật):** `spring.datasource.password=postgres123` — mật khẩu trong code. Phải lấy từ biến môi trường `SPRING_DATASOURCE_PASSWORD` (đặc tả tuần 6). Mật khẩu này đã nằm trong lịch sử PR → nếu là mật khẩu thật thì phải đổi.
2. **blocking (bảo mật/least privilege):** `username=postgres` — ứng dụng dùng superuser. Đặc tả yêu cầu user `taskhub` riêng.
3. **blocking (đúng đặc tả):** `ddl-auto=update` — đặc tả yêu cầu quản lý schema bằng Flyway; `update` trên production có thể thay đổi schema không kiểm soát. Đề xuất `validate` hoặc `none`.
4. **blocking (bảo mật):** `management.endpoints.web.exposure.include=*` — công khai mọi endpoint Actuator (env, heapdump…) có thể lộ thông tin nhạy cảm. Chỉ để `health,info`.
5. **blocking (mạng):** `ports: "5432:5432"` trong `compose.yaml` — publish PostgreSQL ra mọi interface của máy. Không cần publish (app nói chuyện qua mạng nội bộ Docker); nếu cần debug thì giới hạn `127.0.0.1:5432:5432` (liên hệ bind address ở Networking bài 05).
6. **question:** URL `localhost:5432` — khi chạy trong container, `localhost` là chính container app, không phải PostgreSQL. Có định ghi đè bằng biến môi trường không? (Module 04 giải thích.)

### Bài 4 — Issue template

Tham khảo GitHub Docs mục *Configuring issue templates for your repository* (bạn tự tìm và ghi link). Một template Markdown có phần front matter:

```markdown
---
name: Bug report
about: Báo lỗi của taskhub
labels: bug
---

## Phiên bản
<!-- Tag đang chạy, ví dụ v0.2.0 -->

## Các bước tái hiện
1.
2.

## Kết quả mong đợi

## Kết quả thực tế

## Log liên quan
```

Đạt khi: file ở `.github/ISSUE_TEMPLATE/bug_report.md`, vào `main` qua PR, khi bấm *New issue* xuất hiện lựa chọn "Bug report".

### Bài 5 — Mô phỏng hai người

- Tài khoản A **không** approve được PR của chính mình — giao diện review không cho chọn *Approve* (hoặc báo tác giả không thể approve PR của mình).
- Trước khi B approve, hộp merge báo cần ít nhất 1 approving review (*Review required* / *Merging is blocked*).
- Sau khi B chọn *Approve*, nút merge mở.
- Nếu A push thêm commit sau khi B đã approve và bật *Dismiss stale pull request approvals when new commits are pushed*, approval cũ bị hủy, cần B duyệt lại — cách đảm bảo thứ được duyệt chính là thứ được merge.
