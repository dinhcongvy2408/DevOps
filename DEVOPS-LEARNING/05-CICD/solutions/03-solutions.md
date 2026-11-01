# Lời giải — Bài 03: Build image, quét lỗ hổng và đẩy lên registry

> ⚠️ Chỉ đọc sau khi đã tự làm. Câu trả lời khác nhưng lập luận đúng vẫn tính là đạt. Đầu ra mẫu là minh họa; username `phuong-dev` là ví dụ.

Quay lại bài: [03-github-actions-docker-registry.md](../03-github-actions-docker-registry.md)

## Mục lục

- [Phần A — Câu hỏi kiểm tra kiến thức (mục 13)](#phần-a--câu-hỏi-kiểm-tra-kiến-thức-mục-13)
- [Phần B — Bài tập tự làm (mục 14)](#phần-b--bài-tập-tự-làm-mục-14)

---

## Phần A — Câu hỏi kiểm tra kiến thức (mục 13)

**1. Ba lý do build image trong CI.**
(1) Build từ **đúng một commit** trên máy sạch — không có file chưa commit, không có `.env` thật lọt vào build context. (2) **Truy vết**: log, commit SHA, người kích hoạt, label `org.opencontainers.image.revision`. (3) **Quy trình bắt buộc**: quét lỗ hổng chạy mọi lần, không phụ thuộc trí nhớ; không ai phải cầm PAT cá nhân để phát hành. Thêm: người khác phát hành được khi bạn vắng mặt.

**2. `setup-buildx-action` tạo builder gì, vì sao cần cho `type=gha`?**
Builder driver `docker-container` (BuildKit chạy trong container riêng). Driver `docker` mặc định không xuất được cache ra backend ngoài như `type=gha` (trừ khi bật containerd image store) → lỗi `Cache export is not supported for the docker driver`.

**3. `load` và `push`.**
`load: true` nạp image vào Docker daemon của runner — dùng ở bước `Build image` để Trivy quét được. `push: true` đẩy thẳng lên registry — dùng ở bước `Push image`, chỉ khi sự kiện là push vào `main`. Tách vậy để quét **trước**, push **sau**.

**4. `type=sha,prefix=`.**
Tag là SHA commit rút gọn **7 ký tự**, không có tiền tố `sha-` (ví dụ `:4c1d9e2`). Độ dài đổi bằng `DOCKER_METADATA_SHORT_SHA_LENGTH`. `release.yml` tìm image bằng `${GITHUB_SHA::7}` — nếu độ dài khác nhau, tên không khớp, release luôn báo "không tìm thấy".

**5. `type=semver` vs `type=ref,event=tag` với `v0.3.0`.**
`type=semver,pattern={{version}}` → `0.3.0` (bỏ `v`). `type=ref,event=tag` → `v0.3.0` (giữ nguyên). Dự án giữ chữ `v` cho khớp quy ước tag Git và tag image ở Module 03–04. Thực tế `release.yml` không dùng metadata-action mà lấy thẳng `github.ref_name` (= `v0.3.0`), vì nó không build image.

**6. `mode=max`.**
Ghi cache cho **mọi stage**, gồm stage `build` chứa layer `dependency:go-offline`. Với `mode=min` (mặc định), chỉ layer của image cuối (stage runtime) được ghi — lần sau stage build phải tải lại toàn bộ dependency Maven, mất phần lớn lợi ích.

**7. Trivy trước push; quên `exit-code`.**
Nếu quét sau khi push, image có lỗ hổng đã nằm trên registry — server hoặc người khác có thể kéo về trước khi ai đó đọc báo cáo. Quên `exit-code: '1'` → mặc định `0` → Trivy chỉ in báo cáo, bước luôn xanh → cổng chặn không tồn tại.

**8. Đánh đổi CRITICAL + `ignore-unfixed`.**
Ưu: pipeline chỉ đỏ khi có lỗi **nghiêm trọng nhất** mà **sửa được ngay** → đỏ hiếm nhưng đỏ thật, người dùng tin vào màu đỏ. Nhược: lỗi HIGH có bản vá có thể tồn tại một thời gian → bù bằng quy trình (báo cáo HIGH, Dependabot cập nhật base image, rebuild định kỳ) và siết dần ở Module 10. Chặn `HIGH,CRITICAL` không `ignore-unfixed` → đỏ vì lỗi chưa ai vá được → đội quen bỏ qua hoặc tắt cổng.

**9. `write_package` khi merge PR đầu tiên.**
Package `taskhub` đã được push tay bằng PAT ở tuần 8 và chưa kết nối/cấp quyền cho repo → `GITHUB_TOKEN` của workflow không ghi được. Hoặc job thiếu `permissions: packages: write`. Sửa: Package settings → Manage Actions access → Add repository `taskhub` → Role Write; kiểm tra `permissions`; Re-run failed jobs.

**10. `unknown/unknown`.**
Image do `build-push-action` push là image index có **attestation provenance** (mặc định; repo public `mode=max`). Attestation là một manifest riêng trong index với platform `unknown/unknown` để runtime không kéo nhầm về chạy. Image không hỏng; image chạy được là dòng `linux/amd64`.

**11. Job `promote` làm gì.**
Kiểm tra `:<sha7>` của commit được tag đã có trên GHCR, rồi `imagetools create` tạo tag `:vX.Y.Z` là **bản sao y hệt** (cùng digest) của image đó, rồi tạo GitHub Release. Tốt hơn build lại vì image phát hành **chính là** image đã test và quét — không có cơ hội base image hay dependency thay đổi giữa hai lần build.

**12. Tag ngay sau merge, Release đỏ.**
CI trên `main` chưa push `:<sha7>` xong khi `promote` chạy → bước kiểm tra báo không tìm thấy. Sửa: chờ CI xanh rồi **Re-run failed jobs** trên lần chạy Release — re-run dùng lại `GITHUB_SHA`/`GITHUB_REF` của sự kiện ban đầu nên không cần tạo tag mới.

**13. `v0.3.0-rc.1`.**
Có kích hoạt (glob `v*.*.*`: `*` cuối khớp `0-rc.1`). Release tạo ra **không** được đánh dấu pre-release vì workflow không truyền `--prerelease` và `gh` không tự suy ra từ tên tag; nhãn Latest mặc định chọn tự động theo ngày và phiên bản.

**14. Không dùng `git push --tags`.**
(1) Tài liệu GitHub: push **hơn ba tag cùng lúc** thì không tạo sự kiện cho các tag đó → release không chạy. (2) Có thể đẩy cả tag thử nghiệm cục bộ lên remote và kích hoạt phát hành ngoài ý muốn. Luôn `git push origin <một-tag>`.

---

## Phần B — Bài tập tự làm (mục 14)

### Bài 1 — Báo cáo HIGH không chặn

Đặt **trước** bước cổng chặn:

```yaml
      - name: Trivy report (HIGH/CRITICAL, không chặn)
        uses: aquasecurity/trivy-action@v0.36.0   # repo thật: ghim SHA như bản tham khảo
        with:
          image-ref: ${{ fromJSON(steps.meta.outputs.json).tags[0] }}
          format: table
          severity: HIGH,CRITICAL
          exit-code: '0'

      - name: Scan image (Trivy)
        uses: aquasecurity/trivy-action@v0.36.0
        with:
          image-ref: ${{ fromJSON(steps.meta.outputs.json).tags[0] }}
          format: table
          severity: CRITICAL
          ignore-unfixed: true
          exit-code: '1'
          skip-setup-trivy: true   # README trivy-action: lần gọi sau trong cùng job bỏ qua bước cài Trivy
```

Vì sao hai bước: `exit-code` áp dụng cho **toàn bộ** kết quả sau khi lọc theo `severity`/`ignore-unfixed`. Một bước không thể vừa "hiện mọi HIGH/CRITICAL" vừa "chỉ chặn CRITICAL có bản vá". Tách ra: bước 1 cho người đọc thông tin đầy đủ, bước 2 là quy tắc chặn. Đặt báo cáo trước để khi cổng đỏ, bạn đã có bảng đầy đủ trong log.

Lưu ý từ README trivy-action: một số bản cũ có lỗi làm tham số của lần gọi trước "rò" sang lần gọi sau. Nếu bước 2 hiện báo cáo lạ, xem mục `env` của bước có biến `TRIVY_*` bạn không đặt không — có thì nâng phiên bản action.

### Bài 2 — Pre-release đúng nghĩa

```yaml
      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ github.ref_name }}
        run: |
          flags=(--verify-tag --generate-notes)
          # SemVer: phần tiền phát hành đứng sau dấu "-" (v0.3.0-rc.1)
          if [[ "$TAG" == *-* ]]; then
            flags+=(--prerelease --latest=false)
          fi
          gh release create "$TAG" --repo "$GITHUB_REPOSITORY" "${flags[@]}"
```

- Bước `run:` trên runner Ubuntu mặc định chạy bằng `bash`, nên dùng được `[[ ]]` và mảng.
- Mảng `flags=(...)` + `"${flags[@]}"`: mỗi cờ là một đối số riêng, không bị tách sai khi có khoảng trắng — cách viết an toàn đã học ở [Linux bài 06](../../01-LINUX/06-bash-scripting.md).
- `--latest=false`: theo tài liệu `gh`, chặn tường minh việc gắn nhãn Latest.
- Chạy actionlint: không lỗi. (Nếu môi trường có ShellCheck, actionlint dùng nó để kiểm tra luôn script trong `run:` — xem tài liệu actionlint.)

### Bài 3 — Hadolint trong CI

```yaml
      - name: Lint Dockerfile (Hadolint)
        run: docker run --rm -i -e HADOLINT_FAILURE_THRESHOLD=error hadolint/hadolint < docker/Dockerfile
```

- Đặt sau `Checkout`, trước `Build image`. Bước `run:` của job `image` chạy ở gốc repo (job này không có `defaults.run.working-directory`).
- Không dùng action bên thứ ba: chỉ chạy image chính thức bằng `docker run`, giống [Docker 07](../../04-DOCKER/07-docker-security.md).
- `HADOLINT_FAILURE_THRESHOLD=error` (README Hadolint): **in** mọi cảnh báo, nhưng chỉ trả mã lỗi khi có vi phạm mức `error`. Quyết định hợp lý ở mức Junior: lỗi thật (`error`) thì chặn; `warning`/`info` là gợi ý để suy nghĩ, chặn chúng sẽ gây đỏ vì quy tắc bạn đã chủ động chấp nhận.
- Tốt hơn nữa: ghim image theo digest. Tra digest: `docker buildx imagetools inspect hadolint/hadolint` rồi dùng `hadolint/hadolint@sha256:...` — cùng lý do ghim action bằng SHA ở [bài 04](../04-secrets-environments.md).

### Bài 4 — Đo hiệu quả cache

Kết quả mong đợi (số liệu minh họa, máy runner khác nhau mỗi lần):

| PR | Thay đổi | `Build image` | Dòng `CACHED` |
|---|---|---|---|
| (a) | Một file Java | ~1 phút | `COPY app/.mvn/`, `COPY app/mvnw app/pom.xml`, `RUN ... dependency:go-offline`, và layer base image đều `CACHED`; từ `COPY app/src/` chạy lại |
| (b) | Comment trong `pom.xml` | ~3–4 phút | Chỉ các layer trước `COPY app/mvnw app/pom.xml` `CACHED`; `dependency:go-offline` chạy lại (tải lại dependency) |

Giải thích: BuildKit so checksum nội dung file được `COPY`. Thêm comment vẫn đổi nội dung `pom.xml` → layer đó và **mọi layer sau** build lại. Đây đúng là quy tắc layer cache ở [Docker 03](../../04-DOCKER/03-dockerfile-multistage.md), chỉ khác là cache được lưu trong GitHub Actions cache thay vì trên máy bạn.

### Bài 5 — SHA của PR

Không trùng. Với `pull_request`, GitHub tạo một **merge commit tạm** giữa đầu nhánh PR và `main` hiện tại (`refs/pull/<số>/merge`) và chạy workflow trên commit đó — để kiểm tra "code sau khi merge" chứ không chỉ "code trên nhánh". SHA trong `Context info` là SHA của merge commit tạm đó; nó không nằm trên nhánh nào và sẽ khác nếu `main` tiến lên.

Muốn push image cho PR (preview): (1) đặt `DOCKER_METADATA_PR_HEAD_SHA: true` ở `env` của bước metadata để tag theo commit đầu nhánh PR, hoặc dùng `type=ref,event=pr` (`pr-12`); (2) bỏ/sửa điều kiện `if: github.event_name == 'push'` ở bước login và push; (3) cân nhắc bảo mật: PR từ fork nhận token chỉ đọc nên không push được — chỉ áp dụng cho PR trong repo; (4) có chính sách dọn image preview khi PR đóng.

### Bài 6 — ADR

```markdown
# ADR-0002: Phát hành bằng cách gắn tag cho image có sẵn thay vì build lại

- Trạng thái: Đã chấp nhận
- Ngày: 2026-11-15

## Bối cảnh
CI build, test, quét và push image `:<sha7>` mỗi khi code vào main. Khi phát hành
(tag vX.Y.Z) cần một image có tên SemVer. Yêu cầu: image chạy production phải là
image đã được test và quét.

## Các lựa chọn đã cân nhắc
1. Workflow release build lại image từ commit được tag.
2. Workflow release tìm image `:<sha7>` có sẵn và gắn thêm tag `:vX.Y.Z`
   bằng `docker buildx imagetools create`.

## Quyết định
Chọn (2). Image phát hành có cùng digest với image đã quét — kiểm chứng được bằng
`imagetools inspect`. Build lại (1) có thể kéo base image hoặc dependency khác.

## Hệ quả
- Tích cực: không có sai khác giữa bản đã test và bản phát hành; release chạy
  nhanh (vài giây, không build).
- Tiêu cực: release phụ thuộc thứ tự "CI trên main xanh trước, tag sau"; tag
  quá sớm thì release đỏ và phải re-run. Chỉ phát hành được commit nằm trên main.
- Việc cần làm thêm: ghi thứ tự này vào runbook phát hành; độ dài SHA ở
  metadata-action và release.yml phải luôn giống nhau (7).
```

Đạt khi: có đủ bối cảnh, ít nhất hai lựa chọn, lý do dựa trên rủi ro cụ thể, và **nêu được nhược điểm** của lựa chọn đã chọn.
