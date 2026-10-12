# Bài 5 - Chẩn đoán và khắc phục 3 sự cố đứt gãy Pipeline CI/CD

Session 12 - DevOps. Repo: `letoan0902/DevOps-Session12-bai5`. Workflow cần sửa: `.github/workflows/broken-pipeline.yml`.

## 1. Mục tiêu

Phân tích log lỗi thực tế trên GitHub Actions và sửa trực tiếp workflow để khôi phục luồng CI/CD tích xanh.
Workflow ban đầu bị 3 lỗi nằm ở hai job nối tiếp nhau:

| STT | Loại lỗi | Job / bước | Hiện tượng chính |
| --- | --- | --- | --- |
| 1 | Permission Denied | `test` / Chạy test bằng Gradle Wrapper | `./gradlew: Permission denied`, mã thoát 126 |
| 2 | Authentication Failed | `docker-build` / Đăng nhập GitHub Container Registry | Tên secret sai chính tả nên mật khẩu rỗng |
| 3 | Build Context Error | `docker-build` / Build và đẩy Docker image | Không tìm thấy Dockerfile do sai thư mục |

## 2. Mô tả pipeline và dự án

Dự án là một ứng dụng Spring Boot 3.3.4 (Java 21) build bằng Gradle, có hai endpoint `/` và `/api/version`
cùng một bài kiểm thử `HelloControllerTest`. Dự án dùng Gradle Wrapper (`gradlew`, `gradlew.bat`,
`gradle/wrapper/gradle-wrapper.jar`, `gradle-wrapper.properties`, phân phối Gradle 8.10) nên máy runner không
cần cài sẵn Gradle.

Pipeline gồm hai job, `docker-build` phụ thuộc `test` qua `needs: test`:

```text
push lên main / workflow_dispatch
        |
        v
  job test                              job docker-build (chỉ chạy khi test xanh)
  - checkout                            - checkout
  - setup-java (temurin 21)             - setup-buildx
  - [FIX 1] chmod +x gradlew            - login ghcr.io          [FIX 2: secret]
  - ./gradlew test --no-daemon          - metadata (tag sha, latest)
                                        - build-push-action      [FIX 3: context, file]
```

Hệ quả của `needs: test`: lỗi 1 chặn toàn bộ job `docker-build`, nên lỗi 2 và lỗi 3 chỉ lộ ra lần lượt sau khi
lỗi đứng trước được sửa. Đây là đặc điểm điển hình khi chẩn đoán pipeline: sửa một lỗi, push, rồi đọc tiếp log
của lỗi kế tiếp.

Cấu trúc thư mục liên quan:

```text
.
|-- .github/workflows/broken-pipeline.yml
|-- Dockerfile                  (nằm ở gốc repo)
|-- build.gradle, settings.gradle
|-- gradlew, gradlew.bat
|-- gradle/wrapper/gradle-wrapper.jar, gradle-wrapper.properties
`-- src/                        (mã nguồn và test)
```

Lưu ý quan trọng cho lỗi 3: repo không có thư mục `app/` và cũng không có thư mục `docker/`; `Dockerfile` nằm
thẳng ở gốc repo.

## 3. Phương pháp chẩn đoán chung

1. Mở tab Actions của repo, chọn run màu đỏ. Đọc phần Annotations ở đầu trang tóm tắt run: tên job và dòng
   `##[error]` đầu tiên thường đã nói rõ bước hỏng.
2. Trong sơ đồ job, tìm bước có dấu X đỏ. Các bước phía sau bị bỏ qua (skipped) vì mặc định bước sau chỉ chạy
   khi bước trước thành công; job phụ thuộc cũng bị bỏ qua nếu job `needs` thất bại.
3. Mở rộng bước đỏ và đọc ngược từ dưới lên. Thông điệp gốc thường nằm ngay trên dòng
   `##[error]Process completed with exit code N.` hoặc ngay dòng `##[error]` đầu tiên.
4. Phân loại lỗi theo mã thoát và nội dung:
   - Mã thoát 126: lệnh tồn tại nhưng không thực thi được (thiếu quyền `x`).
   - Mã thoát 127: không tìm thấy lệnh (sai đường dẫn hoặc thiếu công cụ).
   - Lỗi từ action (dòng bắt đầu bằng `Error:`): kiểm tra đầu vào `with:` và secret.
   - Lỗi từ Docker/buildx (`ERROR: failed to build`): kiểm tra `context`, `file`, nội dung Dockerfile.
5. Tái hiện cục bộ khi có thể (Docker trên máy cá nhân) để thử nhanh mà không phải push nhiều commit.
6. Sửa đúng một nguyên nhân mỗi lần, push, xem lại log. Với lỗi bị che khuất bởi `needs`, sửa lỗi hiện tại rồi
   chờ lỗi tiếp theo xuất hiện.
7. Chạy linter workflow (actionlint) để bắt lỗi cú pháp, nhưng không coi đó là bằng chứng workflow chạy đúng
   (xem mục 8).

## 4. Lỗi 1 - Permission Denied khi chạy Gradle Wrapper

### 4.1 Triệu chứng

Job `test` dừng ở bước "Chạy test bằng Gradle Wrapper", các bước sau và toàn bộ job `docker-build` bị bỏ qua.
Log mẫu (dạng thường gặp):

```text
Run ./gradlew test --no-daemon
/home/runner/work/_temp/xxxxxxxx.sh: line 1: ./gradlew: Permission denied
##[error]Process completed with exit code 126.
```

Log thật từ GitHub Actions:

```text
Log thật từ GitHub Actions (run 38302240778, commit "ci: pipeline ban đầu", job `test`, bước `Chạy test bằng Gradle Wrapper`):

```text
##[group]Run ./gradlew test --no-daemon
/home/runner/work/_temp/6251fc1f-bc45-4b89-ad55-eee7654234a0.sh: line 1: ./gradlew: Permission denied
##[error]Process completed with exit code 126.
```

Trạng thái job: `test: failure` sau 7 giây, `docker-build: skipped` (vì `needs: test`). Mã thoát 126 của shell nghĩa là tệp tồn tại nhưng không thể thực thi. Kiểm tra mode trong Git xác nhận nguyên nhân: `git ls-files --stage gradlew` cho `100644`.
```

### 4.2 Nguyên nhân gốc

Git lưu kèm mỗi file một mode. Trên Windows, hệ thống file NTFS không có bit thực thi kiểu Unix nên khi `git add`
file `gradlew`, Git ghi mode `100644` (file thường) thay vì `100755` (file thực thi). Runner `ubuntu-latest`
checkout đúng mode đó, vì vậy `gradlew` là file không có quyền `x` và shell từ chối chạy với mã thoát 126.

Có thể kiểm tra mode đang lưu trong index bằng lệnh:

```bash
git ls-files --stage gradlew
# 100644 <sha> 0    gradlew        (chưa có quyền thực thi)
# 100755 <sha> 0    gradlew        (đã có quyền thực thi)
```

### 4.3 Cách sửa

Có hai hướng:

- Sửa gốc rễ trong Git: `git update-index --chmod=+x gradlew`, commit, push. Từ đó mọi lần checkout trên Linux
  đều có quyền thực thi, không cần bước phụ trong workflow.
- Sửa trong workflow, đúng như gợi ý của đề: thêm bước `chmod +x gradlew` trước lệnh test. Cách này an toàn
  khi người dùng khác commit từ Windows và quên đặt mode.

Bài này chọn cách thứ hai theo đề bài, và cố ý không chmod trong Git để lỗi tái hiện được trên runner.

```diff
       - name: Cài đặt JDK 21
         uses: actions/setup-java@v5
         with:
           distribution: temurin
           java-version: '21'

+      # [FIX 1] Cấp quyền thực thi cho gradlew
+      - name: Cấp quyền thực thi cho Gradle Wrapper
+        run: chmod +x gradlew
+
       - name: Chạy test bằng Gradle Wrapper
         run: ./gradlew test --no-daemon
```

Một cách tránh chmod là gọi `sh ./gradlew test` hoặc `bash gradlew test`, nhưng cách đó che giấu vấn đề mode
thay vì giải quyết nó.

### 4.4 Cách phòng ngừa

- Sau khi tạo wrapper trên Windows, chạy ngay `git update-index --chmod=+x gradlew` trước lần commit đầu.
- Thêm một bước kiểm tra nhanh trong CI hoặc pre-commit: `git ls-files --stage gradlew` phải bắt đầu bằng
  `100755`.
- Thống nhất quy ước nhóm để mọi thành viên đặt đúng mode cho các script khi commit từ Windows.
- Luôn commit cả `gradle/wrapper/gradle-wrapper.jar` (file nhị phân, đã khai báo `*.jar binary`), nếu thiếu
  jar thì `gradlew` sẽ lỗi `Could not find or load main class org.gradle.wrapper.GradleWrapperMain`.

## 5. Lỗi 2 - Authentication Failed khi đăng nhập Docker Registry

### 5.1 Triệu chứng

Sau khi lỗi 1 được sửa, job `test` xanh và job `docker-build` chạy. Bước "Đăng nhập GitHub Container Registry"
thất bại ngay lập tức, không có yêu cầu mạng nào tới `ghcr.io`. Log mẫu:

```text
Run docker/login-action@v3
  with:
    registry: ghcr.io
    username: letoan0902
    password: 
    ecr: auto
    logout: true
Error: Password required
##[error]Password required
```

Log thật từ GitHub Actions:

```text
Log thật từ GitHub Actions (run 38302329815, commit "fix(ci): lỗi 1", job `docker-build`, bước `Đăng nhập GitHub Container Registry`):

```text
##[group]Run docker/login-action@v3
  username: letoan0902
##[error]Password required
```

Trạng thái job: `test: success` (39 giây, sau khi đã thêm `chmod +x gradlew`), `docker-build: failure` sau 12 giây, bước `Build và đẩy Docker image` bị bỏ qua. Dòng `username` có giá trị nhưng không có dòng `password`, vì biểu thức `${{ secrets.REGISTRY_TOKKEN }}` tham chiếu một secret không tồn tại nên nhận chuỗi rỗng. Lưu ý: nếu secret đúng tên `REGISTRY_TOKEN` cũng chưa được tạo trong repo thì thông báo lỗi giống hệt; vì vậy sau khi sửa chính tả còn phải kiểm tra `gh secret list` (xem mục 5.4).
```

Dấu hiệu nhận biết: ở phần `with:` của log, trường `password:` để trống. Với secret hợp lệ, GitHub in
`password: ***` (giá trị được che).

### 5.2 Nguyên nhân gốc

Workflow tham chiếu `${{ secrets.REGISTRY_TOKKEN }}` (thừa một chữ K) trong khi secret thật tên
`REGISTRY_TOKEN`. GitHub không báo lỗi khi tên secret không tồn tại; biểu thức đơn giản được thay bằng chuỗi
rỗng. `docker/login-action` nhận `password` rỗng nên báo `Password required`. Đây là lỗi "âm thầm": cú pháp
hợp lệ, actionlint không bắt được (xem mục 8).

### 5.3 Cách sửa

```diff
       - name: Đăng nhập GitHub Container Registry
         uses: docker/login-action@v3
         with:
           registry: ghcr.io
           username: ${{ github.actor }}
-          password: ${{ secrets.REGISTRY_TOKKEN }}
+          password: ${{ secrets.REGISTRY_TOKEN }}
```

Đối chiếu tên secret trong Settings -> Secrets and variables -> Actions của repo; tên phân biệt hoa thường và
phải khớp từng ký tự.

### 5.4 Điều kiện bắt buộc: học viên tự tạo secret `REGISTRY_TOKEN`

Sửa chính tả chỉ có tác dụng khi secret `REGISTRY_TOKEN` thật sự tồn tại. Secret này không nằm trong mã nguồn
và do học viên tự tạo:

1. Vào GitHub -> Settings -> Developer settings -> Personal access tokens -> Tokens (classic) -> Generate new
   token (classic).
2. Chọn quyền `write:packages` (tự kèm `read:packages`); đặt thời hạn hợp lý.
3. Sao chép token (chỉ hiển thị một lần).
4. Vào repo -> Settings -> Secrets and variables -> Actions -> New repository secret, đặt tên đúng
   `REGISTRY_TOKEN`, dán token.
5. Vào tab Actions, chọn run lỗi, bấm Re-run failed jobs (hoặc push commit mới).

Cho đến khi bước 4 hoàn tất, bước đăng nhập vẫn đỏ với `Password required` dù workflow đã sửa đúng. Điều này
không phải do workflow sai. Tuyệt đối không dán token vào mã nguồn, README hay log công khai.

Ghi chú: với GHCR trong cùng repo, `secrets.GITHUB_TOKEN` kèm `permissions: packages: write` cũng có thể đủ để
đẩy image; bài này giữ tên `REGISTRY_TOKEN` theo yêu cầu đề bài.

### 5.5 Cách phòng ngừa

- Đặt tên secret theo quy ước rõ ràng và sao chép nguyên tên từ trang Secrets thay vì gõ tay.
- Thêm bước kiểm tra tồn tại secret (ví dụ `if [ -z "$TOKEN" ]; then echo "Thiếu secret"; exit 1; fi`, với
  `TOKEN` lấy từ `env:`) để thông điệp lỗi nói rõ nguyên nhân.
- Dùng GitHub Environments hoặc secret ở cấp tổ chức khi nhiều repo dùng chung.

## 6. Lỗi 3 - Build Context Error (không tìm thấy Dockerfile)

### 6.1 Triệu chứng

Sau khi đăng nhập thành công, bước "Build và đẩy Docker image" thất bại trước khi bắt đầu build lớp nào. Log mẫu:

```text
Run docker/build-push-action@v5
  with:
    context: ./app
    file: ./docker/Dockerfile
    push: true
    tags: ghcr.io/letoan0902/DevOps-Session12-bai5:latest
Error: buildx failed with: ERROR: failed to build: unable to prepare context: path "./app" not found
##[error]buildx failed with: ERROR: failed to build: unable to prepare context: path "./app" not found
```

Log thật từ GitHub Actions:

```text
Log thật từ GitHub Actions: ở run 38302502567 (bản đã sửa đủ 3 lỗi) job `docker-build` vẫn dừng ở bước đăng nhập vì repository chưa có secret `REGISTRY_TOKEN` (do học viên tự tạo), nên bước `docker/build-push-action@v5` chưa được chạy trên runner và lỗi 3 không xuất hiện trong log GitHub. Lỗi 3 được tái hiện và xác nhận bằng Docker cục bộ ở mục 7 (thông điệp `unable to prepare context: path "./app" not found`). Sau khi học viên thêm secret và Re-run jobs, bước build sẽ dùng `context: .` và `file: ./Dockerfile` đã sửa.
```

Tuỳ phiên bản buildx, cùng nguyên nhân có thể hiện dưới dạng `failed to read dockerfile: open
docker/Dockerfile: no such file or directory`.

### 6.2 Nguyên nhân gốc

Hai đường dẫn đều trỏ tới nơi không có gì:

- `context: ./app` là thư mục build context, nhưng repo không có thư mục `app/`.
- `file: ./docker/Dockerfile` là đường dẫn tới Dockerfile, nhưng repo không có thư mục `docker/`; `Dockerfile`
  nằm ở gốc repo.

Cần phân biệt hai tham số: `context` là thư mục chứa các file mà lệnh `COPY` có thể lấy, còn `file` là đường dẫn
Dockerfile. Khi không đặt `file`, mặc định là `<context>/Dockerfile`. Dockerfile của dự án có
`COPY settings.gradle build.gradle ./` và `COPY src ./src`, tức là context phải là gốc repo.

### 6.3 Cách sửa

```diff
       - name: Build và đẩy Docker image
         uses: docker/build-push-action@v5
         with:
-          context: ./app
-          file: ./docker/Dockerfile
+          context: .
+          file: ./Dockerfile
           push: true
-          tags: ghcr.io/${{ github.repository }}:latest
+          tags: ${{ steps.meta.outputs.tags }}
+          labels: ${{ steps.meta.outputs.labels }}
```

Cùng lúc, bản sửa thêm bước `docker/metadata-action@v5` để sinh danh sách tag gồm `sha-<7 ký tự đầu của commit>`
và `latest`:

```yaml
      - name: Sinh metadata và tag cho image
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha
            type=raw,value=latest
```

Lý do dùng metadata-action: GHCR yêu cầu tên image viết thường, trong khi `github.repository` của repo này là
`letoan0902/DevOps-Session12-bai5` có chữ hoa. Metadata-action tự chuyển tên image về chữ thường
(`ghcr.io/letoan0902/devops-session12-bai5`). Nếu giữ nguyên `tags: ghcr.io/${{ github.repository }}:latest`
thì sau khi sửa context vẫn có thể gặp lỗi `repository name must be lowercase` ở bước đẩy image; đây là một
rủi ro tiềm ẩn phía sau lỗi 3.

### 6.4 Cách phòng ngừa

- Trước khi viết `context`/`file`, chạy `ls` ở gốc repo (hoặc bước debug `run: ls -la`) để thấy đúng cấu trúc
  trên runner.
- Kiểm tra cục bộ cùng lệnh: `docker build -f ./Dockerfile .` tại gốc repo.
- Nhớ rằng đường dẫn `file` tính từ thư mục làm việc của workflow (gốc repo sau `actions/checkout`), không phải
  từ `context`.
- Luôn gắn thêm tag theo commit (`sha`) để truy vết image, không chỉ dựa vào `latest`.

## 7. Tái hiện cục bộ bằng Docker

Toàn bộ output thật nằm trong `local_repro_log.txt`; dưới đây là phần chính.

### 7.1 Lỗi 1

Mô phỏng file có mode 100644 như khi checkout trên runner, rồi chạy không chmod:

```text
$ docker run --rm -v "$PWD:/src:ro" gradle:8.10-jdk21 sh -c "mkdir /work && cp -r /src/. /work/ \
    && cd /work && chmod 644 gradlew && ls -l gradlew && ./gradlew --version; echo exit_code=\$?"
-rw-r--r-- 1 root root 8762 Oct 12 20:02 gradlew
sh: 1: ./gradlew: Permission denied
exit_code=126
```

Lưu ý: nếu bind-mount thư mục Windows vào container và chạy thẳng `./gradlew`, file hiển thị mode 755 nên lỗi
không xuất hiện; vì vậy phải sao chép sang thư mục trong container rồi đặt `chmod 644`.

Sau khi thêm `chmod +x gradlew`:

```text
-rwxr-xr-x 1 root root 8762 Oct 12 20:02 gradlew
> Task :compileJava
> Task :processResources
> Task :classes
> Task :compileTestJava
> Task :processTestResources NO-SOURCE
> Task :testClasses
> Task :test

BUILD SUCCESSFUL in 1m 4s
4 actionable tasks: 4 executed
exit_code=0
```

### 7.2 Lỗi 3

```text
$ docker buildx build -f ./docker/Dockerfile ./app
ERROR: failed to build: unable to prepare context: path "./app" not found
exit_code=1
```

Với context `.` nhưng vẫn trỏ `./docker/Dockerfile`, Docker client trên Windows báo:

```text
$ docker buildx build -f ./docker/Dockerfile .
ERROR: failed to build: resolve : GetFileAttributesEx docker: The system cannot find the file specified.
```

Sau khi sửa thành `context: .` và `file: ./Dockerfile`, lệnh `docker build -f ./Dockerfile .` hoàn tất, `exit_code=0`
(image local được xóa sau khi kiểm chứng).

### 7.3 Lỗi 2

Không tái hiện cục bộ vì phụ thuộc secret của GitHub. Về cơ chế, `docker/login-action` kiểm tra đầu vào
`password` trước khi gọi registry; khi giá trị rỗng nó dừng với `Password required`. Log thật của
`docker/login-action` được ghi ở mục 5.1.

## 8. Vì sao actionlint không phát hiện được 3 lỗi

Kết quả đầy đủ trong `actionlint_output.txt`: cả bản hỏng lẫn bản sửa đều cho `exit_code=0`, không có cảnh báo.

- Lỗi 1 nằm ở mode file trong Git, không nằm trong YAML.
- Lỗi 2 là biểu thức `${{ secrets.TÊN }}` hợp lệ về cú pháp; actionlint không biết repo có secret nào.
- Lỗi 3 là đường dẫn trỏ tới thư mục không tồn tại; actionlint không kiểm tra hệ thống file của repo.

Bài học: linter chỉ đảm bảo cú pháp và schema; muốn bắt 3 lỗi này phải dựa vào log thật hoặc tái hiện cục bộ.

## 9. Kết quả trên GitHub Actions

Repo: https://github.com/letoan0902/DevOps-Session12-bai5 (tab Actions: https://github.com/letoan0902/DevOps-Session12-bai5/actions). Pipeline được sửa theo ba commit để log của từng lỗi lộ ra lần lượt (do `needs: test`, lỗi 2 chỉ xuất hiện sau khi sửa lỗi 1):

| Commit | Nội dung | Run | Job test | Job docker-build | Lỗi lộ ra |
|---|---|---|---|---|---|
| 1 | Pipeline ban đầu (3 lỗi) | 38302240778 | failure (7s) | skipped | Lỗi 1: `./gradlew: Permission denied`, exit code 126 |
| 2 | Sửa lỗi 1 (`chmod +x gradlew`) | 38302329815 | success (39s) | failure (12s) | Lỗi 2: `Password required` ở bước đăng nhập |
| 3 | Sửa lỗi 2 và 3 (`REGISTRY_TOKEN`, `context: .`, `file: ./Dockerfile`) | 38302502567 | success (37s) | failure ở bước đăng nhập | Chưa có secret `REGISTRY_TOKEN` trong repo |

Kết quả run cuối (38302502567):

```text
$ gh run view 38302502567 --repo letoan0902/DevOps-Session12-bai5
X main Broken Pipeline - CI/CD . 38302502567
JOBS
V test in 37s (ID 114988569851)
X docker-build in 18s (ID 114988799132)
  V Checkout mã nguồn
  V Cài đặt Docker Buildx
  X Đăng nhập GitHub Container Registry
  - Sinh metadata và tag cho image
  - Build và đẩy Docker image

$ gh api repos/letoan0902/DevOps-Session12-bai5/actions/runs/38302502567/jobs -q '.jobs[] | "\(.name): \(.status)/\(.conclusion)"'
test: completed/success
docker-build: completed/failure
```

Trích log job `test` của run cuối:

```text
##[group]Run chmod +x gradlew
> Task :test
BUILD SUCCESSFUL in 32s
```

Đọc kết quả: lỗi 1 đã hết (job `test` xanh, Gradle Wrapper chạy được và test pass), workflow đã dùng đúng tên secret và đúng build context. Bước còn đỏ là đăng nhập GHCR, nguyên nhân không nằm trong tệp workflow mà do repository chưa có secret `REGISTRY_TOKEN`. Để pipeline tích xanh hoàn toàn, học viên tạo PAT classic có `write:packages`, chạy `gh secret set REGISTRY_TOKEN --repo letoan0902/DevOps-Session12-bai5`, rồi Re-run jobs trên run 38302502567 và chụp ảnh kết quả tích xanh làm ảnh nộp bài.

## 10. Bảng tổng hợp 3 lỗi

| Lỗi | Loại lỗi | Job / bước | Thông điệp chính | Nguyên nhân | Cách sửa |
| --- | --- | --- | --- | --- | --- |
| 1 | Permission Denied | `test` / Chạy test bằng Gradle Wrapper | `./gradlew: Permission denied`, exit code 126 | `gradlew` có mode 100644 do commit từ Windows | Thêm bước `run: chmod +x gradlew` trước lệnh test |
| 2 | Authentication Failed | `docker-build` / Đăng nhập GHCR | `Error: Password required` | Tên secret sai chính tả `REGISTRY_TOKKEN`, giá trị rỗng | Sửa thành `secrets.REGISTRY_TOKEN` và tạo secret này |
| 3 | Build Context Error | `docker-build` / Build và đẩy image | `path "./app" not found` hoặc `failed to read dockerfile` | `context: ./app`, `file: ./docker/Dockerfile` không tồn tại | `context: .` và `file: ./Dockerfile` |

## 11. Đối chiếu yêu cầu đề bài

| Yêu cầu | Đáp ứng | Vị trí |
| --- | --- | --- |
| Sửa `.github/workflows/broken-pipeline.yml` | Đã sửa 3 lỗi, đánh dấu `[FIX 1]`, `[FIX 2]`, `[FIX 3]` | `.github/workflows/broken-pipeline.yml` |
| Lỗi 1: thiếu quyền thực thi Gradle Wrapper | Thêm `run: chmod +x gradlew` trước lệnh test | Mục 4 |
| Lỗi 2: sai tên biến Secret | `${{ secrets.REGISTRY_TOKEN }}`, hướng dẫn tạo secret | Mục 5 |
| Lỗi 3: sai thư mục làm việc | `context: .`, `file: ./Dockerfile` trong `docker/build-push-action@v5` | Mục 6 |
| Phân tích log lỗi trên Actions | Triệu chứng và log thật cho từng lỗi | Mục 4.1, 5.1, 6.1 |
| Push commit mới, xem log tab Actions | Người điều phối push hai giai đoạn | Mục 9 |
| Nộp `troubleshooting.md` | Tài liệu này | `homework/session_12/ex5/troubleshooting.md` |
| Nộp ảnh chụp kết quả tích xanh | Cập nhật sau khi push | Mục 9 |

## 12. Kết luận

Ba lỗi thuộc ba tầng khác nhau của pipeline: hệ điều hành và Git (quyền thực thi), cấu hình bí mật (tên
secret), và công cụ build (đường dẫn context). Các điểm rút ra:

- Đọc log từ bước đỏ và dòng `##[error]` trước khi đoán nguyên nhân; mã thoát cho biết loại lỗi.
- `needs` làm các lỗi lộ ra lần lượt, nên cần kiên nhẫn sửa từng lỗi và push lại.
- Secret sai tên không gây lỗi cú pháp, chỉ cho giá trị rỗng; luôn đối chiếu tên với trang Secrets.
- Đường dẫn trong workflow tính từ gốc repo sau checkout; kiểm tra bằng `ls` hoặc tái hiện bằng Docker cục bộ.
- Linter như actionlint hữu ích nhưng không thay thế được việc chạy thật hoặc tái hiện cục bộ.
- Về lâu dài nên sửa gốc rễ mode của `gradlew` trong Git và dùng tag theo commit cho image.
