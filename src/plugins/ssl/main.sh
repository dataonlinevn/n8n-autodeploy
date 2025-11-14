#!/bin/bash

# DataOnline N8N Manager - SSL Automation Plugin
# Phiên bản: 1.0.0
# Tự động hóa cài đặt SSL cho N8N với Let's Encrypt

set -euo pipefail

# Source core modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$PLUGIN_DIR")")"

[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
[[ -z "${SPINNER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"

# Constants
readonly SSL_LOADED=true
readonly WEBROOT_PATH="/var/www/html"
readonly CERTBOT_LOG="/var/log/letsencrypt"

# Load sub-modules (override local definitions)
source "$PLUGIN_DIR/ssl-domain.sh"
source "$PLUGIN_DIR/ssl-nginx.sh"
source "$PLUGIN_DIR/ssl-certbot.sh"
source "$PLUGIN_DIR/ssl-verify.sh"

# ===== MAIN SSL SETUP FUNCTION =====

setup_ssl_main() {
    ui_header "Cài đặt SSL với Let's Encrypt"
    
    echo ""
    echo -e "${UI_CYAN}🚀 Script sẽ tự động cấu hình hoàn chỉnh SSL cho N8N${UI_NC}"
    echo -e "${UI_GRAY}   • Tự động tạo nginx config${UI_NC}"
    echo -e "${UI_GRAY}   • Tự động lấy SSL certificate${UI_NC}"
    echo -e "${UI_GRAY}   • Tự động cấu hình N8N cho HTTPS${UI_NC}"
    echo -e "${UI_GRAY}   • Tự động verify và test${UI_NC}"
    echo ""

    # Get domain
    echo -e "${UI_CYAN}📝 Nhập domain cho N8N:${UI_NC}"
    echo -e "${UI_GRAY}   • Domain chính (ví dụ: example.com)${UI_NC}"
    echo -e "${UI_GRAY}   • Hoặc subdomain (ví dụ: n8n.example.com)${UI_NC}"
    echo -e "${UI_GRAY}   • Đảm bảo domain đã được trỏ DNS về server này${UI_NC}"
    echo ""
    echo -n -e "${UI_WHITE}Domain: ${UI_NC}"
    read -r domain

    if [[ -z "$domain" ]]; then
        ui_error "Domain không được để trống" "EMPTY_DOMAIN"
        return 1
    fi

    if ! ui_validate_domain "$domain"; then
        ui_error "Domain không hợp lệ: $domain" "INVALID_DOMAIN"
        echo ""
        echo -e "${UI_YELLOW}💡 Ví dụ domain hợp lệ:${UI_NC}"
        echo -e "   • example.com"
        echo -e "   • n8n.example.com"
        echo -e "   • app.example.com"
        return 1
    fi

    # Get email
    echo ""
    echo -e "${UI_CYAN}📧 Nhập email cho Let's Encrypt:${UI_NC}"
    echo -e "${UI_GRAY}   • Email để nhận thông báo về SSL certificate${UI_NC}"
    echo ""
    echo -n -e "${UI_WHITE}Email: ${UI_NC}"
    read -r email

    if [[ -z "$email" ]]; then
        email="admin@$domain"
        ui_info "Sử dụng email mặc định: $email"
    fi

    if ! ui_validate_email "$email"; then
        ui_error "Email không hợp lệ: $email" "INVALID_EMAIL"
        return 1
    fi

    # Tự động detect N8N port
    local n8n_port=$(config_get "n8n.port" "")
    if [[ -z "$n8n_port" ]]; then
        # Thử detect từ docker
        if command_exists docker && docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
            n8n_port=$(docker port n8n 2>/dev/null | grep -oP '0.0.0.0:\K[0-9]+' | head -1 || echo "5678")
            ui_info "Tự động phát hiện N8N port: $n8n_port"
        else
            n8n_port="5678"
            ui_info "Sử dụng port mặc định: $n8n_port"
        fi
    else
        ui_info "Sử dụng port từ config: $n8n_port"
    fi

    # Hiển thị thông tin và xác nhận
    echo ""
    ui_info_box "Thông tin SSL setup" \
        "Domain: $domain" \
        "Email: $email" \
        "N8N Port: $n8n_port" \
        "" \
        "Script sẽ tự động:" \
        "  1. Kiểm tra và cài đặt dependencies" \
        "  2. Tạo nginx HTTP config" \
        "  3. Lấy SSL certificate từ Let's Encrypt" \
        "  4. Tạo nginx HTTPS config" \
        "  5. Cấu hình N8N cho HTTPS" \
        "  6. Setup auto-renewal" \
        "  7. Verify và test"

    echo ""
    echo -n -e "${UI_YELLOW}Tiếp tục cài đặt SSL? [Y/n]: ${UI_NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        ui_info "Đã hủy cài đặt SSL"
        return 0
    fi

    echo ""
    ui_section "Bắt đầu cài đặt SSL tự động"

    # Step 1: Validate DNS (cảnh báo nhưng vẫn tiếp tục)
    ui_info "🔍 Bước 1/7: Kiểm tra DNS"
    if validate_domain_dns "$domain"; then
        ui_success "DNS đã được cấu hình đúng"
    else
        ui_warning "DNS chưa được cấu hình hoặc chưa trỏ về server này"
        ui_info "Tiếp tục cài đặt (có thể thất bại nếu DNS chưa đúng)"
        echo ""
        echo -n -e "${UI_YELLOW}Tiếp tục dù DNS chưa đúng? [Y/n]: ${UI_NC}"
        read -r continue_dns
        if [[ "$continue_dns" =~ ^[Nn]$ ]]; then
            ui_info "Đã hủy. Vui lòng cấu hình DNS trước."
            return 0
        fi
    fi

    # Step 2: Install dependencies
    ui_info "📦 Bước 2/7: Cài đặt dependencies"
    if ! install_certbot; then
        ui_error "Không thể cài đặt Certbot" "CERTBOT_INSTALL_FAILED"
        return 1
    fi

    # Step 3: Create HTTP config
    ui_info "🌐 Bước 3/7: Tạo nginx HTTP config"
    if ! create_nginx_http_config "$domain" "$n8n_port"; then
        ui_error "Không thể tạo nginx HTTP config" "NGINX_HTTP_FAILED"
        return 1
    fi

    # Step 4: Obtain SSL certificate
    ui_info "🔒 Bước 4/7: Lấy SSL certificate từ Let's Encrypt"
    if ! obtain_ssl_certificate "$domain" "$email"; then
        ui_error "Không thể lấy SSL certificate" "CERT_SETUP_FAILED"
        ui_info "💡 Kiểm tra:"
        ui_info "   • DNS đã trỏ về server này chưa?"
        ui_info "   • Port 80 đã mở chưa?"
        ui_info "   • Domain đã được sử dụng cho certificate khác chưa?"
        return 1
    fi

    # Step 5: Create HTTPS config
    ui_info "🔐 Bước 5/7: Tạo nginx HTTPS config"
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        if ! create_nginx_ssl_config "$domain" "$n8n_port"; then
            ui_error "Không thể tạo nginx HTTPS config" "NGINX_HTTPS_FAILED"
            return 1
        fi
        
        # Setup auto-renewal
        ui_info "🔄 Cấu hình tự động gia hạn SSL"
        if ! setup_auto_renewal; then
            ui_warning "Không thể cấu hình auto-renewal (có thể cấu hình thủ công sau)"
        fi
    else
        ui_error "SSL certificate không tồn tại sau khi cài đặt" "CERT_NOT_FOUND"
        return 1
    fi

    # Step 6: Update N8N configuration
    ui_info "⚙️  Bước 6/7: Cấu hình N8N cho HTTPS"
    if ! update_n8n_ssl_config "$domain" "$n8n_port"; then
        ui_warning "Không thể cập nhật cấu hình N8N (có thể cấu hình thủ công sau)"
    fi

    # Step 7: Final verification
    ui_info "✅ Bước 7/7: Xác minh cài đặt"
    if verify_ssl_setup "$domain" "$n8n_port"; then
        echo ""
        ui_info_box "🎉 SSL setup hoàn tất!" \
            "✅ Chứng chỉ SSL đã được cài đặt" \
            "✅ Nginx đã được cấu hình cho HTTPS" \
            "✅ N8N đã được cập nhật cho HTTPS" \
            "✅ Auto-renewal đã được cấu hình" \
            "" \
            "🌐 Truy cập N8N tại: https://$domain" \
            "" \
            "📝 Lưu ý:" \
            "   • Nếu domain chưa trỏ DNS, hãy đợi DNS propagate" \
            "   • SSL sẽ tự động gia hạn mỗi 90 ngày" \
            "   • Kiểm tra logs: /var/log/letsencrypt/"
        return 0
    else
        ui_warning "SSL đã được cấu hình nhưng có thể cần điều chỉnh"
        ui_info "💡 Kiểm tra:"
        ui_info "   • Domain đã trỏ DNS về server này?"
        ui_info "   • Firewall đã mở port 80 và 443?"
        ui_info "   • Nginx đang chạy: sudo systemctl status nginx"
        ui_info "   • N8N đang chạy: docker ps | grep n8n"
        return 1
    fi
}

# Export main function
export -f setup_ssl_main