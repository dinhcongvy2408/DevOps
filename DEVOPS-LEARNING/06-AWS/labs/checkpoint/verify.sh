#!/usr/bin/env bash
# verify.sh — kiểm tra Phần C của Checkpoint GĐ 6 (stack ck06).
# Chỉ dùng lệnh ĐỌC (describe/get/list) của AWS CLI và curl. Không tạo, sửa, xóa gì.
# ĐỪNG đọc file này trước khi nộp bài — nó chứa đáp án.
#
# Dùng:  bash verify.sh            (stack mặc định: ck06)
set -uo pipefail

STACK="${STACK:-ck06}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
PASS=0
TOTAL=4

awst() { aws --region "$REGION" --output text "$@"; }
ok()   { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
ko()   { printf 'FAIL  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }

for cmd in aws curl awk; do
  command -v "$cmd" > /dev/null || { echo "Thiếu lệnh: $cmd"; exit 2; }
done

if ! awst sts get-caller-identity --query Account > /dev/null 2>&1; then
  echo "AWS CLI chưa đăng nhập được. Chạy: aws login (profile taskhub), rồi export AWS_PROFILE=taskhub"
  exit 2
fi

out() {
  awst cloudformation describe-stacks --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" 2> /dev/null
}

IID="$(out InstanceId)"
SUBNET="$(out SubnetId)"
SG="$(out SecurityGroupId)"
if [[ -z "$IID" || "$IID" == "None" ]]; then
  echo "Không tìm thấy stack '$STACK' (region $REGION) hoặc stack chưa tạo xong."
  exit 2
fi

echo "== Stack $STACK · instance $IID · region $REGION"

# --- 1. Security group cho Internet vào cổng 80 ----------------------------
sg80="$(awst ec2 describe-security-groups --group-ids "$SG" \
  --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort<=\`80\` && ToPort>=\`80\`].IpRanges[?CidrIp=='0.0.0.0/0'][])")"
if [[ "$sg80" =~ ^[0-9]+$ && "$sg80" -ge 1 ]]; then
  ok "1. Security group cho phép TCP 80 từ 0.0.0.0/0"
else
  ko "1. Security group chưa cho Internet vào cổng 80"
fi
sgall="$(awst ec2 describe-security-groups --group-ids "$SG" \
  --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='-1'])")"
[[ "$sgall" =~ ^[0-9]+$ && "$sgall" -ge 1 ]] && warn "   Có rule inbound 'All traffic' — quá rộng"

# --- 2. NACL: gói tin TCP tới cổng 80 từ Internet ---------------------------
# Luật xét theo số tăng dần, luật khớp đầu tiên quyết định.
ingress="$(awst ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query "NetworkAcls[0].Entries[?Egress==\`false\`].[RuleNumber,RuleAction,Protocol,PortRange.From,PortRange.To,CidrBlock]" \
  | sort -n)"
verdict="$(awk -v p=80 '
  $6 != "0.0.0.0/0" { next }
  $3 == "-1" { print $2; found = 1; exit }
  $3 == "6" && $4 != "None" && $4 + 0 <= p && p <= $5 + 0 { print $2; found = 1; exit }
  END { if (!found) print "deny" }' <<< "$ingress")"
if [[ "$verdict" == "allow" ]]; then
  ok "2. NACL cho phép TCP 80 từ Internet đi vào subnet"
else
  ko "2. NACL vẫn chặn TCP 80 từ Internet"
fi
allin="$(awk '$2 == "allow" && $3 == "-1" && $6 == "0.0.0.0/0"' <<< "$ingress")"
[[ -n "$allin" ]] && warn "   NACL inbound có luật allow mọi giao thức — quá rộng"

# --- 3. Session Manager -------------------------------------------------------
ping="$(awst ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$IID" \
  --query "InstanceInformationList[0].PingStatus" 2> /dev/null)"
if [[ "$ping" == "Online" ]]; then
  ok "3. Instance Online trong Systems Manager"
else
  ko "3. Instance chưa Online trong Systems Manager (PingStatus: ${ping:-không có})"
fi
egress_all="$(awst ec2 describe-security-groups --group-ids "$SG" \
  --query "length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol=='-1'])")"
[[ "$egress_all" =~ ^[0-9]+$ && "$egress_all" -ge 1 ]] && \
  warn "   Security group mở outbound mọi thứ — chấp nhận được (mặc định của AWS), nhưng hãy giải thích được vì sao bạn chọn vậy"

# --- 4. Trang web ---------------------------------------------------------------
ip="$(awst ec2 describe-instances --instance-ids "$IID" \
  --query "Reservations[0].Instances[0].PublicIpAddress")"
if [[ -z "$ip" || "$ip" == "None" ]]; then
  ko "4. Instance không có public IPv4 (đang stop?)"
else
  body="$(curl -s -m 8 "http://$ip/")"
  rc=$?
  if (( rc == 0 )) && grep -q 'ck06-ok' <<< "$body"; then
    ok "4. http://$ip/ trả về trang ck06"
  elif (( rc == 7 )); then
    ko "4. Connection refused tới $ip:80"
  elif (( rc == 28 )); then
    ko "4. Timeout tới $ip:80"
  else
    ko "4. http://$ip/ chưa trả về trang ck06 (curl exit $rc)"
  fi
fi

echo "== Kết quả: $PASS/$TOTAL"
(( PASS == TOTAL ))
