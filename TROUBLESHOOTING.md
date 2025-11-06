# Xử lý sự cố (Troubleshooting)

Tài liệu này tổng hợp các lỗi thường gặp và cách xử lý nhanh khi triển khai N8N bằng DataOnline N8N Manager.

## 1. SSL/Domain
### 1.1 DNS không trỏ đúng
Triệu chứng: Cảnh báo DNS không trỏ IP VPS hoặc không resolve.
- Kiểm tra record A trên DNS provider về IP VPS
- Kiểm tra nhanh:
```bash
dig +short A yourdomain.com @1.1.1.1
curl -I http://yourdomain.com
```
- Trong Manager: có thể chọn bỏ qua tạm thời (không khuyến nghị cho production)

### 1.2 Certbot lỗi rate-limit
Triệu chứng: Thông báo đã vượt giới hạn phát hành chứng chỉ trong tuần.
- Giải pháp nhanh: dùng self-signed tạm thời (Manager sẽ gợi ý)
- Lâu dài: đổi subdomain khác hoặc đợi tuần sau
- Lệnh thử nghiệm staging:
```bash
sudo certbot certonly --staging --webroot -w /var/www/html -d yourdomain.com --email you@yourdomain.com --agree-tos --non-interactive
```

### 1.3 Nginx lỗi cấu hình
- Kiểm tra syntax và reload:
```bash
sudo nginx -t && sudo systemctl reload nginx
```
- Xem log: `/var/log/nginx/*.error.log`

## 2. N8N không khởi động
Triệu chứng: Health check fail, hoặc container không chạy.
- Khởi động lại stack:
```bash
cd /opt/n8n
sudo docker compose up -d
```
- Kiểm tra logs:
```bash
sudo docker compose logs -f --tail=200
```
- Kiểm tra port 5678 có bị chiếm:
```bash
ss -tlnp | grep :5678
```
- Thiếu tài nguyên (RAM/disk): nâng cấp hoặc dọn dẹp.

## 3. PostgreSQL
- Kiểm tra sẵn sàng:
```bash
sudo docker exec n8n-postgres pg_isready -U n8n
```
- Nếu DB không sẵn sàng: restart stack và đợi healthcheck pass.

## 4. Backup/Restore
### 4.1 Backup không upload được Google Drive
- Cấu hình rclone lại:
```bash
rclone config
rclone listremotes
rclone lsd remoteName:
```
- Đảm bảo remote có thư mục `n8n-backups/`

### 4.2 Restore thất bại
- Kiểm tra archive, giải nén ra thư mục tạm để xem cấu trúc:
```bash
tar -tzf /opt/n8n/backups/n8n_backup_YYYYmmdd_HHMMSS.tar.gz | head
```
- Đảm bảo có file DB `n8n_database.sql` hoặc `database.sql`
- Đảm bảo volumes mountpoint tồn tại trước khi restore dữ liệu

## 5. SSL HTTPS không truy cập được
- Kiểm tra chứng chỉ tồn tại:
```bash
sudo ls -l /etc/letsencrypt/live/yourdomain.com/
```
- Kiểm tra lắng nghe 443:
```bash
ss -tlnp | grep :443
```
- Kiểm tra route/proxy tới `127.0.0.1:5678` trong file Nginx cho domain

## 6. Quyền & quyền sở hữu file
- Khi gặp lỗi permission, thử dùng sudo cho thao tác hệ thống (nginx/ngả chứng chỉ/compose)
- Log Manager: `/var/log/dataonline-manager.log` (hoặc `~/.dataonline-manager.log`)

## 7. Tối ưu
- VPS yếu: giảm tải executions, chuyển queue/external DB nếu cần
- Bật HTTPS và dùng domain thật khi production
- Thiết lập cron backup daily/weekly

## 8. Liên hệ hỗ trợ
- Website: https://dataonline.vn
- GitHub: https://github.com/vanntpt/n8n-autodeploy
- Email: support@dataonline.vn
