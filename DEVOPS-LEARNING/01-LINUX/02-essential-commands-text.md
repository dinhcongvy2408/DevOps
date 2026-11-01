# 02. Lệnh thiết yếu & xử lý văn bản

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01. Kiến trúc Linux & Filesystem](01-linux-architecture-filesystem.md)
> Môi trường: `[WSL]` Ubuntu 24.04, `[Sandbox]` container `ubuntu:22.04`

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ kiến trúc](#6-sơ-đồ-kiến-trúc)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc thông báo lỗi và xử lý](#12-đọc-thông-báo-lỗi-và-xử-lý)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Tạo, sao chép, di chuyển, xóa file và thư mục **an toàn**, hiểu rõ lệnh nào không thể hoàn tác.
- Dùng **wildcard** (ký tự đại diện) và hiểu ai thực sự xử lý nó (shell, không phải lệnh).
- Xem file lớn, theo dõi log đang ghi theo thời gian thực bằng `less`, `tail -f`.
- Tìm file theo tên, loại, kích thước, thời gian bằng `find`; tìm nội dung bằng `grep`.
- Hiểu **stdin, stdout, stderr** và ghép lệnh bằng **pipe**, **redirect** để phân tích log.
- Trích xuất thông tin từ log bằng `cut`, `sort`, `uniq`, `awk`, sửa file cấu hình bằng `sed`.
- Sửa file trên server bằng `nano`, và "sống sót" được khi bị mở vào `vim`.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Trên server không có Excel, không có công cụ tìm kiếm đồ họa. Khi có sự cố, mọi thông tin nằm trong **file văn bản**: log, cấu hình, output của lệnh. Người nhanh tay xử lý sự cố là người lọc được đúng 5 dòng quan trọng trong 5 triệu dòng log.

| Tình huống | Lệnh giải quyết |
|---|---|
| "Từ 9h sáng nay API trả lỗi 500 nhiều bất thường" | `grep`, `awk` lọc log theo status code và giờ |
| "Có IP lạ đang spam server" | `awk '{print $1}' access.log \| sort \| uniq -c \| sort -rn` |
| "Ổ đầy, tìm file log lớn hơn 1GB" | `find /var/log -size +1G` |
| "Đổi port của app trong 20 file cấu hình" | `sed -i` |
| "Theo dõi log trong lúc deploy" | `tail -f` |
| "App Java chết, cần xem stack trace" | `grep -A 30 "Exception"` |

Đây là các lệnh bạn sẽ dùng **mỗi ngày**, kể cả khi đã có Grafana hay ELK — vì những hệ thống đó cũng có lúc chết.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Ba luồng dữ liệu chuẩn: stdin, stdout, stderr

Mỗi process trên Linux khi chạy được mở sẵn 3 "kênh" gọi là **file descriptor** (bộ mô tả file — một con số đại diện cho kênh vào/ra):

| Số | Tên | Tiếng Việt | Mặc định nối với |
|---|---|---|---|
| `0` | **stdin** | Đầu vào chuẩn | Bàn phím |
| `1` | **stdout** | Đầu ra chuẩn | Màn hình |
| `2` | **stderr** | Đầu ra lỗi chuẩn | Màn hình |

stdout và stderr **đều hiện ra màn hình** nên người mới nghĩ chúng là một. Thực ra là hai kênh riêng: kết quả đi stdout, thông báo lỗi đi stderr. Nhờ tách riêng, bạn có thể lưu kết quả vào file mà lỗi vẫn hiện ra màn hình, hoặc ngược lại.

### 3.2. Triết lý Unix: công cụ nhỏ + pipe

Mỗi lệnh Linux làm **một việc** và làm tốt: `sort` chỉ sắp xếp, `uniq` chỉ gộp dòng trùng, `wc` chỉ đếm. Sức mạnh đến từ việc **nối chúng lại** bằng dấu `|` (pipe — đường ống): stdout của lệnh trước trở thành stdin của lệnh sau.

```bash
cat access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head -5
```

Đọc từ trái sang phải: lấy log → lấy cột IP → sắp xếp → đếm số lần mỗi IP → sắp theo số lần giảm dần → lấy 5 dòng đầu.

### 3.3. Shell xử lý wildcard trước khi chạy lệnh

Khi bạn gõ `rm *.log`, chương trình `rm` **không hề nhìn thấy** dấu `*`. Bash mở rộng `*.log` thành danh sách file khớp (ví dụ `app.log error.log`) **rồi mới** gọi `rm app.log error.log`. Hiểu điều này giúp bạn giải thích nhiều lỗi lạ ở mục 11.

Cách kiểm tra wildcard sẽ khớp với gì trước khi chạy lệnh nguy hiểm:

```bash
echo *.log
```

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Thao tác file và thư mục

| Lệnh | Việc | Lưu ý quan trọng |
|---|---|---|
| `mkdir -p a/b/c` | Tạo thư mục, `-p` tạo luôn thư mục cha nếu chưa có, không báo lỗi nếu đã tồn tại | Luôn dùng `-p` trong script |
| `touch file` | Tạo file rỗng, hoặc cập nhật thời gian sửa nếu file đã có | |
| `cp src dst` | Sao chép | Thư mục phải thêm `-r`. **Ghi đè không hỏi** nếu `dst` đã tồn tại |
| `mv src dst` | Di chuyển **hoặc đổi tên** | Linux không có lệnh "rename" riêng — đổi tên chính là `mv`. Cũng ghi đè không hỏi |
| `rm file` | Xóa file | ⚠️ **Không có thùng rác.** Thư mục cần `-r` |
| `rmdir dir` | Xóa thư mục **rỗng** | An toàn hơn `rm -r` vì từ chối nếu còn file |

> ⚠️ `rm -rf` = xóa đệ quy (`-r`) và không hỏi, không báo lỗi (`-f`, force). Đây là lệnh gây ra nhiều sự cố nghiêm trọng nhất trong lịch sử vận hành. Quy tắc: chạy `pwd` và `ls` trước; với wildcard, chạy `echo` trước; với biến trong script, xem [mục 11](#11-các-lỗi-thường-gặp).

### 4.2. 🟥 Wildcard (globbing)

| Ký tự | Khớp với | Ví dụ | Khớp |
|---|---|---|---|
| `*` | Chuỗi bất kỳ (kể cả rỗng) | `*.log` | `app.log`, `error.log` |
| `?` | Đúng một ký tự | `app?.log` | `app1.log`, `appA.log` (không khớp `app10.log`) |
| `[abc]` | Một ký tự trong tập | `app[12].log` | `app1.log`, `app2.log` |
| `[0-9]` | Một ký tự trong khoảng | `access.log.[0-9]` | `access.log.1` … `access.log.9` |
| `{a,b}` | Liệt kê (brace expansion — không hẳn là glob nhưng hay dùng cùng) | `mkdir -p {dev,prod}/config` | tạo `dev/config` và `prod/config` |

Wildcard **không khớp file ẩn** (bắt đầu bằng `.`) trừ khi bạn viết rõ `.*`.

### 4.3. 🟥 Xem nội dung file

| Lệnh | Khi nào dùng |
|---|---|
| `cat file` | File ngắn (vài chục dòng). Không dùng cho log lớn — sẽ tràn màn hình |
| `less file` | File dài: cuộn, tìm kiếm, **không tải cả file vào RAM** nên mở được file nhiều GB |
| `head -n 20 file` | 20 dòng đầu — xem định dạng file |
| `tail -n 50 file` | 50 dòng cuối — log mới nhất |
| `tail -f file` | Theo dõi file **đang được ghi thêm** (follow). Ctrl+C để thoát |
| `tail -F file` | Như `-f` nhưng tự mở lại nếu file bị **log rotation** (xoay vòng log) thay thế |

Phím trong `less` cần nhớ:

| Phím | Việc |
|---|---|
| `Space` / `b` | Trang sau / trang trước |
| `g` / `G` | Về đầu / xuống cuối file |
| `/từ-khóa` | Tìm xuôi; `n` kết quả tiếp, `N` kết quả trước |
| `?từ-khóa` | Tìm ngược lên |
| `F` | Chuyển sang chế độ theo dõi như `tail -f` (Ctrl+C để dừng theo dõi) |
| `q` | Thoát |

### 4.4. 🟥 Tìm file: `find`

Cú pháp: `find <nơi-tìm> <điều-kiện> <hành-động>`.

| Điều kiện | Nghĩa |
|---|---|
| `-name "*.log"` | Tên khớp mẫu (phân biệt hoa thường). `-iname` không phân biệt. **Luôn đặt mẫu trong nháy** để shell không mở rộng trước |
| `-type f` / `-type d` / `-type l` | Chỉ file / thư mục / symbolic link |
| `-size +100M` | Lớn hơn 100MB (`-` là nhỏ hơn; đơn vị `k`, `M`, `G`) |
| `-mtime +7` | Sửa lần cuối **cách đây hơn** 7 ngày (`-7`: trong vòng 7 ngày). `-mmin` tính bằng phút |
| `-user taskhub` | Thuộc user `taskhub` |
| `-maxdepth 2` | Chỉ tìm sâu tối đa 2 cấp |

| Hành động | Nghĩa |
|---|---|
| (mặc định) `-print` | In đường dẫn |
| `-exec lệnh {} \;` | Chạy lệnh cho **từng** file, `{}` được thay bằng tên file |
| `-exec lệnh {} +` | Gom nhiều file vào **một** lần chạy lệnh (nhanh hơn) |
| `-delete` | ⚠️ Xóa file tìm được. **Luôn chạy không có `-delete` trước** để xem danh sách |

### 4.5. 🟥 Tìm nội dung: `grep`

`grep` in ra các **dòng** chứa mẫu (pattern) cần tìm.

| Tham số | Nghĩa |
|---|---|
| `-i` | Không phân biệt hoa thường |
| `-v` | Đảo ngược: in dòng **không** khớp (lọc bỏ nhiễu) |
| `-n` | Hiện số dòng |
| `-c` | Chỉ đếm số dòng khớp |
| `-r` | Tìm đệ quy trong thư mục |
| `-l` | Chỉ in tên file có chứa mẫu |
| `-o` | Chỉ in **phần khớp**, không in cả dòng |
| `-E` | Dùng biểu thức chính quy mở rộng (extended regex): `\|`, `+`, `?`, `()` không cần escape |
| `-A 5` / `-B 5` / `-C 5` | In thêm 5 dòng sau (After) / trước (Before) / cả hai (Context) — **cực kỳ hữu ích với stack trace Java** |
| `-w` | Khớp nguyên từ (`-w 500` không khớp `1500`) |

Biểu thức chính quy (regular expression — regex) cơ bản đủ dùng:

| Ký hiệu | Nghĩa | Ví dụ |
|---|---|---|
| `^` | Đầu dòng | `^ERROR` — dòng bắt đầu bằng ERROR |
| `$` | Cuối dòng | `\.jar$` |
| `.` | Một ký tự bất kỳ | `5..` — 500, 503… |
| `*` | Lặp lại ký tự trước 0 lần trở lên | |
| `[0-9]` | Một chữ số | |
| `A\|B` (với `-E`: `A|B`) | A hoặc B | `-E "ERROR|WARN"` |

> Wildcard của shell (`*.log`) và regex (`.*`) **là hai thứ khác nhau**. Trong regex, `*` không đứng một mình mà lặp ký tự trước nó.

### 4.6. 🟥 Bộ công cụ xử lý dòng: `wc`, `sort`, `uniq`, `cut`, `tr`

| Lệnh | Việc | Tham số hay dùng |
|---|---|---|
| `wc` | Đếm (word count) | `-l` đếm dòng |
| `sort` | Sắp xếp dòng | `-n` theo số, `-r` giảm dần, `-k2` theo cột 2, `-t:` dùng `:` làm dấu phân cách, `-h` theo kích thước dễ đọc (1K, 2M) |
| `uniq` | Gộp các dòng trùng **liền kề** | `-c` đếm số lần lặp. **Phải `sort` trước** vì chỉ gộp dòng liền nhau |
| `cut` | Cắt cột | `-d' '` dấu phân cách, `-f1,3` lấy cột 1 và 3 |
| `tr` | Thay/xóa ký tự | `tr 'a-z' 'A-Z'` đổi hoa, `tr -d '\r'` xóa ký tự CR |

Mẫu kinh điển **"đếm và xếp hạng"** — sẽ dùng cả đời:

```bash
<lấy cột cần đếm> | sort | uniq -c | sort -rn | head
```

### 4.7. 🟥 `awk` cơ bản — làm việc với cột

`awk` là cả một ngôn ngữ lập trình, nhưng DevOps Junior chỉ cần 3 cách dùng:

```bash
awk '{print $1}' file               # in cột 1 (mặc định tách cột theo khoảng trắng)
awk '$9 == 500 {print $7}' file     # in cột 7 của những dòng có cột 9 bằng 500
awk -F: '{print $1, $7}' /etc/passwd  # tách cột bằng dấu ":"
```

- `$1`, `$2`… là cột thứ 1, 2…; `$0` là cả dòng; `NF` là số cột của dòng; `$NF` là cột cuối.
- Cấu trúc: `điều-kiện {hành-động}`. Bỏ điều kiện → áp dụng mọi dòng.
- `$9 ~ /^5/` nghĩa là "cột 9 khớp regex `^5`" (bắt đầu bằng 5).

Khi nào dùng `cut`, khi nào dùng `awk`? `cut` chỉ tách theo **một ký tự** cố định; log có nhiều dấu cách liên tiếp thì `cut -d' '` sẽ đếm sai cột. `awk` coi nhiều khoảng trắng liền nhau là một → an toàn hơn với log.

### 4.8. 🟥 `sed` cơ bản — sửa văn bản không cần mở editor

```bash
sed 's/cũ/mới/' file        # thay lần xuất hiện ĐẦU TIÊN trên mỗi dòng, in ra màn hình
sed 's/cũ/mới/g' file       # thay TẤT CẢ (g = global)
sed -i 's/cũ/mới/g' file    # ⚠️ sửa thẳng vào file (in-place)
sed -i.bak 's/cũ/mới/g' file  # sửa thẳng, nhưng giữ bản gốc ở file.bak
sed -n '10,20p' file        # chỉ in dòng 10 đến 20
```

Quy trình an toàn với `sed`: chạy **không có `-i`** để xem kết quả trên màn hình → đúng rồi mới thêm `-i.bak`.

Nếu chuỗi cần thay chứa dấu `/` (ví dụ đường dẫn), đổi dấu phân cách: `sed 's|/opt/old|/opt/new|g'`.

### 4.9. 🟥 Redirect — chuyển hướng luồng dữ liệu

| Cú pháp | Nghĩa |
|---|---|
| `lệnh > file` | stdout ghi vào file, **ghi đè** nội dung cũ |
| `lệnh >> file` | stdout ghi **nối thêm** vào cuối file |
| `lệnh 2> file` | stderr ghi vào file |
| `lệnh > file 2>&1` | stdout vào file, rồi stderr đi theo "nơi stdout đang đi" → cả hai vào file |
| `lệnh &> file` | Viết tắt của dòng trên (chỉ Bash) |
| `lệnh 2> /dev/null` | Vứt bỏ thông báo lỗi |
| `lệnh < file` | Lấy stdin từ file |

> ⚠️ **Thứ tự quan trọng:** `lệnh > file 2>&1` gom cả hai vào file. Còn `lệnh 2>&1 > file` thì stderr vẫn ra màn hình — vì lúc `2>&1` được xử lý, stdout vẫn đang trỏ ra màn hình. Đọc từ trái sang phải như phép gán.

### 4.10. 🟨 `tee` và `xargs`

- **`tee`**: vừa hiện ra màn hình, vừa ghi vào file — như chữ T của ống nước. Hay dùng để lưu output của một lệnh dài mà vẫn muốn xem.

  ```bash
  ./deploy.sh 2>&1 | tee deploy-$(date +%F).log
  ```

  Một cách dùng quan trọng khác: ghi vào file cần quyền root. `sudo echo "x" > /etc/file` **không hoạt động** vì redirect `>` do shell của bạn (user thường) thực hiện, không phải `sudo`. Cách đúng:

  ```bash
  echo "127.0.0.1 taskhub.local" | sudo tee -a /etc/hosts
  ```

- **`xargs`**: biến stdin thành **tham số** cho lệnh khác. Cần thiết vì nhiều lệnh (`rm`, `ls`) không đọc stdin.

  ```bash
  find . -name "*.tmp" -print0 | xargs -0 rm -v
  ```

  `-print0` và `-0` dùng ký tự null làm dấu phân cách để **tên file có dấu cách không bị tách sai**.

### 4.11. 🟥 Sửa file trên server: `nano` và `vim`

**`nano`** — dễ dùng, có sẵn trên Ubuntu. Phím tắt hiện ở dưới màn hình, `^` nghĩa là Ctrl:

| Phím | Việc |
|---|---|
| `Ctrl+O`, `Enter` | Lưu |
| `Ctrl+X` | Thoát |
| `Ctrl+W` | Tìm kiếm |
| `Ctrl+K` / `Ctrl+U` | Cắt dòng / dán |

**`vim`** — có mặt trên gần như mọi server và container, và một số lệnh (`git commit`, `crontab -e`, `visudo`) có thể mở vim mặc định. Mức "sống sót" bắt buộc phải thuộc:

```text
vim có 2 chế độ chính:
  NORMAL (mặc định khi mở) ── gõ i ──► INSERT (gõ chữ bình thường)
  NORMAL ◄── nhấn Esc ───────────────── INSERT

Trong NORMAL:
  :wq  Enter   → lưu và thoát
  :q!  Enter   → thoát KHÔNG lưu (khi lỡ sửa linh tinh)
  /từ  Enter   → tìm kiếm
  dd           → xóa dòng hiện tại
  u            → hoàn tác
```

Bị "kẹt" trong vim: nhấn `Esc` vài lần, gõ `:q!`, Enter.

> Muốn đổi editor mặc định sang nano: `export EDITOR=nano` (biến môi trường — học ở [bài 06](06-bash-scripting.md)).

### 4.12. 🟥 Nháy đơn và nháy kép — mức cơ bản

| Cách viết | Bash có thay biến `$X`, wildcard `*` không? | Dùng khi |
|---|---|---|
| `'chuỗi'` | **Không** — giữ nguyên từng ký tự | Chương trình awk, regex, sed: `awk '{print $1}'` |
| `"chuỗi"` | Thay biến, **không** mở rộng wildcard | Chuỗi chứa biến: `echo "Home: $HOME"` |
| không nháy | Thay biến **và** tách từ theo khoảng trắng, mở rộng wildcard | Tránh dùng với biến |

Vì sao `awk` luôn dùng nháy đơn? Vì `$1` trong `awk '{print $1}'` là cột của awk. Nếu dùng nháy kép, Bash sẽ thay `$1` bằng biến của shell (thường là rỗng) trước khi awk kịp thấy. Phần quoting nâng cao được học kỹ ở [bài 06](06-bash-scripting.md).

---

## 5. Ví dụ thực tế

### Ví dụ 1: Tìm stack trace khi app Spring Boot chết

Log của app Java thường có một dòng `ERROR` theo sau là hàng chục dòng stack trace:

```bash
grep -n -A 15 "ERROR" /var/log/taskhub/app.log | less
```

```text
1842:2026-10-31 09:15:02.114 ERROR 1234 --- [main] o.s.boot.SpringApplication : Application run failed
1843-org.springframework.beans.factory.BeanCreationException: Error creating bean with name 'dataSource'...
1844-	at org.springframework.beans.factory.support...
...
1851-Caused by: org.postgresql.util.PSQLException: Connection to localhost:5432 refused.
```

Mẹo đọc stack trace Java: dòng **`Caused by:` cuối cùng** thường là nguyên nhân gốc. Lọc nhanh:

```bash
grep "Caused by" /var/log/taskhub/app.log | tail -3
```

### Ví dụ 2: Ổ đĩa đầy — tìm thủ phạm

```bash
sudo find /var/log -type f -size +100M -exec ls -lh {} \; 2>/dev/null
sudo find /var/log -type f -name "*.gz" -mtime +30
```

Dòng đầu tìm log lớn hơn 100MB và hiện kích thước. Dòng hai tìm log nén cũ hơn 30 ngày — ứng viên để xóa (sau khi đã xác nhận với team).

### Ví dụ 3: Đổi cấu hình trên nhiều file

Database chuyển từ `db-old.internal` sang `db-new.internal`:

```bash
grep -rl "db-old.internal" /opt/taskhub/config/          # 1. file nào chứa chuỗi cũ?
sed -n 's/db-old.internal/db-new.internal/gp' /opt/taskhub/config/application.yml  # 2. xem trước
grep -rl "db-old.internal" /opt/taskhub/config/ | xargs sed -i.bak 's/db-old.internal/db-new.internal/g'  # 3. sửa, giữ .bak
```

### Ví dụ 4: Theo dõi log trong lúc deploy

```bash
tail -F /var/log/nginx/access.log | grep --line-buffered " 50[0-9] "
```

Chỉ hiện những request lỗi 5xx khi chúng vừa xảy ra. `--line-buffered` để grep in ngay từng dòng thay vì gom lại rồi mới in.

---

## 6. Sơ đồ kiến trúc

### 6.1. File descriptor của một process

```text
                 ┌─────────────────────┐
  bàn phím ──0──►│                     │──1── stdout ──► màn hình (hoặc file / pipe)
   (stdin)       │      process        │
                 │                     │──2── stderr ──► màn hình (hoặc file khác)
                 └─────────────────────┘
```

### 6.2. Pipe và redirect trong một dòng lệnh

```bash
grep " 500 " access.log | awk '{print $7}' | sort | uniq -c > errors.txt 2> grep-err.txt
```

```text
 access.log ──► grep ──stdout──► awk ──stdout──► sort ──► uniq -c ──stdout──► errors.txt
                 │                │                │          │
                 └─────stderr─────┴────────────────┴──────────┴──► màn hình
                                                              (riêng uniq: stderr ──► grep-err.txt)
```

Lưu ý: `2> grep-err.txt` ở cuối dòng chỉ áp dụng cho lệnh **cuối cùng** (`uniq`), không phải cho `grep`. Mỗi lệnh trong pipeline có stderr riêng.

---

## 7. Các câu lệnh cần biết

| Lệnh | Mục đích | Mức |
|---|---|---|
| `mkdir -p`, `touch` | Tạo thư mục, file | 🟥 |
| `cp -r`, `mv`, `rm -r`, `rmdir` | Sao chép, di chuyển/đổi tên, xóa | 🟥 |
| `cat`, `less`, `head`, `tail -f/-F` | Xem file | 🟥 |
| `find` | Tìm file theo thuộc tính | 🟥 |
| `grep` | Tìm dòng theo nội dung | 🟥 |
| `wc -l`, `sort`, `uniq -c` | Đếm, sắp xếp, gộp trùng | 🟥 |
| `cut`, `tr` | Cắt cột, đổi ký tự | 🟥 |
| `awk` | Xử lý theo cột, lọc điều kiện | 🟥 |
| `sed` | Thay thế văn bản | 🟥 |
| `>`, `>>`, `2>`, `2>&1`, `&>`, `<`, `\|` | Redirect và pipe | 🟥 |
| `tee`, `xargs` | Chia đôi output, biến stdin thành tham số | 🟨 |
| `nano`, `vim` (mức sống sót) | Sửa file trên server | 🟥 |
| `diff` | So sánh 2 file (ví dụ cấu hình cũ/mới) | 🟨 |

---

## 8. Giải thích câu lệnh và tham số

> Mọi ví dụ chạy trong `~/devops-lab/01-linux/02-text` `[WSL]`. Tạo thư mục trước: `mkdir -p ~/devops-lab/01-linux/02-text && cd $_` (`$_` là tham số cuối của lệnh trước).

### `mkdir -p`, `touch`, `cp`, `mv`, `rm`

```bash
mkdir -p project/{src,config,logs}
touch project/config/app.yml project/logs/app.log
ls -R project
```

```text
project:
config  logs  src

project/config:
app.yml

project/logs:
app.log

project/src:
```

| Lệnh / tham số | Ý nghĩa |
|---|---|
| `mkdir -p` | Tạo cả cây, không lỗi nếu đã tồn tại |
| `{src,config,logs}` | Brace expansion: Bash biến thành 3 đường dẫn |
| `ls -R` | Liệt kê đệ quy |

```bash
cp project/config/app.yml project/config/app.yml.bak   # sao lưu trước khi sửa
cp -r project project-copy                             # sao chép cả thư mục
mv project-copy project-old                            # đổi tên
rm -ri project-old                                     # xóa, hỏi từng file
```

```text
rm: descend into directory 'project-old'? y
rm: remove regular empty file 'project-old/config/app.yml'? y
...
```

| Tham số | Ý nghĩa |
|---|---|
| `cp -r` | Đệ quy (recursive) — bắt buộc với thư mục |
| `cp -p` | Giữ nguyên quyền, chủ sở hữu, thời gian (preserve) — dùng khi backup |
| `cp -i`, `mv -i`, `rm -i` | Hỏi xác nhận (interactive) trước khi ghi đè/xóa |
| `rm -r` | Xóa đệ quy |
| `rm -f` | ⚠️ Không hỏi, không báo lỗi nếu file không tồn tại |
| `-v` | In ra từng thao tác (verbose) — nên dùng khi xóa/chép nhiều file |

### `head`, `tail`, `less`

```bash
seq 1 1000 > numbers.txt     # tạo file 1000 dòng, mỗi dòng một số
head -n 3 numbers.txt
tail -n 3 numbers.txt
```

```text
1
2
3
998
999
1000
```

Thử `tail -f` — mở 2 terminal:

```bash
# Terminal 1
tail -f ~/devops-lab/01-linux/02-text/live.log
# Terminal 2
for i in 1 2 3; do echo "$(date +%T) request $i" >> ~/devops-lab/01-linux/02-text/live.log; sleep 1; done
```

Terminal 1 sẽ hiện từng dòng mới ngay khi nó được ghi. Nhấn `Ctrl+C` để thoát.

| Tham số | Ý nghĩa |
|---|---|
| `-n N` | Số dòng (mặc định 10) |
| `-n +N` (với `tail`) | Từ dòng N đến hết file |
| `-f` | Follow — theo dõi file đang ghi |
| `-F` | Follow theo **tên file**: nếu log bị rotate (đổi tên và tạo file mới), tự mở file mới |

### `find`

```bash
find ~/devops-lab -type f -name "*.log"
find /etc -maxdepth 1 -type f -name "*.conf" | head -5
find /var/log -type f -mmin -60 2>/dev/null
```

```text
/home/phuong/devops-lab/01-linux/02-text/project/logs/app.log
/home/phuong/devops-lab/01-linux/02-text/live.log
/etc/adduser.conf
/etc/ld.so.conf
/etc/sysctl.conf
...
```

| Tham số | Ý nghĩa |
|---|---|
| `-type f` | Chỉ file thường |
| `-name "*.log"` | Theo tên. **Phải có nháy**: không có nháy và trong thư mục hiện tại có file `.log`, shell sẽ mở rộng `*.log` trước và `find` nhận sai tham số |
| `-maxdepth 1` | Chỉ tìm ở cấp đầu tiên |
| `-mmin -60` | Sửa trong 60 phút qua — tìm "file nào vừa thay đổi" khi có sự cố |
| `2>/dev/null` | Bỏ các dòng `Permission denied` khi tìm trong thư mục hệ thống bằng user thường |

Dùng `-exec`:

```bash
find ~/devops-lab -type f -name "*.log" -exec wc -l {} +
```

```text
  0 /home/phuong/devops-lab/01-linux/02-text/project/logs/app.log
  3 /home/phuong/devops-lab/01-linux/02-text/live.log
  3 total
```

### `grep`

Tạo một file log Java mẫu:

```bash
cat > app.log << 'EOF'
2026-10-31 09:00:01 INFO  Starting TaskhubApplication using Java 21
2026-10-31 09:00:05 INFO  Tomcat started on port 8080
2026-10-31 09:10:12 WARN  Slow query detected: 2300 ms
2026-10-31 09:15:02 ERROR Request failed: /api/tasks/99
java.lang.NullPointerException: task is null
	at com.example.taskhub.TaskService.find(TaskService.java:42)
	at com.example.taskhub.TaskController.get(TaskController.java:27)
2026-10-31 09:20:44 INFO  Health check OK
2026-10-31 09:31:09 error Connection reset by peer
EOF
```

> `cat > file << 'EOF' ... EOF` gọi là **here-document**: mọi dòng giữa hai chữ `EOF` được đưa vào stdin của `cat`, rồi `>` ghi ra file. Nháy quanh `'EOF'` để Bash không thay biến bên trong.

```bash
grep ERROR app.log
grep -i error app.log
grep -c INFO app.log
grep -v INFO app.log
grep -n -A 3 ERROR app.log
grep -E "WARN|ERROR" app.log
grep -o "[0-9]* ms" app.log
```

```text
# grep ERROR app.log
2026-10-31 09:15:02 ERROR Request failed: /api/tasks/99

# grep -i error app.log
2026-10-31 09:15:02 ERROR Request failed: /api/tasks/99
2026-10-31 09:31:09 error Connection reset by peer

# grep -c INFO app.log
3

# grep -n -A 3 ERROR app.log
4:2026-10-31 09:15:02 ERROR Request failed: /api/tasks/99
5-java.lang.NullPointerException: task is null
6-	at com.example.taskhub.TaskService.find(TaskService.java:42)
7-	at com.example.taskhub.TaskController.get(TaskController.java:27)

# grep -o "[0-9]* ms" app.log
2300 ms
```

Chú ý: trong output của `-n -A`, dòng khớp dùng dấu `:` sau số dòng, dòng ngữ cảnh dùng dấu `-`.

### `wc`, `sort`, `uniq`, `cut`, `tr`

```bash
awk '{print $3}' app.log | sort | uniq -c | sort -rn
```

```text
      3 INFO
      2
      1 is
      1 error
      1 WARN
      1 ERROR
```

(Thứ tự các dòng có cùng số đếm có thể khác trên máy bạn.)

Kết quả có rác — một dòng trống đếm được 2 lần và chữ `is` — vì các dòng stack trace không có cột 3 là log level: dòng `at com.example...` chỉ có 2 cột nên cột 3 rỗng, dòng `java.lang.NullPointerException: task is null` có cột 3 là `is`. Lọc trước bằng grep chỉ lấy dòng bắt đầu bằng ngày:

```bash
grep -E "^[0-9]{4}-" app.log | awk '{print toupper($3)}' | sort | uniq -c | sort -rn
```

```text
      3 INFO
      2 ERROR
      1 WARN
```

Đây là bài học quan trọng: **luôn kiểm tra dữ liệu đầu vào có đúng định dạng không** trước khi tin kết quả thống kê.

```bash
cut -d: -f1,7 /etc/passwd | head -3
echo "Hello World" | tr 'a-z' 'A-Z'
wc -l app.log
```

```text
root:/bin/bash
daemon:/usr/sbin/nologin
bin:/usr/sbin/nologin
HELLO WORLD
9 app.log
```

| Lệnh | Tham số | Ý nghĩa |
|---|---|---|
| `sort` | `-n` / `-r` / `-k N` / `-t X` / `-h` / `-u` | Theo số / giảm dần / theo cột N / dấu phân cách X / theo kích thước dễ đọc / bỏ trùng |
| `uniq` | `-c` / `-d` | Đếm / chỉ in dòng bị lặp |
| `cut` | `-d X` / `-f N` / `-c 1-10` | Dấu phân cách / cột / ký tự thứ 1–10 |
| `tr` | `'a-z' 'A-Z'` / `-d 'x'` / `-s ' '` | Đổi ký tự / xóa / gộp ký tự lặp |

### `awk`

```bash
awk -F: '$3 >= 1000 {print $1, $3, $7}' /etc/passwd
```

```text
nobody 65534 /usr/sbin/nologin
phuong 1000 /bin/bash
```

Giải thích: tách cột bằng `:`, chọn dòng có cột 3 (UID) ≥ 1000, in tên, UID, shell. (Ý nghĩa các cột của `/etc/passwd` học ở [bài 03](03-permissions-users-groups.md).)

Tính tổng một cột — ví dụ tổng thời gian query chậm:

```bash
grep -o "[0-9]* ms" app.log | awk '{sum += $1} END {print "Tổng:", sum, "ms"}'
```

```text
Tổng: 2300 ms
```

`END {...}` chạy **một lần** sau khi đọc hết dữ liệu.

### `sed`

```bash
cat > application.yml << 'EOF'
server:
  port: 8080
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/taskhub
EOF

sed 's/8080/9090/' application.yml           # chỉ in ra, file chưa đổi
sed -i.bak 's/localhost/postgres/' application.yml
diff application.yml.bak application.yml
```

```text
5c5
<     url: jdbc:postgresql://localhost:5432/taskhub
---
>     url: jdbc:postgresql://postgres:5432/taskhub
```

`diff` cho thấy dòng 5 đã đổi (`c` = changed). `<` là file thứ nhất, `>` là file thứ hai.

### Redirect và `/dev/null`

```bash
ls /etc /khong-co > out.txt
cat out.txt | head -2
ls /etc /khong-co > out.txt 2> err.txt
cat err.txt
ls /etc /khong-co &> all.txt
ls /etc /khong-co > /dev/null 2>&1; echo "exit code: $?"
```

```text
ls: cannot access '/khong-co': No such file or directory     ← vẫn hiện ra màn hình: đó là stderr
/etc:
adduser.conf
ls: cannot access '/khong-co': No such file or directory     ← nội dung err.txt
exit code: 2
```

Dòng cuối là mẫu rất hay gặp trong script: **chỉ quan tâm lệnh thành công hay thất bại**, không cần output.

### `tee` và `xargs`

```bash
echo "deploy started" | tee -a deploy.log
find . -name "*.bak" | xargs ls -l
```

| Tham số | Ý nghĩa |
|---|---|
| `tee -a` | Nối thêm (append) thay vì ghi đè |
| `xargs -0` | Đọc danh sách phân cách bởi null (đi cùng `find -print0`) |
| `xargs -n 1` | Mỗi lần chạy lệnh chỉ truyền 1 tham số |
| `xargs -I{}` | Chỉ định chỗ đặt tham số: `xargs -I{} cp {} /backup/` |

---

## 9. Bài thực hành từng bước

**Lab: Phân tích access log của Nginx** · `[WSL]` · ~90 phút

Bối cảnh: sếp báo "hôm qua web có vẻ bị chậm và lỗi nhiều, xem log giúp anh". Bạn có file access log của Nginx. Không có công cụ nào khác ngoài terminal.

### Bước 1 — Hiểu định dạng log

Nginx mặc định ghi access log theo định dạng **combined** (theo [tài liệu chính thức](https://nginx.org/en/docs/http/ngx_http_log_module.html)):

```nginx
log_format combined '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent"';
```

Một dòng log thật trông như sau. Khi `awk` tách theo khoảng trắng, các cột được đánh số:

```text
203.0.113.10 - - [31/Oct/2026:09:15:02 +0700] "GET /api/tasks HTTP/1.1" 200 512 "-" "curl/7.81.0"
│            │ │ │                     │      │    │          │         │   │   │   └ $12 trở đi: user agent
│            │ │ │                     │      │    │          │         │   │   └ $11: referer
│            │ │ │                     │      │    │          │         │   └ $10: số byte trả về
│            │ │ │                     │      │    │          │         └ $9: status code
│            │ │ │                     │      │    │          └ $8: giao thức
│            │ │ │                     │      │    └ $7: URL
│            │ │ │                     │      └ $6: method (kèm dấu ")
│            │ │ │                     └ $5: múi giờ
│            │ │ └ $4: thời gian (kèm dấu [)
│            │ └ $3: user đăng nhập (thường "-")
│            └ $2: luôn là "-"
└ $1: IP client
```

Trên Ubuntu, Nginx cài bằng `apt` ghi log vào `/var/log/nginx/access.log`.

### Bước 2 — Sinh file log mẫu

Tạo thư mục lab và script sinh log:

```bash
mkdir -p ~/devops-lab/01-linux/02-text/lab && cd ~/devops-lab/01-linux/02-text/lab
nano gen-access-log.sh
```

Dán nội dung sau (trong nano: `Ctrl+Shift+V` hoặc chuột phải để dán), lưu `Ctrl+O`, `Enter`, thoát `Ctrl+X`:

```bash
#!/bin/bash
# Sinh access log giả lập theo định dạng "combined" của Nginx.
# Cách dùng: bash gen-access-log.sh [số_dòng] > access.log
# Mọi IP đều thuộc dải dành cho tài liệu (RFC 5737) hoặc dải private, không phải IP thật.

LINES=${1:-5000}
RANDOM=42   # cố định "hạt giống" ngẫu nhiên để kết quả lặp lại được

users=(203.0.113.10 203.0.113.11 203.0.113.12 203.0.113.25 198.51.100.7
       198.51.100.8 198.51.100.9 192.0.2.44 192.0.2.45 192.0.2.46)
urls=(/ /api/tasks /api/tasks/1 /api/tasks/2 /api/tasks/3 /api/users/me
      /static/app.js /static/style.css /login)
agents=("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0"
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) Safari/605.1"
        "curl/7.81.0")
# Giờ cao điểm (8h-17h) xuất hiện nhiều lần hơn trong danh sách
hours=(0 1 2 3 4 5 6 7 8 8 9 9 9 10 10 10 11 11 11 12 13 14 14 14
       15 15 15 16 16 17 18 19 20 20 21 22 23)

generate() {
  for ((i = 0; i < LINES; i++)); do
    hour=${hours[RANDOM % ${#hours[@]}]}
    ts=$(printf "31/Oct/2026:%02d:%02d:%02d +0700" "$hour" $((RANDOM % 60)) $((RANDOM % 60)))
    r=$((RANDOM % 100))
    if (( r < 20 )); then          # một IP dò quét lỗ hổng
      ip=198.51.100.23; method=GET; url=/wp-login.php; status=404; agent="python-requests/2.31"
    elif (( r < 26 )); then        # health check nội bộ từ load balancer
      ip=10.0.1.$((15 + RANDOM % 2)); method=GET; url=/actuator/health; status=200; agent="ELB-HealthChecker/2.0"
    elif (( r < 31 )); then        # một API bị lỗi
      ip=${users[RANDOM % ${#users[@]}]}; method=POST; url=/api/reports/export; status=500; agent=${agents[0]}
    else                           # truy cập bình thường
      ip=${users[RANDOM % ${#users[@]}]}; url=${urls[RANDOM % ${#urls[@]}]}; agent=${agents[RANDOM % 3]}
      method=GET; status=200
      (( RANDOM % 10 == 0 )) && status=404
      [[ $url == /login ]] && { method=POST; status=302; }
      (( RANDOM % 50 == 0 )) && status=502
    fi
    printf '%s - - [%s] "%s %s HTTP/1.1" %d %d "-" "%s"\n' \
      "$ip" "$ts" "$method" "$url" "$status" $((RANDOM % 5000 + 100)) "$agent"
  done
}

# Sắp xếp theo cột thời gian để giống log thật (ghi theo thứ tự thời gian)
generate | sort -t' ' -k4,4
```

Chạy:

```bash
bash gen-access-log.sh 5000 > access.log
wc -l access.log
head -3 access.log
```

> Bạn chưa cần hiểu từng dòng của script — [bài 06](06-bash-scripting.md) sẽ dạy Bash. Nhưng hãy thử đọc và đoán: phần nào tạo ra IP dò quét? Phần nào tạo lỗi 500?

### Bước 3 — Có bao nhiêu request, trong khoảng thời gian nào?

```bash
wc -l access.log
head -1 access.log | awk '{print $4}'
tail -1 access.log | awk '{print $4}'
```

### Bước 4 — Top 10 IP gửi nhiều request nhất

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
```

❓ IP nào nổi bật hẳn so với phần còn lại? Nó gọi URL gì? Kiểm tra:

```bash
grep "^198.51.100.23 " access.log | awk '{print $7}' | sort | uniq -c
```

### Bước 5 — Phân bố status code

```bash
awk '{print $9}' access.log | sort | uniq -c | sort -rn
```

❓ Tỉ lệ lỗi 5xx là bao nhiêu phần trăm? Tính bằng awk:

```bash
awk '$9 ~ /^5/ {err++} END {printf "5xx: %d / %d = %.2f%%\n", err, NR, err*100/NR}' access.log
```

`NR` là số dòng đã đọc; `printf` định dạng số với 2 chữ số thập phân.

### Bước 6 — URL nào gây lỗi 5xx?

```bash
awk '$9 ~ /^5/ {print $9, $6, $7}' access.log | sort | uniq -c | sort -rn
```

❓ Có mấy loại lỗi 5xx? URL nào là thủ phạm chính?

### Bước 7 — Lượng request theo giờ

Thời gian có dạng `[31/Oct/2026:09:15:02`. Cách 1 — dùng `cut` với dấu `:`:

```bash
cut -d: -f2 access.log | sort | uniq -c
```

Cách 2 — dùng `awk` cắt chuỗi (ký tự 14–15 của cột 4 là giờ):

```bash
awk '{print substr($4, 14, 2)}' access.log | sort | uniq -c
```

❓ Giờ nào cao điểm nhất? Tại sao `cut -d:` lấy đúng giờ? (Gợi ý: đếm dấu `:` trong dòng log.)

### Bước 8 — Lọc nhiễu: bỏ health check và bot

```bash
grep -v -E "actuator/health|wp-login" access.log | wc -l
grep -v -E "actuator/health|wp-login" access.log | awk '{print $9}' | sort | uniq -c | sort -rn
```

❓ Tại sao khi phân tích trải nghiệm người dùng thật nên loại health check ra?

### Bước 9 — Viết báo cáo

Lưu kết quả vào file báo cáo, dùng `tee` để vừa xem vừa ghi:

```bash
{
  echo "# Báo cáo access log ngày 31/10/2026"
  echo "## Tổng request"; wc -l < access.log
  echo "## Top 5 IP"; awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -5
  echo "## Status code"; awk '{print $9}' access.log | sort | uniq -c | sort -rn
  echo "## URL lỗi 5xx"; awk '$9 ~ /^5/ {print $7}' access.log | sort | uniq -c | sort -rn
} | tee report.md
```

`{ ...; }` gom nhiều lệnh thành một khối để chung một đầu ra.

Viết thêm 3–5 câu **kết luận bằng lời** vào cuối `report.md` (dùng `nano report.md`): vấn đề là gì, mức độ nghiêm trọng, đề xuất xử lý.

### Bước 10 — Commit

```bash
mkdir -p ~/devops-journey/week01
cp gen-access-log.sh report.md ~/devops-journey/week01/
cd ~/devops-journey
git add week01/
git commit -m "docs(linux): lab 02 - nginx access log analysis"
git push
```

Không commit `access.log` — đó là dữ liệu sinh ra được, không phải mã nguồn.

---

## 10. Kết quả mong đợi

Con số chính xác phụ thuộc vào phiên bản Bash, nhưng **xu hướng** phải như sau:

- **Bước 3:** 5000 dòng, thời gian từ khoảng `00:xx` đến `23:xx` ngày 31/10/2026.
- **Bước 4:** `198.51.100.23` đứng đầu với khoảng 1000 request (~20%), gấp khoảng 3 lần mỗi IP người dùng (~350 request). Nó chỉ gọi `/wp-login.php` → đây là **bot dò quét lỗ hổng WordPress** (dù app của bạn là Java, bot vẫn quét mù). Hai IP `10.0.1.15`, `10.0.1.16` (dải private) có khoảng 150 request mỗi IP, rải đều cả 24 giờ — đó là health check của load balancer.
- **Bước 5:** Phần lớn là `200`, sau đó `404` (bot + URL sai, ~1300), `500` (~250), `302` (login), một ít `502`. Tỉ lệ 5xx khoảng 6–7%.
- **Bước 6:** Hai loại lỗi: `500` gần như toàn bộ đến từ `POST /api/reports/export` → **lỗi trong code của API này**. `502` rải rác nhiều URL → thường do Nginx không kết nối được tới app (app restart hoặc quá tải) — hai loại lỗi có nguyên nhân khác nhau.
- **Bước 7:** Giờ 9, 10, 11, 14, 15 cao nhất. `cut -d: -f2` đúng vì dấu `:` đầu tiên trong dòng nằm ngay sau năm `2026`, nên trường thứ 2 là giờ.
- **Bước 8:** Health check gửi request đều đặn và luôn thành công → làm tỉ lệ thành công **trông đẹp hơn thực tế**. Bot cũng không phải người dùng thật.
- **Bước 9:** `report.md` có số liệu và kết luận. Ví dụ kết luận tốt: *"API `/api/reports/export` lỗi 500 với 100% request — cần xem log ứng dụng. Có một IP dò quét `/wp-login.php`, đề xuất chặn ở Nginx hoặc Security Group. Lỗi 502 rải rác cần kiểm tra app có bị restart không."*

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `sort file > file` → file **rỗng** | Shell mở `> file` (xóa nội dung) **trước khi** `sort` đọc file | Ghi ra file tạm rồi `mv`, hoặc `sort -o file file` |
| `rm -rf $DIR/*` xóa nhầm cả hệ thống | Biến `$DIR` rỗng → lệnh thành `rm -rf /*` | Trong script dùng `rm -rf "${DIR:?}"/*` — báo lỗi nếu biến rỗng (bài 06). Luôn `echo` lệnh trước khi chạy |
| `find . -name *.log` báo `paths must precede expression` | Không có nháy, shell mở rộng `*.log` thành nhiều tên file | `find . -name "*.log"` |
| Wildcard không khớp gì, lệnh nhận đúng chuỗi `*.txt` | Bash mặc định giữ nguyên mẫu nếu không có file khớp | `cat: '*.txt': No such file or directory` — kiểm tra bằng `ls` |
| `uniq -c` đếm sai, cùng một IP xuất hiện nhiều dòng | Quên `sort` trước `uniq` | `sort \| uniq -c` |
| `cut -d' ' -f3` lấy sai cột | Dữ liệu có nhiều dấu cách liền nhau | Dùng `awk '{print $3}'` |
| `sed -i` làm hỏng file cấu hình | Regex khớp nhiều hơn dự kiến | Chạy không `-i` trước; dùng `-i.bak`; kiểm tra bằng `diff` |
| `tail -f` ngừng hiện log sau nửa đêm | Log bị rotate, `-f` vẫn theo file cũ (đã đổi tên) | Dùng `tail -F` |
| `xargs` lỗi với tên file có dấu cách | xargs tách theo khoảng trắng | `find ... -print0 \| xargs -0 ...` |
| `sudo echo "..." > /etc/file` → `Permission denied` | Redirect do shell của user thường thực hiện | `echo "..." \| sudo tee /etc/file` |
| `grep "1.2.3.4"` khớp cả `1x2y3z4` | `.` trong regex là "ký tự bất kỳ" | `grep -F "1.2.3.4"` (tìm chuỗi cố định) hoặc escape `1\.2\.3\.4` |
| Mở log 10GB bằng `cat` hoặc editor → treo terminal | Đổ toàn bộ file ra màn hình / vào RAM | Dùng `less`, `tail`, `grep` |
| Kẹt trong vim | — | `Esc` → `:q!` → `Enter` |
| Nhấn `Ctrl+Z` tưởng thoát chương trình | `Ctrl+Z` **tạm dừng** process và đẩy xuống nền, không thoát | `fg` để quay lại; `Ctrl+C` mới là dừng. Học kỹ ở [bài 04](04-processes-systemd.md) |

---

## 12. Đọc thông báo lỗi và xử lý

### 12.1. Phân biệt stdout và stderr khi debug

Khi một lệnh in ra nhiều thứ, câu hỏi đầu tiên: **dòng nào là lỗi?** Cách kiểm tra:

```bash
lệnh > /dev/null       # chỉ còn thấy stderr
lệnh 2> /dev/null      # chỉ còn thấy stdout
```

Đây cũng là lý do khi chạy app trong Docker hay systemd, bạn cần biết app ghi log ra stdout hay stderr — cả hai đều được thu thập, nhưng có thể được xử lý khác nhau.

### 12.2. Những thông báo lỗi hay gặp với nhóm lệnh này

| Thông báo | Ý nghĩa | Hướng xử lý |
|---|---|---|
| `cp: -r not specified; omitting directory 'x'` | Sao chép thư mục mà thiếu `-r` | Thêm `-r` |
| `rm: cannot remove 'x': Is a directory` | Xóa thư mục bằng `rm` không `-r` | `rmdir` (nếu rỗng) hoặc `rm -r` |
| `rmdir: failed to remove 'x': Directory not empty` | Thư mục còn file | Xem bằng `ls -A x` trước khi quyết định |
| `find: '/var/log/private': Permission denied` | User thường không vào được thư mục đó | Thêm `2>/dev/null` nếu không quan trọng, hoặc dùng `sudo` |
| `grep: x: binary file matches` | File chứa dữ liệu nhị phân (hoặc log có ký tự lạ) | `grep -a` để coi như văn bản |
| `bash: /usr/bin/rm: Argument list too long` | Wildcard mở rộng thành quá nhiều file | `find ... -delete` hoặc `find ... -print0 \| xargs -0 rm` |
| `sed: -e expression #1, char 15: unknown option to 's'` | Chuỗi chứa `/` trùng với dấu phân cách | Đổi dấu phân cách: `s\|a/b\|c/d\|` |
| `awk: line 1: syntax error at or near` | Thường do dùng nháy kép, Bash đã thay `$1` | Dùng nháy đơn bao chương trình awk |

### 12.3. Đọc log hiệu quả: từ rộng đến hẹp

Quy trình chung khi đứng trước một file log lạ:

1. **Kích thước và khoảng thời gian:** `ls -lh`, `head -1`, `tail -1`.
2. **Định dạng:** `head -5` — xác định cột nào là thời gian, level, message.
3. **Tổng quan:** đếm theo level/status (`awk | sort | uniq -c`).
4. **Thu hẹp:** lọc theo thời điểm sự cố (`grep "09:1[0-9]:"`), theo level (`grep ERROR`).
5. **Ngữ cảnh:** `grep -A/-B` quanh dòng lỗi, tìm `Caused by:`.
6. **Ghi lại** phát hiện vào `troubleshooting-journal.md`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. stdin, stdout, stderr là gì? Vì sao cần tách stdout và stderr thành hai kênh?
2. Khi gõ `rm *.log`, chương trình `rm` nhận được gì? Ai xử lý dấu `*`?
3. `cp` và `mv` có hỏi trước khi ghi đè file không? Làm sao để chúng hỏi?
4. Khác nhau giữa `tail -f` và `tail -F`? Khi nào bắt buộc dùng `-F`?
5. Vì sao `less` mở được file log 10GB mà `nano` thì không nên?
6. Viết lệnh `find` tìm file `.log` trong `/var/log` lớn hơn 50MB và sửa trong vòng 1 ngày qua.
7. Vì sao `uniq -c` cần `sort` đứng trước?
8. `lệnh > file 2>&1` và `lệnh 2>&1 > file` khác nhau thế nào?
9. Vì sao `sudo echo "x" > /etc/hosts` thất bại? Cách đúng là gì?
10. Khi nào dùng `cut`, khi nào nên dùng `awk`?
11. Vì sao chương trình `awk` luôn được bao trong nháy đơn?
12. Trước khi chạy `sed -i` trên file cấu hình production, bạn làm những bước gì?
13. Bạn được mở vào vim và lỡ gõ linh tinh. Làm sao thoát mà không lưu?
14. Trong log Java, dòng nào thường chỉ ra nguyên nhân gốc của exception?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/02-solutions.md](solutions/02-solutions.md) — chỉ mở sau khi đã tự làm và ghi câu trả lời.

Dùng file `access.log` đã sinh ở lab.

**Bài 1 — Byte.** Tính tổng dung lượng (cột `$10`) Nginx đã trả về, đổi ra MB. URL nào trả về nhiều byte nhất tính tổng?

**Bài 2 — Khung giờ sự cố.** Đếm số lỗi 5xx theo từng giờ. Giờ nào nhiều lỗi 5xx nhất? Viết bằng **một** pipeline.

**Bài 3 — Danh sách chặn.** Tạo file `blocklist.txt` chứa các IP có hơn 100 request tới URL trả về 404, mỗi IP một dòng, không có số đếm đi kèm. Sau đó sinh từ file này các dòng cấu hình Nginx dạng `deny 198.51.100.23;` bằng `sed` hoặc `awk`.

**Bài 4 — User agent.** Liệt kê các user agent và số request của mỗi loại. Lưu ý: user agent chứa dấu cách nên `awk '{print $12}'` sẽ không đủ. Gợi ý: dùng `awk -F'"'` (tách theo dấu nháy kép) và tự tìm xem user agent nằm ở cột số mấy.

**Bài 5 — Dọn dẹp an toàn.** Trong `~/devops-lab`, tạo 20 file `old-N.log` (N = 1..20) bằng một lệnh. Dùng `touch -d "10 days ago"` để làm 10 file trong số đó "cũ". Viết lệnh `find` liệt kê đúng 10 file cũ, sau đó mới xóa chúng. Ghi lại lý do vì sao bạn chạy lệnh liệt kê trước.

**Bài 6 — Cấu hình.** Từ file `application.yml` ở mục 8, chỉ dùng `sed`: đổi port thành `8081` và đổi tên database `taskhub` thành `taskhub_dev`, giữ bản sao lưu, rồi dùng `diff` chứng minh chỉ đúng 2 dòng thay đổi.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Viết được pipeline "đếm và xếp hạng" mà không cần nhìn tài liệu.
- [ ] Giải thích được từng phần của `lệnh > file 2>&1` và vì sao thứ tự quan trọng.
- [ ] Tự đánh số cột của một dòng access log Nginx.
- [ ] Không bao giờ chạy `rm -r`, `find -delete`, `sed -i` mà không kiểm tra trước.
- [ ] Mở, sửa, lưu file bằng `nano`; thoát được `vim` khi lỡ bị mở vào.
- [ ] Làm xong Bài tập 2, 3, 4 không cần xem lời giải.
- [ ] Báo cáo `report.md` có kết luận bằng lời, không chỉ có số liệu.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [Nginx — ngx_http_log_module](https://nginx.org/en/docs/http/ngx_http_log_module.html) | Định dạng log `combined` | 2026-10-31 |
| [Linux Journey — Grasshopper: Text-Fu, Advanced Text-Fu](https://labex.io/linuxjourney) | Ôn lại redirect, pipe, xử lý văn bản | 2026-10-31 |
| [MIT Missing Semester 2026 — Introduction to the Shell, Command-line Environment](https://missing.csail.mit.edu/) | Pipe, redirect, tư duy dùng shell | 2026-10-31 |
| `man find`, `man grep`, `man awk`, `man sed` (chạy trên máy) | Tra cứu đầy đủ tham số | — |
