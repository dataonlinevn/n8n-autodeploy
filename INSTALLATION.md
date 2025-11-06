# Hướng dẫn Cài đặt DataOnline N8N Manager

Tài liệu này hướng dẫn khách hàng cài đặt và khởi chạy DataOnline N8N Manager trên VPS Ubuntu.

## 1. Yêu cầu hệ thống
- Hệ điều hành: Ubuntu 20.04, 22.04 hoặc 24.04 (khuyên dùng 22.04/24.04)
- Tài khoản có quyền sudo
- Tài nguyên: RAM ≥ 2GB, dung lượng trống ≥ 10GB
- Mở port: 5678 (N8N), 5432 (PostgreSQL), 80/443 (Nginx/SSL)

## 2. Cài đặt các gói cơ bản
```bash
sudo apt update && sudo apt install -y curl git sudo
```

## 3. Tải mã nguồn và chạy installer
```bash
git clone https://github.com/vanntpt/n8n-autodeploy
cd n8n-autodeploy
bash install.sh
```
Trong quá trình chạy, installer sẽ:
- Kiểm tra phiên bản Ubuntu và cài đặt các phụ thuộc cơ bản
- Tải manager vào: `/opt/dataonline-n8n-manager`
- Tạo lệnh toàn cục: `dataonline-n8n-manager`

## 4. Khởi chạy trình quản lý
```bash
dataonline-n8n-manager
```
Nếu lệnh toàn cục chưa có, có thể chạy trực tiếp:
```bash
/opt/dataonline-n8n-manager/scripts/manager.sh
```

## 5. Quy trình khuyến nghị sau khi cài đặt
1) Cài đặt N8N (menu Install → Cài đặt N8N với Docker)
2) Cấu hình domain và cài SSL (menu SSL)
3) Thiết lập Backup và Google Drive (menu Backup)
4) Kiểm tra và quản lý services (menu Service Management)

## 6. Gỡ cài đặt (nếu cần)
Sử dụng menu Install → Gỡ cài đặt N8N. Tính năng này sẽ:
- Dừng containers, xóa volumes, xóa cấu hình Nginx liên quan
- Dọn dẹp file cấu hình của Manager
- Hỏi bạn có muốn tạo backup cuối trước khi gỡ

## 7. Đường dẫn & cấu hình quan trọng
- Cài đặt Manager: `/opt/dataonline-n8n-manager`
- Cấu hình Manager: `/etc/dataonline-n8n` và `~/.config/dataonline-n8n`
- Log: `/var/log/dataonline-manager.log` (hoặc `~/.dataonline-manager.log`)
- Cài đặt N8N (Docker Compose): `/opt/n8n`

## 8. Câu hỏi thường gặp (FAQ)
- Lệnh `dataonline-n8n-manager` không chạy?
  - Đảm bảo đã chạy installer, hoặc dùng đường dẫn đầy đủ `/opt/dataonline-n8n-manager/scripts/manager.sh`
- Cần `sudo` không?
  - Quản trị Docker, Nginx, Certbot cần quyền `sudo`.
- Không có domain, có thể dùng N8N không?
  - Có. Bạn có thể dùng IP:Port (http://IP:5678). SSL là tùy chọn.

## 9. Hỗ trợ
- Website: https://dataonline.vn
- GitHub: https://github.com/vanntpt/n8n-autodeploy
- Email: support@dataonline.vn
