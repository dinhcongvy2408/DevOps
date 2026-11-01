# Module 03 — Git & Software Development Workflow

> Tuần 1 (ôn tập) + tuần 6 · ~18 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 01 — Linux](../01-LINUX/README.md), [Ôn tập Git nhanh](00-git-quick-review.md)

## Mục lục

- [1. Vì sao DevOps cần hiểu Git sâu?](#1-vì-sao-devops-cần-hiểu-git-sâu)
- [2. DevOps cần biết Git đến mức nào?](#2-devops-cần-biết-git-đến-mức-nào)
- [3. Môi trường thực hành](#3-môi-trường-thực-hành)
- [4. Thứ tự bài học](#4-thứ-tự-bài-học)
- [5. Lab, checkpoint và dự án](#5-lab-checkpoint-và-dự-án)
- [6. Git trong các module sau](#6-git-trong-các-module-sau)
- [7. Checklist hoàn thành module](#7-checklist-hoàn-thành-module)
- [8. Nguồn học](#8-nguồn-học)

---

## 1. Vì sao DevOps cần hiểu Git sâu?

Developer dùng Git để lưu code. DevOps dùng Git làm **nguồn sự thật duy nhất** (single source of truth — nơi duy nhất được coi là đúng) cho gần như mọi thứ:

| Thứ được lưu trong Git | Vì sao quan trọng với DevOps |
|---|---|
| Code ứng dụng | Mỗi `push` / Pull Request **kích hoạt pipeline CI** (Module 05) |
| `Dockerfile`, `compose.yaml` | Cách đóng gói và chạy app có lịch sử, có review |
| Terraform, Ansible | **Infrastructure as Code**: hạ tầng thay đổi qua PR, không ai click tay trên console (Module 07) |
| Manifest Kubernetes, Helm chart | **GitOps**: trạng thái cluster = trạng thái trong repo (Module 09) |
| Tag `v1.2.0` | **Rollback** = triển khai lại image của tag cũ (Module 05) |
| Runbook, postmortem, ADR | Tri thức vận hành không mất khi người nghỉ việc |

Vì vậy DevOps phải xử lý được những tình huống khó: lỡ commit nhầm, conflict khi merge, cứu commit bị mất, tìm commit nào gây lỗi, gắn tag release đúng chuẩn. Đó là nội dung module này.

---

## 2. DevOps cần biết Git đến mức nào?

| Chủ đề | Mức cần cho Junior DevOps | Có thể học sau |
|---|---|---|
| Vòng lặp add/commit/push, `.gitignore` | 🟥 Thành thạo (đã học tuần 1) | — |
| Mô hình dữ liệu: commit, branch, HEAD | 🟥 Giải thích được branch "chỉ là con trỏ" | Định dạng packfile, delta compression |
| reset / revert / reflog | 🟥 Biết lệnh nào an toàn trên nhánh chung; cứu được commit mất | `git filter-repo` viết lại lịch sử |
| Branch, merge, rebase | 🟥 Phân biệt fast-forward / 3-way; biết khi nào **không** rebase | Chiến lược merge nâng cao (`octopus`, `subtree`) |
| Merge conflict | 🟥 Tự giải quyết bằng tay và bằng IDE | `rerere` |
| Pull Request, code review | 🟥 Mở PR đúng chuẩn, review PR của người khác | CODEOWNERS phức tạp |
| Branch protection | 🟥 Cấu hình bắt buộc PR + CI xanh | Rulesets cho cả tổ chức |
| Workflow nhóm | 🟥 GitHub Flow; nhận biết Git Flow, trunk-based | Thiết kế workflow cho tổ chức lớn |
| Tag, release, SemVer | 🟥 Gắn tag annotated, tạo release, chọn đúng số phiên bản | Tự động sinh changelog |
| `git bisect` | 🟨 Biết tồn tại và dùng được khi cần | — |
| Submodule, monorepo, Git LFS | 🟦 Nhận biết | Vận hành thực tế |

---

## 3. Môi trường thực hành

| Nhãn | Môi trường | Dùng cho |
|---|---|---|
| `[WSL]` | Ubuntu 24.04 trên WSL, Git đã cấu hình ở [bài ôn tập](00-git-quick-review.md) | Toàn bộ bài học và lab |
| GitHub | Tài khoản GitHub của bạn | Bài 03–05: Pull Request, branch protection, release |

Thư mục làm việc:

```bash
mkdir -p ~/devops-lab/03-git
cd ~/devops-lab/03-git
```

Bài 01, 02 và lab conflict **không cần GitHub**: dùng repo cục bộ và một "remote giả" (bare repository) trên chính máy bạn. Nhờ vậy bạn thử nghiệm thoải mái mà không làm bẩn repo thật.

---

## 4. Thứ tự bài học

| # | Bài | Tuần | Thời lượng | Mức |
|---|---|---|---|---|
| 00 | [Ôn tập Git nhanh](00-git-quick-review.md) | 1 | 2h | 🟥 |
| 01 | [Git fundamentals & internals](01-git-fundamentals-internals.md) | 6 | 3h | 🟥 |
| 02 | [Branching, merging & conflicts](02-branching-merging-conflicts.md) | 6 | 3h | 🟥 |
| 03 | [GitHub: Pull Request & code review](03-github-pull-request-code-review.md) | 6 | 3h | 🟥 |
| 04 | [Workflow làm việc nhóm](04-team-workflows.md) | 6 | 2h | 🟥 |
| 05 | [Tag, release & versioning](05-tags-releases-versioning.md) | 6 | 2h | 🟥 |

Tuần 6 khá dày (~13 giờ học + lab + dự án). Nếu thiếu thời gian, đẩy phần 🟨/🟦 của bài 01–02 sang giờ dự phòng, **không** cắt bài 03–05 vì dự án cần chúng ngay.

---

## 5. Lab, checkpoint và dự án

| Việc | Tuần | Mô tả |
|---|---|---|
| Lab trong mục 9 của mỗi bài | 6 | Thực hành theo từng chủ đề |
| [Lab 01 — 3 loại conflict + mô phỏng làm việc nhóm](labs/lab-01-conflicts-team-simulation.md) | 6 | Hai "đồng nghiệp" (2 thư mục clone) cùng đẩy lên một remote giả |
| [Dự án tuần 6 — ứng dụng Spring Boot taskhub](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md) | 6 | Tạo app, bật branch protection, làm việc qua PR, release `v0.1.0` |
| [Checkpoint Git + Docker](../04-DOCKER/checkpoint.md) | 8 | Checkpoint chung giai đoạn 3–4, làm sau khi xong Module 04 |

Lời giải bài tập ở [solutions/](solutions/). **Chỉ mở sau khi đã tự làm.**

---

## 6. Git trong các module sau

| Khái niệm ở đây | Gặp lại ở |
|---|---|
| Commit SHA | Tag image Docker theo SHA để biết chính xác image chứa code nào (Module 04, 05) |
| Branch, Pull Request | Pipeline CI chạy trên mỗi PR; PR chỉ merge được khi CI xanh (Module 05) |
| Tag SemVer | Pipeline release: push tag `v*` → build và đẩy image (Module 05) |
| `git revert` | Rollback cấu hình hạ tầng an toàn (Module 07) |
| Repo là nguồn sự thật | GitOps với Kubernetes (Module 09) |
| Không commit secret | Secret scanning, secrets management (Module 10) |

---

## 7. Checklist hoàn thành module

- [ ] 🟥 Giải thích được commit, tree, blob, branch, HEAD; chứng minh "branch chỉ là con trỏ" bằng lệnh.
- [ ] 🟥 Phân biệt `reset --soft/--mixed/--hard` và `revert`; biết vì sao trên nhánh chung chỉ dùng `revert`.
- [ ] 🟥 Cứu được một commit "bị mất" bằng `git reflog`.
- [ ] 🟥 Giải thích fast-forward và 3-way merge bằng sơ đồ; biết quy tắc vàng của rebase.
- [ ] 🟥 Tự giải quyết conflict nội dung và conflict modify/delete.
- [ ] 🟥 Mở PR có mô tả tốt, review PR, cấu hình branch protection cho `main`.
- [ ] 🟥 Giải thích GitHub Flow và vì sao dự án taskhub chọn nó.
- [ ] 🟥 Tạo tag annotated và GitHub Release `v0.1.0` cho taskhub.
- [ ] 🟥 Hoàn thành [Lab 01](labs/lab-01-conflicts-team-simulation.md).
- [ ] Cập nhật [Ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#git).

---

## 8. Nguồn học

| Vai trò | Nguồn | Ghi chú |
|---|---|---|
| Chính | Các bài trong module này | Tiếng Việt |
| Chính | [Pro Git (2nd Edition)](https://git-scm.com/book/en/v2) | Miễn phí. Đọc theo bài: [3.2 Basic Branching and Merging](https://git-scm.com/book/en/v2/Git-Branching-Basic-Branching-and-Merging), [3.6 Rebasing](https://git-scm.com/book/en/v2/Git-Branching-Rebasing), [7.1 Revision Selection](https://git-scm.com/book/en/v2/Git-Tools-Revision-Selection), [7.7 Reset Demystified](https://git-scm.com/book/en/v2/Git-Tools-Reset-Demystified), [10.2 Git Objects](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects), [10.3 Git References](https://git-scm.com/book/en/v2/Git-Internals-Git-References) |
| Bổ sung | [GitHub Docs](https://docs.github.com/) | Pull request, branch protection, release — link cụ thể trong bài 03–05 |
| Bổ sung | [MIT Missing Semester — Version Control and Git](https://missing.csail.mit.edu/) | Giải thích mô hình dữ liệu của Git rất gọn |
| Tra cứu nhanh | `git help <lệnh>`, `git <lệnh> -h` | Có sẵn trên máy |

Thuật ngữ của module: [glossary.md](glossary.md).
