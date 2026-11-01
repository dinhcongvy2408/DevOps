# Checkpoint Giai đoạn 7 — Terraform & Ansible

> ⏱️ Tổng ~4,5 giờ (nên chia 2 buổi: A + B một buổi, C một buổi) · Làm vào cuối tuần 16
> Bao phủ: Module 07, bài [01](01-iac-concepts.md) → [05](05-ansible-fundamentals.md), [Break-fix Terraform #1](labs/break-fix-01/README.md)
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

> 💰 **Chi phí: 0 USD.** Cả ba phần chạy trên Docker trong máy bạn (provider `kreuzwerker/docker`, Ansible qua connection plugin `community.docker.docker`). Không phần nào đụng tới AWS. Lý do: dự án v4 đã cho bạn thực hành Terraform/Ansible trên AWS; checkpoint đo **hiểu biết**, và mức hiểu đó kiểm tra được hoàn toàn trên máy, làm lại bao nhiêu lần cũng không tốn tiền.

## Mục lục

- [Quy tắc](#quy-tắc)
- [Chuẩn bị](#chuẩn-bị)
- [Phần A — Lý thuyết (45 phút)](#phần-a--lý-thuyết-45-phút)
- [Phần B — Thực hành (120 phút)](#phần-b--thực-hành-120-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép:** tài liệu chính thức (developer.hashicorp.com, registry.terraform.io / docs của provider trên GitHub, docs.ansible.com, `ansible-doc <module>`), các bài trong Module 07, ghi chú của chính bạn.
3. Tự bấm giờ cho từng phần. Hết giờ thì dừng, ghi lại mình đang ở đâu.
4. Nộp bài: thư mục `~/devops-journey/week16/checkpoint/` gồm `part-a.md`, `part-b/` (toàn bộ code + output các lần chạy), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.

## Chuẩn bị

`[WSL]` — phải chạy được cả 4 lệnh:

```bash
terraform version                                    # 1.17.x trở lên
ansible --version                                    # ansible-core 2.20+ (Python 3.12 của Ubuntu 24.04)
ansible-galaxy collection list community.docker      # đã cài collection
docker ps                                            # Docker Desktop đã bật WSL integration
```

Thiếu collection: `ansible-galaxy collection install community.docker`. Không chạy được `docker ps` trong WSL: xem [Docker bài 01](../04-DOCKER/01-vm-vs-container-architecture.md) (mục lỗi thường gặp).

---

## Phần A — Lý thuyết (45 phút)

Trả lời bằng lời của bạn, 3–8 câu mỗi câu. Giải thích **bản chất** và **vì sao**, không chép định nghĩa.

### Terraform: state và vòng đời

1. **State** chứa gì và vì sao Terraform cần nó (Terraform không thể "hỏi AWS" thay vì giữ state được sao)? Vì sao không được commit `terraform.tfstate` lên Git, còn `.terraform.lock.hcl` thì **phải** commit?
2. Giải thích từng ký hiệu trong plan: `+`, `-`, `~`, `-/+`, `+/-`, `<=`. Dòng `# forces replacement` nghĩa là gì? Cho một ví dụ trên AWS mà một thay đổi nhỏ trong code dẫn tới **replace** một EC2 và hậu quả của nó với taskhub.
3. **State locking** giải quyết vấn đề gì? Với backend S3 có `use_lockfile = true`, khóa nằm ở đâu? Khi nào được phép chạy `terraform force-unlock`, khi nào tuyệt đối không?
4. **Drift** là gì? Kể 3 cách drift xảy ra trong team thật. `terraform plan -refresh-only` khác `terraform plan` thế nào, và bạn dùng nó khi nào?
5. So sánh `import {}` block, `moved {}` block và `terraform state rm`: mỗi cái thay đổi **code**, **state** hay **hạ tầng**? Cho một tình huống phải dùng từng cái. *(bắt buộc đúng)*

### Terraform: thiết kế code

6. `count` và `for_each` khác nhau thế nào về **địa chỉ** tài nguyên trong state? Vì sao xóa phần tử **đầu** của một list dùng với `count` có thể phá hủy và tạo lại những tài nguyên không liên quan?
7. **Module** là gì? Một module tốt nên nhận gì qua `variable` và trả gì qua `output`? Vì sao không nên đặt `provider` và `backend` bên trong module con? Ở v4, `envs/dev` dùng module `network` và `app_server` như thế nào?
8. Mật khẩu PostgreSQL của taskhub được tạo/lưu ra sao ở v4? Vì sao đánh dấu `sensitive = true` cho output **không** làm cho giá trị biến khỏi state? **Write-only argument** (`value_wo` + `value_wo_version`) và **ephemeral** giải quyết điều gì mà `sensitive` không giải quyết được? *(bắt buộc đúng)*
9. Vì sao state của dự án đặt ở **S3** mà không để file local? Bucket state cần những thiết lập gì (versioning, Block Public Access, mã hóa, chính sách TLS) và mỗi thiết lập chống lại rủi ro gì? Bucket state được tạo bằng gì (vấn đề "con gà và quả trứng")?

### Ansible

10. **Idempotent** nghĩa là gì? Vì sao `ansible.builtin.shell: echo "x" >> file` không idempotent, còn `ansible.builtin.copy`/`lineinfile` thì có? Bạn **chứng minh** một playbook idempotent bằng cách nào? *(bắt buộc đúng)*
11. **Handler** chạy khi nào? Một task có `notify` nhưng handler không chạy — kể 3 nguyên nhân có thể. Vì sao sửa file cấu hình nginx mà không reload thì "chạy Ansible xanh nhưng hệ thống không đổi"?
12. **Inventory** tĩnh và **inventory động** (`amazon.aws.aws_ec2`) khác nhau thế nào? Một play có `hosts: webservers` nhưng inventory không có nhóm đó — Ansible báo lỗi hay không? Vì sao đây là lỗi nguy hiểm?
13. Ở v4, Ansible nói chuyện với EC2 **không qua SSH** (cổng 22 đóng). Nó đi bằng đường nào, cần những gì trên máy điều khiển, trên EC2 và trên AWS (gợi ý: plugin, S3, IAM)?

### Phân vai

14. Terraform và Ansible chồng lấn nhau (Terraform có `user_data`, Ansible có module tạo EC2). Ở taskhub v4, ranh giới giữa hai công cụ được đặt ở đâu, và vì sao? Nêu một ví dụ việc **không nên** làm bằng Terraform và một việc **không nên** làm bằng Ansible.

---

## Phần B — Thực hành (120 phút)

### Nhiệm vụ: "Một lệnh dựng, một lệnh xóa" — Terraform tạo máy, Ansible cài máy

Nhiệm vụ này **mới**: lab và v4 chưa từng cho Terraform **sinh inventory** cho Ansible, cũng chưa từng dùng `for_each` với **map**. Vì sao chọn chạy cục bộ: nó tái hiện đúng quy trình v4 (Terraform dựng → bàn giao địa chỉ máy cho Ansible → Ansible cấu hình) mà không tốn tiền, và chấm được tự động.

Làm trong thư mục mới `~/devops-lab/07-terraform/ck07b` (tự viết mọi file từ đầu).

**Yêu cầu Terraform:**

| # | Yêu cầu |
|---|---|
| R1 | Provider `kreuzwerker/docker` (`~> 4.6`), `required_version = "~> 1.17"`, có `.terraform.lock.hcl` |
| R2 | Network `ck07b-net` |
| R3 | Biến `nodes` kiểu `map(number)`, mặc định `{ app1 = 8381, app2 = 8382 }`. Mỗi phần tử → một container `ck07b-<key>` từ `ubuntu:24.04` (`command = ["sleep", "infinity"]`), publish `127.0.0.1:<value>` → cổng 80 trong container. Dùng **`for_each`**, không dùng `count` |
| R4 | Terraform **sinh file** `inventory.ini` (resource `local_file` + hàm `templatefile`) với nhóm `[app]` chứa tên các container và biến kết nối `ansible_connection=community.docker.docker`. Thêm một node vào map → inventory tự có node đó |
| R5 | Output `urls`: map từ tên node tới URL `http://127.0.0.1:<port>` |

**Yêu cầu Ansible:**

| # | Yêu cầu |
|---|---|
| R6 | Play đầu cài `python3` bằng module `raw` khi chưa có, và **không báo `changed`** khi python3 đã có |
| R7 | Play cho nhóm `app`: cài nginx, trang chủ chứa `ck07b <inventory_hostname> <app_color>` (biến `app_color` mặc định `blue`, đặt trong `group_vars/app.yml`), khởi động nginx (container không có systemd) |
| R8 | Đổi `app_color` → `green` rồi chạy lại: trang chủ đổi **mà không** khởi động lại container. Cấu hình nginx thay đổi phải đi qua **handler** |
| R9 | Chạy playbook lần 2 liên tiếp: `changed=0` cho mọi host |

**Yêu cầu tự động hóa:**

| # | Yêu cầu |
|---|---|
| R10 | `Makefile` với `make up` (terraform apply + ansible-playbook), `make check` (curl mọi URL từ `terraform output -json urls`), `make down` (terraform destroy, xóa inventory sinh ra) |
| R11 | Từ thư mục trống (sau `make down`), `make up && make check` thành công **trong một lần chạy** |

**Kiểm thử phải ghi vào `part-b.md`** (dán output thật):

1. `make up` lần đầu — recap Ansible.
2. `make check` — cả hai URL trả nội dung đúng.
3. `make up` lần 2 — recap `changed=0`.
4. Đổi `app_color=green` (cách bạn chọn: `-e`, sửa group_vars…), chạy lại — recap cho thấy handler/task nào chạy; `make check` thấy `green`.
5. Thêm `app3 = 8383` vào map, `make up` — plan **không đụng** container app1/app2 (chỉ tạo app3 và thay file inventory), inventory có `ck07b-app3`.
6. `make down` — `docker ps -a --filter name=ck07b-` rỗng, `docker network ls --filter name=ck07b` rỗng.

---

## Phần C — Break-fix (90 phút)

### Khởi tạo

```bash
mkdir -p ~/devops-lab/07-terraform/tools-ck && cd ~/devops-lab/07-terraform/tools-ck
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/07-TERRAFORM-ANSIBLE/labs/checkpoint/setup.sh .
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/07-TERRAFORM-ANSIBLE/labs/checkpoint/verify.sh .
sed -i 's/\r$//' setup.sh verify.sh
bash setup.sh                    # cổng 8280 bị chiếm → CK07_PORT=9280 bash setup.sh
```

Script dựng hệ thống `ck07` (3 container Ubuntu do Terraform quản lý, nginx đã chạy sẵn trên node `web` từ "sprint trước"), viết sẵn playbook Ansible của đồng nghiệp, rồi áp thay đổi của sprint này. **Không đọc `setup.sh` và `verify.sh` trước khi nộp bài.**

### Bối cảnh

Đồng nghiệp bàn giao trước khi nghỉ: *"Sprint này mình bỏ node `api`, thêm output mật khẩu DB cho tiện, và viết playbook đổi nginx sang cổng 8080 cho khớp cổng publish. Chưa kịp chạy thử, nhờ bạn apply giúp."*

### Các ticket

| Ticket | Triệu chứng được báo | Kết quả mong đợi |
|---|---|---|
| 🎫 #7101 | `terraform plan` không ra kế hoạch, báo lỗi đỏ | Plan chạy được, mật khẩu **không** hiện ra màn hình |
| 🎫 #7102 | (sau #7101) Plan muốn **thay thế** `ck07-worker` và `ck07-web`, dù chỉ bỏ `api` | Chỉ `ck07-api` bị xóa. `ck07-worker`, `ck07-web` giữ nguyên **cùng ID container**. Thêm/bớt node sau này không bao giờ làm node khác bị tạo lại |
| 🎫 #7103 | `ansible-playbook site.yml` xanh, nhưng `curl 127.0.0.1:8280` không ra trang. Recap cho thấy `ck07-web` hầu như không được đụng tới | Playbook thực sự cấu hình `ck07-web`; `curl` trả `ck07 OK from ck07-web` |
| 🎫 #7104 | Chạy playbook lần 2 thì có task báo `changed`, đến lần 3 thì nginx báo lỗi khi reload | Chạy lại bao nhiêu lần cũng `changed=0`, `nginx -t` luôn thành công |

### Luật chơi

- Không sửa tay `terraform.tfstate`, không `-lock=false`, không xóa/tạo lại `ck07-worker` hay `ck07-web` (kể cả bằng `docker rm`).
- Không cấu hình nginx bằng tay trong container (`docker exec ... vi`) — mọi thay đổi cấu hình đi qua Ansible. Được dùng `docker exec` để **xem**, và được chạy một lệnh ad-hoc của Ansible nếu bạn giải thích được vì sao cần.
- Nhật ký cho **từng** ticket theo mẫu ở [Break-fix Terraform #1](labs/break-fix-01/README.md#8-sản-phẩm-phải-nộp) vào `part-c.md`.

### Kiểm tra

```bash
cd ~/devops-lab/07-terraform/ck07
bash ~/devops-lab/07-terraform/tools-ck/verify.sh      # mục 5 chạy playbook một lần để đo tính idempotent
```

### Dọn dẹp (bắt buộc)

```bash
cd ~/devops-lab/07-terraform/ck07 && terraform destroy -auto-approve; cd ..
docker rm -f $(docker ps -aq --filter 'name=^ck07-') 2>/dev/null || true   # ⚠️ chỉ container ck07-*
docker network rm ck07-net 2>/dev/null || true
rm -rf ck07 .ck07
```

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 11/14 câu đúng **bản chất** (tự chấm theo lời giải, trung thực). Câu **5, 8 và 10 bắt buộc đúng** | 30% |
| B | Đạt R1–R11 và đủ 6 kiểm thử có output thật, trong 120 phút | 35% |
| C | `verify.sh` đạt **7/7** trong 90 phút, nhật ký nêu **cách tìm ra** từng lỗi (lệnh nào, thấy gì) và giải thích vì sao cách sửa không gây tác dụng phụ | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần → tick vào checklist [Module 07](README.md) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md).

---

## Nếu chưa đạt

Không chuyển sang Module 08 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ)):

| Sai ở | Ôn lại |
|---|---|
| Câu A1, A2, A6 | [Bài 02 — Terraform cơ bản](02-terraform-basics.md) |
| Câu A3, A4, A5, A9, ticket #7101 | [Bài 03 — State và backend](03-terraform-state-backend.md), làm lại [Break-fix Terraform #1](labs/break-fix-01/README.md) |
| Câu A6, A7, R3–R5, ticket #7102 | [Bài 04 — Module và môi trường](04-terraform-modules-environments.md) |
| Câu A8 | [Bài 03](03-terraform-state-backend.md) (secret trong state), [dự án v4](../12-PRACTICAL-PROJECT/milestones/v4-terraform.md) |
| Câu A10–A13, R6–R9, ticket #7103, #7104 | [Bài 05 — Ansible](05-ansible-fundamentals.md) |
| Câu A14 | [Bài 01 — Khái niệm IaC](01-iac-concepts.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt. Phần C: dọn dẹp rồi chạy lại `setup.sh` — lỗi được cài lại y hệt.
