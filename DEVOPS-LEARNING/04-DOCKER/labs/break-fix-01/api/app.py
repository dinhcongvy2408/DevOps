"""taskhub-lite API — ứng dụng "của team dev" cho Break-fix Docker #1.

KHÔNG SỬA FILE NÀY. Lỗi của bài lab nằm ở hạ tầng (Dockerfile, start.sh,
compose.yaml, cấu hình nginx), không nằm ở code ứng dụng.
"""
import json
import os
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psycopg

DB = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": os.environ.get("DB_PORT", "5432"),
    "dbname": os.environ.get("DB_NAME", "taskhub"),
    "user": os.environ.get("DB_USER", "taskhub"),
    "password": os.environ.get("DB_PASSWORD", ""),
}
LISTEN_PORT = 8000


def log(msg):
    print(f"[api] {msg}", flush=True)


def connect():
    return psycopg.connect(connect_timeout=3, **DB)


def init_db():
    log(f"connecting to database {DB['user']}@{DB['host']}:{DB['port']}/{DB['dbname']} ...")
    try:
        with connect() as conn:
            conn.execute(
                "CREATE TABLE IF NOT EXISTS tasks ("
                " id SERIAL PRIMARY KEY,"
                " title TEXT NOT NULL,"
                " created_at TIMESTAMPTZ NOT NULL DEFAULT now())"
            )
    except psycopg.OperationalError as exc:
        log(f"FATAL cannot connect to database at {DB['host']}:{DB['port']}: {exc}")
        sys.exit(1)
    log("database ready, table 'tasks' ok")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/health":
            try:
                with connect() as conn:
                    conn.execute("SELECT 1")
                self._send(200, {"status": "UP", "db": "ok"})
            except psycopg.Error as exc:
                self._send(503, {"status": "DOWN", "db": str(exc).strip()})
        elif self.path == "/api/tasks":
            with connect() as conn:
                rows = conn.execute(
                    "SELECT id, title, created_at FROM tasks ORDER BY id"
                ).fetchall()
            self._send(200, [
                {"id": r[0], "title": r[1], "created_at": r[2].isoformat()} for r in rows
            ])
        else:
            self._send(404, {"error": "not found", "path": self.path})

    def do_POST(self):
        if self.path != "/api/tasks":
            self._send(404, {"error": "not found", "path": self.path})
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            title = json.loads(self.rfile.read(length) or b"{}").get("title", "").strip()
        except json.JSONDecodeError:
            title = ""
        if not title:
            self._send(400, {"error": "field 'title' is required"})
            return
        with connect() as conn:
            row = conn.execute(
                "INSERT INTO tasks (title) VALUES (%s) RETURNING id", (title,)
            ).fetchone()
        self._send(201, {"id": row[0], "title": title})

    def log_message(self, fmt, *args):
        log(f"{self.address_string()} {fmt % args}")


def main():
    init_db()
    server = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)

    def on_sigterm(signum, frame):
        log("received SIGTERM, shutting down gracefully")
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, on_sigterm)
    log(f"listening on 0.0.0.0:{LISTEN_PORT} (pid={os.getpid()}, uid={os.getuid()})")
    server.serve_forever()
    log("bye")


if __name__ == "__main__":
    main()
