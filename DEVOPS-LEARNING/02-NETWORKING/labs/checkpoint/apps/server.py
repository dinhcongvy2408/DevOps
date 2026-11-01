#!/usr/bin/env python3
"""Ứng dụng HTTP tối giản dùng cho lab mạng (đóng vai "ứng dụng của team dev").

Cấu hình hoàn toàn qua biến môi trường:
  APP_NAME      tên dịch vụ, in trong log và response
  BIND_ADDR     địa chỉ lắng nghe (mặc định 0.0.0.0)
  APP_PORT      port lắng nghe (mặc định 8000)
  SLOW_PATH     tiền tố đường dẫn xử lý chậm (tùy chọn)
  SLOW_SECONDS  số giây xử lý chậm cho SLOW_PATH (tùy chọn)

Mọi đường dẫn GET đều trả 200 kèm JSON mô tả request nhận được.
"""
import json
import os
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = os.environ.get("APP_NAME", "app")
BIND = os.environ.get("BIND_ADDR", "0.0.0.0")
PORT = int(os.environ.get("APP_PORT", "8000"))
SLOW_PATH = os.environ.get("SLOW_PATH", "")
SLOW_SECONDS = float(os.environ.get("SLOW_SECONDS", "0"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if SLOW_PATH and self.path.startswith(SLOW_PATH):
            time.sleep(SLOW_SECONDS)
        body = json.dumps({
            "service": NAME,
            "hostname": socket.gethostname(),
            "path": self.path,
            "host_header": self.headers.get("Host"),
            "x_real_ip": self.headers.get("X-Real-IP"),
            "x_forwarded_for": self.headers.get("X-Forwarded-For"),
            "client_ip": self.client_address[0],
            "status": "ok",
        }).encode() + b"\n"
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except BrokenPipeError:
            # Phía gọi (ví dụ reverse proxy) đã đóng kết nối trước khi ta trả lời
            sys.stdout.write(f"{NAME}: client closed connection before response\n")
            sys.stdout.flush()

    def log_message(self, fmt, *args):
        sys.stdout.write(f"{NAME} {self.client_address[0]} - {fmt % args}\n")
        sys.stdout.flush()


if __name__ == "__main__":
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    print(f"{NAME} listening on {BIND}:{PORT}", flush=True)
    server.serve_forever()
