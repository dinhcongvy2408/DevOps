# Lời giải — Bài 01: VM vs Container & kiến trúc Docker

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [01-vm-vs-container-architecture.md](../01-vm-vs-container-architecture.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Container giải quyết vấn đề gì?**
Đóng gói app cùng runtime, thư viện và cấu hình mặc định thành một image bất biến. Cùng một image chạy giống nhau ở laptop, CI, EC2, Kubernetes → hết cảnh "chạy trên máy tôi". Cài trực tiếp lên server thì mỗi server một trạng thái, phụ thuộc người cài và lịch sử thay đổi.

**2. Bốn khác biệt VM và container; khi nào vẫn chọn VM?**
Kernel riêng vs dùng chung; kích thước GB vs MB; khởi động phút vs giây; cô lập bằng hypervisor (mạnh) vs bằng namespace/cgroup (yếu hơn); VM chạy được hệ điều hành khác. Chọn VM khi cần cô lập mạnh giữa các khách hàng/bên không tin nhau, cần hệ điều hành khác (Windows), phần mềm cũ không đóng gói được, hoặc chính là nền để chạy container (EC2).

**3. "Container là VM nhẹ" sai ở đâu?**
Container không có kernel riêng, không giả lập phần cứng, không "boot". Nó là process bình thường của host, chỉ bị kernel giới hạn tầm nhìn (namespace) và tài nguyên (cgroup).

**4. Namespace vs cgroup?**
Namespace trả lời "process nhìn thấy gì" (process khác, mạng, filesystem, hostname). cgroup trả lời "process được dùng bao nhiêu" (RAM, CPU, số process, I/O).

**5. Bốn namespace và hệ quả:**
`pid` → app là PID 1, chỉ thấy process của container; `net` → IP/eth0/port riêng; `mnt` → `/` là filesystem của image; `uts` → hostname riêng; (`ipc`, `user`, `cgroup` cũng được chấp nhận).

**6. Vì sao `free -h` có thể sai?**
`free` đọc `/proc/meminfo`, file này không bị namespace che nên phản ánh RAM của cả host (ở máy bạn: của VM WSL). Giới hạn thật nằm ở cgroup (`/sys/fs/cgroup/memory.max` với cgroup v2) hoặc cột LIMIT của `docker stats`.

**7. Vượt RAM vs vượt CPU?**
Vượt RAM: OOM killer giết process → container `Exited (137)`, `OOMKilled=true`, thường không có log lỗi. Vượt CPU: process bị throttle → chậm, timeout, latency tăng, nhưng không chết.

**8. Chuỗi CLI → dockerd → containerd → runc:**
CLI gửi yêu cầu REST qua socket tới dockerd; dockerd kiểm tra/kéo image, chuẩn bị network/volume rồi giao cho containerd; containerd chuẩn bị filesystem từ layer và gọi runc (qua shim); runc tạo namespace + cgroup và exec process chính rồi thoát; shim giữ container sống và thu stdout/stderr.

**9. OCI và Kubernetes:**
OCI chuẩn hóa định dạng image và cách chạy container. Nhờ vậy image build bằng Docker chạy được trên containerd/CRI-O mà Kubernetes dùng, không cần Docker trên node.

**10. Vì sao `/var/run/docker.sock` tương đương root?**
Ai gửi được API vào socket thì ra lệnh được cho dockerd (chạy bằng root): ví dụ chạy container `--privileged` hoặc mount `/` của host vào container và sửa mọi file. Nên nhóm `docker` và việc mount socket vào container phải được coi như cấp quyền root.

**11. Container `exited` còn gì? Khi nào mất?**
Còn: cấu hình, layer ghi được (file đã sửa), log stdout/stderr, trạng thái (exit code). Mất hẳn khi `docker rm` (hoặc chạy với `--rm`).

**12. `sleep 300` + `docker stop` = 10 giây và 137?**
`docker stop` gửi SIGTERM. `sleep` là PID 1 trong namespace PID và không đăng ký xử lý SIGTERM; kernel bỏ qua signal có hành động mặc định đối với init của namespace → không có gì xảy ra. Hết 10 giây Docker gửi SIGKILL (không thể bỏ qua) → 128 + 9 = 137.

**13. `ps aux` trên Ubuntu vs EC2?**
Trên máy bạn, Docker Engine và container chạy trong distro `docker-desktop`, khác namespace/distro với Ubuntu của bạn nên `ps` trong Ubuntu không thấy. Trên EC2, dockerd chạy ngay trên Ubuntu đó; container là process con trên cùng host nên `ps` thấy.

**14. `ubuntu:22.04` trên Amazon Linux?**
Được — image chỉ chứa userspace Ubuntu; process dùng kernel Amazon Linux. Cần khớp kiến trúc CPU (`amd64` vs `arm64`) và kernel đủ mới cho các tính năng image cần (hiếm khi là vấn đề).

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Bảng so sánh

Đạt khi có ≥ 6 tiêu chí đúng và cột AWS hợp lý, ví dụ:

| Tiêu chí | VM | Container | Ví dụ trên AWS |
|---|---|---|---|
| Kernel | Riêng | Dùng chung | EC2 = VM; container chạy trên EC2 |
| Khởi động | Phút | Giây | Launch EC2 ~1 phút; container ECS/K8s vài giây |
| Kích thước | GB (AMI) | MB (image) | AMI vs image trong ECR |
| Cô lập | Hypervisor (Nitro) | Namespace/cgroup | Fargate chạy mỗi task trong micro-VM riêng để cô lập mạnh hơn |
| Đơn vị scale | Instance | Container/Pod | Auto Scaling Group vs số task ECS / replica |
| Hệ điều hành khác | Có | Không (cùng kernel Linux) | EC2 Windows vs container Linux |

(Chi tiết Fargate là kiến thức bổ sung, không bắt buộc.)

### Bài 2 — Đếm namespace

```bash
docker run --rm alpine:3.20 ls -l /proc/1/ns
```

```text
lrwxrwxrwx ... cgroup -> cgroup:[4026532451]
lrwxrwxrwx ... ipc -> ipc:[4026532389]
lrwxrwxrwx ... mnt -> mnt:[4026532387]
lrwxrwxrwx ... net -> net:[4026532392]
lrwxrwxrwx ... pid -> pid:[4026532390]
lrwxrwxrwx ... user -> user:[4026531837]
lrwxrwxrwx ... uts -> uts:[4026532388]
...
```

(Minh họa — số trên máy bạn khác.)

So sánh:

```bash
docker run --rm alpine:3.20 readlink /proc/1/ns/net
docker run --rm alpine:3.20 readlink /proc/1/ns/net
docker run --rm --network host alpine:3.20 readlink /proc/1/ns/net
docker run --rm --pid=host alpine:3.20 readlink /proc/1/ns/net   # net của process 1 của HOST Engine
```

Kết luận đúng:
- Hai container thường có **ID net khác nhau** → mỗi container một network namespace.
- Container `--network host` có ID net **giống** của host Engine → dùng chung mạng host, không có IP riêng.
- `user` thường **giống** giữa các container và host → Docker mặc định không dùng user namespace (root trong container là UID 0 thật — bài 07).

### Bài 3 — Giới hạn số process

```bash
docker run --rm -it --pids-limit 20 alpine:3.20 sh
# trong container:
for i in $(seq 1 50); do sleep 100 & done
```

Sau khoảng 18–19 process (shell và các process sẵn có chiếm phần còn lại), sẽ thấy lỗi kiểu:

```text
sh: can't fork: Resource temporarily unavailable
```

(Câu chữ minh họa, tùy shell.) `fork()` thất bại với `EAGAIN` vì cgroup `pids.max` đã đạt giới hạn. Fork bomb (process tự nhân bản vô hạn) trong một container không có giới hạn có thể làm cạn bảng process của **cả host**, khiến container khác và host không tạo được process mới. `--pids-limit` khoanh vùng thiệt hại trong container đó.

### Bài 4 — Exit code detective

| Exit code | Lệnh | Giải thích |
|---|---|---|
| 0 | `docker run --rm alpine:3.20 true` | Process thoát bình thường |
| 1 | `docker run --rm alpine:3.20 sh -c 'exit 1'` hoặc `false` | App tự báo lỗi |
| 125 | `docker run --rm --khong-co-co-nay alpine:3.20` | Lỗi của chính lệnh `docker run` (cờ không tồn tại) |
| 126 | `docker run --rm alpine:3.20 /etc/hostname` | File tồn tại nhưng không thực thi được (không có quyền x, không phải chương trình) |
| 127 | `docker run --rm alpine:3.20 khongcolenhnay` | Không tìm thấy lệnh trong `PATH` của container |
| 137 | `docker run --name k alpine:3.20 sleep 300` rồi `docker kill k` (hoặc OOM như lab Bước 8) | SIGKILL = 128 + 9 |
| 143 | `docker run -d --name t alpine:3.20 sh -c 'trap "exit 143" TERM; sleep 300 & wait'` rồi `docker stop t` | Shell bắt SIGTERM và thoát 143 = 128 + 15 |

Ghi chú:
- 126 và 127 do Docker/runtime báo khi exec process chính thất bại; một số phiên bản in thêm thông báo `OCI runtime create failed: ... executable file not found` (127) hoặc `permission denied` (126). Câu chữ có thể khác — quan trọng là exit code.
- Ở dòng 143 phải có `sleep 300 & wait`: nếu `sh` đang chạy `sleep` ở foreground, nó chỉ xử lý trap sau khi `sleep` kết thúc. `wait` bị signal làm gián đoạn ngay → trap chạy ngay.
- Dùng `echo $?` ngay sau `docker run` (khi không có `-d`) hoặc `docker inspect --format '{{.State.ExitCode}}' <tên>`.

### Bài 5 — Java và giới hạn RAM

```bash
docker run --rm --memory 256m eclipse-temurin:21-jre-noble \
  java -XX:+PrintFlagsFinal -version | grep -E 'MaxHeapSize|UseContainerSupport'
docker run --rm eclipse-temurin:21-jre-noble \
  java -XX:+PrintFlagsFinal -version | grep -E 'MaxHeapSize|UseContainerSupport'
```

Kết quả dạng (minh họa):

```text
size_t MaxHeapSize = 67108864        {product} {ergonomic}     # 64MB ≈ 1/4 của 256MB
bool UseContainerSupport = true      {product} {default}
size_t MaxHeapSize = 2061500416      {product} {ergonomic}     # ≈ 1/4 RAM mà VM WSL có
```

- JVM hiện đại (`UseContainerSupport` bật mặc định) đọc giới hạn RAM từ **cgroup**, không phải `/proc/meminfo` → heap mặc định ≈ 25% giới hạn container.
- Ý nghĩa với `taskhub`: nếu đặt `--memory 512m` mà không chỉnh heap, heap tối đa chỉ ~128MB — có thể thiếu cho Spring Boot. Ngược lại, nếu tự đặt `-Xmx` lớn gần bằng giới hạn container, heap + metaspace + thread stack + bộ nhớ ngoài heap vượt giới hạn → OOMKilled (exit 137) mà log Java không ghi gì. Cách cân bằng phổ biến: dùng `-XX:MaxRAMPercentage` (ví dụ 70–75%) thay cho `-Xmx` cố định. Sẽ quay lại khi viết Dockerfile (bài 03) và khi đặt giới hạn tài nguyên trên EC2/Kubernetes.
