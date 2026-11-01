# Lời giải — Bài 05: Amazon S3

> Chỉ mở sau khi đã tự làm. Bài: [05-s3.md](../05-s3.md). Output trong file này là minh họa.

## Câu hỏi kiểm tra kiến thức (mục 13)

**1. Object storage khác block storage ở điểm nào?** Block storage (EBS) xuất hiện trong hệ điều hành như một ổ đĩa: ghi được từng khối, có filesystem, truy cập ngẫu nhiên với độ trễ thấp. Object storage (S3) truy cập qua HTTP API theo **cả object**: muốn sửa một byte phải ghi lại toàn bộ object, độ trễ mỗi request cao hơn nhiều. PostgreSQL cần ghi ngẫu nhiên từng trang dữ liệu nhỏ và cần `fsync`, nên không thể chạy trên S3. S3 chỉ phù hợp để lưu **bản backup** của database.

**2. Vì sao tên bucket có account ID?** Tên bucket là **duy nhất toàn cầu** trong cùng một partition AWS. Một tên chung chung như `taskhub-backups` rất dễ đã có người dùng. Thêm account ID giúp tên gần như chắc chắn chưa bị lấy, và nhìn vào là biết bucket thuộc tài khoản nào. Còn dữ liệu của bucket thì nằm ở **một region** (`ap-southeast-1`).

**3. Ba mặc định an toàn là gì?** Block Public Access bật sẵn, Object Ownership = Bucket owner enforced (ACL tắt), và mã hóa SSE-S3. **SSE-S3 không tắt được**: theo FAQ, từ 05/01/2023 mọi object mới đều được mã hóa. BPA và ACL thì chỉnh được, nhưng không nên.

**4. Lỗi `AccessControlListNotSupported` khi `--acl public-read`?** Bucket đang ở chế độ Bucket owner enforced: ACL bị vô hiệu, mọi request đặt ACL cấp quyền đều bị từ chối. Đây là chủ đích của AWS. Cách đúng để chia sẻ một file là dùng **presigned URL** có thời hạn. Nếu cần chia sẻ lâu dài với một tài khoản AWS cụ thể thì dùng bucket policy. Chỉ trường hợp đặc biệt như static website mới mở public, và khi đó phải chủ động chỉnh BPA cùng policy.

**5. Bucket policy khác IAM policy ở đâu?** IAM policy gắn vào **danh tính** (user/role) và không có trường `Principal`. Bucket policy gắn vào **bucket** và có trường `Principal`. **Bắt buộc** dùng bucket policy khi:
- cấp quyền cho **tài khoản AWS khác** (cross-account);
- đặt quy tắc áp dụng cho **mọi người**, kể cả những ai bạn không quản lý IAM, ví dụ Deny khi không dùng TLS, hoặc Deny khi request không đến từ một VPC endpoint.

**6. Bucket policy Deny, IAM policy Allow thì sao?** Request **bị từ chối**. Trong logic đánh giá policy, **Deny tường minh luôn thắng** mọi Allow, bất kể Deny nằm ở policy loại nào.

**7. `aws s3 rm` trong bucket có versioning làm gì?** Lệnh `aws s3 rm` không truyền `versionId`, nên S3 **không xóa dữ liệu** mà chỉ thêm một **delete marker** làm phiên bản current. Mọi phiên bản cũ vẫn còn. `GET` trả 404 vì phiên bản current là marker. Muốn lấy lại file: xóa delete marker theo `versionId` của nó.

**8. Dùng cách khôi phục nào cho trường hợp nào?**
- **Xóa nhầm** thì gỡ delete marker. Thao tác nhanh, không tạo phiên bản mới.
- **Ghi đè nhầm** thì copy phiên bản cũ đè lên chính key đó. Cách này tạo thêm một phiên bản mới có nội dung cũ và **giữ nguyên toàn bộ lịch sử**, kể cả bản bị ghi đè. Có thể bạn sẽ cần lại bản đó để điều tra. Xóa các phiên bản mới hơn là thao tác **vĩnh viễn**, không hoàn tác được.

**9. Vì sao versioning thiếu lifecycle là bom chi phí?** Mỗi phiên bản là **một object đầy đủ** và bị tính tiền lưu trữ (theo tài liệu Versioning), trong khi `aws s3 ls` không hiển thị chúng. Backup ghi đè hằng ngày sẽ làm số phiên bản tăng mãi. Rule `NoncurrentVersionExpiration` (30 ngày) giải quyết việc này. Rule `ExpiredObjectDeleteMarker` dọn các delete marker còn sót lại.

**10. Multipart upload dở dang là gì?** Đó là các phần của một file lớn đã tải lên nhưng chưa được "ghép" lại vì upload bị ngắt giữa chừng. Chúng chưa thành object nên **không hiện** trong `ls`, nhưng vẫn chiếm dung lượng và bị tính tiền. Kiểm tra bằng `aws s3api list-multipart-uploads`. Rule `AbortIncompleteMultipartUpload` (7 ngày) tự dọn chúng.

**11. Presigned URL đặt `--expires-in 3600` mà chết sau vài phút?** Bạn ký URL bằng **credential tạm thời** lấy qua `aws login`. Theo tài liệu S3, presigned URL hết hạn khi credential dùng để ký hết hạn, dù bạn đặt thời hạn dài hơn. Trong URL có tham số `X-Amz-Security-Token`, đó là dấu hiệu URL được ký bằng credential tạm thời.

**12. Vì sao role EC2 không có `s3:DeleteObject`?** Nếu server bị chiếm, kẻ tấn công không xóa được backup. Hắn chỉ ghi đè được, và nhờ versioning bản cũ vẫn còn. Bản cũ được dọn bằng **lifecycle**, do chính dịch vụ S3 thực hiện, không cần role có quyền xóa.

**13. Vì sao `ListBucket` dùng ARN bucket, còn `GetObject` dùng ARN `.../*`?** `ListBucket` là thao tác **trên bucket** (liệt kê nội dung bucket), nên resource là ARN bucket. Muốn giới hạn phạm vi thì dùng condition `s3:prefix`. `GetObject` và `PutObject` là thao tác **trên object**, nên resource là ARN object (`bucket/prefix/*`). Đặt nhầm hai loại ARN này là lỗi `AccessDenied` phổ biến nhất khi viết policy S3.

**14. Server ở private subnet không có NAT gửi file lên S3 thế nào?** Dùng **S3 Gateway Endpoint**. Nó thêm một route trong route table của private subnet, trỏ thẳng tới S3 qua mạng nội bộ của AWS, và **không tính phí theo giờ**. Kết hợp với bucket policy có condition `aws:SourceVpce` nếu muốn bucket chỉ nhận request đi qua endpoint đó.

---

## Bài tập tự làm (mục 14)

### Bài 1 — Script backup tập dượt

```bash
#!/usr/bin/env bash
# scripts/backup-dryrun.sh — tập dượt cho v5: tạo, nén, upload, tải lại, so checksum
set -euo pipefail

BUCKET="${BUCKET:?Đặt biến BUCKET (taskhub-backups-<account-id>)}"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
day="$(date -u +%F)"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

file="$workdir/dump-${ts}.txt"
printf 'taskhub dry-run backup\ncreated=%s\nhost=%s\n' "$ts" "$(hostname)" > "$file"
gzip -9 "$file"                                     # → dump-<ts>.txt.gz
key="pg-dumps/${day}/dump-${ts}.txt.gz"

aws s3 cp "${file}.gz" "s3://${BUCKET}/${key}" --only-show-errors
aws s3 cp "s3://${BUCKET}/${key}" "$workdir/downloaded.gz" --only-show-errors

local_sum="$(sha256sum "${file}.gz" | cut -d' ' -f1)"
remote_sum="$(sha256sum "$workdir/downloaded.gz" | cut -d' ' -f1)"

if [[ "$local_sum" != "$remote_sum" ]]; then
  echo "CHECKSUM MISMATCH: local=$local_sum remote=$remote_sum" >&2
  exit 1
fi
echo "OK s3://${BUCKET}/${key} sha256=${local_sum}"
```

Điểm chấm:
- Dùng `set -euo pipefail`.
- Dùng `mktemp -d` kèm `trap` để dọn file tạm.
- Timestamp theo **UTC**.
- Key chia theo ngày.
- `--only-show-errors` để log gọn.
- So sánh checksum và trả **exit code khác 0** khi lệch, để cron/alert ở v5 bắt được.

### Bài 2 — Chặn xóa ở mức bucket

Thêm statement này vào bucket policy. Policy phải gửi lại **cả** statement TLS cũ, vì `put-bucket-policy` thay thế toàn bộ policy:

```json
{
  "Sid": "DenyDeleteBackupsExceptAdmin",
  "Effect": "Deny",
  "Principal": "*",
  "Action": ["s3:DeleteObject", "s3:DeleteObjectVersion"],
  "Resource": "arn:aws:s3:::BUCKET_NAME/pg-dumps/*",
  "Condition": {
    "ArnNotEquals": { "aws:PrincipalArn": "arn:aws:iam::111122223333:user/phuong-admin" }
  }
}
```

Kiểm chứng role bằng simulator, truyền kèm bucket policy:

```bash
aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text > current-policy.json
aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::${ACCOUNT_ID}:role/taskhub-ec2-role" \
  --action-names s3:DeleteObject \
  --resource-arns "arn:aws:s3:::${BUCKET}/pg-dumps/x.gz" \
  --resource-policy file://current-policy.json \
  --query 'EvaluationResults[].[EvalActionName,EvalDecision]' --output table
# → s3:DeleteObject  explicitDeny
```

**Vì sao không chặn lifecycle?** Theo trang *Troubleshooting Amazon S3 Lifecycle issues*, Deny tường minh trong bucket policy **không** chặn lifecycle expiration. Lý do: lifecycle không gọi thao tác `DeleteObject` như một principal, mà chạy qua endpoint nội bộ của S3. Muốn lifecycle ngừng tác động thì chỉ có cách sửa, tắt hoặc xóa chính rule đó. Hệ quả cần biết: để chặn hoàn toàn việc xóa, còn phải Deny `s3:PutLifecycleConfiguration`. Nếu không, ai có quyền đó có thể đặt một lifecycle "xóa sau 1 ngày". Ở mức cao hơn thì dùng S3 Object Lock (🟦).

⚠️ Cẩn thận khi viết Deny có `Principal: "*"`: nếu ARN trong `ArnNotEquals` sai, **chính bạn** cũng bị chặn xóa. Vẫn sửa được bằng cách đặt lại hoặc xóa bucket policy, vì Deny này không chặn `PutBucketPolicy`/`DeleteBucketPolicy`.

### Bài 3 — Phiên bản thứ N

```bash
for i in 1 2 3 4 5; do echo "lan $i" | aws s3 cp - "s3://$BUCKET/lab/multi.txt"; done
V2=$(aws s3api list-object-versions --bucket "$BUCKET" --prefix lab/multi.txt \
  --query 'Versions[-2].VersionId' --output text)
aws s3api get-object --bucket "$BUCKET" --key lab/multi.txt --version-id "$V2" out.txt >/dev/null
cat out.txt          # lan 2
```

`list-object-versions` liệt kê phiên bản của mỗi key theo thứ tự **mới nhất trước**. Với 5 lần upload, phần tử `[0]` là lần 5 và phần tử cuối `[-1]` là lần 1, nên lần 2 là `[-2]` (hoặc `[3]`). Cách chắc chắn hơn là sắp xếp theo thời gian: `sort_by(Versions, &LastModified)[1].VersionId`. Ghi chú: nếu các lần upload diễn ra trong cùng một giây, `LastModified` có thể trùng nhau, khi đó dựa vào thứ tự S3 trả về. Đừng quên dọn `lab/` sau bài.

### Bài 4 — Lifecycle cho backup thật

Gửi **cả 4 rule** cùng lúc, vì `put-bucket-lifecycle-configuration` thay thế toàn bộ cấu hình. Gửi mỗi rule mới sẽ **xóa** 3 rule hiện có.

```json
{
  "Rules": [
    { "ID": "expire-noncurrent-after-30-days", "Filter": { "Prefix": "" }, "Status": "Enabled",
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 } },
    { "ID": "abort-incomplete-multipart-after-7-days", "Filter": { "Prefix": "" }, "Status": "Enabled",
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 } },
    { "ID": "remove-expired-delete-markers", "Filter": { "Prefix": "" }, "Status": "Enabled",
      "Expiration": { "ExpiredObjectDeleteMarker": true } },
    { "ID": "pg-dumps-retention", "Filter": { "Prefix": "pg-dumps/" }, "Status": "Enabled",
      "Expiration": { "Days": 14 },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 7 } }
  ]
}
```

Phân tích:
- Với `pg-dumps/`, sau 14 ngày backup current nhận delete marker và trở thành noncurrent. Sau 7 ngày nữa nó bị xóa vĩnh viễn. Tổng cộng một backup sống khoảng 21 ngày.
- Bản bị ghi đè được giữ 7 ngày.
- Khi hai rule cùng áp dụng cho một object (rule 1 dùng prefix rỗng, rule 4 dùng `pg-dumps/`), theo trang *How Amazon S3 handles conflicts in lifecycle configurations*, lifecycle tối ưu cho chi phí: hai rule expiration chồng nhau thì **rule ngắn hơn được áp dụng**. Vì vậy noncurrent trong `pg-dumps/` bị xóa sau 7 ngày, không phải 30.
- Không đặt `ExpiredObjectDeleteMarker` trong rule 4, vì nó không được đi cùng `Days` trong một `Expiration`. Rule 3 đã lo việc này. Ngoài ra, khi dùng `Days`, S3 cũng tự dọn marker đủ tuổi.

### Bài 5 — Kiểm toán bucket

```bash
#!/usr/bin/env bash
# scripts/s3-audit.sh <bucket>
set -euo pipefail
B="${1:?Cách dùng: s3-audit.sh <bucket>}"

echo "== $B"
echo -n "BlockPublicAccess (4 cờ): "
aws s3api get-public-access-block --bucket "$B" \
  --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' \
  --output text
echo -n "ObjectOwnership: "
aws s3api get-bucket-ownership-controls --bucket "$B" \
  --query 'OwnershipControls.Rules[0].ObjectOwnership' --output text
echo -n "Encryption: "
aws s3api get-bucket-encryption --bucket "$B" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text
echo -n "Versioning: "
aws s3api get-bucket-versioning --bucket "$B" --query 'Status' --output text
echo -n "Lifecycle rules: "
aws s3api get-bucket-lifecycle-configuration --bucket "$B" --query 'length(Rules)' --output text 2>/dev/null || echo 0
echo -n "Deny non-TLS: "
if aws s3api get-bucket-policy --bucket "$B" --query Policy --output text 2>/dev/null | grep -q 'aws:SecureTransport'; then
  echo yes
else
  echo NO
fi
echo -n "Multipart dở dang: "
aws s3api list-multipart-uploads --bucket "$B" --query 'length(Uploads || `[]`)' --output text
```

Đầu ra mong đợi với bucket của dự án (minh họa):

```text
== taskhub-backups-111122223333
BlockPublicAccess (4 cờ): True	True	True	True
ObjectOwnership: BucketOwnerEnforced
Encryption: AES256
Versioning: Enabled
Lifecycle rules: 3
Deny non-TLS: yes
Multipart dở dang: 0
```

Điểm chấm:
- Xử lý được trường hợp bucket không có lifecycle hoặc không có policy (API trả lỗi), dùng `2>/dev/null || ...`.
- Dùng `Uploads || \`[]\``, vì khi không có upload nào, trường `Uploads` vắng mặt, và `length(null)` sẽ lỗi nếu không có giá trị dự phòng.

---

## Nguồn tham khảo bổ sung

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Troubleshooting Amazon S3 Lifecycle issues](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-lifecycle.html) | Bucket policy Deny không chặn lifecycle; lifecycle chạy không đồng bộ | 2026-10-31 |
| [How Amazon S3 handles conflicts in lifecycle configurations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-conflicts.html) | Hai rule expiration chồng nhau thì rule ngắn hơn được áp dụng | 2026-10-31 |
| [Retaining multiple versions of objects with S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html) | Mỗi phiên bản bị tính phí như một object đầy đủ | 2026-10-31 |
