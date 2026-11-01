#!/bin/sh
# Firewall của dịch vụ reports (port 9000).
# Chính sách: chỉ các máy được phép mới gọi được reports, còn lại chặn.
set -eu

# Cho phép mạng được phép gọi reports
iptables -A INPUT -p tcp --dport 9000 -s 172.28.9.0/24 -j ACCEPT

# Chặn mọi nguồn khác tới port 9000
iptables -A INPUT -p tcp --dport 9000 -j DROP

echo "reports: firewall rules loaded"
iptables -L INPUT -n --line-numbers
