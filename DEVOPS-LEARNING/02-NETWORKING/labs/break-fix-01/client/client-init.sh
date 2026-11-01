#!/bin/bash
# Chuẩn bị jump host: cài công cụ chẩn đoán mạng, cài lệnh verify, rồi chạy mãi.
set -eu

echo "client: waiting for DNS..."
for _ in $(seq 1 30); do
  getent hosts archive.ubuntu.com >/dev/null 2>&1 && break
  sleep 2
done

echo "client: installing network tools (1-2 phút)..."
apt-get update >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  dnsutils curl iproute2 iputils-ping netcat-openbsd tcpdump traceroute \
  ca-certificates less nano >/dev/null

install -m 0755 /opt/lab/verify.sh /usr/local/bin/verify

echo "client ready — vào bằng: docker compose exec client bash"
exec sleep infinity
