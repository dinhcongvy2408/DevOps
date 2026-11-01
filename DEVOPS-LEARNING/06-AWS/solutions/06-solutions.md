# Lời giải — 06. AWS CLI

> Chỉ mở sau khi đã tự làm. Bài học: [06-aws-cli.md](../06-aws-cli.md). Đầu ra minh họa có thể khác trên máy bạn.

## Mục lục

- [Câu hỏi trong bài thực hành (❓)](#câu-hỏi-trong-bài-thực-hành-)
- [Năm câu hỏi về find-leftovers.sh (Bước 10)](#năm-câu-hỏi-về-find-leftoverssh-bước-10)
- [Mục 13 — Câu hỏi kiểm tra kiến thức](#mục-13--câu-hỏi-kiểm-tra-kiến-thức)
- [Mục 14 — Bài tập tự làm](#mục-14--bài-tập-tự-làm)

---

## Câu hỏi trong bài thực hành (❓)

**Bước 3 — Quyền của `~/.aws/login/cache/`.**
Kỳ vọng: chỉ chủ sở hữu đọc/ghi được (dạng `-rw-------` cho file, `drwx------` cho thư mục). Đúng vì file chứa credential tạm thời — user khác trên cùng máy không được đọc. Nếu bạn thấy quyền rộng hơn (ví dụ do chép thư mục từ Windows), siết lại: `chmod 700 ~/.aws ~/.aws/login ~/.aws/login/cache && chmod 600 ~/.aws/login/cache/*`. Ghi lại quyền thực tế bạn thấy vào nhật ký.

**Bước 4 — Hai lệnh `describe-vpcs` có cùng VPC ID không?**
Không. Mỗi region có VPC mặc định **riêng** (ID khác nhau). VPC là tài nguyên **thuộc một region**; region khác là "thế giới khác" — đó là lý do lệnh sai region trả về kết quả khác hoặc rỗng.

**Bước 4 — `ZoneName` và `ZoneId`.**
Theo tài liệu AWS, tên AZ (`ap-southeast-1a`) được **ánh xạ độc lập cho từng tài khoản** — `ap-southeast-1a` của bạn có thể là trung tâm dữ liệu khác với `ap-southeast-1a` của người khác. `ZoneId` (`apse1-az1`, `apse1-az2`…) là định danh **nhất quán giữa các tài khoản**. Dùng ZoneId khi cần phối hợp với tài khoản khác (ví dụ chia sẻ subnet, kết nối giữa hai tài khoản).

**Bước 5 — Số AZ `available`:**

```bash
aws ec2 describe-availability-zones \
  --query 'length(AvailabilityZones[?State==`available`])'
```

**Bước 7 — Exit code của `create-vpc --dry-run`.**
Khác 0 (với AWS CLI v2, lỗi do dịch vụ trả về thường cho mã **254**). Lý do: về mặt kỹ thuật, EC2 trả **lỗi** `DryRunOperation` — "lẽ ra thành công nhưng không làm vì cờ DryRun". Script tự động phải đọc **nội dung** lỗi (`DryRunOperation` = có quyền, `UnauthorizedOperation` = không có quyền), không thể chỉ dựa vào exit code. Ví dụ:

```bash
if out="$(aws ec2 create-vpc --cidr-block 10.99.0.0/16 --dry-run 2>&1)"; then
  echo "Bất thường: lệnh dry-run không được trả về thành công"
elif grep -q DryRunOperation <<< "$out"; then
  echo "Có quyền tạo VPC"
else
  echo "Không có quyền hoặc lỗi khác: $out"
fi
```

**Bước 8a — `AWS_REGION=us-east-1 aws …` ảnh hưởng tới đâu?**
Chỉ **lệnh đó**. Cú pháp `TÊN=giá-trị lệnh` đặt biến trong môi trường của riêng tiến trình con, shell hiện tại không đổi. Kiểm tra: `echo "${AWS_REGION:-chưa đặt}"` sau lệnh.

**Bước 8b — Đầu ra khi dùng key ví dụ (minh họa):**

```text
An error occurred (InvalidClientTokenId) when calling the GetCallerIdentity operation: The security token included in the request is invalid.
```

`aws configure list` hiện `TYPE` = `env`: biến môi trường **thắng** profile `taskhub`. Đây chính là kịch bản "mọi thứ trong `~/.aws/config` đúng mà vẫn lỗi".

**Bước 8c — Sau `aws logout`.**
CLI không còn credential cho profile `taskhub` và báo lỗi không tìm thấy credential (thông báo cụ thể tùy phiên bản CLI — ghi lại nguyên văn bạn thấy). `aws login --profile taskhub` khôi phục.

---

## Năm câu hỏi về find-leftovers.sh (Bước 10)

**1. Vì sao ghi cảnh báo vào file thay vì tăng biến đếm?**
`q` được gọi bên trong `$(...)` — command substitution chạy trong **subshell**. Biến thay đổi trong subshell **không** truyền về shell cha; một biến `warnings=$((warnings+1))` trong `q` sẽ luôn mất. File trên đĩa thì subshell và shell cha cùng thấy. (Biến `found` vẫn đếm được vì `report` chạy ở shell cha, không nằm trong `$(...)`.)

**2. `trap 'rm -f "$warn_file"' EXIT` làm gì?**
Khi script kết thúc vì **bất kỳ lý do gì** (chạy hết, `exit`, lỗi do `set -e`, hay Ctrl+C), bash chạy lệnh xóa file tạm. Bỏ dòng này: mỗi lần chạy để lại một file trong `/tmp` (rác tích tụ, và có thể chứa thông tin tài khoản).

**3. Vì sao không dừng khi gặp `AccessDenied` dù có `set -e`?**
Lệnh `aws` nằm trong điều kiện `if ! out="$(...)"` — `set -e` **không** áp dụng cho lệnh dùng làm điều kiện của `if`. `q` bắt lỗi, ghi cảnh báo và `return 0`. Đây là chủ ý: script kiểm kê nên chạy hết mọi mục, rồi báo cáo mục nào không kiểm tra được, thay vì dừng ở mục đầu tiên bị lỗi.

**4. Vì sao S3 và Route 53 chỉ quét một lần?**
Cả hai là dịch vụ **toàn cục** ở mức danh sách: `list-buckets` trả về **mọi** bucket của tài khoản bất kể region; hosted zone Route 53 không thuộc region nào. Lặp theo region sẽ in trùng.

**5. Loại tài nguyên bị bỏ sót (gợi ý, không có đáp án duy nhất):** ECR repository (lưu image), Secrets Manager secret, KMS customer managed key, EFS file system, DynamoDB table, Lambda function (thường rất rẻ), CloudFront distribution, Elastic Beanstalk/ECS/EKS (EKS control plane tốn tiền theo giờ), OpenSearch domain, CloudTrail trail ghi vào S3, AWS Config recorder. Kiểm tra giá trên trang pricing trước khi kết luận cái nào đáng quét.

---

## Mục 13 — Câu hỏi kiểm tra kiến thức

**1.** `curl … | bash` chạy code ngay khi tải, không có cơ hội kiểm chứng. Gói apt của Ubuntu là CLI v1/bản cũ, không có `aws login`. Zip + chữ ký PGP: chứng minh file do AWS CLI Team ký và không bị sửa.

**2.** Không. Cảnh báo chỉ nói bạn chưa đánh dấu tin cậy khóa này trong keyring cá nhân. Thứ chứng minh file hợp lệ là `Good signature` **và** fingerprint khóa khớp đúng giá trị trong tài liệu AWS chính thức (`FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C`).

**3.** `~/.aws/config`: tên profile, `login_session = <ARN danh tính>`, `region` — không có bí mật. `~/.aws/login/cache/`: credential tạm thời + dữ liệu làm mới — **có bí mật** (hết hạn nhanh, nhưng vẫn phải bảo vệ).

**4.** `aws configure` + key: credential dài hạn trong `~/.aws/credentials`; lộ là dùng được đến khi bị thu hồi; MFA phải xử lý riêng. `aws login`: credential tạm thời tự làm mới 15 phút, phiên tối đa 12 giờ; lộ cache thì giá trị bị giới hạn theo thời gian; MFA (kể cả passkey) đi theo phiên đăng nhập trình duyệt.

**5.** `eu-west-1`. Thứ tự ưu tiên: tham số dòng lệnh `--region` > `AWS_REGION` > `AWS_DEFAULT_REGION` > `region` trong profile.

**6.** `--filters` do **dịch vụ** xử lý, chỉ trả về bản ghi khớp; cú pháp riêng từng API. `--query` do **CLI** xử lý trên máy bạn bằng JMESPath, sau khi nhận phản hồi. Ví dụ: lọc instance đang chạy có tag `Project=taskhub` bằng `--filters`, rồi chỉ lấy ID và IP bằng `--query` (xem mục 4.5 của bài).

**7.**

```bash
aws ec2 describe-instances \
  --query 'Reservations[].Instances[].Tags[?Key==`Name`]|[].Value' --output text
```

Hoặc, kèm ID cho dễ đọc: `--query 'Reservations[].Instances[].[InstanceId,Tags[?Key==\`Name\`]|[0].Value]'`.

**8.** `--page-size`: mỗi lần gọi API lấy bao nhiêu bản ghi — CLI vẫn lấy **hết**, đầu ra **không đổi** (chỉ đổi số lần gọi). `--max-items`: giới hạn số bản ghi **in ra**, kèm `NextToken` → đầu ra **thay đổi**.

**9.** Trả lỗi `DryRunOperation: Request would have succeeded, but DryRun flag is set.` Exit code khác 0 vì về hình thức đó là phản hồi lỗi của dịch vụ.

**10.** Theo tài liệu: kiểm tra mỗi 15 giây, tối đa 40 lần → khoảng 10 phút. Thất bại thoát với mã **255**.

**11.** CLI v2 mặc định đưa đầu ra qua pager (`less` trên Linux). Trong script/cron không có ai bấm phím → script đứng chờ. `AWS_PAGER=""` tắt pager.

**12.** Credential đang lấy từ **biến môi trường** (`AWS_ACCESS_KEY_ID`…), ghi đè profile. Lỗi khó hiểu vì `~/.aws/config` đúng mà CLI lại dùng danh tính khác (hoặc key hết hạn/không tồn tại) — thường là biến còn sót từ lần assume role trước.

**13.** Không tìm được tài nguyên **không có tag** (hoặc quên gắn tag `Project=taskhub`), và một số loại tài nguyên không được Tagging API hỗ trợ. `find-leftovers.sh` bù lại bằng cách quét **theo loại tài nguyên** (instance, EIP, volume, NAT, LB, RDS…) bất kể tag.

**14.** AMI ID khác nhau giữa các region và đổi mỗi khi Canonical phát hành bản build mới (vá bảo mật) — chép cứng thì script chỉ đúng ở một region, và dần dùng image cũ chưa vá. Cách đúng: đọc tham số SSM công khai `/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id`, hoặc `describe-images --owners 099720109477` + lọc tên + sắp xếp theo `CreationDate`.

**15.** Không tính thêm phí (chỉ trả tiền tài nguyên bạn tạo). `$HOME` được giữ 1 GB mỗi region; dữ liệu bị xóa nếu không dùng CloudShell ở region đó 120 ngày.

---

## Mục 14 — Bài tập tự làm

### Bài 1 — Truy vấn

(a)

```bash
aws ec2 describe-regions \
  --query 'Regions[?starts_with(RegionName, `ap-`)].RegionName' --output text \
  | tr '\t' '\n' | sort
```

(b)

```bash
vpc_id="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" \
  --query 'sort_by(Subnets,&AvailabilityZone)[].{Id:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,FreeIPs:AvailableIpAddressCount}' \
  --output table
```

Để ý: VPC mặc định có subnet `/20` → 4096 địa chỉ, nhưng `FreeIPs` = 4091 vì AWS giữ lại 5 địa chỉ mỗi subnet (gặp lại ở [bài 03 VPC](../03-vpc-networking.md)).

(c)

```bash
aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true \
  --query 'length(InstanceTypes)'
```

> Lưu ý: kết quả của (c) cần đủ trang. Với `--output json` (mặc định), `--query` chạy một lần trên toàn bộ kết quả đã gộp — đúng như mong muốn. Với `--output text`, `length()` có thể chạy trên **từng trang**.

(d)

```bash
aws ec2 describe-images --owners 099720109477 \
  --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
  --query 'reverse(sort_by(Images,&CreationDate))[:3].[Name,CreationDate]' --output table
```

### Bài 2 — Hàm `whoami-aws`

```bash
# Thêm vào ~/.bashrc
whoami-aws() {
  local arn src region
  if ! arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)"; then
    echo "Chưa đăng nhập AWS (profile: ${AWS_PROFILE:-default}). Chạy: aws login --profile ${AWS_PROFILE:-default}"
    return 1
  fi
  region="$(aws configure get region 2>/dev/null)"
  region="${AWS_REGION:-${region:-chưa đặt}}"
  src="$(aws configure list 2>/dev/null | awk '$1 == "access_key" {print $(NF-1)}')"
  printf '%s | account %s | region %s | nguồn %s\n' "$arn" "$(cut -d: -f5 <<< "$arn")" "$region" "${src:-?}"
}
```

- Hàm dùng `return`, **không** `exit` — `exit` trong hàm của `~/.bashrc` sẽ đóng cả terminal.
- Không dùng `set -e` trong hàm nạp vào shell tương tác (sẽ ảnh hưởng cả shell).
- Cột nguồn lấy bằng `awk` từ `aws configure list`. Định dạng cột có thể khác nhẹ giữa các phiên bản CLI — nếu `awk` trả sai, in thử `aws configure list | cat -A` để xem dấu phân cách rồi chỉnh.

### Bài 3 — Mở rộng `find-leftovers.sh` (ví dụ)

```bash
  report "[$r] ECR repository (lưu image tính theo dung lượng)" "$(q "$r" ecr describe-repositories \
    --query 'repositories[].[repositoryName,createdAt]')"

  report "[$r] Secrets Manager secret (tính phí theo số secret/tháng)" "$(q "$r" secretsmanager list-secrets \
    --query 'SecretList[].[Name,LastChangedDate]')"
```

Đặt hai khối này trong vòng lặp `for r in …` cùng các mục khác. Lý do chọn: cả hai đều tính phí theo thời gian tồn tại, dễ bị quên khi thử nghiệm. **Bạn phải tự mở trang pricing** của ECR và Secrets Manager, ghi giá ap-southeast-1 và ngày kiểm tra vào comment — giáo trình không ghi con số để tránh lỗi thời. Các ứng viên khác: `kms list-keys` (cần lọc khóa *customer managed* bằng `describe-key`, phức tạp hơn), `efs describe-file-systems`, `eks list-clusters`. SNS topic gần như không tốn tiền khi không gửi tin — không đáng quét.

### Bài 4 — Chạy hằng ngày

Cron (đơn giản, chạy được nếu `cron` đang chạy trong WSL — xem Linux bài 08):

```cron
0 22 * * * AWS_PROFILE=taskhub $HOME/devops-lab/06-aws/find-leftovers.sh ap-southeast-1 us-east-1 > $HOME/devops-lab/06-aws/leftovers-$(date +\%F).log 2>&1
```

- `%` trong crontab phải viết `\%`.
- Cron có PATH tối giản: nếu `aws` không tìm thấy, thêm `PATH=/usr/local/bin:/usr/bin:/bin` ở đầu crontab.
- **Khi phiên `aws login` đã hết hạn** (tối đa 12 giờ): `aws sts get-caller-identity` thất bại → script in "Chưa đăng nhập…" ra stderr và **thoát mã 2** — không báo nhầm là "sạch". Đây là lý do script tách mã 2/3 khỏi mã 0.
- Cách được nhắc: thêm vào `~/.bashrc` một đoạn in dòng cuối của log mới nhất mỗi khi mở terminal:

```bash
latest="$(ls -t ~/devops-lab/06-aws/leftovers-*.log 2>/dev/null | head -1)"
[[ -n "$latest" ]] && echo "[find-leftovers] $(basename "$latest"): $(tail -1 "$latest")"
```

Hạn chế cần ghi nhận: WSL chỉ chạy khi bạn mở nó; máy tắt lúc 22:00 thì không có lần quét đó. **AWS Budgets** (bài 00) mới là lưới an toàn thật vì chạy phía AWS.

### Bài 5 — Chạy bằng profile role chỉ-đọc

Với `AWS_PROFILE=taskhub-ro` (role chỉ có `s3:ListAllMyBuckets` và `ec2:Describe*` ở ap-southeast-1):

- Các mục EC2 ở **ap-southeast-1** chạy được.
- Các mục EC2 ở **us-east-1** (nếu quét) bị `UnauthorizedOperation` → vào danh sách cảnh báo.
- `elbv2`, `autoscaling`, `rds`, `logs`, `resourcegroupstaggingapi`, `route53` → `AccessDenied` → cảnh báo.
- `s3api list-buckets` chạy được.
- Kết quả: nếu không có tài nguyên nào, script kết thúc mã **3** ("sạch nhưng có mục chưa kiểm tra được") — đúng thiết kế: không được coi là "an toàn" khi chưa kiểm tra hết.

Bài học: script kiểm kê cần quyền **đọc** rộng (ví dụ AWS managed policy `ReadOnlyAccess` hoặc `ViewOnlyAccess`), và phải báo rõ khi thiếu quyền thay vì im lặng trả "không có gì".

Dọn dẹp: xóa role/policy demo, xóa profile `taskhub-ro`, `rm -r ~/.aws/cli/cache`.
