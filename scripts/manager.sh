#!/bin/bash

# DataOnline N8N Manager
# Phiên bản: 1.0.0
# Tác giả: DataOnline Team

set -euo pipefail

# Lấy thư mục script
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source các module core
source "$PROJECT_ROOT/src/core/logger.sh"
source "$PROJECT_ROOT/src/core/config.sh"
source "$PROJECT_ROOT/src/core/utils.sh"
source "$PROJECT_ROOT/src/core/ui.sh"
source "$PROJECT_ROOT/src/core/spinner.sh"

# Thông tin ứng dụng
readonly APP_NAME="$(config_get "app.name")"
readonly APP_VERSION="$(config_get "app.version")"

# Khởi tạo ứng dụng
init_app() {
    log_debug "Đang khởi tạo DataOnline N8N Manager..."

    # Thiết lập log level từ config
    local log_level
    log_level=$(config_get "logging.level")
    set_log_level "$log_level"

    log_debug "Ứng dụng đã được khởi tạo"
}

# Menu chính
show_main_menu() {
    clear
    echo -e "${LOG_CYAN}╭──────────────────────────────────────────────────────────╮${LOG_NC}"
    echo -e "${LOG_CYAN}│                $APP_NAME                    │${LOG_NC}"
    echo -e "${LOG_CYAN}│              Phiên bản phát triển v$APP_VERSION                 │${LOG_NC}"
    echo -e "${LOG_CYAN}│                https://datalonline.vn                    │${LOG_NC}"
    echo -e "${LOG_CYAN}╰──────────────────────────────────────────────────────────╯${LOG_NC}"
    echo ""
    echo -e "${LOG_WHITE}CHỨC NĂNG CHÍNH:${LOG_NC}"
    echo -e "1️⃣  🚀 Cài đặt N8N"
    echo -e "2️⃣  🌐 Quản lý tên miền & SSL"
    echo -e "3️⃣  ⚙️  Quản lý dịch vụ"
    echo -e "4️⃣  💾 Sao lưu & khôi phục"
    echo -e "5️⃣  🔄 Cập nhật phiên bản"
    echo -e "6️⃣  🗄️  Quản lý Database"
    echo -e "7️⃣  🔄 Workflow Manager"
    echo ""
    echo -e "${LOG_WHITE}HỖ TRỢ:${LOG_NC}"
    echo -e "A️  📋 Thông tin hệ thống"
    echo -e "B️  🔧 Cấu hình"
    echo -e "C️  📚 Trợ giúp & tài liệu"
    echo -e "D️  🧪 Chế độ debug"
    echo ""
    echo -e "0️⃣  ❌ Thoát"
    echo ""
    echo -e "${LOG_CYAN}───────────────────────────────────────────────────────────${LOG_NC}"
}

# Xử lý lựa chọn menu
handle_selection() {
    local choice="$1"

    case "$choice" in
    1) handle_installation ;;
    2) handle_domain_management ;;
    3) handle_service_management ;;
    4) handle_backup_restore ;;
    5) handle_updates ;;
    6) handle_database_management ;;
    7) handle_workflow_management ;;
    A | a) show_system_info ;;
    B | b) show_configuration_menu ;;
    C | c) show_help ;;
    D | d) toggle_debug_mode ;;
    0)
        log_success "Cảm ơn bạn đã sử dụng DataOnline N8N Manager!"
        exit 0
        ;;
    *)
        log_error "Lựa chọn không hợp lệ: $choice"
        ;;
    esac
}

# Xử lý cài đặt
handle_installation() {
    # Source plugin cài đặt
    local install_plugin="$PROJECT_ROOT/src/plugins/install/main.sh"

    if [[ -f "$install_plugin" ]]; then
        source "$install_plugin"
        # Gọi hàm main của plugin
        install_n8n_main
    else
        log_error "Không tìm thấy plugin cài đặt"
        log_info "Đường dẫn: $install_plugin"
        return 1
    fi
}

# Xử lý quản lý domain
handle_domain_management() {
    echo ""
    log_info "QUẢN LÝ TÊN MIỀN & SSL"
    echo ""

    # Kiểm tra n8n đã được cài đặt
    if ! is_n8n_installed; then
        log_error "N8N chưa được cài đặt. Vui lòng cài đặt N8N trước."
        return 1
    fi

    # Menu quản lý domain
    echo "1) Cấu hình SSL với Let's Encrypt"
    echo "2) Kiểm tra trạng thái SSL"
    echo "3) Gia hạn chứng chỉ SSL"
    echo "0) Quay lại"
    echo ""

    read -p "Chọn [0-3]: " domain_choice

    case "$domain_choice" in
    1)
        # Source plugin SSL
        local ssl_plugin="$PROJECT_ROOT/src/plugins/ssl/main.sh"
        if [[ -f "$ssl_plugin" ]]; then
            source "$ssl_plugin"
            # Gọi hàm main của plugin
            setup_ssl_main
        else
            log_error "Không tìm thấy plugin SSL"
            log_info "Đường dẫn: $ssl_plugin"
        fi
        ;;
    2)
        check_ssl_status
        ;;
    3)
        renew_ssl_certificate
        ;;
    0)
        return
        ;;
    *)
        log_error "Lựa chọn không hợp lệ: $domain_choice"
        ;;
    esac
}

# Kiểm tra N8N đã cài đặt chưa
is_n8n_installed() {
    # Kiểm tra qua docker hoặc dịch vụ
    if command_exists docker && docker ps --format '{{.Names}}' | grep -q "n8n"; then
        return 0 # N8N đã được cài đặt
    elif is_service_running "n8n"; then
        return 0 # N8N đã được cài đặt
    else
        return 1 # N8N chưa được cài đặt
    fi
}

# Kiểm tra trạng thái SSL
check_ssl_status() {
    echo ""
    log_info "KIỂM TRA TRẠNG THÁI SSL"
    echo ""

    # Kiểm tra domain từ cấu hình
    local domain
    domain=$(config_get "n8n.domain")

    if [[ -z "$domain" ]]; then
        log_error "Chưa cấu hình domain trong hệ thống"
        echo -n -e "${LOG_WHITE}Nhập tên miền để kiểm tra: ${LOG_NC}"
        read -r domain

        if [[ -z "$domain" ]]; then
            log_error "Domain không được để trống"
            return 1
        fi
    fi

    log_info "Đang kiểm tra SSL cho domain: $domain"

    # Kiểm tra nginx config
    if [[ -f "/etc/nginx/sites-available/${domain}.conf" ]]; then
        log_success "✅ Cấu hình Nginx cho $domain đã tồn tại"
    else
        log_error "❌ Không tìm thấy cấu hình Nginx cho $domain"
    fi

    # Kiểm tra chứng chỉ Let's Encrypt
    if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
        log_success "✅ Chứng chỉ SSL đã được cài đặt"

        # Kiểm tra ngày hết hạn
        local expiry_date
        expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -enddate | cut -d= -f2)
        local expiry_epoch
        expiry_epoch=$(date -d "$expiry_date" +%s)
        local now_epoch
        now_epoch=$(date +%s)
        local days_remaining
        days_remaining=$(((expiry_epoch - now_epoch) / 86400))

        if [[ $days_remaining -gt 30 ]]; then
            log_success "✅ SSL còn $days_remaining ngày trước khi hết hạn"
        elif [[ $days_remaining -gt 0 ]]; then
            log_warning "⚠️ SSL sẽ hết hạn trong $days_remaining ngày! Cần gia hạn sớm."
        else
            log_error "❌ SSL đã hết hạn! Cần gia hạn ngay."
        fi
    else
        log_error "❌ Không tìm thấy chứng chỉ SSL cho $domain"
    fi

    # Kiểm tra HTTPS
    if command_exists curl; then
        if curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "200\|301\|302"; then
            log_success "✅ HTTPS hoạt động bình thường (https://$domain)"
        else
            log_error "❌ HTTPS không hoạt động (https://$domain)"
        fi
    fi
}

# Gia hạn chứng chỉ SSL
renew_ssl_certificate() {
    echo ""
    log_info "GIA HẠN CHỨNG CHỈ SSL"
    echo ""

    if ! command_exists certbot; then
        log_error "Certbot chưa được cài đặt"
        return 1
    fi

    log_info "Đang thực hiện gia hạn SSL..."

    if certbot renew; then
        log_success "✅ Gia hạn SSL thành công"

        # Khởi động lại Nginx
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx
            log_success "✅ Đã khởi động lại Nginx"
        fi
    else
        log_error "❌ Gia hạn SSL thất bại"
        log_info "Kiểm tra logs: /var/log/letsencrypt/"
    fi
}

# Xử lý quản lý dịch vụ
handle_service_management() {
    # Source service management plugin
    local service_plugin="$PROJECT_ROOT/src/plugins/service-management/main.sh"

    if [[ -f "$service_plugin" ]]; then
        source "$service_plugin"
        service_management_main
    else
        log_error "Không tìm thấy service management plugin"
        return 1
    fi
}

# Xử lý backup & restore
handle_backup_restore() {
    # Source plugin backup
    local backup_plugin="$PROJECT_ROOT/src/plugins/backup/main.sh"

    if [[ -f "$backup_plugin" ]]; then
        source "$backup_plugin"
        # Gọi menu backup
        backup_menu_main
    else
        log_error "Không tìm thấy plugin backup"
        log_info "Đường dẫn: $backup_plugin"
        return 1
    fi
}

# Xử lý updates
handle_updates() {
    # Source upgrade plugin
    local upgrade_plugin="$PROJECT_ROOT/src/plugins/upgrade/main.sh"

    if [[ -f "$upgrade_plugin" ]]; then
        source "$upgrade_plugin"
        upgrade_n8n_main
    else
        log_error "Không tìm thấy upgrade plugin"
        return 1
    fi
}

# Xử lý quản lý database
handle_database_management() {
    # Source database manager plugin
    local database_plugin="$PROJECT_ROOT/src/plugins/database-manager/main.sh"
    
    if [[ -f "$database_plugin" ]]; then
        source "$database_plugin"
        # Gọi hàm main của database manager
        database_manager_main
    else
        echo ""
        log_error "Không tìm thấy Database Manager plugin"
        log_info "Đường dẫn: $database_plugin"
        echo ""
        echo "🔧 Troubleshooting:"
        echo "1. Kiểm tra plugin đã được cài đặt đúng chưa:"
        echo "   ls -la $PROJECT_ROOT/src/plugins/database-manager/"
        echo ""
        echo "2. Plugin files cần có:"
        echo "   ✅ main.sh - Entry point"
        echo "   ✅ nocodb-setup.sh - Docker integration"
        echo "   ✅ nocodb-config.sh - Views configuration"
        echo "   ✅ nocodb-management.sh - Operations"
        echo ""
        echo "3. Tạo plugin files nếu chưa có:"
        echo "   mkdir -p $PROJECT_ROOT/src/plugins/database-manager/"
        echo "   # Copy plugin files vào directory này"
        echo ""
        echo "4. Set permissions:"
        echo "   chmod +x $PROJECT_ROOT/src/plugins/database-manager/*.sh"
        echo ""
        read -p "Nhấn Enter để tiếp tục..."
        return 1
    fi
}

# Xử lý quản lý workflow
handle_workflow_management() {
    local workflow_plugin="$PROJECT_ROOT/src/plugins/workflow-manager/main.sh"
    if [[ -f "$workflow_plugin" ]]; then
        source "$workflow_plugin"
        workflow_manager_main
    else
        log_error "Workflow Manager plugin không tồn tại"
        return 1
    fi
}

# Thông tin hệ thống nâng cao
show_system_info() {
    echo ""
    log_info "THÔNG TIN HỆ THỐNG:"
    echo ""

    echo "════════════════════════════════════════"
    echo "Thông tin OS:"
    echo "  OS: $(lsb_release -d | cut -f2)"
    echo "  Kernel: $(uname -r)"
    echo "  Kiến trúc: $(uname -m)"
    echo ""

    echo "Phần cứng:"
    echo "  CPU: $(nproc) cores"
    echo "  RAM: $(free -h | awk '/^Mem:/ {print $2}') tổng, $(free -h | awk '/^Mem:/ {print $7}') có sẵn"
    echo "  Đĩa: $(df -h / | awk 'NR==2 {print $4}') có sẵn trên /"
    echo ""

    echo "Mạng:"
    if command_exists curl; then
        local public_ip
        if public_ip=$(get_public_ip); then
            echo "  IP công khai: $public_ip"
        else
            echo "  IP công khai: Không thể xác định"
        fi
    fi
    echo "  Hostname: $(hostname)"
    echo ""

    echo "Dịch vụ:"
    echo "  Docker: $(command_exists docker && echo "$(docker --version | cut -d' ' -f3 | cut -d',' -f1)" || echo "Chưa cài đặt")"
    echo "  Node.js: $(command_exists node && echo "$(node --version)" || echo "Chưa cài đặt")"
    echo "  Nginx: $(command_exists nginx && echo "$(nginx -v 2>&1 | cut -d' ' -f3)" || echo "Chưa cài đặt")"
    echo ""

    echo "DataOnline Manager:"
    echo "  Phiên bản: $APP_VERSION"
    echo "  File cấu hình: $CONFIG_FILE"
    echo "  File log: $(config_get "logging.file")"
    
    echo ""
    echo "N8N Status:"
    if is_n8n_installed; then
        echo "  N8N: ✅ Đã cài đặt"
        if command_exists docker; then
            local n8n_version=$(docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
            echo "  Version: $n8n_version"
            echo "  Status: $(docker ps --format '{{.Status}}' --filter 'name=n8n' | head -1 || echo "Stopped")"
        fi
    else
        echo "  N8N: ❌ Chưa cài đặt"
    fi
    
    echo ""
    echo "Database Manager:"
    if [[ -f "$PROJECT_ROOT/src/plugins/database-manager/main.sh" ]]; then
        echo "  Plugin: ✅ Đã cài đặt"
        echo "  Files: $(ls -1 "$PROJECT_ROOT/src/plugins/database-manager/" 2>/dev/null | wc -l) files"
        
        # Check NocoDB status if possible
        if command_exists docker && docker ps --format '{{.Names}}' | grep -q "nocodb"; then
            echo "  NocoDB: ✅ Đang chạy"
        elif command_exists curl && curl -s "http://localhost:8080/api/v1/health" >/dev/null 2>&1; then
            echo "  NocoDB: ✅ API available"
        else
            echo "  NocoDB: ❌ Chưa chạy"
        fi
    else
        echo "  Plugin: ❌ Chưa cài đặt"
    fi
    
    echo "════════════════════════════════════════"
    echo ""
}

# Menu cấu hình
show_configuration_menu() {
    echo ""
    log_info "CẤU HÌNH HỆ THỐNG"
    echo ""

    echo "1) Xem cấu hình hiện tại"
    echo "2) Thay đổi log level"
    echo "3) Kiểm tra cấu hình"
    echo "0) Quay lại"
    echo ""

    read -p "Chọn [0-3]: " config_choice

    case "$config_choice" in
    1) show_config ;;
    2) change_log_level ;;
    3) validate_config ;;
    0) return ;;
    *) log_error "Lựa chọn không hợp lệ: $config_choice" ;;
    esac
}

# Thay đổi log level
change_log_level() {
    echo ""
    log_info "THAY ĐỔI LOG LEVEL"
    echo ""

    echo "Log level hiện tại: $(config_get "logging.level")"
    echo ""
    echo "Các level có sẵn:"
    echo "1) debug - Hiện tất cả tin nhắn"
    echo "2) info - Hiện info, cảnh báo, lỗi"
    echo "3) warn - Chỉ hiện cảnh báo và lỗi"
    echo "4) error - Chỉ hiện lỗi"
    echo ""

    read -p "Chọn level [1-4]: " level_choice

    case "$level_choice" in
    1) config_set "logging.level" "debug" && set_log_level "debug" ;;
    2) config_set "logging.level" "info" && set_log_level "info" ;;
    3) config_set "logging.level" "warn" && set_log_level "warn" ;;
    4) config_set "logging.level" "error" && set_log_level "error" ;;
    *) log_error "Lựa chọn không hợp lệ: $level_choice" ;;
    esac
}

# Bật/tắt debug mode
toggle_debug_mode() {
    local current_debug
    current_debug=$(config_get "app.debug")

    if [[ "$current_debug" == "true" ]]; then
        config_set "app.debug" "false"
        set_log_level "info"
        log_success "Đã tắt chế độ debug"
    else
        config_set "app.debug" "true"
        set_log_level "debug"
        log_success "Đã bật chế độ debug"
    fi
}

# Thông tin trợ giúp
show_help() {
    echo ""
    log_info "TRỢ GIÚP & TÀI LIỆU"
    echo ""

    echo "════════════════════════════════════════"
    echo "Liên hệ hỗ trợ:"
    echo "  • Website: https://dataonline.vn"
    echo "  • Tài liệu: https://docs.dataonline.vn/n8n-manager"
    echo "  • Hỗ trợ: support@dataonline.vn"
    echo "  • GitHub: https://github.com/dataonline-vn/n8n-manager"
    echo ""
    echo "Phím tắt:"
    echo "  • Ctrl+C: Thoát khẩn cấp"
    echo "  • Enter: Tiếp tục"
    echo ""
    echo "Thông tin phiên bản:"
    echo "  • Phiên bản: $APP_VERSION"
    echo "  • Build: Development"
    echo "  • Hỗ trợ: Ubuntu 24.04+"
    echo ""
    echo "Database Manager:"
    echo "  • NocoDB integration cho web interface"
    echo "  • Thay thế CLI commands phức tạp"
    echo "  • Mobile-friendly dashboard"
    echo "  • User management & permissions"
    echo "  • Export/import capabilities"
    echo "════════════════════════════════════════"
    echo ""
}

# Vòng lặp chính
main() {
    # Khởi tạo ứng dụng
    init_app

    log_debug "Bắt đầu vòng lặp ứng dụng chính"

    while true; do
        show_main_menu
        read -p "Nhập lựa chọn [1-6, A-D, 0]: " choice
        echo ""
        handle_selection "$choice"
        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

# Chạy hàm main
main "$@"