# Thuật ngữ Module 03 — Git & Workflow

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó.

## Mục lục

- [Cơ bản (bài 00)](#cơ-bản-bài-00)
- [Bên trong Git (bài 01)](#bên-trong-git-bài-01)
- [Nhánh, merge, conflict (bài 02 + lab)](#nhánh-merge-conflict-bài-02--lab)
- [GitHub, Pull Request, review (bài 03)](#github-pull-request-review-bài-03)
- [Quy trình làm việc nhóm (bài 04)](#quy-trình-làm-việc-nhóm-bài-04)
- [Tag, release, phiên bản (bài 05)](#tag-release-phiên-bản-bài-05)

---

## Cơ bản (bài 00)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Repository (repo) | Kho mã | Thư mục `.git` chứa toàn bộ lịch sử commit của dự án. |
| Working directory | Thư mục làm việc | Các file bạn đang thấy và sửa. |
| Staging area (index) | Vùng chuẩn bị | Danh sách thay đổi sẽ đi vào commit tiếp theo. |
| Commit | Lần ghi nhận | Ảnh chụp dự án kèm tác giả, thời gian, lời nhắn. |
| Remote / origin | Kho từ xa | Repo trên server như GitHub; `origin` là tên mặc định. |
| Push / Pull / Fetch | Đẩy lên / kéo về và gộp / kéo về | Đồng bộ commit giữa local và remote. |
| `.gitignore` | Danh sách bỏ qua | Mẫu tên file Git không theo dõi. |
| `.gitattributes` | Thuộc tính file | Quy định cách Git xử lý file, ví dụ ép LF. |
| SSH key / fingerprint | Cặp khóa SSH / dấu vân tay | Khóa công khai đưa lên GitHub; vân tay để xác minh server. |
| Conventional Commits | Quy ước commit | Định dạng `type(scope): mô tả`. |
| Secret / rotate | Bí mật / xoay vòng | Thay secret đã lộ bằng secret mới và vô hiệu hóa cái cũ. |

## Bên trong Git (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Snapshot | Ảnh chụp | Mỗi commit lưu trạng thái toàn bộ dự án, không phải diff. |
| Content-addressable | Đánh địa chỉ theo nội dung | Object được đặt tên bằng hash của chính nội dung. |
| SHA-1 / hash | Hàm băm | Chuỗi 40 ký tự hex định danh một object. |
| Blob / Tree / Commit object | Đối tượng nội dung / cây / commit | Nội dung file / một thư mục / ảnh chụp trỏ tới tree gốc và commit cha. |
| Ref | Tham chiếu | Tên dễ nhớ trỏ tới một SHA (branch, tag, HEAD). |
| HEAD / detached HEAD | Con trỏ hiện tại / HEAD tách rời | Đang đứng ở đâu / HEAD trỏ thẳng commit thay vì nhánh. |
| Three trees | Ba cây | HEAD, index, working directory — ba thứ `reset` thao tác. |
| Reset (soft/mixed/hard) | Đặt lại | Dời nhánh và đồng bộ index/working directory ở mức tương ứng. |
| Revert | Hoàn tác | Tạo commit mới đảo ngược commit cũ, không viết lại lịch sử. |
| Reflog | Nhật ký tham chiếu | Lịch sử di chuyển của HEAD, chỉ ở local — cứu commit "mất". |
| Stash | Ngăn cất tạm | Cất thay đổi chưa commit để làm sạch working directory. |
| Blame / pickaxe (`log -S`) | Truy dòng / tìm theo nội dung | Ai sửa dòng này / commit nào thêm hoặc xóa một chuỗi. |

## Nhánh, merge, conflict (bài 02 + lab)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Merge base | Tổ tiên chung | Commit gần nhất có trong lịch sử của cả hai nhánh. |
| Fast-forward | Tua nhanh | Merge chỉ bằng cách dời con trỏ. |
| 3-way merge / merge commit | Hợp nhất 3 chiều / commit hợp nhất | Merge dựa trên 3 snapshot, tạo commit có hai cha. |
| Rebase / interactive rebase | Chuyển gốc / rebase tương tác | Phát lại commit lên gốc mới / gộp, sửa, đổi thứ tự commit trước khi chia sẻ. |
| Conflict markers | Dấu xung đột | `<<<<<<<`, `=======`, `>>>>>>>` bao quanh hai phiên bản. |
| Modify/delete conflict | Xung đột sửa/xóa | Một bên sửa file, bên kia xóa file đó. |
| Ours / theirs | Phía mình / phía kia | Hai phiên bản khi conflict; đảo chiều khi rebase. |
| Remote-tracking branch | Nhánh theo dõi từ xa | `origin/main` — bản sao chỉ đọc từ lần fetch gần nhất. |
| Upstream | Nhánh thượng nguồn | Nhánh remote gắn với nhánh local, dùng cho push/pull, ahead/behind. |
| `--force-with-lease` | Đẩy ép có kiểm tra | Force push nhưng từ chối nếu remote có commit bạn chưa thấy. |
| Cherry-pick | Nhặt commit | Áp dụng thay đổi của một commit sang nhánh hiện tại. |
| Bare repository | Kho trần | Repo không có working directory, dùng làm server. |

## GitHub, Pull Request, review (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Pull Request / Merge Request | Yêu cầu gộp | Đề nghị gộp nhánh nguồn vào nhánh đích, kèm diff, thảo luận, review, CI. |
| Base / head branch | Nhánh đích / nhánh nguồn | Nơi thay đổi sẽ vào / nhánh chứa thay đổi. |
| Fork | Bản sao repo | Bản sao toàn bộ repo sang tài khoản khác, dùng khi không có quyền ghi. |
| Draft PR / PR template | PR nháp / mẫu PR | PR chưa sẵn sàng merge / mô tả tự điền khi mở PR. |
| Merge commit / Squash / Rebase merge | Ba kiểu merge | Giữ lịch sử + commit gộp / gộp thành một commit / viết lại thành đường thẳng. |
| Code review | Duyệt code | Đọc và góp ý thay đổi trước khi merge (Approve / Request changes / Comment). |
| Branch protection rule / Ruleset | Luật bảo vệ nhánh / bộ luật | Ràng buộc trên nhánh: bắt PR, status check, chặn force push. |
| Bypass | Bỏ qua luật | Admin được bỏ qua bảo vệ nhánh trừ khi bật *Do not allow bypassing*. |
| Status check | Kiểm tra trạng thái | Kết quả CI gắn vào PR, có thể bắt buộc xanh mới merge. |
| CODEOWNERS | Chủ sở hữu code | File gán người review cho từng đường dẫn. |
| Closing keyword | Từ khóa đóng issue | `Closes #N` trong PR tự đóng issue khi merge. |

## Quy trình làm việc nhóm (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Branching workflow | Quy trình phân nhánh | Thỏa thuận của team về nhánh, cách gộp, lúc tag/deploy. |
| GitHub Flow / Git Flow / Trunk-based | Ba quy trình | Một nhánh chính + PR / main + develop + release/hotfix / trunk + nhánh cực ngắn. |
| Feature flag | Cờ tính năng | Bật/tắt tính năng bằng cấu hình, tách deploy khỏi phát hành. |
| Breaking change | Thay đổi phá vỡ tương thích | Đánh dấu bằng `!` hoặc `BREAKING CHANGE:` trong commit. |
| Environment (dev/staging/prod) | Môi trường | Các nơi chạy phần mềm với mục đích khác nhau. |
| Build once, deploy many | Build một lần, triển khai nhiều nơi | Cùng một artifact đi qua mọi môi trường. |
| Monorepo / polyrepo | Một repo / nhiều repo | Nhiều dự án chung repo / mỗi dự án một repo. |
| ADR | Bản ghi quyết định kiến trúc | File ngắn ghi một quyết định, lý do, hệ quả. |

## Tag, release, phiên bản (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Lightweight / annotated tag | Tag nhẹ / tag có chú thích | Tên trỏ thẳng commit / đối tượng tag có người tạo, ngày, thông điệp. |
| Semantic Versioning | Phiên bản ngữ nghĩa | MAJOR.MINOR.PATCH — mỗi phần là một lời hứa về tương thích. |
| Pre-release / build metadata | Bản trước phát hành / siêu dữ liệu build | `-rc.1` xếp trước bản chính thức / `+...` bị bỏ qua khi so sánh. |
| Release / release notes | Bản phát hành / ghi chú phát hành | Trang GitHub gắn với tag, có ghi chú và file đính kèm. |
| CHANGELOG | Nhật ký thay đổi | File ghi thay đổi theo phiên bản cho con người đọc. |
| Immutable tag | Tag bất biến | Không bao giờ bị sửa — nền tảng của rollback đáng tin. |
| `git describe` | Mô tả commit theo tag | Dạng `tag-N-gSHA`, mặc định chỉ dùng annotated tag. |
| Signed tag | Tag ký số | Tag ký GPG/SSH chứng minh người tạo. |
