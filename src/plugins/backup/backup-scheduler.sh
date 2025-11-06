#!/bin/bash

# DataOnline N8N Manager - Backup Scheduler
# Phiên bản: 1.0.0
# Mô tả: Cron job management cho automated backups

set -euo pipefail

# ===== CRON JOB MANAGEMENT =====

# Cài đặt cron job 
setup_cron_job() {
    local frequency="$1" # daily, weekly, monthly
    local hour="${2:-2}" # Default 2 AM
    
    ui_section "Cài đặt Backup Tự động"
    
    # Tạo script wrapper
    local cron_script="/usr/local/bin/n8n-backup-cron.sh"
    
    # Create script content
    cat > /tmp/n8n-backup-cron.sh << EOF
#!/bin/bash
# N8N Backup Cron Script
export PATH="/usr/local/bin:/usr/bin:/bin"

# Đường dẫn tới thư mục backup và plugin
BACKUP_DIR="/opt/n8n/backups"
PLUGIN_DIR="$PLUGIN_DIR"
PROJECT_ROOT="$PLUGIN_PROJECT_ROOT"

# Source backup plugin trực tiếp
source "\$PROJECT_ROOT/src/core/logger.sh"
source "\$PROJECT_ROOT/src/core/config.sh"
source "\$PROJECT_ROOT/src/core/utils.sh"
source "\$PLUGIN_DIR/main.sh"

# Tạo backup
log_info "Starting automated backup..."
backup_file=\$(create_backup)

# Upload to Google Drive if configured
if [[ -f "\$HOME/.config/rclone/rclone.conf" ]] && [[ -n "\$backup_file" ]]; then
    upload_to_gdrive "\$backup_file"
fi

# Cleanup old backups
cleanup_old_backups
EOF
    
    # Install script with proper permissions
    if sudo cp /tmp/n8n-backup-cron.sh "$cron_script" 2>/dev/null && sudo chmod +x "$cron_script" 2>/dev/null; then
        rm -f /tmp/n8n-backup-cron.sh
        ui_success "Cron script đã được tạo"
    else
        ui_error "Không thể tạo cron script" "CRON_SCRIPT_CREATE_FAILED" "Kiểm tra permissions"
        return 1
    fi
    
    # Set cron schedule
    local cron_schedule
    case "$frequency" in
    "daily") cron_schedule="0 $hour * * *" ;;
    "weekly") cron_schedule="0 $hour * * 0" ;;
    "monthly") cron_schedule="0 $hour 1 * *" ;;
    *) cron_schedule="0 2 1 * *" ;; # Default monthly
    esac
    
    # Add to crontab
    (
        crontab -l 2>/dev/null | grep -v "$CRON_JOB_NAME"
        echo "$cron_schedule $cron_script # $CRON_JOB_NAME"
    ) | crontab -
    
    ui_success "Đã cài đặt backup $frequency lúc $hour:00"
    return 0
}

# Remove cron job
remove_cron_job() {
    ui_section "Gỡ Cron Job Backup"
    
    if ui_confirm "Gỡ cron job backup tự động?"; then
        (
            crontab -l 2>/dev/null | grep -v "$CRON_JOB_NAME"
        ) | crontab -
        
        # Remove cron script
        if [[ -f "/usr/local/bin/n8n-backup-cron.sh" ]]; then
            sudo rm -f "/usr/local/bin/n8n-backup-cron.sh"
        fi
        
        ui_success "Đã gỡ cron job backup"
        return 0
    fi
    
    return 1
}

# Check cron job status
check_cron_job_status() {
    if crontab -l 2>/dev/null | grep -q "$CRON_JOB_NAME"; then
        local cron_line=$(crontab -l 2>/dev/null | grep "$CRON_JOB_NAME")
        ui_info "Cron job đang hoạt động:"
        echo "   $cron_line"
        return 0
    else
        ui_warning "Chưa có cron job backup được cài đặt"
        return 1
    fi
}

# Export functions
export -f setup_cron_job remove_cron_job check_cron_job_status

