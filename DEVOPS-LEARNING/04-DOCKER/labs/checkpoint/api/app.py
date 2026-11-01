"""reports-api — nhận và lưu báo cáo dạng JSON Lines vào /data.

KHÔNG SỬA FILE NÀY. Lỗi của phần C nằm ở hạ tầng.
"""
import json
import os
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG_PATH = "/app/config/settings.json"
DATA_FILE = os.environ.get("REPORTS_FILE", "/data/reports.jsonl")


def log(msg):
    print(f"[reports-api] {msg}", flush=True)


try:
    with open(CONFIG_PATH, encoding="utf-8") as f:
        SETTINGS = json.load(f)
except FileNotFoundError:
    log(f"FATAL config file not found: {CONFIG_PATH}")
    sys.exit(1)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/health", "/api/health"):
            self._send(200, {"status": "ok", "env": SETTINGS.get("env")})
        elif self.path == "/api/reports":
            items = []
            if os.path.exists(DATA_FILE):
                with open(DATA_FILE, encoding="utf-8") as f:
                    items = [json.loads(line) for line in f if line.strip()]
            self._send(200, items[-50:])
        else:
            self._send(404, {"error": "not found", "path": self.path})

    def do_POST(self):
        if self.path != "/api/reports":
            self._send(404, {"error": "not found", "path": self.path})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            data = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid JSON"})
            return
        record = {
            "source": str(data.get("source", "unknown")),
            "title": str(data.get("title", "")),
            "received_at": datetime.now(timezone.utc).isoformat(),
        }
        try:
            with open(DATA_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        except OSError as exc:
            log(f"ERROR cannot write {DATA_FILE}: {exc}")
            self._send(500, {"error": f"cannot write report: {exc}"})
            return
        self._send(201, record)

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} {fmt % args}")


if __name__ == "__main__":
    log(f"env={SETTINGS.get('env')} data_file={DATA_FILE} uid={os.getuid()}")
    server = ThreadingHTTPServer(("0.0.0.0", 8000), Handler)
    log("listening on 0.0.0.0:8000")
    server.serve_forever()
