# N8N Auto-Deploy Manager

**Công cụ quản lý và triển khai N8N tự động cho Ubuntu VPS** - Giao diện CLI tiếng Việt, dễ sử dụng, tích hợp đầy đủ tính năng.

## 🚀 Giới thiệu

N8N Auto-Deploy Manager là một script bash mạnh mẽ giúp bạn triển khai và quản lý N8N workflow automation trên Ubuntu VPS một cách nhanh chóng và chuyên nghiệp. Script được thiết kế với:

- ✅ **Giao diện CLI thân thiện** - Menu tiếng Việt, dễ hiểu, dễ sử dụng
- ✅ **Tự động hóa hoàn toàn** - Từ cài đặt Docker đến cấu hình SSL
- ✅ **Kiến trúc modular** - Dễ bảo trì, mở rộng và tùy chỉnh
- ✅ **Logging chi tiết** - Theo dõi mọi hoạt động, dễ dàng debug
- ✅ **Backup & Restore** - Bảo vệ dữ liệu, đồng bộ Google Drive
- ✅ **SSL tự động** - Tích hợp Let's Encrypt, gia hạn tự động
- ✅ **Database Manager** - Quản lý PostgreSQL, tích hợp NocoDB

## 📋 Yêu cầu hệ thống

- **OS**: Ubuntu 20.04+ (khuyến nghị 22.04 hoặc 24.04)
- **RAM**: Tối thiểu 2GB
- **Disk**: Tối thiểu 10GB trống
- **Network**: Kết nối internet ổn định
- **Quyền**: Sudo/root access

## ⚡ Cài đặt nhanh

### Bước 1: Tải và cài đặt script

```bash
# Clone repository
git clone https://github.com/vanntpt/n8n-autodeploy.git
cd n8n-autodeploy

# Chạy installer
bash install.sh
```

Script sẽ tự động:
- Kiểm tra hệ thống
- Cài đặt dependencies cần thiết
- Tạo lệnh global `dataonline-n8n-manager`

### Bước 2: Khởi chạy manager

```bash
dataonline-n8n-manager
```

Hoặc nếu chưa cài đặt global:

```bash
bash scripts/manager.sh
```

## 📖 Hướng dẫn sử dụng

### 1️⃣ Cài đặt N8N lần đầu

Sau khi chạy manager, chọn:

```
Menu chính → [1] Cài đặt N8N
```

Script sẽ hỏi bạn:
- **Port N8N** (mặc định: 5678)
- **Port PostgreSQL** (mặc định: 5432)
- **Domain** (tùy chọn - để trống nếu dùng IP)
- **Email SSL** (nếu có domain)

Sau đó script tự động:
1. ✅ Cài đặt Docker & Docker Compose (nếu chưa có)
2. ✅ Tạo cấu hình docker-compose.yml
3. ✅ Khởi động N8N, PostgreSQL, Redis
4. ✅ Cấu hình SSL/HTTPS (nếu có domain)
5. ✅ Xác minh cài đặt thành công

**Truy cập N8N:**
- Với domain: `https://domain-cua-ban.com`
- Không domain: `http://IP-VPS:5678`

### 2️⃣ Quản lý Domain & SSL

```
Menu chính → [2] Quản lý Domain & SSL
```

**Chức năng:**
- Cài đặt SSL mới cho domain
- Kiểm tra trạng thái SSL hiện tại
- Gia hạn chứng chỉ SSL
- Thiết lập gia hạn tự động (cron)
- Sửa lỗi cấu hình Nginx

**Lưu ý SSL:**
- Domain phải trỏ về IP VPS trước khi cài SSL
- Let's Encrypt có giới hạn 5 lần/tuần/domain
- Script tự động thiết lập gia hạn mỗi 60 ngày

### 3️⃣ Quản lý Services

```
Menu chính → [3] Quản lý Services
```

**Điều khiển các dịch vụ:**
- **N8N**: Start, Stop, Restart, Logs, Status
- **PostgreSQL**: Kiểm tra kết nối, backup DB, restore
- **Nginx**: Reload config, kiểm tra syntax
- **Redis**: Flush cache, monitor
- **NocoDB**: Quản lý database UI (nếu đã cài)

### 4️⃣ Backup & Restore

```
Menu chính → [4] Backup & Restore
```

**Tính năng backup:**
- Backup toàn bộ (DB + volumes + configs)
- Backup chỉ database
- Backup workflows
- Upload tự động lên Google Drive
- Lên lịch backup định kỳ (cron)

**Restore:**
- Restore từ file local
- Restore từ Google Drive
- Restore chọn lọc (DB hoặc workflows)

**Thiết lập Google Drive:**
```bash
# Cấu hình rclone (chỉ lần đầu)
rclone config
# Tạo remote tên "n8n-backups"
```

### 5️⃣ Database Manager

```
Menu chính → [5] Database Manager
```

**Quản lý PostgreSQL:**
- Xem thông tin database
- Tạo/xóa database
- Export/Import SQL
- Tối ưu hóa performance
- Kiểm tra kích thước

**NocoDB Integration:**
- Cài đặt NocoDB (Database UI)
- Kết nối với PostgreSQL của N8N
- Quản lý data qua giao diện web
- Monitoring & maintenance

### 6️⃣ Updates & Maintenance

```
Menu chính → [6] Updates
```

**Cập nhật:**
- Update N8N lên phiên bản mới nhất
- Update script manager
- Update Docker images
- Kiểm tra phiên bản hiện tại

### 7️⃣ Thông tin hệ thống

```
Menu chính → [7] Thông tin hệ thống
```

Hiển thị:
- Trạng thái các containers
- Sử dụng CPU, RAM, Disk
- Thông tin network
- Phiên bản các thành phần
- Logs gần đây

## 🏗️ Cấu trúc dự án

```
n8n-autodeploy/
├── install.sh              # Script cài đặt chính
├── scripts/
│   └── manager.sh          # Menu quản lý chính
├── src/
│   ├── core/               # Hệ thống lõi
│   │   ├── ui.sh          # Giao diện CLI
│   │   ├── logger.sh      # Logging system
│   │   ├── config.sh      # Quản lý cấu hình
│   │   ├── spinner.sh     # Progress indicators
│   │   └── utils.sh       # Utilities
│   └── plugins/           # Các module chức năng
│       ├── install/       # Cài đặt N8N
│       ├── ssl/           # Quản lý SSL
│       ├── backup/        # Backup & Restore
│       ├── database-manager/  # PostgreSQL & NocoDB
│       ├── service-management/ # Quản lý services
│       ├── upgrade/       # Updates
│       └── workflow-manager/  # Quản lý workflows
```

## 🔧 Cấu hình nâng cao

### File cấu hình

Script lưu cấu hình tại:
- **System-wide**: `/etc/dataonline-n8n/settings.conf`
- **User**: `~/.config/dataonline-n8n/settings.conf`

### Logs

- **Manager logs**: `/var/log/dataonline-manager.log`
- **N8N logs**: `docker compose logs -f n8n`
- **PostgreSQL logs**: `docker compose logs -f postgres`

### Ports mặc định

| Service    | Port  | Mô tả                    |
|------------|-------|--------------------------|
| N8N        | 5678  | Web UI & API             |
| PostgreSQL | 5432  | Database                 |
| Redis      | 6379  | Cache & Queue            |
| NocoDB     | 8080  | Database UI (tùy chọn)   |
| Nginx      | 80    | HTTP                     |
| Nginx      | 443   | HTTPS (khi có SSL)       |

## 🐛 Xử lý sự cố

### N8N không khởi động

```bash
# Kiểm tra logs
docker compose -f /opt/n8n/docker-compose.yml logs -f

# Kiểm tra port đã được sử dụng chưa
sudo netstat -tulpn | grep 5678

# Restart services
dataonline-n8n-manager → [3] Quản lý Services → Restart N8N
```

### SSL không hoạt động

```bash
# Kiểm tra domain đã trỏ đúng IP chưa
nslookup domain-cua-ban.com

# Kiểm tra Nginx config
sudo nginx -t

# Xem logs certbot
sudo cat /var/log/letsencrypt/letsencrypt.log

# Sử dụng chức năng tự động sửa lỗi
dataonline-n8n-manager → [2] Domain & SSL → Sửa lỗi Nginx
```

### Backup thất bại

```bash
# Kiểm tra dung lượng disk
df -h

# Kiểm tra quyền thư mục backup
ls -la /opt/n8n/backups

# Kiểm tra Google Drive connection
rclone lsd n8n-backups:
```

### Database lỗi

```bash
# Kiểm tra PostgreSQL
docker exec -it postgres psql -U n8n -d n8n

# Backup database ngay
dataonline-n8n-manager → [4] Backup → Backup Database

# Xem logs PostgreSQL
docker compose -f /opt/n8n/docker-compose.yml logs postgres
```

## 🤝 Đóng góp

Mọi đóng góp đều được chào đón! Vui lòng:

1. Fork repository
2. Tạo branch mới (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Tạo Pull Request

## 📝 License

Dự án này được phát hành dưới MIT License.

## 📞 Liên hệ & Hỗ trợ

- **Website**: https://dataonline.vn
- **Email**: support@dataonline.vn
- **Issues**: [GitHub Issues](https://github.com/dataonlinevn/n8n-autodeploy/issues)

## ⭐ Credits

Phát triển bởi **DataOnline Team** - Mang automation đến gần hơn với người dùng Việt Nam.

---

**Nếu script này hữu ích, đừng quên cho một ⭐ trên GitHub!**