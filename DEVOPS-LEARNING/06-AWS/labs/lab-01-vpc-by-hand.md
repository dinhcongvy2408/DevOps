# Lab 01 — Dựng VPC `taskhub` bằng tay

> Tuần 11 · Thời lượng: 2–3 giờ · Mức độ: 🟥 Bắt buộc
> Kiến thức cần có trước: [bài 03 — VPC](../03-vpc-networking.md) (đọc hết), [bài 00 — tài khoản, MFA, Budget](../00-aws-account-setup-cost-safety.md), [bài 02 — IAM](../02-iam.md) (đăng nhập bằng user `<tên>-admin`, không dùng root), [bài 06 — AWS CLI](../06-aws-cli.md) (`aws login`, profile `taskhub`)
> Đầu vào: `docs/network-plan.md` của bạn (tuần 4, đã rà soát ở bài 03 mục 9)

## Mục lục

- [Ước tính chi phí](#ước-tính-chi-phí)
- [Mục tiêu](#mục-tiêu)
- [Phần A — Chuẩn bị](#phần-a--chuẩn-bị)
- [Phần B — Dựng từng mảnh trên console](#phần-b--dựng-từng-mảnh-trên-console)
- [Phần C — Kiểm chứng bằng AWS CLI](#phần-c--kiểm-chứng-bằng-aws-cli)
- [Phần D — Thí nghiệm](#phần-d--thí-nghiệm)
- [Phần E — Sơ đồ và commit](#phần-e--sơ-đồ-và-commit)
- [Kết quả mong đợi](#kết-quả-mong-đợi)
- [Lỗi thường gặp](#lỗi-thường-gặp)
- [Giữ lại hay dọn dẹp?](#giữ-lại-hay-dọn-dẹp)
- [Câu hỏi sau lab](#câu-hỏi-sau-lab)

---

## Ước tính chi phí

| Tài nguyên tạo trong lab | Chi phí | Nguồn (kiểm tra 2026-10-31) |
|---|---|---|
| VPC, 4 subnet, 3 route table | **0 USD** — *"no additional charges for creating and using the VPC itself"* | [Amazon VPC FAQ](https://aws.amazon.com/vpc/faqs/) |
| Internet Gateway | **0 USD** (chỉ tính phí dữ liệu của EC2 đi qua — lab này chưa có EC2) | [AWS — Internet gateways](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html) |
| Security Group, Network ACL | **0 USD** | [Security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html), [Network ACLs](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html) |
| Bật *auto-assign public IPv4* trên subnet | **0 USD** cho đến khi có EC2 thật sự nhận IP (khi đó 0,005 USD/giờ mỗi IP) | [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) |
| **Tổng lab** | **0 USD** | |

> ⚠️ **Những thứ tuyệt đối KHÔNG tạo trong lab này** (đều tính tiền theo giờ): **NAT Gateway**, **Elastic IP**, **interface VPC endpoint**, **EC2**. Nếu một màn hình nào đó gợi ý tạo chúng — bấm **Cancel**.
>
> Cuối buổi: mở **Billing and Cost Management** kiểm tra không có dòng chi phí mới (dữ liệu billing có thể trễ vài giờ — kiểm tra lại hôm sau).

## Mục tiêu

- Tự tay tạo từng thành phần: VPC → subnet → IGW → route table → Security Group, hiểu **vì sao** từng bước.
- Biến kế hoạch tuần 4 thành hạ tầng thật, đúng tên và tag theo [quy ước dự án](../README.md).
- Kiểm chứng bằng CLI thay vì "nhìn console thấy ổn".
- Chứng minh bằng thí nghiệm: subnet public hay private là do **route table**.

Kết quả là nền mạng cho EC2 ở [bài 04](../04-ec2.md) và [dự án v2](../../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md).

---

## Phần A — Chuẩn bị

### A1. Bảng giá trị của bạn

Điền bảng sau từ `docs/network-plan.md`. Cột "Ví dụ" là giá trị dùng trong giáo trình — **dùng số của bạn** nếu khác.

| Thành phần | Ví dụ | Của bạn |
|---|---|---|
| VPC `taskhub-vpc` | `10.20.0.0/16` | |
| `taskhub-public-a` (ap-southeast-1a) | `10.20.1.0/24` | |
| `taskhub-public-b` (ap-southeast-1b) | `10.20.2.0/24` | |
| `taskhub-private-a` (ap-southeast-1a) | `10.20.11.0/24` | |
| `taskhub-private-b` (ap-southeast-1b) | `10.20.12.0/24` | |

### A2. Bộ tag dùng cho **mọi** tài nguyên

| Key | Value |
|---|---|
| `Name` | Theo bảng trên (`taskhub-vpc`, `taskhub-public-a`…) |
| `Project` | `taskhub` |
| `Env` | `dev` |
| `Owner` | Tên bạn (ví dụ `phuong`) |
| `ManagedBy` | `manual` (sẽ thành `terraform` ở v4) |

Vì sao tag kỹ ngay từ đầu? (1) Lọc được bằng CLI: `--filters Name=tag:Project,Values=taskhub`. (2) Tìm tài nguyên sót khi dọn dẹp. (3) **Cost allocation tag** ở [bài 00](../00-aws-account-setup-cost-safety.md) tách chi phí theo dự án. (4) Khi chuyển sang Terraform, `ManagedBy=manual` cho biết thứ gì còn tạo bằng tay.

### A3. Kiểm tra trước khi bắt đầu

- [ ] Đăng nhập console bằng **IAM user admin** (góc phải trên hiển thị `<tên>-admin @ <account>`), **không phải root**.
- [ ] Region ở góc phải trên là **Asia Pacific (Singapore) ap-southeast-1**.
- [ ] `[WSL]` CLI hoạt động:

```bash
export AWS_PROFILE=taskhub
export AWS_REGION=ap-southeast-1
aws sts get-caller-identity --query Arn --output text
```

```text
arn:aws:iam::111122223333:user/phuong-admin
```

Thấy `:root` ở cuối ARN → dừng lại, đăng nhập lại bằng user admin ([bài 02](../02-iam.md)).

---

## Phần B — Dựng từng mảnh trên console

> Lab dùng **VPC only** — tạo từng thứ một — để bạn hiểu từng mảnh. Wizard **VPC and more** tạo mọi thứ trong một màn hình; bạn sẽ xem nó ở thí nghiệm D7 nhưng **không** dùng để tạo.

### B1. Tạo VPC `[AWS Console]`

1. **VPC console** → **Your VPCs** → **Create VPC**.
2. **Resources to create**: **VPC only**.
3. **Name tag**: `taskhub-vpc`.
4. **IPv4 CIDR block**: **IPv4 CIDR manual input** → dải VPC của bạn.
5. **IPv6 CIDR block**: **No IPv6 CIDR block**. **Tenancy**: **Default**.
6. **Tags**: thêm `Project`, `Env`, `Owner`, `ManagedBy` (tag `Name` đã có từ bước 3).
7. **Create VPC**.

Bật DNS hostnames (mặc định `false` với VPC bạn tự tạo — [bài 03 §4.10](../03-vpc-networking.md#410--dns-trong-vpc)):

8. Chọn `taskhub-vpc` → **Actions** → **Edit VPC settings** → tích **Enable DNS hostnames** (để nguyên **Enable DNS resolution** đã tích) → **Save**.

❓ Mở tab **Resource map** của VPC: đã có những gì dù bạn chỉ tạo "VPC only"? (Gợi ý: một route table và… — tìm cả trong **Network ACLs** và **Security groups**.)

### B2. Tạo 4 subnet `[AWS Console]`

1. **Subnets** → **Create subnet** → **VPC ID**: `taskhub-vpc`.
2. Subnet 1: **Subnet name** `taskhub-public-a`, **Availability Zone** `Asia Pacific (Singapore) / ap-southeast-1a`, **IPv4 subnet CIDR block** theo bảng A1, thêm 4 tag còn lại.
3. **Add new subnet** → lặp lại cho `taskhub-public-b` (1b), `taskhub-private-a` (1a), `taskhub-private-b` (1b).
4. **Create subnet**.

❓ Ngay sau khi tạo, mở tab **Route table** của `taskhub-public-a`. Nó đang dùng route table nào, có route tới Internet không? Vậy **lúc này** nó là public hay private?

### B3. Bật auto-assign public IPv4 cho 2 subnet public `[AWS Console]`

Với **từng** subnet `taskhub-public-a` và `taskhub-public-b`:

**Actions** → **Edit subnet settings** → tích **Enable auto-assign public IPv4 address** → **Save**.

Không làm với 2 subnet private.

> Bước này **không** làm subnet thành public. Nó chỉ quyết định EC2 launch vào đó có nhận public IP hay không. Một instance có public IP mà subnet không có route tới IGW vẫn **không** ra được Internet (bài 03 §4.3).

### B4. Tạo và gắn Internet Gateway `[AWS Console]`

1. **Internet gateways** → **Create internet gateway** → **Name tag** `taskhub-igw` + 4 tag → **Create**.
2. Trạng thái hiện **Detached**. **Actions** → **Attach to VPC** → `taskhub-vpc` → **Attach internet gateway**.
3. Trạng thái chuyển thành **Attached**.

❓ Gắn IGW xong, `taskhub-public-a` đã public chưa? Vì sao?

### B5. Route table `[AWS Console]`

**Đặt tên cho main route table** (để không nhầm khi nhìn danh sách):

1. **Route tables** → lọc theo VPC `taskhub-vpc` → dòng có cột **Main = Yes** → sửa **Name** thành `taskhub-main-rt`, thêm 4 tag. **Không thêm route nào** vào bảng này.

**Route table cho public subnet:**

2. **Create route table** → **Name** `taskhub-public-rt`, **VPC** `taskhub-vpc`, 4 tag → **Create**.
3. Tab **Routes** → **Edit routes** → **Add route**: **Destination** `0.0.0.0/0`, **Target** **Internet Gateway** → `taskhub-igw` → **Save changes**.
4. Tab **Subnet associations** → **Edit subnet associations** → tích `taskhub-public-a`, `taskhub-public-b` → **Save associations**.

**Route table cho private subnet:**

5. **Create route table** → `taskhub-private-rt`, VPC `taskhub-vpc`, 4 tag.
6. **Không thêm route** (chỉ có `local`). **Subnet associations** → gắn `taskhub-private-a`, `taskhub-private-b`.

> Vì sao tạo `taskhub-private-rt` riêng mà không để 2 subnet private dùng main route table? Gắn **rõ ràng** giúp đọc cấu hình là biết ý định; và sau này nếu cần thêm route riêng cho private (ví dụ gateway endpoint S3) thì không ảnh hưởng subnet nào khác. Main route table giữ vai trò "lưới an toàn" cho subnet quên gắn.

### B6. Security Group `taskhub-web-sg` `[AWS Console]`

1. **Security groups** (trong VPC console hoặc EC2 console) → **Create security group**.
2. **Security group name** `taskhub-web-sg`; **Description** `taskhub web: HTTP/HTTPS from Internet`; **VPC** `taskhub-vpc`.
3. **Inbound rules** → **Add rule** hai lần:

| Type | Protocol | Port range | Source | Description |
|---|---|---|---|---|
| HTTP | TCP | 80 | Anywhere-IPv4 `0.0.0.0/0` | `nginx http` |
| HTTPS | TCP | 443 | Anywhere-IPv4 `0.0.0.0/0` | `nginx https (when domain + cert)` |

4. **Outbound rules**: giữ luật mặc định (All traffic → `0.0.0.0/0`).
5. **Tags**: `Name` = `taskhub-web-sg` + 4 tag → **Create security group**.

**Không thêm port 22.** Bài 04 dùng SSM Session Manager.

❓ Trong ô **Type** của inbound rule, có lựa chọn nào để **deny** không? Điều đó nói gì về Security Group?

### B7. Nhìn lại toàn cảnh `[AWS Console]`

**Your VPCs** → `taskhub-vpc` → tab **Resource map**. Bạn phải thấy: 4 subnet chia 2 AZ, 3 route table (main, public, private), đường nối từ `taskhub-public-rt` tới `taskhub-igw`. Chụp màn hình lưu vào `week11/`.

<details>
<summary>Gợi ý cấp 1 — Resource map không có đường nối tới IGW</summary>

Route `0.0.0.0/0 → igw` chưa được lưu, hoặc bạn thêm vào nhầm bảng. Mở `taskhub-public-rt` → tab **Routes**.

</details>

<details>
<summary>Gợi ý cấp 2 — Public subnet vẫn nối vào main route table</summary>

Bước B5.4 chưa **Save associations**. Mở subnet → tab **Route table** → **Edit route table association**.

</details>

---

## Phần C — Kiểm chứng bằng AWS CLI

> Mọi lệnh ở phần này **chỉ đọc** — 0 USD. Đầu ra là **minh họa**; ID và thứ tự dòng của bạn sẽ khác.

### C1. Tìm VPC theo tag `[WSL]`

```bash
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc \
           --query 'Vpcs[0].VpcId' --output text)
echo "$VPC_ID"

aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].{Cidr:CidrBlock,Default:IsDefault,Tags:Tags}' --output json
aws ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames \
  --query 'EnableDnsHostnames.Value' --output text
```

```text
vpc-0123456789abcdef0
{
    "Cidr": "10.20.0.0/16",
    "Default": false,
    "Tags": [
        {"Key": "Name", "Value": "taskhub-vpc"},
        {"Key": "Project", "Value": "taskhub"},
        ...
    ]
}
True
```

`echo` in ra `None` → không tìm thấy VPC: sai tên tag, sai Region, hoặc sai profile.

### C2. Subnet `[WSL]`

```bash
aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,AZ:AvailabilityZone,Cidr:CidrBlock,Free:AvailableIpAddressCount,PublicIp:MapPublicIpOnLaunch}' \
  --output table
```

```text
--------------------------------------------------------------------------------------
|                                   DescribeSubnets                                  |
+------------------+------------------+-------+----------------------+---------------+
|        AZ        |      Cidr        | Free  |        Name          |   PublicIp    |
+------------------+------------------+-------+----------------------+---------------+
|  ap-southeast-1a |  10.20.1.0/24    |  251  |  taskhub-public-a    |  True         |
|  ap-southeast-1b |  10.20.12.0/24   |  251  |  taskhub-private-b   |  False        |
|  ap-southeast-1b |  10.20.2.0/24    |  251  |  taskhub-public-b    |  True         |
|  ap-southeast-1a |  10.20.11.0/24   |  251  |  taskhub-private-a   |  False        |
+------------------+------------------+-------+----------------------+---------------+
```

- `Free = 251` — đúng con số 256 − 5 của bài 03.
- `` Tags[?Key==`Name`]|[0].Value ``: trong mảng `Tags`, lọc phần tử có `Key` là `Name`, lấy phần tử đầu, lấy `Value`. Dấu backtick `` ` `` là cách JMESPath viết chuỗi hằng — vì cả biểu thức nằm trong nháy đơn nên bash không đụng tới nó.

### C3. Route table và IGW `[WSL]`

```bash
aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC_ID" \
  --query 'RouteTables[].{Name:Tags[?Key==`Name`]|[0].Value,Main:Associations[?Main]|[0].Main,Subnets:Associations[].SubnetId,Routes:Routes[].[DestinationCidrBlock,GatewayId]}' \
  --output json

aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" \
  --query 'InternetGateways[].{Id:InternetGatewayId,State:Attachments[0].State,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

```json
[
  { "Name": "taskhub-main-rt", "Main": true,
    "Subnets": [],
    "Routes": [["10.20.0.0/16", "local"]] },
  { "Name": "taskhub-public-rt", "Main": null,
    "Subnets": ["subnet-0aaa…", "subnet-0bbb…"],
    "Routes": [["10.20.0.0/16", "local"], ["0.0.0.0/0", "igw-0ccc…"]] },
  { "Name": "taskhub-private-rt", "Main": null,
    "Subnets": ["subnet-0ddd…", "subnet-0eee…"],
    "Routes": [["10.20.0.0/16", "local"]] }
]
```

Đọc: chỉ `taskhub-public-rt` có `0.0.0.0/0 → igw` → đúng 2 subnet gắn vào nó là public. Main route table không gắn subnet nào (`[]` — association "main" không có `SubnetId`, và phép chiếu JMESPath bỏ qua giá trị null).

### C4. Security Group `[WSL]`

```bash
aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values=taskhub-web-sg \
  --query 'SecurityGroups[0].{Id:GroupId,In:IpPermissions[].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp],Out:IpPermissionsEgress[].[IpProtocol,IpRanges[0].CidrIp]}' \
  --output json
```

```json
{
  "Id": "sg-0fff…",
  "In": [["tcp", 80, 80, "0.0.0.0/0"], ["tcp", 443, 443, "0.0.0.0/0"]],
  "Out": [["-1", "0.0.0.0/0"]]
}
```

### C5. Tất cả tài nguyên mang tag `Project=taskhub` `[WSL]`

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=taskhub \
  --query 'ResourceTagMappingList[].ResourceARN' --output text | tr '\t' '\n'
```

Phải thấy ARN của VPC, 4 subnet, IGW, 3 route table, SG — **10 dòng** (nếu bạn tag đủ). Thiếu dòng nào → tài nguyên đó thiếu tag; bổ sung trên console (tab **Tags** → **Manage tags**).

### C6. Script kiểm tra tự động `[WSL]`

Lưu thành `~/devops-lab/06-aws/verify-vpc.sh`. Script **chỉ đọc**. Đổi `VPC_CIDR` nếu dải của bạn khác.

```bash
#!/usr/bin/env bash
# verify-vpc.sh — kiểm tra VPC taskhub sau Lab 01. Chỉ dùng lệnh describe (0 USD).
set -euo pipefail

export AWS_REGION="${AWS_REGION:-ap-southeast-1}"
VPC_NAME="${VPC_NAME:-taskhub-vpc}"
VPC_CIDR="${VPC_CIDR:-10.20.0.0/16}"
pass=0
fail=0

check() {  # check "mô tả" "giá trị thực tế" "giá trị mong đợi"
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
    pass=$((pass + 1))
  else
    echo "FAIL  $1 (thực tế: '$2', mong đợi: '$3')"
    fail=$((fail + 1))
  fi
}

vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
           --query 'Vpcs[0].VpcId' --output text)
if [[ "$vpc_id" == "None" ]]; then
  echo "FAIL  Không tìm thấy VPC có tag Name=$VPC_NAME ở $AWS_REGION"
  exit 1
fi

check "CIDR của VPC" \
  "$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --query 'Vpcs[0].CidrBlock' --output text)" "$VPC_CIDR"
check "enableDnsHostnames" \
  "$(aws ec2 describe-vpc-attribute --vpc-id "$vpc_id" --attribute enableDnsHostnames \
       --query 'EnableDnsHostnames.Value' --output text)" "True"
check "Số subnet" \
  "$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
       --query 'length(Subnets)' --output text)" "4"
check "Số subnet tự cấp public IPv4" \
  "$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=map-public-ip-on-launch,Values=true" \
       --query 'length(Subnets)' --output text)" "2"
check "IGW đã gắn vào VPC" \
  "$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" \
       --query 'InternetGateways[0].Attachments[0].State' --output text)" "available"

main_rt=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$vpc_id" "Name=association.main,Values=true" \
            --query 'RouteTables[0].RouteTableId' --output text)
check "Main route table không có route ra Internet" \
  "$(aws ec2 describe-route-tables --route-table-ids "$main_rt" \
       --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`])' --output text)" "0"

# Mỗi subnet: "có route tới IGW" phải trùng với "tự cấp public IPv4"
for subnet in $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
                  --query 'Subnets[].SubnetId' --output text); do
  name=$(aws ec2 describe-subnets --subnet-ids "$subnet" \
           --query 'Subnets[0].Tags[?Key==`Name`]|[0].Value' --output text)
  map_public=$(aws ec2 describe-subnets --subnet-ids "$subnet" \
                 --query 'Subnets[0].MapPublicIpOnLaunch' --output text)
  rt=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$subnet" \
         --query 'RouteTables[0].RouteTableId' --output text)
  [[ "$rt" == "None" ]] && rt="$main_rt"   # không gắn rõ ràng → dùng main route table
  target=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
             --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]|[0].GatewayId' --output text)
  if [[ "$target" == igw-* ]]; then has_igw="True"; else has_igw="False"; fi
  check "Subnet $name: route tới IGW ($has_igw) khớp auto-assign public IP" "$has_igw" "$map_public"
done

check "Inbound của taskhub-web-sg chỉ gồm port 80 và 443" \
  "$(aws ec2 describe-security-groups \
       --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=taskhub-web-sg" \
       --query 'SecurityGroups[0].IpPermissions[].FromPort' --output text | tr '\t' '\n' | sort -n | paste -sd, -)" "80,443"
check "Cả 4 subnet có tag Project=taskhub" \
  "$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" "Name=tag:Project,Values=taskhub" \
       --query 'length(Subnets)' --output text)" "4"

echo
echo "Kết quả: $pass PASS, $fail FAIL"
[[ "$fail" -eq 0 ]]
```

```bash
chmod +x ~/devops-lab/06-aws/verify-vpc.sh
VPC_CIDR=10.20.0.0/16 ~/devops-lab/06-aws/verify-vpc.sh
```

```text
PASS  CIDR của VPC
PASS  enableDnsHostnames
PASS  Số subnet
PASS  Số subnet tự cấp public IPv4
PASS  IGW đã gắn vào VPC
PASS  Main route table không có route ra Internet
PASS  Subnet taskhub-public-a: route tới IGW (True) khớp auto-assign public IP
PASS  Subnet taskhub-private-b: route tới IGW (False) khớp auto-assign public IP
PASS  Subnet taskhub-public-b: route tới IGW (True) khớp auto-assign public IP
PASS  Subnet taskhub-private-a: route tới IGW (False) khớp auto-assign public IP
PASS  Inbound của taskhub-web-sg chỉ gồm port 80 và 443
PASS  Cả 4 subnet có tag Project=taskhub

Kết quả: 12 PASS, 0 FAIL
```

❓ Đọc lại vòng `for`: vì sao script phải tự xử lý trường hợp subnet **không** gắn route table rõ ràng? Bỏ dòng `[[ "$rt" == "None" ]] && rt="$main_rt"` thì script sai ở tình huống nào?

---

## Phần D — Thí nghiệm

> Thí nghiệm D1–D4 dùng lệnh `create-subnet`. D1–D3 **được thiết kế để thất bại** (không tạo gì). D4 tạo một subnet tạm và xóa ngay. Subnet không tính phí, nhưng hãy làm đúng bước dọn.

### D1. Subnet chồng lấn `[WSL]`

```bash
aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.20.1.128/25 \
  --availability-zone ap-southeast-1a
```

Dự đoán trước khi chạy: thành công hay lỗi, mã lỗi gì? Ghi kết quả thật. (Đổi `10.20.1.128/25` thành một dải nằm trong `public-a` **của bạn** nếu dải khác.)

### D2. Subnet nằm ngoài VPC `[WSL]`

```bash
aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.30.0.0/24 \
  --availability-zone ap-southeast-1a
```

### D3. Subnet quá nhỏ `[WSL]`

```bash
aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.20.50.0/29 \
  --availability-zone ap-southeast-1a
```

So sánh với giới hạn `/28`–`/16` ở bài 03. Thử lại với `/28` **chỉ trong đầu** — nó có hợp lệ không, và còn bao nhiêu IP dùng được?

> Nếu D1–D3 ngoài dự đoán lại **tạo thành công** một subnet (vì dải của bạn khác ví dụ), xóa ngay: ⚠️ `aws ec2 delete-subnet --subnet-id <id-vừa-tạo>`.

### D4. Subnet "quên gắn" route table rơi vào đâu? `[WSL]`

```bash
# ⚠️ Tạo tài nguyên (0 USD) — xóa ở cuối thí nghiệm
TEMP_SUBNET=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.20.99.0/24 \
  --availability-zone ap-southeast-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=taskhub-temp},{Key=Project,Value=taskhub}]' \
  --query Subnet.SubnetId --output text)
echo "$TEMP_SUBNET"

# Có route table nào gắn RÕ RÀNG với nó không?
aws ec2 describe-route-tables --filters Name=association.subnet-id,Values="$TEMP_SUBNET" \
  --query 'RouteTables[].RouteTableId' --output text

# Chạy lại script kiểm tra
~/devops-lab/06-aws/verify-vpc.sh || true
```

❓ Lệnh `describe-route-tables` trả về gì? Subnet tạm đang dùng bảng nào? Nó public hay private? Script báo gì và vì sao (có 2 dòng thay đổi)? Nếu ở B5 bạn đã thêm route IGW vào **main** route table thì subnet tạm sẽ ra sao?

Dọn ngay:

```bash
# ⚠️ Xóa subnet tạm
aws ec2 delete-subnet --subnet-id "$TEMP_SUBNET"
aws ec2 describe-subnets --filters Name=tag:Name,Values=taskhub-temp --query 'length(Subnets)'
```

Kết quả cuối phải là `0`.

### D5. Gỡ route ra Internet `[AWS Console]`

1. `taskhub-public-rt` → **Routes** → **Edit routes** → **Remove** dòng `0.0.0.0/0` → **Save**.
2. Chạy lại `verify-vpc.sh`. Mở **Resource map**.
3. ❓ Bây giờ `taskhub-public-a` là public hay private? Nếu lúc này đã có EC2 chạy Nginx ở đó (có public IP, SG mở 80), người dùng Internet thấy gì — *connection refused* hay *timeout*? Vì sao?
4. **Thêm lại** route `0.0.0.0/0 → taskhub-igw` và chạy `verify-vpc.sh` cho tới khi **12 PASS**.

### D6. Security Group không có "deny"

Tạm thời thêm vào `taskhub-web-sg` một luật inbound **SSH 22** từ **My IP** (console tự điền IP public của bạn dạng `x.x.x.x/32`). Quan sát: luật có nút chọn Allow/Deny không? Sau đó **xóa luật này ngay** (SG của dự án không mở 22). ❓ Muốn chặn hẳn một IP xấu khỏi subnet, bạn dùng thành phần nào?

### D7. Xem wizard "VPC and more" — **không tạo** `[AWS Console]`

1. **Create VPC** → **VPC and more**. **Không** bấm Create ở cuối.
2. Nhập thử: 2 AZ, 2 public subnet, 2 private subnet.
3. Đọc ô **NAT gateways**: những lựa chọn nào? Chọn thử khác **None** và xem khung **Preview** thay đổi thế nào.
4. Đọc ô **VPC endpoints**: lựa chọn **S3 Gateway** là gì, tốn tiền không? (bài 03 §4.6)
5. Ghi vào `week11/vpc-lab.md`: wizard tạo những gì mà bạn đã tạo bằng tay, và thứ gì bạn **không** muốn nó tạo.
6. Bấm **Cancel**. Kiểm tra lại không có VPC mới:

```bash
aws ec2 describe-vpcs --query 'Vpcs[].{Id:VpcId,Cidr:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' --output table
aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId'
```

Phải chỉ thấy default VPC và `taskhub-vpc`; danh sách NAT Gateway rỗng (`[]`).

---

## Phần E — Sơ đồ và commit

1. Cập nhật `docs/network-plan.md` của repo `taskhub`: thêm mục **"Đã triển khai (tuần 11)"** gồm sơ đồ ASCII (theo mẫu [bài 03 §6.1](../03-vpc-networking.md#61-vpc-của-taskhub-v2)) với **tên** tài nguyên, bảng route table và bảng luật của `taskhub-web-sg`.
2. **Không** commit ID tài nguyên hay Account ID vào repo public. Account ID không phải mật khẩu, nhưng không có lý do gì để công khai. Ghi ID vào `week11/vpc-lab.md` trong repo nhật ký `devops-journey` (private hoặc không chứa thông tin nhạy cảm).
3. Commit qua PR như mọi khi:

```bash
cd ~/projects/taskhub
git switch main && git pull
git switch -c docs/vpc-deployed
git add docs/network-plan.md
git commit -m "docs(network): document taskhub-vpc as deployed in week 11"
git push -u origin docs/vpc-deployed
```

---

## Kết quả mong đợi

- [ ] `verify-vpc.sh` báo **12 PASS, 0 FAIL**.
- [ ] `get-resources` theo tag `Project=taskhub` liệt kê đủ 10 tài nguyên (VPC, 4 subnet, IGW, 3 route table, SG) và không có `taskhub-temp`.
- [ ] Trả lời được mọi câu ❓ trong lab, ghi trong `week11/vpc-lab.md`.
- [ ] D1–D3 thất bại với mã lỗi bạn đã dự đoán (hoặc bạn giải thích được vì sao khác).
- [ ] Không có NAT Gateway, Elastic IP, EC2 nào trong tài khoản.
- [ ] `docs/network-plan.md` có mục "Đã triển khai" và đã merge qua PR.

## Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| Không thấy `taskhub-vpc` trong console | Đang xem Region khác | Đổi Region góc phải trên sang Singapore |
| `VPC_ID` là `None` | Sai tag `Name`, sai Region/profile | `aws configure list`, `echo $AWS_REGION`, xem tag trên console |
| `verify-vpc.sh`: `enableDnsHostnames` FAIL | Quên B1.8 | **Edit VPC settings** → **Enable DNS hostnames** |
| `verify-vpc.sh`: subnet public báo `False` cho route IGW | Chưa gắn vào `taskhub-public-rt` (B5.4) | **Subnet associations** → **Edit** |
| `verify-vpc.sh`: số subnet tự cấp public IP = 0 | Quên B3 | **Edit subnet settings** cho từng subnet public |
| Không chọn được IGW làm target khi sửa route | IGW chưa **Attached** vào VPC này | B4.2 |
| Không tạo được subnet: `InvalidSubnet.Conflict` | CIDR chồng lấn subnet có sẵn (thường do gõ nhầm) | Đối chiếu bảng A1 |
| Script báo lỗi `ExpiredToken` / yêu cầu đăng nhập | Phiên `aws login` hết hạn | `aws login --profile taskhub` |
| `get-resources` thiếu dòng | Tài nguyên thiếu tag `Project` | Tab **Tags** → **Manage tags** |

<details>
<summary>Gợi ý cấp 3 — Đã sửa mà <code>verify-vpc.sh</code> vẫn FAIL ở cùng một dòng</summary>

In phần dữ liệu mà dòng đó đọc, ví dụ với route table của một subnet:

```bash
aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=<subnet-id> --output json
```

So sánh từng trường với điều bạn nghĩ là đúng. Nếu output không có route table nào → subnet đang dùng main route table. Thói quen này ("in dữ liệu thô ra trước khi kết luận") quan trọng hơn bản thân lab.

</details>

## Giữ lại hay dọn dẹp?

> 🟢 **Khuyến nghị: GIỮ LẠI `taskhub-vpc`** nếu bạn tiếp tục [bài 04 — EC2](../04-ec2.md) và [dự án v2](../../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md) trong tuần 11–12. Một VPC **không có EC2, NAT Gateway, Elastic IP hay endpoint** không phát sinh chi phí (xem bảng [Ước tính chi phí](#ước-tính-chi-phí)). Từ tuần 15, Terraform sẽ thay thế VPC tạo bằng tay này.

Dọn dẹp khi: bạn muốn làm lại lab từ đầu, hoặc đã chuyển sang VPC do Terraform quản lý (tuần 15–16).

**Thứ tự xóa — phụ thuộc trước, VPC sau** (nếu xóa ngược, AWS báo `DependencyViolation`):

| # | Xóa | Vì sao phải trước |
|---|---|---|
| 0 | Mọi EC2, ENI, NAT Gateway, endpoint trong VPC (lab này chưa có) | ENI nằm trong subnet; còn ENI thì không xóa được subnet |
| 1 | Security Group `taskhub-web-sg` | SG thuộc VPC (SG mặc định tự bị xóa cùng VPC) |
| 2 | 4 subnet | Subnet thuộc VPC; xóa subnet tự gỡ liên kết route table |
| 3 | Route table `taskhub-public-rt`, `taskhub-private-rt` | Main route table tự bị xóa cùng VPC |
| 4 | **Detach** rồi **Delete** `taskhub-igw` | IGW đang gắn thì VPC không xóa được |
| 5 | VPC `taskhub-vpc` | Cuối cùng |

**Cách 1 — Console:** **Your VPCs** → chọn `taskhub-vpc` → **Actions** → **Delete VPC**. Console liệt kê các tài nguyên đi kèm sẽ bị xóa cùng (subnet, route table, IGW, SG…), yêu cầu gõ xác nhận. Đọc kỹ danh sách trước khi xác nhận.

**Cách 2 — CLI** (để hiểu thứ tự):

```bash
# ⚠️ XÓA TÀI NGUYÊN — chỉ chạy khi chắc chắn không cần VPC nữa. Không hoàn tác được.
export AWS_PROFILE=taskhub AWS_REGION=ap-southeast-1
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=taskhub-vpc --query 'Vpcs[0].VpcId' --output text)

SG_ID=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values=taskhub-web-sg \
          --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 delete-security-group --group-id "$SG_ID"

for s in $(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --subnet-id "$s"
done

for rt in $(aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC_ID" \
              --query 'RouteTables[?!(Associations[?Main])].RouteTableId' --output text); do
  aws ec2 delete-route-table --route-table-id "$rt"
done

IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values="$VPC_ID" \
           --query 'InternetGateways[0].InternetGatewayId' --output text)
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"

aws ec2 delete-vpc --vpc-id "$VPC_ID"
```

**Kiểm tra sau khi dọn** (chỉ đọc):

```bash
aws ec2 describe-vpcs --filters Name=tag:Project,Values=taskhub --query 'length(Vpcs)'
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=taskhub \
  --query 'ResourceTagMappingList[].ResourceARN'
aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId'
aws ec2 describe-addresses --query 'Addresses[].PublicIp'
```

Mong đợi: `0`, `[]`, `[]`, `[]`. (Tagging API có thể còn hiện ARN vừa xóa trong ít phút — chạy lại sau.)

- [ ] Không còn VPC/subnet/IGW/route table/SG mang tag `Project=taskhub` (nếu đã chọn dọn).
- [ ] Không có NAT Gateway, Elastic IP ở `ap-southeast-1`.
- [ ] Billing không có dòng chi phí mới (kiểm tra lại sau 24 giờ).

## Câu hỏi sau lab

1. Sau B2 (trước B5), 4 subnet đang public hay private? Bằng chứng nào trong console/CLI cho thấy điều đó?
2. Bạn bật auto-assign public IPv4 (B3) **trước** khi tạo route table (B5). Thứ tự này có ảnh hưởng kết quả không? Vì sao?
3. Kết quả D4 chứng minh điều gì về main route table? Viết thành một quy tắc cho team.
4. Ở D5, phân biệt rõ: thiếu route IGW, thiếu luật SG, Nginx không chạy — mỗi trường hợp phía client thấy gì?
5. Nếu tuần sau bạn cần cho máy ở `taskhub-private-a` ghi file lên S3 mà không có NAT Gateway, bạn sẽ thêm gì, vào route table nào, tốn bao nhiêu?
6. Đếm số thao tác click bạn đã làm trong Phần B. Tuần 15 bạn sẽ viết lại toàn bộ bằng Terraform — liệt kê 3 rủi ro của việc "dựng bằng tay" mà bạn đã gặp hoặc suýt gặp trong lab này.

Lời giải: [solutions/lab-01-solutions.md](../solutions/lab-01-solutions.md) — chỉ mở sau khi đã tự trả lời.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [AWS — Create a VPC](https://docs.aws.amazon.com/vpc/latest/userguide/create-vpc.html) | *VPC only*, *VPC and more*, tab Resource map, lệnh CLI | 2026-10-31 |
| [AWS — Subnet IP addressing attributes](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-public-ip.html) | *Edit subnet settings* → *Enable auto-assign public IPv4 address* | 2026-10-31 |
| [AWS — Internet gateways](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html) | Attach IGW, định nghĩa public subnet, IGW không tính phí | 2026-10-31 |
| [AWS — Understanding Amazon DNS](https://docs.aws.amazon.com/vpc/latest/userguide/AmazonDNS-concepts.html) | `enableDnsHostnames` mặc định `false` | 2026-10-31 |
| [Amazon VPC FAQ](https://aws.amazon.com/vpc/faqs/) | VPC không tính phí | 2026-10-31 |
| [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/) | Public IPv4, NAT Gateway | 2026-10-31 |
| [AWS CLI — describe-subnets](https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-subnets.html) | `AvailableIpAddressCount`, `MapPublicIpOnLaunch`, filter `map-public-ip-on-launch`, `tag:<key>` | 2026-10-31 |
| [AWS CLI — ec2 reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/) | `describe-route-tables`, `describe-internet-gateways`, `describe-security-groups`, `create-subnet`, `delete-*` | 2026-10-31 |
