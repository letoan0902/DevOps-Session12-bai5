# DevOps Session 12 - Bài 5: Chẩn đoán và khắc phục 3 sự cố Pipeline CI/CD

Ứng dụng Spring Boot (Java 21, Gradle Wrapper) cùng workflow GitHub Actions `broken-pipeline.yml` gồm hai job:
`test` (chạy Gradle test) và `docker-build` (build và đẩy image lên GitHub Container Registry). Workflow ban đầu
bị 3 lỗi (Permission Denied, Authentication Failed, Build Context Error) và đã được chẩn đoán, khắc phục.

- Báo cáo chẩn đoán: [homework/session_12/ex5/troubleshooting.md](homework/session_12/ex5/troubleshooting.md)
- Workflow đã sửa: [.github/workflows/broken-pipeline.yml](.github/workflows/broken-pipeline.yml)
- Workflow bản hỏng để đối chiếu: [homework/session_12/ex5/broken-pipeline.before.yml](homework/session_12/ex5/broken-pipeline.before.yml)

## Danh sách file

| Đường dẫn | Mô tả |
| --- | --- |
| `.github/workflows/broken-pipeline.yml` | Workflow CI/CD |
| `Dockerfile`, `.dockerignore` | Đóng gói ứng dụng thành image |
| `build.gradle`, `settings.gradle` | Cấu hình Gradle |
| `gradlew`, `gradlew.bat`, `gradle/wrapper/` | Gradle Wrapper 8.10 |
| `src/` | Mã nguồn và bài kiểm thử |
| `homework/session_12/ex5/` | Bài nộp: troubleshooting.md, hai bản workflow, log tái hiện, actionlint |

## Yêu cầu trước khi chạy pipeline

Tạo secret `REGISTRY_TOKEN` (Personal access token classic, quyền `write:packages`) trong Settings -> Secrets and
variables -> Actions của repo, nếu không bước đăng nhập GHCR sẽ lỗi.

Trạng thái CI: (cập nhật sau khi push)
