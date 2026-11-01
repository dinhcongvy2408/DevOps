# Bộ nhận webhook tối giản cho laptop: in tóm tắt từng alert Alertmanager gửi tới, rồi trả 200.
# Chạy trong container python:3.12-slim (service webhook-debug, profile "debug"). Không cần thư viện ngoài.
import json
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        payload = json.loads(body or b"{}")
        for alert in payload.get("alerts", []):
            print(f'[{alert.get("status")}] {alert["labels"].get("alertname")} '
                  f'severity={alert["labels"].get("severity")} '
                  f'summary={alert.get("annotations", {}).get("summary")}', flush=True)
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):  # tắt log truy cập mặc định, chỉ giữ dòng alert ở trên
        pass


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
