# reports — mã nguồn cho Phần C của Checkpoint CI

Đề bài nằm ở [checkpoint.md — Phần C](../../checkpoint.md#phần-c--break-fix-90-phút). Đọc đề bài trước khi mở các file ở đây.

| File | Nội dung | Được sửa? |
|---|---|---|
| `app.py` | Dịch vụ HTTP nhỏ (thư viện chuẩn Python): `GET /health`, `POST /summary` | Không |
| `tests/test_app.py` | Unit test, chạy bằng `python -m unittest discover -s tests -v` | Không |
| `Dockerfile`, `.dockerignore` | Image runtime `python:3.12-slim`, user non-root, nhận `APP_VERSION` lúc build | Không |
| `.github/workflows/ci.yml` | Workflow `CI` — **có lỗi** | ✅ |
| `.github/workflows/release.yml` | Workflow `Release` — **có lỗi** | ✅ |
| `logs/*.txt` | Log thu thập từ các lần chạy hỏng (minh họa) | Chỉ đọc |

Chạy thử không cần Docker (trên WSL):

```bash
python3 -m unittest discover -s tests -v
APP_VERSION=local python3 app.py     # terminal khác: curl -s localhost:8080/health ; Ctrl+C để dừng
```

> Thư mục `.github/` bắt đầu bằng dấu chấm nên bị ẩn khi `ls` thường — dùng `ls -la`.
