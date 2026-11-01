#!/usr/bin/env bash
# Break-fix Observability #1 — dựng hệ thống giám sát "bf08" có lỗi cài sẵn.
# Chạy trong [WSL] (Docker Desktop đã bật WSL integration). Chi phí: 0 USD.
#
# Script chỉ TẠO thư mục mới và các container của Compose project "bf08".
# Nó từ chối chạy nếu thư mục đã tồn tại hoặc project bf08 đã có container.
#
# Đổi cổng (khi bị chiếm) bằng biến môi trường TRƯỚC khi chạy, ví dụ:
#   BF08_GRAFANA_PORT=23000 BF08_PROM_PORT=29090 bash setup.sh
# Giá trị được ghi vào file .env của lab để các lệnh docker compose sau dùng lại.

set -euo pipefail

LAB_DIR="${BF08_DIR:-$HOME/devops-lab/08-monitoring/bf08}"

die() { echo "❌ $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "Không tìm thấy lệnh docker."
docker info >/dev/null 2>&1 || die "Không kết nối được Docker daemon. Bật WSL integration trong Docker Desktop (xem Docker bài 01)."
docker compose version >/dev/null 2>&1 || die "Không có 'docker compose' (Compose v2)."

[[ -e "$LAB_DIR" ]] && die "Thư mục $LAB_DIR đã tồn tại. Dọn dẹp theo README mục 11 rồi chạy lại."
if [[ -n "$(docker ps -aq --filter label=com.docker.compose.project=bf08)" ]]; then
  die "Đã có container của project bf08. Dọn dẹp theo README mục 11 rồi chạy lại."
fi

mkdir -p "$LAB_DIR"/{app,webhook,prometheus,alertmanager,alloy,grafana/provisioning/datasources}
cd "$LAB_DIR"

# ---------------------------------------------------------------- .env (cổng)
cat > .env <<EOF
BF08_APP_PORT=${BF08_APP_PORT:-18088}
BF08_PROM_PORT=${BF08_PROM_PORT:-19090}
BF08_AM_PORT=${BF08_AM_PORT:-19093}
BF08_WEBHOOK_PORT=${BF08_WEBHOOK_PORT:-15001}
BF08_LOKI_PORT=${BF08_LOKI_PORT:-13100}
BF08_GRAFANA_PORT=${BF08_GRAFANA_PORT:-13000}
BF08_GRAFANA_PASSWORD=${BF08_GRAFANA_PASSWORD:-bf08-admin}
EOF

# ---------------------------------------------------------------- app demo
cat > app/requirements.txt <<'EOF'
prometheus_client==0.26.0
EOF

cat > app/Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
USER nobody
EXPOSE 8080 8000
CMD ["python", "-u", "app.py"]
EOF

cat > app/app.py <<'EOF'
"""App demo cho bf08: HTTP ở cổng 8080, metrics Prometheus ở cổng 8000, log JSON ra stdout."""
import json
import random
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from prometheus_client import Counter, Histogram, start_http_server

KNOWN_PATHS = {"/", "/fail", "/slow"}
REQUESTS = Counter("demo_requests_total", "So request HTTP", ["path", "status"])
LATENCY = Histogram("demo_request_duration_seconds", "Thoi gian xu ly request", ["path"])


def log(level, msg, **fields):
    print(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "level": level, "msg": msg, **fields}), flush=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        start = time.time()
        path = self.path.split("?")[0]
        if path == "/":
            status, body = 200, b"bf08 demo ok\n"
        elif path == "/fail":
            status, body = 500, b"boom\n"
        elif path == "/slow":
            time.sleep(random.uniform(0.4, 0.7))
            status, body = 200, b"slow ok\n"
        else:
            status, body = 404, b"not found\n"
        label = path if path in KNOWN_PATHS else "other"  # giữ cardinality thấp
        REQUESTS.labels(path=label, status=str(status)).inc()
        LATENCY.labels(path=label).observe(time.time() - start)
        level = "error" if status >= 500 else "info"
        log(level, "request", path=path, status=status, request_id=uuid.uuid4().hex[:12],
            duration_ms=round((time.time() - start) * 1000, 1))
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # tắt log mặc định dạng text của http.server
        pass


def heartbeat():
    while True:
        log("info", "heartbeat")
        time.sleep(5)


if __name__ == "__main__":
    start_http_server(8000)
    threading.Thread(target=heartbeat, daemon=True).start()
    log("info", "started", http_port=8080, metrics_port=8000)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
EOF

# ---------------------------------------------------------------- webhook-debug
cat > webhook/Dockerfile <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY webhook.py .
USER nobody
EXPOSE 5001
CMD ["python", "-u", "webhook.py"]
EOF

cat > webhook/webhook.py <<'EOF'
"""Receiver giả của Alertmanager: POST nhận cảnh báo, GET trả danh sách đã nhận (JSON)."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RECEIVED = []


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        payload = json.loads(self.rfile.read(length) or b"{}")
        for alert in payload.get("alerts", []):
            item = {
                "status": alert.get("status"),
                "alertname": alert.get("labels", {}).get("alertname"),
                "severity": alert.get("labels", {}).get("severity"),
                "receiver": payload.get("receiver"),
                "startsAt": alert.get("startsAt"),
            }
            RECEIVED.append(item)
            print(json.dumps(item, ensure_ascii=False), flush=True)
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        body = json.dumps(RECEIVED[-500:], ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("0.0.0.0", 5001), Handler).serve_forever()
EOF

# ---------------------------------------------------------------- compose
cat > compose.yaml <<'EOF'
name: bf08

services:
  app:
    build: ./app
    image: bf08-app:local
    ports:
      - "127.0.0.1:${BF08_APP_PORT:-18088}:8080"
    mem_limit: 128m
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.12.1
    mem_limit: 64m
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v3.15.1
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=1d
      - --web.enable-lifecycle
    volumes:
      - ./prometheus:/etc/prometheus:ro
    ports:
      - "127.0.0.1:${BF08_PROM_PORT:-19090}:9090"
    mem_limit: 256m
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:v0.34.2
    command:
      - --config.file=/etc/alertmanager/alertmanager.yml
    volumes:
      - ./alertmanager:/etc/alertmanager:ro
    ports:
      - "127.0.0.1:${BF08_AM_PORT:-19093}:9093"
    mem_limit: 64m
    restart: unless-stopped

  webhook-debug:
    build: ./webhook
    image: bf08-webhook:local
    ports:
      - "127.0.0.1:${BF08_WEBHOOK_PORT:-15001}:5001"
    mem_limit: 64m
    restart: unless-stopped

  loki:
    image: grafana/loki:3.7.9
    ports:
      - "127.0.0.1:${BF08_LOKI_PORT:-13100}:3100"
    mem_limit: 256m
    restart: unless-stopped

  alloy:
    image: grafana/alloy:v1.21.3
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy/data
      - /etc/alloy/config.alloy
    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy:ro
    mem_limit: 192m
    restart: unless-stopped

  grafana:
    image: grafana/grafana:13.3.0
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${BF08_GRAFANA_PASSWORD:-bf08-admin}
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    ports:
      - "127.0.0.1:${BF08_GRAFANA_PORT:-13000}:3000"
    mem_limit: 384m        # Grafana 13 rảnh đã ~230 MiB (đo thật) — 256m quá sát
    restart: unless-stopped
EOF

# ---------------------------------------------------------------- Prometheus
cat > prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - /etc/prometheus/rules.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: app
    static_configs:
      - targets: ["app:8080"]

  - job_name: node
    static_configs:
      - targets: ["node-exporter:9100"]

  - job_name: alertmanager
    static_configs:
      - targets: ["alertmanager:9093"]

  - job_name: loki
    static_configs:
      - targets: ["loki:3100"]

  - job_name: alloy
    static_configs:
      - targets: ["alloy:12345"]
EOF

cat > prometheus/rules.yml <<'EOF'
groups:
  - name: bf08-alerts
    rules:
      - alert: Watchdog
        expr: vector(1)
        labels:
          severity: warning
        annotations:
          summary: "Đường ống cảnh báo còn sống (alert này luôn firing)"

      - alert: AppDown
        expr: up{job="demo-app"} == 0
        for: 1m
        labels:
          severity: crit
        annotations:
          summary: "App demo {{ $labels.instance }} không scrape được quá 1 phút"

      - alert: HighErrorRate
        expr: |
          sum(rate(demo_requests_total{status=~"5.."}[5m]))
            / sum(rate(demo_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Hơn 5% request trả lỗi 5xx trong 5 phút"
EOF

# ---------------------------------------------------------------- Alertmanager
cat > alertmanager/alertmanager.yml <<'EOF'
route:
  receiver: blackhole
  group_by: [alertname]
  group_wait: 10s
  group_interval: 1m
  repeat_interval: 4h
  routes:
    - matchers:
        - severity =~ "critical|warning"
      receiver: webhook-debug

receivers:
  - name: blackhole

  - name: webhook-debug
    webhook_configs:
      - url: http://webhook-debug:5001/alerts
        send_resolved: true
EOF

# ---------------------------------------------------------------- Alloy
cat > alloy/config.alloy <<'EOF'
// Chỉ đọc log của container thuộc project bf08 (máy bạn còn nhiều container khác)
discovery.docker "bf08" {
  host = "unix:///var/run/docker.sock"

  filter {
    name   = "label"
    values = ["com.docker.compose.project=bf08"]
  }
}

// Gắn label ít giá trị (low cardinality): tên service và tên container
discovery.relabel "bf08" {
  targets = []

  rule {
    source_labels = ["__meta_docker_container_label_com_docker_compose_service"]
    target_label  = "compose_service"
  }

  rule {
    source_labels = ["__meta_docker_container_name"]
    regex         = "/(.*)"
    target_label  = "container"
  }
}

loki.source.docker "bf08" {
  host          = "unix:///var/run/docker.sock"
  targets       = discovery.docker.bf08.targets
  labels        = { compose_project = "bf08" }
  relabel_rules = discovery.relabel.bf08.rules
  forward_to    = [loki.process.json.receiver]
}

// Log của app là JSON: lấy trường "level" làm label (chỉ vài giá trị: info, error…)
loki.process "json" {
  forward_to = [loki.write.local.receiver]

  stage.json {
    expressions = { level = "level" }
  }

  stage.labels {
    values = { level = "" }
  }
}

loki.write "local" {
  endpoint {
    url = "http://loki:3100/api/v1/push"
  }
}
EOF

# ---------------------------------------------------------------- Grafana
cat > grafana/provisioning/datasources/datasources.yaml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true

  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
EOF

# ---------------------------------------------------------------- khởi động
echo "▶ Build image app/webhook và khởi động project bf08 (lần đầu có thể mất vài phút để tải image)…"
docker compose up -d --build

# shellcheck disable=SC1091
source ./.env
cat <<EOF

✅ bf08 đã chạy. Thư mục: $LAB_DIR

  App demo      http://127.0.0.1:${BF08_APP_PORT}/
  Prometheus    http://127.0.0.1:${BF08_PROM_PORT}/
  Alertmanager  http://127.0.0.1:${BF08_AM_PORT}/
  Webhook-debug http://127.0.0.1:${BF08_WEBHOOK_PORT}/   (danh sách cảnh báo đã nhận, JSON)
  Grafana       http://127.0.0.1:${BF08_GRAFANA_PORT}/   (admin / ${BF08_GRAFANA_PASSWORD})

Chờ khoảng 1 phút cho mọi thứ khởi động, rồi đọc các ticket trong README.
EOF
