# Thuật ngữ Module 07 — Terraform & Ansible

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó. Tài nguyên AWS (VPC, IAM role, S3…) ở [glossary AWS](../06-AWS/glossary.md); idempotency của script Bash đã gặp ở [Linux bài 06](../01-LINUX/06-bash-scripting.md).

## Mục lục

- [Khái niệm IaC (bài 01)](#khái-niệm-iac-bài-01)
- [Terraform cơ bản (bài 02)](#terraform-cơ-bản-bài-02)
- [State và backend (bài 03)](#state-và-backend-bài-03)
- [Module và môi trường (bài 04)](#module-và-môi-trường-bài-04)
- [Ansible (bài 05)](#ansible-bài-05)

---

## Khái niệm IaC (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Infrastructure as Code (IaC) | Hạ tầng dạng code | Mô tả hạ tầng bằng file văn bản, được review, versioning và chạy lặp lại được. |
| Click-ops | Thao tác bằng chuột | Tạo hạ tầng bằng tay trên console — khó lặp lại, khó kiểm toán. |
| Declarative / imperative | Khai báo / mệnh lệnh | Mô tả **trạng thái mong muốn** / mô tả **các bước** phải làm. |
| Idempotency | Tính lũy đẳng | Chạy nhiều lần cho cùng kết quả như chạy một lần. |
| Desired state / actual state | Trạng thái mong muốn / thực tế | Code nói gì / hạ tầng đang thế nào. |
| Drift | Lệch cấu hình | Hạ tầng thật khác với code (thường do sửa tay). |
| Immutable / mutable infrastructure | Hạ tầng bất biến / khả biến | Thay mới thay vì sửa tại chỗ / sửa máy đang chạy. |
| Provisioning / configuration management | Cấp phát / quản lý cấu hình | Tạo tài nguyên (Terraform) / cấu hình bên trong máy (Ansible). |
| OpenTofu | — | Bản fork mã nguồn mở của Terraform sau khi Terraform chuyển sang giấy phép BSL. |
| GitOps | Vận hành qua Git | Git là nguồn sự thật; hệ thống tự đồng bộ theo Git. |

## Terraform cơ bản (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| HCL | Ngôn ngữ cấu hình HashiCorp | Cú pháp của file `.tf`. |
| Provider | Nhà cung cấp | Plugin nói chuyện với API (aws, docker, random…). |
| `.terraform.lock.hcl` | File khóa phiên bản | Ghi phiên bản + checksum provider; phải commit. |
| Resource / data source | Tài nguyên / nguồn dữ liệu | Thứ Terraform tạo và quản lý / thứ chỉ đọc. |
| Variable / output / local | Biến / đầu ra / giá trị cục bộ | Đầu vào / kết quả xuất ra / giá trị đặt tên dùng lại trong module. |
| `sensitive` / `ephemeral` | Nhạy cảm / tạm thời | Ẩn khỏi output nhưng **vẫn** ở state / không ghi vào state lẫn plan. |
| `count` / `for_each` | Đếm / lặp theo khóa | Theo chỉ số (dễ dịch chỉ số khi xóa phần tử) / theo khóa ổn định. |
| Lifecycle | Vòng đời | `prevent_destroy`, `create_before_destroy`, `ignore_changes`. |
| Plan | Kế hoạch | Danh sách thay đổi: `+` tạo, `-` xóa, `~` sửa tại chỗ, `-/+` thay thế, `<=` đọc. |
| ForceNew / forces replacement | Buộc tạo mới | Thuộc tính không sửa tại chỗ được — đổi là phải thay tài nguyên. |
| Root module | Module gốc | Thư mục bạn chạy `terraform` trong đó. |

## State và backend (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| State | Trạng thái | File ánh xạ code ↔ ID tài nguyên thật; có thể chứa secret. |
| Backend (local / S3) | Nơi lưu state | Máy bạn / bucket S3 dùng chung. |
| `use_lockfile` | Khóa bằng file | S3 backend tạo `<key>.tflock` để chặn hai lần apply đồng thời. |
| State lock / `force-unlock` | Khóa state / mở khóa cưỡng bức | ⚠️ Chỉ force-unlock khi chắc chắn không còn process nào đang chạy. |
| Bootstrap | Khởi tạo ban đầu | Root module riêng tạo bucket state (con gà – quả trứng). |
| `-migrate-state` | Di chuyển state | Chuyển state sang backend mới khi `terraform init`. |
| Write-only argument (`value_wo`) | Tham số chỉ ghi | Giá trị gửi lên API nhưng không bao giờ lưu vào state. |
| `moved {}` | Khối đổi địa chỉ | Báo Terraform tài nguyên chỉ đổi tên/vị trí, không tạo lại. |
| `import {}` | Khối nhập | Đưa tài nguyên có sẵn vào quản lý của Terraform. |
| `removed {}` | Khối bỏ quản lý | Gỡ khỏi state mà (tùy chọn) không xóa tài nguyên thật. |
| Refresh-only | Chỉ làm mới | `plan/apply -refresh-only`: phát hiện/chấp nhận drift mà không đổi hạ tầng. |
| Serial / lineage | Số thứ tự / dòng dõi | Metadata trong state để phát hiện ghi đè sai. |

## Module và môi trường (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Child module | Module con | Thư mục được gọi bằng khối `module`; không chứa khối `provider`. |
| Module source / ref | Nguồn module / tham chiếu | Đường dẫn local, registry hoặc Git (ghim `?ref=v1.2.0`). |
| Directory-per-environment | Mỗi môi trường một thư mục | `envs/dev`, `envs/prod` — state và cấu hình tách hẳn. |
| Workspace (CLI) | Không gian làm việc | Nhiều state cho cùng một cấu hình — dự án không dùng để tách môi trường. |
| `.tfvars` | File giá trị biến | Giá trị biến cho từng môi trường. |
| `default_tags` | Tag mặc định | Tag provider tự gắn cho mọi tài nguyên. |
| tflint | Công cụ lint Terraform | Bắt lỗi logic, biến không dùng, loại instance sai… |
| `trivy config` | Quét cấu hình IaC | Phát hiện cấu hình thiếu an toàn (bucket public, SG mở rộng…). |
| `terraform test` / mock provider | Kiểm thử / provider giả | Kiểm thử module bằng file `.tftest.hcl` không cần gọi AWS. |

## Ansible (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Control node / managed node | Máy điều khiển / máy được quản lý | Máy chạy Ansible / máy được cấu hình. |
| Agentless | Không tác tử | Không cài phần mềm riêng trên máy đích (chỉ cần Python). |
| Inventory (static / dynamic) | Danh sách máy (tĩnh / động) | File liệt kê máy / plugin hỏi API (ví dụ `amazon.aws.aws_ec2`). |
| Group / host vars | Biến nhóm / biến máy | `group_vars/`, `host_vars/` — phải nằm cạnh inventory hoặc playbook. |
| Ad-hoc command | Lệnh tức thời | `ansible all -m ping` — chạy một module không cần playbook. |
| Playbook / play / task | Kịch bản / màn / tác vụ | Playbook gồm các play; play áp các task lên nhóm máy. |
| Module | Mô-đun | Đơn vị công việc idempotent (`apt`, `copy`, `template`…). |
| `changed` / `ok` | Đã đổi / không đổi | Kết quả task — chạy lần 2 phải `changed=0`. |
| Handler / notify | Trình xử lý / thông báo | Task chỉ chạy khi được task khác báo có thay đổi (restart service). |
| Facts | Dữ kiện | Thông tin máy Ansible tự thu thập (`ansible_facts`). |
| Template (Jinja2) | Mẫu | File có biến `{{ }}` được điền khi copy lên máy. |
| `become` | Nâng quyền | Chạy task bằng root (sudo). |
| Role | Vai trò | Cấu trúc thư mục chuẩn đóng gói task, handler, biến, file. |
| Collection | Bộ sưu tập | Gói phân phối module/plugin (`amazon.aws`, `community.docker`). |
| Connection plugin | Plugin kết nối | Cách Ansible tới máy: `ssh`, `community.docker.docker`, `amazon.aws.aws_ssm`. |
| Check mode / diff | Chạy thử / hiển thị khác biệt | `--check --diff`: xem sẽ đổi gì mà không đổi thật. |
| Ansible Vault | Kho bí mật Ansible | Mã hóa file biến chứa secret. |
