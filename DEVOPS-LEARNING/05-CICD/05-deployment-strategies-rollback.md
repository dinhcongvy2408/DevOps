# 05. Chiến lược triển khai và rollback

> ⏱️ ~3,5 giờ · Mức độ: 🟥 Bắt buộc (blue/green thực hành 🟨, canary/shadow 🟦) · Kiến thức cần có trước: [01. Khái niệm CI/CD](01-cicd-concepts.md), [03. Build & push image lên GHCR](03-github-actions-docker-registry.md), [Docker 05 — Compose](../04-DOCKER/05-docker-compose.md), [Network 07 — Reverse proxy & load balancing](../02-NETWORKING/07-load-balancing-reverse-proxy.md)
> Môi trường: `[WSL]` Ubuntu 24.04 + Docker Desktop. Không cần tài khoản AWS.
> Phiên bản khi viết (kiểm tra 2026-10-31): Docker Compose v2, `nginx:1.30-alpine`, `python:3.12-slim`

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

- Giải thích và so sánh các chiến lược triển khai: **recreate**, **rolling**, **blue/green**, **canary**, cùng **feature flag** và 🟦 **shadow**, theo bốn tiêu chí: thời gian gián đoạn, chi phí, độ phức tạp, tốc độ rollback.
- Phân biệt **deploy** (đưa code lên server) và **release** (cho người dùng thấy tính năng).
- Dùng **health check** và **smoke test** để quyết định một lần triển khai là "thành công" hay "phải quay lại".
- **Rollback** bằng cách triển khai lại một **tag image bất biến** cũ, và biết khi nào nên **roll forward** thay vì rollback.
- Giải thích vì sao **database migration** là phần khó nhất của rollback, và áp dụng mẫu **expand/contract**.
- Tự đo **downtime** của một lần triển khai bằng vòng lặp `curl`, tự viết script deploy **tự rollback**, và chuyển traffic blue/green bằng `nginx -s reload`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

CI ở bài 02–03 trả lời câu hỏi "**code này có tốt không?**". Bài này trả lời câu hỏi tiếp theo: "**đưa nó tới người dùng thế nào mà không làm hỏng hệ thống đang chạy, và nếu hỏng thì quay lại thế nào?**"

| Tình huống thật | Kiến thức trong bài |
|---|---|
| "Deploy lúc 2 giờ chiều có làm người dùng thấy lỗi 502 không?" | Downtime của từng chiến lược |
| Bản mới lỗi, sếp hỏi "bao lâu thì quay lại được?" | Rollback bằng tag bất biến |
| Bản mới đã chạy migration xóa một cột, giờ muốn rollback | Expand/contract, roll forward |
| "Thử tính năng mới cho 5% người dùng trước" | Canary, feature flag |
| Dự án yêu cầu "Rollback khi deployment lỗi" (yêu cầu số 12 của [dự án](../12-PRACTICAL-PROJECT/README.md)) | Toàn bộ bài; diễn tập thật ở v5 |
| Phỏng vấn: "Blue/green khác canary thế nào? Rollback database ra sao?" | Mục 4 |

Theo kinh nghiệm chung của ngành, phần lớn sự cố production xuất phát từ **thay đổi** (deploy, đổi cấu hình). Vì vậy cách bạn deploy và khả năng quay lại nhanh quan trọng không kém chất lượng code.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Deploy khác release

- **Deploy** (triển khai): đưa phiên bản mới lên hạ tầng và cho nó chạy.
- **Release** (phát hành): cho **người dùng** tiếp xúc với thay đổi.

Hai việc này **có thể tách nhau**: deploy code chứa tính năng mới nhưng tắt bằng feature flag (đã deploy, chưa release); hoặc deploy bản mới lên môi trường "green" chưa nhận traffic (đã deploy, chưa release). Tách được hai việc này là chìa khóa của mọi chiến lược an toàn.

### 3.2. Ba thứ một chiến lược phải trả lời

1. **Khi chuyển đổi, có lúc nào không có phiên bản nào phục vụ người dùng không?** → downtime.
2. **Có lúc nào hai phiên bản cùng chạy không?** → nếu có, chúng phải **tương thích** với nhau và với database.
3. **Phát hiện lỗi thì quay lại bằng cách nào, mất bao lâu?** → rollback.

### 3.3. Health check: "sống" và "sẵn sàng"

Bạn đã gặp `/actuator/health` ([tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)) và `HEALTHCHECK` ([Docker 03](../04-DOCKER/03-dockerfile-multistage.md)). Khi triển khai, cần phân biệt hai câu hỏi:

| Câu hỏi | Tên thường gặp | Sai thì làm gì |
|---|---|---|
| "Process còn sống không, hay bị treo?" | **Liveness** | Khởi động lại container |
| "Đã sẵn sàng nhận request chưa?" (khởi động xong, kết nối được database) | **Readiness** | **Chưa gửi traffic** tới nó |

Spring Boot mất vài giây đến vài chục giây để khởi động. Gửi traffic vào lúc đó → lỗi. Mọi chiến lược không-gián-đoạn đều dựa vào readiness: **chỉ chuyển traffic sang bản mới khi nó báo sẵn sàng**. Kubernetes (Module 09) có hai probe riêng; Docker Compose chỉ có một `healthcheck`, ta dùng nó như readiness.

### 3.4. Smoke test

**Smoke test** (kiểm tra khói — tên gọi từ việc bật máy lần đầu xem có bốc khói không) là vài request đơn giản chạy **ngay sau khi deploy**, trên **môi trường thật**, để xác nhận thứ quan trọng nhất hoạt động. Nó không thay thế test trong CI: CI chứng minh code đúng; smoke test chứng minh **lần deploy này** đúng (đúng image, đúng cấu hình, kết nối được database).

Smoke test tốt kiểm tra **đúng phiên bản** đang chạy, không chỉ "có trả lời":

```bash
curl -fsS --retry 5 --retry-connrefused --retry-delay 2 http://localhost:8000/actuator/health
```

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Recreate — dừng hết, chạy bản mới

```text
v1 ████████████│
               │← downtime →│
v2             │            ████████████
```

Dừng toàn bộ bản cũ, rồi khởi động bản mới. Đây là thứ `docker compose up -d` làm khi bạn đổi tag image: Compose **dừng và tạo lại** container (theo tài liệu Docker), giữ nguyên volume.

| Ưu | Nhược |
|---|---|
| Đơn giản nhất, không cần thêm tài nguyên | **Có downtime** = thời gian dừng + thời gian khởi động bản mới (Spring Boot: vài chục giây) |
| Không bao giờ có hai phiên bản chạy cùng lúc → không lo tương thích | Bản mới không khởi động được → hệ thống **chết** cho tới khi rollback |

Dùng khi: môi trường dev, ứng dụng nội bộ chấp nhận gián đoạn ngắn, hoặc khi hai phiên bản **không thể** chạy cùng lúc (ví dụ migration phá vỡ tương thích). `taskhub` v0 (laptop) và v3 (một EC2) dùng recreate.

### 4.2. 🟥 Rolling — thay dần từng phần

```text
Ban đầu:   [v1] [v1] [v1] [v1]
Bước 1:    [v2] [v1] [v1] [v1]   ← v2 sẵn sàng mới thay tiếp
Bước 2:    [v2] [v2] [v1] [v1]
...
Cuối:      [v2] [v2] [v2] [v2]
```

Cần **nhiều bản sao** sau một load balancer ([Network 07](../02-NETWORKING/07-load-balancing-reverse-proxy.md)). Thay từng bản (hoặc từng nhóm): tạo bản mới → chờ readiness → đưa vào load balancer → rút bản cũ ra.

| Ưu | Nhược |
|---|---|
| Không downtime (nếu readiness đúng) | **v1 và v2 chạy cùng lúc** trong suốt quá trình → phải tương thích (API, database) |
| Không cần gấp đôi tài nguyên (chỉ thêm 1–2 bản tạm) | Rollback = rolling ngược lại, **không tức thì** |
| Là mặc định của Kubernetes Deployment | Người dùng có thể gặp v1 ở request này, v2 ở request sau |

Kubernetes Deployment mặc định dùng `RollingUpdate` với `maxSurge: 25%` và `maxUnavailable: 25%` — bạn sẽ thấy ở v6 (Module 09).

### 4.3. 🟥 Blue/green — hai môi trường, một công tắc

```text
                      ┌──► BLUE  (v1) ── đang nhận 100% traffic
Người dùng ──► Router ┤
                      └──► GREEN (v2) ── đã deploy, đang kiểm tra, 0% traffic

Chuyển:  Router trỏ sang GREEN  →  100% traffic vào v2 ngay lập tức
Rollback: Router trỏ lại BLUE   →  vài giây
```

Theo mô tả của Martin Fowler: có hai môi trường giống hệt nhau; một bên (blue) đang phục vụ, bên kia (green) nhận bản mới để kiểm tra lần cuối; khi sẵn sàng thì **đổi router** sang green. Lỗi → **đổi router về blue**. Sau đó blue trở thành nơi chuẩn bị cho bản tiếp theo.

| Ưu | Nhược |
|---|---|
| Chuyển đổi và **rollback gần như tức thì** | Cần **gấp đôi** tài nguyên trong lúc chuyển |
| Kiểm tra được bản mới trên hạ tầng thật **trước khi** nhận traffic | **Database dùng chung** → schema phải hợp với cả hai bản (mục 4.8) |
| Không có giai đoạn trộn lẫn hai phiên bản lâu | Request đang dở lúc chuyển, session người dùng — phải tính |

"Router" có thể là: nginx đổi `upstream` (lab mục 9), AWS ALB đổi target group, DNS, Kubernetes Service đổi selector.

### 4.4. 🟨 Canary — thử trên một nhóm nhỏ trước

```text
Người dùng ──► Router ──┬── 95% ──► v1
                        └──  5% ──► v2 (canary)
Theo dõi lỗi, độ trễ của v2 → ổn: 25% → 50% → 100%
                             → tệ: 0%, quay về v1
```

Tên gọi từ chú chim hoàng yến (canary) thợ mỏ mang xuống hầm để phát hiện khí độc sớm. Bản mới nhận một **phần nhỏ** traffic; nếu số liệu (tỉ lệ lỗi, độ trễ) tốt thì tăng dần.

| Ưu | Nhược |
|---|---|
| Lỗi chỉ ảnh hưởng một phần nhỏ người dùng | Cần router chia traffic theo tỉ lệ (ALB weighted, Ingress, service mesh) |
| Quyết định dựa trên **số liệu production thật** | Cần **monitoring tốt** (Module 08) — không đo được thì canary vô nghĩa |
| | Hai phiên bản cùng chạy lâu → tương thích là bắt buộc |

`taskhub` không làm canary thật (cần nhiều server + monitoring). Bạn cần **giải thích được** nó trong phỏng vấn.

### 4.5. 🟨 Feature flag — tách release khỏi deploy

**Feature flag** (cờ tính năng) đã giới thiệu ở [Git 04 — Quy trình nhóm](../03-GIT/04-team-workflows.md): code mới được deploy nhưng nằm sau một điều kiện `if (flags.isOn("new-search"))`. Bật/tắt bằng cấu hình, **không cần deploy lại**.

Bài viết *Feature Toggles* (Pete Hodgson, trên martinfowler.com) chia làm 4 loại:

| Loại | Mục đích | Sống bao lâu |
|---|---|---|
| **Release toggle** | Ẩn tính năng chưa xong để vẫn merge vào `main` hằng ngày | Ngắn — xóa khi tính năng hoàn thành |
| **Experiment toggle** | A/B test | Ngắn–trung bình |
| **Ops toggle** | "Công tắc khẩn cấp" tắt tính năng nặng khi hệ thống quá tải | Có thể lâu dài |
| **Permissioning toggle** | Bật tính năng cho nhóm người dùng (trả phí, nội bộ) | Lâu dài |

Rollback một tính năng bằng flag chỉ mất vài giây. Đánh đổi: code có nhiều nhánh `if`, cờ cũ quên xóa thành nợ kỹ thuật.

### 4.6. 🟦 Shadow (mirror) — chạy thử bằng traffic thật mà người dùng không thấy

Router **sao chép** request thật gửi tới cả v1 và v2, nhưng chỉ trả kết quả của v1 cho người dùng; kết quả v2 dùng để so sánh. Rất hữu ích để kiểm tra hiệu năng, nhưng nguy hiểm với request **có ghi dữ liệu** (v2 ghi lần hai, gửi email lần hai…). Biết tên là đủ ở mức Junior.

### 4.7. 🟥 So sánh tổng hợp

| Chiến lược | Downtime | Tài nguyên thêm | Độ phức tạp | Tốc độ rollback | Hai phiên bản cùng chạy? | `taskhub` |
|---|---|---|---|---|---|---|
| **Recreate** | Có (khởi động app) | Không | Thấp | Chậm (= một lần recreate nữa) | Không | v0, v3 |
| **Rolling** | Không* | Ít | Trung bình | Trung bình (rolling ngược) | Có, trong lúc chuyển | v6 (Kubernetes) |
| **Blue/green** | Không* | Gấp đôi lúc chuyển | Trung bình | **Nhanh nhất** (đổi router) | Có, ngắn | Lab bài này; 🟨 bài tập v3 |
| **Canary** | Không* | Ít–trung bình | Cao (cần chia traffic + monitoring) | Nhanh (về 0%) | Có, lâu | Chỉ lý thuyết |
| **Feature flag** | Không | Không | Trung bình (trong code) | Rất nhanh (tắt cờ) | Không áp dụng | Chỉ lý thuyết |

\* Với điều kiện health check/readiness đúng và ứng dụng tắt nhẹ nhàng (graceful shutdown — xử lý xong request đang dở khi nhận SIGTERM, xem [Docker 02](../04-DOCKER/02-images-containers.md)).

### 4.8. 🟥 Database migration — phần khó nhất của rollback

Image là bất biến: rollback image = chạy lại image cũ, xong. **Dữ liệu thì không quay ngược được** như vậy.

Kịch bản kinh điển:

```text
v0.4.0: bảng tasks có cột "title"
v0.5.0: migration V5__rename_title.sql   ALTER TABLE tasks RENAME COLUMN title TO name;
        → deploy v0.5.0, migration chạy, phát hiện lỗi khác, rollback về image v0.4.0
        → v0.4.0 khởi động, Hibernate tìm cột "title"... không có → app chết
```

Rollback image **không** rollback schema. Và Flyway bản cộng đồng (Community — bản `taskhub` dùng) **không có lệnh undo**: theo bảng tính năng của Redgate, *Undo migrations* chỉ có trong **Flyway Teams và Enterprise** (bản trả phí). Flyway được thiết kế đi **tiến** (forward-only): sửa sai bằng một migration mới `V6__...`, không phải bằng cách lùi.

Ngay cả khi có undo, chạy ngược một migration đã xóa cột thì **dữ liệu trong cột đó đã mất**.

**Giải pháp: expand/contract** (còn gọi là *parallel change*, Danilo Sato mô tả trên martinfowler.com). Chia một thay đổi phá vỡ tương thích thành nhiều bước, **mỗi bước tương thích ngược với phiên bản ngay trước nó**:

| Bước | Migration | Code app | Rollback về bản trước có an toàn? |
|---|---|---|---|
| 1. **Expand** (mở rộng) | `ADD COLUMN name` (cho phép NULL) | v0.5.0: ghi **cả** `title` và `name`, đọc `title` | ✅ v0.4.0 bỏ qua cột thừa |
| 2. **Migrate** (chuyển dữ liệu) | `UPDATE tasks SET name = title WHERE name IS NULL` | v0.6.0: đọc `name`, vẫn ghi cả hai | ✅ v0.5.0 vẫn đọc `title` còn đầy đủ |
| 3. **Contract** (thu gọn) — **vài bản sau**, khi chắc không cần quay lại | `DROP COLUMN title` | v0.7.0: chỉ dùng `name` | ⚠️ Chỉ rollback được về v0.6.0 trở đi |

Quy tắc thực hành cho `taskhub`:

1. Migration **thêm** (bảng, cột cho phép NULL, index) thì an toàn — làm thoải mái.
2. Migration **xóa/đổi tên/đổi kiểu** cột → luôn tách expand/contract, bước contract ở release sau.
3. **Không bao giờ sửa** file migration đã chạy (bạn đã gặp lỗi *checksum mismatch* ở [tuần 6](../12-PRACTICAL-PROJECT/milestones/v-pre-week6-springboot-app.md)).
4. Trước migration có rủi ro: **backup database** (v5 sẽ tự động hóa `pg_dump`).

Fowler cũng nêu đúng điều này trong bài blue/green: phần khó nhất là database; cách làm là deploy thay đổi schema tương thích với cả hai phiên bản trước, rồi mới deploy app, và sau đó mới bỏ phần hỗ trợ bản cũ.

### 4.9. 🟥 Rollback bằng tag bất biến, và khi nào roll forward

Nhờ quy ước tag ở [Docker 06](../04-DOCKER/06-registry.md) và pipeline ở [bài 03](03-github-actions-docker-registry.md), mỗi phiên bản `taskhub` có tên **không bao giờ bị ghi đè**:

```text
ghcr.io/phuong-dev/taskhub:v0.3.0    (release)
ghcr.io/phuong-dev/taskhub:9f8e7d6   (mỗi commit trên main)
```

Rollback = **triển khai lại tag cũ**, không build lại gì:

```bash
# Trên server (v3): đổi tag trong file .env rồi recreate
sed -i 's/^TASKHUB_IMAGE_TAG=.*/TASKHUB_IMAGE_TAG=v0.3.0/' .env
docker compose pull taskhub
docker compose up -d --wait
```

Vì sao tuyệt đối không rollback bằng `latest` hay build lại từ commit cũ: `latest` đã bị ghi đè; build lại hôm nay ra image **khác** image đã test (base image mới hơn, thư viện mới hơn) — bạn đang deploy một thứ chưa ai kiểm tra trong lúc khẩn cấp.

**Rollback hay roll forward?**

| Chọn **rollback** (về bản cũ) khi | Chọn **roll forward** (sửa nhanh, deploy bản mới hơn) khi |
|---|---|
| Lỗi nghiêm trọng, chưa rõ nguyên nhân | Bản mới đã chạy migration không tương thích ngược (rollback sẽ làm app cũ chết) |
| Bản cũ chắc chắn tương thích với schema hiện tại | Lỗi nhỏ, đã biết nguyên nhân, sửa trong vài phút và CI chạy nhanh |
| Mục tiêu đầu tiên là **khôi phục dịch vụ** | Rollback mất lâu hơn sửa |

Nguyên tắc khi có sự cố: **khôi phục dịch vụ trước, tìm nguyên nhân sau.** Rollback thường là cách khôi phục nhanh nhất — nếu bạn đã giữ database tương thích ngược.

### 4.10. 🟥 Triển khai an toàn = chiến lược + cổng kiểm tra tự động

Một script deploy tốt (bạn tự viết ở Bước 6 phần thực hành) luôn có dạng:

```text
1. Ghi lại phiên bản đang chạy (để biết quay về đâu)
2. Triển khai phiên bản mới
3. Chờ health check báo healthy (có giới hạn thời gian)
4. Smoke test: đúng phiên bản? chức năng chính chạy?
5. Đạt  → ghi nhận phiên bản mới
   Trượt → TỰ ĐỘNG triển khai lại phiên bản ở bước 1, báo lỗi (exit ≠ 0)
```

Pipeline CD ở v3 sẽ chạy đúng các bước này trên EC2.

### 4.11. Gặp lại ở đâu

| Kiến thức | Gặp lại ở |
|---|---|
| Recreate bằng Compose, rollback bằng tag | Dự án v3 — CD lên EC2 (tuần 13–14) |
| Blue/green bằng nginx | 🟨 Bài tập mở rộng ở v3 |
| ALB, target group, weighted routing | Module 06 — lab ALB + ASG (tuần 14) |
| Rolling update, readiness/liveness probe, `kubectl rollout undo` | Module 09, dự án v6 |
| Metrics để quyết định canary | Module 08 |
| Diễn tập rollback < 5 phút, backup trước migration | Dự án v5 (tuần 18) |
| Expand/contract với Flyway | Mỗi khi bạn đổi schema `taskhub` từ nay về sau |

---

## 5. Ví dụ thực tế

### Ví dụ 1: Recreate lúc cao điểm

Một team deploy ứng dụng Spring Boot bằng `docker compose up -d` lúc 10 giờ sáng. App mất 40 giây để khởi động. Trong 40 giây đó, nginx trả 502 cho mọi request, hệ thống giám sát của khách hàng báo động. Không ai sai về kỹ thuật — chiến lược recreate **luôn** có khoảng này. Cách xử lý thực tế: deploy ngoài giờ cao điểm + thông báo trước (chấp nhận được với hệ thống nhỏ), hoặc chuyển sang blue/green khi downtime không còn chấp nhận được.

### Ví dụ 2: Rollback làm sự cố tệ hơn

Bản mới có migration đổi tên cột. Sau deploy, phát hiện lỗi hiển thị nhỏ. Kỹ sư trực bấm rollback theo phản xạ → app cũ không tìm thấy cột → **toàn bộ** hệ thống chết thay vì một lỗi hiển thị. Bài học: trước khi rollback, phải biết bản mới **có thay đổi schema không tương thích** không. Đó là lý do runbook rollback (v5) có câu hỏi đầu tiên: "Release này có migration không?"

### Ví dụ 3: Canary bắt lỗi chỉ xuất hiện ở production

Bản mới chạy tốt ở staging, nhưng với dữ liệu thật có một số bản ghi chứa ký tự đặc biệt làm một endpoint lỗi. Ở 5% canary, tỉ lệ lỗi HTTP 500 của canary tăng rõ so với bản cũ, hệ thống tự hạ canary về 0%. Chỉ một phần nhỏ người dùng gặp lỗi trong vài phút. Nếu deploy 100% ngay, toàn bộ người dùng đã bị ảnh hưởng.

---

## 6. Sơ đồ kiến trúc

### 6.1. Lab bài này

```text
Phần A–B (recreate + tự rollback)              Phần C (blue/green)

curl loop ──► localhost:8090                     curl loop ──► localhost:8090
                 │                                                │
           ┌─────▼─────┐                                    ┌─────▼─────┐
           │  nginx    │ resolver 127.0.0.11                │  nginx    │ active.inc: set $backend ...
           └─────┬─────┘                                    └──┬─────┬──┘
                 │ http://app:8080                    (đang chọn)│     │(chờ)
           ┌─────▼─────┐                              ┌──────────▼┐   ┌▼──────────┐
           │ app       │ demo-app:${APP_TAG}          │ app-blue  │   │ app-green │
           └───────────┘                              │ v1.0.0    │   │ v1.1.0    │
                                                      └───────────┘   └───────────┘
 Đổi APP_TAG → Compose recreate app → có khoảng 502     Đổi active.inc + nginx -s reload → 0 lỗi
```

### 6.2. `taskhub` qua các phiên bản

```text
v0 (laptop)  : compose up -d  ─────────────── recreate, downtime vài chục giây, không sao
v3 (1 EC2)   : CD → ssh/SSM → compose pull + up -d --wait → smoke test → lỗi thì tag cũ
               recreate, downtime ~ thời gian khởi động Spring Boot
               🟨 nâng cấp: blue/green bằng 2 service + nginx (giống lab phần C)
v6 (K8s)     : kubectl/helm → Deployment RollingUpdate + readiness probe → không downtime
               rollback: helm rollback / kubectl rollout undo
```

---

## 7. Các câu lệnh cần biết

| Lệnh | Chạy ở | Mục đích |
|---|---|---|
| `docker compose up -d --wait --wait-timeout 40` | `[WSL]` | Triển khai và **chờ** mọi service running/healthy; quá thời gian hoặc unhealthy → lỗi |
| `docker compose ps` | `[WSL]` | Xem trạng thái và health |
| `docker inspect -f '{{.State.Health.Status}}' <container>` | `[WSL]` | Lấy riêng trạng thái health |
| `curl -fsS --retry 5 --retry-connrefused --retry-delay 1 <url>` | `[WSL]` | Smoke test chịu được vài giây khởi động |
| `curl -s -o /dev/null -w '%{http_code}' --max-time 1 <url>` | `[WSL]` | Lấy mã HTTP để đo downtime |
| `docker compose exec nginx nginx -t` | `[WSL]` | Kiểm tra cú pháp cấu hình nginx trước khi áp dụng |
| `docker compose exec nginx nginx -s reload` | `[WSL]` | Áp dụng cấu hình mới **không ngắt** kết nối đang có |

---

## 8. Giải thích câu lệnh và tham số

### `docker compose up -d --wait --wait-timeout 40`

```bash
docker compose up -d --wait --wait-timeout 40
```

Đầu ra minh họa khi thành công:

```text
[+] Running 2/2
 ✔ Container bg05-app-1    Healthy
 ✔ Container bg05-nginx-1  Healthy
```

Đầu ra minh họa khi bản mới không healthy (chữ chính xác có thể khác theo phiên bản Compose):

```text
[+] Running 1/2
 ✘ Container bg05-app-1    Error
dependency failed to start: container bg05-app-1 is unhealthy
```

| Tham số | Ý nghĩa (theo tài liệu Docker) |
|---|---|
| `-d` | Chạy nền |
| `--wait` | Chờ service ở trạng thái running/healthy; tự bao hàm `-d` |
| `--wait-timeout 40` | Chờ tối đa 40 giây |
| Hành vi mặc định | Service nào đổi cấu hình hoặc image → Compose **dừng và tạo lại** container đó, giữ volume |

Exit code ≠ 0 khi chờ thất bại → script dùng được trong `if`.

### `curl` cho smoke test

```bash
curl -fsS --retry 5 --retry-connrefused --retry-delay 1 http://localhost:8090/version
```

```text
{"version": "v1.1.0"}
```

| Tham số | Ý nghĩa |
|---|---|
| `-f` | HTTP ≥ 400 → exit code khác 0 (mặc định curl coi 500 là "thành công") |
| `-sS` | Im lặng nhưng vẫn in lỗi |
| `--retry 5` | Thử lại tối đa 5 lần với lỗi tạm thời (timeout, một số mã 5xx) |
| `--retry-connrefused` | Coi "connection refused" là lỗi tạm thời, cũng thử lại |
| `--retry-delay 1` | Chờ 1 giây giữa các lần |

### Vòng lặp đo downtime

```bash
curl -s -o /dev/null -w '%{http_code}\n' --max-time 1 http://localhost:8090/version
```

| Tham số | Ý nghĩa |
|---|---|
| `-o /dev/null` | Bỏ phần thân |
| `-w '%{http_code}\n'` | In mã HTTP; không kết nối được → `000` |
| `--max-time 1` | Không chờ quá 1 giây, để vòng lặp đều đặn |

### `nginx -t` và `nginx -s reload`

```bash
docker compose -f compose.bluegreen.yaml exec nginx nginx -t
```

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

| Lệnh | Ý nghĩa |
|---|---|
| `nginx -t` | Đọc và kiểm tra toàn bộ cấu hình, **không** áp dụng |
| `nginx -s reload` | Gửi tín hiệu cho master process: đọc cấu hình mới, khởi động worker mới, để worker cũ **xử lý xong** request đang dở rồi mới thoát → không rớt kết nối |

Luôn `-t` trước `reload`: cấu hình sai thì reload bị từ chối và nginx giữ cấu hình cũ, nhưng kiểm tra trước giúp bạn thấy lỗi ngay.

---

## 9. Bài thực hành từng bước

> Không tạo tài nguyên cloud. Dùng một ứng dụng demo nhỏ (Python, khởi động giả lập chậm 5 giây như Spring Boot) để mỗi lần thử chỉ mất vài giây. Project Compose tên `bg05`, cổng `8090` (tránh đụng `taskhub` ở 8000). Bài tập 4 sẽ áp dụng lại cho `taskhub` thật.

### Bước 1 — Tạo ứng dụng demo `[WSL]`

```bash
mkdir -p ~/devops-lab/05-cicd/deploy-lab && cd ~/devops-lab/05-cicd/deploy-lab
```

`app.py`:

```bash
cat > app.py <<'EOF'
import json
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = os.environ.get("APP_VERSION", "dev")
BROKEN = os.environ.get("APP_BROKEN") == "1"
STARTUP_DELAY = float(os.environ.get("STARTUP_DELAY", "5"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            code = 500 if BROKEN else 200
            body = {"status": "DOWN" if BROKEN else "UP", "version": VERSION}
        elif self.path == "/version":
            code, body = 200, {"version": VERSION}
        else:
            code, body = 404, {"error": "not found"}
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    # PID 1 phải tự xử lý SIGTERM, nếu không docker stop chờ 10 giây rồi SIGKILL
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    print(f"starting version={VERSION} broken={BROKEN}, warming up {STARTUP_DELAY}s", flush=True)
    time.sleep(STARTUP_DELAY)          # giả lập Spring Boot khởi động chậm
    server = ThreadingHTTPServer(("0.0.0.0", 8080), Handler)
    print("listening on :8080", flush=True)
    server.serve_forever()
EOF
```

`Dockerfile` — phiên bản và "lỗi" được **đóng băng trong image** lúc build, giống một bản phát hành thật:

```bash
cat > Dockerfile <<'EOF'
FROM python:3.12-slim
ARG APP_VERSION=dev
ARG APP_BROKEN=0
ENV APP_VERSION=${APP_VERSION} \
    APP_BROKEN=${APP_BROKEN} \
    PYTHONUNBUFFERED=1
WORKDIR /app
COPY app.py .
RUN useradd --system --no-create-home app
USER app
EXPOSE 8080
CMD ["python", "app.py"]
EOF
```

Build ba "bản phát hành", mỗi bản một tag bất biến:

```bash
docker build -t demo-app:v1.0.0 --build-arg APP_VERSION=v1.0.0 .
docker build -t demo-app:v1.1.0 --build-arg APP_VERSION=v1.1.0 .
docker build -t demo-app:v1.2.0 --build-arg APP_VERSION=v1.2.0 --build-arg APP_BROKEN=1 .
docker image ls demo-app
```

`v1.2.0` là **bản phát hành lỗi**: khởi động được, `/version` trả lời bình thường, nhưng `/health` trả 500 (ví dụ không kết nối được database).

### Bước 2 — Compose và nginx (recreate) `[WSL]`

```bash
mkdir -p nginx/single
cat > nginx/single/default.conf <<'EOF'
server {
    listen 80;

    # Phân giải tên "app" lúc có request (qua DNS nội bộ của Docker), không chỉ một lần lúc khởi động.
    # Container được tạo lại có thể đổi IP — thiếu dòng này nginx giữ IP cũ và trả 502 mãi.
    resolver 127.0.0.11 valid=2s ipv6=off;
    set $backend http://app:8080;

    location / {
        proxy_pass $backend;
        proxy_connect_timeout 1s;
    }
}
EOF
```

```bash
cat > compose.yaml <<'EOF'
name: bg05

services:
  app:
    image: demo-app:${APP_TAG:?Đặt APP_TAG trong .env, ví dụ APP_TAG=v1.0.0}
    environment:
      STARTUP_DELAY: "5"
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=2)"]
      interval: 2s
      timeout: 3s
      retries: 3
      start_period: 10s
    restart: unless-stopped

  nginx:
    image: nginx:1.30-alpine
    ports:
      - "${BG_PORT:-8090}:80"
    volumes:
      - ./nginx/single:/etc/nginx/conf.d:ro
    depends_on:
      - app
    restart: unless-stopped
EOF
```

Vì sao healthcheck dùng Python? Image `python:3.12-slim` không có `curl`. `urlopen` gặp HTTP 500 sẽ ném lỗi → exit code 1 → unhealthy.

Triển khai bản đầu tiên:

```bash
echo 'APP_TAG=v1.0.0' > .env
docker compose up -d --wait --wait-timeout 40
docker compose ps
curl -s localhost:8090/version; echo
```

```text
{"version": "v1.0.0"}
```

### Bước 3 — Đo downtime của recreate `[WSL]`

Tạo `watch.sh` — in mã HTTP mỗi 0,2 giây, **Ctrl+C** để dừng và xem tổng kết:

```bash
cat > watch.sh <<'EOF'
#!/usr/bin/env bash
# Gọi /version liên tục, in thời điểm + mã HTTP + phiên bản. Ctrl+C để xem tổng kết.
port="${BG_PORT:-8090}"
ok=0
fail=0
trap 'echo; echo "OK=$ok  LỖI=$fail"; exit 0' INT
while true; do
  # tr -d '\n': trang lỗi 502 của nginx có nhiều dòng — gộp lại để mỗi request đúng một dòng
  out="$(curl -s --max-time 1 -w ' %{http_code}' "http://localhost:${port}/version" | tr -d '\n' || true)"
  code="${out##* }"
  if [[ "$code" == "200" ]]; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  printf '%s %s\n' "$(date +%T.%N | cut -c1-12)" "$out"
  sleep 0.2
done
EOF
chmod +x watch.sh
```

Mở **terminal thứ hai** chạy `./watch.sh`. Ở terminal thứ nhất, triển khai v1.1.0 theo kiểu recreate:

```bash
echo 'APP_TAG=v1.1.0' > .env
time docker compose up -d --wait --wait-timeout 40
```

Quan sát terminal thứ hai (minh họa):

```text
10:15:01.204 {"version": "v1.0.0"} 200
10:15:01.421 {"version": "v1.0.0"} 200
10:15:01.640  000                             ← container cũ đang dừng: curl chờ hết 1 giây
10:15:02.861 <html><head><title>502 Bad Gateway</title>... 502
...                                            ← khoảng 5–7 giây toàn 502/000
10:15:08.112 {"version": "v1.1.0"} 200
```

(Khi chạy thử lab trên Docker Desktop ngày 2026-10-31: `OK=55  LỖI=15` trong 30 giây, gồm 12 dòng `502` và 3 dòng `000`.)

Ctrl+C, ghi lại `LỖI=` vào `week10/deploy-lab.md`. Nhân số lỗi với 0,2 giây ≈ thời gian downtime. Câu hỏi để ghi: downtime gồm những phần nào? (dừng container cũ + 5 giây "khởi động" + chờ nginx phân giải lại tên).

### Bước 4 — Bản phát hành lỗi, rollback thủ công `[WSL]`

Chạy lại `./watch.sh` ở terminal hai. Ở terminal một:

```bash
echo 'APP_TAG=v1.2.0' > .env
docker compose up -d --wait --wait-timeout 40; echo "exit code: $?"
docker compose ps
```

Quan sát:

- Lệnh `up --wait` **thất bại** sau khoảng 15–20 giây, exit code ≠ 0.
- `docker compose ps` hiện `app` ở trạng thái `unhealthy`.
- Điều thú vị ở terminal hai: `/version` **vẫn trả 200 với `v1.2.0`**. Healthcheck của Compose **không chặn traffic** — nginx vẫn gửi request vào container unhealthy. Đây là khác biệt lớn giữa Compose và load balancer/Kubernetes (chúng rút bản unhealthy khỏi danh sách nhận traffic).

Rollback = triển khai lại tag cũ, không build gì:

```bash
echo 'APP_TAG=v1.1.0' > .env
docker compose up -d --wait --wait-timeout 40; echo "exit code: $?"
curl -s localhost:8090/version; echo
```

### Bước 5 — Đọc dấu vết của lần lỗi `[WSL]`

```bash
docker compose logs app --tail 20
```

Nếu đã rollback, container của v1.2.0 đã bị thay. Lần sau, hãy **ghi lại bằng chứng trước khi rollback** (Bước 6 làm tự động). Ghi vào `week10/deploy-lab.md`: lệnh nào cho bạn biết bản lỗi là bản nào và lỗi gì?

### Bước 6 — Script deploy tự rollback `[WSL]`

```bash
cat > deploy.sh <<'EOF'
#!/usr/bin/env bash
# Triển khai demo-app theo tag. Healthcheck hoặc smoke test thất bại → tự quay về tag trước.
set -euo pipefail

new_tag="${1:?Cách dùng: ./deploy.sh <tag>, ví dụ ./deploy.sh v1.1.0}"
port="${BG_PORT:-8090}"
prev_tag="$(sed -n 's/^APP_TAG=//p' .env 2>/dev/null || true)"

deploy() {
  echo "APP_TAG=$1" > .env
  docker compose up -d --wait --wait-timeout 40
}

smoke_test() {
  # Phải trả về ĐÚNG phiên bản vừa triển khai, không chỉ "có trả lời"
  curl -fsS --retry 5 --retry-connrefused --retry-delay 1 "http://localhost:${port}/version" \
    | grep -q "\"$1\""
}

echo ">> Triển khai ${new_tag} (đang chạy: ${prev_tag:-chưa có})"
if deploy "$new_tag" && smoke_test "$new_tag"; then
  echo ">> OK: ${new_tag} healthy và smoke test đạt"
  exit 0
fi

echo ">> LỖI: ${new_tag} không đạt. Log gần nhất của app:" >&2
docker compose logs app --tail 20 >&2 || true

if [[ -z "$prev_tag" || "$prev_tag" == "$new_tag" ]]; then
  echo ">> Không có phiên bản trước để quay về" >&2
  exit 1
fi

echo ">> Rollback về ${prev_tag}" >&2
deploy "$prev_tag"
smoke_test "$prev_tag"
echo ">> Đã rollback về ${prev_tag}. Lần triển khai ${new_tag} THẤT BẠI." >&2
exit 1
EOF
chmod +x deploy.sh
```

Đọc kỹ trước khi chạy và trả lời trong ghi chú:

- Vì sao `deploy "$new_tag" && smoke_test "$new_tag"` nằm trong `if` lại không làm `set -e` dừng script khi `deploy` thất bại?
- Vì sao script kết thúc bằng `exit 1` **dù rollback thành công**? (Gợi ý: pipeline CD đọc exit code để biết lần triển khai có đạt mục tiêu không.)
- `prev_tag` được lấy từ đâu? Điều gì xảy ra nếu file `.env` bị ai đó sửa tay?

Chạy thử (để `watch.sh` chạy ở terminal hai):

```bash
./deploy.sh v1.0.0; echo "exit: $?"     # bản tốt → exit 0
./deploy.sh v1.2.0; echo "exit: $?"     # bản lỗi → tự rollback về v1.0.0, exit 1
cat .env                                 # APP_TAG=v1.0.0
```

### Bước 7 — 🟨 Blue/green bằng nginx `[WSL]`

Dọn phần trước:

```bash
docker compose down
```

Cấu hình nginx chọn upstream qua một file nhỏ. File tên `.inc` (không phải `.conf`) vì image nginx tự nạp mọi `/etc/nginx/conf.d/*.conf` — ta muốn file này chỉ được `include` ở đúng chỗ:

```bash
mkdir -p nginx/bluegreen
cat > nginx/bluegreen/default.conf <<'EOF'
server {
    listen 80;
    resolver 127.0.0.11 valid=2s ipv6=off;

    # active.inc chứa đúng một dòng: set $backend http://app-blue:8080;  (hoặc app-green)
    include /etc/nginx/conf.d/active.inc;

    location / {
        proxy_pass $backend;
        proxy_connect_timeout 1s;
    }
}
EOF
echo 'set $backend http://app-blue:8080;' > nginx/bluegreen/active.inc
```

```bash
cat > compose.bluegreen.yaml <<'EOF'
name: bg05

x-app: &app
  environment:
    STARTUP_DELAY: "5"
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=2)"]
    interval: 2s
    timeout: 3s
    retries: 3
    start_period: 10s
  restart: unless-stopped

services:
  app-blue:
    <<: *app
    image: demo-app:${BLUE_TAG:?Đặt BLUE_TAG trong .env}

  app-green:
    <<: *app
    image: demo-app:${GREEN_TAG:?Đặt GREEN_TAG trong .env}

  nginx:
    image: nginx:1.30-alpine
    ports:
      - "${BG_PORT:-8090}:80"
    volumes:
      - ./nginx/bluegreen:/etc/nginx/conf.d:ro
    depends_on:
      - app-blue
      - app-green
    restart: unless-stopped
EOF
```

`x-app` + `&app` / `<<: *app` là **YAML anchor**: định nghĩa một lần, dùng lại cho hai service. Compose bỏ qua các khóa bắt đầu bằng `x-`.

Script chuyển traffic:

```bash
cat > switch.sh <<'EOF'
#!/usr/bin/env bash
# Chuyển traffic sang app-blue hoặc app-green. Chỉ chuyển khi bản đích đang healthy.
set -euo pipefail

target="${1:?Cách dùng: ./switch.sh blue|green}"
case "$target" in
  blue|green) ;;
  *) echo "Chỉ nhận blue hoặc green" >&2; exit 1 ;;
esac

compose=(docker compose -f compose.bluegreen.yaml)
cid="$("${compose[@]}" ps -q "app-$target")"
if [[ -z "$cid" ]]; then
  echo "app-$target chưa chạy" >&2
  exit 1
fi
state="$(docker inspect -f '{{.State.Health.Status}}' "$cid")"
if [[ "$state" != "healthy" ]]; then
  echo "app-$target đang '$state' — KHÔNG chuyển traffic" >&2
  exit 1
fi

echo "set \$backend http://app-$target:8080;" > nginx/bluegreen/active.inc
"${compose[@]}" exec nginx nginx -t
"${compose[@]}" exec nginx nginx -s reload
echo ">> Traffic đã chuyển sang app-$target"
EOF
chmod +x switch.sh
```

Khởi động: blue chạy v1.0.0 (đang phục vụ), green chạy v1.1.0 (bản mới, chưa nhận traffic):

```bash
printf 'BLUE_TAG=v1.0.0\nGREEN_TAG=v1.1.0\n' > .env
docker compose -f compose.bluegreen.yaml up -d --wait --wait-timeout 40
curl -s localhost:8090/version; echo        # v1.0.0
```

Kiểm tra green **trước khi** nó nhận traffic — gọi thẳng vào container qua mạng nội bộ:

```bash
docker compose -f compose.bluegreen.yaml exec nginx wget -qO- http://app-green:8080/version; echo
```

Bật `./watch.sh` ở terminal hai, rồi chuyển:

```bash
./switch.sh green
```

Terminal hai (minh họa): phiên bản đổi từ `v1.0.0` sang `v1.1.0`, **không có dòng nào khác 200**. Ctrl+C, so sánh `LỖI=` với Bước 3.

Rollback blue/green:

```bash
./switch.sh blue
```

Thử chuyển sang một bản lỗi: đặt `GREEN_TAG=v1.2.0`, `docker compose -f compose.bluegreen.yaml up -d app-green`, chờ vài chục giây, rồi `./switch.sh green`. Script phải **từ chối** vì green `unhealthy`.

### Bước 8 — Dọn dẹp `[WSL]`

```bash
docker compose -f compose.bluegreen.yaml down
docker image rm demo-app:v1.0.0 demo-app:v1.1.0 demo-app:v1.2.0   # nếu không cần nữa
```

Giữ lại thư mục `deploy-lab/` (các script dùng lại ở Bài tập 4 và ở v3).

---

## 10. Kết quả mong đợi

- [ ] Ba image `demo-app:v1.0.0`, `v1.1.0`, `v1.2.0` được build; `v1.2.0` khởi động nhưng `unhealthy`.
- [ ] Đo được downtime của recreate (số dòng lỗi × 0,2 giây) và giải thích được nó gồm những phần nào.
- [ ] `up --wait` với `v1.2.0` thất bại với exit code ≠ 0; bạn quan sát được nginx **vẫn** gửi traffic vào container unhealthy.
- [ ] Rollback thủ công về tag cũ thành công mà không build lại.
- [ ] `./deploy.sh v1.2.0` tự rollback, kết thúc với `exit 1`, `.env` trở về tag trước.
- [ ] Blue/green: chuyển `blue → green → blue` với `LỖI=0` trong `watch.sh`.
- [ ] `./switch.sh` từ chối chuyển sang bản `unhealthy`.
- [ ] `week10/deploy-lab.md` có số liệu downtime và câu trả lời cho các câu hỏi trong Bước 3, 5, 6.

---

## 11. Các lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách sửa |
|---|---|---|
| `required variable APP_TAG is missing a value` khi chạy **bất kỳ** lệnh compose nào (kể cả `ps`, `down`) | `${APP_TAG:?...}` bắt buộc, `.env` chưa có hoặc đang chứa biến của phần khác | Kiểm tra `cat .env`; phần C dùng `BLUE_TAG`/`GREEN_TAG` và `-f compose.bluegreen.yaml` |
| nginx trả 502 **mãi mãi** sau khi app được tạo lại | nginx phân giải tên `app` một lần lúc khởi động, giữ IP cũ | Dùng `resolver 127.0.0.11` + biến `$backend` như bài, hoặc `nginx -s reload` (đã gặp ở [lab Docker](../04-DOCKER/labs/lab-springboot-postgres-compose/README.md)) |
| `docker compose down` / `stop` mất đúng ~10 giây | App là PID 1 không xử lý SIGTERM → Docker chờ hết hạn rồi SIGKILL | Xử lý SIGTERM như `app.py`; xem [Docker 02](../04-DOCKER/02-images-containers.md) |
| `up --wait` thành công nhưng smoke test thấy **phiên bản cũ** | Image tag bị build đè (không còn bất biến), hoặc nhầm file `.env` | Đừng build đè tag đã phát hành; smoke test luôn so khớp phiên bản |
| Sửa `active.inc` nhưng nginx vẫn trỏ bản cũ | Quên `nginx -s reload`; hoặc bind mount **một file** rồi sửa bằng `sed -i` (tạo file mới, inode khác — container vẫn thấy file cũ) | Mount **thư mục** như bài; luôn reload sau khi sửa |
| `nginx: [emerg] unknown "backend" variable` | `active.inc` rỗng/sai, hoặc `include` đặt sau `location` dùng biến | Kiểm tra nội dung file; `nginx -t` trước khi reload |
| `switch.sh` báo `starting` | Bản đích chưa qua `start_period` + healthcheck đầu tiên | Chờ vài giây; script đúng khi từ chối |
| Port 8090 đã bị chiếm | Một process khác dùng 8090 | `BG_PORT=8091` trước lệnh, hoặc tìm process bằng `sudo ss -ltnp \| grep 8090` |

---

## 12. Đọc log và xử lý lỗi

### 12.1. Một lần triển khai thất bại — đọc theo thứ tự nào?

```text
1. Exit code của lệnh deploy          → thất bại ở bước nào: pull? start? health? smoke?
2. docker compose ps                   → container nào unhealthy/exited/restarting?
3. docker inspect --format '{{json .State.Health}}' <container>
                                       → 5 lần healthcheck gần nhất: lệnh nào, output gì
4. docker compose logs <service>       → log ứng dụng quanh thời điểm đó
5. Đối chiếu với phiên bản trước       → thay đổi gì giữa hai tag? (git log v1.1.0..v1.2.0)
```

Ví dụ bước 3 với v1.2.0 (minh họa, đã rút gọn):

```bash
docker inspect --format '{{json .State.Health}}' bg05-app-1
```

```json
{"Status":"unhealthy","FailingStreak":4,"Log":[{"ExitCode":1,"Output":"Traceback ...\nurllib.error.HTTPError: HTTP Error 500: Internal Server Error\n"}]}
```

`HTTP Error 500` từ chính endpoint `/health` → app chạy nhưng **tự báo không khỏe**. Khác hẳn với `Connection refused` (app chưa nghe cổng — khởi động chậm hoặc crash).

### 12.2. Phân biệt "bản mới lỗi" và "hạ tầng lỗi"

| Dấu hiệu | Khả năng cao |
|---|---|
| Bản cũ healthy, bản mới unhealthy, cùng hạ tầng | Lỗi ở bản mới → **rollback** |
| Cả bản cũ lẫn bản mới đều unhealthy | Lỗi hạ tầng (database chết, hết disk, mạng) → rollback **không giúp gì**, đi tìm nguyên nhân ở tầng dưới |
| Unhealthy chỉ sau vài phút chạy | Rò rỉ tài nguyên, phụ thuộc bên ngoài chập chờn — xem log theo thời gian |

Rollback một vấn đề hạ tầng là lỗi phổ biến của người mới: mất thời gian, không giải quyết gì, còn xóa mất bằng chứng.

### 12.3. Ghi lại

Mỗi lần rollback (kể cả trong lab) là một dòng trong `troubleshooting-journal.md` theo [mẫu](../00-ROADMAP/templates/troubleshooting-journal-template.md): phiên bản lỗi, dấu hiệu, lệnh đã dùng để xác định, thời gian từ lúc phát hiện tới lúc khôi phục.

---

## 13. Câu hỏi kiểm tra kiến thức

1. Deploy và release khác nhau thế nào? Nêu hai cách tách chúng ra.
2. Với recreate, downtime gồm những phần nào? Ước lượng cho `taskhub` (Spring Boot).
3. Rolling update yêu cầu điều kiện gì về tương thích giữa hai phiên bản? Vì sao?
4. Blue/green rollback nhanh nhờ đâu? Đánh đổi lớn nhất của nó là gì?
5. Canary khác blue/green ở điểm nào? Vì sao canary vô nghĩa nếu không có monitoring?
6. Liveness và readiness khác nhau thế nào? Compose `healthcheck` có chặn traffic vào container unhealthy không (dựa vào lab)?
7. Smoke test khác test trong CI thế nào? Vì sao smoke test nên kiểm tra **phiên bản**?
8. Vì sao rollback bằng cách build lại từ commit cũ là ý tồi?
9. Bản v0.5.0 có migration `DROP COLUMN title`. Rollback image về v0.4.0 thì sao? Lẽ ra phải làm thế nào?
10. Flyway Community có undo migration không? Nếu có undo, nó có cứu được dữ liệu của cột đã xóa không?
11. Khi nào bạn chọn roll forward thay vì rollback?
12. Trong `deploy.sh`, vì sao script `exit 1` dù rollback thành công?
13. `nginx -s reload` khác `docker compose restart nginx` thế nào về ảnh hưởng tới request đang xử lý?
14. Vì sao `taskhub` v3 (một EC2) dùng recreate mà không dùng rolling?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/05-solutions.md](solutions/05-solutions.md) — chỉ mở sau khi đã tự làm.

**Bài 1 — Chọn chiến lược.** Với mỗi hệ thống, chọn chiến lược triển khai và giải thích bằng 3–4 câu (downtime chấp nhận được? tài nguyên? database?): (a) công cụ nội bộ cho 20 nhân viên, dùng giờ hành chính; (b) API thanh toán, 24/7, chạy 6 bản sao sau ALB; (c) ứng dụng di động có tính năng mới muốn thử trên 1% người dùng; (d) `taskhub` v3 trên một EC2 nhỏ (ví dụ loại 1 GiB RAM như `t3.micro` — loại cụ thể sẽ chọn ở Module 06).

**Bài 2 — Expand/contract.** `taskhub` muốn tách cột `description` (TEXT) thành bảng `task_notes` (một task nhiều ghi chú). Viết kế hoạch theo các release `v0.6.0`, `v0.7.0`, `v0.8.0`: mỗi release gồm migration Flyway nào (tên file + nội dung SQL chính), app đọc/ghi gì, và rollback về release trước có an toàn không.

**Bài 3 — Đo downtime chính xác hơn.** Cải tiến `watch.sh` để khi Ctrl+C in ra thêm: thời điểm bắt đầu và kết thúc **chuỗi lỗi dài nhất**, và độ dài chuỗi đó tính bằng giây (dùng `date +%s.%N`, tính bằng `awk` hoặc `bc` nếu có). Chạy lại Bước 3 và so sánh với cách ước lượng "số lỗi × 0,2".

**Bài 4 — Áp dụng cho `taskhub` thật.** Trong repo `taskhub` (Compose v0), đổi `image:` của service `taskhub` thành `ghcr.io/<github-user>/taskhub:${TASKHUB_IMAGE_TAG:?...}` (dùng image do CI đã push ở bài 03). Viết `scripts/deploy.sh` theo mẫu `deploy.sh` của bài: smoke test gọi `/actuator/health` qua nginx (cổng 8000) **và** kiểm tra `docker inspect` của container `taskhub` đang chạy đúng image tag mong muốn. Thử với một tag tốt, một tag không tồn tại (lỗi ở bước pull), và một tag tốt nhưng đặt sai `SPRING_DATASOURCE_PASSWORD` (lỗi ở health). Ghi kết quả. **Không** commit mật khẩu.

**Bài 5 — Blue/green cho `taskhub` (🟨, chuẩn bị cho v3).** Thiết kế (chưa cần chạy hoàn chỉnh) `compose.bluegreen.yaml` cho `taskhub` với `taskhub-blue`, `taskhub-green`, một `postgres`, một `nginx`. Trả lời: hai bản dùng chung database thì migration Flyway chạy lúc nào, bởi bản nào? Điều gì xảy ra nếu bản green chạy migration không tương thích với blue đang phục vụ? Bạn quy định gì cho các migration để blue/green an toàn?

---

## 15. Tiêu chí đánh giá đã hiểu bài

- [ ] Vẽ và giải thích được 4 chiến lược chính trên giấy trong 5 phút, kèm bảng đánh đổi.
- [ ] Đo được downtime của recreate bằng số liệu thật, không phải ước đoán.
- [ ] Tự viết lại `deploy.sh` (không nhìn bài) với đủ: ghi tag cũ, chờ health, smoke test đúng phiên bản, tự rollback, exit code đúng.
- [ ] Giải thích được vì sao rollback image không rollback database, và lập được kế hoạch expand/contract cho một thay đổi schema.
- [ ] Trả lời câu phỏng vấn "Nếu bản mới lỗi sau khi deploy, bạn làm gì?" theo thứ tự: phát hiện → khôi phục (rollback hay roll forward, vì sao) → điều tra → ngăn tái diễn.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Martin Fowler — BlueGreenDeployment](https://martinfowler.com/bliki/BlueGreenDeployment.html) | Định nghĩa blue/green, rollback bằng đổi router, thách thức database | 2026-10-31 |
| [Danilo Sato — CanaryRelease (martinfowler.com)](https://martinfowler.com/bliki/CanaryRelease.html) | Định nghĩa canary release | 2026-10-31 |
| [Danilo Sato — ParallelChange (martinfowler.com)](https://martinfowler.com/bliki/ParallelChange.html) | Mẫu expand → migrate → contract | 2026-10-31 |
| [Pete Hodgson — Feature Toggles (martinfowler.com)](https://martinfowler.com/articles/feature-toggles.html) | 4 loại feature toggle | 2026-10-31 |
| [Redgate — Flyway feature summary](https://documentation.red-gate.com/fd/feature-summary-165740620.html) | Undo migrations chỉ có ở Flyway Teams/Enterprise, không có ở Community | 2026-10-31 |
| [Docker Docs — docker compose up](https://docs.docker.com/reference/cli/docker/compose/up/) | `--wait`, `--wait-timeout`, hành vi tạo lại container khi đổi image/cấu hình | 2026-10-31 |
| [Kubernetes Docs — Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) | Rolling update, `maxSurge`/`maxUnavailable`, `kubectl rollout undo` (xem trước Module 09) | 2026-10-31 |
| [nginx — Controlling nginx](https://nginx.org/en/docs/control.html) | `-s reload`: worker cũ xử lý xong request rồi thoát | 2026-10-31 |
