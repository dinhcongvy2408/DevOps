# Lời giải — Lab 01: Terraform quản lý Docker trên máy

> Chỉ mở sau khi đã tự làm. Lab: [lab-01-terraform-local-docker.md](../labs/lab-01-terraform-local-docker.md)
> Các kết quả dưới đây suy ra từ schema provider `kreuzwerker/docker` 4.6 và `hashicorp/local` 2.9 (kiểm tra 2026-10-31). Nếu máy bạn khác, tin máy bạn và ghi lại.

## Câu hỏi trước khi chạy (A1)

1. **9 resource** (3 đơn lẻ + 3 nhóm `for_each` × 2 site): `docker_network.this`, `docker_volume.logs`, `docker_image.nginx`, `local_file.conf["blue"]`, `local_file.conf["green"]`, `local_file.page["blue"]`, `local_file.page["green"]`, `docker_container.web["blue"]`, `docker_container.web["green"]`. Nhiều người trả lời 8 vì quên một nhóm `for_each`.
2. Bắt buộc: network, volume, image, conf, page **trước** container (container tham chiếu cả năm). Network, volume, image, 4 file **không** phụ thuộc nhau → tạo song song. Hai container cũng song song với nhau.
3. Docker yêu cầu bind mount bằng đường dẫn tuyệt đối; `local_file.filename` là `./generated/...` (tương đối với thư mục chạy). `abspath()` đổi thành `/home/phuong/devops-lab/...`.

## A2

- `Plan: 9 to add, 0 to change, 0 to destroy.`
- `id = (known after apply)`: ID container do Docker sinh ra khi tạo — Terraform chỉ biết sau khi gọi API.
- Hash trong `labels` **đã biết** lúc plan: `sha1(local_file.conf[...].content)` tính từ `content`, mà `content` là chuỗi tĩnh trong code.

## A4 — Bảng T1–T6

| # | Ký hiệu | Container mới? | Giải thích |
|---|---|---|---|
| T1 restart `always` | `~` cho 2 container | Không | `restart` không phải ForceNew trong schema → provider gọi Docker cập nhật restart policy |
| T2 message green | `-/+` `local_file.page["green"]` | Không | `content` của `local_file` buộc thay file. Container gắn **thư mục** `html/` → `host_path` không đổi → container không đổi. Trước apply trang vẫn cũ (file chưa đổi); sau apply trang mới ngay |
| T3 thêm `add_header` | `-/+` 2 `local_file.conf` **và** `-/+` 2 container | Có | Hash trong `labels` đổi; `labels` là ForceNew → `# forces replacement`. `curl -sI` thấy `X-Site: blue` |
| T4 base_port 8091 | `-/+` 2 container, `-/+` 2 `local_file.page` | Có | `ports` ForceNew. `page` đổi vì nội dung HTML có in số cổng. `conf` không đổi |
| T5 thêm red | `+` 3 resource | Chỉ `red` | `for_each` thêm key → chỉ thêm resource của key đó |
| T6 xóa blue | `-` 3 resource của blue | Không | `green` giữ nguyên địa chỉ `["green"]`, cổng vẫn `base_port + 1` |

**Thí nghiệm phụ (bỏ `labels`):** sau khi đổi `conf`, `/healthz` vẫn trả nội dung **cũ**, và `docker exec ... cat` cũng in nội dung cũ. Provider `local` thay file bằng cách xóa file cũ rồi ghi file mới → file mới có **inode mới**. Bind mount một *file* gắn vào inode lúc container được tạo; container vẫn nhìn thấy inode cũ (đã bị xóa khỏi thư mục nhưng còn được mount giữ lại). Gắn *thư mục* thì không bị vì container nhìn vào thư mục, tìm file theo tên mỗi lần đọc. Block `labels` chứa hash nội dung biến "cấu hình đổi" thành "container phải tạo lại" — một kỹ thuật phổ biến (Kubernetes có cách làm tương tự với annotation chứa hash ConfigMap — Module 09).

## A5 — Drift

**D1.** `+ docker_container.web["green"]` (create): khi refresh, provider không tìm thấy container → xóa khỏi state → plan thấy code có mà state không có → tạo. `terraform plan -refresh-only` không đề xuất tạo gì; nó báo object đã bị xóa ngoài Terraform và đề xuất cập nhật **state** cho khớp thực tế. Khác biệt cốt lõi: `plan` thường = đưa thực tế về code; `-refresh-only` = đưa state về thực tế.

**D2.** Plan đề xuất **thay thế** container (đã chạy thật với provider 4.6, 2026-10-31): `-/+ docker_container.web["blue"]` với `~ must_run = false -> true` và `+ ports { # forces replacement }`. Theo tài liệu provider, `must_run` (mặc định `true`) nghĩa là Terraform giữ container ở trạng thái chạy; khi container dừng, state ghi `false` → lệch với code. Còn `ports` bị đánh dấu "forces replacement" vì container đã dừng **không còn port binding** khi provider đọc lại (`docker inspect` của container dừng không có `Ports`) → Terraform thấy cổng "mất" và đòi tạo lại. Bài học: một thao tác tay nhỏ (`docker stop`) có thể khiến Terraform **thay** chứ không chỉ "bật lại" — luôn đọc plan trước khi apply. Sau apply, `docker ps` thấy container mới `Up`.

**D3.** Không. Terraform chỉ quản lý — và chỉ nhìn thấy — những gì có trong **state**. Container `tf07-intruder` tạo bằng `docker run` không nằm trong state nên vô hình với `plan`. Hệ quả: Terraform **không** phải công cụ kiểm kê tài nguyên; cần tag + công cụ quét (`find-leftovers.sh`, Tag Editor, AWS Config). Khi `destroy`, Docker từ chối xóa `tf07-net` vì còn endpoint của `tf07-intruder` → destroy lỗi ở bước network; các resource khác đã bị xóa. Lỗi thật Terraform in ra là `timeout while waiting for state to become 'removed' (last state: 'pending', timeout: 30s)` — nguyên nhân chỉ thấy khi chạy `docker network rm tf07-net` (`... has active endpoints`). Gỡ kẻ lạ rồi chạy lại `destroy` (hoặc `apply` để dựng lại: lần chạy thật báo `8 added` — mọi thứ trừ network vẫn còn).

**Thí nghiệm phụ (ghi chú khi chạy thật):** bước "xóa block `labels`, apply" báo `0 changed` — `labels` là thuộc tính *computed* của provider, bỏ khỏi code không gỡ label đã có trên container. Không sao: điều cần quan sát là bước sau — đổi `conf` thì chỉ `local_file.conf` bị thay, container **không** bị tạo lại và `/healthz` vẫn trả nội dung cũ.

## A6

Plan báo lỗi dạng `Instance cannot be destroyed` và nói resource `docker_volume.logs` có `lifecycle.prevent_destroy` (chữ chính xác tùy phiên bản). Đây là tính năng tốt: volume chứa dữ liệu không tạo lại được — một `destroy` gõ nhầm thư mục hay một thay đổi làm volume bị `-/+` đều bị chặn trước khi gây mất dữ liệu.

## A7

Sau destroy: không còn container/network/volume `tf07-`; image `nginx:1.30-alpine` còn vì `keep_locally = true`. State rỗng.

## Phần B

- Thay đổi ở bài *Manage infrastructure* thường gồm một thay đổi sửa tại chỗ (ví dụ tag → `~`) và một thay đổi thay thế (ví dụ đổi AMI → `-/+ ... # forces replacement`). Ghi đúng những gì plan của bạn in ra.
- `data "aws_ami"` lọc theo owner + tên: linh hoạt (chọn được phiên bản Ubuntu bất kỳ, hoặc AMI riêng), nhưng phải viết đúng bộ lọc tên và cần quyền `ec2:DescribeImages`; lọc sai owner có nguy cơ lấy AMI của người khác. SSM public parameter: Canonical công bố đường dẫn ổn định, một dòng, luôn đúng region; nhưng chỉ có cho các AMI mà nhà cung cấp chọn công bố và cần quyền `ssm:GetParameter`.
- Dọn dẹp đạt khi `terraform state list` rỗng và `find-leftovers.sh` trả `exit=0`.

## Câu hỏi sau lab

1. `restart` không phải ForceNew trong schema provider (Docker có API cập nhật restart policy của container đang tồn tại); `ports` là ForceNew (Docker không đổi được port mapping của container đã tạo).
2. Một resource: `local_file.page["green"]`. Container gắn thư mục, `host_path` không đổi → không bị tạo lại; nginx đọc file theo tên mỗi request → thấy nội dung mới ngay.
3. Với `count`, `green` sẽ trượt từ index 1 về 0 → `docker_container.web[0]` bị đổi tên/cổng (thay thế), `web[1]` bị xóa: cả hai container bị đụng, `green` bị tạo lại vô cớ và cổng của nó còn đổi thành 8081.
4. Trên AWS: EC2/SG/bucket ai đó tạo bằng console. Phát hiện: lọc theo tag (`Project=taskhub` mà thiếu `ManagedBy=terraform`), `find-leftovers.sh`, Tag Editor/Resource Explorer, Cost Explorer theo tag; ở công ty dùng AWS Config.
5. Bảo vệ image dùng chung khỏi bị xóa khi một cấu hình bị destroy (image lớn, tải lại tốn thời gian; cấu hình khác/lab khác còn dùng). Muốn `false` khi image chỉ dành riêng cho cấu hình đó và bạn muốn destroy dọn sạch dung lượng.
6. State cục bộ `terraform.tfstate` trong thư mục làm việc. Laptop hỏng → mất state → Terraform không còn biết EC2 nào là của nó; phải xóa bằng tay (console/CLI, lọc theo tag `Lab=tf07-getstarted`) hoặc viết lại cấu hình và `import`. Remote backend S3 ([bài 03](../03-terraform-state-backend.md)) giải quyết vấn đề này.
