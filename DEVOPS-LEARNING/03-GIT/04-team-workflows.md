# 04. Quy trình Git trong đội nhóm

> ⏱️ ~2 giờ · Mức độ: 🟥 Bắt buộc (🟦 cho một số mục ghi rõ) · Kiến thức cần có trước: [02. Branching, merging & conflict](02-branching-merging-conflicts.md), [03. Pull Request & code review](03-github-pull-request-code-review.md)
> Môi trường: `[WSL]` Ubuntu 24.04

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

- So sánh ba quy trình phổ biến: **GitHub Flow**, **Git Flow** và **trunk-based development** — ưu, nhược, loại team phù hợp.
- Đặt tên nhánh và viết commit message theo quy ước (**Conventional Commits**), biết commit nào làm tăng phiên bản nào.
- Giữ nhánh **ngắn hạn** và cập nhật thường xuyên từ `main` để tránh conflict lớn.
- Hiểu mối liên hệ giữa nhánh, tag và các **môi trường** dev/staging/prod (chuẩn bị cho Module 05).
- Ghi lại quyết định quy trình của `taskhub` thành tài liệu (`CONTRIBUTING.md`, ADR).

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Quy trình Git quyết định **pipeline CI/CD được thiết kế thế nào**:

| Câu hỏi khi thiết kế pipeline | Phụ thuộc vào quy trình Git |
|---|---|
| CI chạy khi nào? | Trên mỗi PR vào `main`? Trên mọi nhánh `feature/*`? |
| Khi nào deploy lên staging, khi nào lên production? | Merge vào `main` → staging; tạo tag `v*` → production? Hay merge vào nhánh `release`? |
| Hotfix production đi đường nào? | Nhánh `hotfix/*` từ tag cũ? Hay sửa trên `main` rồi deploy luôn? |
| Phiên bản tiếp theo là bao nhiêu? | Đọc commit message theo Conventional Commits để tự tính |

Khi vào một công ty mới, một trong những việc đầu tiên của DevOps là **đọc hiểu quy trình hiện có** — và đôi khi đề xuất đơn giản hóa nó. Câu hỏi phỏng vấn "Git Flow và trunk-based khác nhau thế nào?" rất phổ biến.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Quy trình (workflow) là gì?

Git cho phép làm gần như mọi thứ: bao nhiêu nhánh cũng được, merge kiểu gì cũng được. **Branching workflow** (quy trình phân nhánh) là **thỏa thuận của team** về:

- Có những nhánh lâu dài nào (`main`, `develop`, `release`…)?
- Nhánh làm việc tạo từ đâu, gộp vào đâu, sống bao lâu?
- Lúc nào tạo tag, lúc nào deploy?

Git không ép buộc quy trình. Team ép buộc nó bằng **branch protection** (bài 03), **CI** (Module 05) và **quy ước viết thành văn bản**.

### 3.2. Hai khái niệm then chốt

- **Continuous Integration** (tích hợp liên tục): mọi người gộp code vào nhánh chung **thường xuyên** (ít nhất mỗi ngày), mỗi lần gộp đều được build và test tự động. Nhánh càng sống lâu → càng xa `main` → conflict càng lớn → càng ít "liên tục".
- **Continuous Delivery** (phân phối liên tục): `main` **luôn ở trạng thái có thể release**. Deploy chỉ là bấm nút (hoặc tự động).

Hai khái niệm này được học kỹ ở Module 05. Ở đây chỉ cần hiểu: quy trình Git càng có **nhánh ngắn hạn** và `main` càng **luôn sạch**, CI/CD càng dễ.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 GitHub Flow

Quy trình bạn đã làm ở [bài 03](03-github-pull-request-code-review.md#42--vòng-đời-một-pull-request): một nhánh lâu dài duy nhất là `main`; mọi việc làm trên nhánh ngắn hạn → PR → merge → xóa nhánh. Deploy từ `main` (hoặc từ tag trên `main`).

| Ưu | Nhược |
|---|---|
| Đơn giản, dễ dạy, ít nhánh | Không có chỗ "chuẩn bị release" riêng — cần CI tốt để giữ `main` luôn sạch |
| Hợp với CI/CD | Khó khi phải duy trì song song nhiều phiên bản đã phát hành (v1 và v2 cùng lúc) |

**Phù hợp:** web app, API, dịch vụ nội bộ — triển khai thường xuyên, chỉ một phiên bản đang chạy trên production. **Đây là trường hợp của `taskhub`.**

### 4.2. 🟥 Git Flow

Do Vincent Driessen đề xuất năm 2010. Có **hai nhánh lâu dài** và ba loại nhánh hỗ trợ:

| Nhánh | Vai trò |
|---|---|
| `main` (hoặc `master`) | Chỉ chứa code đã phát hành, mỗi commit là một release có tag |
| `develop` | Nhánh tích hợp — tính năng hoàn thành được gộp vào đây |
| `feature/*` | Tạo từ `develop`, gộp về `develop` |
| `release/*` | Tạo từ `develop` để chuẩn bị phát hành (sửa lỗi nhỏ, đổi version), gộp vào cả `main` và `develop` |
| `hotfix/*` | Tạo từ `main` để sửa gấp production, gộp vào cả `main` và `develop` |

| Ưu | Nhược |
|---|---|
| Rõ ràng cho sản phẩm phát hành theo đợt, nhiều phiên bản song song | Nhiều nhánh, nhiều lần merge → dễ quên gộp ngược, conflict |
| Có giai đoạn ổn định hóa release | Nhánh `feature`/`develop` sống lâu → đi ngược tinh thần CI |

**Phù hợp:** phần mềm đóng gói cài đặt, ứng dụng mobile phát hành qua store, thư viện cần duy trì nhiều phiên bản.

> Chính tác giả Git Flow, trong "Note of reflection" (2020) ở đầu bài viết gốc, khuyên **không nên ép Git Flow** cho phần mềm được phân phối liên tục như web app, mà dùng quy trình đơn giản hơn như GitHub Flow. Bạn vẫn cần **hiểu** Git Flow vì nhiều công ty (đặc biệt dự án outsource lâu năm) vẫn dùng.

### 4.3. 🟥 Trunk-based development

Mọi người làm việc trên **một nhánh chung** ("trunk", ngày nay thường là `main`). Không có nhánh phát triển sống lâu. Có thể dùng **nhánh ngắn hạn** (vài giờ đến 1–2 ngày) để review và chạy CI trước khi vào trunk; team rất nhỏ có thể commit thẳng vào trunk.

| Ưu | Nhược |
|---|---|
| Đúng tinh thần CI nhất: tích hợp liên tục, conflict nhỏ | Đòi hỏi kỷ luật cao: test tự động tốt, commit nhỏ |
| Nền tảng cho CD tốc độ cao | Tính năng chưa xong vẫn nằm trong `main` → cần **feature flag** (mục 4.7) |

**Phù hợp:** team có CI/CD trưởng thành, deploy nhiều lần mỗi ngày.

**GitHub Flow và trunk-based rất gần nhau.** GitHub Flow với nhánh thật ngắn hạn về cơ bản là trunk-based có PR. Khác biệt chủ yếu ở **độ dài sống của nhánh** và mức độ dùng feature flag.

### 4.4. 🟥 So sánh tổng hợp

| Tiêu chí | GitHub Flow | Git Flow | Trunk-based |
|---|---|---|---|
| Nhánh lâu dài | `main` | `main` + `develop` | `main` (trunk) |
| Nhánh làm việc sống | Vài ngày | Có thể nhiều tuần | Vài giờ – 1–2 ngày (hoặc không có) |
| Release từ đâu | `main` / tag | Nhánh `release/*` → `main` + tag | `main` / tag (hoặc nhánh release ngắn) |
| Độ phức tạp | Thấp | Cao | Thấp về nhánh, cao về kỷ luật |
| Hợp với CI/CD | Tốt | Kém hơn | Rất tốt |
| Nhiều phiên bản song song | Khó | Tốt | Khó |
| Ví dụ phù hợp | `taskhub`, web app, API | App mobile, phần mềm đóng gói | Team lớn deploy liên tục |

### 4.5. 🟥 Quy ước đặt tên nhánh

Đặt tên nhánh theo **loại công việc** — trùng với `type` của Conventional Commits để dễ nhớ:

| Tiền tố | Dùng cho | Ví dụ |
|---|---|---|
| `feat/` | Tính năng mới | `feat/task-api` |
| `fix/` | Sửa lỗi | `fix/health-db-down` |
| `docs/` | Tài liệu | `docs/pr-template` |
| `chore/` | Việc vặt: nâng phiên bản dependency, cấu hình | `chore/bump-spring-boot` |
| `ci/` | Pipeline (từ Module 05) | `ci/add-build-workflow` |
| `refactor/` | Sửa cấu trúc code, không đổi hành vi | `refactor/task-service` |

Quy tắc: chữ thường, nối bằng `-`, ngắn nhưng đủ nghĩa, có thể kèm số issue (`fix/12-health-db-down`). Một số team dùng `feature/` thay cho `feat/` — quan trọng là **cả team thống nhất**.

### 4.6. 🟥 Conventional Commits đầy đủ hơn

[Bài 00](00-git-quick-review.md) đã giới thiệu. Cấu trúc đầy đủ:

```text
<type>[(scope)][!]: <mô tả ngắn>

[body — giải thích vì sao, có thể nhiều dòng]

[footer — BREAKING CHANGE: ..., Closes #12, Co-authored-by: ...]
```

| Thành phần | Ý nghĩa |
|---|---|
| `type` | Spec chỉ định nghĩa `feat` (tính năng) và `fix` (sửa lỗi). Các type khác phổ biến theo quy ước Angular/commitlint: `docs`, `chore`, `ci`, `build`, `test`, `refactor`, `perf`, `style` |
| `scope` | Phần nào bị ảnh hưởng: `feat(api):`, `fix(db):`, `ci(docker):` |
| `!` | Đánh dấu **breaking change** (thay đổi không tương thích ngược) |
| Footer `BREAKING CHANGE:` | Cách khác để đánh dấu breaking change, kèm mô tả |

**Liên hệ với Semantic Versioning** ([bài 05](05-tags-releases-versioning.md)):

| Commit | Tăng phần nào của phiên bản |
|---|---|
| `fix: ...` | PATCH (`0.1.0` → `0.1.1`) |
| `feat: ...` | MINOR (`0.1.1` → `0.2.0`) |
| Bất kỳ type nào có `!` hoặc `BREAKING CHANGE:` | MAJOR (`1.4.2` → `2.0.0`) |
| `docs`, `chore`, `ci`, `test`… (không breaking) | Không ảnh hưởng phiên bản |

Nhờ quy ước này, công cụ có thể **tự tính phiên bản tiếp theo** và tự sinh changelog từ lịch sử commit. Với `taskhub` dùng squash merge, chỉ cần **title PR** đúng quy ước (bài 03).

Ví dụ breaking change trong `taskhub`:

```text
feat(api)!: rename field "name" to "title" in task payload

Client gửi "name" sẽ nhận 400. Đổi tên để khớp đặc tả.

BREAKING CHANGE: trường "name" trong request/response đã đổi thành "title".
Closes #21
```

### 4.7. 🟥 Thói quen giữ nhánh khỏe mạnh

1. **Commit nhỏ, thường xuyên** — mỗi commit một ý, build được. Dễ review, dễ tìm lỗi, dễ revert.
2. **Nhánh ngắn hạn** — mục tiêu: PR mở và merge trong 1–3 ngày. Việc lớn → chia nhỏ thành nhiều PR.
3. **Cập nhật từ `main` thường xuyên** — `git fetch` rồi `git rebase origin/main` (hoặc `git merge origin/main`) trên nhánh của bạn (bài 02). Phát hiện conflict khi nó còn nhỏ.
4. **Một PR = một việc** — không gộp "thêm API + nâng Spring Boot + sửa README" vào một PR.

### 4.8. 🟦 Feature flag (nhận biết)

**Feature flag** (cờ tính năng): đoạn code mới đã nằm trong `main` và đã deploy, nhưng được **tắt bằng cấu hình**, chỉ bật khi sẵn sàng (hoặc chỉ bật cho một nhóm người dùng). Nhờ đó tách được "deploy code" khỏi "phát hành tính năng" — kỹ thuật quan trọng của trunk-based development. Ví dụ đơn giản trong Spring Boot: `if (features.isNewSearchEnabled())` đọc từ biến môi trường. Junior chỉ cần biết khái niệm.

### 4.9. 🟥 Nhánh, tag và môi trường (báo trước Module 05)

Hầu hết dự án có nhiều **môi trường** (environment):

| Môi trường | Mục đích | Trong `taskhub` |
|---|---|---|
| **dev / local** | Lập trình viên thử nghiệm | Laptop + Docker Compose (v0) |
| **staging** | Bản sao gần giống production để kiểm thử trước khi phát hành | Có thể bỏ qua để tiết kiệm chi phí AWS — nêu rõ trong ADR |
| **production** | Người dùng thật | EC2 trên AWS (v2+) |

Hai cách phổ biến để nối Git với môi trường:

| Cách | Mô tả | Nhận xét |
|---|---|---|
| **Nhánh theo môi trường** (`develop` → dev, `staging` → staging, `main` → prod) | Merge sang nhánh nào thì deploy lên môi trường đó | Dễ bị lệch giữa các nhánh; cùng một code lại build nhiều lần |
| **Một nhánh + tag** (khuyến nghị cho `taskhub`) | Merge vào `main` → build image một lần, deploy staging/dev; tạo tag `v*` → deploy **chính image đó** lên production | "Build once, deploy many": thứ được test chính là thứ lên production |

Module 05 sẽ hiện thực hóa cách thứ hai bằng GitHub Actions.

### 4.10. 🟦 Monorepo và polyrepo (nhận biết)

- **Monorepo**: nhiều dịch vụ/dự án trong **một** repo (ví dụ app + hạ tầng + tài liệu). `taskhub` là một monorepo nhỏ: `app/`, `infra/`, `k8s/`, `docs/` cùng một repo.
- **Polyrepo**: mỗi dịch vụ một repo riêng.

Mỗi kiểu có đánh đổi về CI (monorepo cần lọc "thư mục nào thay đổi thì chạy job nào"), phân quyền và quản lý phiên bản. Bạn sẽ gặp lại khi viết workflow CI với điều kiện `paths:` ở Module 05.

### 4.11. Quyết định quy trình cho taskhub

| Hạng mục | Quyết định |
|---|---|
| Quy trình | **GitHub Flow** |
| Nhánh lâu dài | Chỉ `main`, được bảo vệ (bài 03) |
| Tên nhánh | `feat/`, `fix/`, `docs/`, `chore/`, `ci/`, `refactor/` + mô tả ngắn |
| Kiểu merge | **Squash and merge** — title PR theo Conventional Commits |
| Phiên bản | **SemVer**, tag annotated `vX.Y.Z` trên `main` ([bài 05](05-tags-releases-versioning.md)) |
| Deploy (từ Module 05) | Merge `main` → build image tag `<sha>`; tag `v*` → deploy production bằng chính image đó |

### 4.12. Gặp lại ở đâu

| Kiến thức ở đây | Gặp lại ở |
|---|---|
| Nhánh ngắn hạn + CI trên PR | Module 05 — workflow `on: pull_request` |
| Tag → deploy production | Module 05 — workflow `on: push: tags: ['v*']`; Module 08 — rollback bằng tag cũ |
| Môi trường dev/staging/prod | Module 05 (GitHub Environments), Module 07 (Terraform `envs/`) |
| Monorepo + `paths:` | Module 05 — chỉ chạy job Terraform khi `infra/` thay đổi |
| Feature flag | Khi đi làm — kết hợp với canary deployment (Module 05) |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Dự án outsource dùng Git Flow, khách muốn deploy hằng ngày

Team có `develop`, `release/*`, `main`. Nhánh `feature` thường sống 2–3 tuần; mỗi đợt release mất 2 ngày chỉ để merge và giải quyết conflict. Khách hàng yêu cầu deploy bản sửa lỗi hằng ngày. DevOps đề xuất: bỏ `develop`, chuyển sang GitHub Flow + tag; CI chạy trên mọi PR; deploy production bằng tag. Kết quả: thời gian từ merge đến production giảm từ tuần xuống giờ. **Bài học:** quy trình Git phải phục vụ tần suất phát hành.

### Ví dụ 2: Hotfix trong GitHub Flow

Production (`v0.3.0`) lỗi health check. Trong GitHub Flow:

1. `git switch -c fix/health-check` từ `main` mới nhất.
2. Sửa, PR, CI xanh, squash merge (`fix(health): ...`).
3. Tag `v0.3.1` → deploy.

Nếu `main` đã có tính năng chưa muốn phát hành, đây là lúc feature flag hoặc nhánh release ngắn phát huy tác dụng — một lý do khiến team lớn cân nhắc thêm kỹ thuật thay vì chỉ GitHub Flow thuần.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. GitHub Flow

```text
main     ──●────────●──────────●─────●──▶   (tag v0.1.0, v0.2.0 trên main)
            \      ↑ \        ↑     ↑
feat/a       ●──●──┘  \       │     │      PR + squash
fix/b                  ●──────┘     │
docs/c                         ●────┘
```

### 6.2. Git Flow

```text
main     ──●───────────────────────●─────────────●──▶   (v1.0)        (v1.0.1)
            \                     ↑ \            ↑
hotfix       \                    │  ●──fix──────┤
              \                   │              ↓
develop  ──────●──────●───────●───┼──────────────●──▶
                \    ↑ \     ↑ \  │
feature/x        ●──●┘  \    │  ●─┘ release/1.0 (ổn định hóa → main + develop)
feature/y                ●───┘
```

### 6.3. Trunk-based development

```text
main (trunk) ──●──●──●──●──●──●──●──●──▶   (deploy nhiều lần/ngày)
                \/    \/    \/
            nhánh vài giờ, PR nhỏ, CI bắt buộc; tính năng dở dang ẩn sau feature flag
```

---

## 7. Các câu lệnh cần biết

Bài này chủ yếu về **quy ước**. Các lệnh dưới đây giúp tuân thủ quy ước hằng ngày:

| Lệnh | Mục đích | Mức |
|---|---|---|
| `git fetch origin` | Lấy thông tin mới từ remote mà không thay đổi nhánh của bạn | 🟥 |
| `git log --oneline HEAD..origin/main` | `main` trên remote có gì mới mà nhánh bạn chưa có | 🟥 |
| `git rebase origin/main` | Đặt các commit của nhánh lên đầu `main` mới nhất (bài 02) | 🟥 |
| `git branch -vv` | Xem nhánh nào theo dõi remote nào, đi trước/sau bao nhiêu commit | 🟥 |
| `git log --oneline --since="2 weeks ago" main` | Lịch sử gần đây của `main` | 🟨 |
| `git commit` (không có `-m`) | Mở editor để viết commit có body và footer | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

> Đầu ra mẫu là **minh họa**.

### Nhánh của tôi đã cũ chưa?

```bash
git fetch origin
git branch -vv
git log --oneline HEAD..origin/main
```

```text
* feat/task-api 8c1d2e4 [origin/feat/task-api: ahead 2] feat(api): add validation
  main          a41f003 [origin/main: behind 3] docs: add pull request template (#2)
5b7e9aa chore: bump spring boot to 4.1.2 (#5)
91c03fd fix(db): use env var for datasource url (#4)
c2d8810 docs: add CONTRIBUTING.md (#3)
```

| Thông tin | Đọc thế nào |
|---|---|
| `[origin/feat/task-api: ahead 2]` | Nhánh local có 2 commit chưa push |
| `[origin/main: behind 3]` | `main` local thiếu 3 commit so với GitHub — cần `git pull` khi đứng ở `main` |
| `HEAD..origin/main` liệt kê 3 commit | `main` đã tiến thêm 3 commit kể từ khi bạn rẽ nhánh → nên cập nhật nhánh trước khi mở PR |

### Viết commit có body và footer

```bash
git commit          # không -m → mở editor (nano nếu đã cấu hình core.editor ở bài 00)
```

Trong editor, dòng đầu là title (≤ ~72 ký tự), **một dòng trống**, rồi body và footer:

```text
fix(health): report DOWN when database is unreachable

Trước đây /actuator/health luôn trả UP vì health indicator của DB bị tắt
trong application.properties. Bật lại để load balancer (Module 06) biết
instance không phục vụ được.

Closes #12
```

Dòng trống sau title là bắt buộc — nhiều công cụ (kể cả GitHub) dựa vào nó để tách title và body.

---

## 9. Bài thực hành từng bước

**Lab: Viết quy ước làm việc cho taskhub và áp dụng thử** · `[WSL]` · ~60 phút

### Bước 1 — Tạo nhánh theo quy ước

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c docs/contributing
```

### Bước 2 — Viết `CONTRIBUTING.md`

Tạo file `CONTRIBUTING.md` ở thư mục gốc `taskhub`, dựa trên bảng ở mục 4.11. Khung gợi ý:

```markdown
# Đóng góp cho taskhub

## Quy trình
GitHub Flow: nhánh ngắn hạn từ `main` → Pull Request → squash merge → xóa nhánh.

## Đặt tên nhánh
feat/… · fix/… · docs/… · chore/… · ci/… · refactor/…

## Commit và title PR
Theo Conventional Commits: `type(scope): mô tả`. Breaking change dùng `!` hoặc footer `BREAKING CHANGE:`.

## Pull Request
- Điền đủ template; liên kết issue bằng `Closes #N`.
- PR nhỏ, một việc.

## Phiên bản
SemVer, tag annotated `vX.Y.Z` trên `main`.
```

### Bước 3 — Commit có body

```bash
git add CONTRIBUTING.md
git commit
```

Viết commit theo mẫu ở mục 8 (title `docs: add contributing guide`, body giải thích vì sao repo cần file này).

### Bước 4 — Mô phỏng `main` tiến lên trong lúc bạn làm việc

Trên GitHub, sửa trực tiếp `README.md` của `taskhub` qua giao diện web **bằng một PR** (GitHub cho phép tạo nhánh và PR ngay khi sửa file trên web — chọn *Create a new branch for this commit and start a pull request*). Squash merge PR đó.

### Bước 5 — Phát hiện và cập nhật

```bash
git fetch origin
git log --oneline HEAD..origin/main     # thấy commit README vừa merge
git rebase origin/main                  # đưa commit của bạn lên đầu main mới nhất
git log --oneline --graph -5
git push -u origin docs/contributing
```

### Bước 6 — Mở PR, tự review, squash merge

Title PR: `docs: add contributing guide`. Kiểm tra ô commit message khi squash: title đúng quy ước. Merge, dọn dẹp nhánh như bài 03.

### Bước 7 — Đọc lại lịch sử

```bash
git switch main && git pull
git log --oneline -5
```

Ghi vào `~/devops-journey/week06/lab-workflow.md`: lịch sử `main` có đọc được như một "changelog" không? Commit nào sẽ làm tăng phiên bản, tăng phần nào?

---

## 10. Kết quả mong đợi

- `CONTRIBUTING.md` có trên `main`, mô tả đúng quy trình `taskhub`.
- **Bước 5:** `git log --oneline HEAD..origin/main` liệt kê đúng commit sửa README; sau `rebase`, đồ thị cho thấy commit `docs: add contributing guide` nằm **phía trên** commit README — một đường thẳng.
- **Bước 7:** mọi commit trên `main` đều có dạng `type(scope): mô tả (#N)`. Các commit `docs:` không làm tăng phiên bản; nếu có `feat:` thì phiên bản tiếp theo tăng MINOR.

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| Conflict khổng lồ khi mở PR | Nhánh sống quá lâu, không cập nhật từ `main` | Chia việc nhỏ; `git fetch && git rebase origin/main` ít nhất mỗi ngày |
| Push bị từ chối sau khi `rebase` | Rebase viết lại commit đã push → lịch sử local và remote khác nhau | Với nhánh **của riêng bạn**: `git push --force-with-lease` (bài 02). Không bao giờ force push `main` hay nhánh chung |
| Title commit squash không theo quy ước | Title PR viết tùy ý | Sửa title PR **trước khi** bấm merge, hoặc sửa trong ô commit message lúc squash |
| Commit `feat: ...` nhưng thực ra là sửa lỗi | Chọn sai type | Ảnh hưởng đến việc tính phiên bản và changelog — chọn type theo **tác động với người dùng** |
| Team mỗi người một kiểu đặt tên nhánh | Không có quy ước bằng văn bản | `CONTRIBUTING.md` + nhắc trong review |
| "Chúng tôi dùng Git Flow nhưng không ai merge `release` về `develop`" | Git Flow phức tạp, dễ quên bước | Cân nhắc đơn giản hóa quy trình; nếu giữ, tự động hóa bước gộp ngược |

---

## 12. Đọc thông báo lỗi và xử lý

### Push bị từ chối sau rebase

```text
To github.com:phuong-dev/taskhub.git
 ! [rejected]        docs/contributing -> docs/contributing (non-fast-forward)
error: failed to push some refs to 'github.com:phuong-dev/taskhub.git'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart.
```

Đọc:

- Dòng này **không có** `remote: error: GH006` → không phải luật bảo vệ nhánh (bài 03).
- `non-fast-forward` → lịch sử nhánh trên GitHub không phải là "tổ tiên" của nhánh local. Hai khả năng:
  1. Có người khác đã push lên nhánh này → cần `git pull --rebase` (đừng force push, sẽ xóa việc của họ).
  2. **Bạn vừa rebase** nhánh đã push → lịch sử bị viết lại là chủ ý → `git push --force-with-lease`.
- Kiểm tra bằng `git log --oneline origin/docs/contributing..HEAD` và ngược lại `HEAD..origin/docs/contributing` để biết mỗi bên có commit gì mà bên kia không có.

`--force-with-lease` an toàn hơn `--force`: nó từ chối ghi đè nếu remote có commit mà bạn **chưa từng thấy** (ai đó vừa push thêm).

### "Nhánh tôi khác main bao nhiêu?"

`git branch -vv` và `git log HEAD..origin/main` (mục 8) là hai lệnh quan sát đầu tiên mỗi sáng trước khi bắt đầu làm việc.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Branching workflow là gì? Ai/cái gì ép buộc team tuân theo nó?
2. Kể các nhánh của Git Flow và vai trò của từng nhánh.
3. Vì sao Git Flow không phù hợp với web app deploy liên tục? Tác giả của nó nói gì?
4. GitHub Flow và trunk-based development giống và khác nhau ở điểm nào?
5. Feature flag giải quyết vấn đề gì trong trunk-based development?
6. Commit `feat(api)!: remove /api/v1/tasks` làm phiên bản `1.3.2` thành bao nhiêu? Commit `docs: fix typo` thì sao?
7. Vì sao dòng trống giữa title và body của commit lại quan trọng?
8. Giải thích "build once, deploy many". Vì sao cách "một nhánh + tag" làm được điều này còn "nhánh theo môi trường" thì khó?
9. Khi nào được dùng `git push --force-with-lease`? Khi nào tuyệt đối không?
10. `taskhub` là monorepo hay polyrepo? Điều đó ảnh hưởng gì đến CI?
11. Bạn vào một công ty dùng Git Flow với nhánh feature sống 3 tuần. Bạn quan sát thấy vấn đề gì và đề xuất gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/04-solutions.md](solutions/04-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Chọn quy trình.** Với mỗi tình huống, chọn GitHub Flow, Git Flow hay trunk-based và giải thích bằng 2–3 câu: (a) app mobile phát hành lên store mỗi tháng, phải hỗ trợ bản cũ 6 tháng; (b) API nội bộ, team 4 người, deploy vài lần mỗi tuần; (c) công ty 200 kỹ sư, deploy 50 lần/ngày, có hệ thống feature flag; (d) thư viện mã nguồn mở có v2 và v3 cùng được bảo trì.

**Bài 2 — Viết commit message.** Viết commit message đúng Conventional Commits (có scope, body khi cần) cho: (a) thêm endpoint lọc task theo status; (b) sửa lỗi `updatedAt` không cập nhật khi sửa task; (c) đổi đường dẫn API từ `/tasks` sang `/api/tasks` (client cũ sẽ lỗi); (d) thêm workflow CI; (e) nâng PostgreSQL driver. Với mỗi commit, cho biết phiên bản `0.4.1` thay đổi thế nào.

**Bài 3 — ADR quy trình.** Viết `docs/adr/0002-git-workflow.md` cho `taskhub` theo đúng mẫu ADR trong [README dự án](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr): bối cảnh (repo một người, mục tiêu CI/CD, deploy lên một EC2), các lựa chọn đã cân nhắc (GitHub Flow, Git Flow, trunk-based thuần), quyết định, hệ quả (gồm cả nhược điểm chấp nhận được). Đưa vào repo qua PR.

**Bài 4 — Vẽ lại Git Flow.** Trong repo thử nghiệm local, tự dựng đúng đồ thị mục 6.2: `main`, `develop`, 2 nhánh feature, 1 nhánh release, 1 hotfix. Dùng `git merge --no-ff` cho mọi lần gộp. Chụp `git log --oneline --graph --all` và đếm: bạn đã merge bao nhiêu lần? So với GitHub Flow cho cùng lượng công việc.

**Bài 5 — Môi trường và tag.** Vẽ sơ đồ (bằng chữ) luồng từ "merge PR vào `main`" đến "chạy trên production" cho `taskhub` theo cách "một nhánh + tag" ở mục 4.9: image được build ở đâu, gắn tag gì, môi trường nào nhận image nào. Bạn sẽ đối chiếu sơ đồ này khi học Module 05.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Bạn vẽ được ba quy trình bằng sơ đồ và nói được mỗi quy trình hợp với loại dự án nào.
- [ ] Bạn chọn đúng type và tính đúng phiên bản cho mọi commit trong Bài tập 2.
- [ ] `taskhub` có `CONTRIBUTING.md` và ADR quy trình trên `main`, đều vào qua PR.
- [ ] Bạn tự cập nhật được nhánh từ `main` bằng `rebase` và đẩy lại an toàn với `--force-with-lease`.
- [ ] Bạn trả lời được câu phỏng vấn "Git Flow và trunk-based khác nhau thế nào, bạn chọn cái nào cho web app?" trong 2 phút.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow) | GitHub Flow | 2026-10-31 |
| [Vincent Driessen — A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model/) | Git Flow gốc và "Note of reflection" (2020) | 2026-10-31 |
| [trunkbaseddevelopment.com](https://trunkbaseddevelopment.com/) | Trunk-based development, nhánh ngắn hạn, feature flag | 2026-10-31 |
| [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) | Cấu trúc commit, breaking change, liên hệ SemVer | 2026-10-31 |
| [Semantic Versioning 2.0.0](https://semver.org/) | Quy tắc tăng phiên bản | 2026-10-31 |
| [Pro Git — Chương 5: Distributed Git](https://git-scm.com/book/en/v2) | Các mô hình làm việc phân tán | 2026-10-31 |
