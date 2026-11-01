# 06. Bash scripting & biến môi trường

> ⏱️ ~4 giờ · Mức độ: 🟥 Bắt buộc · Kiến thức cần có trước: [01](01-linux-architecture-filesystem.md), [02](02-essential-commands-text.md), [03](03-permissions-users-groups.md), [04](04-processes-systemd.md)
> Môi trường: `[WSL]` Ubuntu 24.04 (Bash 5.2), `[Sandbox]` container `ubuntu:22.04` (Bash 5.1)

## Mục lục

1. [Mục tiêu bài học](#1-mục-tiêu-bài-học)
2. [Tại sao DevOps Engineer cần kiến thức này?](#2-tại-sao-devops-engineer-cần-kiến-thức-này)
3. [Kiến thức nền tảng cần hiểu](#3-kiến-thức-nền-tảng-cần-hiểu)
4. [Giải thích chi tiết](#4-giải-thích-chi-tiết)
5. [Ví dụ thực tế](#5-ví-dụ-thực-tế)
6. [Sơ đồ luồng hoạt động](#6-sơ-đồ-luồng-hoạt-động)
7. [Các câu lệnh cần biết](#7-các-câu-lệnh-cần-biết)
8. [Giải thích câu lệnh và tham số](#8-giải-thích-câu-lệnh-và-tham-số)
9. [Bài thực hành từng bước](#9-bài-thực-hành-từng-bước)
10. [Kết quả mong đợi](#10-kết-quả-mong-đợi)
11. [Các lỗi thường gặp](#11-các-lỗi-thường-gặp)
12. [Đọc log và xử lý lỗi](#12-đọc-log-và-xử-lý-lỗi)
13. [Câu hỏi kiểm tra kiến thức](#13-câu-hỏi-kiểm-tra-kiến-thức)
14. [Bài tập tự làm](#14-bài-tập-tự-làm)
15. [Tiêu chí đánh giá đã hiểu bài](#15-tiêu-chí-đánh-giá-đã-hiểu-bài)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Mục tiêu bài học

Sau bài này, bạn có thể:

- Viết một script Bash có cấu trúc rõ ràng: shebang, biến, điều kiện, vòng lặp, hàm.
- **Quote biến đúng cách** và giải thích được vì sao quote sai làm script hỏng (hoặc xóa nhầm dữ liệu).
- Dùng **exit code**, `&&`, `||`, `set -euo pipefail` và `trap` để script **dừng an toàn khi có lỗi** thay vì chạy tiếp trong trạng thái sai.
- Phân biệt **biến shell** và **biến môi trường**, hiểu `PATH`, `export`, `~/.bashrc`, file `.env`.
- Debug script bằng `bash -x` và ShellCheck.

---

## 2. Tại sao DevOps Engineer cần kiến thức này?

Bash là "keo dán" của hạ tầng. Bạn sẽ gặp nó ở khắp nơi, kể cả khi công ty dùng công cụ hiện đại:

| Nơi gặp Bash | Ví dụ |
|---|---|
| CI/CD pipeline | Mỗi bước `run:` trong GitHub Actions là một đoạn Bash |
| Dockerfile | `RUN apt-get update && apt-get install -y ...` là lệnh shell |
| EC2 user data | Script chạy lần đầu khi máy chủ khởi động |
| Cron job | Backup database, dọn log, healthcheck |
| Entrypoint của container | Script chuẩn bị cấu hình trước khi chạy app |
| Vận hành hằng ngày | Tự động hóa việc lặp lại: kiểm tra 10 server, xoay vòng backup |

Một script viết ẩu có thể gây hậu quả nghiêm trọng. Ví dụ kinh điển: `rm -rf "$BACKUP_DIR/"*` khi biến `BACKUP_DIR` rỗng → thành `rm -rf /*`. Bài này dạy bạn viết script **an toàn trước, tiện lợi sau**.

---

## 3. Kiến thức nền tảng cần hiểu

### 3.1. Script là gì?

**Script** (kịch bản) là một file văn bản chứa các lệnh bạn vẫn gõ trong terminal, được chạy tuần tự từ trên xuống. Không cần biên dịch như Java — Bash đọc và chạy từng dòng.

### 3.2. Nhắc lại từ các bài trước

| Kiến thức | Học ở | Dùng trong bài này |
|---|---|---|
| Exit code (`0` = thành công) | [Bài 01](01-linux-architecture-filesystem.md#echo---exit-code) | Điều kiện `if`, `&&`, `set -e` |
| Pipe, redirect `>`, `>>`, `2>&1`, `grep`, `awk` | [Bài 02](02-essential-commands-text.md) | Xử lý dữ liệu trong script |
| Quyền thực thi `x`, `chmod +x` | [Bài 03](03-permissions-users-groups.md) | Chạy `./script.sh` |
| Process cha – con, PID | [Bài 04](04-processes-systemd.md) | Biến môi trường được kế thừa từ cha sang con |

### 3.3. Shell đọc một dòng lệnh như thế nào?

Đây là điều quan trọng nhất để hiểu quoting. Trước khi chạy lệnh, Bash **biến đổi** dòng lệnh theo các bước (rút gọn):

1. Thay biến: `$NAME` → giá trị.
2. Thay kết quả lệnh: `$(date)` → chuỗi ngày giờ.
3. **Tách từ** (word splitting): kết quả **không nằm trong nháy kép** bị cắt ở dấu cách, tab, xuống dòng.
4. **Mở rộng ký tự đại diện** (globbing): `*.log` → danh sách file khớp.
5. Chạy lệnh với danh sách tham số đã có.

Bước 3 và 4 là nguồn gốc của phần lớn lỗi script. Dấu nháy kép `"..."` **chặn** bước 3 và 4, nhưng vẫn cho bước 1 và 2.

---

## 4. Giải thích chi tiết

### 4.1. 🟥 Shebang và cách chạy script

Dòng đầu tiên của script:

```bash
#!/usr/bin/env bash
```

Gọi là **shebang**. Khi bạn chạy `./script.sh`, kernel đọc dòng này để biết **chương trình nào sẽ thông dịch** file. `/usr/bin/env bash` tìm `bash` trong `PATH` — chạy được cả trên hệ thống đặt bash ở chỗ khác. `#!/bin/bash` cũng phổ biến và dùng tốt trên Ubuntu.

Hai cách chạy:

| Cách | Cần quyền `x`? | Dùng shebang? | Ghi chú |
|---|---|---|---|
| `bash script.sh` | Không | Không — bạn chỉ định `bash` trực tiếp | Tiện khi thử nghiệm |
| `./script.sh` | **Có** (`chmod +x script.sh`) | Có | Cách dùng chuẩn cho cron, systemd |

> ⚠️ `sh script.sh` **không** giống `bash script.sh`. Trên Ubuntu, `sh` là **dash** — một shell tối giản, không hiểu `[[ ]]`, mảng, `pipefail`... Script viết cho Bash chạy bằng `sh` sẽ báo lỗi khó hiểu.

### 4.2. 🟥 Biến

```bash
name="taskhub"          # gán: KHÔNG có dấu cách quanh dấu =
echo "$name"            # dùng: thêm dấu $
echo "${name}-v1"       # dùng ngoặc nhọn khi dính với chữ khác
```

- `name = "taskhub"` (có dấu cách) → Bash hiểu là **chạy lệnh** tên `name` với tham số `=` và `taskhub` → lỗi `name: command not found`.
- Quy ước: biến trong script viết thường hoặc `snake_case`; biến môi trường/hằng số viết HOA (`BACKUP_DIR`).

**Giá trị mặc định** (🟥 dùng rất nhiều):

| Cú pháp | Nghĩa |
|---|---|
| `${VAR:-mặc_định}` | Nếu `VAR` rỗng hoặc chưa đặt → dùng `mặc_định` (không thay đổi `VAR`) |
| `${VAR:=mặc_định}` | Như trên nhưng **gán** luôn vào `VAR` |
| `${VAR:?thông báo lỗi}` | Nếu `VAR` rỗng → in lỗi và **dừng script** |

```bash
KEEP="${KEEP:-7}"                                  # mặc định giữ 7 bản backup
SOURCE_DIR="${1:?Cần truyền thư mục nguồn}"        # bắt buộc có tham số 1
```

### 4.3. 🟥 Quoting — nháy kép, nháy đơn, không nháy

| Cách viết | Thay biến `$x`? | Thay `$(...)`? | Tách từ & glob? | Dùng khi |
|---|---|---|---|---|
| `"..."` nháy kép | Có | Có | **Không** | **Mặc định cho mọi biến** |
| `'...'` nháy đơn | Không | Không | Không | Chuỗi cố định, có ký tự `$` (ví dụ chương trình `awk`) |
| Không nháy | Có | Có | **Có** | Hầu như không bao giờ với biến |

Ví dụ thấy rõ sự khác biệt `[Sandbox]`:

```bash
file="bao cao.txt"
touch "$file"
ls -l $file        # KHÔNG nháy
ls -l "$file"      # CÓ nháy
```

```text
ls: cannot access 'bao': No such file or directory
ls: cannot access 'cao.txt': No such file or directory
-rw-r--r-- 1 root root 0 Oct 31 10:00 'bao cao.txt'
```

Không có nháy, Bash tách `bao cao.txt` thành **hai** tham số. Với `ls` chỉ là báo lỗi; với `rm` thì có thể xóa nhầm file `bao` và `cao.txt` nếu chúng tồn tại.

> **Quy tắc vàng:** luôn viết `"$var"`, `"$(lệnh)"`, `"$@"`. Chỉ bỏ nháy khi bạn **cố ý** muốn tách từ và giải thích được lý do.

### 4.4. 🟥 Command substitution và số học

```bash
today="$(date +%F)"                 # chạy lệnh, lấy kết quả làm giá trị
file_count="$(ls /etc | wc -l)"
echo "Hôm nay $today, /etc có $file_count mục"

a=7; b=3
echo "$(( a + b )) $(( a * b )) $(( a / b )) $(( a % b ))"
```

```text
Hôm nay 2026-10-31, /etc có 104 mục
10 21 2 1
```

- `$(...)` = **command substitution** (thay thế bằng kết quả lệnh). Cách cũ dùng dấu backtick `` `...` `` — tránh dùng vì khó đọc và khó lồng nhau.
- `$(( ... ))` = **arithmetic expansion** (tính toán số nguyên). Bên trong không cần `$` trước tên biến. Bash **chỉ tính số nguyên**: `7 / 3 = 2`.

### 4.5. 🟥 Tham số dòng lệnh

Chạy `./deploy.sh staging v1.2.0 "ghi chú dài"`:

| Biến | Giá trị | Ý nghĩa |
|---|---|---|
| `$0` | `./deploy.sh` | Tên script |
| `$1`, `$2`, `$3` | `staging`, `v1.2.0`, `ghi chú dài` | Tham số thứ 1, 2, 3 |
| `$#` | `3` | Số lượng tham số |
| `"$@"` | 3 phần tử riêng biệt | **Tất cả tham số, giữ nguyên ranh giới** — dùng cái này |
| `$*` / `"$*"` | Gộp thành một chuỗi | Hiếm khi cần |
| `$?` | Exit code của lệnh vừa chạy | |
| `$$` | PID của chính script | Đã gặp ở bài 01 |

`"$@"` có nháy giữ `"ghi chú dài"` là **một** tham số. `$@` không nháy sẽ tách thành `ghi`, `chú`, `dài`.

### 4.6. 🟥 Điều kiện: `if`, `[[ ]]`, `test`

`if` trong Bash **không** kiểm tra đúng/sai như Java. Nó **chạy một lệnh và xem exit code**: `0` → nhánh `then`, khác `0` → nhánh `else`.

```bash
if grep -q "ERROR" app.log; then
    echo "Có lỗi trong log"
fi
```

`[[ ... ]]` là một lệnh đặc biệt chuyên để kiểm tra điều kiện:

| Loại | Biểu thức | Đúng khi |
|---|---|---|
| File | `[[ -e path ]]` | Tồn tại (bất kỳ loại nào) |
| | `[[ -f path ]]` | Là **file** thường |
| | `[[ -d path ]]` | Là **thư mục** |
| | `[[ -x path ]]` | Có quyền **thực thi** |
| | `[[ -r path ]]` / `-w` | Đọc được / ghi được |
| | `[[ -s path ]]` | Tồn tại và **không rỗng** (size > 0) |
| Chuỗi | `[[ -z "$s" ]]` | Chuỗi **rỗng** (zero length) |
| | `[[ -n "$s" ]]` | Chuỗi **không rỗng** |
| | `[[ "$a" == "$b" ]]` / `!=` | Bằng / khác |
| | `[[ "$f" == *.log ]]` | Khớp mẫu (pattern) |
| Số | `[[ $a -eq $b ]]` | Bằng (**eq**ual) |
| | `-ne`, `-lt`, `-le`, `-gt`, `-ge` | Khác, nhỏ hơn, ≤, lớn hơn, ≥ |
| Kết hợp | `&&`, `\|\|`, `!` | Và, hoặc, phủ định |

So sánh số còn có cách viết dễ đọc hơn: `(( a > b ))`.

> ⚠️ `[[ $a > $b ]]` so sánh **chuỗi** theo thứ tự từ điển, không phải số: `"10" > "9"` là **sai** vì ký tự `1` đứng trước `9`. So sánh số dùng `-gt` hoặc `(( ))`.

`[ ... ]` (một ngoặc) là lệnh `test` cũ, có trong mọi shell. `[[ ]]` an toàn hơn (ít bị tách từ) — trong script Bash, dùng `[[ ]]`.

```bash
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Không tìm thấy thư mục: $SOURCE_DIR" >&2
    exit 1
elif [[ ! -r "$SOURCE_DIR" ]]; then
    echo "Không có quyền đọc: $SOURCE_DIR" >&2
    exit 1
else
    echo "OK"
fi
```

`>&2` = ghi thông báo vào **stderr** (luồng lỗi) thay vì stdout. Thông báo lỗi nên đi vào stderr để không lẫn với dữ liệu đầu ra.

### 4.7. 🟥 `case` — rẽ nhiều nhánh theo giá trị

Rất hay dùng để xử lý lệnh con kiểu `./app.sh start|stop|status`:

```bash
case "$1" in
    start)   echo "Đang khởi động..." ;;
    stop)    echo "Đang dừng..." ;;
    status)  echo "Trạng thái..." ;;
    *)       echo "Cách dùng: $0 {start|stop|status}" >&2; exit 2 ;;
esac
```

### 4.8. 🟥 Vòng lặp

```bash
# for qua danh sách
for env in dev staging prod; do
    echo "Kiểm tra môi trường: $env"
done

# for qua file (glob) — KHÔNG dùng $(ls)
for f in /var/log/*.log; do
    [[ -e "$f" ]] || continue          # nếu không có file nào khớp, bỏ qua
    echo "$f: $(wc -l < "$f") dòng"
done

# for kiểu C
for (( i = 1; i <= 3; i++ )); do echo "Lần $i"; done

# while: lặp khi điều kiện còn đúng
count=0
while (( count < 3 )); do
    count=$(( count + 1 ))
done

# until: lặp cho đến khi điều kiện đúng — chờ dịch vụ sẵn sàng
until curl -fs http://localhost:8080/actuator/health > /dev/null; do
    echo "Chờ app khởi động..."
    sleep 2
done
```

`break` thoát vòng lặp, `continue` sang lần lặp tiếp theo.

> Vòng `until curl ...` ở trên là mẫu bạn sẽ dùng lại nhiều lần: chờ PostgreSQL sẵn sàng, chờ app khởi động sau khi deploy. Trong thực tế nên có **giới hạn số lần thử** để không chờ vô hạn (Bài tập 3).

### 4.9. 🟥 Đọc file từng dòng

```bash
while IFS= read -r line; do
    echo "Server: $line"
done < servers.txt
```

| Thành phần | Tác dụng |
|---|---|
| `< servers.txt` | Đưa file vào stdin của **cả vòng lặp** |
| `read -r` | Đọc một dòng; `-r` giữ nguyên dấu `\` (không coi là ký tự thoát) |
| `IFS=` | Không cắt khoảng trắng đầu/cuối dòng |

> ⚠️ Không dùng `for line in $(cat file)` — nó tách theo **dấu cách**, không theo dòng.

### 4.10. 🟥 Hàm, `local`, `return` và `exit`

```bash
log() {
    local level="$1"; shift              # lấy tham số 1, dịch các tham số còn lại sang trái
    echo "$(date '+%F %T') [$level] $*"
}

is_port_open() {
    local port="$1"
    ss -ltn | grep -q ":${port} "        # ss -ltn: liệt kê port TCP đang lắng nghe (học ở bài 07); exit code của grep thành exit code của hàm
}

log INFO "Bắt đầu kiểm tra"
if is_port_open 8080; then
    log INFO "Port 8080 đang mở"
else
    log WARN "Không có gì lắng nghe ở port 8080"
fi
```

```text
2026-10-31 10:15:02 [INFO] Bắt đầu kiểm tra
2026-10-31 10:15:02 [WARN] Không có gì lắng nghe ở port 8080
```

- Hàm nhận tham số giống script: `$1`, `$2`, `"$@"` — của **hàm**, không phải của script.
- `local` giới hạn biến trong hàm. Không có `local`, biến trong hàm là **biến toàn cục** và có thể ghi đè biến cùng tên bên ngoài.
- `return N`: thoát **hàm** với exit code N (0–255). Hàm không có `return` trả về exit code của lệnh cuối cùng.
- `exit N`: thoát **cả script**.
- Hàm Bash không "trả về giá trị" như Java. Muốn lấy dữ liệu, cho hàm `echo` ra rồi bắt bằng `result="$(ten_ham)"`.

### 4.11. 🟥 `&&` và `||`

```bash
mkdir -p /tmp/build && cd /tmp/build           # chỉ cd nếu mkdir thành công
cd /khong-ton-tai || { echo "Lỗi cd" >&2; exit 1; }   # nếu cd thất bại thì thoát
```

- `A && B`: chạy B **chỉ khi** A thành công.
- `A || B`: chạy B **chỉ khi** A thất bại.

> ⚠️ `A && B || C` **không phải** if-else: nếu A đúng nhưng B thất bại, C vẫn chạy. Cần if-else thật thì viết `if`.

### 4.12. 🟥 Chế độ an toàn: `set -euo pipefail`

Mặc định Bash **chạy tiếp** sau lỗi. Script backup có thể thất bại ở bước nén nhưng vẫn chạy bước "xóa bản cũ" → mất hết backup. Đặt dòng này ngay sau shebang:

```bash
set -euo pipefail
```

| Cờ | Tên | Tác dụng |
|---|---|---|
| `-e` | errexit | Dừng script ngay khi một lệnh trả về exit code khác 0 |
| `-u` | nounset | Dùng biến **chưa đặt** → báo lỗi và dừng (thay vì âm thầm coi là rỗng) |
| `-o pipefail` | | Exit code của pipeline = lệnh **cuối cùng thất bại**, không chỉ lệnh cuối pipeline |

Ví dụ `pipefail`: `false | true` → không có pipefail: exit code `0` (của `true`); có pipefail: exit code `1`.

**Cạm bẫy của `set -e`** — cần biết để không bị bất ngờ:

| Tình huống | Hành vi | Cách xử lý |
|---|---|---|
| Lệnh thất bại nằm trong điều kiện `if`, `while`, hoặc trước `&&`/`\|\|` | **Không** dừng script (vì bạn đã chủ động xử lý) | Đúng mong muốn |
| `grep` không tìm thấy gì | grep trả về `1` → script **dừng** | `grep ... \|\| true` nếu "không tìm thấy" là bình thường |
| `local x="$(lệnh_lỗi)"` | **Không** dừng — `local` luôn trả về 0, che mất lỗi | Tách 2 dòng: `local x` rồi `x="$(lệnh)"` |
| `(( count++ ))` khi `count=0` | Biểu thức bằng 0 → exit code 1 → script **dừng** | Dùng `count=$(( count + 1 ))` |
| Biến môi trường tùy chọn với `-u` | `$OPTIONAL` chưa đặt → dừng | Dùng `"${OPTIONAL:-}"` |

`set -e` không thay thế việc kiểm tra lỗi cẩn thận, nhưng là **lưới an toàn** tốt.

### 4.13. 🟥 `trap` — dọn dẹp khi script kết thúc

```bash
tmp_dir="$(mktemp -d)"                 # tạo thư mục tạm với tên ngẫu nhiên
cleanup() {
    rm -rf -- "$tmp_dir"
}
trap cleanup EXIT                      # chạy cleanup khi script thoát, dù thành công hay lỗi
```

`trap <lệnh> EXIT` đảm bảo file tạm, file khóa… được xóa kể cả khi `set -e` làm script dừng giữa chừng. Có thể bắt thêm tín hiệu: `trap cleanup EXIT INT TERM` (Ctrl+C và `kill`, xem [bài 04](04-processes-systemd.md)).

### 4.14. 🟨 Here-document và `read`

**Here-doc** — viết một khối văn bản nhiều dòng làm stdin, rất hay dùng để sinh file cấu hình:

```bash
APP_PORT=8080
cat > app.conf <<EOF
port=${APP_PORT}
created=$(date +%F)
EOF

cat > note.txt <<'EOF'
Giữ nguyên $APP_PORT, không thay biến
EOF
```

`<<EOF` thay biến bên trong; `<<'EOF'` (có nháy) giữ nguyên văn bản.

**`read`** — hỏi người dùng (chỉ dùng cho script chạy tay, **không** dùng trong cron/CI vì không có người trả lời):

```bash
read -r -p "Xóa backup cũ? (y/N) " answer
[[ "$answer" == "y" ]] || { echo "Hủy"; exit 0; }
```

### 4.15. 🟥 Biến shell và biến môi trường

Đây là khái niệm bạn sẽ dùng lại trong Docker, Spring Boot, GitHub Actions, Kubernetes.

- **Biến shell**: chỉ tồn tại trong shell hiện tại.
- **Biến môi trường** (environment variable): biến được **truyền xuống mọi process con** mà shell khởi chạy. Tạo bằng `export`.

```bash
APP_ENV=dev                         # biến shell
bash -c 'echo "con thấy: [$APP_ENV]"'
export APP_ENV                      # biến thành biến môi trường
bash -c 'echo "con thấy: [$APP_ENV]"'
```

```text
con thấy: []
con thấy: [dev]
```

Quy tắc kế thừa: **cha truyền cho con, con không bao giờ sửa được biến của cha**. Vì vậy `./set-env.sh` (chạy trong process con) không thể đặt biến cho terminal của bạn — muốn vậy phải `source set-env.sh` (chạy trong chính shell hiện tại).

Đặt biến **chỉ cho một lệnh**:

```bash
APP_ENV=prod ./run.sh               # chỉ run.sh thấy APP_ENV=prod
```

**`PATH`** là biến môi trường chứa danh sách thư mục, ngăn cách bởi `:`, nơi shell tìm chương trình:

```bash
echo "$PATH"
```

```text
/home/phuong/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Thêm thư mục script riêng vào `PATH`:

```bash
mkdir -p ~/bin
export PATH="$HOME/bin:$PATH"       # thêm vào ĐẦU, giữ nguyên phần cũ
```

> ⚠️ `export PATH=~/bin` (quên `:$PATH`) sẽ **xóa** toàn bộ PATH cũ → mọi lệnh `ls`, `cat` báo `command not found` trong terminal đó. Mở terminal mới là hết, vì bạn chưa lưu vào file.

**Lưu biến lâu dài** — file nào được đọc khi nào (mức đủ dùng):

| File | Đọc khi | Dùng cho |
|---|---|---|
| `~/.bashrc` | Mỗi lần mở shell tương tác (terminal mới) | Alias, `PATH` cá nhân, prompt. **Nơi bạn sửa nhiều nhất** |
| `~/.profile` | Khi đăng nhập (login shell, SSH vào server) | Trên Ubuntu, file này mặc định gọi `~/.bashrc` |
| `/etc/environment` | Khi bất kỳ user nào đăng nhập | Biến toàn hệ thống. Chỉ chứa dòng `KEY=value` — **không phải script**, không dùng `$VAR` hay `export` |
| `/etc/profile.d/*.sh` | Login shell của mọi user | Script cấu hình toàn hệ thống |

Sau khi sửa `~/.bashrc`: chạy `source ~/.bashrc` hoặc mở terminal mới.

> ⚠️ **Cron và systemd không đọc `~/.bashrc`**. Biến bạn đặt ở đó sẽ không có khi script chạy bằng cron — xem [bài 08](08-cron-scheduling.md).

### 4.16. 🟥 File `.env` và secrets

Ứng dụng thường nhận cấu hình qua biến môi trường. Để khỏi gõ lại, người ta gom vào file `.env`:

```bash
# .env — KHÔNG commit file này
DB_HOST=localhost
DB_USER=taskhub
DB_PASSWORD=doi-mat-khau-nay
```

Nạp vào shell:

```bash
set -a              # tự động export mọi biến được gán sau đây
source .env
set +a
```

Quy tắc bắt buộc:

- Thêm `.env` vào `.gitignore` **trước** khi tạo file.
- Commit file mẫu `.env.example` chứa tên biến với giá trị giả.
- Một khi secret đã lên GitHub, coi như **đã lộ** — phải đổi mật khẩu, xóa commit là không đủ.

**Báo trước cho các module sau:**

- Docker Compose đọc file `.env` tự động (Module 04).
- Spring Boot ánh xạ biến môi trường sang thuộc tính cấu hình: `SPRING_DATASOURCE_URL` → `spring.datasource.url`. Nhờ vậy cùng một image chạy được ở dev và prod, chỉ khác biến môi trường.
- GitHub Actions có Secrets, AWS có Parameter Store/Secrets Manager — cùng ý tưởng, an toàn hơn file `.env`.

### 4.17. 🟥 Debug script

| Cách | Dùng khi |
|---|---|
| `bash -x script.sh` | Chạy cả script, in từng lệnh **sau khi đã thay biến**, mỗi dòng có dấu `+` |
| `set -x` … `set +x` trong script | Chỉ theo dõi một đoạn |
| `bash -n script.sh` | Chỉ kiểm tra cú pháp, không chạy |
| `shellcheck script.sh` | Phân tích tĩnh, phát hiện lỗi quote, lỗi logic phổ biến |

```bash
bash -x ./greet.sh "Phương"
```

```text
+ name=Phương
+ echo 'Xin chào Phương'
Xin chào Phương
```

`bash -x` cho bạn thấy **giá trị thật** mà Bash dùng — cách nhanh nhất để phát hiện biến rỗng hoặc bị tách từ.

**ShellCheck** là công cụ kiểm tra script miễn phí, mã nguồn mở. Thử ngay trên trình duyệt tại [shellcheck.net](https://www.shellcheck.net/), hoặc cài vào WSL (bạn tự quyết định cài):

```bash
sudo apt install shellcheck
shellcheck backup.sh
```

```text
In backup.sh line 12:
rm -rf $BACKUP_DIR/*
       ^---------^ SC2086 (info): Double quote to prevent globbing and word splitting.
```

Mỗi cảnh báo có mã `SCxxxx` — tra mã trên trang ShellCheck để đọc giải thích chi tiết. Tập thói quen: **mọi script trước khi commit phải qua ShellCheck không cảnh báo**.

---

## 5. Ví dụ thực tế

### Ví dụ 1: Script deploy trong CI thất bại âm thầm

Một pipeline có bước:

```bash
./mvnw package
cp target/app.jar /opt/taskhub/
systemctl restart taskhub
```

Không có `set -e`: nếu build thất bại, `cp` copy file **jar cũ** (nếu còn) và restart — pipeline báo xanh dù code mới không được deploy. Với `set -euo pipefail`, bước build lỗi → script dừng → pipeline báo đỏ đúng chỗ. (GitHub Actions mặc định chạy `bash -e` cho mỗi bước `run:` — bạn sẽ xác minh điều này ở Module 05.)

### Ví dụ 2: Biến rỗng và `rm`

```bash
BACKUP_DIR=$(cat /etc/backup-path)    # file không tồn tại → biến rỗng
rm -rf $BACKUP_DIR/*                   # → rm -rf /*
```

Ba lớp bảo vệ học trong bài này:

```bash
set -euo pipefail                                  # cat lỗi → dừng ngay
BACKUP_DIR="${BACKUP_DIR:?BACKUP_DIR chưa đặt}"    # rỗng → dừng
rm -rf -- "${BACKUP_DIR:?}/"*                      # thêm một lớp kiểm tra tại chỗ dùng
```

`--` báo cho `rm` "hết tùy chọn, phía sau là tên file" — tránh trường hợp tên file bắt đầu bằng `-`.

---

## 6. Sơ đồ luồng hoạt động

### 6.1. Bash xử lý một dòng lệnh

```text
 rm -rf $DIR/*            (DIR="my data")
        │
 (1) Thay biến            rm -rf my data/*
        │
 (2) Tách từ              rm │ -rf │ my │ data/*        ← 4 tham số!
        │
 (3) Glob                 rm │ -rf │ my │ data/a data/b
        │
 (4) Chạy                 xóa "my", "data/a", "data/b"   ← SAI

 rm -rf "$DIR"/*
 (1) → "my data"/*   (2) không tách trong nháy   (3) glob phần ngoài nháy
 (4) xóa "my data/a", "my data/b"                       ← ĐÚNG
```

### 6.2. Biến môi trường đi từ cha sang con

```text
 bash (terminal)            export DB_HOST=db.local
   │   APP_TMP=1            (biến shell — không truyền)
   │
   └─► ./run.sh             thấy DB_HOST, không thấy APP_TMP
         │
         └─► java -jar app.jar   thấy DB_HOST
                                 (Spring Boot đọc SPRING_* tương tự)

 Con sửa DB_HOST → chỉ ảnh hưởng con và cháu, KHÔNG ảnh hưởng terminal.
```

---

## 7. Các câu lệnh cần biết

| Lệnh / Cú pháp | Mục đích | Mức |
|---|---|---|
| `#!/usr/bin/env bash` | Shebang | 🟥 |
| `chmod +x`, `./script.sh`, `bash script.sh` | Chạy script | 🟥 |
| `"$var"`, `${var:-x}`, `${var:?msg}` | Dùng biến an toàn | 🟥 |
| `$(...)`, `$(( ... ))` | Lấy kết quả lệnh, tính toán | 🟥 |
| `$1 $# "$@" $? $$` | Tham số và biến đặc biệt | 🟥 |
| `if / [[ ]] / case` | Điều kiện | 🟥 |
| `for / while / until`, `while IFS= read -r` | Vòng lặp | 🟥 |
| `func() { local ...; }`, `return`, `exit` | Hàm | 🟥 |
| `set -euo pipefail` | Chế độ an toàn | 🟥 |
| `trap ... EXIT`, `mktemp` | Dọn dẹp, file tạm | 🟥 |
| `export`, `env`, `printenv`, `source` | Biến môi trường | 🟥 |
| `<<EOF`, `read -r -p` | Here-doc, nhập liệu | 🟨 |
| `bash -x`, `bash -n`, `shellcheck` | Debug | 🟥 |

---

## 8. Giải thích câu lệnh và tham số

### `env` và `printenv` — xem biến môi trường

```bash
printenv HOME USER SHELL
env | grep -i path
```

```text
/home/phuong
phuong
/bin/bash
PATH=/home/phuong/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

- `printenv TÊN`: in giá trị một biến môi trường (chỉ biến **đã export**).
- `env`: in toàn bộ. Cũng dùng để chạy lệnh với môi trường sửa đổi: `env -i bash -c 'echo $PATH'` chạy với môi trường **rỗng** — mô phỏng gần giống môi trường nghèo nàn của cron.
- `set` (không tham số): in mọi biến **kể cả biến shell và hàm** — dài, ít dùng.

### `source` (hoặc `.`)

```bash
source ~/.bashrc
. ./.env
```

Chạy file trong **shell hiện tại** (không tạo process con) → mọi biến, hàm, `cd` trong file có hiệu lực luôn ở terminal của bạn.

### `mktemp`

```bash
mktemp          # tạo file tạm
mktemp -d       # tạo thư mục tạm
```

```text
/tmp/tmp.k3Jd8sQ2Lp
/tmp/tmp.Wq0zR7nB1x
```

Tên ngẫu nhiên, không đụng nhau khi nhiều bản script chạy cùng lúc. Tốt hơn tự đặt `/tmp/myscript.tmp`.

### `shift`

```bash
set -- a b c        # giả lập tham số $1=a $2=b $3=c
shift
echo "$1 $#"
```

```text
b 2
```

Bỏ tham số đầu tiên, dịch các tham số còn lại sang trái. Dùng khi xử lý tham số từng cái một.

### `date` trong script

| Lệnh | Kết quả mẫu | Dùng cho |
|---|---|---|
| `date +%F` | `2026-10-31` | Tên file backup theo ngày |
| `date '+%F %T'` | `2026-10-31 10:15:02` | Timestamp trong log |
| `date +%Y%m%d-%H%M%S` | `20261031-101502` | Tên file không có dấu cách, sắp xếp đúng thứ tự |
| `date +%s` | `1793420102` | Số giây từ 1970 — tính thời gian chạy |

### Exit code đặc biệt bạn sẽ gặp

| Exit code | Nghĩa thường gặp |
|---|---|
| `0` | Thành công |
| `1` | Lỗi chung |
| `2` | Dùng sai cú pháp/tham số (nhiều công cụ dùng quy ước này) |
| `126` | Tìm thấy file nhưng **không thực thi được** (thiếu quyền `x`) |
| `127` | **Không tìm thấy lệnh** (`command not found`, sai `PATH`) |
| `128 + N` | Bị dừng bởi tín hiệu số N: `130` = Ctrl+C (SIGINT=2), `137` = bị `kill -9` (SIGKILL=9), `143` = SIGTERM (15) |

> Nhớ `137` — ở Module 04 và 09 bạn sẽ gặp container chết với exit code 137, thường do **hết bộ nhớ** (OOM killer gửi SIGKILL).

---

## 9. Bài thực hành từng bước

**Lab: Script backup thư mục có kiểm tra lỗi, log và xoay vòng** · `[WSL]` · ~90 phút

Mục tiêu: viết `backup.sh` nén một thư mục thành file `.tar.gz` có timestamp, ghi log, và chỉ giữ lại N bản mới nhất. Đây là tiền thân của script backup PostgreSQL ở Module 08.

### Bước 1 — Chuẩn bị dữ liệu thử

```bash
mkdir -p ~/devops-lab/01-linux/lab06/{data,backups}
cd ~/devops-lab/01-linux/lab06
echo "cấu hình A" > data/app.conf
echo "dữ liệu B" > "data/bao cao.txt"     # cố ý có dấu cách
ls -l data
```

### Bước 2 — Phiên bản đầu tiên (chưa an toàn)

Tạo `backup.sh` bằng editor (VS Code: `code backup.sh`, nhớ để xuống dòng **LF**):

```bash
#!/usr/bin/env bash
SOURCE_DIR=$1
DEST_DIR=$2
tar -czf $DEST_DIR/backup-$(date +%Y%m%d-%H%M%S).tar.gz $SOURCE_DIR
echo "Xong"
```

```bash
chmod +x backup.sh
./backup.sh data backups
./backup.sh data khong-ton-tai
echo "exit code: $?"
```

❓ Lần chạy thứ hai báo lỗi gì? Script vẫn in `Xong` không? Exit code là bao nhiêu? Vì sao điều này nguy hiểm khi chạy bằng cron?

### Bước 3 — Thêm chế độ an toàn và kiểm tra đầu vào

Viết lại:

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:?Cách dùng: $0 <thư-mục-nguồn> <thư-mục-đích>}"
DEST_DIR="${2:?Cách dùng: $0 <thư-mục-nguồn> <thư-mục-đích>}"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Lỗi: không tìm thấy thư mục nguồn '$SOURCE_DIR'" >&2
    exit 1
fi
mkdir -p "$DEST_DIR"

archive="${DEST_DIR}/backup-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$archive" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"
echo "Đã tạo $archive"
```

| Thành phần mới | Tác dụng |
|---|---|
| `${1:?...}` | Không truyền tham số → in cách dùng và dừng |
| `[[ ! -d ... ]]` | Kiểm tra nguồn trước khi làm gì |
| `-C "$(dirname ...)" "$(basename ...)"` | `tar` chuyển vào thư mục cha rồi nén tên thư mục → file nén không chứa đường dẫn tuyệt đối |

Chạy lại 3 trường hợp: không tham số, nguồn sai, đúng. Kiểm tra exit code mỗi lần.

### Bước 4 — Thêm hàm log có timestamp

Thêm vào sau `set -euo pipefail`:

```bash
LOG_FILE="${LOG_FILE:-$HOME/devops-lab/01-linux/lab06/backup.log}"

log() {
    local level="$1"; shift
    echo "$(date '+%F %T') [$level] $*" | tee -a "$LOG_FILE"
}
```

Thay các `echo` bằng `log INFO "..."` và `log ERROR "..."`. (Gợi ý: với lỗi, ghi vào stderr bằng cách thêm `>&2` sau `tee`.)

### Bước 5 — Xoay vòng, chỉ giữ N bản mới nhất

```bash
KEEP="${KEEP:-5}"

rotate() {
    local old
    # liệt kê file backup mới → cũ, bỏ qua KEEP file đầu, phần còn lại là file cần xóa
    old="$(ls -1t "$DEST_DIR"/backup-*.tar.gz 2>/dev/null | tail -n +$(( KEEP + 1 )))" || true
    if [[ -n "$old" ]]; then
        while IFS= read -r f; do
            rm -f -- "$f"
            log INFO "Đã xóa bản cũ: $f"
        done <<< "$old"
    fi
}
```

Gọi `rotate` ở cuối script, **sau khi** tạo backup thành công. `<<<` là **here-string**: đưa nội dung biến vào stdin.

> Dùng `ls` ở đây chấp nhận được vì tên file backup do chính script đặt, không có dấu cách. Với tên file bất kỳ, dùng `find` (Bài tập 4).

### Bước 6 — Kiểm thử xoay vòng

```bash
for i in 1 2 3 4 5 6 7; do KEEP=3 ./backup.sh data backups; sleep 1; done
ls -1 backups
cat backup.log | tail -8
```

### Bước 7 — Thêm `trap` và kiểm tra bằng ShellCheck

Thêm một `trap` ghi log khi script thất bại:

```bash
on_error() { log ERROR "Backup thất bại ở dòng $1"; }
trap 'on_error $LINENO' ERR
```

`ERR` được kích hoạt khi một lệnh lỗi làm `set -e` dừng script. `$LINENO` là số dòng hiện tại.

Thử làm hỏng: `chmod 000 backups` rồi chạy script → đọc log → `chmod 755 backups` để khôi phục.

Kiểm tra cú pháp và chất lượng:

```bash
bash -n backup.sh && echo "Cú pháp OK"
shellcheck backup.sh          # hoặc dán vào shellcheck.net
```

### Bước 8 — Commit

```bash
mkdir -p ~/devops-journey/week03
cp backup.sh ~/devops-journey/week03/
cd ~/devops-journey
git add week03/backup.sh
git commit -m "feat(linux): backup script with logging and rotation"
git push
```

---

## 10. Kết quả mong đợi

- Bước 2: lần chạy thứ hai `tar` báo lỗi `Cannot open: No such file or directory`, nhưng script **vẫn in `Xong`** và exit code là **0** (của `echo`, lệnh cuối). Cron/CI sẽ tưởng backup thành công → không ai biết backup đã hỏng nhiều ngày.
- Bước 3: không tham số → in dòng cách dùng, exit code `1`; nguồn sai → thông báo lỗi rõ ràng, exit code `1`; đúng → file `backup-YYYYMMDD-HHMMSS.tar.gz`.
- Kiểm tra nội dung backup: `tar -tzf backups/<file>` liệt kê `data/`, `data/app.conf`, `data/bao cao.txt` — đủ cả file có dấu cách.
- Bước 6: thư mục `backups` chỉ còn **3** file mới nhất; log có các dòng `Đã xóa bản cũ`.
- Bước 7: với `chmod 000 backups`, log có dòng `[ERROR] Backup thất bại ở dòng ...`, exit code khác 0. ShellCheck không còn cảnh báo.

Mẫu log:

```text
2026-10-31 10:40:01 [INFO] Đã tạo /home/phuong/devops-lab/01-linux/lab06/backups/backup-20261031-104001.tar.gz
2026-10-31 10:40:01 [INFO] Đã xóa bản cũ: /home/phuong/devops-lab/01-linux/lab06/backups/backup-20261031-103955.tar.gz
```

---

## 11. Các lỗi thường gặp

| Lỗi | Nguyên nhân | Cách xử lý |
|---|---|---|
| `name: command not found` khi gán biến | Có dấu cách quanh `=` | Viết `name="x"` |
| `Permission denied` khi `./script.sh` (exit 126) | Thiếu quyền thực thi | `chmod +x script.sh` |
| `/bin/bash^M: bad interpreter` | Xuống dòng CRLF | Xem [bài 01, mục 11](01-linux-architecture-filesystem.md#11-các-lỗi-thường-gặp) |
| `[[: not found` hoặc `Syntax error: "(" unexpected` | Chạy bằng `sh` (dash) thay vì `bash` | Chạy `bash script.sh` hoặc `./script.sh` với shebang bash |
| `unbound variable` | `set -u` + biến chưa đặt | Đặt biến, hoặc dùng `"${VAR:-}"` nếu biến là tùy chọn |
| Script dừng bất ngờ ở `grep`, không có thông báo | `set -e` + grep không tìm thấy (exit 1) | `grep ... \|\| true`, hoặc đặt grep trong `if` |
| `[: too many arguments` | Biến có dấu cách, không quote, trong `[ ]` | Quote biến, dùng `[[ ]]` |
| `integer expression expected` | So sánh số với chuỗi rỗng hoặc chữ (`[[ "" -gt 5 ]]`) | Kiểm tra biến có giá trị số trước |
| Sửa `~/.bashrc` nhưng không có tác dụng | Chưa nạp lại | `source ~/.bashrc` hoặc mở terminal mới |
| Script chạy tay được, cron không chạy | Môi trường cron khác shell | Xem [bài 08](08-cron-scheduling.md) |
| `export PATH=...` xong mọi lệnh đều `command not found` | Ghi đè PATH, quên `:$PATH` | Mở terminal mới; sửa lại dòng trong file cấu hình |

---

## 12. Đọc log và xử lý lỗi

Script bị lỗi cho bạn 3 nguồn thông tin. Đọc theo thứ tự:

**1. Thông báo lỗi của Bash** — có số dòng:

```text
./backup.sh: line 14: DEST_DIR: unbound variable
│            │        │         └ mô tả
│            │        └ đối tượng
│            └ vị trí — mở file tới dòng 14
└ script nào
```

```text
./deploy.sh: line 8: mvnw: command not found
```

→ exit code `127`. Kiểm tra: chương trình có tồn tại không, có trong `PATH` không, có cần `./mvnw` không.

**2. Exit code** — `echo $?` ngay sau khi chạy. Đối chiếu bảng ở [mục 8](#exit-code-đặc-biệt-bạn-sẽ-gặp).

**3. Dấu vết thực thi** — khi thông báo không đủ rõ:

```bash
bash -x ./backup.sh data backups 2>&1 | tail -20
```

```text
+ SOURCE_DIR=data
+ DEST_DIR=backups
+ [[ ! -d data ]]
+ mkdir -p backups
++ date +%Y%m%d-%H%M%S
+ archive=backups/backup-20261031-104500.tar.gz
+ tar -czf backups/backup-20261031-104500.tar.gz -C . data
tar: backups/backup-20261031-104500.tar.gz: Cannot open: Permission denied
```

Số dấu `+` cho biết độ sâu lồng (`++` là lệnh bên trong `$(...)`). Lệnh cuối cùng trước thông báo lỗi chính là thủ phạm — ở đây: không có quyền ghi vào `backups/`.

**Quy trình debug script:**

1. Chạy lại với `bash -x`, tìm lệnh cuối cùng trước khi lỗi.
2. Copy đúng lệnh đó (với giá trị đã thay biến, lấy từ dòng `+`) ra terminal, chạy riêng.
3. Lệnh lỗi riêng lẻ → vấn đề ở lệnh/môi trường (quyền, file, PATH). Lệnh chạy riêng thì được → vấn đề ở biến/logic của script.
4. Chạy `shellcheck` — nhiều lỗi quote/logic được phát hiện trước khi bạn kịp chạy.
5. Ghi vào `troubleshooting-journal.md`.

---

## 13. Câu hỏi kiểm tra kiến thức

1. `bash script.sh` và `./script.sh` khác nhau thế nào? Khi nào cái này chạy được còn cái kia không?
2. Vì sao `sh script.sh` có thể lỗi dù `bash script.sh` chạy tốt trên Ubuntu?
3. Giải thích 3 kết quả: `echo "$HOME"`, `echo '$HOME'`, `echo $HOME`. Khi nào cách thứ 3 cho kết quả khác cách thứ 1?
4. `"$@"` và `$*` khác nhau thế nào? Cho ví dụ cụ thể.
5. `if` trong Bash kiểm tra cái gì? Vì sao `if grep -q ...` viết được mà không cần `[[ ]]`?
6. Vì sao `[[ 10 > 9 ]]` cho kết quả sai? Viết lại cho đúng.
7. Giải thích từng cờ trong `set -euo pipefail`. Nêu 2 tình huống `set -e` **không** dừng script dù có lệnh lỗi.
8. `return` và `exit` khác nhau thế nào? Một hàm Bash "trả về" dữ liệu bằng cách nào?
9. Vì sao `./set-env.sh` không thể đặt biến cho terminal của bạn, còn `source set-env.sh` thì được?
10. Biến shell và biến môi trường khác nhau thế nào? Ứng dụng Spring Boot chạy từ terminal thấy được loại nào?
11. Sau khi chạy `export PATH=/opt/tool/bin`, chuyện gì xảy ra? Viết lại cho đúng.
12. Exit code 126, 127 và 137 nói lên điều gì?
13. Vì sao không được commit file `.env`? Nếu lỡ commit lên GitHub, cần làm gì?
14. `trap cleanup EXIT` giải quyết vấn đề gì?

---

## 14. Bài tập tự làm

> Lời giải: [solutions/06-solutions.md](solutions/06-solutions.md) — chỉ mở sau khi đã tự làm. Mọi script nộp phải qua `bash -n` và ShellCheck không cảnh báo.

**Bài 1 — Script quản lý dịch vụ giả.** Viết `svc.sh` nhận lệnh con `start | stop | status | restart`:

- `start`: chạy `sleep 1000` ở chế độ nền, lưu PID vào `/tmp/svc.pid`. Nếu đã chạy rồi thì báo và không chạy thêm.
- `stop`: đọc PID, gửi SIGTERM, xóa file PID.
- `status`: in `running (PID xxx)` + exit 0, hoặc `stopped` + exit 3.
- Lệnh con sai → in cách dùng, exit 2.

Gợi ý: `kill -0 PID` kiểm tra process còn sống mà không gửi tín hiệu thật.

**Bài 2 — Kiểm tra danh sách website.** File `sites.txt` mỗi dòng một URL (có dòng trống và dòng chú thích bắt đầu bằng `#`). Viết script đọc từng dòng, bỏ qua dòng trống/chú thích, dùng `curl -s -o /dev/null -w '%{http_code}' --max-time 5` để lấy mã HTTP, in `OK`/`FAIL` cho mỗi URL. Script trả về exit code bằng **số URL thất bại** (tối đa 255).

**Bài 3 — Chờ có giới hạn.** Viết hàm `wait_for_port <host> <port> <timeout_giây>` thử kết nối mỗi giây (gợi ý: `bash -c "</dev/tcp/$host/$port"` hoặc `nc -z`), trả về 0 khi kết nối được, trả về 1 khi hết thời gian. Thử với `localhost 22` và một port không có gì lắng nghe.

**Bài 4 — Xoay vòng an toàn với `find`.** Viết lại hàm `rotate` của lab mà **không dùng `ls`**, xử lý đúng cả tên file có dấu cách. Thêm tùy chọn xóa theo **tuổi**: xóa backup cũ hơn `MAX_AGE_DAYS` ngày (gợi ý: `find -mtime`). Kiểm thử bằng `touch -d "10 days ago" <file>`.

**Bài 5 — Săn lỗi.** Script sau có ít nhất **6 lỗi** (cú pháp, quote, logic, an toàn). Tìm hết, giải thích mỗi lỗi gây ra hậu quả gì, rồi viết lại bản đúng:

```bash
#!/bin/sh
LOG_DIR = /var/log/myapp
DAYS=$1
if [ $DAYS > 30 ]
then
  echo "Giữ quá lâu"
fi
for f in $(ls $LOG_DIR/*.log); do
  rm $f
done
cd $LOG_DIR/archive
rm -rf *
echo "Done"
```

**Bài 6 — Biến môi trường.** Tạo `~/bin/hello` (script in `Xin chào $GREET_NAME`, mặc định `bạn` nếu biến chưa đặt). Làm cho lệnh `hello` chạy được từ **mọi thư mục** trong mọi terminal mới. Sau đó chứng minh bằng lệnh rằng: `GREET_NAME=Phương hello` không làm thay đổi `GREET_NAME` trong terminal.

---

## 15. Tiêu chí đánh giá đã hiểu bài

Bạn đã hiểu bài khi:

- [ ] Giải thích được sơ đồ mục 6.1 — vì sao `"$var"` an toàn còn `$var` thì không.
- [ ] Mọi script bạn viết đều bắt đầu bằng shebang + `set -euo pipefail` và kiểm tra tham số đầu vào.
- [ ] Đọc một script lạ, bạn chỉ ra được chỗ nào thiếu quote, chỗ nào lỗi bị nuốt mất.
- [ ] Gặp script lỗi, bạn dùng `bash -x` và tìm ra lệnh gây lỗi trong vòng 5 phút.
- [ ] Giải thích được vì sao biến đặt trong `~/.bashrc` không có khi chạy bằng cron.
- [ ] Hoàn thành Bài tập 1 và 5 không cần xem lời giải.

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [bash(1) — Ubuntu 24.04 manpage](https://manpages.ubuntu.com/manpages/noble/man1/bash.1.html) | Tài liệu chính thức của Bash 5.2 trên Ubuntu 24.04. Xem các mục *QUOTING*, *EXPANSION*, *SHELL BUILTIN COMMANDS* (`set`) | 2026-10-31 |
| [ShellCheck](https://www.shellcheck.net/) · [GitHub](https://github.com/koalaman/shellcheck) | Kiểm tra script trên trình duyệt hoặc cài bằng `apt` | 2026-10-31 |
| [MIT Missing Semester 2026 — Introduction to the Shell, Command-line Environment](https://missing.csail.mit.edu/) | Bổ sung về shell và biến môi trường | 2026-10-31 |
| [Linux Journey](https://labex.io/linuxjourney) | Ôn lại phần *Text-Fu* và *Command Line* nếu cần | 2026-10-31 |
| `man bash`, `help set`, `help [[` (chạy trên máy) | Tra cứu nhanh không cần mạng | — |
