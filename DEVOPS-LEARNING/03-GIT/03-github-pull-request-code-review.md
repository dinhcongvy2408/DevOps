# 03. GitHub, Pull Request & Code Review

> ⏱️ ~3 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [00. Ôn tập Git nhanh](00-git-quick-review.md), [02. Branching, merging & conflict](02-branching-merging-conflicts.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + trình duyệt (GitHub) · Repo thực hành: `taskhub` (public)

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

- Phân biệt **fork** và **branch**, biết khi nào dùng cái nào.
- Đi trọn **vòng đời một Pull Request**: tạo nhánh → push → mở PR → review → sửa → merge → xóa nhánh.
- Viết **mô tả PR** đủ để người khác review mà không cần hỏi lại, và tạo **PR template** cho repo.
- Giải thích 3 kiểu merge trên GitHub (**merge commit**, **squash**, **rebase**) và lý do `taskhub` chọn **squash**.
- Review code của người khác (và của chính mình) theo một checklist, viết comment lịch sự và cụ thể.
- Bật **bảo vệ nhánh `main`** để mọi thay đổi phải đi qua Pull Request.
- Liên kết Issue với PR để Issue tự đóng khi merge.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Pull Request không chỉ là việc của developer. Với DevOps, PR là **cửa kiểm soát** của mọi thay đổi — kể cả thay đổi hạ tầng:

| Tình huống thật | Liên quan đến PR thế nào |
|---|---|
| Sửa Terraform để mở thêm port trên Security Group | Đồng nghiệp review PR, phát hiện bạn mở `0.0.0.0/0` cho port 5432 trước khi nó lên production |
| Pipeline CI chạy test và quét lỗ hổng | CI chạy **trên mỗi PR**; branch protection chặn merge khi CI đỏ (Module 05) |
| Ai đó vô tình commit file `.env` chứa mật khẩu | Reviewer bắt được trong tab *Files changed* — trước khi vào `main` |
| Sự cố sau deploy, cần biết "thay đổi gì, ai duyệt, vì sao" | Lịch sử PR là **bản ghi kiểm toán** (audit trail): mô tả, review, commit, CI — tất cả ở một chỗ |
| Phỏng vấn: "Quy trình làm việc với Git của bạn thế nào?" | Bạn trả lời bằng chính repo `taskhub`: main được bảo vệ, PR, squash, tag |

Ở nhiều công ty, quy tắc "không ai push thẳng vào `main`, kể cả trưởng nhóm" là chuẩn mực. Biết thiết lập và làm việc theo quy tắc này là kỹ năng Junior bắt buộc.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Pull Request là tính năng của GitHub, không phải của Git

Git (chạy trên máy bạn) chỉ biết commit, branch, merge. **Pull Request** (yêu cầu kéo — đề nghị gộp một nhánh vào nhánh khác) là tính năng của các nền tảng lưu trữ Git như GitHub. GitLab gọi tương tự là **Merge Request**, Bitbucket cũng dùng tên Pull Request. Khái niệm giống nhau.

Một PR gồm:

- **Base branch** (nhánh đích): nơi thay đổi sẽ được gộp vào — thường là `main`.
- **Head branch** (nhánh nguồn): nhánh chứa thay đổi của bạn — ví dụ `feat/task-api`.
- **Diff**: phần khác biệt giữa hai nhánh, là thứ reviewer đọc.
- **Cuộc trò chuyện**: mô tả, comment, review, kết quả CI.

### 3.2. Các vai trò

| Vai trò | Việc |
|---|---|
| **Author** (tác giả) | Tạo nhánh, viết code, mở PR, trả lời review, sửa |
| **Reviewer** (người duyệt) | Đọc diff, đặt câu hỏi, đề xuất sửa, approve hoặc request changes |
| **Maintainer** (người quản lý repo) | Thiết lập luật cho repo: ai được merge, kiểu merge, bảo vệ nhánh |

Trong `taskhub` bạn đóng cả ba vai — đó là lý do bài này dạy cả cách **tự review**.

### 3.3. Ôn nhanh: vì sao làm việc trên nhánh?

Bài 02 đã giải thích nhánh là gì. Ở đây chỉ cần nhớ: **`main` luôn phải ở trạng thái chạy được và triển khai được.** Mọi việc dở dang nằm trên nhánh riêng, chỉ vào `main` khi đã được kiểm tra. PR là cơ chế kiểm tra đó.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Fork và branch

| | Branch trong cùng repo | Fork |
|---|---|---|
| Là gì | Nhánh mới nằm **trong** repo gốc | **Bản sao toàn bộ repo** sang tài khoản của bạn |
| Cần quyền ghi (write) vào repo gốc? | Có | Không |
| Dùng khi | Bạn là thành viên của team/repo | Đóng góp cho dự án mã nguồn mở bạn không có quyền ghi |
| PR đi từ đâu đến đâu | `feat/x` → `main` cùng repo | `ban/repo:feat/x` → `goc/repo:main` |

Trong công ty và trong `taskhub`: dùng **branch**. Fork chủ yếu gặp khi đóng góp cho mã nguồn mở.

### 4.2. 🟥 Vòng đời một Pull Request

Đây cũng là 6 bước của **GitHub Flow** — quy trình `taskhub` dùng (so sánh với quy trình khác ở [bài 04](04-team-workflows.md)):

1. **Tạo nhánh** từ `main` mới nhất, tên ngắn và rõ: `feat/task-api`, `fix/health-check`.
2. **Commit và push** các thay đổi lên nhánh. Mỗi commit tập trung vào một việc.
3. **Mở Pull Request** với mô tả rõ ràng. Có thể mở dạng **draft** nếu muốn góp ý sớm. Liên kết Issue liên quan.
4. **Trả lời review**: trả lời câu hỏi, push thêm commit để sửa — PR tự cập nhật.
5. **Merge** khi đã được duyệt và thỏa mãn mọi luật bảo vệ nhánh.
6. **Xóa nhánh** — công việc đã xong. Lịch sử PR và commit vẫn còn; nhánh đã xóa có thể khôi phục.

### 4.3. 🟥 Mô tả PR tốt và PR template

Reviewer không ngồi cạnh bạn. Mô tả PR phải trả lời được:

| Câu hỏi | Ví dụ |
|---|---|
| **Cái gì** thay đổi? | Thêm endpoint `POST /api/tasks` và validation cho `title` |
| **Vì sao**? | Issue #3: cần tạo task từ API |
| **Kiểm tra thế nào**? | `./mvnw verify` xanh; `curl -X POST ...` trả 201; thiếu title trả 400 |
| **Rủi ro / ảnh hưởng**? | Thêm migration `V2__...` — cần chạy trước khi deploy |
| **Liên kết** | `Closes #3` |

**PR template** là file Markdown mà GitHub tự điền vào ô mô tả mỗi khi mở PR. Vị trí hợp lệ:

- `.github/pull_request_template.md` (khuyến nghị — gọn gàng)
- `pull_request_template.md` ở thư mục gốc
- `docs/pull_request_template.md`

> Template chỉ có hiệu lực khi đã nằm trên **nhánh mặc định** (`main`). Vì vậy PR đầu tiên của bạn trong lab sẽ chính là PR thêm template.

Template gợi ý cho `taskhub`:

```markdown
## Thay đổi gì?
<!-- Mô tả ngắn gọn. -->

## Vì sao?
<!-- Liên kết issue: Closes #... -->

## Kiểm tra thế nào?
- [ ] `./mvnw verify` chạy xanh
- [ ] Đã thử thủ công: <lệnh curl / bước kiểm tra>

## Checklist
- [ ] Không có secret (mật khẩu, key, file .env) trong diff
- [ ] Đã cập nhật README/tài liệu nếu cần
- [ ] Commit title theo Conventional Commits
```

### 4.4. 🟨 Draft Pull Request

**Draft PR** (PR nháp) báo hiệu "chưa sẵn sàng để merge, nhưng muốn bạn xem sớm". Không merge được cho đến khi bạn bấm *Ready for review*. Dùng khi muốn hỏi ý kiến hướng làm trước khi đầu tư nhiều công sức.

### 4.5. 🟥 Ba kiểu merge trên GitHub

| Kiểu | Điều gì xảy ra với `main` | Ưu | Nhược |
|---|---|---|---|
| **Create a merge commit** (mặc định) | Mọi commit của nhánh vào `main` + 1 **merge commit** (giống `git merge --no-ff`) | Giữ đầy đủ lịch sử nhánh | `main` nhiều commit lặt vặt ("fix typo", "wip"), đồ thị rối |
| **Squash and merge** | Mọi commit của PR **gộp thành 1 commit** trên `main` | `main` gọn: **1 PR = 1 commit** | Mất các commit riêng lẻ của nhánh; SHA gốc không còn |
| **Rebase and merge** | Từng commit được **viết lại** lên đầu `main`, không có merge commit | Lịch sử thẳng, giữ từng commit | Commit có SHA mới; mỗi commit đều phải "đẹp" |

**Quyết định của `taskhub`: chỉ cho phép Squash and merge.** Lý do:

1. Mỗi commit trên `main` tương ứng **một PR hoàn chỉnh** — dễ đọc, dễ `git revert` cả một tính năng khi có sự cố.
2. Bạn được tự do commit nhỏ, thử nghiệm trên nhánh ("wip", "sửa lại") mà không làm bẩn `main`.
3. Title của commit squash = **title của PR** → chỉ cần đặt title PR theo Conventional Commits (`feat(api): add create task endpoint`) là lịch sử `main` tự chuẩn.

> ⚠️ **Cạm bẫy của squash:** sau khi PR đã squash merge, **đừng tiếp tục làm việc trên nhánh cũ** rồi mở PR mới từ chính nhánh đó. Các commit cũ (đã bị gộp, mang SHA khác) sẽ xuất hiện lại và gây conflict lặp đi lặp lại. Quy tắc: merge xong → xóa nhánh → tạo nhánh mới từ `main` mới nhất.

Thiết lập trong **Settings → General → Pull Requests**: chỉ tick *Allow squash merging*, bỏ tick hai kiểu còn lại. Trong menu thả xuống của mục này, chọn thông điệp mặc định là **Pull request title** (hoặc *Pull request title and description*) để commit trên `main` luôn mang title PR.

### 4.6. 🟥 Code review: reviewer nhìn gì?

Checklist review cho `taskhub` (dùng cả khi tự review):

| Nhóm | Câu hỏi |
|---|---|
| **Đúng** | Code làm đúng điều mô tả PR nói? Xử lý trường hợp lỗi chưa (404, 400, DB chết)? |
| **Dễ hiểu** | Tên biến/hàm rõ nghĩa? Người khác đọc 6 tháng sau có hiểu không? |
| **Test** | Có test cho hành vi mới? CI xanh? |
| **Bảo mật** | **Có secret trong diff không?** Có mở quyền/port rộng hơn cần không? Có log thông tin nhạy cảm không? |
| **Vận hành** | Thêm biến môi trường mới thì README/compose đã cập nhật chưa? Có migration không, có rollback được không? |
| **Phạm vi** | PR làm đúng một việc? PR quá lớn (> ~400 dòng) nên tách? |

**Viết comment review lịch sự và cụ thể:**

| ❌ Tránh | ✅ Nên |
|---|---|
| "Code này sai." | "Nếu `title` rỗng thì hàm này trả 500 thay vì 400. Mình nghĩ nên thêm `@NotBlank` — bạn thấy sao?" |
| "Đổi tên đi." | "nit: `t` hơi khó hiểu, đổi thành `task` cho rõ nhé (không bắt buộc)." |
| "Tại sao làm vậy???" | "question: vì sao mình dùng `ddl-auto=update` ở đây? Đặc tả yêu cầu dùng Flyway." |

Mẹo: đánh dấu mức độ ở đầu comment — `nit:` (chi tiết nhỏ, không bắt buộc), `question:` (hỏi để hiểu), `blocking:` (phải sửa mới merge). Khi đề xuất sửa cụ thể một dòng, dùng tính năng **suggest changes** của GitHub để tác giả áp dụng bằng một nút bấm.

Một review có thể kết thúc bằng 3 quyết định: **Comment** (góp ý chung), **Approve** (đồng ý merge), **Request changes** (cần sửa trước khi merge).

**Nhận review:** comment là về **code**, không phải về bạn. Trả lời mọi comment (sửa, hoặc giải thích vì sao không sửa), bấm *Resolve conversation* khi đã xử lý xong.

### 4.7. 🟥 Bảo vệ nhánh `main`

GitHub có hai cơ chế:

| Cơ chế | Vị trí trong Settings | Ghi chú |
|---|---|---|
| **Branch protection rule** (luật bảo vệ nhánh — kiểu "classic") | Settings → Branches | Mỗi nhánh chỉ áp dụng **một** luật |
| **Ruleset** (bộ luật) | Settings → Rules → Rulesets | Cơ chế mới hơn: nhiều ruleset áp dụng cùng lúc, bật/tắt mà không cần xóa, ai có quyền đọc cũng xem được |

Hai cơ chế hoạt động cùng nhau; khi cùng một luật được cấu hình khác nhau, luật **chặt hơn** thắng. Bài này dùng **branch protection rule** vì giao diện đơn giản. Nếu repo của bạn hiển thị Rulesets, các luật tương ứng có tên: *Require a pull request before merging*, *Require status checks to pass before merging*, *Block force pushes*, *Restrict deletions*.

Các thiết lập cần bật cho `main` của `taskhub` **bây giờ**:

| Thiết lập | Bật? | Vì sao |
|---|---|---|
| **Require a pull request before merging** | ✅ | Không ai push thẳng vào `main` |
| ↳ Required approvals | **0** | Xem giải thích bên dưới |
| **Require status checks to pass before merging** | ⏳ Tuần 9 | Chưa có CI. Tuần 9 bật và chọn job CI ([Lab 01 — Module 05](../05-CICD/labs/lab-01-ci-pr-gate.md)) |
| **Require conversation resolution before merging** | 🟨 Nên | Không merge khi còn comment chưa xử lý |
| **Do not allow bypassing the above settings** | ✅ | Mặc định **admin được bỏ qua** luật — bạn là admin repo mình, nên phải bật để luật áp dụng cả với bạn |
| Allow force pushes | ❌ (mặc định tắt) | Force push có thể xóa lịch sử của `main` |
| Allow deletions | ❌ (mặc định tắt) | Không ai xóa được `main` |

**Vì sao đặt 0 approval mà vẫn bắt buộc PR?** GitHub không cho tác giả tự approve PR của mình. Repo cá nhân chỉ có một người, nếu đặt 1 approval bạn sẽ không bao giờ merge được. Đặt 0 approval nhưng bắt buộc PR vẫn đạt được điều quan trọng: mọi thay đổi đều có **diff để tự review**, có **mô tả**, và từ tuần 9 có **CI chạy trước khi merge**. Khi làm việc trong team, con số này thường là 1–2.

> Repo `taskhub` là **public** nên dùng được branch protection với tài khoản GitHub miễn phí. Nếu bạn để repo private trên gói miễn phí, tính năng này có thể không khả dụng — hãy kiểm tra trong Settings của repo.

### 4.8. 🟨 CODEOWNERS

File `CODEOWNERS` gán **người chịu trách nhiệm** cho từng phần của repo. Khi PR sửa file thuộc phần nào, GitHub tự yêu cầu review từ chủ sở hữu phần đó. Đặt ở `.github/`, thư mục gốc hoặc `docs/`.

```text
# Mặc định: mọi file
*                 @phuong-dev
# Hạ tầng cần team DevOps duyệt
/infra/           @phuong-dev
/.github/workflows/ @phuong-dev
# Bảo vệ chính file CODEOWNERS
/.github/CODEOWNERS @phuong-dev
```

Kết hợp với luật *Require review from Code Owners* để bắt buộc. Với repo một người thì chưa cần — biết để đọc hiểu khi vào công ty.

### 4.9. 🟥 Issues và liên kết với PR

**Issue** (vấn đề/công việc) là nơi ghi một việc cần làm, một lỗi, một ý tưởng. Dùng Issue cho `taskhub` giúp bạn có **backlog** rõ ràng và lịch sử "vì sao làm việc này".

Viết vào **mô tả PR** (hoặc commit message) một từ khóa + số issue để Issue **tự đóng khi PR được merge vào nhánh mặc định**:

```text
Closes #3
Fixes #7
Resolves #12
```

Các từ khóa hợp lệ: `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`. Lưu ý: nếu PR **không** nhắm vào nhánh mặc định, từ khóa bị bỏ qua.

### 4.10. 🟨 Quản lý repository

Những thứ làm repo trông "chuyên nghiệp" khi nhà tuyển dụng mở ra:

| Mục | Nội dung |
|---|---|
| **About** (cột phải trang repo) | Description 1 câu, **topics** (`spring-boot`, `docker`, `aws`, `terraform`, `devops`) |
| `README.md` | Giới thiệu, kiến trúc, cách chạy — cập nhật theo từng phiên bản |
| `LICENSE` | Cho biết người khác được dùng code thế nào (ví dụ MIT) |
| `.gitignore` | Không đưa file build, IDE, `.env` lên repo |
| Settings → General | Kiểu merge (chỉ squash), **Automatically delete head branches** (tự xóa nhánh sau merge) |
| Settings → Collaborators | Mời người khác cùng làm (cấp quyền write) |

### 4.11. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| Require status checks | Module 05 — CI GitHub Actions chạy trên mỗi PR, chặn merge khi đỏ |
| Review PR hạ tầng | Module 07 — PR Terraform kèm kết quả `terraform plan` để review |
| PR là audit trail | Module 08 — viết postmortem, truy ngược "thay đổi nào gây sự cố" |
| Không lộ secret | Module 10 — quét secret tự động trong CI |
| `CODEOWNERS` cho `infra/` | Khi đi làm: team DevOps thường là owner của thư mục hạ tầng và pipeline |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Review bắt được secret

Một đồng nghiệp mở PR "chore: update local config". Trong tab *Files changed*, reviewer thấy:

```diff
+SPRING_DATASOURCE_PASSWORD=Sup3rS3cret!
```

Reviewer chọn **Request changes**: "blocking: file `.env` chứa mật khẩu thật. Vui lòng xóa file khỏi PR, thêm `.env` vào `.gitignore`, và **đổi mật khẩu DB** vì nó đã nằm trên GitHub." Nhớ lại [bài 00](00-git-quick-review.md): secret đã push lên là phải coi như đã lộ — xóa commit không đủ, phải xoay vòng (rotate) secret.

### Ví dụ 2: Một PR mẫu tốt

```text
Title:  feat(api): add create task endpoint

## Thay đổi gì?
Thêm POST /api/tasks. Validate title (1–200 ký tự), status mặc định TODO.
Trả 201 + header Location.

## Vì sao?
Closes #3

## Kiểm tra thế nào?
- [x] ./mvnw verify xanh (thêm 3 test controller)
- [x] curl -X POST localhost:8080/api/tasks -H 'Content-Type: application/json'
      -d '{"title":"Học Docker"}'  → 201
- [x] Thiếu title → 400 dạng Problem Details

## Checklist
- [x] Không có secret trong diff
- [x] README đã thêm ví dụ curl
```

Title PR theo Conventional Commits → sau khi squash merge, commit trên `main` cũng mang đúng title này.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Vòng đời PR trong taskhub

```text
 main ──●──────────────────────────────────●── (commit squash: "feat(api): add create task endpoint (#4)")
         \                                 ▲
          \ git switch -c feat/task-api    │ Squash and merge
           ●── wip ──●── add test ──●── fix review
                 │                        │
            git push -u              PR #4: review → sửa → approve*
                 ▼                        │
            GitHub: "Create a pull request" ─┘
                                          │
                                   xóa nhánh feat/task-api
 (* repo 1 người: 0 approval, tự review)
```

### 6.2. Ba kiểu merge cho cùng một nhánh 3 commit (A, B, C)

```text
Merge commit:   main: ─●──────────●M        (A, B, C + merge commit M đều vào main)
                        \        /
                         A──B──C

Squash:         main: ─●──S                 (S = A+B+C gộp làm một, SHA mới)

Rebase:         main: ─●──A'──B'──C'        (A, B, C được viết lại, SHA mới, không có M)
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `git switch -c <nhánh>` | Tạo nhánh mới và chuyển sang | 🟥 |
| `git push -u origin <nhánh>` | Đẩy nhánh lên GitHub lần đầu, thiết lập upstream | 🟥 |
| `git log --oneline main..HEAD` | Các commit có trên nhánh này mà `main` chưa có | 🟥 |
| `git diff main...HEAD` | Diff giống tab *Files changed* của PR | 🟥 |
| `git switch main && git pull` | Cập nhật `main` local sau khi merge | 🟥 |
| `git fetch --prune` | Xóa tham chiếu tới nhánh remote đã bị xóa | 🟥 |
| `git branch -d <nhánh>` / `-D` | Xóa nhánh local | 🟥 |
| `gh pr create`, `gh pr view` | Làm việc với PR từ terminal (cần cài GitHub CLI) | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa** (tên tài khoản `phuong-dev`, SHA, số PR sẽ khác trên máy bạn).

### `git switch -c` — tạo nhánh từ main mới nhất

```bash
git switch main
git pull                          # luôn bắt đầu từ main mới nhất
git switch -c docs/pr-template
```

```text
Switched to a new branch 'docs/pr-template'
```

Tạo nhánh từ một `main` cũ là nguyên nhân phổ biến khiến PR có conflict hoặc chứa commit lạ.

### `git push -u origin <nhánh>` — đẩy nhánh và nhận link mở PR

```bash
git push -u origin docs/pr-template
```

```text
Enumerating objects: 5, done.
...
remote:
remote: Create a pull request for 'docs/pr-template' on GitHub by visiting:
remote:      https://github.com/phuong-dev/taskhub/pull/new/docs/pr-template
remote:
To github.com:phuong-dev/taskhub.git
 * [new branch]      docs/pr-template -> docs/pr-template
branch 'docs/pr-template' set up to track 'origin/docs/pr-template'.
```

| Phần | Ý nghĩa |
|---|---|
| `-u` (`--set-upstream`) | Ghi nhớ nhánh local này theo dõi `origin/docs/pr-template` → lần sau chỉ cần `git push` / `git pull` |
| `origin` | Tên remote (bài 00) |
| Dòng `remote: Create a pull request...` | GitHub gợi ý link mở PR — giữ Ctrl và bấm vào link trong terminal |

### `git log main..HEAD` và `git diff main...HEAD` — xem trước PR

```bash
git log --oneline main..HEAD
git diff --stat main...HEAD
```

```text
3f2a9c1 docs: add pull request template
 .github/pull_request_template.md | 15 +++++++++++++++
 1 file changed, 15 insertions(+)
```

| Cú pháp | Nghĩa |
|---|---|
| `main..HEAD` (2 chấm, với `log`) | Commit có ở `HEAD` mà **không** có ở `main` → danh sách commit sẽ nằm trong PR |
| `main...HEAD` (3 chấm, với `diff`) | Khác biệt giữa `HEAD` và **điểm rẽ nhánh chung** với `main` → đúng những gì PR hiển thị, không lẫn thay đổi mới của `main` |
| `--stat` | Chỉ thống kê file nào đổi bao nhiêu dòng |

Chạy hai lệnh này **trước khi mở PR** là bước tự review đầu tiên: có commit nào lạ? có file nào không nên có (`.env`, `target/`)?

### Dọn dẹp sau khi merge

```bash
git switch main
git pull                     # kéo commit squash về
git fetch --prune            # xóa tham chiếu origin/docs/pr-template (nhánh đã bị xóa trên GitHub)
git branch -d docs/pr-template
```

```text
From github.com:phuong-dev/taskhub
 - [deleted]         (none)     -> origin/docs/pr-template
error: The branch 'docs/pr-template' is not fully merged.
If you are sure you want to delete it, run 'git branch -D docs/pr-template'.
```

Vì sao `-d` báo "not fully merged" dù PR đã merge? Vì **squash** tạo commit mới với SHA khác — Git không thấy các commit của nhánh nằm trong `main`. Sau khi đã kiểm tra trên GitHub rằng PR ở trạng thái *Merged*, dùng `git branch -D` (xóa ép) là an toàn. Đây là hệ quả bình thường của squash merge.

### 🟨 GitHub CLI (`gh`)

`gh` là phần mềm riêng (phải cài thêm nếu muốn dùng). Nó cho phép `gh pr create --fill`, `gh pr status`, `gh pr merge --squash` ngay trong terminal. Không bắt buộc cho khóa học — giao diện web đủ dùng và giúp bạn hiểu rõ từng bước hơn.

---

## 9. Bài thực hành từng bước

**Lab: Bảo vệ `main` và đi trọn vòng đời một PR** · `[WSL]` + trình duyệt · ~75 phút

Repo: `taskhub` trên GitHub (public, đã tạo ở tuần 1 — [milestone v-pre](../12-PRACTICAL-PROJECT/milestones/v-pre-foundation.md)). Ghi kết quả vào `~/devops-journey/week06/lab-pr.md`.

### Bước 1 — Cấu hình kiểu merge

Trên GitHub: **taskhub → Settings → General → Pull Requests**:

- [x] Allow squash merging → chọn thông điệp mặc định **Pull request title**
- [ ] Allow merge commits (bỏ tick)
- [ ] Allow rebase merging (bỏ tick)
- [x] Automatically delete head branches

### Bước 2 — Bật bảo vệ nhánh main

**Settings → Branches → Add branch protection rule** (hoặc *Add classic branch protection rule*):

- Branch name pattern: `main`
- [x] Require a pull request before merging — Required approvals: `0`
- [x] Require conversation resolution before merging
- [x] Do not allow bypassing the above settings
- Bấm **Create**.

### Bước 3 — Chứng minh luật có hiệu lực

```bash
cd ~/projects/taskhub                 # thư mục clone repo taskhub của bạn
git switch main && git pull
echo "test" >> README.md
git commit -am "test: direct push"
git push
```

❓ Ghi lại thông báo lỗi. Sau đó **hủy commit thử nghiệm** để `main` local khớp với GitHub:

```bash
git reset --hard origin/main   # ⚠️ xóa commit local chưa push — chỉ dùng ở đây vì đó là commit thử nghiệm
```

(`git reset --hard` được giải thích kỹ ở [bài 01](01-git-fundamentals-internals.md).)

### Bước 4 — Tạo Issue

Trên GitHub: **Issues → New issue**, title `Add pull request template`, mô tả 1–2 câu. Ghi lại số issue (ví dụ `#1`).

### Bước 5 — Làm việc trên nhánh

```bash
git switch -c docs/pr-template
mkdir -p .github
nano .github/pull_request_template.md     # dán template ở mục 4.3
git add .github/pull_request_template.md
git commit -m "docs: add pull request template"
git log --oneline main..HEAD
git diff --stat main...HEAD
git push -u origin docs/pr-template
```

### Bước 6 — Mở PR

Bấm link GitHub in ra ở bước trên (hoặc nút *Compare & pull request*):

- Base: `main` ← Compare: `docs/pr-template`
- Title: `docs: add pull request template`
- Mô tả: viết theo 4 câu hỏi ở mục 4.3, cuối cùng ghi `Closes #1`
- Bấm **Create pull request**.

### Bước 7 — Tự review

Mở tab **Files changed**, đọc từng dòng như thể đó là code của người khác. Thêm ít nhất **một comment** vào một dòng cụ thể (ví dụ đề xuất thêm mục "Rủi ro" vào template). Kết thúc review bằng **Comment** (bạn không thể Approve PR của chính mình).

Sau đó sửa theo comment:

```bash
nano .github/pull_request_template.md     # thêm mục "## Rủi ro / ảnh hưởng"
git commit -am "docs: add risk section to PR template"
git push
```

Quay lại PR: commit mới xuất hiện tự động. Bấm **Resolve conversation**.

### Bước 8 — Squash and merge

Bấm **Squash and merge**. Quan sát ô commit message: title đã được điền sẵn từ title PR (kèm số PR). Bấm **Confirm squash and merge**.

❓ Kiểm tra: Issue #1 đã tự đóng chưa? Nhánh `docs/pr-template` trên GitHub còn không?

### Bước 9 — Dọn dẹp local và kiểm tra lịch sử

```bash
git switch main
git pull
git fetch --prune
git branch -D docs/pr-template
git log --oneline -3
```

### Bước 10 — Kiểm chứng template

Tạo nhánh bất kỳ, sửa một dòng README, push và bấm mở PR. Ô mô tả phải được điền sẵn template. Đóng PR đó mà không merge (nút *Close pull request*) và xóa nhánh.

---

## 10. Kết quả mong đợi

- **Bước 3:** push bị từ chối với thông báo có `GH006: Protected branch update failed` và `Changes must be made through a pull request` → luật đã áp dụng **cả với admin** nhờ *Do not allow bypassing*.
- **Bước 6–7:** PR hiển thị 2 commit trên nhánh; comment của bạn nằm đúng dòng; conversation đã resolve.
- **Bước 8:** Issue #1 chuyển sang *Closed* và hiển thị "closed this as completed in #2" (số có thể khác). Nhánh trên GitHub đã tự xóa (do Bước 1).
- **Bước 9:** `git log --oneline -3` cho thấy **một** commit mới trên `main` với title `docs: add pull request template (#2)` — hai commit trên nhánh đã được gộp thành một.
- **Bước 10:** mô tả PR mới được điền sẵn template.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Push vào `main` bị từ chối (`GH006`) | Branch protection đang hoạt động — **đây là điều bạn muốn** | Tạo nhánh, push nhánh, mở PR |
| PR hiện hàng chục commit/file không liên quan | Tạo nhánh từ một nhánh khác (không phải `main`), hoặc `main` local quá cũ | Kiểm tra `git log --oneline main..HEAD`. Tạo lại nhánh từ `main` mới nhất và cherry-pick commit cần thiết (bài 02) |
| Nút merge bị xám | Còn conversation chưa resolve, có conflict, hoặc (từ tuần 9) CI chưa xanh | Đọc hộp trạng thái phía dưới PR — GitHub ghi rõ điều kiện nào chưa đạt |
| Issue không tự đóng sau merge | Từ khóa nằm ở comment thay vì mô tả PR/commit, sai cú pháp, hoặc PR không nhắm vào nhánh mặc định | Dùng `Closes #N` trong mô tả PR; kiểm tra base branch |
| `git branch -d` báo *not fully merged* sau squash | Squash tạo commit mới, Git không nhận ra nhánh đã gộp | Xác nhận PR *Merged* trên GitHub → `git branch -D` |
| Conflict lặp lại khi mở PR thứ hai từ cùng một nhánh | Tiếp tục làm việc trên nhánh đã squash merge | Merge xong → xóa nhánh → tạo nhánh mới từ `main` |
| `git branch -a` vẫn thấy `remotes/origin/<nhánh>` đã xóa | Tham chiếu remote cũ còn trong máy | `git fetch --prune` |
| Template không xuất hiện | File chưa nằm trên `main`, sai tên hoặc sai thư mục | Đúng tên `pull_request_template.md` trong `.github/`, đã merge vào `main` |

---

## 12. Đọc thông báo lỗi và xử lý

### Thông báo khi push bị chặn

```text
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: error: Changes must be made through a pull request.
To github.com:phuong-dev/taskhub.git
 ! [remote rejected] main -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:phuong-dev/taskhub.git'
```

Đọc theo cấu trúc đã học ở [Linux bài 01](../01-LINUX/01-linux-architecture-filesystem.md#12-đọc-thông-báo-lỗi-và-xử-lý):

- Các dòng `remote:` là **GitHub (phía server) nói**, không phải Git trên máy bạn. Lỗi nằm ở luật của repo, không phải ở mạng hay SSH key.
- `refs/heads/main` → đối tượng bị chặn là nhánh `main`.
- `Changes must be made through a pull request` → nguyên nhân và cách làm đúng.
- `! [remote rejected]` khác với `! [rejected] ... (fetch first)`: cái sau nghĩa là remote có commit mới mà bạn chưa có (cần `git pull`), không liên quan bảo vệ nhánh.

### Hộp trạng thái merge trên PR

Phần dưới cùng của PR là "log" quan trọng nhất. Các trạng thái hay gặp:

| GitHub hiển thị | Nghĩa | Làm gì |
|---|---|---|
| *This branch has no conflicts with the base branch* | Merge được | Merge |
| *This branch has conflicts that must be resolved* | Conflict với `main` | Cập nhật nhánh từ `main`, giải quyết conflict (bài 02) |
| *Merging is blocked* + lý do | Một luật bảo vệ chưa thỏa | Đọc lý do: conversation chưa resolve, thiếu approval, CI chưa xanh… |
| *Some checks were not successful* (từ tuần 9) | CI đỏ | Bấm *Details* để xem log của job (Module 05) |

### Quy trình khi PR "kỳ lạ"

1. `git log --oneline --graph main..HEAD` — commit nào thực sự thuộc PR?
2. `git diff --stat main...HEAD` — file nào thực sự thay đổi?
3. So với tab *Files changed* trên GitHub. Nếu khác → `main` local cũ, chạy `git fetch` rồi so lại với `origin/main`.
4. Ghi lại vào `troubleshooting-journal.md`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Pull Request là tính năng của Git hay của GitHub? GitLab gọi nó là gì?
2. Khi nào bạn dùng fork, khi nào dùng branch trong cùng repo?
3. Kể 6 bước của GitHub Flow.
4. Một mô tả PR tốt cần trả lời những câu hỏi nào?
5. So sánh merge commit, squash và rebase merge. `taskhub` chọn kiểu nào, vì sao?
6. Vì sao sau khi squash merge, `git branch -d` báo nhánh "not fully merged"? Có nguy hiểm không?
7. Vì sao không nên tiếp tục làm việc trên một nhánh đã squash merge?
8. Repo cá nhân: vì sao đặt 0 required approvals nhưng vẫn bật "Require a pull request before merging"?
9. Thiết lập "Do not allow bypassing the above settings" giải quyết vấn đề gì?
10. Kể 4 nhóm điều reviewer cần kiểm tra. Nhóm nào quan trọng nhất với DevOps, vì sao?
11. Viết lại comment "Sai rồi, sửa đi" thành một comment review tốt cho tình huống: API trả 500 khi `title` rỗng.
12. Viết dòng gì vào mô tả PR để Issue #8 tự đóng khi merge? Trường hợp nào nó không tự đóng?
13. `git diff main...HEAD` (3 chấm) khác `git diff main HEAD` thế nào?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/03-solutions.md](solutions/03-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Đọc lịch sử.** Sau lab, chạy `git log --oneline --graph -10` trên `main` của `taskhub`. Giải thích vì sao đồ thị là một đường thẳng không có nhánh, dù bạn đã làm việc trên nhánh riêng.

**Bài 2 — So sánh kiểu merge.** Trong một repo thử nghiệm **local** (`~/devops-lab/03-git/merge-styles`), tạo 3 nhánh giống hệt nhau, mỗi nhánh 3 commit. Gộp nhánh 1 bằng `git merge --no-ff`, nhánh 2 bằng `git merge --squash` + `git commit`, nhánh 3 bằng `git rebase main` rồi `git merge --ff-only`. Vẽ đồ thị `git log --oneline --graph` sau mỗi cách và đối chiếu với mục 6.2.

**Bài 3 — Review một PR có vấn đề.** Đọc diff dưới đây và viết ít nhất 4 comment review (ghi rõ dòng, mức độ `blocking:`/`question:`/`nit:`, đề xuất sửa):

```diff
+++ b/app/src/main/resources/application.properties
+spring.datasource.url=jdbc:postgresql://localhost:5432/taskhub
+spring.datasource.username=postgres
+spring.datasource.password=postgres123
+spring.jpa.hibernate.ddl-auto=update
+management.endpoints.web.exposure.include=*
+++ b/compose.yaml
+    ports:
+      - "5432:5432"
```

**Bài 4 — Template của riêng bạn.** Viết `.github/ISSUE_TEMPLATE/bug_report.md` cho `taskhub` (tự tìm hiểu cú pháp trong GitHub Docs, ghi link nguồn bạn dùng). Template phải yêu cầu: phiên bản (tag), các bước tái hiện, kết quả mong đợi/thực tế, log liên quan. Đưa vào repo qua một PR.

**Bài 5 — Mô phỏng hai người.** Mời một người bạn (hoặc tạo tài khoản GitHub thứ hai của chính bạn) làm collaborator của một repo thử nghiệm. Đặt required approvals = 1. Mở PR từ tài khoản A, review và approve từ tài khoản B, merge. Ghi lại: tài khoản A có tự approve được không? Thông báo GitHub hiển thị là gì?

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] `main` của `taskhub` được bảo vệ, bạn đã tự chứng minh không push thẳng được.
- [ ] Bạn đã hoàn thành ít nhất một PR có Issue liên kết, có comment review, squash merge, nhánh đã xóa.
- [ ] Bạn giải thích được ba kiểu merge bằng sơ đồ mà không nhìn tài liệu.
- [ ] Bạn đọc được thông báo `GH006` và phân biệt được với lỗi `rejected (fetch first)`.
- [ ] Bạn tìm được ít nhất 4 vấn đề trong diff ở Bài tập 3, trong đó có vấn đề bảo mật.
- [ ] Bạn trả lời được câu phỏng vấn "Quy trình Git của bạn thế nào?" bằng ví dụ từ `taskhub`.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow) | 6 bước của quy trình | 2026-10-31 |
| [GitHub Docs — About merge methods on GitHub](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/about-merge-methods-on-github) | 3 kiểu merge, cạm bẫy của squash | 2026-10-31 |
| [GitHub Docs — Configuring commit squashing](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/configuring-commit-squashing-for-pull-requests) | Chỉ cho phép squash, thông điệp mặc định | 2026-10-31 |
| [GitHub Docs — About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) | Các thiết lập bảo vệ nhánh, bypass của admin | 2026-10-31 |
| [GitHub Docs — About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) | Rulesets khác branch protection thế nào | 2026-10-31 |
| [GitHub Docs — Creating a pull request template](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository) | Vị trí file template | 2026-10-31 |
| [GitHub Docs — About pull request reviews](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/about-pull-request-reviews) | Comment / Approve / Request changes | 2026-10-31 |
| [GitHub Docs — Linking a pull request to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue) | Từ khóa đóng issue | 2026-10-31 |
| [GitHub Docs — About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) | CODEOWNERS | 2026-10-31 |
| [Pro Git — Chương 6: GitHub](https://git-scm.com/book/en/v2) | Đọc thêm về fork và PR | 2026-10-31 |
