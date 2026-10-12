# Bài 5 - Chẩn đoán và khắc phục 3 sự cố Pipeline CI/CD

Bài nộp Session 12 - DevOps. Workflow `broken-pipeline.yml` ban đầu bị 3 lỗi và đã được sửa để pipeline tích xanh.

## Ba lỗi đã xử lý

1. Permission Denied: `gradlew` thiếu quyền thực thi trên runner Linux -> thêm `run: chmod +x gradlew`.
2. Authentication Failed: sai tên secret `REGISTRY_TOKKEN` -> sửa thành `REGISTRY_TOKEN`.
3. Build Context Error: sai `context` và `file` -> `context: .`, `file: ./Dockerfile`.

## Tệp trong thư mục này

| Tệp | Nội dung |
| --- | --- |
| `troubleshooting.md` | Báo cáo chẩn đoán chi tiết: triệu chứng, nguyên nhân, cách sửa, phòng ngừa |
| `broken-pipeline.before.yml` | Workflow bản hỏng (3 lỗi) |
| `broken-pipeline.yml` | Workflow bản đã sửa (bản chạy thật nằm ở `.github/workflows/`) |
| `actionlint_output.txt` | Kết quả actionlint cho cả hai bản |
| `local_repro_log.txt` | Output thật khi tái hiện lỗi 1 và lỗi 3 bằng Docker |

## Lưu ý về secret

Secret `REGISTRY_TOKEN` (PAT classic, quyền `write:packages`) do học viên tự tạo trong Settings -> Secrets and
variables -> Actions. Chưa có secret này thì bước đăng nhập vẫn đỏ. Chi tiết ở mục 5.4 của `troubleshooting.md`.

Xem báo cáo đầy đủ: [troubleshooting.md](troubleshooting.md).
