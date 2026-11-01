# Lời giải — Lab 02: Hạ tầng `taskhub` bằng Terraform

> Chỉ mở sau khi đã tự làm [Lab 02](../labs/lab-02-taskhub-infra-terraform.md). Code đầy đủ để so sánh: [reference/terraform/](../labs/reference/terraform/README.md).

## Mục lục

- [Câu hỏi trong các bước](#câu-hỏi-trong-các-bước)
- [Danh sách đầy đủ các khối `moved` (B2)](#danh-sách-đầy-đủ-các-khối-moved-b2)
- [Thử nghiệm E1–E6](#thử-nghiệm-e1e6)
- [Câu hỏi sau lab](#câu-hỏi-sau-lab)

---

## Câu hỏi trong các bước

**A1 — `constraints` vs `version` trong `.terraform.lock.hcl`.** `constraints` là ràng buộc bạn viết trong `required_providers` (`~> 6.0` = mọi bản 6.x). `version` là bản **cụ thể** Terraform đã chọn lúc `init` (ví dụ 6.71.0) kèm các hash của gói. Commit file này để mọi máy (laptop, đồng nghiệp, CI) dùng **đúng** bản đó; muốn lên bản mới phải chủ động `terraform init -upgrade` và commit file đã đổi — thay đổi provider đi qua review như thay đổi code.

**A3 — Bỏ `aws_vpc_security_group_egress_rule.all`.** Khi tạo `aws_security_group`, Terraform xóa rule egress "allow all" mà AWS tự thêm. Không khai báo lại thì SG **không có đường ra**: SSM Agent không gọi được endpoint SSM qua 443 → `describe-instance-information` không thấy máy (hoặc `ConnectionLost`), Session Manager không vào được; sau này `apt`, pull image từ GHCR, gửi log CloudWatch đều hỏng. Triệu chứng giống hệt lỗi C3 của checkpoint Module 06 — nhưng lần này nguyên nhân nằm trong code, và `plan` đã cho bạn thấy trước nếu đọc kỹ (không có resource egress nào).

## Danh sách đầy đủ các khối `moved` (B2)

Địa chỉ phẳng của Phần A → địa chỉ trong module của code tham khảo. Data source (`aws_caller_identity`, `aws_ssm_parameter`, `aws_iam_policy_document`) không cần `moved` — chúng không có trong state theo nghĩa "tài nguyên được quản lý", Terraform đọc lại mỗi lần plan.

```hcl
# ---- module.network ----
moved {
  from = aws_vpc.this
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_internet_gateway.this
  to   = module.network.aws_internet_gateway.this
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_subnet.private
  to   = module.network.aws_subnet.private
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table.private
  to   = module.network.aws_route_table.private
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_route_table_association.private
  to   = module.network.aws_route_table_association.private
}

# ---- module.app_server ----
moved {
  from = aws_security_group.web
  to   = module.app_server.aws_security_group.web
}

moved {
  from = aws_vpc_security_group_ingress_rule.http
  to   = module.app_server.aws_vpc_security_group_ingress_rule.web["80"]
}

moved {
  from = aws_vpc_security_group_egress_rule.all
  to   = module.app_server.aws_vpc_security_group_egress_rule.all
}

moved {
  from = aws_iam_role.ec2
  to   = module.app_server.aws_iam_role.ec2
}

moved {
  from = aws_iam_role_policy_attachment.ssm_core
  to   = module.app_server.aws_iam_role_policy_attachment.ssm_core
}

moved {
  from = aws_iam_role_policy.ec2_app
  to   = module.app_server.aws_iam_role_policy.ec2_app
}

moved {
  from = aws_iam_role_policy.ec2_s3_backup
  to   = module.app_server.aws_iam_role_policy.ec2_s3_backup
}

moved {
  from = aws_iam_instance_profile.ec2
  to   = module.app_server.aws_iam_instance_profile.ec2
}

moved {
  from = aws_instance.app
  to   = module.app_server.aws_instance.app
}
```

17 khối. Tham số mật khẩu, OIDC, role deploy, monitoring vẫn ở root `envs/dev` nên giữ nguyên địa chỉ.

Subnet và association dùng `for_each` với **cùng** khóa `a`/`b` ở cả code phẳng lẫn module, nên một khối `moved` cho cả resource là đủ: `aws_subnet.public["a"]` → `module.network.aws_subnet.public["a"]`, `["b"]` tương tự. Nếu code phẳng của bạn dùng `count` (`[0]`, `[1]`) mà module dùng `for_each`, khối `moved` cho cả resource **không** chuyển được (khóa số ≠ khóa chuỗi) — phải viết từng instance:

```hcl
moved {
  from = aws_subnet.public[0]
  to   = module.network.aws_subnet.public["a"]
}

moved {
  from = aws_subnet.public[1]
  to   = module.network.aws_subnet.public["b"]
}
# … tương tự cho aws_subnet.private và hai aws_route_table_association
```

Vì sao plan vẫn có thể còn `~ update in-place` sau khi đủ `moved`? Code trong module khác code phẳng một chút (ví dụ module thêm `tags` cho `root_block_device`, thêm `description` cho tham số). Đó là thay đổi **thật** bạn vừa viết, không phải lỗi `moved` — đọc diff, chấp nhận nếu đúng ý. Thứ không được phép là `to add`/`to destroy`.

Sau khi `apply` xong và mọi người trong nhóm (cùng CI) đã chạy qua, có thể xóa `moved.tf`. Dự án cá nhân giữ lại cũng không sao — là tài liệu cho việc refactor.

## Thử nghiệm E1–E6

**E1 — Drift với rule SG thêm tay.** Plan **không** thấy gì. Với kiểu khai báo từng rule bằng `aws_vpc_security_group_ingress_rule`, Terraform chỉ quản lý những rule **nó** tạo ra (mỗi rule là một resource có ID riêng); rule cổng 22 bạn thêm tay không thuộc resource nào → Terraform không biết nó tồn tại. Đây là drift "vô hình" nguy hiểm nhất: cổng 22 mở ra Internet mà `plan` báo sạch.

Phát hiện bằng: `aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg-id>` rồi so với code; về lâu dài là AWS Config hoặc công cụ quét (Module 10). Đánh đổi ngược lại: khai báo rule **inline** (`ingress {}` trong `aws_security_group`) thì Terraform quản lý **toàn bộ tập rule** và sẽ xóa rule lạ — nhưng tài liệu provider khuyến nghị resource rule riêng, và không được trộn hai kiểu cho cùng một SG. Xóa tay rule đó sau thử nghiệm.

**E2 — `-replace`.** Plan có `-/+` cho EC2 (`replaced as requested`). Mất: toàn bộ dữ liệu trên ổ gốc (database PostgreSQL trong volume `pgdata`, `.env`, mọi thứ Ansible đã cài), IP public cũ. Phải cập nhật `APP_URL`; phải chạy lại Ansible. Alarm và role deploy tự cập nhật theo (alarm dùng `InstanceId` của máy mới qua tham chiếu; deploy tìm máy theo tag). Đây là lý do backup (v5) quan trọng: hạ tầng dựng lại được, **dữ liệu** thì không.

**E3 — `prevent_destroy`.** Terraform kiểm tra `prevent_destroy` ngay khi **lập plan**: một plan có hành động xóa tài nguyên được bảo vệ bị từ chối toàn bộ, nên không có gì bị xóa — kể cả các tài nguyên không được bảo vệ trong cùng root. Đó cũng chính là lý do bucket backup không thể nằm trong `envs/dev`: `destroy` hằng ngày sẽ luôn lỗi. Gỡ `prevent_destroy` "cho chạy được" là bỏ đi lớp bảo vệ duy nhất giữa một lệnh gõ nhầm và mất dữ liệu.

**E4 — Khóa state.** Terminal 2 nhận `Error acquiring the state lock` với Lock Info (ID, Path, Operation `OperationTypeApply`, Who `phuong@LEGION`, Created). Trong bucket có `envs/dev/terraform.tfstate.tflock`; sau khi terminal 1 trả lời `no`, file biến mất. `force-unlock` chỉ dùng khi **chắc chắn** không còn tiến trình nào giữ khóa (laptop sập giữa lúc apply, CI job bị hủy cứng) — mở khóa khi một apply khác đang chạy = hai tiến trình cùng ghi state = state hỏng. Trước khi force-unlock, kiểm tra Who/Created và hỏi người đó.

**E5 — Xoay mật khẩu.** Plan chỉ hiện `~ value_wo_version = 1 -> 2` (write-only không bao giờ hiện giá trị). Nếu apply mà không tạo lại PostgreSQL: image `postgres` chỉ dùng `POSTGRES_PASSWORD` khi **khởi tạo** thư mục dữ liệu lần đầu ([04-DOCKER bài 04](../../04-DOCKER/04-volumes-networks-env.md)); volume `pgdata` đã có → mật khẩu thật trong database vẫn là mật khẩu cũ. Lần deploy sau, `deploy.sh` ghi mật khẩu mới vào `.env` → ứng dụng kết nối với mật khẩu mới → `password authentication failed`. Xoay mật khẩu đúng cách: đổi mật khẩu **trong PostgreSQL** (`ALTER USER`) và trong Parameter Store cùng một quy trình — hoặc chỉ tăng version khi đằng nào database cũng được tạo lại (máy mới, chưa có dữ liệu).

**E6 — AMI mới.** Hai giá trị có thể khác nhau mà plan vẫn `No changes`: `ignore_changes = [ami]` bảo Terraform bỏ qua chênh lệch thuộc tính `ami`. Được: không bao giờ bị thay máy bất ngờ. Mất: máy không tự lên AMI mới — bản vá bảo mật của AMI chỉ đến khi bạn chủ động `-replace` (hoặc `apt upgrade` bằng Ansible, cách thường dùng với máy sống lâu). Ghi điều này vào ADR-0008.

## Câu hỏi sau lab

**1.** Backend phải tồn tại **trước khi** `terraform init` của root dùng nó; nếu bucket nằm trong chính root đó thì lần `init` đầu tiên không có chỗ lưu state, và `destroy` sau này sẽ xóa luôn nơi chứa state của chính lệnh đang chạy. Trình tự: (1) `bootstrap` với state cục bộ: `init` → `plan` (kiểm tra import) → `apply` tạo bucket; (2) thêm `backend.tf` (partial config), `init -migrate-state -backend-config="bucket=..."` chép state lên key `bootstrap/terraform.tfstate`; (3) `plan` báo `No changes` để chắc state đã lên đủ; (4) mới xóa state cục bộ; (5) `envs/dev` dùng cùng bucket, key khác.

**2.** `terraform destroy` lỗi `Instance cannot be destroyed` ngay khi lập plan, **không xóa gì cả** — EC2 vẫn chạy, credit vẫn chảy, và "xóa một lệnh" không còn đúng. Xóa `prevent_destroy` cho chạy được thì lệnh destroy tiếp theo xóa luôn bucket backup (nếu còn `force_destroy` thì xóa cả object — mất dữ liệu không lấy lại được). Cách đúng: tách bucket sang root khác (`bootstrap`), mỗi root có vòng đời riêng.

**3.** `terraform state mv` là lệnh **mệnh lệnh** chạy một lần trên state, không để lại dấu vết trong code: đồng nghiệp/CI đang có code cũ hoặc state chưa cập nhật sẽ thấy plan đòi xóa/tạo lại. `moved` là **khai báo trong code**: đi qua PR, được review, và ai chạy `plan` (laptop, CI, môi trường khác dùng cùng module) cũng tự áp dụng cùng một phép đổi địa chỉ. Plan hiển thị rõ `has moved to` — không có thao tác nào ngoài luồng `plan → apply`.

**4.** Đường đi của mật khẩu:

```text
ephemeral random_password (chỉ trong RAM của tiến trình terraform)
  → API PutParameter qua TLS (value_wo — không vào plan/state)
  → Parameter Store, mã hóa bằng KMS key aws/ssm
  → deploy.sh trên EC2: aws ssm get-parameter --with-decryption (quyền của taskhub-ec2-role, lấy qua IMDSv2)
  → /opt/taskhub/.env (quyền 600, chủ root)
  → Docker Compose nội suy biến → biến môi trường của container postgres và taskhub
```

Dạng chữ tồn tại ở: RAM của `terraform` lúc apply, biến shell trong `deploy.sh`, file `.env`, môi trường của hai container (đọc được bằng `docker inspect` / `/proc/<pid>/environ` bởi root trên host). **Không** có trong Git, state, plan, GitHub, user data. Mô hình đe dọa: ai có root trên EC2 thì đọc được — chấp nhận cho một máy một người quản trị (đã ghi ở ADR-0004).

**5.** Parameter AMI là giá trị **thay đổi theo thời gian** do Canonical cập nhật; `ami` của `aws_instance` là thuộc tính **forces replacement**. Không có `ignore_changes`, ngày Canonical ra AMI mới thì `apply` tiếp theo (dù bạn chỉ sửa một alarm) sẽ thay EC2 và mất dữ liệu trên ổ. Mất đi: máy không tự nhận AMI mới — cập nhật hệ điều hành phải chủ động (`-replace` có kế hoạch, hoặc Ansible `apt upgrade`).

**6.** `default_tags` khai báo **một lần** ở provider, gắn vào mọi tài nguyên provider đó tạo (với `aws_instance` còn gắn cả volume). `tags` khai báo trên từng resource. Trùng khóa → tag của **resource** thắng (tài liệu provider, mục `tags` của `aws_instance`). Ví dụ: provider của `bootstrap` đặt `Env = "shared"`, resource `aws_s3_bucket.backups` đặt `Env = "dev"` → bucket backup mang `Env=dev`. Thuộc tính `tags_all` trong plan cho thấy kết quả sau khi gộp.

**7.** `.terraform.lock.hcl` — nằm ở **thư mục root module** (`bootstrap/`, `envs/dev/`), được tạo/cập nhật bởi `terraform init`, phải commit. Nó chốt phiên bản và hash của từng provider; máy khác `init` sẽ cài đúng bản đó dù registry đã có bản mới hơn.

**8.** Ba giá trị đổi mỗi lần dựng lại:

| Giá trị | Hệ quả với CD |
|---|---|
| `public_ip` / `app_url` | Biến `APP_URL` của environment `production` phải cập nhật, nếu không smoke test của `Deploy` gọi sai địa chỉ và báo đỏ dù deploy thành công |
| `instance_id` | Không ảnh hưởng: `deploy.yml` tìm máy theo tag `Project`/`Name`, inventory Ansible tìm theo tag — đây là lý do không hard-code ID ở đâu cả |
| Mật khẩu PostgreSQL (tham số mới, giá trị ngẫu nhiên mới) | Không vấn đề vì database cũng mới (ổ EBS bị xóa cùng EC2); `deploy.sh` luôn đọc giá trị hiện hành từ Parameter Store |

(Cũng chấp nhận: SNS subscription mới phải xác nhận lại email; role `taskhub-github-deploy` là role **mới** — ARN dạng chuỗi không đổi vì tên không đổi, nhưng nếu bạn từng ghi `RoleId` ở đâu thì nó đã khác.)
