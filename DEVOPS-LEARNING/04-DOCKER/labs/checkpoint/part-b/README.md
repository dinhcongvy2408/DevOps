# notes — mã nguồn cho Phần B của Checkpoint Docker

Đề bài nằm ở [checkpoint.md — Phần B](../../../checkpoint.md#phần-b--thực-hành-90-phút).

| File | Nội dung |
|---|---|
| `notes.py` | Dịch vụ ghi chú, chỉ dùng thư viện chuẩn Python, lưu SQLite tại `NOTES_DB` (mặc định `/data/notes.db`), nghe port `8080` |
| `tests/test_notes.py` | Unit test, chạy bằng `python -m unittest discover -s tests` |

Chạy thử không cần Docker (trên WSL):

```bash
python3 -m unittest discover -s tests -v
NOTES_DB=/tmp/notes.db python3 notes.py     # Ctrl+C để dừng
```

Bạn **không sửa** `notes.py` và `tests/` (trừ bước cố ý làm hỏng test theo đề bài, rồi khôi phục).
