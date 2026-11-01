# Lời giải — Bài 01: Khái niệm Infrastructure as Code

> Chỉ đọc sau khi đã tự làm. Quay lại bài: [01-iac-concepts.md](../01-iac-concepts.md)

## Câu hỏi trong bài thực hành (mục 9)

**Bước 1 — `imperative.sh` lần 2.** Dừng ngay ở `mkdir "$base"` (`File exists`), exit code 1. `set -e` khiến script thoát khi một lệnh lỗi, nên các dòng sau không chạy. Nếu **bỏ** `set -e`: các `mkdir` lỗi nhưng script vẫn chạy tiếp, `echo >> .env` **thêm một dòng trùng** mỗi lần (sau 3 lần: 3 dòng `TASKHUB_IMAGE_TAG=v0.5.0`), còn `ln -s` lần 2 lỗi `File exists` hoặc — vì `current` đã là symlink tới thư mục — tạo **symlink lồng** bên trong thư mục đích (`opt-taskhub/opt-taskhub`). Không có `set -e` thì tệ hơn: script không lỗi rõ ràng mà âm thầm làm sai. `idempotent.sh`: lần 1 `changed`, lần 2 và 3 `ok`; `.env` đúng một dòng.

**Bước 2 — "plan".** 1 tạo (`taskhub-public-b`), 1 xóa (`taskhub-test-subnet`). Xóa `taskhub-test-subnet` khi nó là thử nghiệm/sửa nhầm. **Thêm vào code** khi nó là thay đổi cần thiết (ví dụ team quyết định có subnet thứ 5) — lúc đó sửa code qua PR để lần chạy sau công cụ không xóa nó.

**Bước 3 — Kiểm kê (bảng mẫu, của bạn có thể khác chi tiết):**

| # | Tài nguyên / việc ở v2–v3 | v4 | Lý do |
|---|---|---|---|
| 1 | VPC `taskhub-vpc` | Terraform | Hạ tầng mạng |
| 2 | 4 subnet | Terraform | |
| 3 | IGW + 2 route table + association | Terraform | |
| 4 | SG `taskhub-web-sg` + rule 80 | Terraform | |
| 5 | Role `taskhub-ec2-role` + instance profile | Terraform | |
| 6 | Policy `taskhub-ec2-app`, `taskhub-ec2-s3-backup` | Terraform | |
| 7 | EC2 `taskhub-app` (AMI từ tham số SSM, IMDSv2, gp3) | Terraform | |
| 8 | Tham số `/taskhub/dev/postgres-password` | Terraform (`value_wo`) | Giá trị không vào state |
| 9 | Cài Docker Engine + compose plugin | Ansible | Cấu hình bên trong máy (trước là user data/tay) |
| 10 | `git clone` repo vào `/opt/taskhub` | Ansible (chép file cần thiết) | Hết giới hạn "sửa compose phải làm tay" |
| 11 | `.env` trên EC2 | Ansible chạy `deploy.sh` (deploy.sh tạo `.env` từ Parameter Store) | Secret không đi qua Ansible |
| 12 | OIDC provider GitHub | Terraform | |
| 13 | Role `taskhub-github-deploy` + policy | Terraform | |
| 14 | Log group `/taskhub/dev/app` (retention 7 ngày) | Terraform | |
| 15 | Alarm CPU + StatusCheckFailed | Terraform | |
| 16 | SNS topic `taskhub-alerts` | Terraform | |
| 17 | SNS subscription email | Terraform tạo, **bạn bấm xác nhận email tay** | Xác nhận email không tự động được |
| 18 | Bucket backup `taskhub-backups-<id>` | Terraform (`import` nếu còn) | Chứa dữ liệu → `prevent_destroy` |
| 19 | Bucket state `taskhub-tfstate-<id>` | Terraform `bootstrap/` (state local) | Gà và trứng: backend phải có trước root module |
| 20 | Bucket `taskhub-ansible-ssm-<id>` | Terraform | Mới ở v4 |
| 21 | GitHub variables `AWS_DEPLOY_ROLE_ARN`, `APP_URL` | Tay (lấy từ `terraform output`) | Có thể dùng provider GitHub 🟦 nhưng ngoài phạm vi |
| 22 | Environment `production` + required reviewer | Tay (đã có từ Module 05) | Thuộc GitHub, ít khi đổi |
| 23 | Root MFA, user `phuong-admin`, Budget | Tay | Quản trị **tài khoản**, không phải hạ tầng dự án |
| 24 | Workflow `Deploy` bị disable ở v3 §11 | Tay (enable lại) | |
| 25 | `infra/aws-manual/commands.md` | Không cần nữa (giữ làm tài liệu lịch sử) | Code Terraform thay thế |

Vì sao các dòng "Tay" không nên nằm trong Terraform của dự án: (1) **gà và trứng** — danh tính bạn dùng để chạy Terraform (`phuong-admin`) không thể do chính lần chạy đó tạo ra; (2) **phạm vi khác** — root MFA, Budget là quản trị tài khoản, sống lâu hơn dự án, không được bị `terraform destroy` xóa; (3) **không tự động hóa được** — xác nhận email SNS cần người bấm link; (4) **chi phí/độ phức tạp** — quản lý GitHub bằng provider riêng là đáng làm ở công ty, nhưng không đáng ở dự án học.

**Bước 4 — CloudFormation vs Terraform:**

1. `!Ref Vpc` ↔ `aws_vpc.this.id`. Tham chiếu tạo ra **phụ thuộc ngầm**: công cụ biết phải tạo VPC **trước** subnet và SG, và xóa theo thứ tự ngược lại. Bạn không cần tự sắp thứ tự như ở `commands.md`.
2. ↔ `data "aws_availability_zones" "available"` + `names[0]`. Không viết cứng vì tên AZ được ánh xạ khác nhau theo từng tài khoản và AZ có thể không khả dụng ([AWS bài 01](../../06-AWS/01-cloud-fundamentals.md)); code dùng được ở region khác. (Ở dự án `taskhub` bạn vẫn có thể ghi rõ AZ vì network plan đã chốt — đánh đổi giữa "linh hoạt" và "khớp tài liệu".)
3. Thêm/bớt một rule chỉ thêm/bớt **một resource**, không phải sửa danh sách lồng trong SG. Mỗi rule có ID riêng, plan rõ ràng hơn ("thêm 1 rule" thay vì "SG thay đổi"), và tránh xung đột khi hai nơi cùng quản lý rule của một SG. (Tài liệu provider AWS khuyến nghị cách này thay cho khối `ingress` lồng trong `aws_security_group`.)
4. CloudFormation: AWS giữ — stack là một đối tượng trên AWS ghi tài nguyên nào thuộc nó; xóa stack không cần file nào trên máy. Terraform: file **state** (local hoặc remote như S3) — mất state thì Terraform "quên" mình quản lý gì ([bài 03](../03-terraform-state-backend.md)).
5. CloudFormation: **drift detection** phải được kích hoạt (console hoặc `detect-stack-drift`), báo tài nguyên `MODIFIED`/`DELETED`, **không tự sửa** — bạn phải sửa tài nguyên hoặc cập nhật template. Terraform: `plan` luôn đọc trạng thái thật trước khi so (refresh) và in ra thay đổi để đưa về đúng code; `apply` sẽ "sửa ngược".

## Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Ví dụ: chép nhầm ID subnet; quên tag khiến không tìm thấy khi dọn; phải xóa đúng thứ tự (`DependencyViolation`); `commands.md` không còn khớp sau khi sửa tay; dựng lại v2 cho bài thi mất ~3 giờ; không biết SG được sửa khi nào.

**2.** Mệnh lệnh: mô tả **các bước** (`commands.md`, `deploy.sh`). Khai báo: mô tả **kết quả** (`compose.yaml`, Terraform). Ở kiểu khai báo, công cụ suy ra thứ tự và chỉ làm phần còn thiếu.

**3.** Chạy nhiều lần cho cùng trạng thái cuối. `mkdir -p` không lỗi và không đổi gì khi thư mục đã có; `echo >>` mỗi lần thêm một dòng — trạng thái thay đổi theo số lần chạy.

**4.** Khai báo. `up -d` lần 2 khi không đổi gì: container giữ nguyên (`Running`/`up-to-date`), không tạo lại; đổi tag image rồi `up -d` thì **chỉ** service đó được tạo lại.

**5.** Desired: code. Actual: thứ đang tồn tại. Drift: actual khác desired do thay đổi ngoài code. Vòng lặp: đọc code + đọc thực tế → so sánh → tạo/sửa/xóa cho khớp → lặp lại.

**6.** Thay đổi sai (nhầm, thử nghiệm) → chạy lại công cụ để đưa về code. Thay đổi đúng (chữa cháy cần giữ) → cập nhật code qua PR **trước** lần apply tiếp theo, nếu không apply sẽ xóa bản vá.

**7.** Mutable: sửa máy đang chạy. Immutable: thay bằng bản mới. `taskhub`: **ứng dụng immutable** (image theo tag bất biến, deploy = thay container); **máy chủ mutable** nhưng được Ansible quản lý bằng code.

**8.** Máy/container bị thay thế thì mọi thứ lưu bên trong mất theo. Dữ liệu phải ở volume tách rời (EBS volume, named volume), dịch vụ ngoài (RDS, S3) và có backup.

**9.** Provisioning: tạo tài nguyên hạ tầng — Terraform tạo VPC, EC2, IAM. Configuration management: cấu hình bên trong máy — Ansible cài Docker, chép `compose.yaml`, chạy `deploy.sh`.

**10.** OpenTofu là fork mã nguồn mở của Terraform (sau khi HashiCorp đổi sang BSL 1.1 ngày 10/8/2023), do Linux Foundation quản lý, tương thích state tới Terraform 1.5.x, dùng chung provider. BSL không cản việc **dùng** Terraform để quản lý hạ tầng của công ty, kể cả production; hạn chế nằm ở việc cung cấp sản phẩm **cạnh tranh** với HashiCorp. (Câu hỏi pháp lý cụ thể → hỏi bộ phận pháp chế của công ty.)

**11.** Phạm vi: CloudFormation chỉ AWS; Terraform đa nền tảng qua provider. Ngôn ngữ: YAML/JSON vs HCL. State: AWS giữ (stack) vs file state bạn tự lo nơi lưu và khóa.

**12.** Diff code cho biết **ý định**, plan cho biết **hậu quả** trên hạ tầng thật — đặc biệt các thay đổi buộc **thay thế** tài nguyên (`-/+`), xóa tài nguyên, hoặc drift đang tồn tại mà PR sẽ vô tình "sửa ngược".

**13.** (Chọn 3) Secret viết thẳng trong `.tf` → không bao giờ, dùng biến/sinh ngẫu nhiên. File `*.tfvars` bị commit → `.gitignore`, chỉ commit `.example`. State chứa giá trị → backend private + mã hóa, write-only argument. Log CI in giá trị → `sensitive = true`. User data chứa mật khẩu → chỉ tham chiếu Parameter Store.

**14.** Declarative · Versioned and immutable · Pulled automatically · Continuously reconciled. v4 thỏa **declarative** và **versioned** (Git); **chưa** thỏa "pulled automatically" (bạn/pipeline đẩy thay đổi vào) và "continuously reconciled" (không có agent tự sửa drift — chỉ phát hiện khi bạn chạy `plan`).

## Bài tập tự làm (mục 14) — gợi ý chấm

**Bài 1.** Đạt khi chỉ ra đúng các lệnh thêm/ghi đè trong `.env` (phải là "sửa dòng nếu có, thêm nếu chưa" — đúng cách `deploy.sh` mẫu của [CI/CD lời giải 05](../../05-CICD/solutions/05-solutions.md) làm với `TASKHUB_IMAGE_TAG`), mọi `mkdir` không có `-p`, và giải thích `docker compose up -d` vốn idempotent.

**Bài 2.** Một cách làm:

```bash
#!/usr/bin/env bash
set -euo pipefail
desired="$1"; actual="$2"
# join cần đầu vào đã sort theo trường khóa (tên)
d=$(mktemp); a=$(mktemp); trap 'rm -f "$d" "$a"' EXIT
sort -t= -k1,1 "$desired" > "$d"
sort -t= -k1,1 "$actual"  > "$a"

echo "== create"
join -t= -v1 "$d" "$a" || true
echo "== destroy"
join -t= -v2 "$d" "$a" || true
echo "== update"
join -t= "$d" "$a" | awk -F= '$2 != $3 { printf "%s: %s -> %s\n", $1, $3, $2 }'
```

`join -v1` in dòng chỉ có ở file 1, `-v2` chỉ có ở file 2; `join` thường in `tên=cidr_desired=cidr_actual`, `awk` so cột 2 và 3. Chấp nhận mọi cách khác cho kết quả đúng với dữ liệu xáo trộn thứ tự.

**Bài 3.** Đạt khi có ≥ 3 lựa chọn, mỗi cái có ưu/nhược cụ thể (ví dụ CloudFormation: không phải lo state, nhưng chỉ AWS và YAML dài; OpenTofu: mã nguồn mở, nhưng ít gặp trong JD hơn), quyết định có lý do gắn với bối cảnh (JD, tài liệu, Free plan), hệ quả tiêu cực trung thực (phải tự bảo vệ state; secret có thể vào state nếu không dùng write-only; giấy phép BSL).

**Bài 4.** Đáp án tham khảo:

| Việc | Công cụ | Lý do |
|---|---|---|
| Tạo bucket S3 | Terraform | Tài nguyên hạ tầng |
| Đổi timezone server | Ansible | Cấu hình trong máy |
| Cài `htop` | Ansible | Gói trong máy |
| Mở cổng 443 trên SG | Terraform | Tài nguyên mạng |
| Đổi phiên bản JDK trong image | Dockerfile | Thuộc image ứng dụng |
| Tạo IAM user cho đồng nghiệp | Tay (hoặc Terraform ở repo quản trị tài khoản riêng) | Danh tính con người, ngoài phạm vi dự án |
| Xoay vòng mật khẩu PostgreSQL | Terraform (`value_wo_version` tăng) + chạy `deploy.sh`; thực tế cần đổi cả trong DB | Có nhiều bước — ghi runbook |
| Thêm alarm CPU | Terraform | |
| Thêm service Prometheus cạnh app | Compose (+ Ansible chép file lên máy) | Container trên cùng máy |
| Tăng `mem_limit` | Compose | Cấu hình container |
| Tạo DNS record | Terraform | |
| Bật MFA root | Tay | Quản trị tài khoản |
| Cập nhật `nginx/default.conf` trên server | Ansible (file nằm trong repo, Ansible chép) | |
| Tạo SNS topic | Terraform | |
| Gỡ gói có lỗ hổng trên server | Ansible (`state: absent`) | |

**Bài 5.** Ý chính: phát hiện thay đổi thuộc tính và tài nguyên bị xóa (`MODIFIED`, `DELETED`) trên các loại tài nguyên hỗ trợ; chỉ so các thuộc tính **được khai báo rõ** trong template (không so giá trị mặc định); **không tự sửa** — bạn sửa tài nguyên hoặc cập nhật template (hoặc dùng import để giải quyết); có thuộc tính không so được (mật khẩu, mã Lambda). So với Terraform: `plan` so mọi thuộc tính mà provider đọc được và đề xuất hành động cụ thể để đưa về code.
