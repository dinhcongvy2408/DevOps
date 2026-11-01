# Lời giải — Bài 04: Quy trình Git trong đội nhóm

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [04-team-workflows.md](../04-team-workflows.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Thỏa thuận của team về các nhánh lâu dài, cách tạo/gộp nhánh làm việc, lúc nào tag và deploy. Git không ép buộc; team ép buộc bằng branch protection, CI và quy ước văn bản (`CONTRIBUTING.md`, review).

**2.** `main` (code đã phát hành, có tag), `develop` (tích hợp), `feature/*` (từ và về `develop`), `release/*` (ổn định hóa, gộp vào `main` và `develop`), `hotfix/*` (từ `main`, gộp vào `main` và `develop`).

**3.** Nhiều nhánh sống lâu và nhiều bước merge làm chậm việc tích hợp, đi ngược CI/CD; web app chỉ có một phiên bản chạy trên production nên không cần cơ chế duy trì nhiều phiên bản. Trong "Note of reflection" (2020), tác giả khuyên không ép Git Flow cho phần mềm phân phối liên tục, nên dùng quy trình đơn giản hơn như GitHub Flow.

**4.** Giống: một nhánh lâu dài, mọi thứ quay về `main` nhanh, hợp CI/CD. Khác: trunk-based nhấn mạnh nhánh cực ngắn (vài giờ) hoặc commit thẳng vào trunk, thường đi kèm feature flag; GitHub Flow luôn qua PR và nhánh có thể sống vài ngày.

**5.** Cho phép code của tính năng chưa hoàn thành nằm trong `main` (và được deploy) mà không lộ ra cho người dùng — tách "deploy" khỏi "phát hành", nhờ đó không cần nhánh feature sống lâu.

**6.** `feat(api)!:` là breaking change → MAJOR: `1.3.2` → `2.0.0`. `docs: fix typo` → không đổi phiên bản.

**7.** Git và các công cụ (GitHub, `git log --oneline`, công cụ sinh changelog) coi dòng đầu tiên là title, phần sau dòng trống là body. Thiếu dòng trống → toàn bộ bị hiểu là title dài.

**8.** Build artifact (image) **một lần** từ một commit, rồi đưa chính artifact đó qua các môi trường. Cách "một nhánh + tag": image build khi merge vào `main`, tag chỉ là nhãn cho commit/image đã có → production nhận đúng thứ đã test. Cách "nhánh theo môi trường": mỗi lần merge sang nhánh môi trường lại build lại → artifact ở staging và production có thể khác nhau (dependency đổi, merge lệch), và các nhánh dễ trôi khỏi nhau.

**9.** Được dùng trên **nhánh của riêng bạn** sau khi rebase hoặc sửa commit đã push. Tuyệt đối không dùng trên `main` hoặc nhánh nhiều người cùng làm (đã được chặn bởi branch protection ở `main`).

**10.** Monorepo nhỏ (`app/`, `infra/`, `k8s/`, `docs/` cùng một repo). Ảnh hưởng: workflow CI nên lọc theo thư mục thay đổi (`paths:`) — sửa `docs/` không cần build lại app, sửa `infra/` thì chạy job Terraform.

**11.** Quan sát: conflict lớn khi gộp, đợt release kéo dài, lỗi tích hợp phát hiện muộn, nhánh `release` quên gộp về `develop`. Đề xuất: chia việc nhỏ, PR vào nhánh tích hợp hằng ngày; CI trên mọi PR; nếu sản phẩm là web app chỉ một phiên bản production thì cân nhắc chuyển dần sang GitHub Flow + tag. Trình bày bằng số liệu (thời gian release, số conflict) thay vì ý kiến cá nhân.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Chọn quy trình

| Tình huống | Chọn | Lý do |
|---|---|---|
| (a) App mobile, phát hành tháng, hỗ trợ bản cũ 6 tháng | **Git Flow** (hoặc biến thể có nhánh `release`) | Phát hành theo đợt, cần giai đoạn ổn định hóa và vá bản cũ |
| (b) API nội bộ, 4 người, deploy vài lần/tuần | **GitHub Flow** | Đơn giản, một phiên bản production, đủ CI qua PR |
| (c) 200 kỹ sư, 50 deploy/ngày, có feature flag | **Trunk-based** | Tích hợp liên tục ở quy mô lớn, feature flag thay cho nhánh dài |
| (d) Thư viện OSS, v2 và v3 cùng bảo trì | **Nhánh bảo trì theo dòng phiên bản** (`main` cho v3, `v2.x` cho v2) — gần Git Flow | Phải vá lỗi song song nhiều dòng phiên bản |

### Bài 2 — Viết commit message

| | Commit | `0.4.1` → |
|---|---|---|
| (a) | `feat(api): filter tasks by status` | `0.5.0` |
| (b) | `fix(task): update updatedAt on modification` + body giải thích nguyên nhân | `0.4.2` |
| (c) | `feat(api)!: move endpoints from /tasks to /api/tasks` + footer `BREAKING CHANGE: client phải đổi đường dẫn sang /api/tasks` | Theo SemVer thuần: MAJOR → `1.0.0`. Lưu ý: ở giai đoạn `0.y.z` SemVer cho phép mọi thay đổi bất cứ lúc nào; nhiều công cụ chỉ tăng MINOR (`0.5.0`) cho breaking change khi MAJOR = 0. Chấp nhận cả hai nếu bạn giải thích được |
| (d) | `ci: add build workflow` | Không đổi |
| (e) | `chore(deps): bump postgresql driver to x.y.z` (hoặc `build(deps): ...`) | Không đổi (trừ khi nó sửa lỗi người dùng thấy được → có thể coi là `fix`) |

### Bài 3 — ADR quy trình

Đạt khi theo đúng mẫu (Trạng thái, Bối cảnh, Các lựa chọn, Quyết định, Hệ quả) và có ít nhất các ý:

- **Bối cảnh:** repo một người; mục tiêu học CI/CD; deploy lên một EC2; chỉ một phiên bản production; cần lịch sử dễ đọc để trình bày khi phỏng vấn.
- **Lựa chọn:** GitHub Flow; Git Flow (quá phức tạp cho một người, không cần nhiều phiên bản song song); trunk-based thuần không PR (mất bước review/CI trước khi vào `main`).
- **Quyết định:** GitHub Flow + squash merge + Conventional Commits + SemVer tag annotated.
- **Hệ quả:** (+) lịch sử `main` gọn, pipeline đơn giản, rollback theo tag; (−) mất lịch sử commit chi tiết của nhánh; không hỗ trợ tốt việc vá song song nhiều phiên bản — chấp nhận vì không có nhu cầu này.

### Bài 4 — Vẽ lại Git Flow

Một trình tự hợp lệ (rút gọn):

```bash
git init -b main gitflow && cd gitflow && git commit --allow-empty -m "init"
git switch -c develop
git switch -c feature/x develop && git commit --allow-empty -m "x1" && git commit --allow-empty -m "x2"
git switch develop && git merge --no-ff feature/x -m "Merge feature/x"
git switch -c feature/y develop && git commit --allow-empty -m "y1"
git switch develop && git merge --no-ff feature/y -m "Merge feature/y"
git switch -c release/1.0 develop && git commit --allow-empty -m "bump version 1.0"
git switch main && git merge --no-ff release/1.0 -m "Release 1.0" && git tag -a v1.0 -m "1.0"
git switch develop && git merge --no-ff release/1.0 -m "Back-merge release/1.0"
git switch -c hotfix/1.0.1 main && git commit --allow-empty -m "fix"
git switch main && git merge --no-ff hotfix/1.0.1 -m "Hotfix 1.0.1" && git tag -a v1.0.1 -m "1.0.1"
git switch develop && git merge --no-ff hotfix/1.0.1 -m "Back-merge hotfix"
git log --oneline --graph --all
```

Số lần merge: **6**. Cùng lượng công việc với GitHub Flow + squash: 4 PR (x, y, bump version, fix) = 4 lần merge, không có merge ngược, đồ thị thẳng. Bài học: chi phí của Git Flow nằm ở các lần merge ngược (`release`/`hotfix` → `develop`) — rất dễ quên.

### Bài 5 — Môi trường và tag

```text
PR merge vào main
   │  CI (Module 05): test → build image MỘT LẦN
   ▼
ghcr.io/<user>/taskhub:<sha>  ──► (tùy chọn) môi trường dev/staging chạy :<sha>
   │
   │  git tag -a v0.3.0 trên đúng commit <sha>, push tag
   ▼
CI gắn thêm tag :v0.3.0 cho CHÍNH image :<sha> (không build lại)
   │
   ▼
EC2 production chạy taskhub:v0.3.0
   │ lỗi → chạy lại taskhub:v0.2.1 (rollback)
```

Điểm mấu chốt: image production là **cùng một image** đã chạy ở bước trước — chỉ thêm nhãn.
