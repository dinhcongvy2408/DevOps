# syntax=docker/dockerfile:1
# Bản tham khảo cho lab Spring Boot + PostgreSQL — chỉ mở sau khi đã tự viết.
# Build context là GỐC REPO (mã Spring Boot nằm trong thư mục app/):
#   docker build -f docker/Dockerfile -t taskhub:local .

# ---------- Stage 1: build (có JDK + Maven wrapper) ----------
FROM eclipse-temurin:21-jdk-noble AS build
WORKDIR /workspace

# Copy file mô tả dependency trước để tận dụng cache layer:
# chỉ khi pom.xml đổi thì bước tải dependency mới chạy lại.
COPY app/.mvn/ .mvn/
COPY app/mvnw app/pom.xml ./
RUN chmod +x mvnw && ./mvnw -B -q dependency:go-offline

# Copy mã nguồn sau cùng (thay đổi thường xuyên nhất).
COPY app/src/ src/
RUN ./mvnw -B -q package -DskipTests \
 && cp target/*.jar app.jar

# ---------- Stage 2: runtime (chỉ có JRE) ----------
FROM eclipse-temurin:21-jre-noble

# User hệ thống riêng, không đăng nhập được — không chạy app bằng root.
RUN groupadd --system taskhub \
 && useradd --system --gid taskhub --no-create-home --shell /usr/sbin/nologin taskhub

WORKDIR /app
# root sở hữu file jar, group taskhub chỉ đọc → app không sửa được chính code của nó.
COPY --from=build --chown=root:taskhub /workspace/app.jar /app/app.jar

# Liên kết image với repo GitHub khi push lên GHCR (bài 06). Đổi <username>.
LABEL org.opencontainers.image.source="https://github.com/<username>/taskhub"

USER taskhub
EXPOSE 8080

# Image jre-noble có sẵn curl. compose.yaml cũng khai báo healthcheck (ghi đè cái này).
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/actuator/health || exit 1

# Dạng exec (JSON array): java là PID 1, nhận trực tiếp SIGTERM từ "docker stop".
# MaxRAMPercentage: heap tối đa 75% RAM được cấp cho container.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "/app/app.jar"]
