"""notes — dịch vụ ghi chú tối giản cho Phần B của Checkpoint Docker.

Chỉ dùng thư viện chuẩn của Python. Dữ liệu lưu trong SQLite tại NOTES_DB
(mặc định /data/notes.db). Nghe port 8080.

Endpoint:
  GET  /health   -> {"status": "ok"}
  GET  /notes    -> danh sách ghi chú
  POST /notes    -> body {"title": "..."} -> tạo ghi chú
"""
import json
import os
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB_PATH = os.environ.get("NOTES_DB", "/data/notes.db")
PORT = int(os.environ.get("PORT", "8080"))
MAX_TITLE = 200


def validate_title(raw):
    """Chuẩn hóa tiêu đề; ném ValueError nếu không hợp lệ."""
    if not isinstance(raw, str):
        raise ValueError("title must be a string")
    title = raw.strip()
    if not title:
        raise ValueError("title is required")
    if len(title) > MAX_TITLE:
        raise ValueError(f"title longer than {MAX_TITLE} characters")
    return title


def db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, title TEXT NOT NULL)")
    return conn


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        elif self.path == "/notes":
            with db() as conn:
                rows = conn.execute("SELECT id, title FROM notes ORDER BY id").fetchall()
            self._send(200, [{"id": r[0], "title": r[1]} for r in rows])
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/notes":
            self._send(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            title = validate_title(json.loads(self.rfile.read(length) or b"{}").get("title"))
        except (ValueError, json.JSONDecodeError, AttributeError) as exc:
            self._send(400, {"error": str(exc)})
            return
        with db() as conn:
            cur = conn.execute("INSERT INTO notes (title) VALUES (?)", (title,))
        self._send(201, {"id": cur.lastrowid, "title": title})


if __name__ == "__main__":
    print(f"[notes] db={DB_PATH} port={PORT} uid={os.getuid()}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
