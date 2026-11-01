# 01. Khái niệm Infrastructure as Code — từ "bấm tay" đến "mô tả bằng code"

> ⏱️ ~2 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [Module 06 — AWS](../06-AWS/README.md), dự án [v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) và [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md), [Linux 06 — Bash scripting](../01-LINUX/06-bash-scripting.md)
> Môi trường: `[WSL]` (chỉ Bash — chưa cần cài Terraform), giấy bút hoặc file Markdown. **0 USD**, không tạo tài nguyên AWS nào.

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc log và xử lý lỗi](#12-đọc-log-và-xử-lý-lỗi)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Kể ra các vấn đề cụ thể của cách **dựng hạ tầng bằng tay** (click-ops) — bằng chính trải nghiệm v2/v3 của bạn.
- Phân biệt **khai báo** (declarative) và **mệnh lệnh** (imperative); giải thích **idempotency** (tính lũy đẳng) và chứng minh bằng script Bash.
- Giải thích **desired state** (trạng thái mong muốn), **actual state** (trạng thái thực tế), **drift** (lệch trạng thái) và vòng lặp "so sánh → hành động".
- Phân biệt **mutable** và **immutable infrastructure**, và nhận ra `taskhub` đã đi theo hướng immutable ở tầng ứng dụng từ v1.
- Phân biệt **provisioning** (Terraform), **configuration management** (Ansible), **image building** (Packer 🟦) và **container** — công cụ nào cho việc gì.
- Đọc được một bảng so sánh công cụ IaC và chọn công cụ có lý do.
- Hiểu vì sao code hạ tầng phải qua **code review** (plan trong PR) và vì sao **secret** là vấn đề riêng của IaC.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

| Tình huống ở công việc thật | Khái niệm của bài này giúp gì |
|---|---|
| "Môi trường staging chạy được, production lại lỗi — hai cái khác nhau chỗ nào?" | IaC: cả hai sinh ra từ **cùng một code**, khác nhau chỉ ở biến → khác biệt nằm ở chỗ đọc được |
| "Ai đã mở port 22 trên security group này?" | Drift: thay đổi ngoài code bị `plan` phát hiện; lịch sử Git cho biết thay đổi **hợp lệ** đến từ PR nào |
| "Sếp hỏi: dựng lại toàn bộ hệ thống ở region khác mất bao lâu?" | Có IaC: vài chục phút. Không có: vài ngày và không chắc đúng |
| "Script tạo server chạy lần 2 thì lỗi" | Idempotency: script phải chạy lại an toàn |
| "Nên dùng Terraform hay Ansible cho việc này?" | Phân biệt provisioning và configuration management |
| Phỏng vấn: "IaC là gì? Lợi ích? Declarative khác imperative thế nào?" | Câu hỏi mở đầu của gần như mọi buổi phỏng vấn DevOps có Terraform trong JD |

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Nhìn lại những gì bạn đã làm tay ở v2/v3

Mở `infra/aws-manual/commands.md` trong repo `taskhub` của bạn (file bắt buộc của [v2 §4](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md#4-file-phải-có-trong-repo)). Đó là một **kịch bản mệnh lệnh**: "chạy lệnh A, lấy ID in ra, dán vào lệnh B…". Hãy nhớ lại những lúc:

- Chép nhầm `subnet-…` của subnet private vào lệnh tạo EC2 → máy không có IP public, SSM không vào được.
- Quên tag `Owner` cho một tài nguyên → Tag Editor không tìm thấy, gần như bỏ sót khi dọn.
- Dọn dẹp ở [v3 §11](../12-PRACTICAL-PROJECT/milestones/v3-cd.md#11-dọn-dẹp): phải xóa **đúng thứ tự** (inline policy trước role, EC2 trước SG…), nếu không gặp `DependencyViolation`.
- Muốn biết "hạ tầng hiện tại có giống tài liệu không" → phải mở từng trang console để so.

Mỗi điểm trên là một **lớp lỗi** mà IaC loại bỏ — không phải vì bạn cẩn thận hơn, mà vì công cụ làm thay phần dễ sai.

### 3.2. Các vấn đề của click-ops

**Click-ops** (vận hành bằng cú click) là cách gọi vui việc dựng hạ tầng qua giao diện web hoặc lệnh gõ tay.

| Vấn đề | Biểu hiện ở `taskhub` | Hậu quả khi đi làm |
|---|---|---|
| **Không lặp lại được** (not reproducible) | Dựng lại v2 cho bài thi mốc 3 tháng mất ~3 giờ | Không dựng nhanh được môi trường mới, không khôi phục nhanh khi mất region |
| **Không có lịch sử** | Không biết SG được sửa lúc nào, vì sao | Sự cố không truy được nguyên nhân; kiểm toán (audit) thất bại |
| **Không review được** | Không ai nhìn thay đổi trước khi bạn bấm "Save" | Một cú click sai (mở `0.0.0.0/0` cổng 5432) đi thẳng lên production |
| **Lệch giữa môi trường** (snowflake server) | Máy dev và máy "prod" mỗi máy một kiểu | "Chạy trên staging mà" |
| **Tài liệu luôn cũ** | `commands.md` không cập nhật sau khi sửa tay một rule | Người kế nhiệm làm theo tài liệu sai |
| **Dọn dẹp khó** | Phải nhớ thứ tự phụ thuộc, dễ sót | Tiền âm thầm chảy (EIP, EBS, snapshot quên xóa) |

> **Snowflake server** (máy bông tuyết): máy được chỉnh tay qua thời gian đến mức không ai biết chính xác nó được cấu hình thế nào — giống bông tuyết, không cái nào giống cái nào. Đối nghĩa là máy dựng hoàn toàn từ code.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Infrastructure as Code là gì

**Infrastructure as Code** (IaC): quản lý và cấp phát hạ tầng bằng **file định nghĩa đọc được bằng máy**, thay vì cấu hình tay. Các file đó:

1. Nằm trong **Git** → có lịch sử, có `git blame`, có rollback bằng `git revert`.
2. Thay đổi qua **Pull Request** → được review, có CI kiểm tra (đúng như code ứng dụng ở [Module 05](../05-CICD/README.md)).
3. Được một **công cụ** đọc và biến thành tài nguyên thật.

Câu nói hay được nhắc: *"Đối xử với hạ tầng như với code ứng dụng."* Mọi thứ bạn đã học về Git, PR, CI, review áp dụng nguyên vẹn.

### 4.2. 🟥 Khai báo (declarative) và mệnh lệnh (imperative)

| | Mệnh lệnh (imperative) | Khai báo (declarative) |
|---|---|---|
| Bạn viết | **Các bước** để đi tới kết quả | **Kết quả** muốn có |
| Ví dụ | "Tạo VPC. Lấy ID. Tạo subnet trong VPC đó…" | "Phải có 1 VPC `10.20.0.0/16` và 4 subnet như sau" |
| Ở `taskhub` | `commands.md` (v2), `deploy.sh` | Terraform (v4), `compose.yaml` (v0!) |
| Ai lo thứ tự | Bạn | Công cụ (tự suy ra từ phụ thuộc) |
| Chạy lần 2 | Thường **lỗi** (VPC đã tồn tại) hoặc **tạo trùng** | Không làm gì nếu đã đúng |
| Muốn xóa 1 subnet | Viết lệnh xóa | Xóa đoạn mô tả subnet khỏi file |

Bạn **đã** dùng kiểu khai báo từ tuần 8 mà có thể chưa để ý: `compose.yaml` không nói "chạy `docker network create`, rồi `docker run`…"; nó nói "phải có 3 service, 1 volume, như sau" và `docker compose up` tự tính phải làm gì. Chạy `up -d` lần 2 khi không đổi gì → Compose báo các container `Running`, không tạo lại. Terraform làm điều tương tự cho hạ tầng cloud.

> **Không có công cụ thuần túy.** Terraform khai báo, nhưng bên trong vẫn gọi API AWS theo từng bước. Ansible playbook là danh sách **task theo thứ tự** (mang tính mệnh lệnh), nhưng mỗi module lại mô tả **trạng thái** (`state: present`) — người ta gọi nó là "thủ tục nhưng idempotent". Điều quan trọng không phải là cái nhãn, mà là: **chạy lại có an toàn không, và ai chịu trách nhiệm về thứ tự.**

### 4.3. 🟥 Idempotency — chạy lại bao nhiêu lần cũng cho cùng một kết quả

Một thao tác **idempotent** (lũy đẳng) là thao tác mà chạy 1 lần hay 10 lần cho **cùng trạng thái cuối**. Bạn đã gặp ở Linux:

| Không idempotent | Idempotent | Vì sao |
|---|---|---|
| `mkdir /opt/taskhub` | `mkdir -p /opt/taskhub` | Lần 2 không lỗi khi thư mục đã có |
| `echo "x=1" >> app.conf` | `grep -qx 'x=1' app.conf \|\| echo 'x=1' >> app.conf` | Lần 2 không thêm dòng trùng |
| `useradd taskhub` | `id taskhub &>/dev/null \|\| useradd --system taskhub` | Lần 2 không lỗi "already exists" |
| `ln -s a b` | `ln -sfn a b` | Lần 2 không lỗi "File exists" |
| `aws ec2 create-vpc ...` | Terraform `resource "aws_vpc"` | Lần 2 Terraform thấy VPC đã có, không tạo trùng |

Vì sao quan trọng trong DevOps:

- **Thử lại an toàn:** pipeline đứt giữa chừng (mạng chập chờn) → chạy lại từ đầu, không sợ tạo trùng 2 VPC.
- **Hội tụ:** chạy định kỳ để đưa hệ thống về đúng trạng thái mong muốn.
- **Tin được:** "chạy lần 2 không thay đổi gì" là bằng chứng hệ thống **đã đúng** với code. Ở Ansible bạn sẽ thấy điều này qua con số `changed=0`.

### 4.4. 🟥 Desired state, actual state và drift

```text
   Code trong Git                     Hạ tầng thật trên AWS
  (desired state — mong muốn)        (actual state — thực tế)
           │                                   │
           └──────────►  SO SÁNH  ◄────────────┘
                            │
               khác nhau? ──┴── giống nhau?
                  │                   │
          tạo / sửa / xóa        không làm gì
         cho thực tế khớp code   ("No changes")
```

- **Desired state:** điều bạn mô tả trong code.
- **Actual state:** cái đang thật sự tồn tại.
- **Drift** (trôi/lệch): actual khác desired **mà không qua code** — ví dụ ai đó sửa security group trên console lúc 2 giờ sáng để "chữa cháy".

Terraform có thêm một tầng ở giữa gọi là **state** (file ghi nhớ "tài nguyên nào trong code ứng với ID nào trên AWS") — học kỹ ở [bài 03](03-terraform-state-backend.md). Ở bài này chỉ cần hiểu: công cụ IaC so sánh **mong muốn** với **thực tế** rồi hành động cho khớp.

**Xử lý drift thế nào?** Hai hướng, tùy thay đổi đó **đúng hay sai**:

| Thay đổi ngoài code là… | Làm gì |
|---|---|
| **Sai** (sửa nhầm, thử nghiệm quên trả lại) | Chạy lại công cụ IaC → thực tế bị đưa về đúng code |
| **Đúng** (chữa cháy cần thiết) | Cập nhật **code** cho khớp thực tế, qua PR → lần chạy sau không "sửa ngược" |

Điều nguy hiểm nhất là **không biết** có drift: lần `apply` tiếp theo sẽ âm thầm xóa bản vá chữa cháy, và sự cố cũ quay lại. Vì vậy quy tắc ở các team dùng IaC là: **mọi thay đổi đi qua code**; quyền sửa tay trên console được giới hạn. [Break-fix của module](labs/break-fix-01/README.md) là một ca drift có chủ đích.

### 4.5. 🟥 Mutable và immutable infrastructure

| | Mutable (sửa tại chỗ) | Immutable (thay mới) |
|---|---|---|
| Cập nhật | SSH/SSM vào máy đang chạy, `apt upgrade`, sửa file | Tạo máy/image **mới** từ cấu hình mới, bỏ máy cũ |
| Rủi ro | Máy trôi dần thành snowflake; mỗi lần sửa là một thí nghiệm trên production | Tốn thời gian dựng mới; dữ liệu phải nằm **ngoài** máy |
| Rollback | Khó (phải "sửa ngược") | Dễ (quay về image/máy cũ) |
| Ở `taskhub` | Cách bạn cài Docker tay ở v2 | **Image container** từ v1: không bao giờ vào container sửa, mà build image mới, deploy tag mới ([CI/CD bài 05](../05-CICD/05-deployment-strategies-rollback.md)) |

`taskhub` v4 là **lai**: ứng dụng immutable (image theo tag bất biến), máy chủ thì mutable nhưng được **Ansible quản lý** (cấu hình bằng code, chạy lại hội tụ về đúng trạng thái). Ở công ty lớn hơn, bước tiếp theo là "đóng" luôn máy chủ thành image (AMI) bằng Packer — 🟦 nâng cao, xem 4.6.

**Hệ quả quan trọng:** máy immutable thì **dữ liệu phải sống ngoài máy**. Đó là lý do PostgreSQL của `taskhub` dùng volume trên EBS, backup lên S3 (v5) — và lý do bạn phải cẩn thận khi Terraform muốn **thay thế** (replace) EC2: volume gốc bị xóa theo máy ([bài 02](02-terraform-basics.md) dạy đọc dấu `-/+` trong plan).

### 4.6. 🟥 Provisioning, configuration management, image building, container — công cụ nào cho việc gì

| Việc | Câu hỏi nó trả lời | Công cụ tiêu biểu | Ở `taskhub` |
|---|---|---|---|
| **Provisioning** (cấp phát hạ tầng) | "Có những máy, mạng, quyền, bucket nào?" | **Terraform**/OpenTofu, CloudFormation, Pulumi, CDK | v4: VPC, SG, IAM, EC2, S3, CloudWatch |
| **Configuration management** (quản lý cấu hình) | "Bên trong máy có gói gì, file cấu hình gì, service nào chạy?" | **Ansible**, Chef, Puppet, Salt | v4: cài Docker, chép `compose.yaml`, chạy `deploy.sh` |
| 🟦 **Image building** (đóng image máy) | "Máy khởi động lên đã có sẵn mọi thứ chưa?" | Packer, EC2 Image Builder | Không dùng (một máy, Ansible đủ) |
| **Container** | "Ứng dụng và thư viện của nó đóng gói thế nào?" | Docker, Dockerfile | Từ v0: image `taskhub` |
| **Orchestration** (điều phối container) | "Container chạy ở đâu, bao nhiêu bản, khi chết thì sao?" | Compose (1 máy), Kubernetes, ECS | v0–v5: Compose · v6: Kubernetes |

Ranh giới không tuyệt đối: Terraform có thể truyền **user data** để cài vài thứ lúc khởi động (bạn đã làm ở v2), Ansible có module tạo EC2. Nhưng **dùng mỗi công cụ cho đúng sở trường** làm hệ thống dễ hiểu:

- Terraform giỏi quản lý **vòng đời tài nguyên** (tạo → sửa → xóa) và **phụ thuộc** giữa chúng, nhờ có state.
- Ansible giỏi **lặp lại các bước cấu hình** trên nhiều máy, kết nối vào máy (SSH, hoặc SSM như dự án này), không cần cài agent.

**Quy ước của dự án (v4):** Terraform tạo máy và mọi thứ quanh nó; **user data chỉ tối thiểu** (hoặc không có); Ansible cài Docker và triển khai ứng dụng. Ranh giới này được ghi vào ADR-0009 ở [v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md).

### 4.7. 🟨 Bản đồ công cụ IaC (mức nhận biết)

| Công cụ | Loại | Ngôn ngữ | Phạm vi | Có state riêng? | Ghi chú |
|---|---|---|---|---|---|
| **Terraform** | Provisioning | HCL | Đa cloud qua provider | Có (file state) | Phổ biến nhất trong JD. Giấy phép BSL 1.1 từ 10/8/2023 |
| **OpenTofu** | Provisioning | HCL | Như Terraform | Có | Fork mã nguồn mở của Terraform, do Linux Foundation quản lý; lệnh `tofu` |
| **CloudFormation** | Provisioning | YAML/JSON | Chỉ AWS | State do AWS giữ (stack) | Bạn đã dùng ở [break-fix 06-AWS](../06-AWS/labs/break-fix-01/README.md): `aws cloudformation deploy` |
| **AWS CDK** | Provisioning | TypeScript, Python, Java… | Chủ yếu AWS | Sinh ra CloudFormation | Viết hạ tầng bằng ngôn ngữ lập trình |
| **Pulumi** | Provisioning | TypeScript, Python, Go, Java… | Đa cloud | Có | Giống Terraform nhưng dùng ngôn ngữ lập trình |
| **Ansible** | Config management | YAML (playbook) | Mọi máy có SSH/WinRM/… | Không | Không cần agent; dùng ở v4 |
| **Chef / Puppet** | Config management | Ruby DSL / Puppet DSL | Máy có cài agent | Có (server) | Gặp ở công ty có hạ tầng lâu đời |
| **Salt** | Config management | YAML + Jinja | Máy có agent (hoặc SSH) | Có | Ít gặp hơn ở Việt Nam |
| 🟦 **Packer** | Image building | HCL | AMI, image VM | Không | Đóng image máy chủ sẵn cấu hình |

**Cách chọn (bảng quyết định đơn giản):**

| Nếu… | Chọn | Vì sao |
|---|---|---|
| Hạ tầng trên một hay nhiều cloud, team đa dạng | Terraform/OpenTofu | Phổ biến, nhiều provider, nhiều tài liệu |
| Công ty chỉ dùng AWS và muốn mọi thứ do AWS quản lý (kể cả state) | CloudFormation (hoặc CDK nếu team là lập trình viên) | Không phải giữ file state, tích hợp sâu với AWS |
| Team toàn lập trình viên, muốn vòng lặp, test, thư viện của ngôn ngữ quen thuộc | Pulumi / CDK | Dùng IDE, unit test như code thường |
| Cấu hình bên trong nhiều máy Linux | Ansible | Không agent, YAML dễ đọc |
| Công ty đã có Chef/Puppet từ lâu | Tiếp tục dùng | Chi phí chuyển đổi lớn hơn lợi ích |

### 4.8. 🟥 IaC trong code review: plan đi kèm PR

Lợi ích lớn nhất của IaC không phải là "tự động", mà là **thay đổi được nhìn thấy trước khi xảy ra**. Quy trình phổ biến:

```text
nhánh infra/… ──PR──► CI: fmt, validate, lint, quét cấu hình, terraform plan
                              │
                     reviewer đọc DIFF CODE  +  OUTPUT CỦA PLAN
                     ("PR này sẽ: thêm 1 rule SG, THAY THẾ 1 EC2")
                              │ approve
                              ▼
                     merge → apply (người bấm, hoặc pipeline)
```

Reviewer phải đọc **cả hai**: diff code cho biết ý định, **plan** cho biết hậu quả thật. Một thay đổi trông vô hại trong code (đổi `user_data` một dòng) có thể khiến plan **thay thế** EC2 — mất dữ liệu trên ổ gốc. Kỹ năng đọc plan được dạy ở [bài 02](02-terraform-basics.md).

Ở v4, CI cho Terraform chỉ chạy các bước **không cần quyền AWS** (`fmt`, `validate`, lint, quét cấu hình). Chạy `plan` trong CI cần quyền đọc AWS qua OIDC — 🟦 tùy chọn ([bài 04](04-terraform-modules-environments.md)).

### 4.9. 🟥 Secret trong IaC — vấn đề riêng cần chú ý

| Rủi ro | Ví dụ | Cách phòng |
|---|---|---|
| Secret viết thẳng trong code | `password = "MatKhau123"` trong file `.tf` → lên GitHub public | Không bao giờ; dùng biến không có giá trị mặc định, hoặc sinh ngẫu nhiên |
| Secret trong **file biến** bị commit | `terraform.tfvars` chứa mật khẩu | `.gitignore` các file `*.tfvars` riêng; chỉ commit `*.tfvars.example` |
| Secret nằm trong **state** | Terraform ghi giá trị thuộc tính vào state — kể cả mật khẩu | State để ở nơi được bảo vệ (S3 private, mã hóa); dùng **write-only argument** để giá trị không bao giờ vào state ([bài 03](03-terraform-state-backend.md)) |
| Secret in ra **log CI** | `plan` in giá trị | Đánh dấu biến `sensitive = true`; Terraform che giá trị trong output |
| Secret trong **user data** | Mật khẩu viết trong script khởi động | User data đọc được qua console/IMDS — chỉ để **tham chiếu** tới Parameter Store (đã làm ở v2) |

Quy ước của dự án đã chọn từ v2 vẫn giữ: **mật khẩu PostgreSQL chỉ sống ở Parameter Store**. Ở v4, Terraform tạo tham số đó bằng argument write-only `value_wo` (Terraform ≥ 1.11) — giá trị đi qua Terraform nhưng **không được lưu** vào state.

### 4.10. 🟦 GitOps — nhìn trước

**GitOps** đẩy IaC thêm một bước: Git là **nguồn sự thật duy nhất**, và một **agent** chạy liên tục để kéo cấu hình từ Git về rồi đối chiếu với hệ thống. Bộ nguyên tắc OpenGitOps gồm 4 ý:

1. **Declarative** — trạng thái mong muốn được mô tả kiểu khai báo.
2. **Versioned and immutable** — lưu có phiên bản, không sửa tại chỗ, đủ lịch sử.
3. **Pulled automatically** — agent **tự kéo** cấu hình (thay vì pipeline đẩy vào).
4. **Continuously reconciled** — agent liên tục so sánh thực tế với mong muốn và sửa cho khớp.

Công cụ tiêu biểu: Argo CD, Flux — dùng với Kubernetes. `taskhub` v4 **chưa** là GitOps (bạn chạy `terraform apply` bằng tay, pipeline đẩy deploy bằng SSM). Bạn sẽ thấy ý tưởng "reconcile liên tục" ở Kubernetes ([Module 09](../00-ROADMAP/curriculum-structure.md)).

### 4.11. Gặp lại ở đâu

| Khái niệm | Gặp lại ở |
|---|---|
| Khai báo, desired state | Terraform ([bài 02](02-terraform-basics.md)), Kubernetes manifest (Module 09) |
| Idempotency | Ansible `changed=0` ([bài 05](05-ansible-fundamentals.md)) |
| Drift | `terraform plan` phát hiện thay đổi ngoài code ([bài 03](03-terraform-state-backend.md), [break-fix](labs/break-fix-01/README.md)) |
| Immutable | Image container (đã có từ v1), Kubernetes thay Pod thay vì sửa (Module 09) |
| Secret trong state | Write-only argument ([bài 03](03-terraform-state-backend.md)), rà soát bảo mật (Module 10) |
| Plan trong PR | CI cho Terraform ([bài 04](04-terraform-modules-environments.md)) |

---

## 5. Ví dụ thực tế

**Tình huống:** một công ty có môi trường production dựng tay từ 3 năm trước. Một đêm, một kỹ sư trực sự cố mở thêm rule `0.0.0.0/0` cổng 5432 trên security group của database để "kết nối nhanh từ nhà kiểm tra", rồi quên đóng. Hai tháng sau, bộ phận bảo mật phát hiện bot quét cổng đang thử mật khẩu PostgreSQL.

**Không có IaC:** không ai biết rule có từ bao giờ, của ai, có còn cần không. Xóa thì sợ hỏng thứ gì đó.

**Có IaC + quy trình:**

1. Lần chạy `terraform plan` định kỳ (hoặc trên PR kế tiếp) hiện ra: `~ resource "aws_security_group" ... - ingress 0.0.0.0/0:5432` — Terraform muốn **xóa** rule lạ vì nó không có trong code. Drift bị phát hiện **trong vòng một ngày**.
2. CloudTrail cho biết ai, lúc nào, gọi `AuthorizeSecurityGroupIngress`.
3. Team quyết định: thay đổi đó **sai** → `apply` để xóa. Kèm hành động phòng ngừa: giới hạn quyền sửa SG trên console, chỉ cho phép qua PR.

Bài học: IaC không ngăn con người làm sai, nhưng làm cho cái sai **hiện ra** và **sửa được nhanh**.

---

## 6. Sơ đồ kiến trúc

**Từ v2/v3 (tay) sang v4 (code):**

```text
 v2/v3 — CLICK-OPS                          v4 — INFRASTRUCTURE AS CODE
 ┌──────────────────────────┐              ┌──────────────────────────────────────────┐
 │ Bạn                       │              │ Repo taskhub (Git, PR, review, CI)        │
 │  ├─ console: tạo VPC      │              │  ├─ infra/terraform/   (mô tả hạ tầng)    │
 │  ├─ CLI: chép ID, dán ID  │              │  └─ infra/ansible/     (mô tả cấu hình)   │
 │  ├─ SSM: cài Docker tay   │              └─────────────┬────────────────────────────┘
 │  └─ commands.md (cũ dần)  │                            │
 └────────────┬─────────────┘                ┌───────────┴────────────┐
              │ từng lệnh, từng click         ▼                        ▼
              ▼                         terraform apply          ansible-playbook
 ┌──────────────────────────┐          (tạo/sửa/xóa tài nguyên)  (cấu hình bên trong máy)
 │ AWS: VPC, SG, IAM, EC2…   │                │                        │
 │ (trạng thái = những gì    │                ▼                        ▼
 │  bạn nhớ là đã làm)       │   AWS: VPC, SG, IAM, EC2, S3,     EC2: Docker, /opt/taskhub,
 └──────────────────────────┘   CloudWatch (trạng thái = code)  compose, deploy.sh
                                         │
                                  terraform destroy → xóa sạch theo đúng thứ tự phụ thuộc
```

**Vòng đời một thay đổi hạ tầng có IaC:**

```text
sửa code ─► terraform plan (xem trước) ─► PR + review ─► merge ─► terraform apply ─► hạ tầng mới
    ▲                                                                                  │
    └──────────── drift? (ai đó sửa tay) ◄── terraform plan định kỳ phát hiện ◄────────┘
```

---

## 7. Các câu lệnh cần biết

Bài này **chưa cài Terraform** (bài 02 mới cài). Các lệnh dưới đây là Bash, dùng để **cảm nhận** idempotency bằng công cụ bạn đã thạo.

| Lệnh | Mục đích |
|---|---|
| `mkdir -p <dir>` | Tạo thư mục, không lỗi nếu đã có |
| `grep -qxF '<dòng>' <file> \|\| echo '<dòng>' >> <file>` | Thêm dòng vào file chỉ khi chưa có |
| `ln -sfn <đích> <link>` | Tạo/cập nhật symlink, idempotent |
| `diff <(sort a) <(sort b)` | So sánh hai danh sách (desired vs actual) |
| `sha256sum <file>` | Kiểm tra nội dung có đổi không (để quyết định "có cần làm gì không") |

Xem trước — **chỉ để biết**, chạy ở bài 02:

| Lệnh Terraform | Tương ứng khái niệm |
|---|---|
| `terraform plan` | So sánh desired (code) với actual → in ra "sẽ làm gì" |
| `terraform apply` | Làm cho actual khớp desired |
| `terraform destroy` | Xóa mọi thứ Terraform quản lý |

---

## 8. Giải thích câu lệnh và tham số

### 8.1. `mkdir -p`

```bash
mkdir /tmp/iac-demo/app        # lần 1: lỗi nếu /tmp/iac-demo chưa có
mkdir -p /tmp/iac-demo/app     # tạo cả thư mục cha; lần 2 không lỗi
echo $?                        # 0
```

| Phần | Ý nghĩa |
|---|---|
| `-p` (`--parents`) | Tạo các thư mục cha còn thiếu; **không báo lỗi nếu thư mục đã tồn tại** — đây chính là tính idempotent |

### 8.2. Thêm dòng có điều kiện

```bash
grep -qxF 'MAX_UPLOAD=10m' app.conf || echo 'MAX_UPLOAD=10m' >> app.conf
```

| Phần | Ý nghĩa |
|---|---|
| `grep -q` | Im lặng (không in), chỉ trả exit code: 0 = tìm thấy |
| `-x` | Khớp **cả dòng**, không khớp một phần (`MAX_UPLOAD=10m` không khớp `MAX_UPLOAD=10mb`) |
| `-F` | Coi mẫu là **chuỗi cố định**, không phải regex (dấu `.` không phải "ký tự bất kỳ") |
| `\|\|` | Chỉ chạy vế sau khi vế trước **thất bại** (không tìm thấy dòng) |

Đây là "kiểm tra trạng thái → chỉ hành động khi cần" — đúng cái mà module Ansible `ansible.builtin.lineinfile` làm cho bạn ([bài 05](05-ansible-fundamentals.md)).

### 8.3. `diff` hai danh sách

```bash
diff <(sort desired.txt) <(sort actual.txt)
```

| Phần | Ý nghĩa |
|---|---|
| `<( ... )` | Process substitution của Bash: kết quả lệnh trong ngoặc được đưa vào như một "file" |
| `sort` | `diff` so theo dòng — sắp xếp trước để thứ tự không gây khác biệt giả |
| Dòng `<` | Có trong desired, **thiếu** trong actual → cần **tạo** |
| Dòng `>` | Có trong actual, **không có** trong desired → cần **xóa** (hoặc là drift) |

Đầu ra mẫu (minh họa):

```text
4c4
< taskhub-public-b
---
> taskhub-test-subnet
```

Đọc: `4c4` = dòng 4 (sau khi sort) khác nhau; thiếu `taskhub-public-b` (phải tạo), thừa `taskhub-test-subnet` (phải xóa hoặc đưa vào code). Đây là phiên bản "thô sơ" của `terraform plan`.

> Chạy các lab Bash của module **trong WSL**, không trong Git Bash trên Windows: Git Bash mặc định giả lập `ln -s` bằng cách **sao chép**, nên ví dụ symlink ở mục 9 cho kết quả khác Linux thật.

---

## 9. Bài thực hành từng bước

> 0 USD. Không tạo tài nguyên AWS. Chuẩn bị: `mkdir -p ~/devops-lab/07-iac/01 && cd ~/devops-lab/07-iac/01`

### Bước 1 — Script mệnh lệnh vs idempotent `[WSL]`

Tạo `imperative.sh`:

```bash
#!/usr/bin/env bash
# Mô phỏng "dựng server" kiểu mệnh lệnh — mỗi lệnh giả định trạng thái ban đầu trống
set -euo pipefail
base="$HOME/devops-lab/07-iac/01/fake-server"
mkdir "$base"
mkdir "$base/opt-taskhub"
echo "TASKHUB_IMAGE_TAG=v0.5.0" >> "$base/opt-taskhub/.env"
ln -s "$base/opt-taskhub" "$base/current"
echo "Dựng xong"
```

Tạo `idempotent.sh` — cùng mục tiêu nhưng chạy lại an toàn:

```bash
#!/usr/bin/env bash
set -euo pipefail
base="$HOME/devops-lab/07-iac/01/fake-server"
env_file="$base/opt-taskhub/.env"
line="TASKHUB_IMAGE_TAG=v0.5.0"

mkdir -p "$base/opt-taskhub"
touch "$env_file"
if grep -qxF "$line" "$env_file"; then
  echo "ok      .env đã đúng"
else
  echo "$line" >> "$env_file"
  echo "changed .env được cập nhật"
fi
ln -sfn "$base/opt-taskhub" "$base/current"
echo "Dựng xong"
```

Chạy và quan sát:

```bash
chmod +x imperative.sh idempotent.sh
./imperative.sh          # lần 1
./imperative.sh          # lần 2 — chuyện gì xảy ra? exit code?
rm -rf fake-server

./idempotent.sh          # lần 1
./idempotent.sh          # lần 2
./idempotent.sh          # lần 3
cat fake-server/opt-taskhub/.env
```

❓ Ghi vào `~/devops-lab/07-iac/01/notes.md`: lần 2 của `imperative.sh` dừng ở dòng nào, vì sao (`set -e`)? Nếu **bỏ** `set -e`, file `.env` sẽ ra sao sau 3 lần chạy? Lần 2 và 3 của `idempotent.sh` in `ok` hay `changed`?

### Bước 2 — Mô phỏng drift và "plan" bằng `diff` `[WSL]`

```bash
# Desired state: những gì "code" nói phải có
printf '%s\n' taskhub-public-a taskhub-public-b taskhub-private-a taskhub-private-b > desired.txt
# Actual state: ai đó đã xóa public-b và tạo thêm một subnet thử nghiệm trên console
printf '%s\n' taskhub-public-a taskhub-private-a taskhub-private-b taskhub-test-subnet > actual.txt

diff <(sort desired.txt) <(sort actual.txt)
```

❓ Viết lại kết quả theo kiểu một "plan": bao nhiêu tài nguyên sẽ được **tạo**, bao nhiêu sẽ bị **xóa** nếu công cụ đưa thực tế về đúng code? Với `taskhub-test-subnet`, khi nào nên xóa, khi nào nên **thêm vào code**?

### Bước 3 — Kiểm kê hạ tầng tay của v2/v3: ai tạo ở v4? `[giấy hoặc Markdown]`

Mở [v2 §5 — Tài nguyên AWS phải có](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md#5-tài-nguyên-aws-phải-có), [v3](../12-PRACTICAL-PROJECT/milestones/v3-cd.md) (mục kiến trúc, file phải có, dọn dẹp) và `infra/aws-manual/commands.md` trong repo của bạn. Lập bảng `~/devops-lab/07-iac/01/inventory.md`:

| # | Tài nguyên / việc làm tay ở v2–v3 | Tạo ở v4 bởi | Lý do |
|---|---|---|---|
| 1 | VPC `taskhub-vpc` | Terraform | Hạ tầng mạng — vòng đời tạo/xóa |
| 2 | Cài Docker Engine trên EC2 | Ansible | Cấu hình bên trong máy |
| 3 | AWS Budget | ? | ? |
| … | … | … | … |

Yêu cầu: **ít nhất 20 dòng**, mỗi dòng chọn một trong: **Terraform / Ansible / Tay (giữ nguyên) / Không cần nữa**. Gợi ý những thứ dễ bỏ sót: Parameter Store, OIDC provider, role deploy, log group, alarm, SNS topic **và subscription email**, bucket backup, tham số `AWS_DEPLOY_ROLE_ARN` trên GitHub, environment `production`, user `phuong-admin`, root MFA, file `.env` trên EC2, `git clone` vào `/opt/taskhub`.

❓ Những dòng nào bạn xếp vào "Tay (giữ nguyên)"? Vì sao chúng **không nên** (hoặc không thể) nằm trong Terraform của dự án?

### Bước 4 — Đọc CloudFormation và Terraform song song `[đọc]`

Bạn đã chạy template CloudFormation ở [break-fix 06-AWS](../06-AWS/labs/break-fix-01/README.md) (`broken-stack.yaml`). Đây là một đoạn của nó (VPC, subnet, security group):

```yaml
Resources:
  Vpc:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.99.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true
      Tags:
        - Key: Name
          Value: bf06-vpc

  WebSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref Vpc
      CidrBlock: 10.99.1.0/24
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: bf06-web-subnet

  WebSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: bf06-web-sg
      GroupDescription: bf06 web server
      VpcId: !Ref Vpc
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
```

Và đoạn Terraform **tương đương** (bạn chưa cần chạy — bài 02 sẽ giải thích từng dòng):

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = "10.99.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "bf06-vpc"
  }
}

resource "aws_subnet" "web" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.99.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "bf06-web-subnet"
  }
}

resource "aws_security_group" "web" {
  name        = "bf06-web-sg"
  description = "bf06 web server"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}
```

❓ Trả lời trong `notes.md`:

1. `!Ref Vpc` (CloudFormation) tương ứng với gì trong Terraform? Cả hai cách tham chiếu đó giúp công cụ biết **điều gì** về thứ tự tạo?
2. `!Select [0, !GetAZs '']` tương ứng với khối nào? Vì sao không viết cứng `ap-southeast-1a`?
3. Ở Terraform, rule của security group là một **resource riêng** (`aws_vpc_security_group_ingress_rule`). Đoán xem lợi ích là gì khi muốn thêm/bớt một rule? (bài 02 sẽ xác nhận)
4. CloudFormation lưu "tài nguyên nào thuộc stack nào" ở đâu? Terraform lưu ở đâu? (gợi ý: bạn xóa stack bằng một lệnh mà không cần file nào trên máy)
5. Nếu bạn sửa SG trên console (thêm cổng 22) rồi chạy lại công cụ, mỗi công cụ phát hiện điều đó thế nào? (CloudFormation: tìm hiểu tính năng *drift detection*; Terraform: `plan` — bài 03)

### Bước 5 — Ghi một mục nhật ký

Ghi vào `troubleshooting-journal.md` (theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md)) lỗi khi chạy `imperative.sh` lần 2: triệu chứng, nguyên nhân, cách sửa (idempotent), bài học.

### Dọn dẹp

```bash
rm -rf ~/devops-lab/07-iac/01/fake-server
```

Giữ lại `notes.md` và `inventory.md` — `inventory.md` là đầu vào trực tiếp cho [Lab 02](labs/lab-02-taskhub-infra-terraform.md) và [v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md).

---

## 10. Kết quả mong đợi

- `imperative.sh` chạy lần 2 **thất bại** ở `mkdir "$base"` với `File exists`, exit code khác 0.
- `idempotent.sh` lần 1 in `changed`, lần 2 và 3 in `ok`; file `.env` chỉ có **một** dòng.
- `diff` cho thấy 1 dòng cần tạo, 1 dòng thừa.
- `inventory.md` có ≥ 20 dòng, mỗi dòng có chủ sở hữu ở v4 và lý do.
- Trả lời được 5 câu ở Bước 4.

Đầu ra mẫu của `imperative.sh` lần 2 (minh họa):

```text
mkdir: cannot create directory '/home/phuong/devops-lab/07-iac/01/fake-server': File exists
```

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách sửa |
|---|---|---|
| Nghĩ "IaC = viết script tự động hóa" | Script mệnh lệnh cũng tự động, nhưng không idempotent, không so sánh trạng thái | Phân biệt: IaC mô tả **trạng thái**; công cụ tính phải làm gì |
| Nghĩ "đã có IaC thì sửa tay trên console cũng được" | Mỗi lần sửa tay là một lần drift | Mọi thay đổi qua code; chữa cháy xong phải đưa vào code |
| Cho Terraform làm hết, kể cả cài phần mềm trong máy bằng user data dài hàng trăm dòng | Không phân biệt provisioning và config management | User data tối thiểu; dùng Ansible (hoặc image dựng sẵn) |
| Commit file `.tfvars` có mật khẩu | Không nghĩ file biến là secret | `.gitignore` + chỉ commit `*.example` |
| Thấy `grep -q` không hoạt động | Quên `-x`/`-F`: mẫu có `.` bị hiểu là regex, hoặc khớp một phần dòng | Dùng `grep -qxF` khi so cả dòng cố định |
| `diff` báo khác dù hai danh sách giống | Khác thứ tự, hoặc file có CRLF (sửa trên Windows) | `sort` trước; kiểm tra `file desired.txt` (xem [Linux 01](../01-LINUX/01-linux-architecture-filesystem.md)) |

---

## 12. Đọc log và xử lý lỗi

Bài này chưa có công cụ IaC thật, nên "log" là output script của bạn. Thói quen cần hình thành ngay, vì Terraform và Ansible đều in theo đúng tinh thần này:

| Dấu hiệu trong output | Ý nghĩa | Ở Terraform / Ansible sau này |
|---|---|---|
| `ok` | Đã đúng trạng thái, không làm gì | Ansible: `ok`; Terraform: `No changes. Your infrastructure matches the configuration.` |
| `changed` | Đã phải sửa để khớp mong muốn | Ansible: `changed`; Terraform: `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.` |
| Lỗi + exit code ≠ 0 | Dừng giữa chừng — trạng thái có thể **nửa vời** | Terraform: tài nguyên đã tạo trước lỗi **vẫn được ghi vào state**; chạy lại `apply` sẽ tiếp tục từ đó |

**Điều cần nhớ:** khi một công cụ IaC báo lỗi giữa chừng, đừng hoảng và đừng xóa tay những gì đã tạo. Công cụ idempotent được thiết kế để bạn **sửa nguyên nhân rồi chạy lại**. Xóa tay mới là cách tạo ra drift.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Kể 4 vấn đề của click-ops mà bạn đã **thực sự gặp** ở v2/v3.
2. Khác biệt giữa khai báo và mệnh lệnh? Cho một ví dụ mỗi loại từ chính dự án `taskhub`.
3. Idempotency là gì? Vì sao `mkdir -p` idempotent còn `echo ... >> file` thì không?
4. `compose.yaml` là khai báo hay mệnh lệnh? Bằng chứng nào từ hành vi của `docker compose up -d` chạy lần 2?
5. Desired state, actual state, drift là gì? Vẽ vòng lặp so sánh.
6. Có drift — khi nào nên chạy lại công cụ để "sửa ngược", khi nào nên cập nhật code?
7. Mutable và immutable infrastructure khác nhau thế nào? `taskhub` đang immutable ở tầng nào, mutable ở tầng nào?
8. Vì sao infrastructure immutable đòi hỏi dữ liệu phải nằm ngoài máy?
9. Provisioning và configuration management khác nhau thế nào? Mỗi loại một công cụ và một việc cụ thể ở v4.
10. Terraform và OpenTofu liên quan thế nào? Giấy phép BSL ảnh hưởng gì tới việc bạn dùng Terraform ở công ty?
11. CloudFormation khác Terraform ở những điểm nào (phạm vi, ngôn ngữ, nơi giữ state)?
12. Vì sao reviewer phải đọc **plan**, không chỉ đọc diff code?
13. Kể 3 nơi secret có thể rò rỉ khi dùng IaC và cách phòng mỗi nơi.
14. 🟦 4 nguyên tắc GitOps là gì? `taskhub` v4 đã thỏa nguyên tắc nào, chưa thỏa nguyên tắc nào?

---

## 14. Bài tập tự làm

**Bài 1 — Viết lại một đoạn `deploy.sh` cho idempotent.** Mở `scripts/deploy.sh` của bạn (v2/v3). Tìm mọi lệnh **không** idempotent (gợi ý: thêm dòng vào `.env`, tạo thư mục, tạo file). Với mỗi lệnh, ghi lý do và cách viết lại. Không cần sửa file thật nếu nó đã chạy đúng — bài tập là **phân tích**.

**Bài 2 — Mô phỏng "plan" có 3 loại thay đổi.** Mở rộng Bước 2: mỗi dòng có dạng `tên=cidr` (ví dụ `taskhub-public-a=10.20.1.0/24`). Viết script Bash `plan.sh desired.txt actual.txt` in ra 3 nhóm: **create** (chỉ có trong desired), **destroy** (chỉ có trong actual), **update** (cùng tên, khác CIDR). Script phải chạy đúng với `set -euo pipefail` và không phụ thuộc thứ tự dòng.

**Bài 3 — ADR nhỏ: công cụ IaC cho taskhub.** Viết nháp `docs/adr/0008-terraform-s3-backend.md` (sẽ hoàn thiện ở v4) theo [mẫu ADR](../12-PRACTICAL-PROJECT/README.md#7-ghi-lại-quyết-định-adr): so sánh ít nhất **3** lựa chọn (Terraform, OpenTofu, CloudFormation hoặc CDK), mỗi lựa chọn có ưu/nhược, và hệ quả tiêu cực trung thực của lựa chọn cuối cùng.

**Bài 4 — Phân loại 15 việc.** Với mỗi việc sau, chọn công cụ phù hợp nhất (Terraform / Ansible / Dockerfile / Compose / tay) và giải thích một câu: tạo bucket S3; đổi timezone của server; cài `htop`; mở cổng 443 trên SG; đổi phiên bản JDK trong image; tạo user IAM cho đồng nghiệp mới; xoay vòng mật khẩu PostgreSQL; thêm alarm CPU; thêm service Prometheus cạnh app; tăng `mem_limit` của container; tạo DNS record; bật MFA cho root; cập nhật `nginx/default.conf` trên server; tạo SNS topic; gỡ một gói có lỗ hổng trên server.

**Bài 5 — Drift detection của CloudFormation (đọc tài liệu).** Đọc tài liệu AWS về *CloudFormation drift detection*. Viết 5–8 dòng: nó phát hiện được những thay đổi nào, có tự sửa không, so với `terraform plan` thì khác gì.

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Kể được ít nhất 4 vấn đề của click-ops bằng trải nghiệm v2/v3 của chính mình.
- [ ] Giải thích khai báo vs mệnh lệnh, có ví dụ từ dự án (`commands.md` vs `compose.yaml`).
- [ ] Viết được script Bash idempotent và chứng minh bằng chạy 3 lần.
- [ ] Vẽ được vòng lặp desired/actual/drift và nói được hai cách xử lý drift.
- [ ] Phân biệt provisioning và configuration management; biết `taskhub` v4 chia việc giữa Terraform và Ansible thế nào.
- [ ] Có `inventory.md` ≥ 20 dòng — sẵn sàng cho Lab 02.
- [ ] Giải thích được Terraform vs OpenTofu vs CloudFormation ở mức đủ trả lời phỏng vấn.
- [ ] Kể được các nơi secret có thể rò rỉ trong IaC.

---

## Nguồn tham khảo

| Vai trò | Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|---|
| Chính | [Terraform — What is Infrastructure as Code with Terraform?](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/infrastructure-as-code) | IaC, workflow Terraform, khai báo | 2026-10-31 |
| Chính | [HashiCorp adopts the Business Source License](https://www.hashicorp.com/en/blog/hashicorp-adopts-business-source-license) | Thay đổi giấy phép ngày 10/8/2023; người dùng cuối vẫn dùng được cho production | 2026-10-31 |
| Chính | [OpenTofu FAQ](https://opentofu.org/faq/) | Fork của Terraform, Linux Foundation, tương thích state tới 1.5.x | 2026-10-31 |
| Chính | [OpenGitOps — Principles](https://opengitops.dev/) | 4 nguyên tắc GitOps | 2026-10-31 |
| Bổ sung | [AWS CloudFormation — Detect unmanaged configuration changes (drift)](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-stack-drift.html) | Drift detection của CloudFormation (bài tập 5) | 2026-10-31 |
| Bổ sung | [Ansible — Introduction / Getting started](https://docs.ansible.com/ansible/latest/getting_started/index.html) | Ansible không cần agent, playbook | 2026-10-31 |
| Bổ sung | [Terraform AWS provider — aws_vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | Rule SG dạng resource riêng (Bước 4) | 2026-10-31 |
| Bổ sung | [Terraform AWS provider — aws_ssm_parameter (value_wo)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | Write-only argument, Terraform ≥ 1.11 | 2026-10-31 |
