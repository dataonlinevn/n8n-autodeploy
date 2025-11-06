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

    # Get domain
    echo -n -e "${UI_WHITE}Nhập domain cho N8N: ${UI_NC}"
    read -r domain

    if [[ -z "$domain" ]]; then
        ui_error "Domain không được để trống" "EMPTY_DOMAIN"
        return 1
    fi

    if ! ui_validate_domain "$domain"; then
        ui_error "Domain không hợp lệ: $domain" "INVALID_DOMAIN"
        return 1
    fi

    # Get email
    echo -n -e "${UI_WHITE}Nhập email cho Let's Encrypt: ${UI_NC}"
    read -r email

    if [[ -z "$email" ]]; then
        email="admin@$domain"
        ui_info "Sử dụng email mặc định: $email"
    fi

    if ! ui_validate_email "$email"; then
        ui_error "Email không hợp lệ: $email" "INVALID_EMAIL"
        return 1
    fi

    # Get N8N port
    local n8n_port=$(config_get "n8n.port" "5678")
    echo -n -e "${UI_WHITE}Port N8N (hiện tại: $n8n_port): ${UI_NC}"
    read -r port_input
    if [[ -n "$port_input" ]]; then
        n8n_port="$port_input"
    fi

    ui_info_box "Thông tin SSL setup" \
        "Domain: $domain" \
        "Email: $email" \
        "N8N Port: $n8n_port"

    echo -n -e "${UI_YELLOW}Tiếp tục cài đặt SSL? [Y/n]: ${UI_NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        return 0
    fi

    # Validate DNS
    if ! validate_domain_dns "$domain"; then
        ui_warning "DNS validation thất bại nhưng tiếp tục"
    fi

    # Install dependencies
    install_certbot || return 1

    # Create HTTP config first
    if ! create_nginx_http_config "$domain" "$n8n_port"; then
        return 1
    fi

    # Attempt to obtain SSL certificate
    if ! obtain_ssl_certificate "$domain" "$email"; then
        ui_error "SSL certificate setup thất bại" "CERT_SETUP_FAILED"
        return 1
    fi

    # Only create HTTPS config after certificate exists
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        # Create full HTTPS config
        create_nginx_ssl_config "$domain" "$n8n_port" || return 1
        
        # Setup auto-renewal
        setup_auto_renewal || return 1
    fi

    # Update N8N configuration
    update_n8n_ssl_config "$domain" || return 1

    # Final verification
    if verify_ssl_setup "$domain" "$n8n_port"; then
        ui_info_box "SSL setup hoàn tất!" \
            "✅ Chứng chỉ SSL đã được cài đặt" \
            "✅ N8N đã được cập nhật cho HTTPS" \
            "🌐 Truy cập: https://$domain"
    else
        ui_warning "SSL đã cấu hình nhưng có thể cần điều chỉnh"
    fi

    return 0
}

# Export main function
export -f setup_ssl_main