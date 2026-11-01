#!/bin/sh
# Sinh chứng chỉ TLS tự ký (self-signed) cho edge. Chạy trong container certgen.
# Chứng chỉ được ghi vào volume "certs", edge và client cùng đọc từ đó.
set -eu

apk add --no-cache openssl >/dev/null

DOMAIN="www.taskhub.test"

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /certs/edge.key -out /certs/edge.crt \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN}"

chmod 600 /certs/edge.key   # chỉ root (process master của nginx) đọc được khóa bí mật
chmod 644 /certs/edge.crt   # chứng chỉ là công khai

echo "certgen: generated certificate for ${DOMAIN}"
