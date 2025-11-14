# Hướng dẫn Sử dụng DataOnline N8N Manager

Tài liệu dành cho người dùng cuối (khách hàng) để vận hành N8N trên VPS.

## 1. Khởi chạy
```bash
dataonline-n8n-manager
# hoặc
/opt/dataonline-n8n-manager/scripts/manager.sh
```
Bạn sẽ thấy menu chính với trạng thái nhanh (N8N, SSL, Backups, Workflows) và các nhóm chức năng.

## 2. Nhóm chức năng chính

### 2.1 Install (Cài đặt/Gỡ cài đặt N8N)
- Cài đặt N8N (Docker Compose):
  - Kiểm tra yêu cầu hệ thống (OS/RAM/Disk/Network)
  - Thu thập cấu hình (port N8N/DB, domain/webhook)
  - Sinh docker-compose.yml + .env tại `/opt/n8n`
  - Pull image và khởi động container
  - Xác minh: containers, API N8N, PostgreSQL
- Gỡ cài đặt:
  - Dừng containers, xóa volumes, xóa Nginx cấu hình liên quan
  - Dọn dẹp config của Manager (có hỏi tạo backup cuối)

Mẹo:
- Bạn có thể dùng N8N mà không cần domain (http://IP:5678). SSL thiết lập sau.
- Nếu port bận, chọn port khác khi được hỏi.

### 2.2 SSL (Cấu hình domain + chứng chỉ)
- Quy trình:
  1) Xác thực DNS: domain phải trỏ về IP VPS
  2) Tạo HTTP Nginx config cho ACME challenge
  3) Lấy chứng chỉ Let’s Encrypt (Certbot)
  4) Tạo HTTPS Nginx config và kích hoạt auto-renew
  5) Cập nhật cấu hình N8N sang HTTPS
- Trường hợp vượt rate-limit Let’s Encrypt:
  - Có thể dùng self-signed tạm thời, hoặc đổi sang subdomain khác, hoặc đợi 1 tuần.

Yêu cầu:
- Domain đã trỏ A record về IP VPS
- Port 80/443 mở và Nginx chạy được

### 2.3 Backup (Sao lưu/Khôi phục)
- Tạo backup toàn diện:
  - PostgreSQL (n8n), dữ liệu volumes, docker-compose.yml, .env, config Manager, (NocoDB nếu có)
  - Lưu tại `/opt/n8n/backups/`
- Upload Google Drive (tùy chọn):
  - Cấu hình rclone (menu Setup Google Drive)
  - Tự động nhận remote Google Drive
- Cron backup định kỳ:
  - Hỗ trợ daily/weekly/monthly, mặc định 02:00
- Khôi phục backup:
  - Giải nén, khôi phục DB, volumes, compose, .env, khởi động lại N8N

Lưu ý:
- Lần đầu cần cấu hình rclone (theo hướng dẫn trên màn hình), chọn remote dành cho Google Drive.
- Nếu VPS không mở được trình duyệt, chạy `rclone authorize "drive"` trên máy cá nhân (Windows/Linux), copy toàn bộ JSON token và dán vào bước cấu hình trong Manager.

### 2.4 Database Manager (NocoDB)
- Cài đặt/tích hợp NocoDB vào stack
- Mở giao diện NocoDB, monitoring, maintenance, testing
- Cấu hình SSL riêng cho NocoDB nếu có domain (ví dụ: db.yourdomain.com)

### 2.5 Service Management
- Quản lý service N8N, Nginx, Database: start/stop/restart/status
- Xem log nhanh, thông tin port, health

### 2.6 Workflow Manager (đơn giản)
- Liệt kê, export/import workflows N8N (khi có API key hoặc cấu hình phù hợp)

## 3. Cấu hình & Đường dẫn
- Cài đặt Manager: `/opt/dataonline-n8n-manager`
- Cài đặt N8N (Compose + .env): `/opt/n8n`
- Cấu hình Manager: `/etc/dataonline-n8n` và `~/.config/dataonline-n8n`
- Log chính: `/var/log/dataonline-manager.log` (fallback: `~/.dataonline-manager.log`)
- Backup: `/opt/n8n/backups/`

## 4. Quy trình gợi ý khi mới triển khai
1) Install → Cài đặt N8N
2) SSL → Cấu hình domain + chứng chỉ
3) Backup → Thiết lập Google Drive + cron backup định kỳ
4) Service Management → Kiểm tra services và logs
5) Database Manager → (tùy chọn) Cài NocoDB và tạo views

## 5. Lệnh hữu ích
- Khởi động/kiểm tra N8N nhanh (không cần vào manager):
```bash
cd /opt/n8n
sudo docker compose up -d
curl -f http://localhost:5678/healthz && echo OK
```
- Kiểm tra Nginx config và reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```
- Kiểm tra Let’s Encrypt renew (dry-run):
```bash
sudo certbot renew --dry-run
```

## 6. Hỗ trợ
- Website: https://dataonline.vn
- GitHub: https://github.com/vanntpt/n8n-autodeploy
- Email: support@dataonline.vn
