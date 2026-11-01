# Lời giải — Lab 01: Dashboard và 2 cảnh báo bắt buộc

> Chỉ mở sau khi đã tự làm. Quay lại lab: [lab-01-dashboard-alerts.md](../labs/lab-01-dashboard-alerts.md)
> File đầy đủ của dự án (compose, dashboard JSON, receiver) nằm ở [labs/reference/](../labs/reference/README.md). Trang này chỉ có phần lab yêu cầu tự viết và câu trả lời cho các câu ❓.

## Rule — `monitoring/prometheus/rules/alerts.yml` (phần bắt buộc)

```yaml
groups:
  - name: taskhub
    rules:
      - alert: TaskhubDown
        expr: up{job="taskhub"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "taskhub không trả lời Prometheus"
          description: "Scrape {{ $labels.instance }} thất bại hơn 1 phút."
          runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/taskhub-down.md"

  - name: host
    rules:
      - alert: HostDiskUsageHigh
        expr: |
          (1 - node_filesystem_avail_bytes{job="node", mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|9p"}
             / node_filesystem_size_bytes{job="node", mountpoint=~"/|/var/lib", fstype!~"tmpfs|overlay|9p"}) * 100
          > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk / của {{ $labels.instance }} đã dùng hơn 80%"
          description: "Đang dùng {{ printf \"%.0f\" $value }}%."
          runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/host-disk-usage-high.md"
```

Thay `phuong-dev` bằng user GitHub của bạn.

## Test — `monitoring/prometheus/tests/alerts_test.yml`

```yaml
rule_files:
  - ../rules/alerts.yml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      # phút 0..2 = 1, phút 3..9 = 0
      - series: 'up{job="taskhub", instance="taskhub:8080"}'
        values: '1x2 0x6'
    alert_rule_test:
      - eval_time: 3m
        alertname: TaskhubDown
        exp_alerts: []
      - eval_time: 5m
        alertname: TaskhubDown
        exp_alerts:
          - exp_labels:
              severity: critical
              job: taskhub
              instance: taskhub:8080
            exp_annotations:
              summary: "taskhub không trả lời Prometheus"
              description: "Scrape taskhub:8080 thất bại hơn 1 phút."
              runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/taskhub-down.md"

  - interval: 1m
    input_series:
      # size cố định 100; avail 50 (phút 0..4) rồi 15 (phút 5..15) → dùng 85% từ phút 5
      - series: 'node_filesystem_size_bytes{job="node", instance="node-exporter:9100", device="/dev/sda1", fstype="ext4", mountpoint="/"}'
        values: '100x15'
      - series: 'node_filesystem_avail_bytes{job="node", instance="node-exporter:9100", device="/dev/sda1", fstype="ext4", mountpoint="/"}'
        values: '50x4 15x10'
    alert_rule_test:
      - eval_time: 8m           # mới 3 phút > 80% → pending
        alertname: HostDiskUsageHigh
        exp_alerts: []
      - eval_time: 12m          # 7 phút > 80% ≥ for 5m → firing
        alertname: HostDiskUsageHigh
        exp_alerts:
          - exp_labels:
              severity: warning
              job: node
              instance: node-exporter:9100
              device: /dev/sda1
              fstype: ext4
              mountpoint: /
            exp_annotations:
              summary: "Disk / của node-exporter:9100 đã dùng hơn 80%"
              description: "Đang dùng 85%."
              runbook_url: "https://github.com/phuong-dev/taskhub/blob/main/docs/runbooks/host-disk-usage-high.md"
```

Kết quả mong đợi (minh họa):

```text
Unit Testing:  alerts_test.yml
  SUCCESS
```

Vì sao `exp_labels` của disk có `device`, `fstype`, `mountpoint`: phép chia `avail / size` giữ nguyên các nhãn chung của hai series (trừ `__name__`), rồi rule thêm `severity`. Thiếu một nhãn là test fail.

**D2 — ngưỡng `> 90`:** test 4 fail, promtool in hai danh sách *exp* (alert mong đợi) và *got* (alert thật — rỗng, vì 85 không > 90). Đó chính là giá trị của test: một thay đổi ngưỡng vô tình bị bắt ngay trên máy hoặc trong CI.

## Alertmanager

`alertmanager.laptop.yml` và `alertmanager.yml` giống [bản tham khảo](../labs/reference/alertmanager/alertmanager.yml) (bản laptop: `alertmanager.laptop.yml` trong cùng thư mục). Điểm phải có:

- laptop: receiver `webhook-debug`, `url: http://webhook-debug:8080/alerts`, `send_resolved: true`, nhịp ngắn (10s / 1m / 1h);
- Telegram: `bot_token_file`, `chat_id_file` trỏ vào thư mục secret gắn `:ro`; **không** có token trong YAML; nhịp chuẩn (30s / 5m / 4h).

## Trả lời các câu ❓

**B2 — Tỷ lệ 5xx khi không có lỗi / không có traffic.** Có traffic nhưng không có 5xx: tử số là tổng của tập rỗng → **không có series** → phép chia không trả gì → panel "No data" (không phải 0!). Muốn hiện 0, viết tử số `(sum(...) or vector(0))`. Không có traffic: mẫu số = 0 → 0/0 = NaN. Cả hai trường hợp alert tỷ lệ lỗi **không** kêu — đúng ý muốn (không traffic thì không có "tỷ lệ lỗi"), nhưng phải biết để không hoảng khi thấy "No data".

**C5 — T1 − T0.** Ví dụ đo được khoảng 1 phút 25 giây (minh họa — số của bạn sẽ khác, nằm trong khoảng ~1m10s–1m45s):

| Thành phần | Đóng góp |
|---|---|
| `scrape_interval: 15s` | 0–15s tới lần scrape lỗi đầu tiên |
| `evaluation_interval: 15s` | 0–15s tới lần tính rule đầu tiên thấy `up == 0` → pending |
| `for: 1m` | 60s pending (đo theo các lần evaluation) |
| `group_wait: 10s` (laptop) | 10s Alertmanager chờ gom nhóm |

Không bao giờ đúng 1 phút vì hai khoảng chờ đầu phụ thuộc thời điểm app chết rơi vào đâu trong chu kỳ 15s, cộng `group_wait`. Resolved (T3 − T2): scrape thành công tiếp theo + evaluation (alert resolve ngay, không có `for` khi hết) + Alertmanager gửi resolved theo `group_interval`. Với `group_interval: 1m`, tin resolved có thể tới muộn tới ~1 phút.

**C6 — Disk nào?** Trên laptop, node-exporter chạy trong Docker Desktop; `/:/host` gắn filesystem của **máy ảo Linux mà Docker Desktop tạo ra**. Máy ảo này **không** báo series `mountpoint="/"`: disk dữ liệu (image, container, volume) hiện ở `mountpoint="/var/lib"` (ext4), các thư mục Windows chia sẻ vào là `9p` (đã chạy thử) — vì vậy rule dùng `mountpoint=~"/|/var/lib"` và loại `9p`, nếu không alert im lặng mãi trên laptop. Con số **không** khớp `df -h /` trong WSL Ubuntu (đó là ổ ảo của distro Ubuntu), cũng không khớp ổ C:. Trên EC2, Docker chạy thẳng trên Ubuntu nên `mountpoint="/"` đúng là ổ EBS gốc — alert có ý nghĩa thật ở đó.

**E5 — Vì sao silence ở Alertmanager?** Prometheus vẫn đánh giá rule và lưu lịch sử firing (thấy trong UI, dashboard, `ALERTS` series) — bạn vẫn **biết** sự cố đang diễn ra; chỉ việc **làm phiền con người** bị tắt, có thời hạn, có người chịu trách nhiệm và lý do. Tắt rule thì mất cả việc phát hiện, dễ quên bật lại, và phải sửa code + reload.

## Kiểm tra cuối (tự chấm)

```bash
PROM="http://localhost:${PROMETHEUS_HOST_PORT:-9090}"
curl -s "$PROM/api/v1/rules" | jq -r '.data.groups[].rules[].name' | sort
# HostDiskUsageHigh
# TaskhubDown
ls monitoring/prometheus/rules/                       # KHÔNG còn zz-disk-drill.yml
git check-ignore -v monitoring/secrets/telegram_bot_token   # phải in ra dòng .gitignore khớp
jq -r '.uid' monitoring/grafana/dashboards/taskhub-overview.json   # taskhub-overview
```
