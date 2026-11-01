# Break-fix Terraform #1 — "Terraform đòi phá hạ tầng đang chạy"

> ⏱️ 90–150 phút · Chi phí: **0 USD** (chỉ dùng Docker trên máy bạn) · Môi trường: `[WSL]` + Docker Desktop (đã bật WSL integration)
> Kiến thức cần có: Module 07 bài [02](../../02-terraform-basics.md), [03](../../03-terraform-state-backend.md), [04](../../04-terraform-modules-environments.md) · [Lab 01](../lab-01-terraform-local-docker.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã xong, hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Vì sao bài này chạy bằng Docker mà không phải AWS](#2-vì-sao-bài-này-chạy-bằng-docker-mà-không-phải-aws)
- [3. Khởi tạo môi trường](#3-khởi-tạo-môi-trường)
- [4. Công cụ bạn được dùng](#4-công-cụ-bạn-được-dùng)
- [5. Các ticket](#5-các-ticket)
- [6. Luật chơi](#6-luật-chơi)
- [7. Tiêu chí hoàn thành](#7-tiêu-chí-hoàn-thành)
- [8. Sản phẩm phải nộp](#8-sản-phẩm-phải-nộp)
- [9. Gợi ý](#9-gợi-ý)
- [10. Liên hệ với AWS](#10-liên-hệ-với-aws)
- [11. Dọn dẹp](#11-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Bối cảnh

Hệ thống `bf07` gồm 2 web nginx (`bf07-web-a`, `bf07-web-b`) chạy sau 2 cổng trên máy, một network, hai volume và một file nội dung — **toàn bộ do Terraform quản lý**. Code nằm trong thư mục `bf07`, state là file `terraform.tfstate` ngay cạnh code (local backend).

Bạn vừa đi phép một tuần về. Trong tuần, vài đồng nghiệp đã "xử lý nhanh" vài việc mà **không ai ghi lại**. Trưởng nhóm nhắn:

> *"Chạy `terraform plan` giúp mình trước khi merge thay đổi tiếp theo nhé. Plan phải sạch, và tuyệt đối không được làm web gián đoạn."*

Đây là tình huống có thật ở mọi team dùng Terraform: **thực tế (hạ tầng đang chạy) và mô tả (code + state) đã lệch nhau**. Gọi chung là **drift**. Kỹ năng cần luyện không phải là gõ lệnh nhanh, mà là **đọc plan** và quyết định đúng: hạ tầng hay code mới là thứ đúng.

---

## 2. Vì sao bài này chạy bằng Docker mà không phải AWS

- **Miễn phí và làm lại được vô hạn.** Mỗi lần làm hỏng thêm, bạn chỉ cần dọn dẹp rồi chạy lại `setup.sh`.
- **Cơ chế giống hệt.** Terraform không phân biệt "container trên máy" hay "EC2 trên AWS": cùng `plan`, `state`, `import`, `moved`, cùng loại lỗi. Bảng ở [mục 10](#10-liên-hệ-với-aws) chỉ ra từng lỗi trong bài sẽ trông thế nào trên AWS.
- **Không sợ để quên tài nguyên tính tiền.**

---

## 3. Khởi tạo môi trường

**Điều kiện:**

- Đã cài Terraform (bài 02). `terraform version` hiện 1.17.x trở lên.
- `docker ps` chạy được **trong WSL**. Nếu báo `Cannot connect to the Docker daemon`, bật WSL integration theo [Docker bài 01](../../../04-DOCKER/01-vm-vs-container-architecture.md).
- Cổng 8091, 8092, 8093 còn trống (`ss -ltn | grep -E ':809[123]'` không in gì). Nếu bị chiếm, đặt cổng khác trước khi chạy: `export BF07_PORT_A=9091 BF07_PORT_B=9092 BF07_PORT_HOTFIX=9093`.

`[WSL]` — copy script về và chạy:

```bash
mkdir -p ~/devops-lab/07-terraform/tools && cd ~/devops-lab/07-terraform/tools
# Đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/07-TERRAFORM-ANSIBLE/labs/break-fix-01/setup.sh .
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/07-TERRAFORM-ANSIBLE/labs/break-fix-01/verify.sh .
sed -i 's/\r$//' setup.sh verify.sh     # phòng file bị đổi sang CRLF khi copy từ Windows
bash setup.sh
```

Script tạo thư mục `~/devops-lab/07-terraform/bf07`, chạy `terraform init` + `apply` để dựng trạng thái khỏe mạnh, kiểm tra cả hai cổng trả `bf07 OK`, rồi mô phỏng "một tuần vắng mặt". Nó **từ chối chạy** nếu thư mục, container, network hay volume `bf07-*` đã tồn tại.

> 🚫 **Đừng đọc phần cuối của `setup.sh`** trước khi làm xong. Mọi thứ đều tìm ra được bằng công cụ thường ngày — đó mới là kỹ năng bạn luyện.

Kiểm tra tiến độ bất kỳ lúc nào (chỉ đọc, không sửa gì):

```bash
cd ~/devops-lab/07-terraform/bf07
bash ~/devops-lab/07-terraform/tools/verify.sh
```

---

## 4. Công cụ bạn được dùng

| Mục đích | Lệnh |
|---|---|
| Xem Terraform muốn làm gì | `terraform plan` (đọc **từng dòng**, đặc biệt các ký hiệu `+`, `-`, `~`, `-/+`) |
| Chỉ xem phần "thực tế đã đổi" | `terraform plan -refresh-only` |
| Liệt kê / xem chi tiết state | `terraform state list`, `terraform state show <địa-chỉ>` |
| Kiểm tra cấu hình và provider | `terraform validate`, `terraform providers`, `cat .terraform.lock.hcl` |
| Xem thực tế phía Docker | `docker ps -a`, `docker inspect <tên>`, `docker network ls`, `docker volume ls` |
| Lấy ID đầy đủ | `docker inspect -f '{{.Id}}' <tên>`, `docker network inspect -f '{{.Id}}' <tên>` |
| Tìm process | `ps aux`, `ps -ef --forest`, `pgrep -af terraform` |
| Lịch sử lệnh của chính bạn | `history` |

**Được phép:** sửa file `.tf`, thêm block `import {}` / `moved {}`, chạy mọi lệnh `terraform` và `docker`, dừng process.

**Không được phép:** sửa tay file `terraform.tfstate`, xóa `terraform.tfstate`, dùng `-lock=false`, xóa và tạo lại `bf07-web-a`.

---

## 5. Các ticket

### 🎫 Ticket #7001 — P1 — `terraform plan` không chạy được

> **Người báo:** Trưởng nhóm
> **Mô tả:** "Mình chạy `terraform plan` thì báo lỗi ngay, chưa kịp ra kế hoạch gì."
> **Kết quả mong đợi:** `terraform plan` chạy tới cuối và in ra kế hoạch.
> **Ghi chú:** Có **hai** nguyên nhân độc lập, sửa xong cái này mới thấy cái kia. Một cái nằm trong code, một cái **không** nằm trong code.

### 🎫 Ticket #7002 — P1 — Plan đòi xóa web đang chạy

> **Người báo:** Trưởng nhóm (sau khi ticket #7001 xong)
> **Mô tả:** "Plan có dòng `destroy`. Mình không yêu cầu xóa gì cả. Ai đó đã sửa code?"
> **Kết quả mong đợi:** Plan không còn dòng `destroy` nào đụng tới `bf07-web-a`. Container `bf07-web-a` **giữ nguyên** (cùng ID container) suốt quá trình sửa.

### 🎫 Ticket #7003 — P2 — Plan đòi tạo những thứ đã có

> **Người báo:** Trưởng nhóm
> **Mô tả:** "Plan bảo sẽ **tạo** network và vài thứ khác. Nhưng `docker network ls` vẫn thấy `bf07-net` mà? Mình thử apply một lần thì lỗi đỏ, không dám thử nữa."
> **Kết quả mong đợi:** Mọi tài nguyên đang chạy được Terraform **quản lý lại**, không bị tạo trùng, không lỗi khi apply.
> **Ghi chú:** Mỗi thứ "đòi tạo" có một nguyên nhân **khác nhau** và cách xử lý khác nhau. Có thứ phải đưa lại vào state, có thứ chỉ cần apply.

### 🎫 Ticket #7004 — P2 — Cổng lạ đang mở

> **Người báo:** Bảo mật
> **Mô tả:** "Quét máy thấy nginx trả lời ở một cổng không có trong code. `bf07-web-b` trả về trang 'Welcome to nginx!' chứ không phải nội dung của mình."
> **Kết quả mong đợi:** `bf07-web-b` chạy **đúng như code** (cổng chuẩn, nội dung `bf07 OK`), cổng lạ đóng, và Terraform quản lý nó.

---

## 6. Luật chơi

1. **Không bao giờ `apply` khi chưa giải thích được từng dòng của plan.** Viết lời giải thích vào nhật ký trước.
2. Mỗi lần sửa: sửa → `terraform plan` → đọc → ghi nhật ký → mới `apply` nếu plan đúng ý.
3. Gặp lỗi, đọc dòng `Error:` **đầu tiên** và toàn bộ khối giải thích bên dưới — Terraform thường viết sẵn gợi ý sửa.
4. Ghi mọi bước vào `troubleshooting-journal.md` theo [mẫu](../../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 7. Tiêu chí hoàn thành

`verify.sh` báo **8/8 đạt**:

1. Không còn ai giữ khóa state.
2. Ràng buộc phiên bản provider khớp lock file. (Lưu ý: `terraform validate` **không** bắt được lỗi này — nó vẫn báo `Success!`; chỉ `init`/`plan`/`apply` mới kiểm tra lock file.)
3. `terraform plan` báo **No changes**.
4. State có đủ 7 địa chỉ, không trùng.
5. `bf07-web-a` vẫn là container ban đầu (không bị tạo lại).
6. Hai cổng chuẩn đều trả `bf07 OK` (tính là 2 mục).
7. Chỉ còn hai container `bf07-*`, cổng "hotfix" đã đóng.

---

## 8. Sản phẩm phải nộp

Một mục trong `troubleshooting-journal.md` cho **mỗi** nguyên nhân bạn tìm ra (dự kiến 6), mỗi mục gồm:

- **Triệu chứng:** dòng lỗi hoặc dòng plan, chép nguyên văn.
- **Giả thuyết** bạn đặt ra, và **cách kiểm chứng** (lệnh nào, thấy gì).
- **Nguyên nhân gốc** — ai/điều gì đã làm lệch state, code và thực tế.
- **Cách sửa** bạn chọn và **vì sao** chọn cách đó thay vì cách khác.
- **Cách phòng tránh** trong một team thật.

Cuối cùng, trả lời ngắn: *"Nếu ở ngày đầu bạn chạy `terraform apply -auto-approve` ngay, chuyện gì sẽ xảy ra với từng tài nguyên?"*

---

## 9. Gợi ý

Mở từng cấp **chỉ khi** đã thử ít nhất 15 phút ở cấp trước.

### Ticket #7001

<details><summary>Gợi ý cấp 1</summary>

Đọc kỹ chữ đầu tiên sau `Error:`. Lỗi thứ nhất bạn gặp nói về **lock của state** (ai đó đang giữ quyền ghi state). Sửa xong mới lộ lỗi thứ hai: về **provider** và một file Terraform tự sinh ra lúc `init` — cũng có chữ "lock" nhưng là *lock file* của provider, một thứ hoàn toàn khác.

</details>

<details><summary>Gợi ý cấp 2</summary>

- Lỗi provider: so sánh dòng `version = ...` trong `versions.tf` với phiên bản ghi trong `.terraform.lock.hcl`. Ai đổi, đổi thành gì? Bạn có **muốn** đổi phiên bản provider trong một lần "chỉ sửa drift" không?
- Lỗi state lock: đọc khối `Lock Info` — trường `Who`, `Created`, `Operation`. Local backend khóa state bằng cách **một process đang mở** file state. Process đó là gì, vẫn còn sống không?

</details>

<details><summary>Gợi ý cấp 3</summary>

- Đưa ràng buộc phiên bản về như trước khi bị sửa (xem thư mục `.terraform/providers/` hoặc lock file để biết bản đang dùng). Đừng chạy `init -upgrade` để "cho xong" — đó là đổi phiên bản provider, một thay đổi riêng cần test riêng.
- `pgrep -af terraform` hoặc `ps -ef --forest | grep -B2 -A2 terraform`. Một `terraform apply` bị bỏ quên ở câu hỏi `Enter a value:` vẫn giữ khóa state suốt thời gian chờ. Khóa của local state **không** gỡ được từ process khác — thử `terraform force-unlock <ID>` sẽ thấy `Failed to unlock state: LocalState not locked` — nên hãy dừng chính process đó (`kill <PID>`), sau khi chắc chắn nó chưa bắt đầu ghi (vẫn đang chờ câu trả lời).

</details>

### Ticket #7002

<details><summary>Gợi ý cấp 1</summary>

Plan muốn **xóa** một địa chỉ và **tạo** một địa chỉ khác, nhưng tên container (`name = ...`) của hai địa chỉ giống hệt nhau. Terraform theo dõi tài nguyên theo **địa chỉ trong code**, không theo tên thật.

</details>

<details><summary>Gợi ý cấp 2</summary>

Trong state, container này nằm ở địa chỉ nào (`terraform state list`)? Trong code, nó tên là gì? Có ai đó đã "dọn code cho đẹp" bằng cách đổi tên resource.

</details>

<details><summary>Gợi ý cấp 3</summary>

Có hai cách giữ nguyên container: đổi tên trong code về như cũ, **hoặc** giữ tên mới và khai báo cho Terraform biết đây là đổi tên (một block chuyên cho việc này, xem bài 04). Cách thứ hai để lại dấu vết trong code cho cả team và chạy được qua CI. Kiểm tra lại bằng `terraform plan`: dòng cho container này phải là `has moved to`, không phải `destroy`.

</details>

### Ticket #7003

<details><summary>Gợi ý cấp 1</summary>

Với **mỗi** dòng `will be created`, hỏi: thứ đó **có thật đang tồn tại** trong Docker không (`docker network ls`, `docker volume ls`)? Nếu có mà Terraform không biết → state đã mất dấu nó. Nếu không có → ai đó đã xóa nó ngoài Terraform.

</details>

<details><summary>Gợi ý cấp 2</summary>

- Network: đang tồn tại, nhưng **không có** trong `terraform state list`. Ai đó đã gỡ nó khỏi state. Apply sẽ cố tạo network trùng tên → Docker từ chối.
- Volume backup: **không** còn tồn tại. "Không có container nào dùng" là lý do phổ biến khiến ai đó dọn nó (ví dụ `docker volume prune -a`).

</details>

<details><summary>Gợi ý cấp 3</summary>

- Network: dùng block `import { to = ..., id = "<ID đầy đủ>" }` (bài 03). ID của docker network là chuỗi hex dài lấy bằng `docker network inspect -f '{{.Id}}' bf07-net`, **không phải** tên. Chạy plan, xác nhận dòng của network là `will be imported` và không có thay đổi nào khác cho nó, rồi apply. Sau khi apply xong có thể xóa block `import`.
- Volume: chỉ cần apply để tạo lại — nhưng ghi vào nhật ký: dữ liệu trong volume cũ (nếu có) **đã mất**, Terraform không cứu được dữ liệu.

</details>

### Ticket #7004

<details><summary>Gợi ý cấp 1</summary>

`docker ps` và xem cột `PORTS` + `CREATED` của `bf07-web-b`. So với `bf07-web-a`. So ID container hiện tại với ID trong state của Terraform (`terraform state show docker_container.web_b` — nếu nó còn trong state).

</details>

<details><summary>Gợi ý cấp 2</summary>

Container cùng tên nhưng **khác ID** = đã bị xóa và tạo lại **bằng tay** (ai đó "hotfix" bằng `docker run`). Terraform tìm container theo ID cũ, không thấy, nên coi như nó đã mất và muốn tạo mới — nhưng tên đã bị container bằng tay chiếm.

</details>

<details><summary>Gợi ý cấp 3</summary>

Hai hướng, đều đúng, hãy chọn và giải thích:

1. **Import** container bằng tay vào state (`import` block với ID container đầy đủ), rồi plan. Nếu plan vẫn ghi `will be created` (không có `will be imported`): block import đã bị **bỏ qua** vì địa chỉ `docker_container.web_b` vẫn còn trong state với ID cũ — import chỉ áp dụng cho địa chỉ **chưa** có trong state. Cho state "quên" container cũ bằng `terraform apply -refresh-only` trước, rồi plan lại. Plan đúng sẽ báo `must be replaced` vì cổng và nội dung khác code (dòng `# forces replacement`). Apply → Terraform thay nó bằng bản đúng code.
2. **Xóa** container bằng tay (`docker rm -f`), rồi apply để Terraform tạo bản đúng code.

Trong cả hai, ghi rõ: code là nguồn sự thật, thay đổi bằng tay bị **loại bỏ** — nếu "hotfix" đó có lý do thật, phải đưa vào code qua PR.

</details>

---

## 10. Liên hệ với AWS

| Trong bài (Docker) | Trên AWS sẽ trông như |
|---|---|
| Đồng nghiệp đổi ràng buộc `version` của provider | Ai đó đổi `version` của `hashicorp/aws` trong PR "nhỏ" → CI báo `Inconsistent dependency lock file` |
| `terraform apply` bỏ quên ở câu hỏi yes/no giữ khóa local state | Một job CI bị hủy giữa chừng để lại file `.tflock` trên S3 (`use_lockfile = true`) → mọi plan sau báo `Error acquiring the state lock`. Với S3, `terraform force-unlock <LOCK_ID>` **là** công cụ đúng — sau khi chắc chắn job kia đã chết |
| Đổi tên resource không có `moved` | Đổi `aws_instance.app` thành `aws_instance.web` → plan đòi **terminate EC2** và tạo máy mới: mất IP public, mất dữ liệu trên ổ gốc |
| `terraform state rm` network | Ai đó `state rm` một VPC/S3 bucket để "gỡ lỗi" → plan đòi tạo lại → `BucketAlreadyOwnedByYou` / tạo VPC trùng CIDR. Sửa bằng `import` |
| `docker volume rm` volume backup | Xóa EBS volume/S3 bucket trên console → plan tạo lại **rỗng**. Terraform không khôi phục dữ liệu — cần backup (Module 08) |
| Container "hotfix" bằng `docker run` | Sửa Security Group trên console để mở cổng "tạm" → `terraform plan -refresh-only` thấy khác biệt; apply tiếp theo **xóa mất** luật bằng tay, hoặc tệ hơn, không ai biết cổng đó đang mở |

Bài học chung: trên AWS, `terraform plan -refresh-only` (hoặc job CI chạy plan định kỳ) là cách phát hiện drift **trước** khi nó gây sự cố.

---

## 11. Dọn dẹp

⚠️ Xóa toàn bộ môi trường bài này (không đụng tới container nào khác):

```bash
cd ~/devops-lab/07-terraform
# 1. Dừng process giữ khóa nếu vẫn còn (bỏ qua nếu báo "No such process")
kill -- -"$(cat .bf07/holder.pid)" 2>/dev/null || true   # dấu "-" trước PID: giết cả nhóm process (bash + sleep + terraform) mà setup.sh tạo bằng setsid
# 2. Terraform xóa những gì nó quản lý (image nginx được giữ lại vì keep_locally = true)
cd bf07 && terraform destroy -auto-approve; cd ..
# 3. Xóa những thứ còn sót do làm dở (container/network/volume bf07-*), rồi xóa thư mục
docker rm -f $(docker ps -aq --filter 'name=^bf07-') 2>/dev/null || true
docker network rm bf07-net 2>/dev/null || true
docker volume rm bf07-shared bf07-backup 2>/dev/null || true
rm -rf bf07 .bf07
```

Kiểm tra sạch: `docker ps -a --filter name=bf07-`, `docker network ls --filter name=bf07`, `docker volume ls --filter name=bf07` đều không in dòng nào.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Terraform — State locking](https://developer.hashicorp.com/terraform/language/state/locking) | Thao tác nào khóa state, cảnh báo khi force-unlock | 2026-10-31 |
| [Terraform — `force-unlock`](https://developer.hashicorp.com/terraform/cli/commands/force-unlock) | "Local state files cannot be unlocked by another process" | 2026-10-31 |
| [Terraform — State locking](https://developer.hashicorp.com/terraform/language/state/locking) | Lệnh ghi state giữ khóa; `force-unlock` | 2026-10-31 |
| [Terraform — `moved` block](https://developer.hashicorp.com/terraform/language/block/moved) | Đổi địa chỉ resource không phá tài nguyên | 2026-10-31 |
| [Terraform — `import` block](https://developer.hashicorp.com/terraform/language/block/import) | Đưa tài nguyên có sẵn vào state | 2026-10-31 |
| [kreuzwerker/docker — `docker_container`](https://github.com/kreuzwerker/terraform-provider-docker/blob/master/docs/resources/container.md) | Thuộc tính container, ID dùng để import | 2026-10-31 |
| [kreuzwerker/docker — `docker_network`](https://github.com/kreuzwerker/terraform-provider-docker/blob/master/docs/resources/network.md) | Import network bằng ID đầy đủ | 2026-10-31 |
