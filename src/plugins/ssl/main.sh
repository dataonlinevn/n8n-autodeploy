[[ -n "${SSL_MAIN_LOADED:-}" ]] && return 0
readonly SSL_MAIN_LOADED=true

set -euo pipefail

# Source core modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$PLUGIN_DIR")")")"

[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
[[ -z "${SPINNER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"

# Constants
[[ -z "${SSL_LOADED:-}" ]] && readonly SSL_LOADED=true
[[ -z "${WEBROOT_PATH:-}" ]] && readonly WEBROOT_PATH="/var/www/html"
[[ -z "${CERTBOT_LOG:-}" ]] && readonly CERTBOT_LOG="/var/log/letsencrypt"

# Load sub-modules (override local definitions)
source "$PLUGIN_DIR/ssl-domain.sh"
source "$PLUGIN_DIR/ssl-nginx.sh"
source "$PLUGIN_DIR/ssl-certbot.sh"
source "$PLUGIN_DIR/ssl-verify.sh"

# ===== MAIN SSL SETUP FUNCTION =====

setup_ssl_main() {
    ui_header "Cài đặt Bảo mật SSL (HTTPS)"
    
    echo -e "${UI_CYAN}Hệ thống sẽ tự động cấu hình chứng chỉ bảo mật cho tên miền của bạn.${UI_NC}"
    echo -e "${UI_GRAY}   • Tự động thiết lập máy chủ Nginx${UI_NC}"
    echo -e "${UI_GRAY}   • Đăng ký chứng chỉ Let's Encrypt (Miễn phí)${UI_NC}"
    echo -e "${UI_GRAY}   • Tự động chuyển hướng HTTPS và bảo mật ứng dụng${UI_NC}"
    echo ""

    domain=$(ui_prompt "Nhập tên miền (ví dụ: n8n.congty.com)" "")

    if [[ -z "$domain" ]]; then
        ui_error "Lỗi: Tên miền không được để trống"
        return 1
    fi

    if ! ui_validate_domain "$domain"; then
        ui_error "Tên miền không hợp lệ: $domain"
        echo ""
        echo -e "${UI_YELLOW} Ví dụ tên miền đúng:${UI_NC}"
        echo -e "   - n8n.yourdomain.com"
        echo -e "   - automation.site.com"
        return 1
    fi

    email=$(ui_prompt "Email nhận thông báo bảo mật" "admin@$domain")

    if [[ -z "$email" ]]; then
        email="admin@$domain"
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
    ui_info_box "THÔNG TIN CÀI ĐẶT" \
        "Tên miền: $domain" \
        "Email:    $email" \
        "Ứng dụng: n8n (Port $n8n_port)" \
        "" \
        "Quy trình thực hiện:" \
        "  1. Kiểm tra kết nối DNS" \
        "  2. Cài đặt các công cụ bảo mật" \
        "  3. Đăng ký chứng chỉ Let's Encrypt" \
        "  4. Kích hoạt chuyển hướng HTTPS" \
        "  5. Thiết lập tự động gia hạn (90 ngày)"

    echo ""
    echo -n -e "${UI_YELLOW}Tiếp tục cài đặt SSL? [Y/n]: ${UI_NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        ui_info "Đã hủy cài đặt SSL"
        return 0
    fi

    echo ""
    ui_section "Bắt đầu cài đặt SSL tự động"

    # Step 1: Validate DNS 
    ui_info "Bước 1/4: Kiểm tra DNS"
    if ! validate_domain_dns "$domain"; then
        ui_warning "DNS chưa được cấu hình hoặc chưa trỏ về server này"
        if ! ui_confirm "Tiếp tục dù DNS chưa đúng?"; then
            return 0
        fi
    fi

    # Step 2: Obtain SSL certificate
    ui_info "Bước 2/4: Cài đặt & Lấy chứng chỉ SSL"
    install_certbot || return 1
    create_nginx_http_config "$domain" "$n8n_port" || return 1
    obtain_ssl_certificate "$domain" "$email" || return 1

    # Step 3: Configure HTTPS
    ui_info "Bước 3/4: Cấu hình Nginx & HTTPS"
    create_nginx_ssl_config "$domain" "$n8n_port" || return 1
    setup_auto_renewal || return 1

    # Step 4: Finalize N8N
    ui_info "Bước 4/4: Cập nhật N8N & Xác minh"
    update_n8n_ssl_config "$domain" "$n8n_port" || return 1
    
    if verify_ssl_setup "$domain" "$n8n_port"; then
        echo ""
        ui_info_box "KÍCH HOẠT BẢO MẬT THÀNH CÔNG" \
            "Tên miền: $domain" \
            "Trạng thái: Đã bảo mật (HTTPS)" \
            "Gia hạn: Tự động hàng tháng" \
            "" \
            "Bạn có thể truy cập ngay tại:" \
            "https://$domain" \
            "" \
            "Lưu ý: Nếu không truy cập được, hãy đảm bảo" \
            "tên miền đã được trỏ về địa chỉ IP của máy chủ."
        return 0
    else
        ui_warning "Cơ bản đã hoàn tất nhưng có thể DNS chưa cập nhật"
        ui_info " Vui lòng kiểm tra:"
        ui_info "   - Tên miền đã trỏ về IP máy chủ chưa?"
        ui_info "   - Port 80/443 đã được mở trên Firewall chưa?"
        return 1
    fi
}

# Export main function
export -f setup_ssl_main