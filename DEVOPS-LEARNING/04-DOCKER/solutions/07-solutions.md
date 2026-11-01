# Lời giải — Bài 07: Docker Security

> ⚠️ Chỉ đọc sau khi đã tự làm và ghi câu trả lời của bạn. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt.

Quay lại bài: [07-docker-security.md](../07-docker-security.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1.** Máy ảo có kernel riêng; ranh giới là hypervisor — một lớp nhỏ, ít tính năng, khó vượt qua. Container dùng chung kernel host; ranh giới là các cơ chế của chính kernel (namespace, cgroup, capability, seccomp). Một lỗ hổng kernel cho phép process thoát khỏi namespace là đủ để tác động lên host và **mọi** container khác. Với máy ảo, lỗ hổng trong kernel của VM chỉ ảnh hưởng VM đó.

**2.** Mặc định có — UID 0 trong container là UID 0 trên host (khi chưa bật user namespace/rootless). Docker giảm rủi ro bằng: tập capability hạn chế, chặn system call nguy hiểm, cô lập filesystem/process/mạng bằng namespace. Phá vỡ bởi: `--privileged`, mount thư mục nhạy cảm của host (`/`, `/etc`, docker.sock), `--cap-add SYS_ADMIN`, `--pid host`, `--network host` (phần mạng).

**3.** Thành viên group `docker` được ghi vào docker.sock = ra lệnh cho daemon chạy root. `docker run --rm -it -v /:/host ubuntu:22.04 chroot /host bash` → shell root trên filesystem host, có thể sửa `/etc/sudoers`, đọc `/etc/shadow`… mà không cần mật khẩu sudo.

**4.** Socket là API điều khiển daemon; container có nó tạo được container mới với bất kỳ cấu hình nào (mount `/` của host, `--privileged`) → root trên host. App bị chiếm quyền thì server cũng mất. Chấp nhận được với công cụ tin cậy thật sự cần (Trivy quét image cục bộ, CI runner, công cụ quản trị) khi: image chính thức, pin version, chạy ngắn hạn hoặc trên máy riêng/được cô lập, hiểu rõ rủi ro; ưu tiên cách không cần socket nếu có (Trivy `--input` file tar).

**5.** Bỏ toàn bộ capability Linux của container. App non-root không có capability nào ở "effective set" ngay từ đầu (với user thường, kernel không cấp capability); nghe port 8080 (> 1024) không cần `NET_BIND_SERVICE`, đọc file của mình không cần `DAC_OVERRIDE` → không thiếu gì. Bỏ hết chỉ đảm bảo nếu có cách nào leo lên root thì root đó cũng "trần trụi".

**6.** `--privileged` cấp gần như mọi capability **và** quyền truy cập thiết bị của host, tắt nhiều cơ chế bảo vệ — container gần như không còn bị cô lập. `--cap-add NET_ADMIN` chỉ thêm đúng một quyền (cấu hình mạng **trong** network namespace của container). Gặp hướng dẫn bảo dùng `--privileged`: đọc lỗi để biết thao tác nào bị chặn, tìm capability tương ứng (`man 7 capabilities`), chỉ thêm cái đó.

**7.** Chặn process nhận thêm đặc quyền qua `execve` — điển hình là chương trình setuid/setgid (`sudo`, `su`, `passwd`, `ping` cũ). Ở Linux bài 03, bit setuid làm chương trình chạy với UID của chủ file (root). Với `no-new-privileges`, kernel bỏ qua bit đó: kẻ tấn công có shell user thường trong container không leo lên root bằng chương trình setuid được, kể cả khi có lỗ hổng trong chương trình đó.

**8.** Chống việc kẻ tấn công **ghi** vào filesystem container: tải công cụ/mã độc về, sửa file của app, cài backdoor sống tới khi container bị tạo lại. Spring Boot (Tomcat nhúng) tạo thư mục làm việc tạm trong `java.io.tmpdir` = `/tmp` khi khởi động; read-only toàn bộ thì không tạo được → cần `tmpfs` cho `/tmp`.

**9.** Một container rò rỉ bộ nhớ có thể ăn hết RAM của host. Kernel kích hoạt OOM killer ở cấp **host** và có thể giết process của container khác (database chiếm nhiều RAM hay là nạn nhân), thậm chí process hệ thống. Có `mem_limit`, OOM xảy ra trong cgroup của chính container đó — chỉ nó bị giết.

**10.** Image chính thức/nguồn tin cậy; nhỏ nhất có thể; pin version (🟨 digest); cập nhật và quét định kỳ. JRE không có trình biên dịch, công cụ phát triển → nhỏ hơn, ít gói hơn → ít CVE hơn và kẻ tấn công có ít công cụ hơn; app chạy jar không cần JDK.

**11.** Chưa có bản vá. Xử lý: đọc mô tả CVE — gói đó app có dùng không, có đường tấn công từ ngoài vào không (ví dụ thư viện xử lý định dạng mà app không bao giờ nhận)? Nếu rủi ro thật: tìm base image khác không chứa gói đó (nhỏ hơn, distroless), hoặc biện pháp giảm thiểu (tắt tính năng, chặn mạng). Ghi nhận rủi ro có người chịu trách nhiệm, theo dõi để vá ngay khi có bản sửa. Không lặng lẽ bỏ qua.

**12.** Image nào cũng chứa hàng trăm gói, CVE mới được công bố mỗi ngày, nhiều CVE chưa có bản vá hoặc không ảnh hưởng thực tế. Đòi "0 CVE" dẫn tới tê liệt hoặc giả mạo kết quả. Mục tiêu hợp lý: không còn CRITICAL/HIGH **có bản vá** mà chưa vá; phần còn lại được đánh giá và ghi nhận; quét lại định kỳ.

**13.** `docker image inspect <img> --format '{{json .Config.Env}}'` và `docker history --no-trunc <img>`. Thứ tự xử lý: (1) **đổi mật khẩu** database ngay (coi như đã lộ); (2) xóa tag/đặt private image trên registry; (3) sửa Dockerfile, chuyển secret ra biến môi trường lúc chạy; (4) kiểm tra log truy cập DB xem đã bị lạm dụng chưa; (5) postmortem.

**14.** Lúc build (token tải dependency private): BuildKit secret mount — secret chỉ có mặt trong lúc chạy một lệnh `RUN`, không vào layer. Lúc chạy (mật khẩu DB): truyền qua biến môi trường từ `.env` ngoài Git, hoặc 🟦 Compose secrets/secret manager của cloud — **không bao giờ** nằm trong image.

**15.** `Read-only file system` (EROFS, 30): ghi vào filesystem đang mount chỉ đọc — do `read_only`. `Operation not permitted` (EPERM, 1): thao tác cần đặc quyền mà process không có — thiếu capability, hoặc `no-new-privileges` chặn. `Permission denied` (EACCES, 13): quyền rwx của file/thư mục không cho user hiện tại — thường do app non-root ghi vào thư mục/volume thuộc root.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Escape bằng cấu hình sai

Trên Docker Desktop, `/host` là filesystem của **máy ảo Linux** mà Docker Desktop dùng để chạy daemon (không phải Windows, không phải WSL Ubuntu của bạn) — `cat /host/etc/os-release` thường cho thấy một bản phân phối khác Ubuntu của bạn. Giải thích mẫu:

> Lệnh `docker run` được gửi tới daemon chạy root. Daemon mount `/` của máy chủ vào container theo yêu cầu, không kiểm tra người yêu cầu có quyền root hay không. Trong container, process là root nên đọc/ghi được mọi file của máy chủ qua `/host`. Vì vậy ai ra lệnh được cho daemon (thuộc group docker, hoặc container có docker.sock) đều có quyền root trên máy chủ. Trên EC2, đó là toàn quyền với server: đọc khóa SSH, credential, sửa sudoers, cài backdoor, và dùng IAM role của instance để tấn công tài khoản AWS.

### Bài 2 — Capability tối thiểu cho postgres

```bash
docker run --rm --cap-drop ALL -e POSTGRES_PASSWORD=x postgres:17
```

Lỗi điển hình (minh họa): `chown: changing ownership of '/var/lib/postgresql/data': Operation not permitted` → cần `CHOWN`; sau đó lỗi khi chuyển sang user `postgres` (`gosu`/`setgroups: operation not permitted`) → cần `SETUID`, `SETGID`; có thể cần `DAC_OVERRIDE` hoặc `FOWNER` tùy bước chmod/đọc file của entrypoint. Danh sách thường gặp:

```bash
docker run --rm -d --name pg-min --cap-drop ALL \
  --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE --cap-add FOWNER \
  -e POSTGRES_PASSWORD=x postgres:17
docker logs pg-min | tail -3
docker rm -f pg-min
```

Giải thích: entrypoint chạy bằng root để **chuẩn bị thư mục dữ liệu** (đổi chủ sở hữu, đặt quyền — `CHOWN`, `FOWNER`, `DAC_OVERRIDE`) rồi **hạ quyền** sang user `postgres` (`SETUID`, `SETGID`). Server PostgreSQL sau đó chạy không cần capability nào. Danh sách chính xác có thể khác theo phiên bản image — tiêu chí đạt là bạn tìm ra bằng cách **đọc lỗi**, mỗi lần thêm một capability, và giải thích được từng cái.

### Bài 3 — Kiểm chứng no-new-privileges

```bash
cat > /tmp/nnp.sh <<'EOF'
apt-get -qq update >/dev/null && apt-get -qq install -y sudo >/dev/null
useradd -m u
echo 'u ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/u && chmod 0440 /etc/sudoers.d/u
su u -c 'sudo -n id'
EOF
docker run --rm -v /tmp/nnp.sh:/nnp.sh:ro ubuntu:22.04 bash /nnp.sh
docker run --rm --security-opt no-new-privileges -v /tmp/nnp.sh:/nnp.sh:ro ubuntu:22.04 bash /nnp.sh
```

Kết quả (minh họa):

```text
uid=0(root) gid=0(root) groups=0(root)
sudo: effective uid is not 0, is /usr/bin/sudo on a file system with the 'nosuid' option set or an NFS file system without root privileges?
```

Lưu ý: `su` cũng là chương trình setuid — với `no-new-privileges`, root chuyển sang `u` vẫn được (root **hạ** quyền, không cần nâng), nhưng `sudo` từ `u` thì không nâng lên root được: bit setuid bị kernel bỏ qua nên `sudo` chạy với UID của `u` và tự báo lỗi. Cấu hình sudoers cho phép cũng vô ích.

### Bài 4 — Secret lúc build đúng cách

```bash
mkdir -p ~/devops-lab/04-docker/lab07/secret && cd ~/devops-lab/04-docker/lab07/secret
printf 'ghp_FAKE_build_token_123' > token.txt
cat > Dockerfile <<'EOF'
FROM alpine:3.20
RUN --mount=type=secret,id=token \
    echo "token length: $(wc -c < /run/secrets/token)"
CMD ["sh", "-c", "ls /run/secrets 2>/dev/null || echo 'no secrets in image'"]
EOF
docker build --progress=plain --no-cache --secret id=token,src=token.txt -t secret-demo .
docker history --no-trunc secret-demo --format '{{.CreatedBy}}' | grep -i token
docker image inspect secret-demo --format '{{json .Config.Env}}'
docker run --rm secret-demo
```

- Log build có `token length: 24`, chứng tỏ lệnh `RUN` đọc được secret.
- `history` chỉ hiện lệnh `RUN --mount=type=secret,id=token ...` — **không có giá trị** token.
- `Env` không chứa token; container chạy in `no secrets in image`.
- Thêm `token.txt` vào `.gitignore` và `.dockerignore`.

### Bài 5 — Báo cáo bảo mật

Không có đáp án duy nhất. Báo cáo đạt khi: có số liệu cụ thể (ví dụ "12 HIGH, 0 CRITICAL; 9 có bản vá, đều ở base image"), 3 hành động có thứ tự ưu tiên và lý do ("rebuild với `--pull` — xử lý 9/12 lỗ hổng, 10 phút"), liệt kê biện pháp đã có, nêu rõ rủi ro còn lại và mốc thời gian (quét tự động trong CI tuần 10). Viết cho người đọc bận rộn: kết luận trước, chi tiết sau.
