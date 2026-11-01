# Lời giải — Bài 01: Khái niệm CI/CD

> Chỉ mở sau khi đã tự làm. Bài học: [01-cicd-concepts.md](../01-cicd-concepts.md).
> Câu trả lời của bạn không cần giống từng chữ — cần **đúng bản chất** và tự giải thích được.

## Mục lục

- [Câu hỏi trong phần thực hành](#câu-hỏi-trong-phần-thực-hành)
- [Mục 13 — Câu hỏi kiểm tra kiến thức](#mục-13--câu-hỏi-kiểm-tra-kiến-thức)
- [Mục 14 — Bài tập tự làm](#mục-14--bài-tập-tự-làm)

---

## Câu hỏi trong phần thực hành

### Bước 2

1. **`services` đứng trước `build-test`** vì `./mvnw verify` chạy cả test `@SpringBootTest` (`contextLoads`) — test này khởi động toàn bộ ứng dụng, gồm Flyway và kết nối database. Không có PostgreSQL thì test đó lỗi.
2. **Không.** `set -e` ở đầu script làm script dừng ngay khi một lệnh trả exit code khác 0. Trong `run_stage`, dòng `"$@"` gọi hàm của stage; hàm `stage_build_test` kết thúc bằng `./mvnw ...` trả `1` → `"$@"` trả `1` → script dừng, `trap cleanup EXIT` chạy, in `PIPELINE ĐỎ`. Dòng `run_stage package ...` không bao giờ được chạy tới.
3. Cú pháp `TÊN=giá-trị lệnh` chỉ đặt biến cho **riêng process đó** (`./mvnw` và các process con của nó). Lợi ích: biến chứa mật khẩu không "rò" sang các lệnh khác (`docker build`, `git`), phạm vi rõ ràng, giống cách GitHub Actions khai báo `env:` cho đúng job/step cần nó.

### Bước 7 — thiết kế tham khảo

| Sự kiện | Stage chạy | Push image? Tag gì? | Thời gian mục tiêu |
|---|---|---|---|
| PR vào `main` | checkout → build + test (có PostgreSQL) → build image → quét Trivy | **Không** push | < 10 phút |
| Push lên `main` (sau merge) | Như PR, cộng push | Có — `ghcr.io/<user>/taskhub:<sha7>` | < 10 phút |
| Push tag `v0.3.0` | Tìm image `:<sha7>` của commit được tag → gắn thêm tag `:v0.3.0` → tạo GitHub Release | Không build lại; thêm tag `:v0.3.0` cho image có sẵn | < 2 phút |
| 🟨 Hằng đêm | Quét lại image đang dùng bằng Trivy (cơ sở dữ liệu lỗ hổng cập nhật mỗi ngày, image cũ có thể lộ lỗ hổng mới) | Không | — |

1. **Không build lại.** Image đã được test và quét là image `:<sha7>`. Build lại có thể ra image khác (base image, thư viện đã đổi) → thứ phát hành chưa từng được kiểm tra. Release chỉ gắn thêm tên cho **chính** image đó.
2. Chỉ bước push trên `main` và job release cần quyền **ghi** registry. Test, build, quét trên PR chỉ cần quyền **đọc** code.
3. **Không.** Code từ fork là code của người lạ. Nếu PR từ fork được push image (hoặc được cấp token có quyền ghi), kẻ xấu có thể đẩy image độc hại lên registry của bạn hoặc đánh cắp token. GitHub mặc định không đưa secret và chỉ cấp token chỉ đọc cho workflow `pull_request` từ fork ([bài 04](../04-secrets-environments.md)).

Bản hiện thực hóa đầy đủ: [bản tham khảo](../labs/reference/README.md).

---

## Mục 13 — Câu hỏi kiểm tra kiến thức

**1.** "Integration hell" là tình trạng nhiều người làm riêng rẽ lâu ngày rồi mới ghép code: conflict lớn, lỗi chỉ lộ khi ghép, và vì có quá nhiều thay đổi cùng lúc nên rất khó tìm thay đổi nào gây lỗi. Tích hợp thường xuyên giảm rủi ro vì **mỗi lần ghép rất nhỏ**: conflict nhỏ, lỗi lộ ra ngay khi người viết còn nhớ code, và khi đỏ thì chỉ có vài commit để nghi ngờ. Tổng công sức ghép giảm, vì chi phí sửa lỗi tăng rất nhanh theo thời gian lỗi tồn tại.

**2.** Không, hoặc chỉ làm một nửa. Họ có **công cụ** tự động build/test, nhưng CI là **thực hành tích hợp thường xuyên** vào nhánh chính. Nhánh sống 3 tuần nghĩa là 3 tuần không tích hợp → vẫn gặp đủ vấn đề của tích hợp muộn khi merge. Pipeline chỉ cho biết nhánh đó tự nó có xanh hay không, không cho biết nó có ghép được với thay đổi của người khác hay không.

**3.** Continuous Delivery: mọi thay đổi qua pipeline đều **sẵn sàng** lên production, nhưng **người** quyết định lúc nào lên. Continuous Deployment: mọi thay đổi qua pipeline **tự động** lên production, không có cổng duyệt. `taskhub` v1 dừng ở việc build, test, quét và **publish image** lên GHCR, không deploy — tức là **CI cộng với bước đầu của Continuous Delivery** (artifact bất biến luôn sẵn sàng). Chưa phải Continuous Deployment.

**4.** Artifact là thứ pipeline tạo ra để dùng ở bước sau hoặc để triển khai. Ở `taskhub`: file `app.jar` (trung gian, chỉ sống trong lúc build image), **Docker image `ghcr.io/<user>/taskhub:<sha7>`** (**artifact triển khai** — thứ duy nhất chạy ở mọi môi trường), báo cáo test `surefire-reports` (để đọc khi đỏ).

**5.** Build một lần, lưu artifact với tên bất biến, rồi đưa **chính artifact đó** qua mọi môi trường. Cách vi phạm dù cùng commit: build image riêng cho staging và production vào hai thời điểm khác nhau — base image `eclipse-temurin:21-jre-noble` hoặc thư viện có thể đã được cập nhật giữa hai lần build → hai image khác nhau, image chạy production chưa từng được test. Một cách vi phạm khác: `git pull` rồi `docker build` ngay trên server production.

**6.** Máy mới mỗi lần để kết quả **tái lập được** và **an toàn**. Lợi ích: không có rác của lần chạy trước (kết quả không phụ thuộc lịch sử); phát hiện ngay phụ thuộc ngầm vào thứ chỉ có trên máy dev; một lần chạy bị chiếm quyền không ảnh hưởng lần sau. Cái giá: phải tải lại thư viện và base image mỗi lần (giảm bằng cache); không có sẵn database hay dịch vụ phụ (giảm bằng service container); không giữ file giữa các job (giảm bằng artifact).

**7.** Job là đơn vị chạy trên **một máy**; step là từng lệnh/action **tuần tự** bên trong job, dùng chung máy và thư mục. File tạo ở job A **không** tự có ở job B, vì B chạy trên máy khác. Muốn dùng phải upload artifact ở A rồi download ở B (hoặc build lại ở B).

**8.** Để giả lập runner: bản clone chỉ có commit HEAD, **không** có file sửa chưa commit, file chưa `git add`, file trong `.gitignore`, hay file rác `target/` của lần build trước. Chạy thẳng trong `~/projects/taskhub` thì kết quả có thể xanh nhờ những thứ runner không bao giờ có — đúng là bẫy "máy tôi chạy được".

**9.** Mỗi bước được đánh giá bằng exit code: `0` = thành công, khác `0` = thất bại → pipeline đỏ và dừng. Script không có `set -e` sẽ chạy tiếp sau lệnh lỗi, và exit code cuối cùng chỉ là của **lệnh cuối** — nếu lệnh cuối thành công (ví dụ `echo "done"`), pipeline báo **xanh giả** dù build hỏng. (GitHub Actions mặc định chạy bước `run:` bằng `bash -e` — bạn sẽ kiểm chứng ở bài 02.)

**10.** Fail fast: xếp các bước **rẻ và hay lỗi** lên trước để phát hiện lỗi sớm nhất với chi phí nhỏ nhất. Test (khoảng 1 phút) chạy trước build image (vài phút) vì test hay đỏ hơn, và image của code chưa qua test thì cũng không được push — build nó trước chỉ phí thời gian.

**11.** Tác hại: dev chuyển sang việc khác khi chờ, quay lại thì mất ngữ cảnh; họ bắt đầu merge khi CI chưa xong hoặc gộp nhiều thay đổi vào một PR cho đỡ chờ → mất đúng lợi ích của CI; lead time tăng. Kỹ thuật: cache (Maven, layer Docker); fail fast (bước rẻ lên trước); chạy song song các job độc lập; chỉ chạy job liên quan đến phần thay đổi (`paths:`); dời test rất chậm (end-to-end) sang chạy trên `main` hoặc hằng đêm; hủy lần chạy cũ khi PR có commit mới (`concurrency`).

**12.** Đưa kiểm tra bảo mật về **sớm** trong vòng đời (phía "trái" của trục từ lúc viết code đến production), vì sửa lúc PR rẻ hơn rất nhiều so với sửa sau sự cố. Ví dụ ở `taskhub`: quét image bằng Trivy trước khi push, chặn lỗ hổng CRITICAL đã có bản vá; `permissions` tối thiểu cho token của pipeline; không để secret trong YAML; Dependabot mở PR cập nhật action/thư viện/base image.

**13.** Có lịch sử (ai đổi gì, khi nào, vì sao); được review qua PR như code; đi cùng phiên bản code (commit cũ build bằng pipeline của thời điểm đó); khôi phục được bằng `git revert`; tạo lại pipeline cho repo mới chỉ cần copy file. Cấu hình bằng giao diện web thì không có các điều này, và thường chỉ một người biết nó được cấu hình thế nào.

**14.** Theo dora.dev (2026-10-31), 5 chỉ số. **Tốc độ**: change lead time, deployment frequency, failed deployment recovery time. **Độ ổn định**: change fail rate, deployment rework rate. "Four keys" cũ gồm deployment frequency, lead time for changes, change failure rate và MTTR (mean time to restore). Năm 2023, MTTR được thay bằng failed deployment recovery time (chỉ tính khôi phục sau deploy hỏng); năm 2024 thêm deployment rework rate.

**15.** `Failures`: test **chạy xong** nhưng assert không đạt — kết quả sai → thường nhìn vào **code** (hoặc test viết sai). `Errors`: test **ném exception**, không chạy xong — thường do **môi trường** (không kết nối được database, thiếu cấu hình, thiếu biến môi trường) → nhìn vào log `Caused by:` và cấu hình trước.

---

## Mục 14 — Bài tập tự làm

### Bài 1 — Phân loại

| | Loại | Lý do |
|---|---|---|
| a | **CI** (chưa phải CD) | PR được test tự động. Nhưng artifact được build tay sau merge → không có artifact sẵn sàng tự động, không phải Continuous Delivery |
| b | **Continuous Deployment** | Từ merge tới production hoàn toàn tự động, không cổng duyệt |
| c | **Continuous Delivery** | Tự động tới staging, artifact sẵn sàng; production cần người bấm duyệt |
| d | **Không phải CI** | Không có tích hợp tự động; test phụ thuộc vào việc từng người có nhớ chạy hay không, và chạy trên máy không sạch |
| e | **Không thật sự là CI** | Có build tự động ("nightly build") nhưng nhánh sống 2–3 tuần → tích hợp muộn; phản hồi chậm 1 ngày |
| f | **CI + artifact sẵn sàng**; gần Continuous Delivery | Image được publish tự động. Nếu script deploy chạy được an toàn **bất cứ lúc nào** (lịch thứ Năm chỉ là quyết định kinh doanh) thì đó là Continuous Delivery. Nếu deploy cần nhiều bước tay dễ sai, thì chưa đạt |

### Bài 2 — Tính chỉ số DORA

Lead time từng lần (merge → deploy):

| # | Lead time |
|---|---|
| 1 | 2 giờ |
| 2 | 20 giờ (14:00 T2 → 10:00 T3) |
| 3 | 1 giờ |
| 4 | 1 giờ |
| 5 | 24 giờ |
| 6 | 2 giờ |
| 7 | 18 giờ (15:00 T3 → 09:00 T4) |
| 8 | 1 giờ |
| 9 | 1 giờ |
| 10 | 1 giờ |

- **Deployment frequency:** 10 lần / 2 tuần = **5 lần/tuần**, khoảng 1 lần mỗi ngày làm việc.
- **Change lead time:** sắp xếp: 1, 1, 1, 1, 1, 2, 2, 18, 20, 24. Tổng 71 giờ → **trung bình 7,1 giờ**. **Trung vị** = (1 + 2) / 2 = **1,5 giờ**. Khác nhau nhiều vì 3 giá trị ngoại lai (18, 20, 24 giờ) kéo trung bình lên; phần lớn thay đổi thật ra lên production trong 1–2 giờ. Đây là lý do báo cáo thường dùng trung vị: một vài trường hợp bất thường không làm méo bức tranh chung.
- **Change fail rate:** 2 lần lỗi (#3, #7) / 10 = **20%**.
- **Failed deployment recovery time:** #3: 11:00 → 11:30 = **30 phút** (rollback). #7: 09:00 → 13:00 = **4 giờ** (chờ hotfix). Trung bình 2 giờ 15 phút.
- **Deployment rework rate:** 1 lần deploy ngoài kế hoạch do sự cố (#8) / 10 = **10%**.

**Đề xuất có tác động lớn nhất:** quy định **"rollback trước, sửa sau"**. Số liệu cho thấy rollback khôi phục trong 30 phút, còn chờ hotfix mất 4 giờ — gấp 8 lần. Nếu #7 được rollback ngay, recovery time trung bình còn khoảng 30 phút, và hotfix #8 được làm bình tĩnh như một thay đổi bình thường thay vì một lần deploy ngoài kế hoạch dưới áp lực. Điều kiện để làm được: image có tag bất biến, bản trước còn trên registry ([bài 05](../05-deployment-strategies-rollback.md)).

Đáp án khác cũng chấp nhận được nếu lập luận bằng số liệu: ví dụ **tự động deploy ngay sau merge**. Ba lead time ngoại lai đều là thay đổi merge buổi chiều rồi chờ tới sáng hôm sau mới deploy; tự động hóa sẽ cắt các khoảng chờ này và đưa trung bình về gần trung vị.

### Bài 3 — Sắp xếp lại pipeline chậm

Hiện tại tuần tự: 6 + 8 + 1 + 2 + 1 + 2 = **20 phút**, và lint (bước hay đỏ nhất) chạy gần cuối.

Đề xuất cho PR:

```text
 Giai đoạn 1 (song song):  Lint (1')  │  Unit test (2')          → 2 phút
 Giai đoạn 2 (song song):  Test tích hợp (8')  │  Build image (6') → Quét image (2')   → 8 phút
 Tổng tối thiểu cho PR ≈ 10 phút (chưa tính cache — có cache layer, build image còn nhỏ hơn nhiều)
 Push image: KHÔNG chạy trên PR, chỉ chạy trên main sau khi mọi bước xanh
```

Lý do:

- **Lint và unit test lên đầu:** rẻ nhất và hay đỏ nhất (20% và 15%) — phát hiện trong 2 phút thay vì 20.
- **Chạy song song** các bước không phụ thuộc nhau: lint và unit test; test tích hợp và nhánh build → quét image.
- **Quét phụ thuộc vào build image** nên đi ngay sau nó.
- **Push không chạy trên PR:** image của PR chưa được review và chưa merge, không nên có trên registry; PR từ fork tuyệt đối không được có quyền ghi registry.
- Nếu muốn tiết kiệm tài nguyên hơn tốc độ, có thể cho giai đoạn 2 chờ giai đoạn 1 xanh (như đề xuất trên) — đó là cách `taskhub` làm (`image` chờ `build-test`).

### Bài 4 — Tìm vi phạm

1. **Server Jenkins dùng 2 năm không cài lại:** runner không sạch, kết quả phụ thuộc rác tích lũy; nếu bị chiếm quyền thì kẻ tấn công ở lại lâu dài.
2. **Build mỗi tối** thay vì mỗi lần push/PR: phản hồi chậm 1 ngày, không phải CI đúng nghĩa.
3. **Tag `latest`:** tag bị ghi đè mỗi đêm → không biết image nào ứng với code nào, không rollback được.
4. **Production `git pull` rồi `docker build`:** vi phạm "build một lần" — image production chưa từng được test; server production phải có source code và công cụ build.
5. **Deploy bằng SSH tay:** dễ sai bước, không có lịch sử ai deploy gì, khi nào; phụ thuộc vào một người.
6. **Mật khẩu registry ghi trong cấu hình job:** secret dạng văn bản thường, ai đọc được cấu hình là lấy được; phải dùng cơ chế quản lý secret (credentials store của Jenkins, GitHub Secrets).
7. Không thấy bước test hay quét bảo mật nào trong quy trình.

### Bài 5 — Thêm stage `scan`

```bash
stage_scan() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$HOME/.cache/trivy:/root/.cache/" \
    aquasec/trivy:0.76.1 image \
      --severity CRITICAL \
      --ignore-unfixed \
      --exit-code 1 \
      "taskhub:ci-local-${SHA7}"
}
```

Thêm dòng cuối script:

```bash
run_stage scan stage_scan
```

| Cờ | Vai trò |
|---|---|
| `--severity CRITICAL` | Chỉ xét lỗ hổng mức CRITICAL |
| `--ignore-unfixed` | Bỏ qua lỗ hổng chưa có bản vá — chặn những thứ bạn **có thể** sửa (rebuild với base image mới) |
| `--exit-code 1` | Mặc định Trivy trả `0` dù tìm thấy lỗ hổng. Cờ này làm Trivy trả `1` khi có lỗ hổng khớp điều kiện → `set -e` dừng pipeline |
| `-v $HOME/.cache/trivy:...` | Giữ cơ sở dữ liệu lỗ hổng giữa các lần chạy |

Thời gian: lần đầu lâu hơn rõ rệt vì Trivy tải cơ sở dữ liệu lỗ hổng (vài trăm MB); các lần sau chỉ còn vài giây đến vài chục giây. Trên GitHub Actions, runner mới cũng phải tải lại mỗi lần — trừ khi có cache.

Muốn tận mắt thấy cổng chặn hoạt động: tạm đổi thành `--severity HIGH,CRITICAL` và bỏ `--ignore-unfixed`. Base image thường có vài lỗ hổng HIGH chưa có bản vá, nên nhiều khả năng stage sẽ đỏ (không chắc chắn — phụ thuộc thời điểm bạn quét). Nhớ đổi lại sau khi thử.

### Bài 6 — Trình bày (bài mẫu)

> "CI/CD là tự động hóa con đường từ lúc dev viết code đến lúc code chạy cho người dùng. CI — tích hợp liên tục — nghĩa là mọi người đưa thay đổi nhỏ vào nhánh chính thường xuyên, và mỗi lần như vậy một máy sạch tự build và chạy test. Nếu đỏ, thay đổi không được merge. CD là phần tiếp theo: tự đóng gói thành artifact có tên cố định — với em là Docker image gắn tag theo commit — rồi đưa nó lên các môi trường.
>
> Team 3 người vẫn cần, vì ba lý do. Một, người ít nên không ai có thời gian làm tay mười bước mỗi lần release, và làm tay thì sớm muộn cũng quên một bước. Hai, CI chạy trên máy sạch, nên bắt được lỗi kiểu 'máy em chạy được' trước khi lên server. Ba, khi có sự cố, artifact bất biến cho phép quay về bản trước trong vài phút. Ở dự án taskhub, PR nào cũng phải qua build, test với PostgreSQL thật, quét lỗ hổng image; merge xong thì image được đẩy lên GHCR với tag là SHA commit."

Tiêu chí tự chấm: có định nghĩa CI và CD; có ít nhất 2 lý do cụ thể; có ví dụ từ dự án của bạn; mọi thuật ngữ (artifact, tag bất biến, máy sạch) bạn giải thích được nếu bị hỏi lại.
