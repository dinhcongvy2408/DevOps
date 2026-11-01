# Lab 02 — Chạy ứng dụng Java thành systemd service

> Tuần 2 · ⏱️ ~2–3 giờ · Mức độ: 🟥 Bắt buộc · Môi trường: `[WSL]` (cần systemd)
> Kiến thức cần có: [03. Permissions, Users & Groups](../03-permissions-users-groups.md), [04. Processes & systemd](../04-processes-systemd.md)

## Mục lục

- [1. Mục tiêu](#1-mục-tiêu)
- [2. Kiến trúc lab](#2-kiến-trúc-lab)
- [3. Chuẩn bị](#3-chuẩn-bị)
- [4. Các bước thực hiện](#4-các-bước-thực-hiện)
- [5. Kết quả mong đợi](#5-kết-quả-mong-đợi)
- [6. Lỗi thường gặp](#6-lỗi-thường-gặp)
- [7. Dọn dẹp](#7-dọn-dẹp)
- [8. Câu hỏi sau lab](#8-câu-hỏi-sau-lab)

---

## 1. Mục tiêu

Triển khai một ứng dụng Java như cách làm trên server thật:

- Ứng dụng chạy bằng **user hệ thống riêng** (`taskhub`), không phải root, không phải user của bạn.
- File đặt đúng chỗ theo quy ước Linux: app ở `/opt/taskhub/`, cấu hình ở `/etc/`.
- Do **systemd** quản lý: tự khởi động lại khi chết bất thường, log vào journal.
- Kiểm chứng bằng cách cố tình làm app chết theo 3 kiểu khác nhau.

Đây là "tiền thân" của cách bạn sẽ chạy `taskhub` thật trên EC2 trước khi chuyển sang container.

> Đầu ra mẫu trong lab là **minh họa**. PID, thời gian, đường dẫn Java trên máy bạn sẽ khác.

---

## 2. Kiến trúc lab

```text
            curl localhost:8081/health
                       │
┌──────────────────────▼─────────────────────────────────────┐
│ WSL Ubuntu 24.04                                           │
│                                                            │
│  systemd (PID 1)                                           │
│    └── taskhub-demo.service                                │
│          User=taskhub                                      │
│          EnvironmentFile=/etc/taskhub-demo.env (APP_PORT)  │
│          ExecStart=/usr/bin/java -jar /opt/taskhub/app.jar │
│          Restart=on-failure                                │
│              │ stdout/stderr                               │
│              ▼                                             │
│          journal ──► journalctl -u taskhub-demo            │
└────────────────────────────────────────────────────────────┘
```

| Endpoint | Hành vi |
|---|---|
| `GET /health` | Trả `OK` — dùng để kiểm tra app còn sống |
| `GET /crash` | App tự thoát với exit code 1 — giả lập lỗi nghiêm trọng |

Port mặc định `8081` (để dành `8080` cho Spring Boot ở các module sau).

---

## 3. Chuẩn bị

### 3.1. Kiểm tra systemd

```bash
ps -p 1 -o comm=
```

Phải in ra `systemd`. Nếu in `init`, xem [bài 04, mục 9 bước 6](../04-processes-systemd.md#bước-6--kiểm-tra-systemd-trên-wsl).

### 3.2. Kiểm tra Java trong WSL

Java bạn cài trên Windows (dùng cho IntelliJ) **không** dùng được trực tiếp trong WSL như một service. Kiểm tra trong WSL:

```bash
java -version
javac -version
```

```text
openjdk version "21.0.x" ...
javac 21.0.x
```

Nếu báo `Command 'java' not found`: cần cài JDK trong WSL. **Đây là cài thêm phần mềm vào WSL — bạn tự quyết định.** Lệnh cài (gói headless không kèm thư viện giao diện đồ họa, nhẹ hơn):

```bash
sudo apt update
sudo apt install -y openjdk-21-jdk-headless
```

Sau đó tìm đường dẫn tuyệt đối của `java` (cần cho unit file):

```bash
which java
readlink -f "$(which java)"
```

```text
/usr/bin/java
/usr/lib/jvm/java-21-openjdk-amd64/bin/java
```

`/usr/bin/java` là symlink do hệ thống "alternatives" quản lý, trỏ tới bản Java thật. Dùng `/usr/bin/java` trong unit file là được.

### 3.3. Kiểm tra port 8081 còn trống

```bash
ss -tln | grep 8081 || echo "Port 8081 trống"
```

---

## 4. Các bước thực hiện

### Bước 1 — Viết ứng dụng

```bash
mkdir -p ~/devops-lab/01-linux/lab02/src
cd ~/devops-lab/01-linux/lab02
```

Tạo file `src/App.java` (bằng `nano src/App.java` hoặc VS Code: `code .`):

```java
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class App {

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("APP_PORT", "8081"));
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        server.createContext("/health", exchange -> respond(exchange, 200, "OK\n"));

        server.createContext("/crash", exchange -> {
            respond(exchange, 500, "Crashing with exit code 1\n");
            System.out.println("Received /crash -> exiting with code 1");
            System.exit(1);
        });

        Runtime.getRuntime().addShutdownHook(new Thread(() ->
                System.out.println("Shutdown hook: stopping HTTP server gracefully")));

        server.start();
        System.out.println("taskhub-demo started on port " + port
                + " pid=" + ProcessHandle.current().pid()
                + " user=" + System.getProperty("user.name"));
    }

    private static void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream os = exchange.getResponseBody()) {
            os.write(bytes);
        }
    }
}
```

Giải thích nhanh những gì liên quan tới vận hành:

- `APP_PORT` đọc từ **biến môi trường** → đổi port không cần sửa code (biến môi trường học kỹ ở [bài 06](../06-bash-scripting.md)). Đây là nguyên tắc cấu hình bạn sẽ gặp lại trong Docker và Kubernetes.
- **Shutdown hook** chạy khi JVM nhận `SIGTERM` → mô phỏng graceful shutdown.
- Dòng log khởi động in ra `pid` và `user` → giúp bạn kiểm chứng app chạy bằng user nào.

### Bước 2 — Biên dịch và đóng gói thành jar

```bash
javac -d out src/App.java
jar --create --file app.jar --main-class App -C out .
ls -l app.jar
```

| Lệnh / tham số | Ý nghĩa |
|---|---|
| `javac -d out` | Biên dịch, đặt file `.class` vào thư mục `out/` |
| `jar --create --file app.jar` | Tạo file jar tên `app.jar` |
| `--main-class App` | Ghi vào manifest: class chạy đầu tiên là `App` → chạy được bằng `java -jar` |
| `-C out .` | Chuyển vào `out/` rồi đóng gói mọi thứ trong đó |

### Bước 3 — Chạy thử bằng tay (luôn làm trước khi viết service)

```bash
java -jar app.jar
```

```text
taskhub-demo started on port 8081 pid=5120 user=phuong
```

Mở terminal thứ hai:

```bash
curl -i localhost:8081/health
```

```text
HTTP/1.1 200 OK
Date: Fri, 31 Oct 2026 03:15:02 GMT
Content-length: 3

OK
```

Quay lại terminal đầu, bấm `Ctrl+C`. Có thấy dòng "Shutdown hook…" không?

> **Nguyên tắc vàng:** nếu app không chạy được bằng tay, nó cũng sẽ không chạy được dưới systemd. Luôn chạy tay trước.

### Bước 4 — Tạo user hệ thống `taskhub`

Nếu đã tạo ở [bài 03](../03-permissions-users-groups.md), kiểm tra bằng `id taskhub` và bỏ qua lệnh tạo.

```bash
id taskhub 2>/dev/null || sudo useradd --system --no-create-home --shell /usr/sbin/nologin taskhub
id taskhub
```

```text
uid=998(taskhub) gid=998(taskhub) groups=998(taskhub)
```

| Tham số | Ý nghĩa |
|---|---|
| `--system` | User hệ thống: UID thấp, dành cho dịch vụ, không dành cho người đăng nhập |
| `--no-create-home` | Không tạo `/home/taskhub` — dịch vụ không cần |
| `--shell /usr/sbin/nologin` | Không ai đăng nhập được bằng user này |

### Bước 5 — Đặt ứng dụng vào `/opt/taskhub`

```bash
sudo mkdir -p /opt/taskhub
sudo cp ~/devops-lab/01-linux/lab02/app.jar /opt/taskhub/app.jar
sudo chown -R root:taskhub /opt/taskhub
sudo chmod 750 /opt/taskhub
sudo chmod 640 /opt/taskhub/app.jar
ls -la /opt/taskhub
```

```text
drwxr-x---  2 root taskhub 4096 Oct 31 10:20 .
drwxr-xr-x  3 root root    4096 Oct 31 10:20 ..
-rw-r-----  1 root taskhub 1832 Oct 31 10:20 app.jar
```

❓ Vì sao chủ sở hữu là `root` còn group là `taskhub`, thay vì cho `taskhub` sở hữu luôn? Gợi ý: app chỉ cần **đọc** file jar. Nếu app bị chiếm quyền, kẻ tấn công có sửa được file jar không? (Liên hệ nguyên tắc least privilege ở bài 03.)

### Bước 6 — File cấu hình môi trường

```bash
echo "APP_PORT=8081" | sudo tee /etc/taskhub-demo.env
sudo chmod 640 /etc/taskhub-demo.env
sudo chown root:taskhub /etc/taskhub-demo.env
```

Sau này file kiểu này sẽ chứa cả mật khẩu database — đó là lý do không cho mọi người đọc (`640`).

### Bước 7 — Viết unit file

```bash
sudo nano /etc/systemd/system/taskhub-demo.service
```

Nội dung (comment phải nằm trên dòng riêng):

```ini
[Unit]
Description=Taskhub demo HTTP service (Lab 02)
After=network.target

[Service]
Type=simple
User=taskhub
Group=taskhub
WorkingDirectory=/opt/taskhub
EnvironmentFile=/etc/taskhub-demo.env
ExecStart=/usr/bin/java -jar /opt/taskhub/app.jar
# Tự khởi động lại khi chết bất thường, chờ 5 giây giữa các lần
Restart=on-failure
RestartSec=5
# JVM thoát với code 143 sau khi nhận SIGTERM - đó là tắt bình thường
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
```

Nạp và khởi động:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now taskhub-demo
systemctl status taskhub-demo --no-pager
```

```text
● taskhub-demo.service - Taskhub demo HTTP service (Lab 02)
     Loaded: loaded (/etc/systemd/system/taskhub-demo.service; enabled; vendor preset: enabled)
     Active: active (running) since Fri 2026-10-31 10:25:40 +07; 3s ago
   Main PID: 6301 (java)
      Tasks: 18 (limit: 9456)
     Memory: 38.2M
     CGroup: /system.slice/taskhub-demo.service
             └─6301 /usr/bin/java -jar /opt/taskhub/app.jar

Oct 31 10:25:40 LEGION systemd[1]: Started Taskhub demo HTTP service (Lab 02).
Oct 31 10:25:41 LEGION java[6301]: taskhub-demo started on port 8081 pid=6301 user=taskhub
```

Kiểm tra:

```bash
curl -s localhost:8081/health
ps -o pid,user,etime,cmd -C java
```

❓ App đang chạy bằng user nào? Dòng log nào chứng minh điều đó?

### Bước 8 — Thử nghiệm 1: bị `kill -9` (chết bất thường)

```bash
PID=$(systemctl show -p MainPID --value taskhub-demo)
echo "PID hiện tại: $PID"
sudo kill -KILL "$PID"
systemctl status taskhub-demo --no-pager | head -5     # chạy ngay
sleep 6
systemctl status taskhub-demo --no-pager | head -5     # sau 6 giây
systemctl show -p NRestarts --value taskhub-demo
curl -s localhost:8081/health
```

Ngay sau khi kill, dòng `Active` sẽ là `activating (auto-restart)`. Sau ~5 giây là `active (running)` với PID mới.

### Bước 9 — Thử nghiệm 2: app tự thoát với lỗi

```bash
curl -s localhost:8081/crash
sleep 6
journalctl -u taskhub-demo -n 15 --no-pager
```

```text
Oct 31 10:31:02 LEGION java[6377]: Received /crash -> exiting with code 1
Oct 31 10:31:02 LEGION java[6377]: Shutdown hook: stopping HTTP server gracefully
Oct 31 10:31:02 LEGION systemd[1]: taskhub-demo.service: Main process exited, code=exited, status=1/FAILURE
Oct 31 10:31:02 LEGION systemd[1]: taskhub-demo.service: Failed with result 'exit-code'.
Oct 31 10:31:07 LEGION systemd[1]: taskhub-demo.service: Scheduled restart job, restart counter is at 2.
Oct 31 10:31:07 LEGION systemd[1]: Stopped Taskhub demo HTTP service (Lab 02).
Oct 31 10:31:07 LEGION systemd[1]: Started Taskhub demo HTTP service (Lab 02).
Oct 31 10:31:08 LEGION java[6402]: taskhub-demo started on port 8081 pid=6402 user=taskhub
```

(Shutdown hook cũng chạy khi gọi `System.exit()`, nên dòng "Shutdown hook…" xuất hiện cả ở đây.)

### Bước 10 — Thử nghiệm 3: dừng chủ động

```bash
sudo systemctl stop taskhub-demo
systemctl status taskhub-demo --no-pager | head -5
journalctl -u taskhub-demo -n 5 --no-pager
sleep 6
systemctl is-active taskhub-demo
```

Service phải ở trạng thái `inactive (dead)` và **không** tự chạy lại.

### Bước 11 — Thử nghiệm 4: bỏ `SuccessExitStatus` để thấy khác biệt

```bash
sudo sed -i 's/^SuccessExitStatus=143/#SuccessExitStatus=143/' /etc/systemd/system/taskhub-demo.service
sudo systemctl daemon-reload
sudo systemctl start taskhub-demo && sleep 2
sudo systemctl stop taskhub-demo
systemctl status taskhub-demo --no-pager | head -5
```

❓ Trạng thái sau khi stop bây giờ là gì? Vì sao? Sau khi quan sát, **khôi phục** lại dòng đó:

```bash
sudo sed -i 's/^#SuccessExitStatus=143/SuccessExitStatus=143/' /etc/systemd/system/taskhub-demo.service
sudo systemctl daemon-reload
sudo systemctl reset-failed taskhub-demo
sudo systemctl start taskhub-demo
```

### Bước 12 — Ghi kết quả và commit

Tạo `~/devops-journey/week02/lab02-java-systemd.md` gồm: unit file cuối cùng, kết quả 4 thử nghiệm (copy đoạn journal liên quan), câu trả lời các câu hỏi ❓, và ít nhất 1 lỗi bạn gặp phải trong quá trình làm (ghi theo mẫu troubleshooting journal).

```bash
cd ~/devops-journey
cp ~/devops-lab/01-linux/lab02/src/App.java week02/
git add week02/ && git commit -m "feat(linux): lab 02 - java app as systemd service" && git push
```

---

## 5. Kết quả mong đợi

| Thử nghiệm | Trạng thái sau đó | Tự khởi động lại? | Lý do |
|---|---|---|---|
| Bình thường | `active (running)`, user `taskhub` | — | — |
| `kill -9` | `activating (auto-restart)` → `active (running)`, PID mới | **Có**, sau ~5 giây | Chết vì `SIGKILL` = bất thường với `on-failure` |
| `/crash` | Như trên, `status=1/FAILURE` trong journal | **Có** | Exit code khác 0 |
| `systemctl stop` | `inactive (dead)` | **Không** | Dừng chủ động không kích hoạt restart |
| `stop` khi không có `SuccessExitStatus=143` | `failed`, `status=143` | Không | JVM thoát 143, systemd coi là lỗi |

Câu hỏi ở bước 5: `root` sở hữu file, `taskhub` chỉ có quyền đọc qua group → app đọc được jar để chạy nhưng **không sửa/xóa được** nó. Nếu app bị chiếm quyền, kẻ tấn công không thể cài mã độc vào file jar để tồn tại sau lần khởi động lại.

---

## 6. Lỗi thường gặp

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `status=203/EXEC` | `ExecStart` trỏ tới file Java không tồn tại (ví dụ gõ nhầm `/usr/local/bin/java`) hoặc không có quyền thực thi | `which java`, `ls -l` đường dẫn trong `ExecStart` |
| `status=217/USER` | Chưa tạo user `taskhub` | Bước 4 |
| `status=200/CHDIR` | `/opt/taskhub` chưa tồn tại hoặc `taskhub` không có quyền `x` trên thư mục | Bước 5, kiểm tra `ls -ld /opt/taskhub` |
| `Error: Unable to access jarfile /opt/taskhub/app.jar` trong journal, `status=1` | User `taskhub` không đọc được file jar | `sudo -u taskhub cat /opt/taskhub/app.jar > /dev/null` để kiểm chứng; sửa quyền ở bước 5 |
| `Failed to load environment files` | Sai đường dẫn `EnvironmentFile` | `ls -l /etc/taskhub-demo.env`. Thêm dấu `-` phía trước (`EnvironmentFile=-/etc/...`) nếu muốn file là tùy chọn |
| `java.net.BindException: Address already in use` | Port 8081 đang bị chiếm (thường do bản chạy tay ở bước 3 chưa tắt) | `ss -tlnp \| grep 8081`, dừng process đó |
| Sửa unit file mà không có tác dụng, kèm cảnh báo `changed on disk` | Quên `daemon-reload` | `sudo systemctl daemon-reload` rồi restart |
| `start-limit-hit` | App chết liên tục, systemd ngừng thử | Đọc journal tìm lỗi gốc, sửa, `sudo systemctl reset-failed taskhub-demo` |
| `curl: (7) Failed to connect to localhost port 8081` | App chưa chạy xong, hoặc đã chết | `systemctl status`, `journalctl -u taskhub-demo -n 30` |

**Kỹ thuật debug quan trọng nhất:** chạy đúng lệnh `ExecStart` bằng đúng user của service:

```bash
sudo -u taskhub env APP_PORT=8081 /usr/bin/java -jar /opt/taskhub/app.jar
```

Nếu lệnh này lỗi, bạn thấy lỗi ngay trên terminal, không cần đoán qua journal.

---

## 7. Dọn dẹp

Giữ service này cho đến hết Module 01 nếu bạn muốn dùng nó để luyện tập ở các bài sau (ví dụ đọc log ở bài 07). Khi muốn gỡ bỏ hoàn toàn:

```bash
sudo systemctl disable --now taskhub-demo
sudo rm /etc/systemd/system/taskhub-demo.service
sudo rm /etc/taskhub-demo.env
sudo systemctl daemon-reload
sudo systemctl reset-failed
# ⚠️ Xóa thư mục ứng dụng — kiểm tra kỹ đường dẫn trước khi chạy
sudo rm -r /opt/taskhub
# Chỉ xóa user nếu không còn bài nào dùng đến
sudo userdel taskhub
```

Kiểm tra đã sạch:

```bash
systemctl status taskhub-demo --no-pager 2>&1 | head -2
id taskhub
ls /opt
```

```text
Unit taskhub-demo.service could not be found.
id: 'taskhub': no such user
```

JDK đã cài (nếu có) có thể giữ lại — các module sau sẽ cần.

---

## 8. Câu hỏi sau lab

1. Vì sao phải chạy app bằng tay trước khi viết unit file?
2. Nếu bỏ `User=taskhub`, app sẽ chạy bằng user nào? Rủi ro là gì?
3. `systemctl restart` và tự khởi động lại do `Restart=on-failure` khác nhau thế nào?
4. Bạn muốn đổi port thành 9090. Cần sửa những gì, và có cần `daemon-reload` không? (Gợi ý: bạn sửa file nào?)
5. So sánh cách chạy này với `nohup java -jar app.jar &` theo 4 tiêu chí: tự khởi động khi boot, tự khởi động lại khi chết, log, bảo mật.
6. Ở Module 04 bạn sẽ chạy cùng app này bằng Docker với `--restart on-failure`. Dự đoán: Docker đang làm vai trò của thành phần nào trong lab này?
