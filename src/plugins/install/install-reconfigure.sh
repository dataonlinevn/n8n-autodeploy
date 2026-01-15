#!/bin/bash

# DataOnline N8N Manager - Reconfigure Module
# Hỗ trợ chuyển đổi từ IP sang Domain/SSL
# Phiên bản: 1.0.0

set -euo pipefail

# Get script directory
RECONFIGURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$RECONFIGURE_DIR")")")"

# Source required modules
if [[ -z "${INSTALL_COMPOSE_LOADED:-}" ]]; then
    source "$RECONFIGURE_DIR/install-compose.sh"
fi

# Hàm chuyển đổi từ IP sang Domain/SSL
reconfigure_to_domain() {
    local new_domain="$1"
    local ssl_email="$2"
    
    ui_section "CHUYỂN ĐỔI SANG DOMAIN/SSL"
    
    # Kiểm tra N8N đã cài đặt
    if [[ ! -f "/opt/n8n/docker-compose.yml" ]]; then
        ui_error "N8N chưa được cài đặt"
        return 1
    fi
    
    # Validate domain
    if ! ui_validate_domain "$new_domain"; then
        ui_error "Tên miền không hợp lệ: $new_domain"
        return 1
    fi
    
    ui_warning_box "CẢNH BÁO BẢO MẬT" \
        "Hệ thống sẽ thực hiện các thay đổi sau:" \
        "" \
        "1. Cài đặt SSL certificate cho $new_domain" \
        "2. Cấu hình Nginx reverse proxy (HTTPS)" \
        "3. THAY ĐỔI PORT BINDING: 0.0.0.0 → 127.0.0.1" \
        "   (Chặn truy cập HTTP trực tiếp từ bên ngoài)" \
        "" \
        "Sau khi hoàn tất, chỉ có thể truy cập qua:" \
        "  ✓ https://$new_domain (An toàn)" \
        "  ✗ http://IP:5678 (Bị chặn)"
    
    if ! ui_confirm "Bạn có chắc chắn muốn tiếp tục?"; then
        return 0
    fi
    
    # Backup current configuration
    ui_start_spinner "Đang sao lưu cấu hình hiện tại..."
    local backup_dir="/opt/n8n/backups/config-$(date +%Y%m%d-%H%M%S)"
    sudo mkdir -p "$backup_dir"
    sudo cp /opt/n8n/docker-compose.yml "$backup_dir/"
    sudo cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || true
    ui_stop_spinner
    ui_success "Đã sao lưu cấu hình tại: $backup_dir"
    
    # Update environment variables
    N8N_DOMAIN="$new_domain"
    N8N_SSL_EMAIL="$ssl_email"
    N8N_WEBHOOK_URL="https://$new_domain"
    N8N_PORT=$(config_get "n8n.port" "5678")
    POSTGRES_PORT=$(config_get "postgres.port" "5432")
    
    # Regenerate docker-compose with new settings
    ui_info "Đang cập nhật cấu hình Docker..."
    if ! create_docker_compose; then
        ui_error "Không thể cập nhật cấu hình Docker"
        ui_info "Khôi phục từ backup: $backup_dir"
        return 1
    fi
    
    # Restart containers
    ui_info "Đang khởi động lại containers..."
    cd /opt/n8n
    if ! sudo docker compose up -d; then
        ui_error "Không thể khởi động lại containers"
        return 1
    fi
    
    # Setup SSL
    ui_info "Đang cấu hình SSL..."
    
    # Source SSL plugin
    local ssl_plugin="$PROJECT_ROOT/src/plugins/ssl/main.sh"
    if [[ ! -f "$ssl_plugin" ]]; then
        ui_error "Không tìm thấy SSL plugin"
        return 1
    fi
    
    source "$ssl_plugin"
    
    # Install certbot if needed
    if ! command_exists certbot; then
        install_certbot || return 1
    fi
    
    # Create nginx config and obtain SSL
    create_nginx_http_config "$new_domain" "$N8N_PORT" || return 1
    
    if obtain_ssl_certificate "$new_domain" "$ssl_email"; then
        create_nginx_ssl_config "$new_domain" "$N8N_PORT" || return 1
        setup_auto_renewal || ui_warning "Không thể thiết lập gia hạn tự động"
        
        # Update config
        config_set "n8n.domain" "$new_domain"
        config_set "n8n.webhook_url" "$N8N_WEBHOOK_URL"
        config_set "n8n.ssl_enabled" "true"
        config_set "n8n.ssl_email" "$ssl_email"
        
        ui_info_box "CHUYỂN ĐỔI THÀNH CÔNG" \
            "Địa chỉ mới:     https://$new_domain" \
            "Bảo mật:         SSL/TLS (Let's Encrypt)" \
            "Port binding:    127.0.0.1:$N8N_PORT (localhost only)" \
            "" \
            "⚠️  LƯU Ý QUAN TRỌNG:" \
            "Không thể truy cập qua HTTP (http://IP:5678) nữa" \
            "Điều này đảm bảo mọi kết nối đều được mã hóa"
        
        return 0
    else
        ui_error "Không thể cấu hình SSL"
        ui_info "Bạn có thể thử lại sau hoặc khôi phục từ: $backup_dir"
        return 1
    fi
}

# Hàm kiểm tra trạng thái bảo mật
check_security_status() {
    ui_section "KIỂM TRA BẢO MẬT"
    
    local domain=$(config_get "n8n.domain" "")
    local port=$(config_get "n8n.port" "5678")
    
    echo ""
    echo "Cấu hình hiện tại:"
    echo "  Domain: ${domain:-'[Không sử dụng]'}"
    echo "  Port: $port"
    echo ""
    
    # Kiểm tra port binding
    if docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
        local port_binding=$(docker port n8n 5678 2>/dev/null || echo "")
        
        echo "Port Binding:"
        if [[ "$port_binding" =~ ^127\.0\.0\.1 ]]; then
            echo -e "  ${UI_GREEN}✓ 127.0.0.1:$port (Localhost only - BẢO MẬT)${UI_NC}"
            echo "    → Chỉ Nginx mới có thể truy cập N8N"
        elif [[ "$port_binding" =~ ^0\.0\.0\.0 ]]; then
            echo -e "  ${UI_YELLOW}⚠ 0.0.0.0:$port (Public - CẦN CHÚ Ý)${UI_NC}"
            if [[ -n "$domain" ]]; then
                echo -e "    ${UI_RED}→ LỖ HỔNG BẢO MẬT: Có thể bypass HTTPS qua HTTP${UI_NC}"
                echo "    → Khuyến nghị: Chạy lại cài đặt hoặc reconfigure"
            else
                echo "    → OK cho cấu hình chỉ dùng IP"
            fi
        else
            echo "  ✗ Không xác định được: $port_binding"
        fi
    else
        echo "  ✗ N8N container không chạy"
    fi
    
    echo ""
    
    # Kiểm tra SSL
    if [[ -n "$domain" ]]; then
        echo "SSL Status:"
        if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
            local expiry=$(openssl x509 -in "/etc/letsencrypt/live/$domain/fullchain.pem" -noout -enddate | cut -d= -f2)
            echo -e "  ${UI_GREEN}✓ SSL Certificate: Đã cài đặt${UI_NC}"
            echo "    Hết hạn: $expiry"
        else
            echo -e "  ${UI_RED}✗ SSL Certificate: Chưa cài đặt${UI_NC}"
        fi
    fi
    
    echo ""
}

export -f reconfigure_to_domain check_security_status
