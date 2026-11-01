# Lời giải — Bài 04: Terraform module, môi trường và chất lượng code

> Chỉ đọc sau khi đã tự làm. Quay lại bài: [04-terraform-modules-environments.md](../04-terraform-modules-environments.md)

## Câu hỏi trong lab

**Bước 1 — Thêm AZ thứ ba vào code phẳng.** Phải thêm 2 `aws_subnet` + 2 `aws_route_table_association` = 4 block mới, mỗi block gần như copy của block cũ, và dễ quên association (subnet mới khi đó rơi vào **main route table**). Với module: thêm 2 dòng vào hai map ở `envs/dev`.

**Bước 2 — `for_each = aws_subnet.public`.** Hai cách có cùng tập khóa (`a`, `b`), nhưng chỉ resource `aws_subnet.public` có thuộc tính `id` của subnet thật → `each.value.id` dùng được trực tiếp. Lặp qua biến thì phải tra `aws_subnet.public[each.key].id` — dài hơn, cùng kết quả.

**Bước 2 — map + `for_each` thay vì list + `count`.** Với `count`, địa chỉ là chỉ số (`aws_subnet.public[0]`, `[1]`). Xóa phần tử đầu danh sách → mọi phần tử sau dịch chỉ số → Terraform thấy `[0]` đổi CIDR, `[1]` biến mất → **thay thế** hàng loạt subnet (và mọi thứ trong đó). Với `for_each`, địa chỉ là khóa (`["a"]`, `["b"]`) — xóa `a` không ảnh hưởng `b`.

**Bước 3 — Plan khi chưa có `moved`.** `Plan: 13 to add, 0 to change, 13 to destroy`. Terraform thấy 13 địa chỉ cũ biến mất và 13 địa chỉ mới xuất hiện; không có gì cho nó biết đó là cùng object.

**Bước 4 — Thiếu một `moved`.** `1 to add, 1 to destroy`: hủy `aws_route_table_association.private_b`, tạo `module.network.aws_route_table_association.private["b"]`. Với association, hậu quả nhẹ (vài giây subnet dùng main route table) — nhưng nguyên tắc vẫn là 0 destroy.

**Bước 5 — Phát hiện của Trivy.** Kết quả cụ thể phụ thuộc phiên bản bộ kiểm tra. Các nhóm thường gặp với module này và cách xử lý hợp lý:

| Loại phát hiện | Quyết định cho `taskhub` |
|---|---|
| Subnet tự gán public IP (`map_public_ip_on_launch`) | **Chấp nhận** — public subnet chứa EC2 cần IP public để nhận traffic (không có ALB/NAT). Ghi lý do |
| VPC không bật flow logs | **Chấp nhận ở lab/dev**, ghi lý do (chi phí lưu log CloudWatch/S3); cân nhắc bật khi có môi trường prod |
| (Ở v4) SG mở `0.0.0.0/0` cổng 80/443 | **Chấp nhận** — web server công khai; cổng 22 **không** được mở |

Tiêu chí đạt: mỗi phát hiện có quyết định **và** lý do.

**Bước 7 — `envs/prod` khác `envs/dev`.** Backend key khác (`envs/prod/...`), thường **tài khoản AWS khác** (cách ly hoàn toàn, quyền khác); ít người được apply, apply qua pipeline có duyệt; tfvars khác (instance lớn hơn, Multi-AZ, alarm gửi on-call, retention log dài hơn); có thể gọi thêm module (ALB, RDS) mà dev không có.

## Câu hỏi kiểm tra kiến thức

1. Root module là thư mục chạy lệnh, có state/backend/provider. Child module được gọi bằng block `module`, không có state riêng; tài nguyên nằm trong state của root với địa chỉ `module.<tên>.<type>.<name>` (lồng nhau thì `module.a.module.b...`).
2. variable ↔ tham số; output ↔ giá trị trả về; locals ↔ biến cục bộ; validation ↔ kiểm tra tham số đầu vào (ném lỗi sớm với thông điệp rõ).
3. Local, Registry, Git. Chỉ Registry dùng `version`. Git ghim bằng `?ref=<tag hoặc SHA>`; SHA là bất biến tuyệt đối.
4. Cấu hình provider (region, credential, default_tags) là quyết định của root; module có `provider` riêng thì người gọi không kiểm soát được và module trở thành *legacy module*, không dùng được với `count`, `for_each`, `depends_on`.
5. `terraform init`.
6. Địa chỉ đổi từ `aws_subnet.public_a` sang `module.network.aws_subnet.public["a"]`; Terraform coi là hai resource khác nhau.

   ```hcl
   moved {
     from = aws_subnet.public_a
     to   = module.network.aws_subnet.public["a"]
   }
   ```

7. Địa chỉ theo khóa ổn định; thêm/xóa một phần tử không làm dịch địa chỉ phần tử khác (xem câu hỏi Bước 2 ở trên).
8. (1) Các workspace trong một thư mục dùng **chung backend**, trong khi môi trường thật thường cần credential và quyền riêng; (2) dễ apply nhầm môi trường vì môi trường không hiện trong đường dẫn/code, và khác biệt cấu trúc phải viết bằng điều kiện khắp nơi. Hợp với: bản sao tạm thời cùng cấu hình (thử nghiệm theo nhánh).
9. Cao → thấp: `-var x=...` > `a.auto.tfvars` > `terraform.tfvars` > `TF_VAR_x` > `default`.
10. Gắn bộ tag chung (Project, Env, Owner, ManagedBy) cho mọi resource hỗ trợ tag mà không lặp lại, không quên tag. `Name` khác nhau theo resource → khai trong từng resource (hoặc tạo trong module từ tiền tố `name`).
11. `validate` kiểm tra cú pháp và tính nhất quán theo schema provider (kiểu, argument bắt buộc, tham chiếu). tflint kiểm tra **giá trị** theo hiểu biết riêng về provider và các quy ước: `instance_type = "t3.smal"` qua `validate` nhưng bị tflint bắt (`aws_instance_invalid_type`); biến khai mà không dùng.
12. Đọc phát hiện, xác nhận đó là thiết kế có chủ đích (EC2 web trong public subnet, không ALB/NAT), ghi quyết định chấp nhận kèm lý do; không tắt cảnh báo mà không giải thích. Kiểm tra thêm: SG chỉ mở 80/443, không mở 22.
13. Có — mặc định `command = apply` tạo hạ tầng thật rồi hủy khi xong. `mock_provider` thay provider thật bằng bản giả: không gọi API, giá trị tính toán được sinh tự động → test miễn phí, không cần credential. `expect_failures` khẳng định một `run` **phải** thất bại ở đối tượng chỉ định (ví dụ `var.vpc_cidr` bị validation từ chối) — test rằng luật kiểm tra đầu vào hoạt động.
14. `fmt -check`, `init -backend=false` + `validate`, tflint (rule mặc định không gọi AWS), `trivy config`, `terraform test` với `mock_provider`.

## Bài tập tự làm

### Bài 1 — AZ thứ ba

```hcl
public_subnets = {
  a = { az = "ap-southeast-1a", cidr = "10.30.1.0/24" }
  b = { az = "ap-southeast-1b", cidr = "10.30.2.0/24" }
  c = { az = "ap-southeast-1c", cidr = "10.30.3.0/24" }
}

private_subnets = {
  a = { az = "ap-southeast-1a", cidr = "10.30.11.0/24" }
  b = { az = "ap-southeast-1b", cidr = "10.30.12.0/24" }
  c = { az = "ap-southeast-1c", cidr = "10.30.13.0/24" }
}
```

Plan: `4 to add, 0 to change, 0 to destroy` — `module.network.aws_subnet.public["c"]`, `aws_subnet.private["c"]`, `aws_route_table_association.public["c"]`, `aws_route_table_association.private["c"]`. Code phẳng: 4 block mới (~25 dòng) so với 2 dòng.

### Bài 2 — Validation CIDR subnet nằm trong VPC

Từ Terraform 1.9, điều kiện `validation` được tham chiếu **biến khác** của cùng module. Một cách kiểm tra "subnet nằm trong VPC": địa chỉ mạng của subnet khi áp **mặt nạ của VPC** phải bằng địa chỉ mạng của VPC.

```hcl
variable "public_subnets" {
  type = map(object({
    az   = string
    cidr = string
  }))

  validation {
    condition = alltrue([
      for s in values(var.public_subnets) :
      cidrhost("${cidrhost(s.cidr, 0)}/${split("/", var.vpc_cidr)[1]}", 0) == cidrhost(var.vpc_cidr, 0)
      && tonumber(split("/", s.cidr)[1]) >= tonumber(split("/", var.vpc_cidr)[1])
    ])
    error_message = "Mọi CIDR trong public_subnets phải nằm trong vpc_cidr."
  }
}
```

Giải thích: lấy địa chỉ đầu của subnet, gắn prefix của VPC → `cidrhost(..., 0)` trả về địa chỉ mạng ở độ dài prefix VPC; nếu bằng địa chỉ mạng của VPC thì subnet bắt đầu trong VPC; điều kiện thứ hai đảm bảo subnet không **rộng** hơn VPC.

Test:

```hcl
run "subnet_outside_vpc_rejected" {
  command = plan

  variables {
    public_subnets = {
      a = { az = "ap-southeast-1a", cidr = "10.50.1.0/24" }
    }
  }

  expect_failures = [var.public_subnets]
}
```

Cách viết khác đều được nếu test chứng minh đúng hành vi (một subnet trong, một subnet ngoài, một subnet rộng hơn VPC).

### Bài 3 — Output cho `app_server`

Output hiện có (`vpc_id`, `public_subnet_ids` dạng map, `private_subnet_ids` dạng map) đã đủ; người gọi tự chọn:

```hcl
module "app_server" {
  source = "../../modules/app_server"

  name      = "taskhub"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids["a"]
}

# Dùng ở lab RDS tuần 14:
# subnet_ids = values(module.network.private_subnet_ids)
```

Chấp nhận thêm output tiện lợi (ví dụ `private_subnet_id_list = values(...)`) nếu giải thích được vì sao. Không đạt: output trả cả object `aws_subnet` (lộ quá nhiều, ràng buộc chặt).

### Bài 4 — Module VPC công khai

Đáp án phải tự tra trên mã nguồn v6.7.3 (các điểm dưới đây là thứ cần tìm, không phải để chép):

- (a) Biến điều khiển NAT Gateway và giá trị mặc định của nó — ghi rõ tên biến, mặc định, và tác động chi phí (NAT tính theo giờ + theo GB).
- (b) Quy ước tên subnet (tiền tố từ biến `name`, hậu tố theo loại/AZ).
- (c) Module **không** có block `provider` (đúng nguyên tắc module dùng chung).

Kết luận hợp lý: `taskhub` (1 VPC, mục tiêu học) → tự viết; công ty 20 VPC → module công khai ghim phiên bản, hoặc module nội bộ dựa trên nó, với quy trình nâng phiên bản có review plan.

### Bài 5 — tfvars trên cùng state

`plan -var-file=test.tfvars` đổi `cidr_block` của VPC → thuộc tính này **không đổi tại chỗ được** → `forces replacement` → plan thay VPC và mọi thứ phụ thuộc (subnet, route, association…). Lý do: cùng một **state** chỉ mô tả **một** bộ hạ tầng; đổi file biến không tạo bộ thứ hai mà biến bộ hiện có thành bộ kia. Hai môi trường = hai bộ hạ tầng = hai state → hai thư mục (hai backend key).

### Bài 6 — `infra.yml`

Khung đạt yêu cầu (SHA phải tự lấy bằng `git ls-remote`, không chép số dưới đây vì không có):

```yaml
name: Infra

on:
  pull_request:
    paths:
      - 'infra/**'

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  terraform-checks:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<SHA> # v7.x
        with:
          persist-credentials: false

      - uses: hashicorp/setup-terraform@<SHA> # vX.Y.Z
        with:
          terraform_version: 1.17.1

      - name: fmt
        run: terraform fmt -check -recursive infra/terraform

      - name: validate envs
        run: |
          for d in infra/terraform/envs/*/; do
            terraform -chdir="$d" init -backend=false -input=false
            terraform -chdir="$d" validate
          done

      - name: test modules
        run: |
          for d in infra/terraform/modules/*/; do
            if ls "$d"tests/*.tftest.hcl >/dev/null 2>&1; then
              terraform -chdir="$d" init -input=false
              terraform -chdir="$d" test
            fi
          done

      - name: tflint
        run: |
          docker run --rm -v "$PWD/infra/terraform":/data -t --entrypoint /bin/sh \
            ghcr.io/terraform-linters/tflint:v0.65.0 -c "tflint --init && tflint --recursive"

      - name: trivy config
        run: |
          docker run --rm -v "$PWD/infra/terraform":/src:ro aquasec/trivy:0.76.1 \
            config --ignorefile /src/.trivyignore --severity HIGH,CRITICAL --exit-code 1 /src
```

Điểm chấm:

- `paths` chỉ `infra/**` — nhớ hệ quả với required status check đã học ở [CI/CD 02](../../05-CICD/02-github-actions-basics.md): nếu đặt job này là check bắt buộc, PR không chạm `infra/` sẽ bị kẹt chờ.
- Không có credential AWS, `permissions: contents: read`.
- Mọi `run:` có `: ` đều dùng khối `|` (bẫy YAML ở CI/CD 02).
- `trivy config --exit-code 1` chỉ làm đỏ khi có HIGH/CRITICAL — phát hiện đã chấp nhận phải nằm trong `infra/terraform/.trivyignore`, mỗi dòng kèm lý do và hạn `exp:`. Trivy chỉ tự đọc `.trivyignore` ở **thư mục làm việc** (trong container là `/`), không phải thư mục được quét — vì vậy phải truyền `--ignorefile`. Đã chạy thử với code tham khảo v4 (Trivy 0.76.1, 2026-10-31): không có file ignore → 1 CRITICAL (AWS-0104, egress mọi đích) + 6 HIGH (AWS-0164 ×2, AWS-0132 ×3, AWS-0095) → job đỏ; với [.trivyignore tham khảo](../labs/reference/terraform/.trivyignore) → xanh, còn lại 6 phát hiện LOW/MEDIUM để đọc.
- actionlint không báo lỗi.
