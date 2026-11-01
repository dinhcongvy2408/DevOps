# 🎯 Bài thi mốc 3 tháng (cuối tuần 12)

> Kiểm tra tổng hợp Linux · Networking · Git · Docker · CI · AWS sau 12 tuần.
> Đề bài theo [kế hoạch tuần §4](weekly-study-plan.md#4-lịch-kiểm-tra-định-kỳ): **dựng một máy chủ mới từ đầu và triển khai `taskhub` trong 3 giờ**, rồi giải thích được mình đã làm gì.
> Làm sau khi xong [milestone v2](../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md). Thời lượng: 3 giờ thực hành + 45 phút trình bày miệng + 15 phút tự chấm.

## Mục lục

- [1. Luật thi](#1-luật-thi)
- [2. Chuẩn bị trước giờ thi](#2-chuẩn-bị-trước-giờ-thi)
- [3. Đề bài phần thực hành (3 giờ)](#3-đề-bài-phần-thực-hành-3-giờ)
- [4. Phần trình bày miệng (45 phút)](#4-phần-trình-bày-miệng-45-phút)
- [5. Thang điểm](#5-thang-điểm)
- [6. Dọn dẹp sau thi](#6-dọn-dẹp-sau-thi)
- [7. Nếu chưa đạt](#7-nếu-chưa-đạt)

---

## 1. Luật thi

| Được dùng | Không được dùng |
|---|---|
| Tài liệu chính thức (docs.aws.amazon.com, docs.docker.com, docs.github.com, docs.spring.io…), `man`, `--help` | AI dưới mọi hình thức (chat, gợi ý code trong editor — **tắt** Copilot/AI completion trước giờ thi) |
| **Repo `taskhub` của chính bạn**: runbook, `infra/aws-manual/commands.md`, ADR, nhật ký debug | File lab và lời giải trong giáo trình này (`06-AWS/labs/`, `solutions/`, `reference*/`) |
| Ghi chú tay / nhật ký học tập của bạn | Blog, video hướng dẫn từng bước, chép lệnh từ diễn đàn |

Vì sao được dùng repo của mình: ở công ty bạn **luôn** có runbook. Bài thi kiểm tra runbook của bạn có đủ tốt để dựng lại hệ thống không — nếu thiếu bước, đó là một phát hiện quan trọng, ghi lại.

Quy tắc khác:

- **Bấm giờ thật**: ghi giờ bắt đầu, giờ kết thúc từng phần vào `exam-month-3.md` trong repo nhật ký `devops-journey`.
- Kẹt quá 20 phút ở một lỗi → ghi lại triệu chứng và những gì đã thử, **chuyển sang phần khác**, quay lại sau. Kỹ năng phân bổ thời gian cũng được chấm.
- Mọi lỗi gặp phải → một mục trong `troubleshooting-journal.md` (có thể viết sau giờ thi, nhưng trong ngày).
- ⚠️ Bài thi tạo tài nguyên AWS tính phí (1 EC2 vài giờ). Ước tính và ghi số dư credit trước khi bắt đầu.

---

## 2. Chuẩn bị trước giờ thi

Làm **trước** khi bấm giờ (không tính vào 3 giờ):

1. `aws login` thành công; `aws sts get-caller-identity` ra user admin của bạn (không phải root).
2. VPC của v2 còn nguyên (subnet public-a/b, IGW, route table). EC2 của v2 có thể đang **stop** — không đụng vào nó trong giờ thi.
3. Release mới nhất (`v0.4.0`) có trên GHCR, package public.
4. Mở sẵn: repo `taskhub` (laptop), Console AWS, tab Actions của repo.
5. **Bốc thăm biến thể** — tung xúc xắc (hoặc `shuf -i 1-6 -n 2` trong WSL) chọn **2** yêu cầu thêm từ bảng dưới. Biến thể làm bài thi không thể làm thuộc lòng:

| Số | Yêu cầu thêm |
|---|---|
| 1 | Đặt máy mới ở subnet **public-b** (AZ `ap-southeast-1b`), không phải public-a |
| 2 | Tên tham số mật khẩu là `/taskhub/exam/postgres-password` — phải sửa quyền IAM và cách `deploy.sh` biết tên tham số (gợi ý: biến môi trường, không sửa cứng script) |
| 3 | nginx phải trả thêm header `X-Served-By: <hostname của EC2>` cho mọi response — thay đổi đi qua PR → CI → máy chủ |
| 4 | Máy mới dùng **role IAM mới** `taskhub-exam-role` với quyền tối thiểu do bạn tự viết (không dùng lại `taskhub-ec2-role`) |
| 5 | Database phải có sẵn 3 task mẫu ngay sau khi triển khai xong — bằng script trong repo, chạy lại nhiều lần không tạo trùng |
| 6 | Toàn bộ việc tạo tài nguyên AWS chỉ bằng **AWS CLI** (không bấm Console, trừ việc xem) và lưu lại thành script `infra/aws-manual/exam-create.sh` |

---

## 3. Đề bài phần thực hành (3 giờ)

Ngữ cảnh: *"Máy chủ production vừa bị xóa nhầm. Không có AMI, không có snapshot. Hãy dựng máy mới và đưa `taskhub` trở lại Internet. Dữ liệu cũ chấp nhận mất (chưa có backup — v5 sẽ giải quyết)."*

Làm theo thứ tự nào cũng được. Mỗi nhiệm vụ có **bằng chứng** phải nộp (ảnh chụp, output lệnh, link) — ghi vào file bài thi.

### A1 — AWS: dựng máy chủ (25 điểm)

Tạo EC2 mới tên `taskhub-exam` (tag `Project=taskhub`, `Env=exam`, `Owner`, `ManagedBy=manual`):

- `t3.small`, Ubuntu 24.04 lấy từ tham số SSM của Canonical (không chép AMI ID).
- IMDSv2 bắt buộc, hop limit 1; EBS gốc mã hóa, xóa theo instance.
- Instance profile có quyền SSM + đọc đúng tham số mật khẩu.
- Security Group riêng `taskhub-exam-sg`: chỉ TCP 80 từ Internet. **Không có 22.**
- Docker cài từ repo chính thức qua user data; vào máy bằng Session Manager.

**Bằng chứng:** output `describe-instances` (MetadataOptions, BlockDeviceMappings, Tags, IamInstanceProfile), `describe-security-groups`, ảnh phiên Session Manager chạy `docker compose version`.

### A2 — Linux trên máy mới (10 điểm)

Trong phiên Session Manager, trả lời bằng **lệnh + output**:

1. Máy có bao nhiêu RAM trống, ổ gốc còn bao nhiêu, đang chạy kernel nào?
2. User data đã chạy xong chưa, mất bao lâu? Tìm dòng chứng minh trong log nào?
3. Service nào đang lắng nghe cổng nào (sau khi app chạy)? Process nào giữ cổng 80?
4. `/opt/taskhub/.env`: chủ sở hữu, quyền là gì, vì sao phải như vậy?
5. SSM Agent chạy dưới dạng unit systemd tên gì? Xem 20 dòng log gần nhất của nó.

### A3 — Docker: triển khai (15 điểm)

Đưa `taskhub` (bản `v0.4.0`) lên máy mới bằng `deploy.sh` của bạn, mật khẩu lấy từ Parameter Store (tạo tham số mới hoặc dùng lại tùy biến thể).

**Bằng chứng:** `docker compose ps` (cả 3 service healthy/running), user chạy process Java trong container (`docker compose exec taskhub id`), kích thước image, `curl -s localhost/actuator/health` trên máy.

### A4 — Networking: chứng minh từ bên ngoài (10 điểm)

Từ laptop:

1. `curl` tạo một task và đọc lại qua IP public của máy mới.
2. Chứng minh cổng 8080, 5432 và 22 **không** truy cập được từ Internet — và giải thích vì sao kết quả là *timeout* chứ không phải *connection refused*.
3. Vẽ (bằng chữ) đường đi của gói tin từ laptop tới PostgreSQL, ghi rõ chỗ nào xảy ra NAT, chỗ nào là SG, chỗ nào là mạng Docker.

### A5 — Git + CI: một thay đổi nhỏ đi hết đường ống (15 điểm)

Thêm endpoint `GET /api/version` trả về chuỗi phiên bản (đọc từ `pom.xml` hoặc build info — tùy bạn) **kèm một test**. Đi đúng quy trình: nhánh `feat/` → PR → CI xanh (cả `build-test` và `image`) → squash merge → chờ CI trên `main` → tag `v0.4.1` → workflow `Release` → triển khai `:v0.4.1` lên **máy mới** → `curl http://<IP>/api/version`.

(Nếu bốc trúng biến thể 3, gộp thay đổi nginx vào cùng release hoặc release riêng `v0.4.2`.)

**Bằng chứng:** link PR, link 2 lần chạy CI, link lần chạy Release, output `curl`.

### A6 — Dọn dẹp và chi phí (5 điểm)

Trong giờ thi: xóa sạch **mọi** tài nguyên `Env=exam` (máy, volume, SG, role/instance profile nếu tạo mới, tham số nếu tạo mới) và chứng minh bằng lệnh kiểm tra. Ghi số dư credit trước/sau.

---

## 4. Phần trình bày miệng (45 phút)

Ghi âm (điện thoại) hoặc trình bày cho một người bạn. Không nhìn tài liệu, chỉ nhìn sơ đồ của chính bạn.

**Phần 1 — 10 phút:** trình bày dự án `taskhub` như trong phỏng vấn: vấn đề → kiến trúc v2 → đường ống từ commit tới production → một sự cố bạn đã gặp và cách tìm ra nguyên nhân → điều bạn sẽ làm khác.

**Phần 2 — 35 phút:** trả lời 10 câu (mỗi câu 2–4 phút). Rút ngẫu nhiên 10 trong 15:

1. Chuyện gì xảy ra từ lúc gõ `curl http://<IP>/api/tasks` tới khi nhận JSON? Kể đủ DNS (nếu có), TCP, HTTP, NAT, SG, nginx, app, database.
2. Process, signal, exit code 137 và 143 — liên hệ với `docker stop` và OOM.
3. Quyền `rwx` trên thư mục khác trên file thế nào? Vì sao `.env` là `600`?
4. Subnet `/24` có bao nhiêu địa chỉ dùng được trên AWS, vì sao không phải 254?
5. Security Group và NACL khác nhau thế nào? Vì sao gọi SG là *stateful*?
6. Image, layer, container — cái gì nằm ở đâu? Vì sao Dockerfile của bạn có 2 stage?
7. Volume `pgdata` sống ở đâu trên EC2? Terminate instance thì sao? Stop thì sao?
8. `depends_on` + `condition: service_healthy` giải quyết vấn đề gì? Vì sao không đủ cho production?
9. Merge, rebase, squash — dự án bạn dùng kiểu nào, vì sao?
10. Pipeline CI của bạn có những job nào, theo thứ tự nào, vì sao PR không push image?
11. Vì sao ghim action bằng SHA? Kể sự cố thật làm ví dụ.
12. Instance role lấy quyền thế nào? Vì sao không để access key trên máy chủ?
13. IMDSv2 và hop limit 1 bảo vệ khỏi kịch bản tấn công nào?
14. Rollback của bạn hoạt động thế nào, khi nào nó **không** cứu được?
15. Free plan của bạn hết vào ngày nào và tài nguyên nào đang tiêu credit nhiều nhất?

---

## 5. Thang điểm

### 5.1. Phần thực hành (80 điểm)

| Nhiệm vụ | Điểm tối đa | Đủ điểm khi | Mất điểm khi |
|---|---|---|---|
| A1 AWS | 25 | Đủ mọi thuộc tính, có bằng chứng | −5 mỗi thuộc tính thiếu (IMDSv2, mã hóa, tag, AMI từ SSM…) |
| A2 Linux | 10 | 5 câu, mỗi câu lệnh đúng + đọc đúng output | −2 mỗi câu sai/thiếu |
| A3 Docker | 15 | 3 service chạy, health `UP`, app chạy non-root, mật khẩu từ Parameter Store | −5 nếu phải sửa tay `.env`/compose trên máy để chạy được |
| A4 Networking | 10 | Đủ 3 ý, giải thích timeout vs refused đúng | −3 mỗi ý thiếu |
| A5 Git + CI | 15 | Đi đủ đường ống, release do workflow tạo, máy mới chạy `v0.4.1` | −5 nếu bỏ qua PR/CI (push thẳng, build tay); −5 nếu thiếu test |
| A6 Dọn dẹp | 5 | Lệnh kiểm tra chứng minh không còn tài nguyên `Env=exam` | 0 điểm nếu còn sót bất kỳ thứ gì tính phí |
| Biến thể | (nằm trong điểm của nhiệm vụ liên quan) | Làm đủ 2 biến thể đã bốc | −5 mỗi biến thể bỏ qua |

### 5.2. Phần trình bày (20 điểm)

| Tiêu chí | Điểm |
|---|---|
| Phần 1: đủ 5 ý, đúng thời gian, có sự cố thật | 6 |
| Phần 2: mỗi câu trả lời **đúng bản chất** (không chỉ thuộc tên) — 1,4 điểm/câu | 14 |

Nghe lại bản ghi khi tự chấm. Một câu trả lời đạt khi bạn giải thích được **vì sao**, không chỉ **cái gì**. Có thể nhờ Claude đóng vai người phỏng vấn **sau** khi đã tự chấm — đưa bản ghi chép, không đưa đáp án.

### 5.3. Kết quả

- **Đạt:** ≥ 70/100 **và** không vi phạm điều kiện liệt.
- **Điều kiện liệt** (tự động không đạt, dù điểm cao):
  - Security Group mở cổng 22 hoặc "All traffic" ra `0.0.0.0/0`.
  - Mật khẩu/secret nằm trong Git, user data, hay output dán vào file bài thi.
  - Dùng tài khoản root để làm bài, hoặc tạo access key dài hạn.
  - Kết thúc buổi thi mà còn tài nguyên `Env=exam` đang chạy.
  - Dùng AI trong giờ thi.
- Ghi điểm từng phần, thời gian từng nhiệm vụ, và **3 điểm yếu lớn nhất** vào file bài thi.

---

## 6. Dọn dẹp sau thi

Ngoài A6: kiểm tra lần nữa bằng **EC2 Global View** và Tag Editor (tag `Env=exam`, mọi Region). Hai ngày sau xem lại mục Credits trong Billing — chi phí cập nhật trễ. Nếu A5 tạo release `v0.4.1`, cập nhật EC2 của v2 lên bản đó ở buổi học kế tiếp (hoặc để v3 tự làm).

---

## 7. Nếu chưa đạt

Không chuyển sang tuần 13 với nền còn hổng — CD tự động (v3) chỉ tự động hóa những gì bạn làm được bằng tay. Theo [quy tắc khi chậm tiến độ](weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ):

| Mất điểm nhiều nhất ở | Ôn lại | Rồi làm lại |
|---|---|---|
| A1 / điều kiện liệt về AWS | Module 06 bài 02 (IAM), 03 (VPC), 04 (EC2); Lab 02 | Nhiệm vụ A1 với biến thể khác |
| A2 | [01-LINUX](../01-LINUX/README.md) bài 03, 04, 07; [checkpoint Linux](../01-LINUX/checkpoint.md) | A2 trên một máy mới |
| A3 | [04-DOCKER](../04-DOCKER/README.md) bài 05, 08 | A3 |
| A4 | [02-NETWORKING](../02-NETWORKING/README.md) bài 04, 05, 08 | A4 + vẽ lại đường đi gói tin |
| A5 | [03-GIT](../03-GIT/README.md) bài 03, 05; [05-CICD](../05-CICD/README.md) bài 02, 03 | A5 với một thay đổi khác |
| Trình bày | Viết câu trả lời ra giấy trước, rồi nói lại không nhìn | Phần 4 với 10 câu khác |
| Hết giờ dù làm đúng | Runbook thiếu bước / chưa tự động hóa được phần lặp lại — bổ sung `commands.md`, script hóa phần tạo tài nguyên | Toàn bộ bài thi, mục tiêu ≤ 3 giờ |

Dùng tuần dự phòng (1–2 giờ/tuần có sẵn trong kế hoạch). Làm lại **chỉ** phần chưa đạt, với biến thể khác, trong vòng 1 tuần. Nếu lần hai vẫn chưa đạt ở phần AWS, kéo dài tuần 12 thêm một tuần — trễ một tuần tốt hơn nhiều so với học Terraform trên một nền IAM/VPC chưa vững.
