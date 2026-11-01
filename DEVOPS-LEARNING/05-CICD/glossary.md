# Thuật ngữ Module 05 — CI/CD

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó. Branch protection, status check, tag, SemVer đã gặp ở [glossary Git](../03-GIT/glossary.md); image, layer, registry, Trivy ở [glossary Docker](../04-DOCKER/glossary.md).

## Mục lục

- [Khái niệm CI/CD (bài 01)](#khái-niệm-cicd-bài-01)
- [GitHub Actions cơ bản (bài 02)](#github-actions-cơ-bản-bài-02)
- [Image và registry trong pipeline (bài 03)](#image-và-registry-trong-pipeline-bài-03)
- [Secrets, quyền, môi trường, chuỗi cung ứng (bài 04)](#secrets-quyền-môi-trường-chuỗi-cung-ứng-bài-04)
- [Chiến lược triển khai và rollback (bài 05)](#chiến-lược-triển-khai-và-rollback-bài-05)
- [GitLab CI và Jenkins (bài 06)](#gitlab-ci-và-jenkins-bài-06)

---

## Khái niệm CI/CD (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Continuous Integration (CI) | Tích hợp liên tục | Mỗi thay đổi được gộp thường xuyên và tự động build + test. |
| Continuous Delivery | Phân phối liên tục | Mọi commit qua pipeline đều **sẵn sàng** triển khai; người quyết định bấm deploy. |
| Continuous Deployment | Triển khai liên tục | Commit qua pipeline được **tự động** triển khai lên production. |
| Pipeline | Đường ống | Chuỗi bước tự động từ commit đến artifact/triển khai. |
| Stage / job / step | Giai đoạn / công việc / bước | Các mức chia nhỏ của pipeline. |
| Artifact | Sản phẩm build | Kết quả của build (jar, image, báo cáo test) được lưu lại để dùng tiếp. |
| Build once, deploy many | Build một lần, triển khai nhiều nơi | Cùng một artifact đi qua mọi môi trường. |
| Fail fast | Hỏng sớm | Bước rẻ và nhanh chạy trước để báo lỗi sớm nhất. |
| Shift left | Dịch sang trái | Kiểm tra (test, bảo mật) sớm hơn trong quy trình. |
| Pipeline as code | Pipeline dạng code | Định nghĩa pipeline nằm trong repo, được review và versioning như code. |
| Ephemeral runner | Runner dùng một lần | Máy chạy job được tạo mới cho mỗi job rồi bị hủy. |
| DORA metrics | Chỉ số DORA | Bộ chỉ số đo hiệu quả phân phối phần mềm: tần suất deploy, lead time, tỷ lệ lỗi thay đổi, thời gian khôi phục… |

## GitHub Actions cơ bản (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Workflow | Quy trình tự động | File YAML trong `.github/workflows/`. |
| Event / trigger | Sự kiện kích hoạt | `push`, `pull_request`, `workflow_dispatch`, `schedule`… |
| Runner | Máy chạy | Máy thực thi job; GitHub-hosted là VM mới cho mỗi job. |
| Runner label | Nhãn runner | Giá trị của `runs-on`, ví dụ `ubuntu-24.04`. |
| Action | Hành động đóng gói sẵn | Bước tái sử dụng được, gọi bằng `uses: owner/repo@ref`. |
| `needs` | Phụ thuộc | Job chỉ chạy sau khi các job được liệt kê thành công. |
| `if` | Điều kiện | Biểu thức quyết định job/step có chạy không. |
| Context / expression | Ngữ cảnh / biểu thức | `${{ github.sha }}`, `${{ env.X }}` — được thay **trước** khi step chạy. |
| Step output | Đầu ra của bước | Giá trị ghi vào `$GITHUB_OUTPUT`, đọc bằng `steps.<id>.outputs.<tên>`. |
| Service container | Container dịch vụ | Container phụ (PostgreSQL…) chạy kèm job trong suốt thời gian job. |
| `working-directory` | Thư mục làm việc | Chỉ áp dụng cho bước `run:`, không áp dụng cho bước `uses:`. |
| Default shell | Shell mặc định | `bash -e {0}` khi không ghi `shell:`; `shell: bash` thêm `-o pipefail`. |
| Cache | Bộ nhớ đệm | Lưu thư mục (ví dụ `~/.m2`) giữa các lần chạy theo khóa (key). |
| Matrix | Ma trận | Chạy cùng một job với nhiều tổ hợp tham số. |
| Concurrency | Đồng thời | Nhóm các lần chạy; có thể hủy lần chạy cũ khi có lần mới. |
| Required status check | Kiểm tra bắt buộc | Job phải xanh thì PR mới merge được. |
| Annotation | Chú thích | Thông báo lỗi/cảnh báo hiển thị trên trang tóm tắt của run. |
| actionlint | Công cụ lint workflow | Kiểm tra workflow tĩnh trước khi push. |

## Image và registry trong pipeline (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Buildx / BuildKit | Công cụ build image | Bộ build hiện đại của Docker; cần cho cache `type=gha`. |
| metadata-action | Action sinh tag/label | Tạo tên image (chữ thường), tag (SHA, SemVer…) và label OCI. |
| `load` / `push` | Nạp / đẩy | Đưa image vào Docker của runner / đẩy lên registry. |
| GHA cache | Cache của GitHub Actions | Lưu layer image giữa các lần chạy (`cache-to: type=gha,mode=max`). |
| Scan before push | Quét trước khi đẩy | Image có lỗ hổng vượt ngưỡng không bao giờ lên registry. |
| Gate | Cổng chặn | Bước làm pipeline đỏ khi vi phạm quy tắc (ví dụ Trivy `exit-code: 1`). |
| Promote | Thăng cấp image | Gắn thêm tag (ví dụ `:v0.3.0`) cho image đã có, không build lại. |
| Image index | Danh mục image | Manifest trỏ tới nhiều manifest (nhiều nền tảng, attestation). |
| Provenance attestation | Chứng thực nguồn gốc | Bản ghi image được build từ đâu, thế nào; hiện là nền tảng `unknown/unknown` trên GHCR. |
| Pre-release | Bản tiền phát hành | Release ứng viên (`v0.3.0-rc.1`), không mang nhãn Latest. |
| Manage Actions access | Quản lý quyền Actions | Cài đặt package GHCR cho phép repo nào push/pull bằng `GITHUB_TOKEN`. |

## Secrets, quyền, môi trường, chuỗi cung ứng (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Secret | Bí mật | Giá trị mã hóa (`secrets.X`), bị che (`***`) trong log. |
| Variable | Biến cấu hình | Giá trị không nhạy cảm (`vars.X`). |
| Masking | Che giá trị | Log thay secret bằng `***`; giá trị bị biến đổi (đảo ngược, base64) thì không bị che. |
| `GITHUB_TOKEN` | Token tự động | Token sinh cho mỗi job, hết hạn khi job xong; quyền đặt bằng `permissions:`. |
| Least privilege | Quyền tối thiểu | Chỉ cấp đúng quyền cần thiết. |
| Environment | Môi trường triển khai | Nhóm secret + luật bảo vệ (người duyệt, thời gian chờ, nhánh được phép). |
| Required reviewer | Người duyệt bắt buộc | Job vào environment phải được người này duyệt. |
| Script injection | Chèn mã vào script | Dữ liệu người ngoài kiểm soát (tiêu đề PR…) được nhúng thẳng `${{ }}` vào `run:`. |
| `pull_request_target` | Sự kiện PR chạy với quyền repo đích | Có secret và token ghi — nguy hiểm khi chạy code từ fork. |
| Supply chain attack | Tấn công chuỗi cung ứng | Chèn mã độc vào thành phần bạn phụ thuộc (action, thư viện, image). |
| Pin to SHA | Ghim theo SHA | `uses: owner/repo@<40 ký tự>` — không bị đổi khi tag bị push đè. |
| Peeled tag (`^{}`) | Tag đã "bóc" | Commit mà tag có chú thích trỏ tới — SHA đúng để ghim. |
| Dependabot | Bot cập nhật phụ thuộc | Tự mở PR khi action/thư viện/base image có bản mới. |
| `persist-credentials` | Giữ thông tin đăng nhập | `false` để checkout không để lại token trong `.git/config`. |
| OIDC | Danh tính liên kết | Workflow đổi token ngắn hạn lấy quyền cloud tạm thời — không lưu access key (v3). |

## Chiến lược triển khai và rollback (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Recreate | Tạo lại | Dừng bản cũ rồi chạy bản mới — có downtime. |
| Rolling update | Cập nhật cuốn chiếu | Thay dần từng instance. |
| Blue/green | Xanh/lục | Hai môi trường song song, chuyển toàn bộ traffic một lần. |
| Canary | Chim hoàng yến | Đưa bản mới cho một phần nhỏ traffic trước. |
| Feature flag | Cờ tính năng | Bật/tắt tính năng bằng cấu hình, tách deploy khỏi phát hành. |
| Smoke test | Kiểm tra khói | Kiểm tra nhanh ngay sau deploy rằng hệ thống sống và chức năng chính chạy. |
| Rollback / roll forward | Quay lui / sửa tiến | Triển khai lại bản cũ / triển khai nhanh bản sửa mới. |
| Downtime | Thời gian ngừng | Khoảng thời gian người dùng không truy cập được. |
| Expand/contract | Mở rộng/thu hẹp | Đổi schema database qua nhiều bước tương thích ngược để rollback được. |
| Backward compatible | Tương thích ngược | Bản cũ vẫn chạy đúng với schema/API mới. |

## GitLab CI và Jenkins (bài 06)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| `.gitlab-ci.yml` | File pipeline GitLab | Định nghĩa stages và jobs của GitLab CI. |
| GitLab Runner | Máy chạy GitLab | Tương đương runner của GitHub Actions. |
| `rules` | Luật chạy job | Điều kiện job có chạy trong GitLab CI. |
| Jenkins controller / agent | Máy điều khiển / máy chạy | Controller quản lý, agent thực thi build. |
| Jenkinsfile | File pipeline Jenkins | Pipeline dạng code, cú pháp Declarative (`pipeline { stages { ... } }`). |
| Plugin | Phần mở rộng | Hầu hết tính năng Jenkins đến từ plugin — cần cập nhật và rà soát. |
| Multibranch Pipeline | Pipeline đa nhánh | Jenkins tự tạo pipeline cho mỗi nhánh/PR có Jenkinsfile. |
| Credentials | Thông tin xác thực | Kho secret của Jenkins, dùng bằng `credentials()`. |
| LTS | Hỗ trợ dài hạn | Dòng phát hành ổn định của Jenkins. |
