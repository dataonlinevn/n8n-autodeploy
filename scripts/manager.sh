#!/bin/bash

# DataOnline N8N Manager
# Phiên bản: 1.0.0
# Tác giả: DataOnline Team

set -euo pipefail

# Lấy thư mục script (xử lý symlink)
# Sử dụng realpath nếu có, nếu không thì resolve thủ công
if command -v realpath >/dev/null 2>&1; then
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
else
    # Fallback: resolve symlink thủ công
    SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    while [ -h "$SCRIPT_SOURCE" ]; do
        TEMP_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
        SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
        [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$TEMP_DIR/$SCRIPT_SOURCE"
    done
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi
readonly SCRIPT_DIR
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
    # Thiết lập log level từ config
    local log_level
    log_level=$(config_get "logging.level" "info")
    set_log_level "$log_level"
}

# ===== STATUS HELPERS =====

# Get N8N installation status
get_n8n_menu_status() {
    if command_exists docker && docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
        local version=$(docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        echo -e "${UI_GREEN}Đang chạy (v$version)${UI_NC}"
    elif [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        echo -e "${UI_YELLOW}Đã cài đặt (đang dừng)${UI_NC}"
    else
        echo -e "${UI_RED}Chưa cài đặt${UI_NC}"
    fi
}

# Get SSL status
get_ssl_menu_status() {
    local domain=$(config_get "n8n.domain" "")
    if [[ -n "$domain" ]] && [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        local expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$domain/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        local days_left=$(((expiry_epoch - now_epoch) / 86400))
        
        if [[ $days_left -gt 30 ]]; then
            echo -e "${UI_GREEN}An toàn (còn $days_left ngày)${UI_NC}"
        elif [[ $days_left -gt 0 ]]; then
            echo -e "${UI_YELLOW}Sắp hết hạn ($days_left ngày)${UI_NC}"
        else
            echo -e "${UI_RED}Đã hết hạn${UI_NC}"
        fi
    else
        echo -e "${UI_GRAY}Chưa thiết lập${UI_NC}"
    fi
}

# Get backup count
get_backup_count() {
    local count=0
    if [[ -d "/opt/n8n/backups" ]]; then
        count=$(find /opt/n8n/backups -name "n8n_backup_*.tar.gz" 2>/dev/null | wc -l)
    fi
    echo "$count"
}

# Get workflow count (if N8N API available)
get_workflow_count_menu() {
    if command_exists docker && docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
        local port=$(config_get "n8n.port" "5678")
        if curl -s "http://localhost:$port/healthz" >/dev/null 2>&1; then
            # Try to get count via API (if API key available)
            local api_key_file="/opt/n8n/.n8n-api-key"
            if [[ -f "$api_key_file" ]]; then
                local api_key=$(cat "$api_key_file" 2>/dev/null)
                local response=$(curl -s -H "X-N8N-API-KEY: $api_key" "http://localhost:$port/api/v1/workflows" 2>/dev/null)
                if command_exists jq && echo "$response" | jq -e '.data' >/dev/null 2>&1; then
                    local count=$(echo "$response" | jq '.data | length' 2>/dev/null || echo "?")
                    echo "$count"
                    return 0
                fi
            fi
        fi
    fi
    echo "?"
}

# Menu chính với dashboard style
show_main_menu() {
    ui_header "$APP_NAME" "$APP_VERSION"
    
    # Get statuses
    local n8n_status=$(get_n8n_menu_status)
    local ssl_status=$(get_ssl_menu_status)
    local backup_count=$(get_backup_count)
    local workflow_count=$(get_workflow_count_menu)
    
    # Dashboard Panel
    echo -e "  ${UI_BOLD}${UI_WHITE}TRẠNG THÁI HỆ THỐNG:${UI_NC}"
    echo -e "  ${UI_CYAN}•${UI_NC}  N8N Service:     $n8n_status"
    echo -e "  ${UI_CYAN}•${UI_NC}  Domain SSL:      $ssl_status"
    echo -e "  ${UI_CYAN}•${UI_NC}  Bản sao lưu:     $backup_count bản ($workflow_count workflow)"
    echo ""
    
    # Menu Options Grouped
    echo -e "  ${UI_BOLD}${UI_WHITE}1.${UI_NC} Cài đặt N8N                  ${UI_BOLD}${UI_WHITE}A.${UI_NC} Thông tin hệ thống"
    echo -e "  ${UI_BOLD}${UI_WHITE}2.${UI_NC} Tên miền & SSL               ${UI_BOLD}${UI_WHITE}B.${UI_NC} Cấu hình Manager"
    echo -e "  ${UI_BOLD}${UI_WHITE}3.${UI_NC} Quản lý dịch vụ              ${UI_BOLD}${UI_WHITE}C.${UI_NC} Trợ giúp & Tài liệu"
    echo -e "  ${UI_BOLD}${UI_WHITE}4.${UI_NC} Sao lưu & Khôi phục          ${UI_BOLD}${UI_WHITE}D.${UI_NC} Chế độ gỡ lỗi"
    echo -e "  ${UI_BOLD}${UI_WHITE}5.${UI_NC} Nâng cấp N8N"
    echo -e "  ${UI_BOLD}${UI_WHITE}6.${UI_NC} Quản lý Database (NocoDB)"
    echo -e "  ${UI_BOLD}${UI_WHITE}7.${UI_NC} Quản lý Workflow"
    echo ""
    echo -e "  ${UI_BOLD}${UI_WHITE}0.${UI_NC} Thoát"
    echo ""
    echo -n -e "  ${UI_WHITE}Lựa chọn của bạn: ${UI_NC}"
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
        ui_info "Cảm ơn bạn đã sử dụng DataOnline N8N Manager!"
        exit 0
        ;;
    *)
        ui_error "Lựa chọn không hợp lệ"
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
        ui_error "Không tìm thấy module cài đặt"
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
    echo "3) Gia hạn chứng chỉ SSL (thủ công)"
    echo "4) Thiết lập gia hạn tự động (Cronjob)"
    echo "0) Quay lại"
    echo ""

    read -p "Chọn [0-4]: " domain_choice

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
    4)
        setup_ssl_auto_renewal
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
    domain=$(config_get "n8n.domain" "")

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

    # Kiểm tra nginx config - tìm file config dựa trên domain thực tế
    local nginx_config="/etc/nginx/sites-available/${domain}.conf"
    
    # Nếu không tìm thấy, tìm tất cả file config có chứa domain trong tên
    if [[ ! -f "$nginx_config" ]]; then
        local found_config
        found_config=$(sudo find /etc/nginx/sites-available -name "*${domain}*.conf" -type f 2>/dev/null | head -1)
        if [[ -n "$found_config" ]]; then
            nginx_config="$found_config"
        fi
    fi
    
    if [[ -f "$nginx_config" ]]; then
        # Kiểm tra file có trống không
        if [[ ! -s "$nginx_config" ]]; then
            log_warn "File cấu hình Nginx trống: $nginx_config"
            log_info "Đang tự động tạo lại cấu hình nginx..."
            
            # Tự động tạo lại nginx config
            if auto_fix_nginx_config "$domain"; then
                log_success "Đã tạo lại cấu hình Nginx"
            else
                log_error "Không thể tạo lại cấu hình Nginx"
                log_info "Gợi ý: Vui lòng chạy 'Cấu hình SSL với Let's Encrypt' để tạo lại"
            fi
        else
            log_success "Cấu hình Nginx cho $domain đã tồn tại"
        fi
    else
        log_warn "Không tìm thấy cấu hình Nginx cho $domain"
        log_info "Đang tự động tạo cấu hình nginx..."
        
        # Tự động tạo nginx config
        if auto_fix_nginx_config "$domain"; then
            log_success "Đã tạo cấu hình Nginx"
        else
            log_error "Không thể tạo cấu hình Nginx"
            log_info "Gợi ý: Vui lòng chạy 'Cấu hình SSL với Let's Encrypt' để tạo"
        fi
    fi

    # Kiểm tra chứng chỉ Let's Encrypt
    if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
        log_success "Chứng chỉ SSL đã được cài đặt"

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
            log_success "SSL còn $days_remaining ngày trước khi hết hạn"
        elif [[ $days_remaining -gt 0 ]]; then
            log_warn "SSL sẽ hết hạn trong $days_remaining ngày! Cần gia hạn sớm."
        else
            log_error "SSL đã hết hạn! Cần gia hạn ngay."
        fi
    else
        log_error "Không tìm thấy chứng chỉ SSL cho $domain"
    fi

    # Kiểm tra HTTPS
    if command_exists curl; then
        local https_status
        https_status=$(curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$domain" 2>/dev/null || echo "000")
        
        if [[ "$https_status" =~ ^(200|301|302|307|308)$ ]]; then
            log_success "HTTPS hoạt động bình thường (https://$domain) - HTTP $https_status"
        elif [[ "$https_status" == "000" ]]; then
            log_warn "Không thể kết nối đến https://$domain"
            log_info "Gợi ý: Có thể domain chưa được trỏ DNS về server này"
            log_info "Gợi ý: Hoặc firewall đang chặn kết nối"
        else
            log_warn "HTTPS trả về mã lỗi: $https_status"
            log_info "Gợi ý: Kiểm tra cấu hình nginx và SSL certificate"
        fi
    fi
}

# Tự động sửa/tạo nginx config
auto_fix_nginx_config() {
    local domain="$1"
    local n8n_port=$(config_get "n8n.port" "5678")
    
    # Kiểm tra SSL certificate có tồn tại không
    if [[ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        log_error "SSL certificate chưa được cài đặt cho $domain"
        return 1
    fi
    
    # Tìm file config hiện có dựa trên domain thực tế
    local nginx_config="/etc/nginx/sites-available/${domain}.conf"
    
    # Nếu không tìm thấy, tìm tất cả file config có chứa domain trong tên
    if [[ ! -f "$nginx_config" ]]; then
        local found_config
        found_config=$(sudo find /etc/nginx/sites-available -name "*${domain}*.conf" -type f 2>/dev/null | head -1)
        if [[ -n "$found_config" ]]; then
            nginx_config="$found_config"
        fi
    fi
    
    # Source SSL nginx module để dùng hàm create_nginx_ssl_config
    local ssl_nginx_module="$PROJECT_ROOT/src/plugins/ssl/ssl-nginx.sh"
    if [[ -f "$ssl_nginx_module" ]]; then
        # Định nghĩa WEBROOT_PATH nếu chưa có (không dùng readonly trong function)
        if [[ -z "${WEBROOT_PATH:-}" ]]; then
            export WEBROOT_PATH="/var/www/html"
        fi
        
        source "$ssl_nginx_module"
        
        # Tạo lại nginx config (suppress output để không làm rối UI)
        if create_nginx_ssl_config "$domain" "$n8n_port" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Fallback: Tạo config thủ công nếu không có module
    log_info "Tạo nginx config thủ công..."
    
    sudo tee "$nginx_config" > /dev/null <<EOF
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    client_max_body_size 100M;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    location / {
        proxy_pass http://127.0.0.1:$n8n_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

    # Enable site
    sudo ln -sf "$nginx_config" /etc/nginx/sites-enabled/ 2>/dev/null || true
    
    # Test và reload nginx
    if sudo nginx -t >/dev/null 2>&1; then
        sudo systemctl reload nginx >/dev/null 2>&1
        return 0
    else
        log_error "Nginx config có lỗi syntax"
        return 1
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
        log_success "[OK] Gia hạn SSL thành công"

        # Khởi động lại Nginx
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx
            log_success "[OK] Đã khởi động lại Nginx"
        fi
    else
        log_error "[FAIL] Gia hạn SSL thất bại"
        log_info "Kiểm tra logs: /var/log/letsencrypt/"
    fi
}

# Thiết lập gia hạn SSL tự động
setup_ssl_auto_renewal() {
    echo ""
    ui_section "Thiết lập Gia hạn SSL Tự động"

    if ! command_exists certbot; then
        ui_error "Certbot chưa được cài đặt. Vui lòng cấu hình SSL trước."
        return 1
    fi

    local cron_file="/etc/cron.d/certbot-renewal"
    local cron_exists=false
    
    # Check existing cronjob
    if [[ -f "$cron_file" ]] || crontab -l 2>/dev/null | grep -q "certbot"; then
        cron_exists=true
        ui_info "Đã phát hiện cronjob gia hạn SSL đang hoạt động."
    fi

    echo ""
    echo "TRẠNG THÁI HIỆN TẠI:"
    if [[ "$cron_exists" == "true" ]]; then
        echo "  [OK] Gia hạn tự động: Đã kích hoạt"
        if [[ -f "$cron_file" ]]; then
            echo "  Lịch chạy: $(cat "$cron_file" | grep certbot | head -1 | awk '{print $1,$2,$3,$4,$5}')"
        fi
    else
        echo "  [FAIL] Gia hạn tự động: Chưa thiết lập"
    fi
    echo ""

    echo "1) Kích hoạt gia hạn tự động (2 lần/ngày)"
    echo "2) Tắt gia hạn tự động"
    echo "3) Kiểm tra lịch sử gia hạn"
    echo "0) Quay lại"
    echo ""

    read -p "Chọn [0-3]: " auto_choice

    case "$auto_choice" in
    1)
        ui_start_spinner "Đang thiết lập cronjob..."
        
        # Create cronjob file (runs at 3:00 AM and 3:00 PM daily)
        sudo tee "$cron_file" > /dev/null <<EOF
# Certbot SSL Auto-Renewal - Installed by DataOnline N8N Manager
# Runs twice daily as recommended by Let's Encrypt
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

0 3,15 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx" >> /var/log/certbot-renewal.log 2>&1
EOF
        
        sudo chmod 644 "$cron_file"
        ui_stop_spinner
        ui_success "Đã kích hoạt gia hạn tự động!"
        ui_info "SSL sẽ được kiểm tra và gia hạn tự động lúc 3:00 và 15:00 mỗi ngày."
        ;;
    2)
        if [[ -f "$cron_file" ]]; then
            sudo rm -f "$cron_file"
            ui_success "Đã tắt gia hạn tự động."
        else
            ui_info "Chưa có cronjob nào được thiết lập."
        fi
        ;;
    3)
        echo ""
        ui_section "Lịch sử Gia hạn SSL"
        if [[ -f "/var/log/certbot-renewal.log" ]]; then
            tail -20 /var/log/certbot-renewal.log
        else
            ui_info "Chưa có log gia hạn. Cronjob có thể chưa chạy lần nào."
        fi
        ;;
    0)
        return
        ;;
    *)
        ui_error "Lựa chọn không hợp lệ"
        ;;
    esac
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
        echo " Troubleshooting:"
        echo "1. Kiểm tra plugin đã được cài đặt đúng chưa:"
        echo "   ls -la $PROJECT_ROOT/src/plugins/database-manager/"
        echo ""
        echo "2. Plugin files cần có:"
        echo "   [OK] main.sh - Entry point"
        echo "   [OK] nocodb-setup.sh - Docker integration"
        echo "   [OK] nocodb-config.sh - Views configuration"
        echo "   [OK] nocodb-management.sh - Operations"
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

    echo "----------------------------------------"
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
        echo "  N8N: Đã cài đặt"
        if command_exists docker; then
            local n8n_version=$(docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
            echo "  Version: $n8n_version"
            echo "  Status: $(docker ps --format '{{.Status}}' --filter 'name=n8n' | head -1 || echo "Stopped")"
        fi
    else
        echo "  N8N: Chưa cài đặt"
    fi
    
    echo ""
    echo "Database Manager:"
    if [[ -f "$PROJECT_ROOT/src/plugins/database-manager/main.sh" ]]; then
        echo "  Plugin: Đã cài đặt"
        echo "  Files: $(ls -1 "$PROJECT_ROOT/src/plugins/database-manager/" 2>/dev/null | wc -l) files"
        
        # Check NocoDB status if possible
        if command_exists docker && docker ps --format '{{.Names}}' | grep -q "nocodb"; then
            echo "  NocoDB: Đang chạy"
        elif command_exists curl && curl -s "http://localhost:8080/api/v1/health" >/dev/null 2>&1; then
            echo "  NocoDB: API available"
        else
            echo "  NocoDB: Chưa chạy"
        fi
    else
        echo "  Plugin: Chưa cài đặt"
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

    echo "----------------------------------------"
    echo "Liên hệ hỗ trợ:"
    echo "  • Website: https://dataonline.vn"
    echo "  • Tài liệu: https://docs.dataonline.vn/n8n-manager"
    echo "  • Hỗ trợ: support@dataonline.vn"
    echo "  • GitHub: https://github.com/vanntpt/n8n-autodeploy"
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
    echo "  • Monitoring & maintenance tools"
    echo "  • Integration testing"
    echo "----------------------------------------"
    echo ""
}

# Vòng lặp chính
main() {
    init_app

    while true; do
        show_main_menu
        read -r choice
        echo ""
        handle_selection "$choice"
        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

# Chạy hàm main
main "$@"