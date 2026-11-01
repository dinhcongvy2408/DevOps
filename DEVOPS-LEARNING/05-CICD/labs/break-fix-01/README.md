# Break-fix CI #1 — Pipeline được bàn giao chưa bao giờ xanh

> ⏱️ 90–150 phút · Môi trường: `[WSL]` + `[GitHub]` (trình duyệt) · Kiến thức cần có: Module 05 bài [01](../../01-cicd-concepts.md) → [04](../../04-secrets-environments.md), [Lab 01](../lab-01-ci-pr-gate.md)
> Lời giải: [solutions/break-fix-01-solution.md](../../solutions/break-fix-01-solution.md) — **chỉ mở khi đã hoàn thành hoặc đã bị kẹt quá 30 phút sau khi xem hết gợi ý.**

## Mục lục

- [1. Bối cảnh](#1-bối-cảnh)
- [2. Vì sao dùng một repo riêng để luyện](#2-vì-sao-dùng-một-repo-riêng-để-luyện)
- [3. Khởi tạo môi trường](#3-khởi-tạo-môi-trường)
- [4. Công cụ bạn được dùng](#4-công-cụ-bạn-được-dùng)
- [5. Các ticket](#5-các-ticket)
- [6. Luật chơi](#6-luật-chơi)
- [7. Tiêu chí hoàn thành](#7-tiêu-chí-hoàn-thành)
- [8. Sản phẩm phải nộp](#8-sản-phẩm-phải-nộp)
- [9. Gợi ý](#9-gợi-ý)
- [10. Dọn dẹp](#10-dọn-dẹp)
- [Nguồn tham khảo](#nguồn-tham-khảo)

---

## 1. Bối cảnh

Team vừa nhận một bản sao của `taskhub` kèm file `.github/workflows/ci.yml` do một đồng nghiệp viết trước khi chuyển dự án. Lời nhắn bàn giao chỉ có một dòng: *"CI viết xong rồi, chắc chạy được. Mình đã chuyển mật khẩu DB sang secrets cho an toàn."*

Thực tế: từ lúc có file này, pipeline **chưa xanh lần nào**. Trưởng nhóm cần CI chạy đúng trước khi bật luật "PR chỉ merge được khi CI xanh". Bạn được giao sửa.

Khác với break-fix Docker, ở đây bạn **không có quyền vào máy chạy job** (runner). Thứ duy nhất bạn có là: file YAML, log trên trang Actions, và khả năng chạy lại đúng các lệnh đó trên máy mình. Đây chính là tình huống bạn sẽ gặp hằng tuần khi đi làm.

---

## 2. Vì sao dùng một repo riêng để luyện

Bài này dùng một repo GitHub **mới, dùng xong bỏ**, tên `taskhub-ci-breakfix`:

- Repo `taskhub` thật, lịch sử commit và package `ghcr.io/<github-user>/taskhub` của bạn **không bị đụng tới**.
- Bạn được push thẳng lên `main` của repo luyện tập (không cần PR cho từng lần thử) — trên `taskhub` thật thì không.
- Repo để **Public** vì job trên runner chuẩn của GitHub miễn phí cho repo public. Repo private dùng vào phần chi phí miễn phí hằng tháng của tài khoản.

Workflow trong bài **chỉ có job `build-test`**, không có job `image`. Lý do: (1) trọng tâm là đọc log build/test, không phải build image; (2) không có bước push nào nên không có gì được đẩy lên GHCR; (3) mỗi lần thử nhanh hơn vài phút. Bạn có thể thêm job `image` (build + quét, không push) làm bài mở rộng sau khi xong.

---

## 3. Khởi tạo môi trường

**Điều kiện:** repo `~/projects/taskhub` đã hoàn thành dự án v0 (có `app/mvnw`, `app/pom.xml`, `docker/Dockerfile` trong commit `HEAD`), và bạn push lên GitHub bằng SSH được (Module 03).

`[WSL]` — copy script từ giáo trình về và chạy:

```bash
mkdir -p ~/devops-lab/05-cicd/tools && cd ~/devops-lab/05-cicd/tools
# Đổi đường dẫn cho đúng nơi bạn lưu DEVOPS-LEARNING
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/05-CICD/labs/break-fix-01/setup.sh .
cp /mnt/d/HocDepOps/DEVOPS-LEARNING/05-CICD/labs/break-fix-01/verify.sh .
sed -i 's/\r$//' setup.sh verify.sh     # phòng trường hợp file bị đổi sang CRLF khi copy từ Windows
bash setup.sh                          # hoặc: bash setup.sh /đường/dẫn/khác/tới/taskhub
```

Script **chỉ đọc** commit `HEAD` của repo taskhub (`git archive HEAD`) và tạo thư mục mới `~/devops-lab/05-cicd/bf05-ci` có repo Git riêng với một commit. Nó từ chối chạy nếu thư mục đó đã tồn tại, hoặc nếu commit `HEAD` chứa file `.env` (repo luyện tập là public).

`[GitHub]` — tạo repo rỗng:

1. **New repository** → tên `taskhub-ci-breakfix` → **Public**.
2. **Không** tick *Add a README*, *.gitignore*, *license* — repo phải rỗng để push không bị conflict.

`[WSL]` — push:

```bash
cd ~/devops-lab/05-cicd/bf05-ci
git remote add origin git@github.com:<github-user>/taskhub-ci-breakfix.git
git push -u origin main
```

Mở tab **Actions** của repo mới. Từ đây bắt đầu làm ticket.

> Tab Actions không có gì, không có cả thông báo lỗi? Kiểm tra **Settings → Actions → General** xem Actions có bị tắt cho repo không. Repo public mới tạo thường bật sẵn.

Kiểm tra tiến độ (kiểm tra tĩnh, không thay được lần chạy thật trên GitHub):

```bash
cd ~/devops-lab/05-cicd/bf05-ci
bash ~/devops-lab/05-cicd/tools/verify.sh           # kiểm tra file và lịch sử Git
bash ~/devops-lab/05-cicd/tools/verify.sh --lint    # thêm actionlint qua Docker (cần Docker Desktop đang chạy)
```

---

## 4. Công cụ bạn được dùng

| Mục đích | Ở đâu / lệnh |
|---|---|
| Danh sách lần chạy, trạng thái | `[GitHub]` tab **Actions** → chọn workflow **CI** |
| Lỗi file workflow, cảnh báo | Trang tóm tắt của lần chạy (summary) — khung **Annotations** |
| Log từng bước | Bấm vào job → mở từng step. Ô **Search logs** chỉ tìm trong step đang mở |
| Phiên bản image của runner, các container dịch vụ | Step **Set up job** và **Initialize containers** ở đầu log job |
| Tải toàn bộ log | Biểu tượng bánh răng ở góc trên log → **Download log archive**, rồi `grep` trên WSL |
| Artifact | Cuối trang tóm tắt của lần chạy, mục **Artifacts** |
| Chạy lại | **Re-run jobs** (chạy lại với **đúng commit cũ** — sửa file mà chưa push thì chạy lại vô ích) |
| Hủy lần chạy | **Cancel workflow** |
| Kiểm tra tĩnh workflow | `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:1.7.12 -color` (trong `bf05-ci`) |
| Tái hiện trên máy | Chạy đúng các lệnh `run:` của workflow trong `[WSL]`, ví dụ `cd app && ./mvnw -B -ntp verify` |
| Lịch sử, chế độ file trong Git | `git log --oneline`, `git show --stat`, `git ls-files -s <file>` |
| 🟨 Nếu đã cài GitHub CLI | `gh run list`, `gh run view <id> --log-failed` (không bắt buộc, không cần cài thêm cho bài này) |

**Vòng làm việc mỗi lần sửa:** sửa file → `git add` → `git commit` → `git push` → xem lần chạy mới trên Actions → đọc lỗi **đầu tiên** → lặp lại.

---

## 5. Các ticket

### 🎫 Ticket #6001 — P1 — CI chưa bao giờ xanh

> **Người báo:** Trưởng nhóm
> **Mô tả:** Push lên `main` thì tab Actions khi báo lỗi ngay, khi chạy mãi không xong. Không ai biết vì sao.
> **Kết quả mong đợi:** Push lên `main` → workflow **CI**, job `build-test` chạy hết và **xanh**, chạy đủ test (không bỏ qua test nào). Mở Pull Request vào `main` cũng phải kích hoạt CI.
> **Ghi chú:** Ticket này có **6 lỗi nối tiếp nhau** — sửa xong lỗi này mới lộ ra lỗi sau. Một phần nằm trong YAML, một phần **không** nằm trong YAML.

### 🎫 Ticket #6002 — P2 — Test đỏ mà không có báo cáo để xem

> **Người báo:** Dev team
> **Mô tả:** "Khi test đỏ, workflow có bước upload báo cáo test nhưng chưa bao giờ thấy artifact nào. Mà lần chạy cũng không báo lỗi gì ở bước đó."
> **Kết quả mong đợi:** Khi một test thất bại, lần chạy có artifact **`test-reports`** chứa các file báo cáo của Surefire (`TEST-*.xml`, `*.txt`).
> **Ghi chú:** 1 lỗi. Gợi ý nhỏ: bạn có thể nhìn thấy nó ngay trong lúc làm ticket #6001.

---

## 6. Luật chơi

1. **Không sửa code ứng dụng** trong `app/src/` — ngoại trừ phép thử có chủ đích ở mục 7 (và phải hoàn tác).
2. **Không đọc `verify.sh` và `setup.sh`** trước khi xong — chúng chứa đáp án.
3. **Không dùng AI.** Được dùng: log trên GitHub, docs GitHub Actions chính thức, README của từng action, các bài trong giáo trình.
4. **Không lách lỗi:** không `-DskipTests`, không `continue-on-error: true`, không xóa service `postgres`, không xóa bước upload báo cáo, không xóa test.
5. **Giữ các quyết định của dự án:** runner ghim `ubuntu-24.04` (không đổi sang `ubuntu-latest` — giải thích vì sao trong nhật ký), Java **21**, PostgreSQL **17**, action ghim SHA như hiện tại.
6. **Không commit secret thật** (mật khẩu, token) vào repo — repo này public.
7. Mỗi lỗi: ghi lại **dòng log hoặc thông báo đầu tiên** cho thấy lỗi, trước khi sửa.

---

## 7. Tiêu chí hoàn thành

Kiểm tra tĩnh `verify.sh` xanh mới chỉ là điều kiện cần. Bài **chỉ xong** khi cả ba điều sau đúng trên GitHub:

1. **Push lên `main`** → workflow **CI** xanh, step *Build and test* có dòng `Tests run: ..., Failures: 0, Errors: 0` và `BUILD SUCCESS`.
2. **Phép thử báo cáo test** (ticket #6002):

   ```bash
   cd ~/devops-lab/05-cicd/bf05-ci
   git switch -c test/fail-on-purpose
   # Sửa TẠM một assertion trong app/src/test/.../TaskControllerTest.java cho sai,
   # ví dụ đổi status().isNotFound() thành status().isOk() trong test getUnknownIdReturns404
   git commit -am "test: fail on purpose to check reports"
   git push -u origin test/fail-on-purpose
   ```

   `[GitHub]` mở Pull Request từ `test/fail-on-purpose` vào `main` → CI chạy **trên PR** → job đỏ → mục **Artifacts** có `test-reports` → tải về, mở được file báo cáo của test đã cố ý làm sai.
3. **Đóng PR đó, không merge.** Xóa nhánh (`git switch main && git branch -D test/fail-on-purpose && git push origin --delete test/fail-on-purpose`).

---

## 8. Sản phẩm phải nộp

Tạo file `~/devops-journey/week10/break-fix-ci-01.md` gồm:

1. **Timeline** các lỗi theo đúng thứ tự bạn gặp, kèm link (hoặc số thứ tự) lần chạy trên Actions.
2. Với **mỗi lỗi**, theo [mẫu nhật ký debug](../../../00-ROADMAP/templates/troubleshooting-journal-template.md):

   ```markdown
   ### Lỗi N: <tên ngắn>
   - Triệu chứng (dán nguyên dòng log / thông báo, exit code, trạng thái job):
   - Thấy ở đâu (annotation / step nào / dòng nào):
   - Phát hiện được trước khi push không? Bằng cách nào (actionlint, chạy lệnh trên máy, git ls-files...)?
   - Nguyên nhân gốc:
   - Cách sửa (file nào, dòng nào, trước/sau):
   - Vì sao trên laptop không gặp (nếu đúng như vậy):
   - Gặp lại ở đâu (taskhub thật / v3 deploy / Kubernetes):
   ```

3. Ảnh chụp hoặc link lần chạy xanh trên `main`, và lần chạy đỏ trên PR có artifact `test-reports`.
4. Kết quả `verify.sh --lint` cuối cùng (dán vào).
5. Bảng tổng kết: lỗi nào **actionlint bắt được trước khi push**, lỗi nào chỉ lộ ra khi chạy thật.
6. Một đoạn ngắn: **3 thói quen** bạn sẽ áp dụng ngay cho `.github/workflows/` của taskhub thật.

---

## 9. Gợi ý

Chỉ mở từng cấp khi đã thử ít nhất 15 phút ở cấp trước.

<details>
<summary>💡 Gợi ý cấp 1 — Hướng tiếp cận</summary>

- Không phải mọi lỗi đều tạo ra một job đỏ. Có lần chạy **không có job nào**, có job **không bao giờ bắt đầu**, có bước **xanh mà vẫn sai**. Hãy nhìn: trạng thái lần chạy, trạng thái job, rồi mới tới log.
- Lần chạy thất bại ngay mà không có job: đọc khung **Annotations** ở trang tóm tắt — GitHub ghi rõ dòng nào trong file YAML.
- Job hiện vòng tròn vàng mãi, log chỉ có một dòng chờ: job **chưa được máy nào nhận**. Câu hỏi: GitHub chọn máy chạy job dựa vào trường nào? Hủy lần chạy đó trước khi push bản sửa (đọc lại phần `concurrency` trong file để hiểu vì sao).
- Lỗi xảy ra trên runner nhưng `./mvnw` trên laptop vẫn chạy: GitHub **không** dùng thư mục làm việc của bạn, nó checkout **commit**. Thứ gì có trên đĩa của bạn nhưng không có (hoặc khác) trong commit?
- Exit code là manh mối: tra lại bảng exit code ở [Docker bài 08](../../../04-DOCKER/08-container-troubleshooting.md) và [Linux bài 06](../../../01-LINUX/06-bash-scripting.md).
- Với test cần database: bước job chạy **trực tiếp trên máy runner**, còn PostgreSQL chạy **trong container**. Đọc lại [Network bài 05](../../../02-NETWORKING/05-tcp-udp-ports-firewall.md) và [Docker bài 04](../../../04-DOCKER/04-volumes-networks-env.md): `localhost:5432` trên máy host tới được container khi nào?
- Lời nhắn bàn giao có nhắc tới "secrets". Repo này mới tạo — nó có secret nào chưa?
- Ticket #6002: đọc **toàn bộ** output của step upload kể cả dòng màu vàng, không chỉ nhìn dấu tích xanh.

</details>

<details>
<summary>💡 Gợi ý cấp 2 — Lệnh và chỗ cần nhìn</summary>

- Chạy actionlint trước mỗi lần push: `bash ~/devops-lab/05-cicd/tools/verify.sh --lint`. Nó bắt được ít nhất 2 lỗi mà không cần push.
- So nhãn runner với bảng nhãn chuẩn trong docs *GitHub-hosted runners* (mục Nguồn tham khảo).
- Chế độ file trong commit: `git ls-files -s app/mvnw` và `git ls-tree HEAD app/mvnw` — cột đầu là `100755` hay `100644`? Trên máy: `ls -l app/mvnw`.
- Step **Set up JDK**: dòng `Java ... was successfully installed` hoặc tương tự cho biết phiên bản nào được cài. So với `<java.version>` trong `app/pom.xml`.
- Step **Initialize containers**: xem lệnh `docker create` mà runner dùng cho service `postgres` — có `-p` (publish port) không? Dòng `postgres service is healthy` chỉ chứng minh PostgreSQL chạy, **không** chứng minh job kết nối tới được.
- Trong log Maven, đừng đọc stack trace từ trên xuống. Tìm dòng `Caused by:` **cuối cùng** ([Linux bài 07](../../../01-LINUX/07-logs-monitoring-troubleshooting.md)).
- Tái hiện lỗi database trên WSL bằng đúng giá trị của workflow:

  ```bash
  docker run -d --name bf05-pg -e POSTGRES_DB=taskhub -e POSTGRES_USER=taskhub \
    -e POSTGRES_PASSWORD=ci-only-password postgres:17          # cố ý KHÔNG có -p
  cd ~/devops-lab/05-cicd/bf05-ci/app
  SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/taskhub \
  SPRING_DATASOURCE_USERNAME=taskhub SPRING_DATASOURCE_PASSWORD= \
    ./mvnw -B -ntp verify
  docker rm -f bf05-pg                                          # dọn container thử
  ```

  (Nếu PostgreSQL khác đang chiếm 5432 trên WSL, kết quả sẽ khác — kiểm tra bằng `ss -ltn | grep 5432` trước.)
- Trong expression của GitHub Actions, secret **chưa được tạo** trả về giá trị gì? Docs *Using secrets in GitHub Actions* trả lời bằng một câu.
- Step upload: dòng cảnh báo in ra **đường dẫn nó đã tìm**. Đường dẫn đó được tính từ thư mục nào? `defaults.run.working-directory` áp dụng cho loại step nào?

</details>

<details>
<summary>💡 Gợi ý cấp 3 — Gần như đáp án</summary>

Thứ tự lỗi lộ ra (nếu bạn sửa đúng từng cái một):

1. `on:` có khóa `pull-request:` — tên sự kiện đúng là `pull_request`. GitHub coi cả file là không hợp lệ → lần chạy thất bại, không có job nào.
2. `runs-on: ubuntu-24.4` — không có runner nào mang nhãn đó → job nằm chờ mãi. Sửa thành `ubuntu-24.04` và hủy lần chạy cũ.
3. `app/mvnw` nằm trong commit với mode `100644` → `./mvnw: Permission denied`, exit code `126`. Sửa: `chmod +x app/mvnw` (hoặc `git update-index --chmod=+x app/mvnw`), rồi commit.
4. `java-version: '17'` trong khi project biên dịch cho Java 21 → Maven báo kiểu `release version 21 not supported`. Sửa thành `'21'`.
5. Service `postgres` thiếu `ports: - 5432:5432` → job (chạy trên host) gọi `localhost:5432` bị `Connection refused`.
6. `SPRING_DATASOURCE_PASSWORD: ${{ secrets.DB_PASSWORD }}` nhưng repo không có secret `DB_PASSWORD` → giá trị rỗng → PostgreSQL từ chối xác thực. Sửa: dùng cùng một giá trị cho cả hai phía (mật khẩu CI dùng một lần, giống [bản tham khảo](../reference/workflows/ci.yml)), **hoặc** tạo secret và dùng nó ở **cả** `POSTGRES_PASSWORD` lẫn `SPRING_DATASOURCE_PASSWORD`.
7. (Ticket #6002) `path: target/surefire-reports/` — bước `uses:` không chịu ảnh hưởng của `defaults.run.working-directory`, đường dẫn tính từ gốc repo → phải là `app/target/surefire-reports/`. Mặc định `if-no-files-found: warn` nên bước này vẫn xanh.

</details>

---

## 10. Dọn dẹp

Khi đã nộp nhật ký:

1. `[GitHub]` ⚠️ **Xóa repo luyện tập — không hoàn tác được.** Kiểm tra kỹ tên trên thanh địa chỉ là `taskhub-ci-breakfix`, **không phải** `taskhub`: **Settings → General → Danger Zone → Delete this repository**. Log, artifact và cache của repo bị xóa theo.
2. `[WSL]` ⚠️ Xóa thư mục làm bài (chỉ thư mục lab, kiểm tra lại đường dẫn trước khi Enter):

   ```bash
   ls ~/devops-lab/05-cicd/bf05-ci          # nhìn lại trước khi xóa
   rm -rf ~/devops-lab/05-cicd/bf05-ci
   ```

3. Nếu đã tạo secret `DB_PASSWORD` trong repo luyện tập: nó bị xóa cùng repo. Nếu bạn đã dùng một mật khẩu có ý nghĩa ở nơi khác — đừng làm vậy lần sau.

Muốn làm lại từ đầu: xóa thư mục như bước 2 rồi chạy lại `setup.sh` (repo GitHub cũng phải xóa hoặc tạo repo khác tên).

---

## Nguồn tham khảo

| Nguồn | Dùng cho | Kiểm tra ngày |
|---|---|---|
| [GitHub Docs — GitHub-hosted runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) | Bảng nhãn runner chuẩn (`ubuntu-24.04`, `ubuntu-26.04`, `ubuntu-latest`…) | 2026-10-31 |
| [GitHub Docs — Creating PostgreSQL service containers](https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers) | Job chạy trên runner phải map port, kết nối qua `localhost` | 2026-10-31 |
| [GitHub Docs — Using secrets in GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) | Secret chưa tạo → expression trả về chuỗi rỗng | 2026-10-31 |
| [GitHub Docs — Using workflow run logs](https://docs.github.com/en/actions/how-tos/monitor-workflows/use-workflow-run-logs) | Tìm trong log, tải log archive | 2026-10-31 |
| [actions/upload-artifact — README](https://github.com/actions/upload-artifact) | `if-no-files-found` mặc định `warn`; đường dẫn tương đối tính từ thư mục làm việc hiện tại | 2026-10-31 |
| [rhysd/actionlint — checks.md](https://github.com/rhysd/actionlint/blob/main/docs/checks.md) | Kiểm tra tên sự kiện, nhãn runner | 2026-10-31 |
| [rhysd/actionlint trên Docker Hub](https://hub.docker.com/r/rhysd/actionlint) | Tag `1.7.12` (30/03/2026) | 2026-10-31 |
| [GitHub Community #86984 — Typo in "runs-on"](https://github.com/orgs/community/discussions/86984) | Sai nhãn runner → job chờ runner vô thời hạn, không báo lỗi ngay | 2026-10-31 |
