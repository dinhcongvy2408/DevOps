# Lời giải — Lab 03: Ansible qua SSM

> Chỉ mở sau khi đã tự làm. Code đầy đủ ở [bản tham khảo Ansible](../labs/reference/ansible/README.md).
> Quay lại lab: [lab-03-ansible-ssm.md](../labs/lab-03-ansible-ssm.md)

## Câu hỏi trong lab

**A3 — Hai bản `amazon.aws`.** Bản `12.0.0` trong `~/.ansible/collections` được dùng vì đường dẫn đó đứng trước bản đi kèm gói `ansible`. Ghim `12.0.0` để chạy đúng phiên bản bạn đã đọc tài liệu và test (12.0.0 có thay đổi phá vỡ tương thích: bỏ ansible-core < 2.18, nâng boto3 tối thiểu), và để máy CI/máy khác chạy giống hệt.

**B1 — Dòng còn thiếu trong `compose`:**

```yaml
  ansible_aws_ssm_bucket_name: "'taskhub-ansible-ssm-' ~ owner_id"
```

`owner_id` là account id sở hữu reservation của instance (plugin gắn vào hostvars). `~` là toán tử nối chuỗi của Jinja2; `'…'` bên trong nháy kép là chuỗi cố định.

**B2 — Máy stopped.** Có filter `instance-state-name: running`: máy stopped **biến mất** khỏi inventory. Bỏ filter: máy stopped **xuất hiện lại** — mã nguồn plugin tự thêm filter mặc định `running, pending, stopping, stopped` khi bạn không lọc trạng thái. Playbook chạy vào máy stopped sẽ treo tới khi hết thời gian kết nối SSM.

**C2 — `whoami`.** Không `--become`: `ssm-user` (user mà SSM Agent tạo cho phiên Session Manager trên Linux). Có `--become`: `root`. Vì vậy playbook đặt `become: true` ở mức play.

**C3 — File trên S3.** Tiền tố là **instance ID** (`i-0abc…/`), theo tài liệu plugin. Chạy xong, file bị xóa. Plugin khuyên tắt versioning vì nếu bật, mỗi file "đã xóa" vẫn còn trong lịch sử phiên bản — và file module có thể chứa tham số nhạy cảm của task → nằm trong bucket vô thời hạn.

**D — Máy đã có Docker từ user data.** Task cài gói báo `ok` (đã đúng trạng thái), task thêm repo có thể `changed` nếu user data ghi file repo với tên/định dạng khác. Bài học: hai công cụ cùng quản lý **một** thứ dễ "giành nhau" (mỗi bên sửa theo ý mình → không bao giờ `changed=0`). Chọn **một** nơi chịu trách nhiệm — trong v4 là Ansible; user data chỉ giữ việc tối thiểu (hoặc để trống).

**F — Đổi tag.** Chỉ task `deploy.sh` (và task in kết quả) chạy; role `docker` toàn `ok`; task copy toàn `ok`. Thường `changed=1`.

## Thí nghiệm (phần G) — kết quả mong đợi

**G1 — Check mode.** Diff in nội dung khác của `compose.yaml`. Task `deploy.sh` bị **bỏ qua** (`skipping`) vì module `command` không hỗ trợ check mode — Ansible không thể đoán script làm gì. Trên EC2, file **không** đổi. Ghi chú: hai task chỉ đọc vẫn chạy nhờ `check_mode: false`, nên điều kiện của task deploy vẫn được tính mà không lỗi.

**G2 — Thiếu tag / tag lạ.** Không có `-e`: `assert` trong `pre_tasks` dừng play với `fail_msg`, trước khi đụng tới máy. Tag `v1;reboot`: không khớp regex → `assert` chặn. Kiểm tra ở hai nơi là **phòng thủ nhiều lớp**: playbook chặn sớm với thông báo dễ hiểu; `deploy.sh` vẫn tự kiểm tra vì nó còn được gọi từ đường khác (workflow `Deploy` của v3 qua SSM Run Command, hoặc chạy tay).

**G3 — Bind mount và inode.** Với handler `nginx -s reload`: header **không** xuất hiện. `stat -c %i` trên host cho inode **mới** sau khi copy, trong container vẫn là inode **cũ** → container nhìn thấy file cũ. Với handler `docker restart`: header xuất hiện, inode trong container khớp inode mới. Cách khác thường gặp trong thực tế: bind mount **cả thư mục** (`./docker/nginx:/etc/nginx/conf.d:ro`) — đổi tên file bên trong thư mục được mount thì container thấy ngay, khi đó `nginx -s reload` là đủ. Đó là một thay đổi `compose.yaml` hợp lý nếu bạn muốn reload không gián đoạn (ghi vào ADR nếu đổi).

**G4 — group_vars sai chỗ.** `UNREACHABLE` với thông báo SSH (minh họa: *"Failed to connect to the host via ssh: … Could not resolve hostname i-0abc…"*). Không đọc được `ansible_connection` → Ansible dùng connection mặc định `ssh`, và `ansible_host` là instance ID → SSH thử phân giải một tên không tồn tại.

**G5 — Region sai.** Plugin mặc định `us-east-1` (trừ khi biến môi trường `AWS_REGION`/`AWS_DEFAULT_REGION` đã đặt — lab đặt `AWS_REGION=ap-southeast-1` ở mục 3, nên có thể bạn **không** thấy lỗi!). Nếu đã `unset AWS_REGION`: lỗi khi mở phiên SSM tới instance không tồn tại ở `us-east-1`. Bài học: đừng phụ thuộc biến môi trường ngầm — ghi region rõ ràng trong `group_vars`.

**G6 — Máy mới.** Thường 5–10 phút từ `apply` tới app `UP` (boot + SSM Agent online + cài Docker + pull image). So với v2 làm tay (cả buổi) — đây là giá trị của "cấu hình là code".

## Câu hỏi sau lab

**1.** (1) Inventory gọi `DescribeInstances` → biết instance ID, bucket. (2) Ansible đóng gói module + tham số thành file. (3) Upload file lên S3 dưới tiền tố instance ID. (4) Mở phiên SSM qua `session-manager-plugin`. (5) Gửi lệnh `curl <presigned URL>` để EC2 tải file về. (6) EC2 chạy `python3` với module, trả JSON qua phiên. (7) Xóa file tạm trên S3. EC2 **không cần** quyền IAM nào với bucket: presigned URL mang sẵn chữ ký từ credential của máy điều khiển.

**2.** IP public đổi mỗi lần stop/start; `terraform apply -replace` tạo instance ID mới; dựng/xóa hằng ngày (v4). Inventory tĩnh sẽ sai ngay lần sau. Inventory động hỏi AWS mỗi lần chạy, chọn máy theo **tag** — cùng nguyên tắc với role deploy của v3 (`ssm:resourceTag/Project`).

**3.** Container `taskhub` chết (OOM, ai đó `docker stop`), file và tag không đổi → playbook báo `ok` và bỏ qua, ứng dụng vẫn chết. Điều kiện thứ ba biến playbook thành công cụ "đưa về trạng thái mong muốn" thật sự.

**4.** Terraform: tài nguyên AWS (VPC, SG, IAM, EC2, bucket, tham số). Ansible: cấu hình **bên trong** máy (Docker, AWS CLI, file triển khai) và lần triển khai đầu. `deploy.sh`: đổi tag, pull, `up --wait`, smoke test, rollback — chạy **trên** máy. Workflow `Deploy`: đổi tag tự động sau khi CI xanh (có người duyệt). Chỉ đổi tag → dùng workflow `Deploy` (hoặc `workflow_dispatch` để rollback): nhanh, có audit trail trên GitHub, không cần máy điều khiển. Đổi `compose.yaml`/nginx/Docker → Ansible.

**5.**

| | `aws_ssm` | SSH + port 22 tạm thời từ IP của bạn |
|---|---|---|
| Lợi | Không port nào mở vào; không SSH key; quyền qua IAM; lịch sử phiên trong SSM | Nhanh hơn; quen thuộc; không cần bucket, plugin |
| Chi phí | Bucket S3 (gần 0), cài plugin + boto3 | Không đáng kể |
| Rủi ro | Phụ thuộc SSM Agent + đường ra Internet; bucket chứa file tạm | Quên xóa rule 22; IP nhà đổi; quản lý và xoay vòng SSH key; bị dò quét khi port mở |
| Hợp với | taskhub (đã dùng SSM cho deploy ở v3) | Máy on-premises, môi trường không có SSM |
