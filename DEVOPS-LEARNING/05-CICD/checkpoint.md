# Checkpoint Giai đoạn 5 — CI/CD với GitHub Actions

> ⏱️ Tổng ~4,5 giờ (nên chia 2 buổi) · Làm vào cuối tuần 10
> Bao phủ: Module 05 bài [01](01-cicd-concepts.md)–[05](05-deployment-strategies-rollback.md), phần GitLab CI của bài [06](06-jenkins-gitlab-overview.md), [Lab 01](labs/lab-01-ci-pr-gate.md), [Lab 02](labs/lab-02-release-ghcr.md)
> Lời giải: [solutions/checkpoint-solutions.md](solutions/checkpoint-solutions.md) — **chỉ mở sau khi đã nộp bài cho chính mình** (commit vào repo).

## Mục lục

- [Quy tắc](#quy-tắc)
- [Phần A — Lý thuyết (45 phút)](#phần-a--lý-thuyết-45-phút)
- [Phần B — Thực hành (120 phút)](#phần-b--thực-hành-120-phút)
- [Phần C — Break-fix (90 phút)](#phần-c--break-fix-90-phút)
- [Tiêu chí đạt](#tiêu-chí-đạt)
- [Nếu chưa đạt](#nếu-chưa-đạt)

---

## Quy tắc

1. **Không dùng AI và không xem lời giải** trong lúc làm.
2. **Được phép**: tài liệu chính thức GitHub Actions (docs.github.com), README của từng action trên GitHub, tài liệu Docker và Trivy, các bài học Module 03–05. **Không** được mở [file workflow tham khảo](labs/reference/README.md) của taskhub — nhưng được xem **bảng SHA** trong file đó.
3. Tự bấm giờ cho từng phần. Phần B và C có thời gian chờ runner — vẫn tính vào giờ làm bài. Hết giờ thì dừng và ghi lại mình đang ở đâu.
4. Nộp bài: tạo thư mục `~/devops-journey/week10/checkpoint/` gồm `part-a.md`, `part-b.md` (link repo, link các lần chạy workflow, kết quả kiểm thử), `part-c.md` (nhật ký debug). Commit **trước** khi mở lời giải.
5. Phần B và C dùng **repo public dùng một lần** trên tài khoản GitHub của bạn. Hosted runner chạy miễn phí cho repo public — không phát sinh chi phí. Không đưa secret thật nào vào hai repo này.

---

## Phần A — Lý thuyết (45 phút)

Trả lời ngắn bằng lời của bạn (2–6 câu mỗi câu). Giải thích **bản chất**, không chép định nghĩa.

1. Phân biệt Continuous Integration, Continuous Delivery và Continuous Deployment. Pipeline của taskhub v1 đang ở mức nào, và còn thiếu gì để lên mức tiếp theo?
2. Một workflow GitHub Actions gồm workflow, event, job, step, runner. Hai **job** khác nhau có dùng chung file vừa build không? Hai **step** trong cùng một job thì sao? Vì sao?
3. Một bước `run:` có 3 lệnh, lệnh thứ hai lỗi (exit code 1). Lệnh thứ ba có chạy không, và vì sao? Điều gì khác đi nếu lệnh lỗi nằm **trước dấu `|`** trong một pipe?
4. **Cache** và **artifact** khác nhau thế nào về mục đích và vòng đời? Với taskhub, thứ gì nên là cache, thứ gì nên là artifact? Khóa cache của `setup-java` với `cache: maven` được tính từ những file nào — và điều gì xảy ra khi bạn sửa `pom.xml`?
5. `GITHUB_TOKEN` là gì, sống bao lâu? Vì sao workflow của taskhub khai báo `permissions: contents: read` ở đầu file, và chỉ job cần push image mới có `packages: write`? Điều gì xảy ra nếu job push thiếu quyền đó?
6. Vì sao job test của taskhub nối PostgreSQL qua `localhost:5432`, trong khi trong Docker Compose ứng dụng lại nối qua `postgres:5432`? Service container được dọn đi lúc nào?
7. Mô tả luồng từ lúc PR được mở đến lúc image `ghcr.io/<user>/taskhub:<sha7>` xuất hiện trên GHCR. Vì sao trên PR **không** push image? Vì sao quét Trivy đặt **trước** bước push?
8. "Build một lần, triển khai nhiều nơi" nghĩa là gì? Workflow release của taskhub áp dụng nguyên tắc này thế nào khi bạn push tag `v0.3.0`? Vì sao tag image SHA và SemVer phải **bất biến**?
9. Tháng 3/2026, 76/77 tag của `aquasecurity/trivy-action` bị push đè thành mã độc. Workflow ghi tag phiên bản (ví dụ `uses: aquasecurity/trivy-action@0.34.0` — thời đó tag chưa có tiền tố `v`) bị ảnh hưởng thế nào? Workflow ghim SHA đầy đủ thì sao? Ghim SHA có nhược điểm gì, và bạn khắc phục nhược điểm đó bằng công cụ nào?
10. Vì sao `run: echo "${{ github.event.pull_request.title }}"` là lỗ hổng? Viết lại cho an toàn và giải thích vì sao cách mới an toàn.
11. Phân biệt **secret** và **variable** (`vars`). Vì sao workflow chạy từ PR của một **fork** không đọc được secret? GitHub Environment thêm được lớp bảo vệ nào cho bước deploy?
12. So sánh recreate, rolling, blue/green, canary theo: có downtime không, cần bao nhiêu tài nguyên, rollback nhanh cỡ nào. taskhub chạy trên 1 EC2 bằng Compose (v2–v3) phù hợp chiến lược nào, vì sao?
13. Bản `v0.4.0` lỗi sau khi deploy. Mô tả rollback bằng image tag. Vì sao một migration Flyway **xóa cột** khiến rollback ứng dụng không còn đơn giản? Nêu cách viết migration để rollback vẫn an toàn.
14. Đọc đoạn GitLab CI sau và trả lời: job chạy khi nào, chạy trong gì, tương ứng gì ở GitHub Actions?

    ```yaml
    unit-test:
      stage: test
      image: python:3.12-slim
      rules:
        - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      script:
        - python -m unittest discover -s tests
    ```

---

## Phần B — Thực hành (120 phút)

### Bối cảnh

Dịch vụ `notes` (Python, thư viện chuẩn, SQLite) đã được bạn container hóa ở [Checkpoint Docker — Phần B](../04-DOCKER/checkpoint.md#phần-b--thực-hành-90-phút). Team muốn nó có CI/CD theo đúng chuẩn của taskhub. Bạn viết **từ đầu**, không sao chép workflow của taskhub.

### Chuẩn bị `[WSL]`

```bash
mkdir -p ~/devops-lab/05-cicd && cd ~/devops-lab/05-cicd
cp -r ~/notes-service ck05-notes          # repo từ Checkpoint Docker (có Dockerfile của bạn)
cd ck05-notes
git status                                 # sạch, đang ở main
```

Nếu không còn `~/notes-service`: copy mã nguồn từ `04-DOCKER/labs/checkpoint/part-b/`, lấy Dockerfile ở [lời giải Checkpoint Docker](../04-DOCKER/solutions/checkpoint-solutions.md), rồi `git init -b main` và commit.

Trên GitHub `[GitHub]`: tạo repo **public** `ck05-notes` (không tạo README), rồi:

```bash
git remote add origin git@github.com:<github-user>/ck05-notes.git
git push -u origin main
```

### Đề bài

**1. `.github/workflows/ci.yml`** — chạy khi có PR vào `main` và khi push vào `main`:

- Job `test`: Python 3.12; **lint** bằng `python -m py_compile notes.py`; **test** bằng `python -m unittest discover -s tests -v`.
- Job `image`: chỉ chạy khi `test` xanh; build image từ Dockerfile của bạn và **chặn** (job đỏ) nếu Trivy thấy lỗ hổng **CRITICAL đã có bản vá**. Job này **không push** gì.
- Push commit mới vào cùng một PR → lần chạy cũ của PR đó bị hủy. Lần chạy trên `main` không bị hủy.

**2. `.github/workflows/release.yml`** — chạy **chỉ** khi push tag dạng `v*.*.*`:

- Build image, quét Trivy (cùng ngưỡng như CI), **chỉ khi sạch** mới push lên `ghcr.io/<owner-chữ-thường>/notes` với **hai tag**: tên Git tag (ví dụ `v1.0.0`) và 7 ký tự đầu của SHA commit.
- Không bao giờ push tag `latest`.

**3. Yêu cầu chung cho cả hai file:**

- `permissions:` ở cấp workflow chỉ `contents: read`; **chỉ** job push image có thêm `packages: write`.
- Mọi `uses:` ghim bằng **SHA commit đầy đủ (40 ký tự)** kèm ghi chú phiên bản (`# vX.Y.Z`). Bạn tự tra SHA bằng `git ls-remote` (nhớ trường hợp tag có chú thích).
- `runs-on: ubuntu-24.04`, mọi job có `timeout-minutes`.
- Không chèn trực tiếp `${{ github.event.* }}` hay `${{ github.head_ref }}` vào `run:`.
- Mỗi file có comment giải thích các quyết định chính.

**4. Bảo vệ `main`** của `ck05-notes`: bắt buộc PR, bắt buộc check `test` và `image` xanh.

**5. Làm việc qua PR:** đưa hai workflow vào bằng nhánh `ci/add-workflows` + Pull Request.

### Kiểm thử bắt buộc

Ghi lệnh, link lần chạy và kết quả vào `part-b.md`:

| # | Kiểm thử | Kết quả mong đợi |
|---|---|---|
| 1 | `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest -color` | Không có lỗi nào |
| 2 | `grep -c 'uses:' .github/workflows/*.yml` và `grep -cE 'uses: [^@]+@[0-9a-f]{40} # v' .github/workflows/*.yml` | Hai con số **bằng nhau** cho từng file |
| 3 | Trên PR: đổi tạm `"mua sua"` thành `"mua"` trong `test_strips_whitespace`, push | Job `test` đỏ, job `image` **không chạy** (skipped), nút merge bị chặn |
| 4 | Khôi phục test, push thêm **2 commit liên tiếp** thật nhanh | Lần chạy của commit trước bị hủy (*cancelled*), lần chạy mới nhất xanh |
| 5 | Merge PR; xem lần chạy CI trên `main` | Xanh; log job `image` cho thấy **không có** bước push nào; GHCR chưa có package `notes` |
| 6 | `git tag -a v1.0.0 -m "Release v1.0.0" && git push origin v1.0.0` | Workflow Release xanh; trang Packages có `notes` với tag `v1.0.0` và tag 7 ký tự SHA |
| 7 | `docker buildx imagetools inspect ghcr.io/<owner>/notes:v1.0.0` và `…:<sha7>` (đặt package public hoặc `docker login ghcr.io` trước) | Cùng một digest |
| 8 | Chỉ ra trong log job `publish`/`release` dòng quét Trivy và dòng push, theo đúng thứ tự | Quét **trước**, push **sau** |

Dọn dẹp (tùy chọn, sau khi đã ghi kết quả): xóa package `notes` (Package settings → Delete) và repo `ck05-notes` (Settings → Danger Zone).

---

## Phần C — Break-fix (90 phút)

### Khởi tạo `[WSL]`

```bash
mkdir -p ~/devops-lab/05-cicd && cd ~/devops-lab/05-cicd
cp -r /mnt/d/HocDepOps/DEVOPS-LEARNING/05-CICD/labs/checkpoint ck05-reports
cd ck05-reports
find . -type f -exec sed -i 's/\r$//' {} +
mv logs ../ck05-logs                       # log để đọc, không đưa vào repo
git init -b main && git add . && git commit -m "chore: import reports service"

docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest -color   # kiểm tra tĩnh bất cứ lúc nào
```

Trên GitHub `[GitHub]`: tạo repo **public** `ck05-reports`, `git remote add origin …`, `git push -u origin main`. Kiểm chứng bản sửa của bạn bằng lần chạy **thật**, không chỉ bằng actionlint.

### Bối cảnh

Dịch vụ `reports` có hai workflow: `CI` (job `test`, `image`) và `Release` (job `publish`). Tuần trước một đồng nghiệp "dọn dẹp" workflow: đổi tên job `build` thành `test` cho đúng nghĩa, in thông điệp commit ra log cho dễ theo dõi, và thêm điều kiện "chỉ release từ main". Từ đó mọi thứ hỏng. Log thu thập được nằm trong `../ck05-logs/` (là **minh họa** — chữ trên máy bạn có thể khác một chút).

### Các ticket

| Ticket | Mô tả | Log | Kết quả mong đợi |
|---|---|---|---|
| 🎫 #7001 | PR mới không chạy CI, nút merge bị chặn mãi ở trạng thái chờ | `01-ci-pr-17.txt` | PR có đủ check `test` và `image`, đều xanh |
| 🎫 #7002 | Sau khi merge một PR, CI trên `main` đỏ ở bước *Build image* dù PR đó xanh; chạy lại vẫn đỏ | `02-ci-main-push.txt` | Push lên `main` một commit có thông điệp chứa dấu `"` và `(` → CI xanh. Giải thích được vì sao đây là **lỗ hổng bảo mật**, không chỉ là lỗi |
| 🎫 #7003 | Push tag `v1.4.0` nhưng không có image nào được phát hành | `03-release-v1.4.0.txt` | Tag trên commit của `main` → job `publish` chạy. **Vẫn giữ ý định** "chỉ release code đã nằm trên main": tag trên commit **không** thuộc `main` → job đỏ với thông báo rõ ràng |
| 🎫 #7004 | Khi job `publish` chạy được thì đỏ ở bước push: `denied` dù đã `Login Succeeded` | `04-release-v1.4.1.txt` | `ghcr.io/<owner>/reports:<tag>` xuất hiện trên GHCR; `/health` của image trả đúng phiên bản |

### Luật chơi

- **Chỉ sửa** `.github/workflows/ci.yml` và `.github/workflows/release.yml`. Không sửa `app.py`, `tests/`, `Dockerfile`.
- **Không** tạo PAT hay secret mới; **không** dùng `permissions: write-all`; **không** bỏ bước Trivy; **không** bỏ ghim SHA.
- Sửa đúng chỗ, tối thiểu cần thiết, giải thích được.
- Nếu Trivy đỏ vì một lỗ hổng CRITICAL **mới công bố** trong base image (không phải lỗi cài sẵn): ghi lại CVE, rebuild lại sau, không tính là lỗi của bạn.
- Ghi nhật ký debug cho **từng ticket** vào `part-c.md`: triệu chứng → giả thuyết → bằng chứng (dòng log, dòng YAML, kết quả actionlint, link lần chạy) → nguyên nhân gốc → cách sửa → cách kiểm chứng. Nêu rõ lỗi nào actionlint bắt được, lỗi nào chỉ lộ ra khi chạy thật — và vì sao.

Dọn dẹp sau khi xong (tùy chọn): xóa package `reports` và repo `ck05-reports` trên GitHub; ⚠️ `rm -rf ~/devops-lab/05-cicd/ck05-reports ~/devops-lab/05-cicd/ck05-logs` chỉ khi đã commit nhật ký vào `devops-journey`.

---

## Tiêu chí đạt

| Phần | Đạt khi | Trọng số |
|---|---|---|
| A | ≥ 11/14 câu đúng **bản chất** (tự chấm theo lời giải, trung thực). Câu 5, 9 và 13 **bắt buộc đúng** | 30% |
| B | Qua cả 8 kiểm thử trong 120 phút; hai workflow có comment giải thích quyết định chính | 35% |
| C | Đủ 4 ticket đạt "kết quả mong đợi" bằng **lần chạy thật** trong 90 phút, actionlint sạch, **và** nhật ký nêu được **cách tìm ra** từng lỗi | 35% |

**Đạt Checkpoint** khi đạt cả 3 phần → tick vào checklist [Module 05](README.md) và cập nhật [ma trận kỹ năng](../00-ROADMAP/skill-matrix.md#cicd).

---

## Nếu chưa đạt

Không chuyển sang Module 06 ngay (xem [quy tắc khi chậm tiến độ](../00-ROADMAP/weekly-study-plan.md#5-quy-tắc-khi-bị-chậm-tiến-độ)). Module 06 cần pipeline v1 chạy ổn để làm CD ở tuần 13.

| Sai ở | Ôn lại |
|---|---|
| Câu A1, A8 | [Bài 01 — Khái niệm CI/CD](01-cicd-concepts.md) |
| Câu A2–A4, A6, kiểm thử B3, B4, ticket #7001 | [Bài 02 — GitHub Actions cơ bản](02-github-actions-basics.md), [Lab 01](labs/lab-01-ci-pr-gate.md) |
| Câu A7, A8, kiểm thử B5–B8 | [Bài 03 — Build & push image](03-github-actions-docker-registry.md), [Lab 02](labs/lab-02-release-ghcr.md) |
| Câu A5, A9–A11, kiểm thử B1, B2, ticket #7002, #7004 | [Bài 04 — Secrets, permissions, environments](04-secrets-environments.md) |
| Câu A12, A13, ticket #7003 (ý định "chỉ từ main") | [Bài 05 — Chiến lược triển khai & rollback](05-deployment-strategies-rollback.md) |
| Câu A14 | [Bài 06 — Jenkins & GitLab CI](06-jenkins-gitlab-overview.md) |
| Không biết bắt đầu Phần C từ đâu | [Break-fix #1](labs/break-fix-01/README.md), [Docker bài 08 — quy trình debug](../04-DOCKER/08-container-troubleshooting.md) |

Ôn xong 2–3 ngày rồi làm lại phần chưa đạt (Phần C: copy lại thư mục `labs/checkpoint` từ giáo trình để có lỗi ban đầu, tạo repo mới).
