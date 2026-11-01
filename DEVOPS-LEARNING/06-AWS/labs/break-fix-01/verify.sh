#!/usr/bin/env bash
# verify.sh — kiểm tra tiến độ Break-fix AWS #1 (stack bf06).
# Chỉ dùng lệnh ĐỌC (describe/get/list) của AWS CLI và curl. Không tạo, sửa, xóa gì.
# ĐỪNG đọc file này trước khi xong bài — nó chứa đáp án.
#
# Dùng:  bash verify.sh            (stack mặc định: bf06)
#        STACK=ten-khac bash verify.sh
set -uo pipefail

STACK="${STACK:-bf06}"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
PASS=0
TOTAL=6

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

# --- 1. Đường ra Internet của subnet -------------------------------------
routes="$(awst ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].[GatewayId,State]")"
if [[ "$routes" == igw-*active* ]]; then
  ok "1. Route table của subnet có 0.0.0.0/0 → Internet Gateway (active)"
else
  ko "1. Subnet chưa có đường ra Internet đúng (route table đang gắn với subnet)"
fi

# --- 2. Security group mở cổng 80 cho Internet ---------------------------
sg80="$(awst ec2 describe-security-groups --group-ids "$SG" \
  --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='-1' || (IpProtocol=='tcp' && FromPort<=\`80\` && ToPort>=\`80\`)].IpRanges[?CidrIp=='0.0.0.0/0'][])")"
if [[ "$sg80" =~ ^[0-9]+$ && "$sg80" -ge 1 ]]; then
  ok "2. Security group cho phép TCP 80 từ 0.0.0.0/0"
  sg8080="$(awst ec2 describe-security-groups --group-ids "$SG" \
    --query "length(SecurityGroups[0].IpPermissions[?FromPort==\`8080\`])")"
  [[ "$sg8080" =~ ^[0-9]+$ && "$sg8080" -ge 1 ]] && warn "   Rule 8080 vẫn còn — không ai dùng cổng này, nên xóa (quyền tối thiểu)"
  sgall="$(awst ec2 describe-security-groups --group-ids "$SG" \
    --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='-1'])")"
  [[ "$sgall" =~ ^[0-9]+$ && "$sgall" -ge 1 ]] && warn "   Có rule 'All traffic' vào — quá rộng, chỉ cần TCP 80"
else
  ko "2. Security group chưa cho phép TCP 80 từ Internet"
fi

# --- 3. NACL cho phép gói tin trả lời đi ra cổng tạm của client ----------
# Mô phỏng cách NACL xét luật: theo thứ tự số luật tăng dần, luật khớp đầu tiên quyết định.
nacl_eval() { # $1 = cổng đích của gói tin đi ra
  awk -v p="$1" '
    $6 != "0.0.0.0/0" { next }
    $3 == "-1" { print $2; found = 1; exit }
    $3 == "6" && $4 != "None" && $4 + 0 <= p && p <= $5 + 0 { print $2; found = 1; exit }
    END { if (!found) print "deny" }'
}
egress="$(awst ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query "NetworkAcls[0].Entries[?Egress==\`true\`].[RuleNumber,RuleAction,Protocol,PortRange.From,PortRange.To,CidrBlock]" \
  | sort -n)"
all_allow=1
for port in 32768 49152 60999 65535; do
  [[ "$(nacl_eval "$port" <<< "$egress")" == "allow" ]] || all_allow=0
done
if (( all_allow )); then
  ok "3. NACL cho phép gói tin trả lời ra các cổng tạm (ephemeral) của client"
  [[ "$(nacl_eval 1024 <<< "$egress")" == "allow" ]] || warn "   Dải cổng hẹp hơn khuyến nghị 1024-65535 của AWS"
else
  ko "3. NACL của subnet vẫn chặn một phần lưu lượng cần thiết"
fi

# --- 4. Session Manager dùng được -----------------------------------------
prof_arn="$(awst ec2 describe-instances --instance-ids "$IID" \
  --query "Reservations[0].Instances[0].IamInstanceProfile.Arn")"
prof_name="${prof_arn##*/}"
role="$(awst iam get-instance-profile --instance-profile-name "$prof_name" \
  --query "InstanceProfile.Roles[0].RoleName" 2> /dev/null)"
has_core=0
if [[ -n "$role" && "$role" != "None" ]] && \
   awst iam list-attached-role-policies --role-name "$role" \
     --query "AttachedPolicies[].PolicyName" | tr '\t' '\n' | grep -qx 'AmazonSSMManagedInstanceCore'; then
  has_core=1
fi
ping="$(awst ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$IID" \
  --query "InstanceInformationList[0].PingStatus" 2> /dev/null)"
if (( has_core )) && [[ "$ping" == "Online" ]]; then
  ok "4. Instance là managed node của Systems Manager (PingStatus Online)"
elif (( has_core )); then
  ko "4. Quyền đã đúng nhưng instance chưa Online trong Systems Manager (chờ vài phút; còn đường mạng nào chặn agent không?)"
else
  ko "4. Instance chưa đủ điều kiện để Session Manager hoạt động"
fi

# --- 5 & 6. Trang web ------------------------------------------------------
ip="$(awst ec2 describe-instances --instance-ids "$IID" \
  --query "Reservations[0].Instances[0].PublicIpAddress")"
if [[ -z "$ip" || "$ip" == "None" ]]; then
  ko "5. Instance không có public IPv4 (đang stop? Đừng stop/terminate instance trong bài này)"
  ko "6. Không kiểm tra được trang web"
else
  resp="$(curl -s -m 8 -D - "http://$ip/")"
  rc=$?
  case "$rc" in
    0)
      if grep -qi '^server: nginx' <<< "$resp"; then
        ok "5. Có web server nginx trả lời ở http://$ip/"
      else
        ko "5. Có thứ trả lời ở cổng 80 nhưng không phải nginx"
      fi
      if grep -q 'bf06-ok' <<< "$resp"; then
        ok "6. Trang đúng nội dung (bf06-ok)"
      else
        ko "6. Trang trả về KHÔNG phải trang của bf06 — đọc kỹ nội dung curl trả về"
      fi
      ;;
    7)
      ko "5. Kết nối tới $ip:80 bị TỪ CHỐI (connection refused) — gói tin đã tới nơi, nhưng không có gì lắng nghe"
      ko "6. Chưa có trang web"
      ;;
    28)
      ko "5. Kết nối tới $ip:80 bị QUÁ GIỜ (timeout) — gói tin hoặc gói trả lời bị chặn đâu đó trên đường"
      ko "6. Chưa có trang web"
      ;;
    *)
      ko "5. curl lỗi mã $rc khi gọi http://$ip/"
      ko "6. Chưa có trang web"
      ;;
  esac
fi

echo "== Kết quả: $PASS/$TOTAL"
(( PASS == TOTAL ))
