# Lời giải — Break-fix Terraform #1 ("Terraform đòi phá hạ tầng đang chạy")

> Đề bài: [labs/break-fix-01/README.md](../labs/break-fix-01/README.md). Chỉ đọc khi đã làm xong hoặc đã kẹt quá 30 phút sau khi xem hết gợi ý.
> Mọi output dưới đây là **minh họa** — câu chữ chính xác phụ thuộc phiên bản Terraform/provider; hãy tìm **ý chính**.

## Mục lục

- [Tổng quan: setup.sh đã làm gì](#tổng-quan-setupsh-đã-làm-gì)
- [Lỗi 1 — Ràng buộc phiên bản provider bị đổi](#lỗi-1--ràng-buộc-phiên-bản-provider-bị-đổi)
- [Lỗi 2 — Một process giữ khóa state](#lỗi-2--một-process-giữ-khóa-state)
- [Lỗi 3 — Đổi tên resource không có moved](#lỗi-3--đổi-tên-resource-không-có-moved)
- [Lỗi 4 — Network bị gỡ khỏi state](#lỗi-4--network-bị-gỡ-khỏi-state)
- [Lỗi 5 — bf07-web-b bị tạo lại bằng tay ở cổng khác](#lỗi-5--bf07-web-b-bị-tạo-lại-bằng-tay-ở-cổng-khác)
- [Lỗi 6 — Volume backup bị xóa ngoài Terraform](#lỗi-6--volume-backup-bị-xóa-ngoài-terraform)
- [Nếu bạn đã apply ngay từ đầu](#nếu-bạn-đã-apply-ngay-từ-đầu)
- [Phương pháp chung khi gặp drift](#phương-pháp-chung-khi-gặp-drift)

---

## Tổng quan: setup.sh đã làm gì

Sau khi dựng trạng thái khỏe mạnh, script mô phỏng 6 việc "đồng nghiệp" làm trong tuần:

| # | Việc đã làm | Lớp bị lệch | Lộ ra ở |
|---|---|---|---|
| 1 | Đổi `version = "~> 4.6"` thành `"= 4.5.0"` trong `versions.tf` | Code ↔ lock file | Lỗi ngay khi `plan` (#7001) |
| 2 | Chạy nền `terraform apply` rồi bỏ quên ở câu hỏi yes/no (giữ khóa state) | Process ↔ state | Lỗi khi `plan` (#7001) |
| 3 | `sed` đổi `web_a` → `web_primary` trong code | Code ↔ state | Plan có `destroy` (#7002) |
| 4 | `terraform state rm docker_network.bf07` | State ↔ thực tế | Plan "tạo" network, apply lỗi trùng tên (#7003) |
| 5 | `docker rm -f bf07-web-b` rồi `docker run` lại ở cổng hotfix | Thực tế ↔ state | Plan "tạo" web_b, apply lỗi trùng tên (#7004) |
| 6 | `docker volume rm bf07-backup` | Thực tế ↔ state | Plan "tạo" volume (#7003) |

Lỗi 1 và 2 chặn mọi thứ — thứ tự gặp thật: **lỗi 2 (khóa state) trước**, gỡ xong mới thấy lỗi 1 (lock file). Lỗi 3–6 hiện **cùng lúc** trong một plan duy nhất. Kỹ năng chính của bài là tách plan đó thành từng nguyên nhân.

---

## Lỗi 1 — Ràng buộc phiên bản provider bị đổi

**Triệu chứng** (chạy thật với Terraform 1.17.1, 2026-10-31):

```text
│ Error: Inconsistent dependency lock file
│
│ The following dependency selections recorded in the lock file are
│ inconsistent with the current configuration:
│   - provider registry.terraform.io/kreuzwerker/docker: locked version selection 4.6.0 doesn't match the updated version constraints "4.5.0"
│
│ To update the locked dependency selections to match a changed configuration,
│ run:
│   terraform init -upgrade
```

Khi chạy thật, lỗi này chỉ lộ ra **sau** khi gỡ khóa state (lỗi 2): lúc state đang bị khóa, `plan` dừng ở `Error acquiring the state lock` trước. `terraform validate` thì **không** báo gì (vẫn `Success! The configuration is valid.`) — validate không đối chiếu lock file, nên đừng dùng nó để kết luận "provider ổn".

**Cách tìm:** đọc đúng thông báo; `grep -n version versions.tf`; `grep -A2 kreuzwerker .terraform.lock.hcl`.

**Nguyên nhân gốc:** `.terraform.lock.hcl` ghi lại **chính xác** phiên bản provider đã chọn lúc `init` (4.6.x). Code giờ đòi `= 4.5.0`. Terraform từ chối chạy thay vì âm thầm đổi provider.

**Cách sửa đúng:** đưa ràng buộc về `~> 4.6`. Lý do không chạy `terraform init -upgrade`:

- Nó **hạ** provider xuống 4.5.0 — một thay đổi riêng, cần test riêng, không nên lẫn vào việc "sửa drift".
- State hiện tại được ghi bởi provider 4.6.x. Hạ phiên bản provider có nguy cơ provider cũ không đọc được schema mới hơn trong state (🟨 chưa kiểm chứng với cặp phiên bản này — nhưng đó chính là lý do không nên làm).
- Ghi chú `# ghim theo production` không có bằng chứng — hỏi người đổi trước khi chấp nhận.

**Phòng tránh:** commit `.terraform.lock.hcl`; CI chạy `terraform init` **không** `-upgrade`, nên PR đổi phiên bản mà không cập nhật lock file sẽ đỏ ngay; nâng provider bằng PR riêng (Dependabot/Renovate hỗ trợ Terraform).

---

## Lỗi 2 — Một process giữ khóa state

**Triệu chứng** (chạy thật, 2026-10-31 — ID, Who, thời gian sẽ khác):

```text
│ Error: Error acquiring the state lock
│
│ Error message: resource temporarily unavailable
│ Lock Info:
│   ID:        e1c88d34-cede-c180-b5f3-0ed6a67ee704
│   Path:      terraform.tfstate
│   Operation: OperationTypeApply
│   Who:       phuong@LEGION
│   Version:   1.17.1
│   Created:   2026-10-31 09:05:26.625870892 +0000 UTC
```

**Cách tìm:**

```bash
ls -la                      # thấy .terraform.tfstate.lock.info
cat .terraform.tfstate.lock.info
pgrep -af terraform         # → 12345 terraform apply
ps -ef --forest | grep -B1 -A1 'terraform apply'   # cha của nó là "bash -c sleep 86400 | terraform apply"
```

**Nguyên nhân gốc:** `Operation: OperationTypeApply` — một lệnh `terraform apply` đã tính xong plan và đang **chờ câu trả lời** `yes`. Lệnh ghi state giữ khóa từ đầu tới cuối, kể cả lúc chờ người gõ. Ai đó bỏ quên nó (trong thực tế: một cửa sổ tmux, một terminal khác). Với local backend, khóa gắn với process đang mở file state; khóa đó **không gỡ được từ process khác** — chạy thử `terraform force-unlock -force <ID>` sẽ nhận `Failed to unlock state: LocalState not locked`.

> Ghi chú khi kiểm thử bài (Terraform 1.17.1): `terraform console` **không** giữ khóa local state, kể cả khi mở tương tác — đừng tin mọi câu "console giữ khóa" trên mạng mà không thử.

**Cách sửa:** xác nhận process đó chưa ghi gì (nó vẫn đang chờ câu trả lời, chưa có "yes" nào), rồi dừng nó:

```bash
kill 12345          # PID của terraform apply đang chờ
pgrep -af terraform # không còn gì
ls -la .terraform.tfstate.lock.info   # file đã biến mất
```

**Không làm:** `-lock=false` (hai process có thể cùng ghi state → hỏng state), xóa file `.lock.info` khi process còn sống (process vẫn giữ khóa thật, xóa file chỉ che triệu chứng).

**Phòng tránh:** đóng console khi xong (`exit`/Ctrl+D); state dùng chung đặt ở remote backend (S3 + `use_lockfile`, bài 03) và chỉ CI được apply. Với S3, khóa là object `<key>.tflock`; khi job CI chết giữa chừng, `terraform force-unlock <LOCK_ID>` là công cụ đúng — **sau khi** chắc chắn job kia đã dừng.

---

## Lỗi 3 — Đổi tên resource không có moved

**Triệu chứng** (minh họa, rút gọn):

```text
  # docker_container.web_a will be destroyed
  # (because docker_container.web_a is not in configuration)
  - resource "docker_container" "web_a" {
      - name = "bf07-web-a" -> null
  ...
  # docker_container.web_primary will be created
  + resource "docker_container" "web_primary" {
      + name = "bf07-web-a"
```

**Cách tìm:** `terraform state list` có `docker_container.web_a`; code (`grep -n resource main.tf`) có `web_primary`. Cùng `name = "bf07-web-a"`.

**Nguyên nhân gốc:** Terraform gắn tài nguyên với **địa chỉ trong code** (`docker_container.web_a`). Đổi địa chỉ = với Terraform, resource cũ "bị xóa khỏi code" và một resource mới "được thêm". Apply sẽ xóa container đang phục vụ rồi tạo lại → gián đoạn. Tệ hơn, hai thao tác không phụ thuộc nhau nên có thể chạy song song: tạo mới trước khi xóa cũ → lỗi trùng tên container.

**Cách sửa** (giữ tên mới, để lại dấu vết cho team) — thêm vào `main.tf`:

```hcl
moved {
  from = docker_container.web_a
  to   = docker_container.web_primary
}
```

Plan mong đợi:

```text
  # docker_container.web_a has moved to docker_container.web_primary
```

Không có `destroy` cho container này. Cách khác cũng đạt: đổi tên trong code về `web_a` (verify.sh chấp nhận cả hai). Sau khi mọi môi trường đã apply, block `moved` có thể giữ lại làm lịch sử hoặc xóa đi.

**Phòng tránh:** review plan trong PR; bất kỳ dòng `destroy` nào không có trong mô tả PR là cờ đỏ. Đổi tên/di chuyển vào module luôn kèm `moved`.

---

## Lỗi 4 — Network bị gỡ khỏi state

**Triệu chứng:** plan có `# docker_network.bf07 will be created`. Nếu đã thử apply (minh họa):

```text
│ Error: Unable to create network: Error response from daemon: network with name bf07-net already exists
```

**Cách tìm:** `docker network ls` có `bf07-net`; `terraform state list` **không** có `docker_network.bf07`. Containers trong state vẫn tham chiếu network theo **tên** nên không bị ảnh hưởng.

**Nguyên nhân gốc:** ai đó chạy `terraform state rm docker_network.bf07`. Lệnh này chỉ làm Terraform **quên** tài nguyên, không xóa nó. Terraform không còn biết network tồn tại, nên muốn tạo mới.

**Cách sửa:**

```bash
docker network inspect -f '{{.Id}}' bf07-net
```

```hcl
import {
  to = docker_network.bf07
  id = "<ID hex đầy đủ vừa lấy>"
}
```

Plan mong đợi: `docker_network.bf07 will be imported`, `0 to add` cho network. Apply → kiểm tra `terraform state list` → xóa block `import` (tùy chọn). Dùng **ID**, không dùng tên: tài liệu provider ghi import theo ID network.

**Phòng tránh:** `state rm` là thao tác nguy hiểm, nên chỉ làm sau khi ghi lại lý do; trên remote backend bật versioning (bài 03) để khôi phục state cũ khi cần.

---

## Lỗi 5 — bf07-web-b bị tạo lại bằng tay ở cổng khác

**Triệu chứng:** plan có `# docker_container.web_b will be created` (và trong phần "Objects have changed outside of Terraform" có thể thấy web_b đã bị xóa). Apply (minh họa):

```text
│ Error: Unable to create container: Error response from daemon: Conflict. The container name "/bf07-web-b" is already in use by container "c0ffee...". You have to remove (or rename) that container to be able to reuse that name.
```

**Cách tìm:**

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.CreatedAt}}' --filter name=bf07
curl -s 127.0.0.1:8093 | head -3     # "Welcome to nginx!" — không phải "bf07 OK"
```

`bf07-web-b` được tạo **sau** `bf07-web-a`, publish cổng 8093 thay vì 8092.

**Nguyên nhân gốc:** ai đó `docker rm -f bf07-web-b` rồi `docker run` lại với cổng khác. Container mới cùng tên nhưng **khác ID**. Khi refresh, provider tìm theo ID cũ, không thấy → coi như đã mất → muốn tạo lại → trùng tên với container bằng tay.

**Cách sửa** — hai hướng đều đạt, quan trọng là giải thích được:

1. **Import rồi thay thế** (giữ "dấu vết" trong plan). ⚠️ Bẫy đã gặp khi chạy thật: block `import` **chỉ có tác dụng với địa chỉ chưa có trong state**. `docker_container.web_b` vẫn nằm trong state (với ID của container cũ đã bị xóa) → Terraform **bỏ qua** block import, plan vẫn `will be created` và apply lỗi trùng tên. Phải cho state "quên" container cũ trước:

   ```bash
   terraform plan -refresh-only           # thấy web_b "has been deleted" ngoài Terraform
   terraform apply -refresh-only          # chấp nhận thực tế vào state (không đụng hạ tầng)
   terraform state list | grep web_b      # không còn
   ```

   Rồi mới thêm:

   ```hcl
   import {
     to = docker_container.web_b
     id = "<ID đầy đủ: docker inspect -f '{{.Id}}' bf07-web-b>"
   }
   ```

   Plan (chạy thật, 2026-10-31): `# docker_container.web_b must be replaced`, `# (imported from "8824d3ae…")`, `# Warning: this will destroy the imported resource`, `Plan: 1 to import, 1 to add, 0 to change, 1 to destroy.` Các dòng `# forces replacement` gồm `ports`, `upload`, `volumes`, `networks_advanced`, `image` (tên tag → `sha256:…`) và `network_mode = "bf07-net" -> "bridge"` — container bằng tay khác code ở rất nhiều chỗ, không chỉ cổng. Apply → container bằng tay bị thay bằng bản đúng code.
2. **Xóa bản bằng tay rồi apply:** `docker rm -f bf07-web-b` → plan chỉ còn `will be created` → apply.

Sau khi sửa: `curl 127.0.0.1:8092` trả `bf07 OK`, cổng 8093 đóng.

**Phòng tránh:** không ai sửa tài nguyên do Terraform quản lý bằng tay; "hotfix" phải qua code. Nếu bắt buộc sửa tay lúc khẩn cấp, ghi vào ticket và đưa vào code ngay sau đó.

---

## Lỗi 6 — Volume backup bị xóa ngoài Terraform

**Triệu chứng:** plan có `# docker_volume.backup will be created`; `docker volume ls` không có `bf07-backup`.

**Nguyên nhân gốc:** volume không gắn với container nào → dễ bị coi là rác. Từ Docker 23, `docker volume prune` mặc định chỉ xóa volume **vô danh**; muốn xóa cả volume có tên phải thêm `--all`/`-a` (🟨 kiểm tra lại bằng `docker volume prune --help` trên máy bạn). Ai đó đã dọn bằng `prune -a` hoặc `docker volume rm`.

**Cách sửa:** apply để tạo lại. **Ghi vào nhật ký:** dữ liệu cũ (nếu có) đã mất — Terraform tạo lại volume **rỗng**, nó không phải công cụ backup.

**Phòng tránh:** gắn label/tag cho tài nguyên do Terraform quản lý; dữ liệu quan trọng phải có backup riêng (Module 08); trên AWS, `prevent_destroy` trong `lifecycle` hoặc bật delete protection cho tài nguyên chứa dữ liệu.

---

## Nếu bạn đã apply ngay từ đầu

Sau khi qua được lỗi 1 và 2, `terraform apply -auto-approve` với plan chưa đọc sẽ:

| Tài nguyên | Kết quả |
|---|---|
| `web_a` → `web_primary` | Container cũ bị xóa (cổng 8091 **gián đoạn**); container mới có thể lỗi trùng tên nếu được tạo trước khi bản cũ bị xóa |
| `docker_network.bf07` | Lỗi `already exists` |
| `docker_container.web_b` | Lỗi trùng tên với container bằng tay |
| `docker_volume.backup` | Tạo lại thành công (rỗng) |

Apply dừng giữa chừng, để lại state "một nửa" — đúng loại sự cố mà luật "đọc plan trước" sinh ra để tránh. Nếu đã lỡ, vẫn sửa được bằng đúng các bước trên, nhưng tiêu chí 5 (container `web_a` không bị tạo lại) sẽ không đạt — ghi lại bài học đó.

---

## Phương pháp chung khi gặp drift

1. **Đừng apply.** Chạy `terraform plan` (và `terraform plan -refresh-only`) để thấy toàn cảnh.
2. Với **mỗi** dòng plan, hỏi: thực tế có thứ này không? state có không? code có không? Ba câu trả lời cho biết lớp nào lệch.

   | Code | State | Thực tế | Plan hiển thị | Thường do | Cách xử lý |
   |---|---|---|---|---|---|
   | có | có | không | create | Xóa tay | Apply (tạo lại) — kiểm tra dữ liệu |
   | có | không | có | create → lỗi trùng | `state rm`, hoặc tạo tay | `import` |
   | có (địa chỉ mới) | có (địa chỉ cũ) | có | destroy + create | Đổi tên trong code | `moved` |
   | có | có | khác code | update / replace | Sửa tay | Apply (code thắng) hoặc sửa code (nếu thay đổi tay là đúng) |
3. **Quyết định nguồn sự thật cho từng tài nguyên** — thường là code — rồi đưa hai lớp còn lại về khớp với nó.
4. Mỗi lần sửa: plan lại, chỉ apply khi plan đúng **từng dòng** như bạn dự đoán.
5. Kết thúc bằng `terraform plan -detailed-exitcode` → exit 0 (không thay đổi). Đây cũng là lệnh một job CI chạy định kỳ để phát hiện drift sớm.
