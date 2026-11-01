# Tuần 6 — Xây ứng dụng taskhub bằng Spring Boot (hướng dẫn từng bước)

> ⏱️ ~6–8 giờ (phần dự án của tuần 6) · Mức độ: 🟥 Bắt buộc
> Đặc tả gốc (cần xây cái gì, tiêu chí chấp nhận): [v-pre-foundation.md — Tuần 6](v-pre-foundation.md#tuần-6--đặc-tả-ứng-dụng-spring-boot). File này là **cách làm** từng bước.
> Môi trường: `[WSL]` Ubuntu 24.04, trình duyệt Windows, IntelliJ IDEA hoặc VS Code.
> Phiên bản đã kiểm chứng ngày 2026-10-31: **Spring Boot 4.1.2**, **Java 21**, PostgreSQL **17** (image `postgres:17`).

## Mục lục

- [0. Bạn cần hiểu Spring Boot đến mức nào?](#0-bạn-cần-hiểu-spring-boot-đến-mức-nào)
- [1. Chuẩn bị môi trường](#1-chuẩn-bị-môi-trường)
- [2. Tạo project trên start.spring.io](#2-tạo-project-trên-startspringio)
- [3. Hiểu cấu trúc project Maven](#3-hiểu-cấu-trúc-project-maven)
- [4. Chạy PostgreSQL cho môi trường dev](#4-chạy-postgresql-cho-môi-trường-dev)
- [5. Cấu hình qua biến môi trường](#5-cấu-hình-qua-biến-môi-trường)
- [6. Migration bằng Flyway](#6-migration-bằng-flyway)
- [7. Viết code](#7-viết-code)
- [8. Viết test](#8-viết-test)
- [9. Build và chạy](#9-build-và-chạy)
- [10. Kiểm thử bằng curl](#10-kiểm-thử-bằng-curl)
- [11. Lỗi thường gặp khi khởi động và cách đọc](#11-lỗi-thường-gặp-khi-khởi-động-và-cách-đọc)
- [12. Đưa code vào main qua Pull Request và release v0.1.0](#12-đưa-code-vào-main-qua-pull-request-và-release-v010)
- [13. Câu hỏi tự kiểm](#13-câu-hỏi-tự-kiểm)
- [14. Definition of Done](#14-definition-of-done)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 0. Bạn cần hiểu Spring Boot đến mức nào?

Bạn đang học DevOps, không phải học làm Java backend. Mục tiêu tuần này là có một ứng dụng **chuẩn để vận hành**, và bạn hiểu **đủ** để:

| Cần hiểu (🟥) | Không cần lúc này |
|---|---|
| Ứng dụng đọc cấu hình từ đâu, biến môi trường ghi đè thế nào | Thiết kế kiến trúc nhiều tầng, DDD |
| Ứng dụng kết nối database ra sao, migration chạy lúc nào | Tối ưu truy vấn JPA, quan hệ entity phức tạp |
| Build ra file gì, chạy bằng lệnh gì, log in ra đâu | Spring Security, OAuth |
| Đọc được log khởi động và stack trace khi lỗi | Reactive (WebFlux) |
| Health check báo gì, vì sao | — |

Code trong bài là **bản tối thiểu đầy đủ**. Hãy gõ lại (đừng copy cả khối) và đọc giải thích — đó là cách nhanh nhất để hiểu.

---

## 1. Chuẩn bị môi trường

### 1.1. Code ở đâu?

Đặt repo trong thư mục home của WSL, **không** trong `/mnt/c/...` (lý do ở [Linux bài 01, mục 11](../../01-LINUX/01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp): chậm và sai quyền file — Maven đọc/ghi hàng nghìn file nên càng chậm rõ).

```bash
mkdir -p ~/projects
cd ~/projects
git clone git@github.com:<github-user>/taskhub.git   # repo đã tạo ở tuần 1
cd taskhub
```

Hai cách mở code — chọn một:

| Cách | Làm thế nào | Ghi chú |
|---|---|---|
| **IntelliJ IDEA** (Windows) mở project trong WSL | *File → Open* → gõ đường dẫn `\\wsl.localhost\Ubuntu\home\<user>\projects\taskhub\app` | IntelliJ hỗ trợ project nằm trong WSL; chọn JDK **trong WSL** cho project (*Project Structure → SDK → Add JDK from WSL*) để build giống hệt terminal |
| **VS Code** + extension WSL | Trong terminal WSL: `cd ~/projects/taskhub && code .` | Cài thêm *Extension Pack for Java* (chạy phía WSL) |

> Tên distro có thể khác (`Ubuntu`, `Ubuntu-24.04`). Kiểm tra bằng `wsl -l -v` trong `[PowerShell]`.

### 1.2. JDK trong WSL

Java 21 đã có trên Windows, nhưng lệnh `./mvnw` chạy **trong WSL** cần JDK **của WSL**:

```bash
java -version
```

```text
openjdk version "21.0.x" ...
```

Nếu báo `command not found` hoặc ra bản khác 21: kho Ubuntu 24.04 có gói `openjdk-21-jdk-headless` (kiểm tra bằng `apt policy openjdk-21-jdk-headless`). ⚠️ Cài phần mềm là quyết định của bạn: `sudo apt install openjdk-21-jdk-headless`. Không cần cài Maven — Maven Wrapper (`mvnw`) tự tải đúng phiên bản Maven.

---

## 2. Tạo project trên start.spring.io

Mở [start.spring.io](https://start.spring.io) trên trình duyệt và chọn:

| Mục | Chọn | Vì sao |
|---|---|---|
| Project | **Maven** | Đồng bộ với hướng dẫn và CI tuần 9 |
| Language | Java | |
| Spring Boot | **4.1.2** (bản không có chữ SNAPSHOT/RC) | Bản ổn định hiện tại khi viết bài |
| Group | `com.taskhub` | |
| Artifact / Name | `taskhub` | |
| Package name | `com.taskhub` | |
| Packaging | Jar | Chạy bằng `java -jar` — dễ đóng gói vào Docker |
| Java | **21** | Trang web mặc định chọn 17 — nhớ đổi |
| Dependencies | *Spring Web*, *Spring Data JPA*, *PostgreSQL Driver*, *Flyway Migration*, *Spring Boot Actuator*, *Validation* | Theo đặc tả |

Bấm **Generate**, giải nén file zip vào thư mục `app/` của repo:

```bash
cd ~/projects/taskhub
unzip /mnt/c/Users/<windows-user>/Downloads/taskhub.zip -d /tmp/taskhub-gen
mv /tmp/taskhub-gen/taskhub app        # kết quả: ~/projects/taskhub/app/pom.xml
chmod +x app/mvnw                      # file giải nén từ Windows có thể mất quyền thực thi
ls -la app
```

> **Spring Boot 4 khác 3.x ở đâu (gặp ngay trong `pom.xml`)?** Khi chọn 6 dependency trên, start.spring.io sinh ra (đã kiểm tra ngày 2026-10-31):
>
> | Bạn chọn | Dependency thật trong `pom.xml` |
> |---|---|
> | Spring Web | `spring-boot-starter-webmvc` (tutorial 3.x ghi `spring-boot-starter-web`) |
> | Flyway Migration | `spring-boot-starter-flyway` **và** `org.flywaydb:flyway-database-postgresql` (tutorial 3.x thường chỉ có `flyway-core`) |
> | Spring Data JPA, Validation, Actuator | `spring-boot-starter-data-jpa`, `-validation`, `-actuator` |
> | PostgreSQL Driver | `org.postgresql:postgresql` (scope `runtime`) |
> | (test) | Mỗi starter có một starter test riêng: `spring-boot-starter-webmvc-test`, `-data-jpa-test`, `-flyway-test`… (3.x chỉ có một `spring-boot-starter-test`) |
>
> Spring Boot 4 chia nhỏ thành nhiều module. Khi copy code từ tutorial cũ mà báo lỗi không tìm thấy class/annotation, rất có thể **package đã đổi** — xem [mục 8](#8-viết-test).

Mở `app/pom.xml`, đổi phiên bản dự án cho khớp release sắp tới:

```xml
<version>0.1.0-SNAPSHOT</version>
```

`-SNAPSHOT` nghĩa là "bản đang phát triển". Lúc release ở [mục 12](#12-đưa-code-vào-main-qua-pull-request-và-release-v010) bạn bỏ chữ này.

---

## 3. Hiểu cấu trúc project Maven

```text
app/
├── pom.xml                  ← "bản khai" của project: phiên bản Java, dependency, plugin build
├── mvnw, mvnw.cmd           ← Maven Wrapper: script tự tải đúng Maven → mọi máy, mọi CI build giống nhau
├── .mvn/wrapper/            ← cấu hình của wrapper (phiên bản Maven) — PHẢI commit
├── src/main/java/com/taskhub/
│   └── TaskhubApplication.java   ← điểm khởi động (hàm main)
├── src/main/resources/
│   ├── application.properties    ← cấu hình (bài này đổi sang application.yml)
│   └── db/migration/             ← (tự tạo) file SQL của Flyway
├── src/test/java/com/taskhub/    ← test
└── target/                  ← (sinh ra khi build) chứa file .jar — KHÔNG commit
```

| Lệnh | Làm gì | Khi nào dùng |
|---|---|---|
| `./mvnw spring-boot:run` | Biên dịch và chạy ngay | Dev hằng ngày |
| `./mvnw test` | Chạy test | Trước khi commit |
| `./mvnw package` | Biên dịch + test + đóng gói `target/taskhub-<version>.jar` | Tạo artifact |
| `./mvnw verify` | Như `package` + các bước kiểm tra sau đó | **Lệnh CI sẽ chạy** ở tuần 9 |
| `./mvnw clean` | Xóa `target/` | Khi build lạ, muốn làm sạch |

Kiểm tra `.gitignore` ở gốc repo (tạo ở tuần 1) có các dòng `target/` và `.env`.

---

## 4. Chạy PostgreSQL cho môi trường dev

Đặc tả cho hai lựa chọn. Chọn **một**.

### Cách A — Cài bằng `apt` trong WSL (ôn Linux bài 04, 05)

```bash
sudo apt install postgresql              # ⚠️ cài phần mềm — bạn tự quyết định
sudo systemctl status postgresql         # nếu WSL chưa bật systemd: sudo service postgresql start
psql --version                           # Ubuntu 24.04 cài PostgreSQL 16
```

Tạo user và database riêng cho ứng dụng (không dùng superuser `postgres`):

```bash
sudo -u postgres psql -c "CREATE USER taskhub WITH PASSWORD 'devpassword';"
sudo -u postgres psql -c "CREATE DATABASE taskhub OWNER taskhub;"
psql "postgresql://taskhub:devpassword@localhost:5432/taskhub" -c "select current_user;"
```

> PostgreSQL 16 ở máy dev khác 17 ở Docker/production. Với ứng dụng đơn giản này không sao, nhưng hãy ghi nhớ: **môi trường dev nên giống production nhất có thể** — đó là một lý do Docker ra đời (tuần 7).

### Cách B — Chạy bằng một lệnh `docker run`

Đây là lệnh Docker đầu tiên trước khi học Module 04 — chỉ cần hiểu từng tham số ở mức tối thiểu:

```bash
docker run -d --name taskhub-db \
  -e POSTGRES_DB=taskhub \
  -e POSTGRES_USER=taskhub \
  -e POSTGRES_PASSWORD=devpassword \
  -p 127.0.0.1:5432:5432 \
  -v taskhub-dev-pgdata:/var/lib/postgresql/data \
  postgres:17
```

| Tham số | Ý nghĩa |
|---|---|
| `-d` | Chạy nền (detached) |
| `--name taskhub-db` | Đặt tên để gọi lại: `docker stop taskhub-db`, `docker start taskhub-db`, `docker logs taskhub-db` |
| `-e KEY=value` | Biến môi trường. Image `postgres` đọc chúng **lần đầu khởi tạo** để tạo database, user, mật khẩu. Chỉ `POSTGRES_PASSWORD` là bắt buộc |
| `-p 127.0.0.1:5432:5432` | Mở port 5432 của container ra port 5432 của máy — **chỉ trên `127.0.0.1`** (nhớ bài bind address ở [Networking bài 05](../../02-NETWORKING/05-tcp-udp-ports-firewall.md)) |
| `-v taskhub-dev-pgdata:/var/lib/postgresql/data` | Lưu dữ liệu vào một *volume* tên `taskhub-dev-pgdata` → xóa container dữ liệu vẫn còn |
| `postgres:17` | Image và phiên bản (tag). **Luôn ghi rõ phiên bản**, không dùng `latest` |

> ⚠️ **Bẫy phiên bản:** từ **PostgreSQL 18**, image đổi thư mục dữ liệu (`PGDATA`) thành `/var/lib/postgresql/18/docker` và volume nên gắn vào `/var/lib/postgresql`. Tutorial cũ gắn vào `/var/lib/postgresql/data` sẽ **không đúng** với bản 18. Ta dùng 17 nên đường dẫn trên là đúng. Nguồn: trang image `postgres` trên Docker Hub.

> Với image Docker, `POSTGRES_USER=taskhub` thực chất tạo một **superuser** tên `taskhub`. Chấp nhận được cho máy dev; ở production (RDS, tuần 14) sẽ tách user quản trị và user ứng dụng.

Kiểm tra:

```bash
docker ps --filter name=taskhub-db
docker logs taskhub-db --tail 5            # chờ dòng "database system is ready to accept connections"
```

> ⚠️ Mật khẩu gõ trên dòng lệnh sẽ nằm trong lịch sử shell (`~/.bash_history`). Chấp nhận được với mật khẩu dev; với mật khẩu thật thì không bao giờ.

---

## 5. Cấu hình qua biến môi trường

### 5.1. Biến môi trường ghi đè cấu hình thế nào?

Spring Boot đọc cấu hình từ nhiều nguồn; **biến môi trường thắng file `application.yml`**. Tên biến được "dịch" theo quy tắc *relaxed binding* (gắn kết linh hoạt): bỏ dấu chấm và gạch ngang, viết hoa, thay dấu chấm bằng `_`:

| Thuộc tính trong `application.yml` | Biến môi trường tương ứng |
|---|---|
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `spring.datasource.username` | `SPRING_DATASOURCE_USERNAME` |
| `server.port` | `SERVER_PORT` |

Đây là lý do cùng một file `.jar` (và sau này cùng một Docker image) chạy được ở máy bạn, trong Docker Compose và trên EC2 — chỉ đổi biến môi trường.

### 5.2. `application.yml`

Xóa `src/main/resources/application.properties`, tạo `src/main/resources/application.yml`:

```yaml
spring:
  application:
    name: taskhub
  datasource:
    # ${TÊN:mặc-định} — dùng biến môi trường nếu có, không thì dùng giá trị sau dấu ":"
    url: ${SPRING_DATASOURCE_URL:jdbc:postgresql://localhost:5432/taskhub}
    username: ${SPRING_DATASOURCE_USERNAME:taskhub}
    # KHÔNG có giá trị mặc định: thiếu biến này thì ứng dụng từ chối khởi động (cố ý — xem mục 11)
    password: ${SPRING_DATASOURCE_PASSWORD}
  jpa:
    hibernate:
      ddl-auto: validate      # Hibernate chỉ KIỂM TRA bảng khớp entity, không tự tạo/sửa bảng — Flyway lo việc đó
    open-in-view: false
  mvc:
    problemdetails:
      enabled: true           # lỗi trả JSON chuẩn RFC 9457 (application/problem+json)

server:
  port: ${SERVER_PORT:8080}

management:
  endpoints:
    web:
      exposure:
        include: health,info  # chỉ công khai 2 endpoint này
```

Giải thích những dòng liên quan đến vận hành:

| Dòng | Góc nhìn DevOps |
|---|---|
| `password: ${SPRING_DATASOURCE_PASSWORD}` | Mật khẩu không bao giờ nằm trong repo. Thiếu biến → lỗi ngay lúc khởi động, rõ ràng, thay vì chạy với cấu hình sai |
| `ddl-auto: validate` | Schema do migration quản lý (có phiên bản, review được). `update` có thể âm thầm sửa bảng production — cấm dùng |
| `exposure.include: health,info` | Mặc định Spring Boot chỉ mở `/health` qua HTTP. Ta mở thêm `info`. Endpoint `prometheus` sẽ bật ở v5 |
| (không cấu hình log file) | Mặc định Spring Boot log ra **stdout** — đúng yêu cầu: Docker, journald, Loki đều thu log từ stdout |
| (không cấu hình shutdown) | **Graceful shutdown bật sẵn** trong Spring Boot hiện tại: nhận SIGTERM → ngừng nhận request mới, xử lý nốt request đang chạy rồi mới thoát (nối [Linux bài 04](../../01-LINUX/04-processes-systemd.md)) |

### 5.3. File `.env` cho máy dev (không commit)

Spring Boot **không tự đọc** file `.env`. Ta để Bash nạp nó thành biến môi trường (kỹ thuật ở [Linux bài 06](../../01-LINUX/06-bash-scripting.md)):

```bash
cd ~/projects/taskhub
cat > .env <<'EOF'
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/taskhub
SPRING_DATASOURCE_USERNAME=taskhub
SPRING_DATASOURCE_PASSWORD=devpassword
EOF
git check-ignore -v .env      # PHẢI in ra dòng của .gitignore đang bỏ qua file này
```

Mỗi khi mở terminal mới để chạy ứng dụng:

```bash
set -a; source ~/projects/taskhub/.env; set +a    # set -a: mọi biến khai báo sau đó tự được export
env | grep SPRING_                                 # kiểm tra
```

Tạo thêm `.env.example` (CÓ commit) chỉ chứa tên biến và giá trị giả — người khác (và bạn ở tuần 8) biết cần những biến gì:

```bash
cat > .env.example <<'EOF'
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/taskhub
SPRING_DATASOURCE_USERNAME=taskhub
SPRING_DATASOURCE_PASSWORD=change-me
EOF
```

---

## 6. Migration bằng Flyway

Flyway chạy **tự động lúc ứng dụng khởi động**, trước khi Hibernate kiểm tra schema. Mặc định nó tìm file trong `classpath:db/migration`, tên theo mẫu `V<phiên-bản>__<mô-tả>.sql` (hai dấu gạch dưới).

```bash
mkdir -p ~/projects/taskhub/app/src/main/resources/db/migration
```

`app/src/main/resources/db/migration/V1__create_tasks_table.sql`:

```sql
CREATE TABLE tasks (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title       VARCHAR(200)  NOT NULL,
    description VARCHAR(2000),
    status      VARCHAR(20)   NOT NULL DEFAULT 'TODO',
    created_at  TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at  TIMESTAMP WITH TIME ZONE NOT NULL,
    CONSTRAINT tasks_status_check CHECK (status IN ('TODO', 'IN_PROGRESS', 'DONE'))
);

CREATE INDEX idx_tasks_status ON tasks (status);
```

Flyway ghi lại migration nào đã chạy trong bảng `flyway_schema_history`, kèm **checksum** (mã kiểm tra nội dung) của từng file.

> ⚠️ **Quy tắc sống còn:** đã chạy migration lên một database thì **không bao giờ sửa file đó nữa**. Muốn đổi schema → tạo file mới `V2__...sql`. Sửa file cũ → checksum lệch → ứng dụng từ chối khởi động (xem [mục 11](#11-lỗi-thường-gặp-khi-khởi-động-và-cách-đọc)).

---

## 7. Viết code

Tất cả file nằm trong `app/src/main/java/com/taskhub/`. Package chỉ có một tầng cho đơn giản.

### 7.1. `TaskStatus.java` — enum trạng thái

```java
package com.taskhub;

public enum TaskStatus {
    TODO, IN_PROGRESS, DONE
}
```

### 7.2. `Task.java` — entity ánh xạ bảng `tasks`

```java
package com.taskhub;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "tasks")
public class Task {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)   // database tự sinh id (cột IDENTITY)
    private Long id;

    @Column(nullable = false, length = 200)
    private String title;

    @Column(length = 2000)
    private String description;

    @Enumerated(EnumType.STRING)                          // lưu chữ "TODO", không lưu số 0/1/2
    @Column(nullable = false, length = 20)
    private TaskStatus status = TaskStatus.TODO;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist                                           // chạy ngay trước khi INSERT
    void onCreate() {
        createdAt = Instant.now();
        updatedAt = createdAt;
    }

    @PreUpdate                                            // chạy ngay trước khi UPDATE
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public Long getId() { return id; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public TaskStatus getStatus() { return status; }
    public void setStatus(TaskStatus status) { this.status = status; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
```

> Import là `jakarta.persistence.*` — **không phải** `javax.persistence.*` như tutorial rất cũ (trước Spring Boot 3). Thấy `javax.` trong tutorial là dấu hiệu nó đã lỗi thời.

### 7.3. `TaskRepository.java` — truy cập database

```java
package com.taskhub;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskRepository extends JpaRepository<Task, Long> {
    List<Task> findByStatus(TaskStatus status);   // Spring Data tự sinh câu SQL từ tên hàm
}
```

`JpaRepository` cho sẵn `findAll`, `findById`, `save`, `deleteById`, `existsById`… — không cần viết SQL.

### 7.4. `TaskRequest.java` — dữ liệu client gửi lên, kèm kiểm tra hợp lệ

```java
package com.taskhub;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record TaskRequest(
        @NotBlank @Size(max = 200) String title,
        @Size(max = 2000) String description,
        TaskStatus status   // tùy chọn: null khi tạo → TODO; null khi sửa → giữ nguyên
) {}
```

Tách `TaskRequest` khỏi `Task` để client **không** tự đặt được `id`, `createdAt`.

### 7.5. `TaskController.java` — REST API

```java
package com.taskhub;

import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.util.UriComponentsBuilder;

@RestController
@RequestMapping("/api/tasks")
public class TaskController {

    private final TaskRepository repository;

    public TaskController(TaskRepository repository) {   // Spring tự "tiêm" repository vào (dependency injection)
        this.repository = repository;
    }

    @GetMapping
    public List<Task> list(@RequestParam(required = false) TaskStatus status) {
        return status == null ? repository.findAll() : repository.findByStatus(status);
    }

    @GetMapping("/{id}")
    public Task get(@PathVariable Long id) {
        return findOr404(id);
    }

    @PostMapping
    public ResponseEntity<Task> create(@Valid @RequestBody TaskRequest request, UriComponentsBuilder uri) {
        Task task = new Task();
        apply(task, request);
        Task saved = repository.save(task);
        var location = uri.path("/api/tasks/{id}").buildAndExpand(saved.getId()).toUri();
        return ResponseEntity.created(location).body(saved);   // 201 + header Location
    }

    @PutMapping("/{id}")
    public Task update(@PathVariable Long id, @Valid @RequestBody TaskRequest request) {
        Task task = findOr404(id);
        apply(task, request);
        return repository.save(task);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)                   // 204
    public void delete(@PathVariable Long id) {
        if (!repository.existsById(id)) {
            throw notFound(id);
        }
        repository.deleteById(id);
    }

    private Task findOr404(Long id) {
        return repository.findById(id).orElseThrow(() -> notFound(id));
    }

    private static ResponseStatusException notFound(Long id) {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "Task " + id + " not found");
    }

    private static void apply(Task task, TaskRequest request) {
        task.setTitle(request.title());
        task.setDescription(request.description());
        if (request.status() != null) {
            task.setStatus(request.status());
        }
    }
}
```

Lỗi được xử lý thế nào — không cần tự viết exception handler:

| Tình huống | Spring làm gì | Client nhận |
|---|---|---|
| Không tìm thấy id | `ResponseStatusException(NOT_FOUND)` | `404`, JSON Problem Details |
| `title` rỗng / quá dài | `@Valid` thất bại | `400`, JSON Problem Details |
| JSON sai cú pháp, `status` không thuộc enum | Không đọc được body | `400` |
| Database chết giữa chừng | Exception không được xử lý | `500` — và `/actuator/health` báo `DOWN` |

Ví dụ một lỗi 404 (đã bật `spring.mvc.problemdetails.enabled`):

```json
{"type":"about:blank","title":"Not Found","status":404,"detail":"Task 99 not found","instance":"/api/tasks/99"}
```

---

## 8. Viết test

Đặc tả yêu cầu: 1 test khởi động context + test cho controller (201, 400, 404).

### 8.1. Test controller — không cần database

`@WebMvcTest` chỉ dựng tầng web (controller, validation, JSON), **không** kết nối database. Repository được thay bằng *mock* (đối tượng giả).

`app/src/test/java/com/taskhub/TaskControllerTest.java`:

```java
package com.taskhub;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(TaskController.class)
class TaskControllerTest {

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private TaskRepository repository;

    @Test
    void createValidTaskReturns201WithLocation() throws Exception {
        given(repository.save(any(Task.class))).willAnswer(invocation -> {
            Task task = invocation.getArgument(0);
            ReflectionTestUtils.setField(task, "id", 1L);   // giả lập database sinh id
            return task;
        });

        mvc.perform(post("/api/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Học Linux bài 01\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", "http://localhost/api/tasks/1"));
    }

    @Test
    void createWithoutTitleReturns400() throws Exception {
        mvc.perform(post("/api/tasks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"description\":\"thiếu title\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void getUnknownIdReturns404() throws Exception {
        given(repository.findById(99L)).willReturn(Optional.empty());

        mvc.perform(get("/api/tasks/99"))
                .andExpect(status().isNotFound());
    }
}
```

> **Package trong Spring Boot 4** (đã kiểm chứng trên docs chính thức ngày 2026-10-31):
>
> | Annotation | Spring Boot 4 | Tutorial 3.x cũ |
> |---|---|---|
> | `@WebMvcTest` | `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest` (module `spring-boot-webmvc-test`) | `org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest` |
> | Mock một bean | `@MockitoBean` — `org.springframework.test.context.bean.override.mockito.MockitoBean` | `@MockBean` |
>
> Docs Spring Boot 4 còn giới thiệu `MockMvcTester` (cú pháp AssertJ). Bài dùng `MockMvc` cổ điển vì nó xuất hiện trong hầu hết tài liệu và bạn sẽ gặp nhiều nhất khi đọc code người khác.

### 8.2. Test khởi động context — CẦN database

File `TaskhubApplicationTests.java` do start.spring.io sinh sẵn (`@SpringBootTest` + hàm `contextLoads()`) khởi động **toàn bộ** ứng dụng, gồm cả Flyway và kết nối database. Vì vậy:

- Chạy `./mvnw test` khi PostgreSQL dev **đang chạy** và đã nạp `.env` → xanh.
- PostgreSQL tắt → test này **đỏ** với lỗi `Connection refused`. Đây là hành vi đúng, không phải lỗi code.

Ở tuần 9, pipeline CI sẽ chạy một PostgreSQL tạm (service container) để test này xanh trên GitHub Actions. 🟨 Cách thay thế là **Testcontainers** (thư viện tự bật PostgreSQL bằng Docker trong lúc test) — sẽ quay lại khi viết CI.

---

## 9. Build và chạy

```bash
cd ~/projects/taskhub/app
set -a; source ../.env; set +a

./mvnw spring-boot:run
```

Lần đầu Maven tải rất nhiều thư viện (vài phút). Log khởi động thành công trông như sau (minh họa, đã rút gọn):

```text
  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
...
 :: Spring Boot ::                (v4.1.2)

INFO ... com.taskhub.TaskhubApplication      : Starting TaskhubApplication using Java 21.0.x ...
INFO ... o.f.core.internal.command.DbMigrate : Migrating schema "public" to version "1 - create tasks table"
INFO ... o.f.core.internal.command.DbMigrate : Successfully applied 1 migration to schema "public"
INFO ... o.s.boot.tomcat.TomcatWebServer      : Tomcat started on port 8080 (http) ...
INFO ... com.taskhub.TaskhubApplication      : Started TaskhubApplication in 4.2 seconds
```

Ba dòng cần tìm mỗi lần khởi động: **Flyway migrate**, **Tomcat started on port**, **Started … in … seconds**. Không thấy dòng nào → đọc ngược lên tìm `ERROR` (xem mục 11).

Đóng gói và chạy như cách sẽ chạy trên server:

```bash
./mvnw verify                          # build + test (cần PostgreSQL đang chạy, xem 8.2)
ls -lh target/*.jar                    # taskhub-0.1.0-SNAPSHOT.jar
java -jar target/taskhub-0.1.0-SNAPSHOT.jar
```

Dừng ứng dụng bằng **Ctrl+C** (gửi SIGINT) — quan sát log tắt nhẹ nhàng. Tuần 7 file `.jar` này sẽ được đưa vào Docker image.

---

## 10. Kiểm thử bằng curl

Mở terminal thứ hai `[WSL]`:

```bash
# Tạo — mong đợi 201 + header Location
curl -i -X POST localhost:8080/api/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Học Linux bài 01","description":"filesystem"}'
```

```text
HTTP/1.1 201
Location: http://localhost:8080/api/tasks/1
Content-Type: application/json

{"id":1,"title":"Học Linux bài 01","description":"filesystem","status":"TODO","createdAt":"2026-11-08T03:12:45.123Z","updatedAt":"2026-11-08T03:12:45.123Z"}
```

```bash
curl -s localhost:8080/api/tasks                                   # 200, danh sách
curl -s 'localhost:8080/api/tasks?status=TODO'                     # 200, lọc theo trạng thái
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/tasks/99   # 404
curl -i -X PUT localhost:8080/api/tasks/1 \
  -H 'Content-Type: application/json' \
  -d '{"title":"Học Linux bài 01","status":"DONE"}'                 # 200, status=DONE, updatedAt đổi
curl -i -X POST localhost:8080/api/tasks \
  -H 'Content-Type: application/json' -d '{"title":""}'            # 400, application/problem+json
curl -i -X DELETE localhost:8080/api/tasks/1                       # 204
curl -s localhost:8080/actuator/health                             # {"groups":["liveness","readiness"],"status":"UP"}
```

**Thử nghiệm bắt buộc — health check phản ánh database:**

```bash
docker stop taskhub-db          # Cách B;  Cách A: sudo systemctl stop postgresql
curl -s -w '\n%{http_code}\n' localhost:8080/actuator/health
```

```text
{"groups":["liveness","readiness"],"status":"DOWN"}
503
```

⏱️ Lệnh `curl` sẽ **treo khoảng 30 giây** trước khi in kết quả: connection pool HikariCP (Spring Boot dùng mặc định) chờ tối đa `connection-timeout` = 30 giây để lấy được kết nối rồi mới chịu báo lỗi. Ghi nhớ con số này — ở [tuần 8](v0-docker-compose.md) nó sẽ “va” với timeout của nginx. (`groups` liệt kê hai nhóm health `liveness`/`readiness` mà Spring Boot 4.1 trả kèm — đã kiểm chứng khi chạy thật ngày 2026-10-31; Kubernetes ở tuần 19 dùng đúng hai nhóm này.)

Vì sao? Actuator tự có *health indicator* `db` kiểm tra lấy được kết nối tới database; một thành phần `DOWN` → tổng thể `DOWN` → HTTP **503**. Ở các tuần sau, Docker healthcheck, load balancer (ALB) và Kubernetes sẽ dựa vào chính mã này để quyết định có gửi traffic tới ứng dụng hay không. Bật lại database (`docker start taskhub-db`) và gọi lại — ứng dụng tự kết nối lại, không cần khởi động lại.

---

## 11. Lỗi thường gặp khi khởi động và cách đọc

Spring Boot in lỗi khởi động thành **stack trace rất dài**. Đừng đọc từ trên xuống: áp dụng cách đọc ở [Linux bài 07 — Đọc stack trace Java](../../01-LINUX/07-logs-monitoring-troubleshooting.md#43--đọc-stack-trace-java) — tìm khối `APPLICATION FAILED TO START` (nếu có) và dòng **`Caused by:` cuối cùng**.

Các thông báo dưới đây là minh họa — chữ chính xác có thể khác theo phiên bản, hãy tìm **ý chính** in đậm.

| Triệu chứng (dòng `Caused by` cuối / thông báo) | Nguyên nhân | Kiểm tra | Cách sửa |
|---|---|---|---|
| `PSQLException: Connection to localhost:5432 **refused**` | PostgreSQL chưa chạy, hoặc sai host/port | `ss -ltn \| grep 5432`, `docker ps`, `systemctl status postgresql` | Bật database; kiểm tra `SPRING_DATASOURCE_URL` |
| `FATAL: **password authentication failed** for user "taskhub"` | Sai mật khẩu, hoặc chưa nạp `.env` | `env \| grep SPRING_` | `source .env` lại; với Cách B nhớ mật khẩu chỉ được đặt **lần đầu** tạo volume |
| `Could not resolve placeholder '**SPRING_DATASOURCE_PASSWORD**'` | Thiếu biến môi trường (cố ý không có mặc định) | `env \| grep SPRING_` | `set -a; source .env; set +a` |
| `Web server failed to start. **Port 8080 was already in use**.` | Một process khác đang nghe 8080 (thường là chính app chạy lần trước, hoặc server Python ở lab Networking) | `sudo ss -ltnp \| grep 8080` | Dừng process đó, hoặc `SERVER_PORT=8081 ./mvnw spring-boot:run` |
| `Validate failed: ... **Migration checksum mismatch** for migration version 1` | Đã sửa file `V1__...sql` sau khi nó chạy | `select version, checksum from flyway_schema_history;` | Hoàn tác thay đổi trong V1 và tạo `V2__...sql`. Máy dev: có thể xóa và tạo lại database. 🟦 `flyway repair` |
| `Schema-validation: **missing table [tasks]**` | Flyway không chạy hoặc không thấy file migration (sai thư mục/tên file) | Log có dòng `Migrating schema` không? File có ở `src/main/resources/db/migration/`? Tên có đúng **2** dấu gạch dưới? | Sửa vị trí/tên file |
| `./mvnw: Permission denied` | File mất quyền thực thi khi giải nén từ Windows | `ls -l mvnw` | `chmod +x mvnw` (và commit: `git update-index --chmod=+x app/mvnw`) |
| `release version 21 not supported` | `./mvnw` đang dùng JDK cũ hơn 21 | `java -version`, `./mvnw -v` | Dùng JDK 21 trong WSL ([mục 1.2](#12-jdk-trong-wsl)) |

> Cảnh báo kiểu `Mockito is currently self-attaching to enable the inline-mock-maker...` khi chạy test là **cảnh báo**, không phải lỗi — test vẫn xanh. Ghi lại nó vào nhật ký nếu muốn tìm hiểu thêm.

Ghi mọi lỗi bạn gặp vào `troubleshooting-journal.md` theo [mẫu](../../00-ROADMAP/templates/troubleshooting-journal-template.md).

---

## 12. Đưa code vào main qua Pull Request và release v0.1.0

Áp dụng bài Git tuần 6 ([GitHub, Pull Request và code review](../../03-GIT/03-github-pull-request-code-review.md), [tag và release](../../03-GIT/05-tags-releases-versioning.md)).

1. **Bảo vệ `main`** trên GitHub: bắt buộc Pull Request, không cho push thẳng.
2. Làm việc trên nhánh theo đặc tả:

   ```bash
   cd ~/projects/taskhub
   git switch -c feat/task-api
   git add app/ .env.example
   git status                      # KIỂM TRA: không có .env, không có app/target/
   git commit -m "feat(api): add task CRUD API with Flyway and Actuator"
   ```

3. Cập nhật `README.md` gốc repo, thêm mục **"Chạy trên máy"**: yêu cầu (JDK 21, PostgreSQL), cách bật database, bảng biến môi trường, lệnh chạy và lệnh test. Commit: `docs: add local run instructions`.
4. `git push -u origin feat/task-api` → mở Pull Request trên GitHub → **tự review diff** từng file (có lộ mật khẩu không? có file thừa không?) → *Squash and merge* → xóa nhánh.
5. Release:

   ```bash
   git switch main && git pull
   # bỏ "-SNAPSHOT" trong app/pom.xml: <version>0.1.0</version> — làm qua một PR nhỏ "chore: release 0.1.0"
   git tag -a v0.1.0 -m "taskhub v0.1.0: task CRUD API, Flyway, Actuator"
   git push origin v0.1.0
   ```

   Trên GitHub: *Releases → Draft a new release* → chọn tag `v0.1.0` → mô tả những gì đã có.

Kiểm tra cuối cùng không lộ secret:

```bash
git grep -n -i password      # chỉ được thấy tên biến/placeholder (change-me, ${SPRING_DATASOURCE_PASSWORD})
```

---

## 13. Câu hỏi tự kiểm

1. Vì sao `password` trong `application.yml` không có giá trị mặc định, còn `url` thì có?
2. Đặt `SPRING_DATASOURCE_URL` khác với giá trị trong `application.yml` thì Spring Boot dùng giá trị nào? Quy tắc nào cho phép biến môi trường ánh xạ vào `spring.datasource.url`?
3. Vì sao dùng Flyway thay vì `ddl-auto: update`? Điều gì xảy ra nếu sửa file `V1` sau khi đã chạy?
4. Tắt database thì `/actuator/health` trả mã HTTP nào? Ai sẽ dùng mã này ở các tuần sau?
5. Vì sao `TaskControllerTest` chạy được khi database tắt, còn `TaskhubApplicationTests` thì không?
6. Ứng dụng log ra đâu? Vì sao đó là lựa chọn đúng khi chạy trong Docker?
7. Gửi SIGTERM cho ứng dụng (`kill <pid>`) thì chuyện gì xảy ra với các request đang xử lý?
8. Với Cách B, bạn đổi `POSTGRES_PASSWORD` trong lệnh `docker run` rồi chạy lại container mới (cùng volume) nhưng mật khẩu cũ vẫn đúng. Vì sao?

---

## 14. Definition of Done

Giống đặc tả trong [v-pre-foundation.md](v-pre-foundation.md#definition-of-done), kiểm tra lại từng mục:

- [ ] `./mvnw spring-boot:run` (với biến môi trường đúng) khởi động thành công, log có dòng Flyway tạo bảng `tasks`.
- [ ] Gọi đủ 5 endpoint bằng `curl` với đúng mã trả về (201/200/404/400/204).
- [ ] `/actuator/health` trả `UP`; tắt PostgreSQL thì trả `DOWN` + 503, giải thích được vì sao.
- [ ] Không có mật khẩu nào trong repo (`git grep -i password` chỉ ra tên biến/placeholder); `.env` bị `.gitignore` bỏ qua, `.env.example` có commit.
- [ ] `./mvnw verify` xanh (khi PostgreSQL dev đang chạy).
- [ ] `main` được bảo vệ; code vào `main` qua Pull Request từ nhánh `feat/task-api`; có tag và GitHub Release `v0.1.0`.
- [ ] README có mục "Chạy trên máy".
- [ ] Ít nhất một lỗi khởi động ở mục 11 đã được bạn **cố ý tái hiện**, đọc stack trace và ghi vào nhật ký debug.

➡️ Tiếp theo: [v0 — Docker Compose](v0-docker-compose.md) (tuần 7–8).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [start.spring.io](https://start.spring.io) | Tạo project; phiên bản mặc định 4.1.2, dependency sinh ra trong `pom.xml` | 2026-10-31 |
| [Spring Boot — Database initialization (Flyway)](https://docs.spring.io/spring-boot/how-to/data-initialization.html) | `spring-boot-starter-flyway`, `flyway-database-postgresql`, thư mục `db/migration`, quy ước tên file | 2026-10-31 |
| [Spring Boot — Testing Spring Boot applications](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html) | Package `@WebMvcTest`, `@MockitoBean`, `MockMvcTester` | 2026-10-31 |
| [Spring Boot — Actuator endpoints](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html) | Endpoint mặc định, `exposure.include`, health `DOWN` → 503 | 2026-10-31 |
| [Spring Boot — Graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html) | Bật mặc định, `server.shutdown` | 2026-10-31 |
| [Spring Boot — Servlet web (Problem Details)](https://docs.spring.io/spring-boot/reference/web/servlet.html) | `spring.mvc.problemdetails.enabled` | 2026-10-31 |
| [Spring Boot — Externalized configuration](https://docs.spring.io/spring-boot/reference/features/external-config.html) | Placeholder `${name:default}`, biến môi trường dạng `SPRING_CONFIG_NAME` | 2026-10-31 |
| [Docker Hub — postgres](https://hub.docker.com/_/postgres) | Tag 17, `POSTGRES_PASSWORD` bắt buộc, thay đổi PGDATA từ bản 18 | 2026-10-31 |
