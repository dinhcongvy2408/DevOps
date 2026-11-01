# Bản tham khảo workflow cho `taskhub` v1

> ⚠️ **Chỉ mở sau khi đã tự viết.** Mục tiêu của tuần 9–10 là bạn tự viết được từng dòng và giải thích được vì sao. Chép file này mà không hiểu thì phỏng vấn sẽ lộ ngay.

| File ở đây | Chép vào repo `taskhub` tại | Viết ở bài | Dùng trong |
|---|---|---|---|
| [workflows/ci.yml](workflows/ci.yml) | `.github/workflows/ci.yml` | [02](../../02-github-actions-basics.md) (job `build-test`), [03](../../03-github-actions-docker-registry.md) (job `image`) | [Lab 01](../lab-01-ci-pr-gate.md), [v1](../../../12-PRACTICAL-PROJECT/milestones/v1-ci.md) |
| [workflows/release.yml](workflows/release.yml) | `.github/workflows/release.yml` | [03](../../03-github-actions-docker-registry.md) | [Lab 02](../lab-02-release-ghcr.md), [v1](../../../12-PRACTICAL-PROJECT/milestones/v1-ci.md) |
| [dependabot.yml](dependabot.yml) | `.github/dependabot.yml` | [04](../../04-secrets-environments.md) | [v1](../../../12-PRACTICAL-PROJECT/milestones/v1-ci.md) |

## Luồng tổng thể

```text
 nhánh feat/*  ──PR──►  CI: build-test ──► image (build + Trivy, KHÔNG push)
                              │ xanh + branch protection cho phép
                              ▼
 merge vào main ───────► CI: build-test ──► image (build + Trivy + push ghcr.io/<user>/taskhub:<sha7>)
                              │ xanh
                              ▼
 git tag v0.3.0 + push ─► Release: tìm :<sha7> ──► gắn thêm :v0.3.0 (không build lại) ──► GitHub Release
```

## Các quyết định trong file và lý do

| Quyết định | Lý do | Học ở |
|---|---|---|
| `runs-on: ubuntu-24.04`, không dùng `ubuntu-latest` | `ubuntu-latest` đang được GitHub chuyển từ 24.04 sang 26.04 (19/10–19/11/2026). Ghim phiên bản để build không đổi hành vi bất ngờ | Bài 02 |
| Ghim action bằng SHA đầy đủ + ghi chú `# vX.Y.Z` | Tag có thể bị push đè. Tháng 3/2026, 76/77 tag của `aquasecurity/trivy-action` bị đổi thành mã độc đánh cắp secret | Bài 04 |
| `permissions: contents: read` ở đầu file | `GITHUB_TOKEN` chỉ có quyền cần thiết; job nào cần ghi thì tự xin | Bài 04 |
| Quét Trivy **trước** khi push | Image có lỗ hổng CRITICAL không bao giờ lên registry | Bài 03 |
| Release gắn tag cho image có sẵn thay vì build lại | Image chạy production chính là image đã được test và quét | Bài 03, 05 |
| Tag có dấu `-` (`v0.3.0-rc.1`) → `--prerelease --latest=false` | `gh release create` không tự suy ra pre-release từ tên tag. Đây là lời giải bài tập 2 của bài 03 — bản trong bài 03 chưa có, Lab 02 cho bạn tự thấy vấn đề trước | Bài 03, Lab 02 |
| Tag image giữ chữ `v` (`:v0.3.0`) | Khớp quy ước ở [Module 03](../../../03-GIT/05-tags-releases-versioning.md) và [Module 04](../../../04-DOCKER/06-registry.md) | Bài 03 |
| Mật khẩu PostgreSQL CI ghi thẳng trong YAML | Database tạm, chỉ sống trong runner dùng một lần, không chứa dữ liệu thật. Mật khẩu **thật** luôn là secret | Bài 04 |

## Phiên bản đã ghim (kiểm tra 2026-10-31)

| Action | Phiên bản | SHA commit |
|---|---|---|
| `actions/checkout` | v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-java` | v6.1.0 | `b843ebf9b913146b38da2eaa7aeddf76074ae1ad` |
| `actions/upload-artifact` | v7.0.2 | `cf430e030ddbb5b0abf93d22962f4752f3646cd9` |
| `docker/setup-buildx-action` | v4.4.1 | `f87e5991a6d7451dcb8d9637bfbc97413f497069` |
| `docker/metadata-action` | v6.2.0 | `dc802804100637a589fabce1cb79ff13a1411302` |
| `docker/build-push-action` | v7.4.0 | `c3c9e263c25d99ce0380d002d59b67737d91b0dc` |
| `docker/login-action` | v4.7.0 | `81c6f93d4bc991e510b342a00b419b3bb4efc5c6` |
| `aquasecurity/trivy-action` | v0.36.0 | `ed142fd0673e97e23eac54620cfb913e5ce36c25` (tag có chú thích — đây là SHA commit sau khi "bóc" `^{}`, không phải SHA của đối tượng tag `a9c7b0f…`) |

Tự kiểm tra lại (đừng tin bảng này mù quáng):

```bash
git ls-remote https://github.com/aquasecurity/trivy-action 'refs/tags/v0.36.0' 'refs/tags/v0.36.0^{}'
```

Khi bạn đọc file này, các action có thể đã có bản mới hơn. Đó là việc của Dependabot: nó mở PR, bạn đọc release notes, CI xanh thì merge.
