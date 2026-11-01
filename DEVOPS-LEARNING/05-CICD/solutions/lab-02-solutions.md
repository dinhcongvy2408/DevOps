# Lời giải — Lab 02: Build image trong CI, đẩy lên GHCR và phát hành bằng tag

> ⚠️ Chỉ đọc sau khi đã tự làm. SHA, digest, thời gian dưới đây là minh họa; username `phuong-dev` là ví dụ.

Quay lại lab: [lab-02-release-ghcr.md](../labs/lab-02-release-ghcr.md)

## Mục lục

- [Phần A — Câu hỏi trong các bước](#phần-a--câu-hỏi-trong-các-bước)
- [Phần B — Câu hỏi sau lab (mục 8)](#phần-b--câu-hỏi-sau-lab-mục-8)
- [Phần C — Tự đánh giá](#phần-c--tự-đánh-giá)

---

## Phần A — Câu hỏi trong các bước

**A1 — Mỗi PR một mục đích.** Review: người đọc phải giữ hai mạch suy nghĩ cùng lúc ("image build đúng chưa?" và "release làm đúng chưa?"), dễ bỏ sót. Rollback: nếu job `image` gây sự cố, revert commit squash của PR sẽ gỡ luôn `release.yml` vốn không có lỗi. Lịch sử: một commit một ý → `git log`, `git bisect`, release notes tự sinh đều rõ ràng hơn.

**A3 — SHA khác commit cuối nhánh.** Trên `pull_request`, workflow chạy trên merge commit tạm `refs/pull/<số>/merge` (đầu nhánh PR gộp với `main` hiện tại). Metadata-action dùng SHA đó. Không gây hại vì PR không push image.

**A4 — Chỉ yêu cầu `build-test`.** PR làm Trivy đỏ vẫn merge được: branch protection chỉ chặn theo các check được liệt kê. Cổng chặn cần **cả hai**: bước Trivy có `exit-code: '1'` **và** job chứa nó là required check.

**A5 — `<sha7-A>` là commit nào.** Commit squash mới tạo trên `main` khi merge. Squash merge tạo commit **mới** (SHA mới) chứa toàn bộ thay đổi của PR; các commit trên nhánh PR không vào `main`. Vì vậy tag image trên GHCR khớp `git rev-parse --short=7 HEAD` của `main` sau khi pull, không khớp commit nào trên nhánh `ci/build-push-image`.

**A6 — MediaType.** `application/vnd.oci.image.index.v1+json`, có `linux/amd64` + `unknown/unknown` (attestation provenance được thêm khi push từ `build-push-action`). Image `v0.2.0` push tay từ laptop thường không có attestation provenance của GitHub Actions; tùy cấu hình Docker Desktop, nó là manifest đơn hoặc một index không có dòng attestation như vậy.

**B1 — Release không chạy trên PR.** Trigger của `release.yml` chỉ là `push: tags: ['v*.*.*']`. Trước khi merge, thứ kiểm tra nó chỉ có: actionlint trên máy và chính bạn khi review diff. Đây là điểm yếu chung của workflow chạy theo tag/lịch — lý do lab có buổi diễn tập với tag rc.

**B2 — Commit được tag phải có `release.yml`.** Với sự kiện push tag, GitHub dùng file workflow **trong commit được tag**. Tag một commit trước khi `release.yml` vào `main` → không có workflow nào khớp → không có lần chạy.

**B3 — Lỗi hay hành vi đúng?** Hành vi đúng: image của commit đó chưa được build và quét xong, nên không được phát hành. Không có bước kiểm tra, `docker buildx imagetools create` cũng thất bại (nguồn không tồn tại) nhưng thông báo là lỗi kỹ thuật của registry, không nói cho người đọc **vì sao** và **phải làm gì**. Bước kiểm tra + `::error::` biến một lỗi khó hiểu thành hướng dẫn hành động.

**B4 — `GITHUB_SHA` khi re-run.** Của sự kiện ban đầu. Tài liệu GitHub (*Re-running workflows and jobs*): re-run dùng cùng `GITHUB_SHA` và `GITHUB_REF` của sự kiện gốc. Nhờ vậy re-run tìm đúng `<sha7-B>` dù `main` có thể đã có commit mới hơn.

**B5 — Pre-release hay Latest.** Release thường, có thể được gắn Latest: workflow không truyền `--prerelease`, `gh release create` không suy ra pre-release từ tên tag, và nhãn Latest mặc định được chọn tự động theo ngày/phiên bản. Sửa: [bài tập 2 bài 03](03-solutions.md#bài-2--pre-release-đúng-nghĩa).

**C1 — Digest trùng.** Trùng. Nó chứng minh `:v0.3.0-rc.1` và `:<sha7-B>` là **cùng một image index**, byte theo byte — image phát hành chính là image CI đã build và quét. Hai tên tag không chứng minh được điều này; digest thì có.

**C2 — Label `revision`.** Trùng với `git rev-parse v0.3.0-rc.1^{commit}` (SHA đầy đủ). Label do `docker/metadata-action` sinh và `build-push-action` gắn lúc build trong CI. `^{commit}` "bóc" tag annotated ra commit nó trỏ tới (đối tượng tag có SHA riêng — [Git 01](../../03-GIT/01-git-fundamentals-internals.md)).

**C3 — Đếm lần build.** Không có dòng `#N [build ...]` hay `exporting layers` nào trong job `promote`. Chỉ có thao tác trên registry.

**D2 — Server cần gì.** Không cần mã nguồn, Maven hay JDK. Server chỉ cần Docker + Compose, file `compose.yaml`, file `.env` (mật khẩu thật, tag image) và quyền kéo image (image public: không cần đăng nhập). Đó chính là cách triển khai ở dự án v2 (tuần 12).

---

## Phần B — Câu hỏi sau lab (mục 8)

**1.** Workflow trên PR chạy trên merge commit tạm `refs/pull/<số>/merge`, nên SHA trong log là của commit đó. Không hại gì: image trên PR chỉ được build và quét để chặn lỗi, không push, nên tag của nó không bao giờ xuất hiện trên registry.

**2.** Cần (a) bước Trivy có `exit-code: '1'` để job đỏ khi có lỗ hổng, và (b) job `image` là required status check trong luật bảo vệ `main`. Thiếu (a): job luôn xanh, không có gì để chặn. Thiếu (b): job đỏ nhưng nút merge vẫn bấm được.

**3.** Mẫu postmortem ngắn:

```markdown
## Postmortem: Release v0.3.0-rc.1 thất bại lần đầu

- Tóm tắt: Workflow Release đỏ vì image của commit được tag chưa có trên GHCR.
- Tác động: Không có (diễn tập). Release chậm ~6 phút.
- Dòng thời gian: 10:02 merge PR release → 10:02 push tag → 10:03 promote đỏ
  ("Không tìm thấy ghcr.io/phuong-dev/taskhub:9b3f0a1") → 10:08 CI main xanh
  → 10:09 re-run failed jobs → xanh.
- Nguyên nhân gốc: tag được push khi CI trên main chưa xong; release phụ thuộc
  image do CI tạo ra.
- Phát hiện: chú thích ::error:: trên trang tóm tắt lần chạy Release.
- Khắc phục: chờ CI xanh, re-run (dùng lại GITHUB_SHA của sự kiện tag).
- Phòng ngừa: runbook phát hành ghi rõ "chỉ tag sau khi CI main xanh";
  kiểm tra nhanh bằng `docker buildx imagetools inspect ...:<sha7>` trước khi tag.
```

**4.** "Cùng tên tag" không chứng minh gì về nội dung — tag có thể bị push đè bất cứ lúc nào. Digest gắn với nội dung: hai tag cùng digest nghĩa là cùng một image index, nên image phát hành chính là image đã được test và quét.

**5.** CI đỏ ở Trivy → bước push không chạy → không có `:<sha7>` → `promote` báo không tìm thấy và từ chối phát hành. Đó là **ưu điểm** (không bao giờ phát hành image chưa qua cổng quét). Nhược điểm nhỏ: muốn phát hành gấp phải sửa lỗ hổng trước (thường là cập nhật base image), tạo commit mới trên `main`, rồi tag commit mới đó.

**6.** Version trên GHCR gắn với một digest và chứa mọi tag trỏ tới digest đó. Xóa version của bản rc = xóa luôn `:<sha7-B>`, image của một commit trên `main`. Tình huống thật: production đang chạy bằng `:<sha7>` (dự án v3 deploy theo SHA), ai đó "dọn" version chứa tag rc → server không kéo lại được image khi khởi động lại hoặc khi scale thêm máy, và rollback về bản đó cũng không còn image. Khôi phục chỉ được trong 30 ngày theo tài liệu GitHub — và chỉ khi bạn biết đi khôi phục.

---

## Phần C — Tự đánh giá

Lab đạt khi:

- [ ] `image` là required check; chứng minh bằng ảnh chụp luật bảo vệ hoặc một PR bị chặn.
- [ ] Trên GHCR có `:<sha7-A>`, `:<sha7-B>`, `:v0.3.0-rc.1`; `:v0.3.0-rc.1` và `:<sha7-B>` **cùng digest** (ghi digest thật vào `lab02-answers.md`).
- [ ] Có link tới lần chạy Release đỏ và lần re-run xanh.
- [ ] Release `v0.3.0-rc.1` đã được đánh dấu pre-release.
- [ ] Image `:v0.3.0-rc.1` chạy được trên máy từ GHCR, health `UP`.
- [ ] Giải thích được bằng lời: vì sao release không build lại, vì sao tag phải đi sau CI xanh, vì sao không xóa version GHCR của bản rc.
