#!/bin/bash
# User data cho EC2 taskhub-app (Ubuntu 24.04). cloud-init chạy file này MỘT LẦN, bằng root,
# ở lần khởi động đầu tiên. Log: /var/log/cloud-init-output.log
# KHÔNG đặt secret ở đây: ai có quyền ec2:DescribeInstanceAttribute đều đọc được user data.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# 1. Docker Engine + compose plugin từ repo apt chính thức của Docker
#    (theo docs.docker.com/engine/install/ubuntu, kiểm tra 2026-10-31)
apt-get update
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# 2. AWS CLI v2 (gói snap chính thức) — deploy.sh dùng để đọc Parameter Store
snap install aws-cli --classic

echo "user-data hoàn tất: $(docker --version); $(aws --version)"
