# Image runtime cho dịch vụ reports (Phần C — Checkpoint CI). Không chứa lỗi cài sẵn.
FROM python:3.12-slim

RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin reports

# Phiên bản do pipeline truyền vào (--build-arg APP_VERSION=v1.0.0), hiện ở /health
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}

WORKDIR /app
COPY app.py .

USER 10001
EXPOSE 8080

# python:3.12-slim không có curl → kiểm tra sức khỏe bằng chính Python
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8080/health', timeout=2)"]

CMD ["python", "app.py"]
