# Lời giải — 06. Bash scripting & biến môi trường

> ⚠️ Chỉ đọc sau khi đã tự làm. Lời giải ở đây là **một** cách đúng — cách của bạn khác nhưng đáp ứng yêu cầu, qua `bash -n` và ShellCheck sạch thì vẫn đạt.
> Quay lại bài: [06-bash-scripting.md](../06-bash-scripting.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức](#phần-a--câu-hỏi-kiểm-tra-kiến-thức)
- [Phần B — Bài tập tự làm](#phần-b--bài-tập-tự-làm)
  - [Bài 1 — svc.sh](#bài-1--svcsh)
  - [Bài 2 — Kiểm tra danh sách website](#bài-2--kiểm-tra-danh-sách-website)
  - [Bài 3 — wait_for_port](#bài-3--wait_for_port)
  - [Bài 4 — Xoay vòng an toàn với find](#bài-4--xoay-vòng-an-toàn-với-find)
  - [Bài 5 — Săn lỗi](#bài-5--săn-lỗi)
  - [Bài 6 — Biến môi trường](#bài-6--biến-môi-trường)

---

## Phần A — Câu hỏi kiểm tra kiến thức

**1.** `bash script.sh`: bạn chỉ định trực tiếp chương trình thông dịch, file chỉ cần quyền **đọc**, dòng shebang bị bỏ qua (Bash coi nó là chú thích). `./script.sh`: kernel đọc shebang để chọn trình thông dịch, file cần quyền **thực thi** (`x`). Ví dụ: file thiếu quyền `x` → `./script.sh` báo `Permission denied` (exit 126) nhưng `bash script.sh` vẫn chạy. Ngược lại, file có shebang `#!/usr/bin/env python3` thì `./script.sh` chạy bằng Python, còn `bash script.sh` sẽ lỗi cú pháp.

**2.** Trên Ubuntu, `sh` là **dash** — shell tuân thủ POSIX, tối giản, không hỗ trợ `[[ ]]`, mảng, `set -o pipefail` (trên dash bản cũ), `{1..10}`, `(( ))` dạng lệnh... `sh script.sh` buộc dash chạy script viết cho Bash → lỗi kiểu `[[: not found`.

**3.** `"$HOME"` → `/home/phuong` (thay biến, không tách từ). `'$HOME'` → in nguyên văn `$HOME`. `$HOME` không nháy → cũng `/home/phuong`, **nhưng** kết quả bị tách từ và glob. Khác nhau khi giá trị chứa dấu cách hoặc ký tự đại diện: `d="a  b"; echo $d` in `a b` (2 dấu cách gộp thành 1, vì `echo` nhận 2 tham số), `echo "$d"` in `a  b`. Với `x="*"`, `echo $x` in danh sách file trong thư mục hiện tại.

**4.** `"$@"` giữ nguyên từng tham số là một phần tử riêng; `$*` (và `"$*"`) gộp tất cả thành một chuỗi. Ví dụ `./s.sh "a b" c`:
- `for x in "$@"` → 2 lần lặp: `a b`, `c`.
- `for x in "$*"` → 1 lần lặp: `a b c`.
- `for x in $*` → 3 lần lặp: `a`, `b`, `c`.

**5.** `if` chạy một lệnh và kiểm tra **exit code** (0 → `then`). `[[ ]]` chỉ là một lệnh đặc biệt trả về 0/1. `grep -q` cũng là một lệnh trả về 0 khi tìm thấy, 1 khi không — nên đặt thẳng sau `if` được.

**6.** Trong `[[ ]]`, `>` so sánh **chuỗi** theo thứ tự từ điển: ký tự `1` < `9` nên `"10" > "9"` sai. Viết đúng: `[[ 10 -gt 9 ]]` hoặc `(( 10 > 9 ))`. (Trong `[ ]` một ngoặc còn tệ hơn: `>` là **redirect**, tạo ra file tên `9` — xem Bài 5.)

**7.**
- `-e`: dừng khi một lệnh trả về khác 0.
- `-u`: dùng biến chưa đặt → lỗi và dừng.
- `-o pipefail`: pipeline thất bại nếu **bất kỳ** lệnh nào trong đó thất bại (exit code của lệnh cuối cùng thất bại).

Hai tình huống `set -e` không dừng: lệnh lỗi nằm trong điều kiện `if`/`while`/`until`; lệnh lỗi đứng trước `&&` hoặc `||` (ví dụ `false || echo x`); lệnh có `!` phía trước; lỗi bị `local x="$(...)"` che (vì `local` trả về 0).

**8.** `return N` thoát khỏi **hàm**, `exit N` thoát khỏi **cả script** (nếu gọi trong hàm, script cũng kết thúc). Hàm Bash không trả giá trị như Java; dữ liệu được "trả về" bằng cách `echo` ra stdout và người gọi bắt bằng `result="$(ham)"`. Exit code của hàm chỉ dùng để báo thành công/thất bại (0–255).

**9.** `./set-env.sh` chạy trong một **process con**; biến được đặt trong process con và mất khi process đó kết thúc. Process con không bao giờ sửa được môi trường của cha. `source set-env.sh` chạy các lệnh ngay trong **shell hiện tại**, nên biến tồn tại sau đó.

**10.** Biến shell chỉ tồn tại trong shell hiện tại; biến môi trường (đã `export`) được sao chép sang mọi process con. App Spring Boot khởi chạy từ terminal là process con → chỉ thấy **biến môi trường**.

**11.** `PATH` bị thay thế hoàn toàn bằng `/opt/tool/bin` → shell không còn tìm thấy `ls`, `cat`, `grep`... (`command not found`), chỉ trong terminal đó. Viết đúng: `export PATH="/opt/tool/bin:$PATH"`.

**12.** `126`: tìm thấy file nhưng không thực thi được (thiếu quyền `x`, hoặc là thư mục). `127`: không tìm thấy lệnh (sai tên, không có trong `PATH`). `137` = 128 + 9: process bị **SIGKILL** — thường do `kill -9` hoặc OOM killer khi hết bộ nhớ.

**13.** `.env` chứa secret (mật khẩu DB, API key). Commit lên Git = lưu vĩnh viễn trong lịch sử, ai clone repo cũng đọc được; repo public còn bị bot quét secret trong vài phút. Nếu lỡ commit: (1) **đổi ngay** mật khẩu/khóa bị lộ (bước quan trọng nhất); (2) xóa file khỏi repo, thêm vào `.gitignore`; (3) nếu cần, viết lại lịch sử Git để xóa hẳn — nhưng vẫn phải coi secret là đã lộ.

**14.** `trap cleanup EXIT` đảm bảo hàm dọn dẹp (xóa file tạm, nhả khóa...) luôn chạy khi script kết thúc — kể cả khi kết thúc do lỗi với `set -e` hoặc do `exit` ở giữa script. Không có nó, script lỗi giữa chừng để lại rác.

---

## Phần B — Bài tập tự làm

### Bài 1 — svc.sh

```bash
#!/usr/bin/env bash
# svc.sh — quản lý một "dịch vụ" giả (sleep 1000) bằng file PID.
set -euo pipefail

PID_FILE="${PID_FILE:-/tmp/svc.pid}"

is_running() {
    [[ -s "$PID_FILE" ]] || return 1
    local pid
    pid="$(cat "$PID_FILE")"
    kill -0 "$pid" 2>/dev/null
}

start() {
    if is_running; then
        echo "Đã chạy rồi (PID $(cat "$PID_FILE"))"
        return 0
    fi
    sleep 1000 &
    echo "$!" > "$PID_FILE"
    echo "Đã khởi động (PID $!)"
}

stop() {
    if ! is_running; then
        echo "Không chạy"
        rm -f -- "$PID_FILE"
        return 0
    fi
    local pid
    pid="$(cat "$PID_FILE")"
    kill -TERM "$pid"
    for _ in {1..10}; do                      # chờ tối đa 10 giây cho process thoát
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    rm -f -- "$PID_FILE"
    echo "Đã dừng (PID $pid)"
}

status() {
    if is_running; then
        echo "running (PID $(cat "$PID_FILE"))"
        return 0
    fi
    echo "stopped"
    return 3
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    restart) stop; start ;;
    *)       echo "Cách dùng: $0 {start|stop|status|restart}" >&2; exit 2 ;;
esac
```

Giải thích các điểm chính:

- `$!` = PID của process vừa chạy nền gần nhất.
- `kill -0 PID` không gửi tín hiệu thật, chỉ kiểm tra process tồn tại và ta có quyền gửi tín hiệu → exit 0 nếu còn sống.
- `"${1:-}"` để `set -u` không báo lỗi khi gọi script không có tham số.
- `status` trả về 3: vì là lệnh cuối trong `case`, với `set -e` script kết thúc với đúng exit code 3. Quy ước exit 3 = "không chạy" cũng là quy ước của các script init cổ điển (LSB).
- Hạn chế đã biết: nếu process chết và hệ điều hành cấp lại **cùng PID** cho process khác, `kill -0` sẽ nhầm. systemd giải quyết vấn đề này tốt hơn nhiều — đó là lý do thực tế ta dùng systemd ([bài 04](../04-processes-systemd.md)) thay vì tự quản lý file PID.

Kiểm thử:

```bash
./svc.sh status; echo "exit=$?"     # stopped, exit=3
./svc.sh start
./svc.sh start                      # Đã chạy rồi
./svc.sh status; echo "exit=$?"     # running, exit=0
./svc.sh restart
./svc.sh stop
./svc.sh foo; echo "exit=$?"        # cách dùng, exit=2
```

### Bài 2 — Kiểm tra danh sách website

`sites.txt` mẫu:

```text
# Website cần giám sát
https://ubuntu.com
https://example.com

https://khong-ton-tai.invalid
```

```bash
#!/usr/bin/env bash
# check-sites.sh — kiểm tra mã HTTP của danh sách URL. Exit code = số URL thất bại (tối đa 255).
set -euo pipefail

SITES_FILE="${1:?Cách dùng: $0 <file-danh-sách>}"
if [[ ! -r "$SITES_FILE" ]]; then
    echo "Không đọc được $SITES_FILE" >&2
    exit 255
fi

fail=0
while IFS= read -r url || [[ -n "$url" ]]; do
    # bỏ dòng trống (hoặc chỉ có khoảng trắng) và dòng chú thích
    if [[ -z "${url//[[:space:]]/}" || "$url" == \#* ]]; then
        continue
    fi
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
    if [[ "$code" =~ ^[23] ]]; then
        echo "OK   $code $url"
    else
        echo "FAIL $code $url"
        fail=$(( fail + 1 ))
    fi
done < "$SITES_FILE"

echo "Tổng số thất bại: $fail"
exit $(( fail > 255 ? 255 : fail ))
```

```text
OK   200 https://ubuntu.com
OK   200 https://example.com
FAIL 000 https://khong-ton-tai.invalid
Tổng số thất bại: 1
```

Giải thích:

- `|| [[ -n "$url" ]]`: nếu dòng cuối file không có ký tự xuống dòng, `read` trả về 1 nhưng vẫn đọc được dữ liệu — điều kiện này giữ lại dòng đó.
- `${url//[[:space:]]/}`: xóa mọi khoảng trắng; nếu kết quả rỗng thì dòng chỉ có khoảng trắng.
- `curl ... || true`: khi không kết nối được, curl in `000` (nhờ `-w`) và trả về khác 0. `|| true` để `set -e` không dừng script, mà vẫn giữ được chuỗi `000`.
- Coi 2xx, 3xx là OK. Có người chỉ coi 2xx là OK — chấp nhận được nếu bạn giải thích.
- Exit code tối đa 255 vì exit code chỉ có 8 bit: `exit 256` thực tế thành 0 — **báo thành công sai**.
- Kết quả có thể khác nếu trang trả về mã khác (ví dụ chuyển hướng 301) — kiểm tra bằng `curl -sI <url>`.

### Bài 3 — wait_for_port

```bash
#!/usr/bin/env bash
set -euo pipefail

# wait_for_port <host> <port> <timeout_giây>
wait_for_port() {
    local host="$1" port="$2" timeout="$3" i
    for (( i = 1; i <= timeout; i++ )); do
        if timeout 1 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
            echo "Kết nối được ${host}:${port} sau ${i} giây"
            return 0
        fi
        sleep 1
    done
    echo "Hết thời gian chờ ${host}:${port} (${timeout} giây)" >&2
    return 1
}

wait_for_port "${1:-localhost}" "${2:-8000}" "${3:-10}"
```

Giải thích:

- `/dev/tcp/host/port` là tính năng **của Bash** (không phải file thật): mở redirect tới đó = mở kết nối TCP. Thành công → exit 0.
- `timeout 1` giới hạn mỗi lần thử 1 giây — nếu port bị firewall chặn (gói tin bị bỏ, không bị từ chối), kết nối có thể treo lâu.
- Biến `i` khai báo `local` cùng dòng.

Kiểm thử: WSL thường **không** chạy SSH server nên port 22 có thể đóng. Mở một port để thử:

```bash
python3 -m http.server 8000 &          # terminal: một web server đơn giản ở port 8000
./wait.sh localhost 8000 5; echo "exit=$?"     # kết nối được, exit=0
kill %1
./wait.sh localhost 8000 3; echo "exit=$?"     # hết thời gian, exit=1
```

### Bài 4 — Xoay vòng an toàn với find

```bash
KEEP="${KEEP:-5}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-}"          # rỗng = không xóa theo tuổi

rotate() {
    # 1) Giữ KEEP bản mới nhất: in "thời-gian đường-dẫn" phân tách bằng ký tự NUL, sắp mới → cũ
    find "$DEST_DIR" -maxdepth 1 -type f -name 'backup-*.tar.gz' -printf '%T@ %p\0' \
        | sort -z -rn \
        | tail -z -n +$(( KEEP + 1 )) \
        | cut -z -d ' ' -f 2- \
        | while IFS= read -r -d '' f; do
              rm -f -- "$f"
              log INFO "Đã xóa bản cũ (vượt số lượng): $f"
          done

    # 2) Xóa theo tuổi
    if [[ -n "$MAX_AGE_DAYS" ]]; then
        find "$DEST_DIR" -maxdepth 1 -type f -name 'backup-*.tar.gz' -mtime +"$MAX_AGE_DAYS" -print0 \
            | while IFS= read -r -d '' f; do
                  rm -f -- "$f"
                  log INFO "Đã xóa bản cũ (quá ${MAX_AGE_DAYS} ngày): $f"
              done
    fi
}
```

Giải thích:

- `-printf '%T@ %p\0'`: in thời điểm sửa (giây, có phần thập phân), dấu cách, đường dẫn, rồi ký tự **NUL** (`\0`). NUL là ký tự duy nhất không thể xuất hiện trong tên file → an toàn với mọi tên, kể cả có dấu cách hoặc xuống dòng.
- `sort -z`, `tail -z`, `cut -z`, `read -d ''`: các phiên bản "dùng NUL làm dấu phân cách" của lệnh quen thuộc.
- `cut -d ' ' -f 2-`: lấy từ trường 2 đến hết — giữ nguyên đường dẫn có dấu cách.
- `-mtime +N`: sửa đổi cách đây **hơn N ngày tròn** (find làm tròn xuống theo đơn vị 24 giờ). `-mtime +2` khớp file từ 3 ngày tuổi trở lên.
- Vòng `while` nằm sau pipe chạy trong **subshell** — biến đặt trong đó không còn sau vòng lặp. Ở đây chỉ `rm` và ghi log nên không ảnh hưởng.

Kiểm thử:

```bash
touch -d "10 days ago" "backups/backup-20261021-000000.tar.gz"
touch "backups/backup có dấu cách.tar.gz"       # tên lạ — không khớp mẫu backup-*, phải KHÔNG bị xóa
KEEP=3 MAX_AGE_DAYS=7 ./backup.sh data backups
ls -l backups/
```

### Bài 5 — Săn lỗi

| # | Dòng | Lỗi | Hậu quả |
|---|---|---|---|
| 1 | `#!/bin/sh` + không có `set -euo pipefail` | Chạy bằng dash; không dừng khi lỗi | Lỗi ở dòng trên vẫn chạy tiếp các lệnh xóa bên dưới |
| 2 | `LOG_DIR = /var/log/myapp` | Dấu cách quanh `=` | Shell chạy lệnh tên `LOG_DIR` → `not found`; `LOG_DIR` **rỗng** |
| 3 | `DAYS=$1` | Không kiểm tra tham số | `DAYS` rỗng hoặc không phải số |
| 4 | `[ $DAYS > 30 ]` | Trong `[ ]`, `>` là **redirect** | Tạo file tên `30`; điều kiện thực chất là `[ $DAYS ]` → đúng khi `DAYS` không rỗng → luôn in "Giữ quá lâu" |
| 5 | `for f in $(ls $LOG_DIR/*.log)` | Phân tích output `ls`, không quote | Tên có dấu cách bị tách; `LOG_DIR` rỗng → `/*.log` |
| 6 | `rm $f` | Không quote, không `--` | Xóa nhầm khi tên có dấu cách hoặc bắt đầu bằng `-` |
| 7 | Logic | `DAYS` không được dùng khi xóa | Xóa **tất cả** log, không phải log cũ hơn `DAYS` ngày |
| 8 | `cd $LOG_DIR/archive` | Không kiểm tra `cd` thành công | `LOG_DIR` rỗng → `cd /archive` thất bại → vẫn ở thư mục cũ |
| 9 | `rm -rf *` | Chạy ở thư mục hiện tại sau khi `cd` thất bại | ⚠️ **Xóa sạch thư mục bạn đang đứng** — lỗi thảm họa nhất |
| 10 | `echo "Done"` | Luôn exit 0 | Cron/CI báo thành công dù mọi thứ đã hỏng |

Bản đúng:

```bash
#!/usr/bin/env bash
# clean-logs.sh — xóa log cũ hơn N ngày và dọn thư mục archive.
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/myapp}"
DAYS="${1:?Cách dùng: $0 <số-ngày>}"

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "Số ngày phải là số nguyên dương: '$DAYS'" >&2
    exit 2
fi
if (( DAYS > 30 )); then
    echo "Cảnh báo: giữ log quá lâu ($DAYS ngày)" >&2
fi
if [[ ! -d "$LOG_DIR" ]]; then
    echo "Không tìm thấy thư mục $LOG_DIR" >&2
    exit 1
fi

find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$DAYS" -print -delete

if [[ -d "$LOG_DIR/archive" ]]; then
    find "${LOG_DIR:?}/archive" -mindepth 1 -delete      # không cd, không glob
fi

echo "Done"
```

Điểm mấu chốt: **không bao giờ** `cd` rồi `rm -rf *` — xóa bằng đường dẫn tuyệt đối đã được kiểm tra, hoặc dùng `find` với điều kiện rõ ràng.

### Bài 6 — Biến môi trường

```bash
mkdir -p ~/bin
cat > ~/bin/hello <<'EOF'
#!/usr/bin/env bash
echo "Xin chào ${GREET_NAME:-bạn}"
EOF
chmod +x ~/bin/hello
```

Làm cho `hello` chạy được từ mọi nơi: thêm vào **cuối** `~/.bashrc`:

```bash
export PATH="$HOME/bin:$PATH"
```

rồi `source ~/.bashrc` (hoặc mở terminal mới).

> Ghi chú: `~/.profile` mặc định của Ubuntu đã có đoạn tự thêm `~/bin` vào `PATH` **nếu thư mục tồn tại lúc đăng nhập**. Vì vậy trên một số máy, chỉ cần tạo `~/bin` rồi mở terminal mới (login shell) là đủ. Thêm dòng vào `~/.bashrc` thì chắc chắn và rõ ràng hơn. Kiểm tra bằng `echo "$PATH" | tr ':' '\n' | grep bin`.

Chứng minh biến chỉ áp dụng cho một lệnh:

```bash
cd /tmp
hello                          # Xin chào bạn
GREET_NAME=Phương hello        # Xin chào Phương
echo "[${GREET_NAME:-}]"       # [] → terminal không có GREET_NAME
type hello                     # hello is /home/phuong/bin/hello
```

Giải thích: cú pháp `VAR=value lệnh` đặt biến vào môi trường **của riêng process lệnh đó**; shell hiện tại không bị thay đổi.
