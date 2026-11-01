#!/bin/bash
# Chuẩn bị máy monitoring: chờ DNS, cài công cụ chẩn đoán, cài lệnh verify-checkpoint.
set -eu

echo "client: waiting for DNS..."
for _ in $(seq 1 45); do
  getent hosts archive.ubuntu.com >/dev/null 2>&1 && break
  sleep 2
done

echo "client: installing network tools (1-2 phút)..."
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  dnsutils curl openssl iproute2 iputils-ping netcat-openbsd tcpdump traceroute \
  ca-certificates less nano >/dev/null

install -m 0755 /opt/lab/verify.sh /usr/local/bin/verify-checkpoint

echo "client ready — vào bằng: docker compose exec client bash"
exec sleep infinity
