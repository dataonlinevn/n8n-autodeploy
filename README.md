# DataOnline N8N Manager

Vietnamese-first N8N management tool for Ubuntu VPS. Tập trung vào trải nghiệm dòng lệnh (CLI) với giao diện nhất quán, status real-time, logging rõ ràng, và các tác vụ tự động hoá phổ biến cho N8N.

## Môi trường phát triển
- **Laptop**: Ubuntu 24.04 LTS (Development)
- **VPS**: Ubuntu 24.04 LTS (Testing/Production)
- **Ngôn ngữ**: Bash (có thể dùng thêm Python khi cần)
- **Đối tượng**: Người dùng N8N tại Việt Nam

## Tính năng chính
- **Unified UI System**: Thống nhất hàm hiển thị `ui_info`, `ui_success`, `ui_error`, `ui_warning`, progress đa bước, error box, bảng dữ liệu.
- **Menu nâng cao**: Header rõ ràng, quick status panel, nhóm chức năng theo chủ đề.
- **Plugin theo mô-đun**: Cấu trúc module nhỏ-gọn, dễ bảo trì (Install, Backup, SSL, Database Manager/NocoDB).
- **Logging**: Ghi log file + console, hỗ trợ cấp độ INFO/WARN/ERROR/DEBUG.
- **Tự động hoá**: Cài đặt Docker Compose, SSL Let’s Encrypt, backup định kỳ, export/import workflow, Google Drive.

## Cấu trúc dự án
```
cloudfly-n8n-manager/
├── scripts/
│   └── manager.sh                 # Entry chính (menu tổng)
├── src/
│   ├── core/                      # Hạ tầng lõi (UI, logger, config, spinner, utils)
│   │   ├── ui.sh
│   │   ├── logger.sh
│   │   ├── config.sh
│   │   ├── spinner.sh
│   │   └── utils.sh
│   └── plugins/
│       ├── install/
│       │   ├── main.sh            # Entry cài đặt
│       │   ├── install-requirements.sh
│       │   ├── install-config.sh
│       │   ├── install-compose.sh
│       │   ├── install-verify.sh
│       │   └── install-uninstall.sh
│       ├── backup/
│       │   ├── main.sh            # Entry backup
│       │   ├── backup-utils.sh
│       │   ├── backup-gdrive.sh
│       │   └── backup-scheduler.sh
│       ├── ssl/
│       │   ├── main.sh            # Entry SSL
│       │   ├── ssl-domain.sh
│       │   ├── ssl-nginx.sh
│       │   ├── ssl-certbot.sh
│       │   └── ssl-verify.sh
│       ├── database-manager/
│       │   ├── main.sh            # Entry NocoDB
│       │   ├── nocodb-setup.sh
│       │   ├── nocodb-monitoring.sh
│       │   ├── nocodb-maintenance.sh
│       │   ├── nocodb-testing.sh
│       │   └── nocodb-integration.sh
│       └── service-management/    # Quản lý services (n8n/nginx/postgres)
│           ├── main.sh
│           ├── n8n-service.sh
│           ├── nginx-service.sh
│           └── database-service.sh
└── install.sh                     # One-click installer
```

## Yêu cầu hệ thống
- Ubuntu 18.04+ (khuyến nghị 20.04/22.04/24.04)
- RAM tối thiểu 2GB, dung lượng trống ≥ 10GB
- Docker + Docker Compose (plugin tự cài nếu thiếu)
- Port mở sẵn: 5678 (N8N), 5432 (PostgreSQL), 80/443 (Nginx/SSL)

## Cài đặt nhanh
1) Chạy one-click installer (tùy môi trường):
```
bash install.sh
```
2) Mở trình quản lý:
```
bash scripts/manager.sh
```

## Sử dụng nhanh
- Từ menu chính, bạn có thể:
  - Cài đặt/Gỡ N8N (Install)
  - Cấu hình SSL domain + Let’s Encrypt (SSL)
  - Backup/Restore và đồng bộ Google Drive (Backup)
  - Quản lý Database/NocoDB (Database Manager)
  - Quản lý services (N8N/Nginx/PostgreSQL)

### Install Plugin
- Kiểm tra yêu cầu hệ thống, thu thập cấu hình, tạo `docker-compose.yml` + `.env`, khởi động stack, xác minh.
- Mô-đun:
  - `install-requirements.sh`: kiểm tra OS/RAM/Disk/Network/Commands
  - `install-config.sh`: lấy `N8N_PORT`, `POSTGRES_PORT`, domain/webhook
  - `install-compose.sh`: sinh Compose + khởi động N8N
  - `install-verify.sh`: xác minh containers, API, DB
  - `install-uninstall.sh`: gỡ cài đặt, dọn dẹp hệ thống

### SSL Plugin
- Quy trình: xác thực DNS → tạo HTTP config → lấy cert (certbot) → tạo HTTPS config → auto-renew → cập nhật N8N.
- Mô-đun: `ssl-domain.sh`, `ssl-nginx.sh`, `ssl-certbot.sh`, `ssl-verify.sh`.

### Backup Plugin
- Tạo backup toàn diện (DB, volumes, compose, env, config), nén, upload Google Drive (rclone), cron định kỳ.
- Mô-đun: `backup-utils.sh`, `backup-gdrive.sh`, `backup-scheduler.sh`.

### Database Manager (NocoDB)
- Cài đặt/tích hợp NocoDB, monitoring, maintenance, testing, integration với menu chính.
- Mô-đun: `nocodb-setup.sh`, `nocodb-monitoring.sh`, `nocodb-maintenance.sh`, `nocodb-testing.sh`, `nocodb-integration.sh`.

## Giao diện & Logging
- UI thống nhất: `ui_info`, `ui_success`, `ui_error`, `ui_warning`, `ui_table`, progress đa bước.
- Logger: ghi ra console và file (khi có), hỗ trợ `DEBUG/INFO/WARN/ERROR/SUCCESS`.
- Spinner & Progress: hiển thị tiến trình cho các tác vụ dài (pull images, renew cert, backup...).

## Mẹo & Khắc phục sự cố
- SSL rate limit: dùng subdomain khác hoặc self-signed tạm thời, thử lại sau 1 tuần.
- N8N không start: `docker compose logs -f`, kiểm tra port/ram/disk.
- NocoDB không phản hồi: kiểm tra `http://localhost:8080/api/v1/health`, logs container, cấu hình DB.
- Google Drive: cấu hình `rclone config`, kiểm tra remote `n8n-backups`.

## Trạng thái dự án
- ✅ Hoàn tất Phase 1: Unified UI & UX nâng cao
- ✅ Hoàn tất Phase 2: Refactor plugins sang mô-đun
- ✅ Hoàn tất Phase 3: Chuẩn hoá toàn bộ plugins dùng UI mới

Đóng góp/Issues: Vui lòng tạo issue/pull request để phản hồi hoặc đề xuất cải tiến.