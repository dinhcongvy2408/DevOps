# Module `network`

VPC của `taskhub`: mỗi phần tử của `public_subnets`/`private_subnets` là một subnet, một Internet Gateway, route table public (`0.0.0.0/0 → IGW`) và route table private (chỉ `local`). **Không có NAT Gateway** (ADR-0005).

Subnet dùng `for_each` trên **map** có khóa `a`/`b` — địa chỉ trong state là `aws_subnet.public["a"]`, không phải `[0]`. Xóa hay thêm một AZ không làm subnet khác bị "đánh số lại" rồi bị thay thế (cùng giao diện với module ở [bài 04](../../../../../04-terraform-modules-environments.md)).

## Input

| Biến | Kiểu | Bắt buộc | Ví dụ |
|---|---|---|---|
| `name` | string | ✅ | `"taskhub"` → `taskhub-vpc`, `taskhub-public-a`… |
| `vpc_cidr` | string | ✅ | `"10.20.0.0/16"` |
| `public_subnets` | map(object({ az = string, cidr = string })) | ✅ | `{ a = { az = "ap-southeast-1a", cidr = "10.20.1.0/24" }, b = { az = "ap-southeast-1b", cidr = "10.20.2.0/24" } }` |
| `private_subnets` | map(object({ az = string, cidr = string })) | — (mặc định `{}`) | `{ a = { az = "ap-southeast-1a", cidr = "10.20.11.0/24" }, b = { … "10.20.12.0/24" } }` |

Khóa của map là hậu tố trong tên subnet: khóa `a` → `taskhub-public-a`.

## Output

| Output | Mô tả |
|---|---|
| `vpc_id` | ID của VPC |
| `vpc_cidr` | CIDR của VPC |
| `public_subnet_ids` | Map khóa → ID subnet public, ví dụ `module.network.public_subnet_ids["a"]` |
| `private_subnet_ids` | Map khóa → ID subnet private |

Module không có khối `provider`: root module quyết định region và tag (`default_tags`).
