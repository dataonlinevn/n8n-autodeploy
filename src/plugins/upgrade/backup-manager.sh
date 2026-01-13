#!/bin/bash

# DataOnline N8N Manager - Upgrade Backup Manager Module
# Phiên bản: 2.1.0
# Tích hợp với hệ thống backup chính

set -euo pipefail

# Global variable để lưu đường dẫn backup file cho rollback
UPGRADE_BACKUP_FILE=""

# ===== BACKUP CREATION =====

create_upgrade_backup() {
    ui_section "Sao luu du lieu"
    
    ui_info "Dang tao ban sao luu truoc khi nang cap..."
    
    # Gọi hàm create_backup() từ backup plugin chính
    local backup_file
    backup_file=$(create_backup)
    
    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        ui_error "Khong the tao ban sao luu"
        return 1
    fi
    
    # Lưu đường dẫn backup để dùng cho rollback
    UPGRADE_BACKUP_FILE="$backup_file"
    BACKUP_ID=$(basename "$backup_file" .tar.gz)
    
    # Lưu thông tin upgrade
    save_upgrade_metadata "$backup_file"
    
    ui_success "Da tao ban sao luu: $(basename "$backup_file")"
    
    # Hỏi upload lên Google Drive
    if [[ -f "${RCLONE_CONFIG:-}" ]]; then
        local remote_name=$(get_gdrive_remote_name 2>/dev/null || echo "")
        if [[ -n "$remote_name" ]]; then
            echo ""
            if ui_confirm "Tai ban sao luu len Google Drive?"; then
                upload_to_gdrive "$backup_file"
            fi
        fi
    fi
    
    return 0
}

save_upgrade_metadata() {
    local backup_file="$1"
    local metadata_file="${backup_file%.tar.gz}_upgrade_meta.json"
    
    cat > "$metadata_file" << EOF
{
    "backup_type": "pre_upgrade",
    "timestamp": "$(date -Iseconds)",
    "from_version": "${CURRENT_VERSION:-unknown}",
    "target_version": "${TARGET_VERSION:-unknown}",
    "backup_file": "$backup_file"
}
EOF
    
    chmod 600 "$metadata_file" 2>/dev/null || true
}

# ===== ROLLBACK =====

rollback_upgrade() {
    local backup_id="$1"
    
    ui_section "Khoi phuc du lieu"
    
    # Tìm file backup
    local backup_file=""
    local backup_base="${BACKUP_BASE_DIR:-/opt/n8n/backups}"
    
    if [[ -f "$backup_id" ]]; then
        backup_file="$backup_id"
    elif [[ -f "$backup_base/${backup_id}.tar.gz" ]]; then
        backup_file="$backup_base/${backup_id}.tar.gz"
    elif [[ -f "$backup_base/$backup_id" ]]; then
        backup_file="$backup_base/$backup_id"
    elif [[ -n "${UPGRADE_BACKUP_FILE:-}" && -f "$UPGRADE_BACKUP_FILE" ]]; then
        backup_file="$UPGRADE_BACKUP_FILE"
    fi
    
    if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
        ui_error "Khong tim thay ban sao luu: $backup_id"
        return 1
    fi
    
    echo ""
    echo "=========================================="
    echo "XAC NHAN KHOI PHUC"
    echo "=========================================="
    echo "  File: $(basename "$backup_file")"
    echo ""
    echo "  Luu y: Tat ca thay doi sau thoi diem"
    echo "  sao luu se bi mat."
    echo "=========================================="
    echo ""
    
    if ! ui_confirm "Ban chac chan muon khoi phuc?"; then
        ui_info "Da huy"
        return 1
    fi
    
    ui_info "Dang khoi phuc tu ban sao luu..."
    
    if restore_backup "$backup_file"; then
        ui_success "Khoi phuc thanh cong!"
        
        local restored_version=$(get_current_n8n_version)
        echo ""
        echo "Phien ban hien tai: v$restored_version"
        
        return 0
    else
        ui_error "Khoi phuc that bai"
        return 1
    fi
}

# ===== ROLLBACK MENU =====

show_rollback_menu() {
    ui_section "Chon ban sao luu de khoi phuc"
    
    local backup_base="${BACKUP_BASE_DIR:-/opt/n8n/backups}"
    local backups=($(ls -t "$backup_base"/n8n_backup_*.tar.gz 2>/dev/null | head -10))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        ui_warning "Khong co ban sao luu nao"
        return 1
    fi
    
    echo ""
    echo "Danh sach ban sao luu:"
    echo ""
    
    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local backup_name=$(basename "$backup" .tar.gz)
        local backup_info=$(get_backup_info "$backup_name")
        echo "  $((i + 1))) $backup_name - $backup_info"
    done
    echo ""
    echo "  0) Quay lai"
    echo ""
    
    echo -n "Lua chon cua ban: "
    read -r choice
    
    if [[ "$choice" == "0" ]]; then
        return 1
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice - 1))]}"
        rollback_upgrade "$selected_backup"
        return $?
    else
        echo "Lua chon khong hop le"
        return 1
    fi
}

# ===== HELPER FUNCTIONS =====

get_backup_info() {
    local backup_id="$1"
    local backup_base="${BACKUP_BASE_DIR:-/opt/n8n/backups}"
    local backup_file="$backup_base/${backup_id}.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        backup_file="$backup_base/$backup_id"
    fi
    
    if [[ -f "$backup_file" ]]; then
        local size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        local date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1)
        
        # Kiểm tra có upgrade metadata không
        local meta_file="${backup_file%.tar.gz}_upgrade_meta.json"
        local upgrade_info=""
        if [[ -f "$meta_file" ]] && command -v jq >/dev/null 2>&1; then
            local from_ver=$(jq -r '.from_version' "$meta_file" 2>/dev/null || echo "")
            if [[ -n "$from_ver" && "$from_ver" != "null" ]]; then
                upgrade_info=" [truoc nang cap v$from_ver]"
            fi
        fi
        
        echo "$date ($size)$upgrade_info"
    else
        echo "Khong tim thay"
    fi
}

verify_n8n_health() {
    local n8n_port=$(config_get "n8n.port" "5678")
    local max_wait=60
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$n8n_port/healthz" >/dev/null 2>&1; then
            if docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
                return 0
            fi
        fi
        sleep 2
        ((waited += 2))
    done
    
    return 1
}

cleanup_old_backups() {
    local retention_days="${1:-30}"
    
    ui_info "Dang don dep ban sao luu cu..."
    
    local backup_base="${BACKUP_BASE_DIR:-/opt/n8n/backups}"
    
    # Xóa upgrade metadata files cũ
    find "$backup_base" -maxdepth 1 -name "*_upgrade_meta.json" -mtime +$retention_days -delete 2>/dev/null || true
    
    ui_success "Don dep hoan tat"
}

# Export functions
export -f create_upgrade_backup rollback_upgrade show_rollback_menu cleanup_old_backups get_backup_info verify_n8n_health
