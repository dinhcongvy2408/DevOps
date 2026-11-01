# Lời giải — Bài 03: Terraform state và remote backend

> Chỉ đọc sau khi đã tự làm. Quay lại bài: [03-terraform-state-backend.md](../03-terraform-state-backend.md)

## Câu hỏi trong lab

**A2 — `serial` có tăng khi apply không đổi gì?** Chạy thật (Terraform 1.17.1 + docker provider 4.6, 2026-10-31): `apply` báo *No changes* nhưng `serial` vẫn tăng **3 → 4**. Lý do: `apply` luôn làm refresh rồi **ghi lại** state sau khi chạy xong, kể cả khi không có thay đổi hạ tầng — mỗi lần ghi là một `serial` mới. (`terraform plan` thì không ghi state nên không làm tăng.) Điểm cần nắm: `serial` tăng **mỗi lần state được ghi**, không phải mỗi lần hạ tầng đổi — và `apply` là lệnh ghi.

**A4 — `sensitive` che ở đâu?** `terraform output` và plan hiện `<sensitive>`, nhưng `jq` đọc thẳng file state in ra mật khẩu rõ. `sensitive` chỉ là bộ lọc **hiển thị**; state vẫn lưu nguyên giá trị.

**A5 — Đổi tên không có `moved`.** `Plan: 1 to add, 0 to change, 1 to destroy`: Terraform hủy container `web` và tạo container `frontend` (cùng tên Docker `tf07-state-web`). Với container, mất vài giây phục vụ; với database là mất dữ liệu.

**A7 — `apply -refresh-only` thay vì `apply`.** State được cập nhật để khớp thực tế: `docker_container.frontend` bị **xóa khỏi state** (vì object thật không còn). Container **không** được tạo lại. Lần `plan` sau sẽ đề xuất `1 to add` vì code vẫn khai báo container đó.

**B1 — Versioning + lifecycle 90 ngày.** Versioning cho phép quay lại state cũ khi bị ghi đè/hỏng. Nhưng mỗi lần apply sinh một phiên bản; không dọn thì số phiên bản tăng mãi. Lifecycle xóa phiên bản **không còn hiện hành** sau 90 ngày — đủ dài để phát hiện sự cố, đủ ngắn để không tích tụ vô hạn.

## Câu hỏi kiểm tra kiến thức

1. Mapping, metadata (phụ thuộc → thứ tự hủy), performance (cache thuộc tính), syncing (team dùng chung). Xóa state → Terraform coi như chưa tạo gì: `plan` đề xuất **tạo mới toàn bộ**; apply sẽ lỗi trùng tên (bucket, role, container tên cố định) hoặc tạo bản thứ hai cho resource không ràng buộc tên → tốn tiền, hạ tầng mồ côi.
2. `serial`: số thứ tự tăng mỗi lần ghi — chặn ghi đè bản mới bằng bản cũ. `lineage`: định danh "dòng dõi" sinh khi state tạo lần đầu — chặn trộn state của hai cấu hình khác nhau (ví dụ `state push` nhầm file).
3. Có, dạng rõ. `sensitive` chỉ che khi hiển thị. Ephemeral resource/biến ephemeral không bao giờ được ghi vào state hay plan file; write-only argument nhận giá trị (thường ephemeral) và gửi cho provider nhưng không lưu.
4. Terraform không lưu giá trị write-only nên không so sánh được cũ/mới để biết có thay đổi. `..._wo_version` là tín hiệu thay đổi do bạn kiểm soát. Muốn đổi mật khẩu: tăng `value_wo_version` (ví dụ 1 → 2) rồi apply — giá trị mới (từ ephemeral `random_password`) được gửi đi.
5. Block `backend` được xử lý khi `init`, trước khi Terraform đánh giá biến. Tránh ghi cứng: **partial configuration** — để trống trong code, truyền bằng `terraform init -backend-config=backend.hcl` (hoặc `-backend-config="key=value"`).
6. `s3:ListBucket` trên bucket; `s3:GetObject` + `s3:PutObject` trên state object; `s3:GetObject` + `s3:PutObject` + `s3:DeleteObject` trên `<key>.tflock`. Mở khóa = **xóa** file khóa, còn state file chỉ bị ghi đè, Terraform không bao giờ xóa nó.
7. Deprecated, sẽ bị gỡ ở một bản minor tương lai; tham số `dynamodb_table` cũng deprecated. Trả lời: tutorial đã cũ — dùng `use_lockfile = true`, không cần DynamoDB.
8. Bucket state phải có trước khi lưu state vào nó, nhưng bucket cũng là hạ tầng cần quản lý. Giải pháp: root module `bootstrap/` chạy với state local để tạo bucket, sau đó thêm backend S3 và `init -migrate-state` để chuyển chính state đó vào bucket. Hệ quả: muốn xóa bucket phải kéo state về local trước; bucket được bảo vệ bằng `prevent_destroy`.
9. Chỉ khi khóa là **của chính bạn** và việc tự mở khóa thất bại (tiến trình bị kill, mất mạng giữa apply), sau khi chắc chắn không có lệnh/pipeline nào khác đang chạy. Dùng sai → hai tiến trình cùng ghi state → state lệch hoặc hỏng, hạ tầng ở trạng thái không xác định.
10. `moved` nằm trong code: qua PR, được review, có plan xem trước, áp dụng cho **mọi** state dùng code đó khi họ apply. `state mv` là lệnh tay, sửa một state ngay lập tức, không ai thấy trước, đồng nghiệp/môi trường khác phải tự làm lại.
11. Chỉ xóa khỏi code → plan **hủy** object thật. `removed { lifecycle { destroy = false } }` → Terraform thôi theo dõi, object thật còn nguyên.
12. `to` (địa chỉ trong code) và `id` (import ID). Import ID tra ở mục *Import* cuối trang tài liệu của resource. Mục tiêu: plan sau import ra **No changes** (chỉ còn "will be imported") — chứng tỏ code mô tả đúng object thật.
13. `plan -refresh-only`: chỉ cho xem state sẽ được cập nhật thế nào cho khớp thực tế. `apply -refresh-only`: ghi kết quả đó vào state, không đụng hạ tầng (chấp nhận drift). `apply` thường: đưa hạ tầng thật về đúng code (đảo ngược drift).
14. Người dùng `terraform_remote_state` phải có quyền đọc **toàn bộ** snapshot state, thường chứa thông tin nhạy cảm. Ghi riêng đúng giá trị cần chia sẻ (SSM Parameter Store, data source theo tag) chỉ lộ đúng thứ đó và tách phụ thuộc giữa hai cấu hình.

## Bài tập tự làm

### Bài 1 — Đọc state bằng `jq`

```bash
jq -r '.resources[] | select(.mode=="managed") | "\(.type).\(.name) -> \(.instances[0].attributes.id)"' terraform.tfstate

terraform show -json | jq -r '.values.root_module.resources[] | select(.mode=="managed") | "\(.address) -> \(.values.id)"'
```

`terraform show -json` đọc state qua backend đang cấu hình (local hay S3 đều như nhau), cho cấu trúc JSON được tài liệu hóa và ổn định, có sẵn `address` đầy đủ (kể cả khóa `for_each`, tiền tố module). Đọc file trực tiếp chỉ làm được với state local. (Resource trong module con nằm ở `.values.root_module.child_modules[]` — cần duyệt thêm nếu có module.)

### Bài 2 — Chuyển sang `for_each`

```hcl
resource "docker_container" "site" {
  for_each = toset(["blue"])

  name  = "tf07-state-web"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = 18081
  }
}

moved {
  from = docker_container.frontend
  to   = docker_container.site["blue"]
}
```

Nếu `moved` cũ (`web` → `frontend`) vẫn còn, có thể **nối chuỗi** (giữ cả hai block) như tài liệu khuyên. Trong shell, bọc địa chỉ trong **nháy đơn** để bash không hiểu `[` và `"`:

```bash
terraform state show 'docker_container.site["blue"]'
```

### Bài 3 — Quyền cho role chỉ được `plan`

`plan` mặc định có xin khóa state (trừ khi `-lock=false`), nên role này vẫn cần ghi/xóa lock file nhưng **không** được `PutObject` lên state:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListStatePrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::taskhub-tfstate-111122223333",
      "Condition": { "StringLike": { "s3:prefix": ["envs/dev/*"] } }
    },
    {
      "Sid": "ReadState",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::taskhub-tfstate-111122223333/envs/dev/terraform.tfstate"
    },
    {
      "Sid": "LockFile",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::taskhub-tfstate-111122223333/envs/dev/terraform.tfstate.tflock"
    }
  ]
}
```

Trong Policy Simulator: `s3:PutObject` lên `.../terraform.tfstate` → **implicitDeny**; lên `.../terraform.tfstate.tflock` → **allowed**. Lưu ý: role này còn cần quyền **đọc** tài nguyên AWS để refresh (ví dụ `ReadOnlyAccess` hoặc các `Describe*`), nếu không plan sẽ lỗi ở bước refresh.

### Bài 4 — Runbook khôi phục state

```text
1. DỪNG mọi apply: báo team, tạm disable pipeline có thể chạy terraform.
2. Liệt kê phiên bản:
   aws s3api list-object-versions --bucket taskhub-tfstate-111122223333 \
     --prefix envs/dev/terraform.tfstate \
     --query 'Versions[].{v:VersionId,latest:IsLatest,at:LastModified,size:Size}' --output table
   → bản hiện hành có Size rất nhỏ (state rỗng); bản ngay trước có Size bình thường.
3. Tải bản tốt ra file tạm (lệnh ĐỌC):
   aws s3api get-object --bucket ... --key envs/dev/terraform.tfstate \
     --version-id <VERSION_TỐT> /tmp/state-good.json
4. Kiểm tra: jq '.serial, .lineage, (.resources|length)' /tmp/state-good.json
   so lineage với bản hiện hành (phải giống); số resource hợp lý.
5. Khôi phục (VIẾT RA, chưa chạy):
   terraform state push /tmp/state-good.json
   Nếu bị từ chối vì serial thấp hơn bản hiện hành: tăng "serial" trong file tạm lên
   (serial hiện hành + 1) bằng jq — đây là trường hợp hiếm hoi được phép sửa state,
   và chỉ sửa đúng trường serial.
   (Cách khác tương đương: copy phiên bản cũ thành phiên bản hiện hành bằng
    aws s3api copy-object --copy-source "bucket/key?versionId=...")
6. terraform plan → phải ra No changes (hoặc chỉ những thay đổi giải thích được).
7. Ghi postmortem: script nào ghi đè, vì sao có quyền PutObject lên state.
```

### Bài 5 — Container cùng tên, khác ID

Sau `docker rm -f` + `docker run --name tf07-state-web -p 18085:80 ...`:

- `plan -refresh-only`: Terraform refresh theo **ID** đã lưu (`9a55...`) → không tìm thấy → báo object **đã bị xóa**. Nó không biết container mới cùng tên là "của mình".
- `plan`: đề xuất **tạo** container `tf07-state-web` → `apply` lỗi kiểu *Conflict. The container name "/tf07-state-web" is already in use* (minh họa).
- Xử lý: xóa container tay (`docker rm -f`) rồi apply; hoặc `import` container mới nếu muốn giữ nó (rồi sửa code cổng 18085 cho khớp).
- Bài học: Terraform nhận diện object bằng **ID trong state**, không phải bằng tên.

Mục nhật ký mẫu: *Triệu chứng* apply lỗi tên đã tồn tại · *Nguyên nhân gốc* container bị tạo lại ngoài Terraform với cùng tên · *Cách tìm* `plan -refresh-only` báo deleted + `docker ps` thấy container khác ID (`docker inspect -f '{{.Id}}'`) · *Cách sửa* xóa container tay rồi apply · *Phòng ngừa* không sửa tài nguyên do Terraform quản lý bằng tay.

### Bài 6 — ADR bootstrap

Ý chính một ADR đạt yêu cầu:

- **Bối cảnh:** cần bucket state trước khi có state remote; một người vận hành; cần khôi phục được.
- **Lựa chọn:** (a) Terraform `bootstrap/` + migrate state vào chính bucket; (b) AWS CLI tạo tay.
- **Quyết định:** (a) — cấu hình bucket (versioning, BPA, mã hóa, policy chặn non-TLS, lifecycle) nằm trong code, được review, tái tạo được ở tài khoản mới trong ~5 phút; `prevent_destroy` chặn xóa nhầm.
- **Hệ quả tiêu cực:** thêm một root module; xóa bucket phải qua quy trình nhiều bước (migrate state về local trước); nếu bucket bị xóa ngoài ý muốn, state bootstrap mất cùng — giảm thiểu bằng versioning và giữ một bản `state pull` ngoài AWS.
- **Số liệu:** chi phí ≈ 0 USD/tháng (vài KB); thời gian dựng lại ~5 phút với (a), ~15 phút gõ lại lệnh CLI và dễ thiếu cấu hình với (b).
