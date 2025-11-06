#!/bin/bash

# DataOnline N8N Manager - SSL Verify Module
# Phiên bản: 1.0.0

set -euo pipefail

verify_ssl_setup() {
    local domain="$1"
    local n8n_port="${2:-5678}"

    ui_section "Xác minh cài đặt SSL"

    # Check N8N running
    if command_exists docker && docker ps | grep -q "n8n"; then
        ui_success "N8N đang chạy trong Docker"
    elif systemctl is-active --quiet n8n; then
        ui_success "N8N service đang chạy"
    else
        ui_warning "N8N có thể không chạy"
        if [[ -f "/opt/n8n/docker-compose.yml" ]]; then
            ui_run_command "Khởi động N8N" "cd /opt/n8n && docker compose up -d"
        fi
    fi

    # Check HTTPS connection
    ui_start_spinner "Kiểm tra kết nối HTTPS"
    if curl -s -k "https://$domain" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_success "HTTPS hoạt động: https://$domain"
        return 0
    else
        ui_stop_spinner
        ui_error "HTTPS không hoạt động" "HTTPS_FAILED" "Kiểm tra nginx và cert files"
        return 1
    fi
}

update_n8n_ssl_config() {
    local domain="$1"
    local compose_dir="/opt/n8n"

    if [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
        ui_error "Không tìm thấy N8N Docker installation" "N8N_COMPOSE_NOT_FOUND"
        return 1
    fi

    ui_run_command "Cập nhật cấu hình N8N cho SSL" "
        cd $compose_dir
        
        # Update .env file
        sed -i 's|^N8N_DOMAIN=.*|N8N_DOMAIN=$domain|' .env
        sed -i 's|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=https://$domain|' .env
        
        # Update docker-compose environment
        sed -i 's|N8N_PROTOCOL=http|N8N_PROTOCOL=https|' docker-compose.yml
        sed -i 's|WEBHOOK_URL=http://.*|WEBHOOK_URL=https://$domain/|' docker-compose.yml
        sed -i 's|N8N_HOST=0.0.0.0|N8N_HOST=$domain|' docker-compose.yml
        
        # Restart N8N
        docker compose restart n8n
    "

    # Save to config
    config_set "n8n.domain" "$domain"
    config_set "n8n.ssl_enabled" "true"
    config_set "n8n.webhook_url" "https://$domain"
}

export -f verify_ssl_setup update_n8n_ssl_config
