# Thuật ngữ Module 06 — AWS

> Mỗi nhóm ghi bài học giải thích kỹ thuật ngữ đó. CIDR, route, NAT, DNS, TLS đã gặp ở [glossary Networking](../02-NETWORKING/glossary.md); OIDC, environment, secret ở [glossary CI/CD](../05-CICD/glossary.md).

## Mục lục

- [Tài khoản và chi phí (bài 00)](#tài-khoản-và-chi-phí-bài-00)
- [Cloud fundamentals (bài 01)](#cloud-fundamentals-bài-01)
- [IAM (bài 02)](#iam-bài-02)
- [VPC (bài 03)](#vpc-bài-03)
- [EC2 (bài 04)](#ec2-bài-04)
- [S3 (bài 05)](#s3-bài-05)
- [AWS CLI (bài 06)](#aws-cli-bài-06)
- [RDS (bài 07)](#rds-bài-07)
- [ELB và Auto Scaling (bài 08)](#elb-và-auto-scaling-bài-08)
- [Route 53 (bài 09)](#route-53-bài-09)
- [CloudWatch (bài 10)](#cloudwatch-bài-10)
- [Triển khai tự động (bài 11, v3)](#triển-khai-tự-động-bài-11-v3)

---

## Tài khoản và chi phí (bài 00)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Free plan / Paid plan | Gói miễn phí / gói trả phí | Free plan: dùng credit, không phát sinh phí, tự đóng sau 6 tháng hoặc khi hết credit. |
| Credit | Tín dụng | Số tiền AWS tặng, tự trừ vào chi phí sử dụng. |
| Root user | Người dùng gốc | Danh tính tạo tài khoản, có mọi quyền — chỉ dùng cho việc bắt buộc phải là root. |
| MFA / passkey | Xác thực đa yếu tố / khóa truy cập | Yếu tố thứ hai khi đăng nhập. |
| AWS Budgets | Ngân sách | Theo dõi chi phí/mức dùng và gửi cảnh báo. |
| Unblended / net unblended cost | Chi phí gốc / chi phí sau credit | Budget trên Free plan nên dùng Unblended — net luôn gần 0. |
| Cost Explorer | Trình xem chi phí | Biểu đồ chi phí theo dịch vụ, thời gian, tag. API tính phí mỗi request. |
| Cost allocation tag | Tag phân bổ chi phí | Tag được bật để lọc chi phí theo dự án. |
| AWS Global View | Xem toàn cục | Liệt kê tài nguyên EC2/VPC trên mọi region. |

## Cloud fundamentals (bài 01)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| IaaS / PaaS / SaaS | Hạ tầng / nền tảng / phần mềm như dịch vụ | Mức độ nhà cung cấp quản lý thay bạn. |
| Region / AZ | Vùng / vùng sẵn sàng | Region gồm nhiều AZ cách biệt về vật lý; tên AZ ánh xạ ngẫu nhiên theo tài khoản (AZ ID cố định). |
| Edge location | Điểm biên | Điểm phân phối gần người dùng (CloudFront, Route 53). |
| Shared Responsibility Model | Mô hình trách nhiệm chung | AWS lo bảo mật "của" cloud; bạn lo bảo mật "trong" cloud. |
| Well-Architected Framework | Khung kiến trúc tốt | 6 trụ cột: vận hành, bảo mật, tin cậy, hiệu năng, chi phí, bền vững. |
| CloudTrail | Nhật ký API | Ghi lại mọi lời gọi API; event history 90 ngày miễn phí. |

## IAM (bài 02)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Principal | Chủ thể | Ai thực hiện yêu cầu: user, role, dịch vụ AWS. |
| IAM user / group / role | Người dùng / nhóm / vai trò | User có danh tính lâu dài; role được "đảm nhận" để nhận credential tạm thời. |
| Policy | Chính sách | Tài liệu JSON gồm Effect, Action, Resource, Condition. |
| Identity-based / resource-based policy | Gắn vào danh tính / gắn vào tài nguyên | Gắn vào user/role / gắn vào bucket, key… |
| Managed / inline policy | Chính sách dùng chung / nhúng | Tái sử dụng được / gắn riêng một danh tính. |
| Explicit deny / implicit deny | Từ chối tường minh / ngầm định | Deny luôn thắng; không có Allow nào thì mặc định bị từ chối. |
| Trust policy | Chính sách tin cậy | Ai được phép đảm nhận role. |
| STS / AssumeRole | Dịch vụ token bảo mật / đảm nhận vai trò | Cấp credential tạm thời. |
| Instance profile | Hồ sơ instance | Vỏ chứa role để gắn vào EC2. |
| Least privilege | Quyền tối thiểu | Chỉ cấp đúng quyền cần. |
| IAM Access Analyzer | Bộ phân tích truy cập | Tìm quyền thừa, sinh policy từ hoạt động thực tế. |
| Policy Simulator | Trình mô phỏng policy | Thử policy cho phép/từ chối gì mà không gọi API thật. |
| IAM Identity Center | Trung tâm danh tính | SSO cho nhiều tài khoản — cần AWS Organizations (sẽ nâng Free plan lên Paid). |

## VPC (bài 03)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| VPC | Mạng riêng ảo | Mạng riêng của bạn trên AWS, có dải CIDR riêng. |
| Subnet public / private | Mạng con công khai / riêng | Do **route table** quyết định: có route `0.0.0.0/0 → IGW` thì là public. |
| Reserved IPs | Địa chỉ bị giữ | 5 địa chỉ mỗi subnet AWS dùng riêng. |
| Internet Gateway (IGW) | Cổng Internet | Cho subnet public ra/vào Internet, NAT 1-1 với public IP. |
| Route table / main route table | Bảng định tuyến / bảng mặc định | Subnet không gắn bảng nào sẽ dùng bảng main. |
| NAT Gateway | Cổng NAT | Cho subnet private đi ra Internet — tính phí theo giờ và theo GB (dự án không dùng). |
| VPC endpoint (gateway / interface) | Điểm cuối VPC | Truy cập dịch vụ AWS không qua Internet; gateway (S3, DynamoDB) miễn phí, interface tính phí. |
| Security Group | Nhóm bảo mật | Tường lửa **stateful** gắn vào ENI, chỉ có luật cho phép. |
| Network ACL | Danh sách kiểm soát mạng | Tường lửa **stateless** gắn vào subnet, luật đánh số, có deny — nhớ cổng tạm 1024-65535. |
| ENI | Giao diện mạng | Card mạng ảo của EC2. |
| Flow Logs | Nhật ký luồng | Ghi metadata các kết nối (chấp nhận/từ chối). |
| Reachability Analyzer | Phân tích khả năng kết nối | Kiểm tra đường đi giữa hai điểm có thông không. |

## EC2 (bài 04)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Instance type | Loại máy | Tổ hợp vCPU/RAM, ví dụ `t3.small` (2 vCPU, 2 GiB). |
| Burstable / CPU credit | Có thể tăng tốc / tín dụng CPU | Dòng `t` chạy dưới baseline thì tích credit, vượt baseline thì tiêu credit. |
| AMI | Ảnh máy | Image khởi tạo ổ gốc của instance. |
| Key pair | Cặp khóa | Khóa SSH; dự án dùng Session Manager thay vì SSH. |
| User data / cloud-init | Dữ liệu khởi tạo | Script chạy bằng root ở lần boot đầu; log ở `/var/log/cloud-init-output.log`. |
| EBS / gp3 | Ổ đĩa khối | Ổ mạng gắn vào EC2; vẫn tính tiền khi instance stop. |
| Stop / terminate / hibernate | Dừng / hủy / ngủ đông | Stop giữ ổ và mất public IP; terminate xóa máy. |
| IMDSv2 | Dịch vụ metadata v2 | `169.254.169.254`, bắt buộc token; hop limit quyết định container có lấy được token không. |
| Session Manager (SSM) | Trình quản lý phiên | Vào shell của EC2 không cần mở cổng 22. |
| Status check | Kiểm tra trạng thái | System / Instance / Attached EBS. |
| Service Quotas | Hạn mức dịch vụ | Ví dụ số vCPU on-demand tối đa (mặc định 5 với tài khoản mới). |

## S3 (bài 05)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Bucket / object / key | Thùng / đối tượng / khóa | Tên bucket duy nhất toàn cầu; "thư mục" chỉ là tiền tố của key. |
| Block Public Access | Chặn truy cập công khai | Bật mặc định cho bucket mới. |
| Object Ownership | Quyền sở hữu object | ACL tắt mặc định — dùng policy thay ACL. |
| SSE-S3 | Mã hóa phía server | Mặc định cho mọi object mới. |
| Versioning | Lưu phiên bản | Giữ mọi phiên bản; xóa chỉ tạo delete marker. |
| Lifecycle rule | Luật vòng đời | Tự chuyển lớp lưu trữ hoặc xóa object/phiên bản cũ. |
| Storage class | Lớp lưu trữ | Standard, IA, Glacier… đánh đổi giá lưu và giá truy xuất. |
| Presigned URL | URL ký sẵn | Cho phép tải/lên tạm thời không cần credential. |

## AWS CLI (bài 06)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| `aws login` | Đăng nhập CLI qua trình duyệt | Credential tạm thời, tự xoay vòng — không cần access key dài hạn. |
| Profile | Hồ sơ cấu hình | Bộ cấu hình có tên (`taskhub`), chọn bằng `AWS_PROFILE`. |
| Access key | Khóa truy cập | Credential dài hạn — tránh dùng trên laptop. |
| JMESPath / `--query` | Ngôn ngữ truy vấn JSON | Lọc kết quả ở phía client. |
| `--filters` | Bộ lọc | Lọc ở phía server (ít dữ liệu trả về hơn). |
| Waiter | Lệnh chờ | `aws ec2 wait instance-running`. |
| `--dry-run` | Chạy thử | Kiểm tra quyền mà không tạo tài nguyên. |
| CloudShell | Shell trên trình duyệt | Terminal có sẵn AWS CLI, đăng nhập theo phiên console. |

## RDS (bài 07)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| RDS | Dịch vụ database quản lý | AWS lo cài đặt, vá, backup, failover. |
| DB subnet group | Nhóm subnet DB | Danh sách subnet (≥ 2 AZ) RDS được đặt vào. |
| Multi-AZ | Đa vùng sẵn sàng | Bản dự phòng ở AZ khác, tự failover. |
| Automated backup / PITR | Sao lưu tự động / khôi phục theo thời điểm | Khôi phục về bất kỳ giây nào trong thời gian lưu. |
| Snapshot | Ảnh chụp | Bản sao lưu thủ công, tồn tại tới khi bạn xóa. |
| Parameter group | Nhóm tham số | Cấu hình engine database. |

## ELB và Auto Scaling (bài 08)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| ALB / NLB | Cân bằng tải tầng 7 / tầng 4 | ALB hiểu HTTP (path, host); NLB chuyển TCP/UDP. |
| Listener / rule / target group | Bộ nghe / luật / nhóm đích | Listener nhận kết nối, rule chọn target group. |
| Health check | Kiểm tra sức khỏe | Target trả sai mã thì bị loại khỏi vòng phân phối. |
| LCU | Đơn vị dung lượng | Thành phần tính phí theo lưu lượng của ALB. |
| Launch template | Mẫu khởi chạy | Cấu hình EC2 để ASG tạo instance. |
| Auto Scaling group | Nhóm tự co giãn | Giữ số instance trong khoảng min/desired/max, thay instance hỏng. |
| Instance refresh | Làm mới instance | Thay dần instance theo template mới — rolling deploy. |
| Target tracking | Bám mục tiêu | Tự co giãn để giữ một chỉ số (ví dụ CPU 50%). |

## Route 53 (bài 09)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Hosted zone | Vùng được lưu trữ | Tập bản ghi DNS của một tên miền; tính phí theo tháng. |
| Alias record | Bản ghi bí danh | Trỏ tên miền (kể cả gốc) tới tài nguyên AWS. |
| NS delegation | Ủy quyền nameserver | Nhà đăng ký trỏ tên miền về nameserver của Route 53. |
| Routing policy | Chính sách định tuyến | Simple, weighted, failover, latency… |
| ACM | Trình quản lý chứng chỉ | Chứng chỉ TLS công khai miễn phí dùng với ALB/CloudFront. |

## CloudWatch (bài 10)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| Metric / namespace / dimension | Chỉ số / không gian tên / chiều | `AWS/EC2` · `CPUUtilization` · `InstanceId=...`. |
| Basic / detailed monitoring | Giám sát cơ bản / chi tiết | 5 phút (miễn phí) / 1 phút (tính phí). |
| Log group / log stream | Nhóm log / luồng log | Retention mặc định là không bao giờ hết hạn — bẫy chi phí. |
| Logs Insights | Truy vấn log | Ngôn ngữ truy vấn log, tính phí theo GB quét. |
| `awslogs` driver | Trình ghi log của Docker | Gửi stdout/stderr của container lên CloudWatch Logs. |
| Alarm | Cảnh báo | Trạng thái OK / ALARM / INSUFFICIENT_DATA. |
| SNS topic | Chủ đề thông báo | Kênh gửi email/tin nhắn khi alarm kích hoạt. |
| CloudWatch agent | Tác tử CloudWatch | Thu metric RAM/disk và log file mà EC2 không gửi mặc định. |

## Triển khai tự động (bài 11, v3)

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích |
|---|---|---|
| OIDC identity provider | Nhà cung cấp danh tính OIDC | AWS tin token do GitHub Actions ký (`token.actions.githubusercontent.com`). |
| `sub` claim | Trường chủ thể | Ví dụ `repo:<user>/taskhub:environment:production` — điều kiện trong trust policy. |
| Run Command | Chạy lệnh từ xa | `ssm send-command` chạy script trên EC2 không cần SSH. |
| Parameter Store (SecureString) | Kho tham số (chuỗi mã hóa) | Lưu mật khẩu database, mã hóa bằng KMS. |
| `workflow_run` | Sự kiện sau workflow | Deploy chạy khi CI trên `main` hoàn tất thành công. |
| Smoke test | Kiểm tra khói | Gọi `/actuator/health` ngay sau deploy. |
