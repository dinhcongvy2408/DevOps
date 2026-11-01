# Lời giải — Bài 05: Tags, Releases & Semantic Versioning

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [05-tags-releases-versioning.md](../05-tags-releases-versioning.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Branch là con trỏ **di chuyển** theo mỗi commit mới; tag là con trỏ **đứng yên**, đánh dấu vĩnh viễn một commit.

**2.** Lightweight chỉ là tên trỏ thẳng commit; annotated là đối tượng tag riêng có người tạo, email, ngày, thông điệp, có thể ký số. Release dùng annotated: có thông tin ai/khi nào/vì sao phát hành, được `git describe` dùng mặc định, được Pro Git khuyến nghị cho release.

**3.** Không. `git push origin <tag>` (một tag) hoặc `git push origin --tags` (mọi tag chưa có trên remote). Rủi ro của `--tags`: đẩy cả tag thử nghiệm/cá nhân lên remote, có thể kích hoạt pipeline release (Module 05) ngoài ý muốn.

**4.** (a) `1.4.3`; (b) `1.5.0`; (c) `2.0.0`.

**5.** Giai đoạn phát triển ban đầu — mọi thứ có thể thay đổi bất cứ lúc nào, API chưa ổn định. `taskhub` mới bắt đầu, API còn thay đổi, nên chưa hứa hẹn ổn định của `1.0.0`.

**6.** `0.9.9` < `1.0.0-rc.1` < `1.0.0-rc.2` < `1.0.0` < `1.0.1`.

**7.** Không. Phiên bản là `1.2.3`; `v` là tiền tố quy ước khi đặt tên tag.

**8.** Máy người khác và CI đã fetch tag cũ sẽ giữ nguyên tag cũ (Git không tự cập nhật tag đã có) → cùng tên trỏ hai commit. Hậu quả: (1) image `:v0.1.0` đã build không khớp với code mà tag mới trỏ tới → không biết production chạy gì; (2) rollback về "v0.1.0" không đáng tin; (3) pipeline có thể build lại và ghi đè image.

**9.** Sửa trên nhánh `fix/...` từ `main` → PR → CI → squash merge → tag `v0.3.1` → release → deploy. Không sửa, không xóa `v0.3.0`.

**10.** Release notes, tiêu đề, file nén source code (zip, tar.gz) tự tạo, assets đính kèm tùy chọn, đánh dấu pre-release/latest.

**11.** Tag `v0.1.0` trỏ commit `3f2a9c1`; CI build image từ commit đó và gắn `:3f2a9c1` và `:v0.1.0`; EC2 chạy image đó. Khi lỗi, chuyển sang image của tag trước — đã có sẵn, bất biến, không cần build hay sửa code.

**12.** Commit hiện tại đi sau annotated tag `v0.2.0` **5** commit, SHA rút gọn `1a2b3c4` (`g` = git).

**13.** `latest` luôn bị ghi đè → không biết chính xác production đang chạy phiên bản nào, không rollback được về "latest trước đó", và hai máy pull vào hai thời điểm có thể chạy hai phiên bản khác nhau.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Tính phiên bản

**Phát hành sau mỗi PR làm thay đổi phiên bản:**

| PR | Ảnh hưởng | Phiên bản |
|---|---|---|
| `docs: update README` | Không | (vẫn `0.4.1`, không phát hành) |
| `fix(api): return 404 for missing task` | PATCH | `0.4.2` |
| `feat(api): add pagination` | MINOR | `0.5.0` |
| `chore: bump flyway` | Không | (không phát hành) |
| `feat(api)!: change task id from Long to UUID` | Breaking | SemVer thuần: `1.0.0`. Nhiều dự án ở giai đoạn `0.y.z` chọn tăng MINOR (`0.6.0`) cho breaking change vì "mọi thứ có thể thay đổi" |

**Phát hành một lần sau cả 5 PR:** lấy mức cao nhất trong các thay đổi → breaking → `1.0.0` (SemVer thuần) hoặc `0.5.0` (theo quy ước "breaking ở 0.y.z tăng MINOR"). Điều quan trọng là **dự án ghi rõ quy ước của mình** (trong `CONTRIBUTING.md` hoặc ADR) và áp dụng nhất quán. Chuyển sang `1.0.0` nên là quyết định có chủ ý ("API đã ổn định"), không phải tai nạn.

### Bài 2 — CHANGELOG

```markdown
## [0.5.0] - 2027-01-10
### Added
- Phân trang cho `GET /api/tasks`.

### Changed
- **BREAKING:** `id` của task đổi từ số nguyên sang UUID. Client phải cập nhật kiểu dữ liệu.

### Fixed
- `GET /api/tasks/{id}` trả 404 thay vì 500 khi task không tồn tại.
```

Không cần đưa vào: `docs: update README`, `chore: bump flyway` — không thay đổi hành vi người dùng thấy (Keep a Changelog: viết cho con người, chỉ những thay đổi đáng chú ý). Nếu nâng dependency để vá lỗ hổng bảo mật → đưa vào mục **Security**.

### Bài 3 — Pre-release

```bash
cd ~/devops-lab/03-git/tags-lab
for t in v1.0.0-rc.1 v1.0.0-rc.2 v1.0.0 v0.9.0 v0.10.0; do
  git commit --allow-empty -m "release $t" && git tag -a "$t" -m "$t"
done
git tag -l
git tag -l --sort=v:refname
```

Quan sát (minh họa):

- `git tag -l` sắp theo **thứ tự chữ**: `v0.10.0` đứng trước `v0.9.0` (vì ký tự `1` < `9`) — sai về mặt phiên bản.
- `--sort=v:refname` (version sort) đưa `v0.9.0` trước `v0.10.0` — đúng. **Nhưng** `v1.0.0` vẫn đứng **trước** `v1.0.0-rc.1`: tài liệu `git config` giải thích version sort vẫn so sánh hậu tố theo thứ tự chữ, nên tag pre-release xuất hiện **sau** bản chính thức.
- Sửa bằng cấu hình `versionsort.suffix`:

```bash
git config versionsort.suffix -rc
git tag -l --sort=v:refname
```

Lúc này `v1.0.0-rc.1`, `v1.0.0-rc.2` đứng trước `v1.0.0` — khớp thứ tự của SemVer. Bài học: đừng giả định công cụ hiểu SemVer; kiểm tra.

### Bài 4 — `release.yml`

Đạt khi: 3 label tồn tại trong repo; `.github/release.yml` đã vào `main` qua PR; ở release kế tiếp, nhấn *Generate release notes* thấy các PR được nhóm dưới tiêu đề tương ứng, PR không có label rơi vào nhóm "Khác" (`"*"`).

### Bài 5 — Kịch bản sự cố

**Vấn đề:**

- Image `taskhub:v0.2.0` trong registry được build từ commit cũ, nhưng tag Git `v0.2.0` giờ trỏ commit mới → hai nguồn sự thật mâu thuẫn.
- Máy đồng nghiệp/CI runner đã fetch trước vẫn giữ `v0.2.0` cũ; `git fetch` không tự ghi đè tag đã có → mỗi nơi hiểu "v0.2.0" một kiểu.
- Nếu pipeline release chạy lại khi tag được tạo lại → có thể ghi đè image `:v0.2.0` → rollback về `v0.2.0` không còn như trước.
- Release notes/CHANGELOG của `v0.2.0` không còn khớp code.

**Phát hiện:**

```bash
git ls-remote --tags origin | grep 'v0.2.0'     # commit mà remote đang trỏ (dòng ^{})
git rev-parse 'v0.2.0^{}'                        # commit mà tag local trỏ
git fetch --tags --force && git show v0.2.0 --no-patch   # xem tag mới: ai tạo, khi nào
```

So sánh với nhãn/metadata của image trong registry (Module 04–05: image thường ghi lại commit SHA trong label).

**Phòng ngừa:**

- Tạo **ruleset cho tag** trên GitHub: chặn xóa và cập nhật tag khớp mẫu `v*` (tìm trong GitHub Docs phần rulesets — mục tiêu áp dụng cho tag, các luật *Restrict deletions*, *Restrict updates*; ghi link nguồn bạn đã đọc).
- Registry: bật chế độ tag bất biến nếu registry hỗ trợ (ví dụ ECR có tag immutability — gặp ở Module 06), hoặc pipeline từ chối push đè tag SemVer đã tồn tại.
- Quy ước nhóm: lỗi trong bản đã phát hành → phát hành bản PATCH mới.
