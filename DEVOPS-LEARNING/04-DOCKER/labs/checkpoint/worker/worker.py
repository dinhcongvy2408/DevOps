"""report-worker — cứ 5 giây gửi một báo cáo tự động tới reports-api.

KHÔNG SỬA FILE NÀY.
"""
import json
import os
import time
import urllib.error
import urllib.request

API_URL = os.environ.get("API_URL", "http://api:8000")


def log(msg):
    print(f"[worker] {msg}", flush=True)


def send(n):
    body = json.dumps({"source": "worker", "title": f"auto report #{n}"}).encode()
    req = urllib.request.Request(
        f"{API_URL}/api/reports", data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=3) as resp:
        return resp.status


if __name__ == "__main__":
    log(f"started, target={API_URL}")
    n = 0
    while True:
        n += 1
        try:
            log(f"sent report #{n} -> HTTP {send(n)}")
        except urllib.error.HTTPError as exc:
            log(f"error sending report #{n}: HTTP {exc.code} {exc.read().decode(errors='replace')}")
        except (urllib.error.URLError, OSError) as exc:
            log(f"error sending report #{n}: {exc}")
        time.sleep(5)
