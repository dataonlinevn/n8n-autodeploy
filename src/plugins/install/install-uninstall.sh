#!/bin/bash

# DataOnline N8N Manager - Install Uninstall Module
# Phiên bản: 1.0.0

set -euo pipefail

handle_n8n_uninstall() {
    ui_header "Gỡ cài đặt N8N"

    # Check if N8N is installed
    if [[ ! -d "/opt/n8n" ]]; then
        ui_warning "N8N chưa được cài đặt"
        return 0
    fi

    # Show current installation info
    show_current_installation_info

    ui_warning_box "⚠️  CẢNH BÁO GỠ CÀI ĐẶT" \
        "Sẽ xóa hoàn toàn N8N và tất cả dữ liệu" \
        "Bao gồm: workflows, executions, credentials" \
        "Hành động này KHÔNG THỂ HOÀN TÁC!"

    # Double confirmation
    if ! ui_confirm "Bạn CHẮC CHẮN muốn gỡ cài đặt N8N?"; then
        return 0
    fi

    echo -n -e "${UI_RED}Nhập 'XAC NHAN' để tiếp tục: ${UI_NC}"
    read -r confirmation
    if [[ "$confirmation" != "XAC NHAN" ]]; then
        ui_info "Hủy gỡ cài đặt"
        return 0
    fi

    # Offer backup before uninstall
    if ui_confirm "Tạo backup trước khi gỡ cài đặt?"; then
        create_final_backup
    fi

    # Proceed with uninstallation
    uninstall_n8n_completely
}

show_current_installation_info() {
    ui_section "Thông tin cài đặt hiện tại"
    
    local n8n_version="unknown"
    local install_date="unknown"
    
    if docker ps --format '{{.Names}}' | grep -q "n8n"; then
        n8n_version=$(docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    fi
    
    install_date=$(config_get "n8n.installed_date" "unknown")
    
    local n8n_port=$(config_get "n8n.port" "5678")
    local n8n_domain=$(config_get "n8n.domain" "")
    
    echo "📊 **Thông tin N8N:**"
    echo "   Version: $n8n_version"
    echo "   Port: $n8n_port"
    echo "   Domain: ${n8n_domain:-'Chưa cấu hình'}"
    echo "   Ngày cài đặt: $install_date"
    echo ""
    
    # Check disk usage
    if [[ -d "/opt/n8n" ]]; then
        local disk_usage=$(du -sh /opt/n8n 2>/dev/null | cut -f1)
        echo "💾 **Disk Usage:**"
        echo "   N8N folder: $disk_usage"
        
        # Check volumes
        local volumes=$(docker volume ls --filter name=n8n --format "{{.Name}}" 2>/dev/null)
        if [[ -n "$volumes" ]]; then
            echo "   Docker volumes:"
            for volume in $volumes; do
                local vol_size=$(docker system df -v | grep "$volume" | awk '{print $3}' || echo "unknown")
                echo "     - $volume: $vol_size"
            done
        fi
    fi
    echo ""
}

create_final_backup() {
    ui_start_spinner "Tạo backup cuối cùng"
    
    local backup_dir="/tmp/n8n-final-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup docker-compose and config
    if [[ -d "/opt/n8n" ]]; then
        cp -r /opt/n8n "$backup_dir/"
    fi
    
    # Export database
    if docker ps --format '{{.Names}}' | grep -q "n8n-postgres"; then
        docker exec n8n-postgres pg_dump -U n8n n8n > "$backup_dir/database_final.sql" 2>/dev/null || true
    fi
    
    # Compress backup
    tar -czf "/tmp/n8n-final-backup-$(date +%Y%m%d_%H%M%S).tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    ui_stop_spinner
    ui_success "Backup cuối cùng đã được tạo tại /tmp/"
}

uninstall_n8n_completely() {
    ui_section "Thực hiện gỡ cài đặt"
    
    # Step 1: Stop services
    ui_start_spinner "Dừng N8N services"
    if [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        cd /opt/n8n && docker compose down -v 2>/dev/null || true
    fi
    
    # Stop containers manually if compose fails
    docker stop n8n n8n-postgres n8n-nocodb 2>/dev/null || true
    docker rm n8n n8n-postgres n8n-nocodb 2>/dev/null || true
    ui_stop_spinner
    ui_success "✅ Services đã dừng"
    
    # Step 2: Remove Docker volumes
    ui_start_spinner "Xóa Docker volumes"
    local volumes=(
        "n8n_postgres_data"
        "n8n_n8n_data" 
        "n8n_nocodb_data"
    )
    
    for volume in "${volumes[@]}"; do
        docker volume rm "$volume" 2>/dev/null || true
    done
    ui_stop_spinner
    ui_success "✅ Docker volumes đã xóa"
    
    # Step 3: Remove installation directory
    ui_run_command "Xóa thư mục cài đặt" "rm -rf /opt/n8n"
    
    # Step 4: Remove systemd service
    ui_start_spinner "Xóa systemd service"
    systemctl stop n8n 2>/dev/null || true
    systemctl disable n8n 2>/dev/null || true
    rm -f /etc/systemd/system/n8n.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    ui_stop_spinner
    ui_success "✅ Systemd service đã xóa"
    
    # Step 5: Remove Nginx configs (if any)
    ui_start_spinner "Xóa cấu hình Nginx"
    local n8n_domain=$(config_get "n8n.domain" "")
    if [[ -n "$n8n_domain" ]]; then
        rm -f "/etc/nginx/sites-available/${n8n_domain}.conf" 2>/dev/null || true
        rm -f "/etc/nginx/sites-enabled/${n8n_domain}.conf" 2>/dev/null || true
        
        # Also remove NocoDB domain if exists
        rm -f "/etc/nginx/sites-available/db.${n8n_domain}.conf" 2>/dev/null || true
        rm -f "/etc/nginx/sites-enabled/db.${n8n_domain}.conf" 2>/dev/null || true
        
        # Reload nginx if running
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx 2>/dev/null || true
        fi
    fi
    ui_stop_spinner
    ui_success "✅ Nginx configs đã xóa"
    
    # Step 6: Clean up manager config
    ui_start_spinner "Dọn dẹp cấu hình manager"
    config_set "n8n.installed" "false"
    config_set "n8n.domain" ""
    config_set "n8n.port" ""
    config_set "n8n.webhook_url" ""
    config_set "n8n.ssl_enabled" "false"
    config_set "nocodb.installed" "false"
    config_set "nocodb.domain" ""
    ui_stop_spinner
    ui_success "✅ Cấu hình manager đã dọn dẹp"
    
    # Step 7: Remove cron jobs (if any)
    ui_start_spinner "Xóa cron jobs"
    crontab -l 2>/dev/null | grep -v "n8n-backup" | crontab - 2>/dev/null || true
    ui_stop_spinner
    ui_success "✅ Cron jobs đã xóa"
    
    ui_success "🎉 N8N đã được gỡ cài đặt hoàn toàn!"
}

backup_existing_installation() {
    ui_start_spinner "Backup cài đặt hiện tại"
    
    local backup_dir="/opt/n8n/backups/installation_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup current docker-compose and env
    cp /opt/n8n/docker-compose.yml "$backup_dir/" 2>/dev/null || true
    cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || true
    
    ui_stop_spinner
    ui_success "Đã backup cài đặt hiện tại"
}

export -f handle_n8n_uninstall show_current_installation_info create_final_backup uninstall_n8n_completely backup_existing_installation
