# Lời giải — Bài 05: Chiến lược triển khai và rollback

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; username `phuong-dev` là ví dụ.

Quay lại bài: [05-deployment-strategies-rollback.md](../05-deployment-strategies-rollback.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Deploy và release?**
Deploy: đưa phiên bản mới lên hạ tầng và cho chạy. Release: cho người dùng tiếp xúc với thay đổi. Tách bằng: (1) feature flag — code đã deploy nhưng tính năng tắt; (2) blue/green — bản mới chạy ở môi trường chưa nhận traffic; (3) canary — bản mới chỉ nhận một phần nhỏ traffic.

**2. Downtime của recreate?**
Thời gian dừng container cũ (nhanh nếu app xử lý SIGTERM, ~10 giây nếu không) + thời gian bản mới khởi động tới khi sẵn sàng + độ trễ để proxy nhận ra bản mới (phân giải lại tên). Với `taskhub`: Spring Boot khởi động vài giây đến vài chục giây trên laptop, có thể lâu hơn trên EC2 nhỏ → downtime cỡ vài chục giây.

**3. Rolling update yêu cầu gì?**
Hai phiên bản **chạy cùng lúc** trong suốt quá trình và cùng phục vụ người dùng, cùng dùng một database → phải **tương thích**: API (client gọi bản nào cũng hiểu), schema database (cả hai bản đọc/ghi được), định dạng dữ liệu trong cache/queue.

**4. Blue/green rollback nhanh nhờ đâu? Đánh đổi?**
Bản cũ vẫn chạy nguyên vẹn; rollback chỉ là đổi router trỏ lại (vài giây, không khởi động gì). Đánh đổi lớn nhất: **gấp đôi tài nguyên** lúc chuyển, và **database dùng chung** buộc schema phải tương thích cả hai bản.

**5. Canary khác blue/green? Vì sao cần monitoring?**
Blue/green chuyển **toàn bộ** traffic một lần; canary chuyển **dần** theo tỉ lệ (5% → 25% → 100%). Quyết định tăng hay hạ canary dựa trên **số liệu** (tỉ lệ lỗi, độ trễ của canary so với bản cũ). Không đo được thì không biết canary tốt hay xấu → chỉ là deploy chậm hơn.

**6. Liveness/readiness? Compose có chặn traffic vào container unhealthy?**
Liveness: process còn sống không → sai thì khởi động lại. Readiness: sẵn sàng nhận request chưa → sai thì chưa gửi traffic. **Compose không chặn**: ở Bước 4, `v1.2.0` unhealthy mà nginx vẫn gửi request vào và `/version` vẫn trả 200. Healthcheck của Compose chỉ ảnh hưởng `depends_on: condition: service_healthy`, `up --wait` và trạng thái hiển thị. Load balancer (ALB) và Kubernetes thì rút bản không sẵn sàng khỏi danh sách nhận traffic.

**7. Smoke test khác test trong CI? Vì sao kiểm tra phiên bản?**
CI chứng minh **code** đúng trên môi trường tạm. Smoke test chứng minh **lần triển khai này** đúng trên môi trường thật: đúng image, đúng cấu hình, kết nối được database. Kiểm tra phiên bản vì "có trả lời 200" có thể đến từ **bản cũ** (deploy không thực sự xảy ra, nhầm tag, proxy trỏ sai) — smoke test chỉ kiểm tra 200 sẽ báo xanh sai.

**8. Vì sao không rollback bằng build lại từ commit cũ?**
Build lại hôm nay ra image **khác** image đã test: base image mới hơn, thư viện tải về có thể khác, công cụ build khác. Bạn đang deploy thứ chưa ai kiểm tra, đúng lúc khẩn cấp, và mất thêm thời gian build. Image cũ với tag bất biến đã được test và quét — chỉ cần chạy lại.

**9. v0.5.0 có `DROP COLUMN title`, rollback về v0.4.0?**
Image v0.4.0 khởi động, Hibernate (`ddl-auto: validate`) hoặc truy vấn đầu tiên tìm cột `title` không thấy → app lỗi ngay khi khởi động hoặc khi truy vấn → rollback làm hệ thống **chết**. Dữ liệu cột `title` đã mất. Lẽ ra: expand/contract — v0.5.0 chỉ thêm cột mới và ghi cả hai; xóa cột cũ ở release sau khi chắc không cần quay lại; backup trước migration.

**10. Flyway Community có undo không? Có cứu được dữ liệu không?**
Không — theo bảng tính năng Redgate, undo migrations chỉ có ở Flyway Teams/Enterprise. Kể cả có undo: script undo cho `DROP COLUMN` chỉ **tạo lại cột rỗng**, dữ liệu đã mất. Chỉ backup mới lấy lại được dữ liệu.

**11. Khi nào roll forward?**
Khi bản mới đã chạy migration không tương thích ngược (rollback làm app cũ chết); khi lỗi nhỏ, đã rõ nguyên nhân và sửa + CI + deploy nhanh hơn rollback; khi rollback chính nó có rủi ro (ví dụ bản cũ có lỗ hổng bảo mật đã được vá ở bản mới).

**12. Vì sao `deploy.sh` exit 1 dù rollback thành công?**
Mục tiêu của lệnh là "triển khai **phiên bản mới**". Mục tiêu đó **không đạt**. Exit code là cách pipeline CD (và người chạy) biết kết quả: exit 0 sẽ làm pipeline báo xanh, mọi người tưởng bản mới đang chạy. Dịch vụ vẫn hoạt động (nhờ rollback) là thông tin khác, được in ra log.

**13. `nginx -s reload` vs `docker compose restart nginx`?**
`reload`: master process kiểm tra cấu hình, khởi động worker mới, worker cũ **xử lý xong request đang dở** rồi mới thoát → không rớt kết nối; cấu hình sai thì giữ cấu hình cũ. `restart`: dừng hẳn container (mọi kết nối bị cắt) rồi khởi động lại → có khoảng không phục vụ, và nếu cấu hình sai thì nginx không lên được.

**14. Vì sao v3 dùng recreate?**
Một EC2 nhỏ, một bản `taskhub`: rolling cần nhiều bản sao sau load balancer (không có); blue/green cần chạy hai bản Spring Boot cùng lúc (gấp đôi RAM trên một instance nhỏ cỡ 1 GiB — sát giới hạn) và phức tạp hơn. Dự án cá nhân chấp nhận được vài chục giây downtime khi deploy. Đó là quyết định có ý thức, nên ghi thành ADR; blue/green để làm bài tập nâng cao.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Chọn chiến lược

- **(a) Công cụ nội bộ 20 người, giờ hành chính → Recreate**, deploy ngoài giờ. Downtime vài chục giây lúc không ai dùng là chấp nhận được; không cần thêm tài nguyên; không lo tương thích hai phiên bản. Thêm smoke test + rollback bằng tag là đủ.
- **(b) API thanh toán 24/7, 6 bản sao sau ALB → Rolling** (có sẵn nhiều bản sao, không downtime, ít tài nguyên thêm) hoặc **blue/green** nếu cần rollback tức thì và chịu được chi phí gấp đôi lúc chuyển. Bắt buộc: readiness đúng, graceful shutdown, migration expand/contract (hai bản chạy cùng lúc), monitoring để dừng giữa chừng. Nhiều team kết hợp canary nhỏ trước.
- **(c) Thử tính năng trên 1% người dùng → Feature flag** (permissioning/experiment toggle) — chọn đúng 1% **người dùng**, bật/tắt tức thì không cần deploy. Canary chia theo **request/instance**, khó đảm bảo cùng một người dùng luôn thấy cùng phiên bản; và ứng dụng di động không deploy lại tức thì được, nên cờ ở phía server là lựa chọn thực tế.
- **(d) `taskhub` v3, một EC2 nhỏ → Recreate** với `up --wait` + smoke test + tự rollback bằng tag. Lý do như câu A14. Chấp nhận downtime khi deploy, ghi rõ trong README/ADR.

### Bài 2 — Expand/contract: `description` → bảng `task_notes`

| Release | Migration | App | Rollback về release trước |
|---|---|---|---|
| **v0.6.0** — Expand | `V6__create_task_notes.sql`: `CREATE TABLE task_notes (id BIGSERIAL PRIMARY KEY, task_id BIGINT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, content TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());` + index trên `task_id` | Đọc `description` như cũ. Khi tạo/sửa task: ghi `description` **và** thêm một dòng `task_notes` | ✅ v0.5.x không biết bảng mới, bỏ qua nó |
| **v0.7.0** — Migrate | `V7__backfill_task_notes.sql`: `INSERT INTO task_notes (task_id, content) SELECT id, description FROM tasks t WHERE description IS NOT NULL AND NOT EXISTS (SELECT 1 FROM task_notes n WHERE n.task_id = t.id);` | **Đọc** từ `task_notes`; API mới cho nhiều ghi chú. Vẫn ghi `description` (bằng ghi chú mới nhất) để bản trước còn đúng | ✅ v0.6.0 vẫn đọc `description`, cột này vẫn được cập nhật |
| **v0.8.0** — Contract (sau khi v0.7.0 ổn định một thời gian) | `V8__drop_tasks_description.sql`: `ALTER TABLE tasks DROP COLUMN description;` — **backup trước** | Chỉ dùng `task_notes` | ⚠️ Chỉ về được v0.7.0 nếu v0.7.0 **không bắt buộc** cột `description` tồn tại. An toàn hơn: v0.7.1 ngừng ghi/đọc `description` trước, v0.8.0 mới xóa cột |

Điểm chấm: mỗi release tương thích với release ngay trước; bước xóa nằm riêng và muộn; backfill **idempotent** (chạy lại không nhân đôi — nhờ `NOT EXISTS`); có backup trước bước contract.

### Bài 3 — Đo chuỗi lỗi dài nhất

```bash
#!/usr/bin/env bash
# Như watch.sh, thêm: chuỗi lỗi liên tiếp dài nhất (thời điểm bắt đầu, kết thúc, độ dài).
port="${BG_PORT:-8090}"
ok=0
fail=0
streak_start=""
best_len=0
best_from=""
best_to=""

fmt() { date -d "@$1" +%T.%N | cut -c1-12; }

close_streak() {             # $1 = thời điểm request thành công đầu tiên sau chuỗi lỗi
  [[ -z "$streak_start" ]] && return 0
  local len
  len="$(awk -v a="$streak_start" -v b="$1" 'BEGIN { printf "%.3f", b - a }')"
  if awk -v l="$len" -v m="$best_len" 'BEGIN { exit !(l > m) }'; then
    best_len="$len"; best_from="$streak_start"; best_to="$1"
  fi
  streak_start=""
}

summary() {
  close_streak "$(date +%s.%N)"
  echo
  echo "OK=$ok  LỖI=$fail"
  if [[ -n "$best_from" ]]; then
    echo "Chuỗi lỗi dài nhất: $(fmt "$best_from") → $(fmt "$best_to") (${best_len} giây)"
  fi
  exit 0
}
trap summary INT

while true; do
  now="$(date +%s.%N)"
  code="$(curl -s -o /dev/null --max-time 1 -w '%{http_code}' "http://localhost:${port}/version" || true)"
  if [[ "$code" == "200" ]]; then
    ok=$((ok + 1))
    close_streak "$now"
  else
    fail=$((fail + 1))
    [[ -z "$streak_start" ]] && streak_start="$now"
  fi
  printf '%s %s\n' "$(fmt "$now")" "$code"
  sleep 0.2
done
```

So sánh với "số lỗi × 0,2": cách cũ **đánh giá thấp** downtime, vì mỗi vòng lặp mất 0,2 giây ngủ **cộng** thời gian của chính request (request lỗi có thể chờ tới `--max-time 1`). Đo bằng đồng hồ (từ request lỗi đầu tiên tới request thành công đầu tiên) mới là con số thật. Nếu Ctrl+C khi đang trong chuỗi lỗi, `summary` đóng chuỗi tại thời điểm dừng.

### Bài 4 — Áp dụng cho `taskhub`

**Chuẩn bị Compose.** Vấn đề: service `taskhub` ở v0 có cả `build:` lẫn `image: taskhub:local`. Khi deploy từ registry, ta không muốn build. Cách gọn (dùng lại [Docker 05 — override file](../../04-DOCKER/05-docker-compose.md)):

- `compose.yaml` (dùng để deploy): `image: ghcr.io/phuong-dev/taskhub:${TASKHUB_IMAGE_TAG:?Đặt TASKHUB_IMAGE_TAG trong .env}`, **bỏ** `build:`.
- `compose.override.yaml` (chỉ dev, tự gộp khi chạy `docker compose` không có `-f`): thêm lại `build:` và `image: taskhub:local`.
- Script deploy luôn gọi `docker compose -f compose.yaml` để **không** gộp file override.

**Khác biệt quan trọng so với lab:** `.env` của `taskhub` còn chứa `POSTGRES_PASSWORD` → script **chỉ sửa dòng `TASKHUB_IMAGE_TAG`**, không được ghi đè cả file.

`scripts/deploy.sh`:

```bash
#!/usr/bin/env bash
# Triển khai taskhub theo tag image trên GHCR. Lỗi pull/health/smoke → quay về tag trước.
set -euo pipefail
cd "$(dirname "$0")/.."

new_tag="${1:?Cách dùng: scripts/deploy.sh <tag>, ví dụ v0.3.0 hoặc 9f8e7d6}"
port="${NGINX_HOST_PORT:-8000}"
compose=(docker compose -f compose.yaml)
prev_tag="$(sed -n 's/^TASKHUB_IMAGE_TAG=//p' .env)"

set_tag() {
  if grep -q '^TASKHUB_IMAGE_TAG=' .env; then
    sed -i "s/^TASKHUB_IMAGE_TAG=.*/TASKHUB_IMAGE_TAG=$1/" .env
  else
    echo "TASKHUB_IMAGE_TAG=$1" >> .env
  fi
}

deploy() {
  set_tag "$1"
  "${compose[@]}" pull taskhub
  "${compose[@]}" up -d --wait --wait-timeout 150
}

smoke_test() {
  local cid image
  curl -fsS --retry 10 --retry-connrefused --retry-delay 3 \
    "http://localhost:${port}/actuator/health" | grep -q '"status":"UP"'
  cid="$("${compose[@]}" ps -q taskhub)"
  image="$(docker inspect -f '{{.Config.Image}}' "$cid")"
  [[ "$image" == *":$1" ]] || { echo "Container đang chạy image $image, không phải :$1" >&2; return 1; }
}

echo ">> Triển khai taskhub:${new_tag} (đang chạy: ${prev_tag:-chưa có})"
if deploy "$new_tag" && smoke_test "$new_tag"; then
  echo ">> OK: taskhub:${new_tag}"
  exit 0
fi

echo ">> LỖI khi triển khai ${new_tag}. Log gần nhất:" >&2
"${compose[@]}" logs taskhub --tail 40 >&2 || true

if [[ -z "$prev_tag" || "$prev_tag" == "$new_tag" ]]; then
  echo ">> Không có phiên bản trước để quay về" >&2
  exit 1
fi
echo ">> Rollback về ${prev_tag}" >&2
deploy "$prev_tag"
smoke_test "$prev_tag"
echo ">> Đã rollback về ${prev_tag}. Triển khai ${new_tag} THẤT BẠI." >&2
exit 1
```

`--wait-timeout 150` vì healthcheck của `taskhub` có `start_period: 60s` và Spring Boot cần thời gian; 40 giây như lab sẽ báo lỗi oan.

Kết quả mong đợi của ba thử nghiệm:

| Thử nghiệm | Thất bại ở | Script làm gì |
|---|---|---|
| Tag tốt (ví dụ SHA của commit mới nhất trên `main`) | — | Exit 0 |
| Tag không tồn tại (`v9.9.9`) | `pull`: `manifest unknown` (chữ có thể khác) | Rollback về tag trước (thực tế container cũ chưa bị thay, rollback chỉ ghi lại `.env`), exit 1 |
| Tag tốt + sai mật khẩu database (sửa tạm `POSTGRES_PASSWORD` trong `.env`) | `up --wait`: `taskhub` không healthy (Flyway/kết nối lỗi `password authentication failed`) | Rollback… **cũng thất bại**, vì bản cũ dùng cùng mật khẩu sai → exit khác 0 |

Thử nghiệm thứ ba là bài học quan trọng nhất (mục 12.2 của bài): lỗi **cấu hình/hạ tầng** thì rollback image không cứu được. Thay đổi cấu hình cũng là một lần triển khai, cần được kiểm soát như code. ⚠️ Nhớ trả lại `POSTGRES_PASSWORD` đúng ngay sau thử nghiệm (PostgreSQL giữ mật khẩu từ lần đầu tạo volume, chỉ app bị sai).

### Bài 5 — Thiết kế blue/green cho `taskhub`

Thiết kế: `taskhub-blue`, `taskhub-green` (cùng cấu hình, khác `image:` tag), một `postgres`, `nginx` chọn upstream bằng `active.inc` như lab.

**Migration chạy lúc nào, bởi bản nào?** Với cấu hình hiện tại, Flyway chạy **lúc ứng dụng khởi động** → bản green chạy migration ngay khi được khởi động, **trong khi blue vẫn đang phục vụ** trên cùng database. Flyway dùng bảng `flyway_schema_history` và khóa để hai bản không chạy migration chồng lên nhau, nhưng điều đó không giải quyết vấn đề tương thích.

**Nếu migration của green không tương thích với blue?** Ngay khi green khởi động (chưa nhận traffic), schema đã đổi → blue đang phục vụ người dùng bắt đầu lỗi. Lợi thế "kiểm tra trước khi chuyển" của blue/green mất hết, và "rollback bằng cách chuyển về blue" cũng vô nghĩa vì blue đã hỏng.

**Quy định để blue/green an toàn:**

1. Mọi migration phải **tương thích ngược với phiên bản đang chạy** (chỉ expand). Contract luôn ở release sau, khi bản cũ không còn chạy ở đâu.
2. Review PR có migration với câu hỏi bắt buộc: "bản đang chạy có hoạt động được với schema mới không?"
3. 🟨 Cân nhắc tách migration khỏi khởi động app (chạy Flyway như một bước riêng trong pipeline trước khi khởi động green) để kiểm soát thời điểm và quan sát kết quả.
4. Backup trước release có migration.
5. RAM: hai JVM cùng chạy trên một instance cỡ 1 GiB rất sát — đặt `-XX:MaxRAMPercentage` và giới hạn bộ nhớ container, hoặc chấp nhận instance lớn hơn trong lúc làm bài tập (và ghi vào bảng chi phí).
