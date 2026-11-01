"""reports — dịch vụ nhỏ cho Phần C của Checkpoint CI (Module 05).

Không cần sửa file này. Lỗi của bài nằm trong .github/workflows/.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
VERSION = os.environ.get("APP_VERSION", "dev")


def summarize(values):
    """Tóm tắt danh sách số nguyên không âm: số phần tử, tổng, lớn nhất."""
    if not isinstance(values, list):
        raise ValueError("values phải là một danh sách")
    for v in values:
        if isinstance(v, bool) or not isinstance(v, int) or v < 0:
            raise ValueError("mọi phần tử phải là số nguyên không âm")
    return {"count": len(values), "total": sum(values), "max": max(values, default=0)}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok", "version": VERSION})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/summary":
            self._send(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length) or b"{}")
            self._send(200, summarize(data.get("values")))
        except (ValueError, AttributeError) as exc:
            self._send(400, {"error": str(exc)})


if __name__ == "__main__":
    print(f"[reports] version={VERSION} port={PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
