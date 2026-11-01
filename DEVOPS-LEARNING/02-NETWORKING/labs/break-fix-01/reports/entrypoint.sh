#!/bin/sh
# Khởi động dịch vụ reports: cài iptables, nạp luật firewall, rồi chạy ứng dụng.
set -eu

echo "reports: installing iptables..."
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends iptables >/dev/null

echo "reports: loading firewall rules from /opt/reports/firewall.sh"
sh /opt/reports/firewall.sh

exec python /srv/server.py
