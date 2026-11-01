# Lời giải — Bài 02. Lệnh thiết yếu & xử lý văn bản

> ⚠️ Chỉ đọc sau khi đã tự làm. Mỗi bài thường có nhiều cách đúng — so sánh **cách suy nghĩ**, không chỉ so lệnh.
> Quay lại bài học: [02-essential-commands-text.md](../02-essential-commands-text.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. stdin, stdout, stderr?**
Ba kênh vào/ra mặc định của mọi process: `0` đầu vào, `1` kết quả, `2` thông báo lỗi. Tách stdout và stderr để có thể xử lý riêng: lưu kết quả vào file hoặc đưa qua pipe mà lỗi vẫn hiện ra màn hình (không bị lẫn vào dữ liệu), hoặc lưu lỗi riêng để phân tích.

**2. `rm *.log` — `rm` nhận được gì?**
Bash mở rộng `*.log` thành danh sách tên file khớp **trước khi** chạy `rm`. `rm` chỉ nhận được các tên file cụ thể, ví dụ `rm app.log error.log`. Nếu không có file nào khớp, Bash giữ nguyên chuỗi `*.log` và `rm` báo không tìm thấy file tên là `*.log`.

**3. `cp`/`mv` có hỏi trước khi ghi đè?**
Không — ghi đè im lặng. Thêm `-i` để hỏi, hoặc `-n` (no-clobber) để không bao giờ ghi đè.

**4. `tail -f` và `tail -F`?**
`-f` theo dõi **file đang mở** (theo inode). Khi log rotation đổi tên `access.log` thành `access.log.1` và tạo `access.log` mới, `-f` vẫn đọc file cũ và không thấy log mới. `-F` theo dõi **tên file**, tự mở lại khi file bị thay thế. Bắt buộc dùng `-F` khi theo dõi log lâu dài trên server có logrotate.

**5. `less` và `nano` với file 10GB?**
`less` chỉ đọc phần đang hiển thị, không tải cả file vào RAM. Trình soạn thảo như `nano` tải toàn bộ file vào bộ nhớ để có thể sửa → chậm, tốn RAM, có thể làm treo server.

**6. Lệnh `find`:**

```bash
find /var/log -type f -name "*.log" -size +50M -mtime -1
```

**7. Vì sao `uniq -c` cần `sort`?**
`uniq` chỉ gộp các dòng trùng **liền kề nhau**. Nếu cùng một IP xuất hiện rải rác, không sort thì mỗi cụm được đếm riêng.

**8. `> file 2>&1` và `2>&1 > file`?**
Redirect được xử lý từ trái sang phải như phép gán.
- `> file 2>&1`: stdout → file; rồi stderr → "nơi stdout đang trỏ" = file. Cả hai vào file.
- `2>&1 > file`: stderr → "nơi stdout đang trỏ" = màn hình; rồi stdout → file. Lỗi vẫn ra màn hình.

**9. `sudo echo "x" > /etc/hosts`?**
Redirect `>` do **shell của bạn** (chạy bằng user thường) thực hiện trước khi `sudo` chạy. `sudo` chỉ áp dụng cho `echo`. Shell của user thường không có quyền ghi `/etc/hosts`. Cách đúng: `echo "x" | sudo tee -a /etc/hosts` — `tee` chạy bằng quyền root và tự ghi file.

**10. `cut` hay `awk`?**
`cut` khi dữ liệu có dấu phân cách **cố định và duy nhất** (ví dụ `:` trong `/etc/passwd`, `,` trong CSV đơn giản). `awk` khi dữ liệu phân cách bằng khoảng trắng không đều (log, output của lệnh như `ps`, `df`), hoặc khi cần điều kiện/tính toán.

**11. Vì sao awk dùng nháy đơn?**
Trong nháy kép, Bash thay `$1`, `$NF`… bằng biến của shell trước khi awk thấy chúng. Nháy đơn giữ nguyên mọi ký tự, chương trình awk đến tay awk đúng như bạn viết.

**12. Trước khi `sed -i` trên production:**
(1) Sao lưu file hoặc dùng `-i.bak`. (2) Chạy `sed` không có `-i` để xem kết quả. (3) Dùng `grep` kiểm tra regex khớp đúng những dòng mong muốn. (4) Sau khi sửa, `diff` với bản gốc. (5) Kiểm tra cú pháp cấu hình nếu công cụ hỗ trợ (ví dụ `nginx -t`). (6) Lý tưởng: sửa qua Git + CI/CD thay vì sửa tay trên server — sẽ học ở các module sau.

**13. Thoát vim không lưu:** `Esc` → `:q!` → `Enter`.

**14. Dòng chỉ ra nguyên nhân gốc trong log Java?**
Dòng `Caused by:` **cuối cùng** trong chuỗi exception. Exception ở trên cùng thường là lớp bọc ngoài (ví dụ `BeanCreationException`), nguyên nhân thật nằm sâu bên dưới (ví dụ `Connection refused`).

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Byte

```bash
awk '{sum += $10} END {printf "Tổng: %.2f MB\n", sum/1024/1024}' access.log
```

Với 5000 dòng, mỗi dòng trung bình ~2600 byte → khoảng **12–13 MB**.

URL trả về nhiều byte nhất tính tổng — cần **mảng kết hợp** (associative array) của awk: một "từ điển" có khóa là URL, giá trị là tổng byte.

```bash
awk '{bytes[$7] += $10} END {for (u in bytes) print bytes[u], u}' access.log | sort -rn | head -3
```

- `bytes[$7] += $10`: cộng cột 10 vào ô có khóa là URL.
- `for (u in bytes)`: duyệt mọi khóa khi đã đọc xong.
- Kết quả: `/wp-login.php` đứng đầu vì có nhiều request nhất (~1000), dù mỗi request trả về không nhiều hơn URL khác.

> Bài học: "nhiều byte nhất" thường đi cùng "nhiều request nhất". Muốn biết URL nào "nặng" thật, tính **trung bình**: `awk '{b[$7]+=$10; c[$7]++} END {for (u in b) printf "%d %s\n", b[u]/c[u], u}' access.log | sort -rn`. Với log giả lập, các URL có trung bình gần nhau vì kích thước được sinh ngẫu nhiên đều.

### Bài 2 — Khung giờ sự cố

```bash
awk '$9 ~ /^5/ {print substr($4, 14, 2)}' access.log | sort | uniq -c | sort -rn | head -5
```

Kết quả: các giờ cao điểm (9, 10, 11, 14, 15) có nhiều lỗi 5xx nhất — vì lỗi tỉ lệ thuận với lượng truy cập. Một kỹ sư tốt sẽ đặt câu hỏi tiếp: **tỉ lệ** lỗi theo giờ có thay đổi không? Nếu tỉ lệ đều, lỗi là do code; nếu tỉ lệ tăng vọt vào giờ cao điểm, có thể do quá tải.

```bash
awk '{h = substr($4,14,2); total[h]++; if ($9 ~ /^5/) err[h]++}
     END {for (h in total) printf "%s giờ: %.1f%%\n", h, err[h]*100/total[h]}' access.log | sort
```

### Bài 3 — Danh sách chặn

```bash
awk '$9 == 404 {print $1}' access.log | sort | uniq -c | awk '$1 > 100 {print $2}' > blocklist.txt
cat blocklist.txt
```

```text
198.51.100.23
```

Người dùng thường chỉ có ~30–40 lỗi 404 mỗi IP nên không bị chặn nhầm. Sinh cấu hình Nginx:

```bash
sed 's/.*/deny &;/' blocklist.txt
# hoặc
awk '{print "deny " $1 ";"}' blocklist.txt
```

```text
deny 198.51.100.23;
```

Trong `sed`, `&` đại diện cho **toàn bộ phần khớp** (ở đây `.*` = cả dòng).

> Thực tế: chặn IP ở tầng Nginx chỉ là giải pháp tạm. Bot đổi IP liên tục. Các module sau sẽ nói về Security Group, WAF, rate limiting.

### Bài 4 — User agent

Tách theo dấu nháy kép `"`. Một dòng log được chia thành:

```text
$1: 203.0.113.10 - - [31/Oct/2026:09:15:02 +0700]␣
$2: GET /api/tasks HTTP/1.1
$3: ␣200 512␣
$4: -                       ← referer
$5: ␣
$6: curl/7.81.0             ← user agent
```

```bash
awk -F'"' '{print $6}' access.log | sort | uniq -c | sort -rn
```

```text
   1000 python-requests/2.31
   ...  Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0
   ...  curl/7.81.0
   ...  Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Safari/605.1
    300 ELB-HealthChecker/2.0
```

(Chrome nhiều hơn các agent bình thường khác một chút vì mọi request lỗi `/api/reports/export` đều dùng agent Chrome.)

### Bài 5 — Dọn dẹp an toàn

```bash
cd ~/devops-lab
touch old-{1..20}.log
touch -d "10 days ago" old-{1..10}.log
ls -l old-*.log | head -3

find ~/devops-lab -maxdepth 1 -type f -name "old-*.log" -mtime +7          # 1. liệt kê
find ~/devops-lab -maxdepth 1 -type f -name "old-*.log" -mtime +7 | wc -l  # 2. đếm: phải là 10
find ~/devops-lab -maxdepth 1 -type f -name "old-*.log" -mtime +7 -delete  # 3. mới xóa
ls old-*.log | wc -l                                                       # 4. kiểm tra: còn 10
```

Lý do liệt kê trước: `-delete` không thể hoàn tác. Điều kiện của `find` rất dễ sai (`-mtime 7` khác `+7` khác `-7`; quên `-maxdepth` thì xóa luôn file trong thư mục con; đặt `-delete` trước điều kiện thì xóa mọi thứ). Liệt kê và đếm giúp chắc chắn điều kiện đúng.

> ⚠️ Thứ tự trong `find` có ý nghĩa: `find . -delete -name "*.log"` sẽ xóa **mọi file** rồi mới kiểm tra tên. `-delete` luôn phải đứng **cuối**.

### Bài 6 — Cấu hình

```bash
cp application.yml application.yml.orig
sed -i.bak -e 's/port: 8080/port: 8081/' -e 's|/taskhub$|/taskhub_dev|' application.yml
diff application.yml.orig application.yml
```

```text
2c2
<   port: 8080
---
>   port: 8081
5c5
<     url: jdbc:postgresql://postgres:5432/taskhub
---
>     url: jdbc:postgresql://postgres:5432/taskhub_dev
```

Giải thích:
- `-e` cho phép nhiều biểu thức trong một lần chạy `sed`.
- Mẫu thay port viết cụ thể `port: 8080` thay vì chỉ `8080` — tránh vô tình đổi một chuỗi `8080` khác trong file.
- Mẫu đổi tên database dùng `$` (cuối dòng) để chỉ khớp `/taskhub` ở cuối URL, không khớp chữ `taskhub` ở chỗ khác. Dùng `|` làm dấu phân cách vì chuỗi có `/`.
- Lưu ý: `-i.bak` ghi đè file `.bak` cũ từ mục 8, nên ở đây tạo thêm bản `.orig` để so sánh.
