#!/bin/sh
# Script khởi động api — do đồng nghiệp viết "để sau này thêm bước chuẩn bị".
echo "[start.sh] starting api (pid of this shell: $$)"
python /app/app.py
echo "[start.sh] api exited with code $?"
