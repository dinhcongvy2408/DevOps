# Bản tham khảo Ansible cho `taskhub` v4

> ⚠️ **Chỉ mở sau khi đã tự viết** playbook của bạn ở [Lab 03](../../lab-03-ansible-ssm.md). File ở đây để **so sánh**, không phải để chép.
> Account id ví dụ `111122223333`, user GitHub `phuong-dev` — thay bằng giá trị của bạn.

Đặt toàn bộ thư mục này vào repo `taskhub` tại `infra/ansible/`. Mọi lệnh chạy **từ** `infra/ansible/` (để Ansible đọc `ansible.cfg`).

```text
infra/ansible/
├── ansible.cfg                  # inventory mặc định, interpreter, timeout
├── requirements.yml             # amazon.aws 12.0.0, community.docker 5.4.0 (ghim)
├── inventory/
│   ├── aws_ec2.yml              # inventory động: EC2 tag Project=taskhub, đang chạy
│   └── group_vars/all.yml       # connection aws_ssm, region — KHÔNG có secret
├── playbooks/site.yml           # assert tag → role docker → role taskhub
└── roles/
    ├── docker/                  # Docker Engine + compose plugin (repo apt chính thức), AWS CLI (snap)
    │   ├── defaults/main.yml
    │   ├── handlers/main.yml
    │   └── tasks/main.yml
    └── taskhub/                 # copy compose*.yaml, nginx conf, deploy.sh → chạy deploy.sh khi cần
        ├── defaults/main.yml
        ├── handlers/main.yml
        └── tasks/main.yml
```

Chạy:

```bash
cd infra/ansible
export AWS_PROFILE=taskhub
ansible-galaxy collection install -r requirements.yml
ansible-inventory --graph
ansible-playbook playbooks/site.yml -e taskhub_image_tag=v0.6.0
ansible-playbook playbooks/site.yml -e taskhub_image_tag=v0.6.0   # lần 2: changed=0
```

## Các quyết định và lý do

| Quyết định | Lý do | Đánh đổi |
|---|---|---|
| Connection `amazon.aws.aws_ssm`, không SSH | Không mở port 22, không quản lý SSH key; đi cùng đường với deploy của v3 (SSM) | Cần `session-manager-plugin`, boto3, bucket S3 trung gian; chậm hơn SSH vài giây mỗi task |
| `group_vars/` nằm **trong** `inventory/` | Ansible chỉ đọc `group_vars/` cạnh nguồn inventory hoặc cạnh playbook. Đặt ở đây thì cả `ansible`, `ansible-inventory`, `ansible-playbook` đều thấy biến kết nối | Khác với nhiều tutorial đặt cạnh `ansible.cfg` (chỉ đúng khi inventory cũng nằm ở đó) |
| Tên bucket SSM tính từ `owner_id` trong `compose` của inventory | Không phải ghi account id vào Git; đổi account không phải sửa file | Bucket phải đặt đúng tên `taskhub-ansible-ssm-<account-id>` (Terraform tạo) |
| Bucket SSM **không** bật versioning, lifecycle xóa sau 1 ngày | Tài liệu plugin: file module tạm có thể chứa tham số nhạy cảm; versioning giữ chúng mãi trong lịch sử | Không khôi phục được file tạm (không cần) |
| `filters.instance-state-name: running` | Mặc định plugin lấy cả máy `stopped` → playbook treo khi kết nối | — |
| `hostnames: tag:Name` + `compose.ansible_host: instance_id` | Log dễ đọc (`taskhub-app`) nhưng vẫn kết nối bằng instance ID như `aws_ssm` yêu cầu | Hai máy cùng tag Name sẽ trùng tên host |
| `taskhub_image_tag` bắt buộc qua `-e`, có `assert` định dạng | Không deploy nhầm bản; chuỗi lạ không bao giờ tới shell của EC2 (cùng regex với `deploy.sh`) | Phải gõ tag mỗi lần |
| Role `taskhub` **copy file từ repo** (`taskhub_repo_root`) thay vì `git clone` trên máy | Máy chủ nhận đúng bản bạn đang có trên nhánh hiện tại; EC2 không cần git, không cần quyền đọc repo | Chạy playbook từ nhánh chưa merge sẽ đưa file chưa review lên máy → chỉ chạy từ `main` |
| Không có thư mục `templates/` trong role `taskhub` | File triển khai lấy **nguyên văn** từ repo (một nguồn sự thật); không có gì cần điền biến | Template Jinja2 được luyện ở lab local của [bài 05](../../../05-ansible-fundamentals.md) |
| Chỉ chạy `deploy.sh` khi file đổi / tag đổi / container không chạy | Lần chạy thứ hai `changed=0` (Q5 của v4) | Logic điều kiện dài hơn một dòng `command` |
| Nginx conf đổi → **restart** container nginx (handler), không chạy lại deploy | Bind mount một file + `copy` thay inode → `nginx -s reload` vẫn đọc file cũ | Nginx gián đoạn vài giây |
| Mật khẩu **không** đi qua Ansible | `deploy.sh` đọc Parameter Store bằng instance role ([v2](../../../../12-PRACTICAL-PROJECT/milestones/v2-aws-ec2.md)) | — |
| Role `docker` không tự gỡ gói "xung đột" | AMI Ubuntu mới không có các gói đó; `apt state: absent` với tên gói ảo như `containerd` có thể đụng nhầm `containerd.io` | Máy cũ đã cài `docker.io` phải gỡ tay trước |

## Đã kiểm tra những gì

- Mọi file YAML đọc được bằng PyYAML.
- Tên tùy chọn của `aws_ec2` (`filters`, `hostnames`, `keyed_groups`, `compose`, `use_deprecated_tags`, hostvar `owner_id`) và của `aws_ssm` (`ansible_aws_ssm_region`, `ansible_aws_ssm_bucket_name`, đọc `AWS_PROFILE`) đối chiếu với **mã nguồn amazon.aws 12.0.0**.
- `deb822_repository` (tùy chọn, yêu cầu `python3-debian`) đối chiếu với mã nguồn ansible-core 2.21.5.
- **Chưa** chạy trên EC2 thật — lần chạy đầu tiên là của bạn ở Lab 03.
