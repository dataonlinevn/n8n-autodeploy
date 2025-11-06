#!/bin/bash

# DataOnline N8N Manager - Google Drive Backup Integration
# Phiên bản: 1.0.0
# Mô tả: Google Drive integration cho backup operations

set -euo pipefail

# ===== GOOGLE DRIVE SETUP =====

# Cấu hình Google Drive
setup_google_drive() {
    ui_section "Cấu hình Google Drive Backup"
    
    # Cài đặt rclone nếu chưa có
    if ! command_exists rclone; then
        ui_info "Cài đặt rclone..."
        curl https://rclone.org/install.sh | sudo bash
    fi
    
    # Kiểm tra cấu hình hiện tại
    local existing_remote=""
    if [[ -f "$RCLONE_CONFIG" ]]; then
        existing_remote=$(get_gdrive_remote_name || echo "")
    fi
    
    if [[ -n "$existing_remote" ]]; then
        ui_success "Google Drive đã được cấu hình (remote: $existing_remote)"
        if ! ui_confirm "Bạn muốn cấu hình lại?"; then
            # Save existing remote name
            save_gdrive_remote_name "$existing_remote"
            return 0
        fi
    fi
    
    ui_info "Bắt đầu cấu hình Google Drive với rclone..."
    ui_info "💡 Rclone sẽ hướng dẫn bạn từng bước để kết nối Google Drive"
    ui_info "💡 Bạn có thể đặt tên remote bất kỳ (VD: gdrive, n8n, backup, ...)"
    echo ""
    
    # Chạy rclone config
    rclone config
    
    # Auto-detect remote name after configuration
    ui_info "Đang tự động nhận diện remote Google Drive..."
    
    local remote_name
    if remote_name=$(get_gdrive_remote_name); then
        ui_success "Đã nhận diện remote: $remote_name"
        save_gdrive_remote_name "$remote_name"
    else
        ui_error "Không tìm thấy remote Google Drive" "RCLONE_CONFIG_ERROR" "Chạy lại rclone config"
        return 1
    fi
    
    # Test connection
    ui_info "Kiểm tra kết nối với remote '$remote_name'..."
    if rclone lsd "${remote_name}:" >/dev/null 2>&1; then
        ui_success "Kết nối Google Drive thành công!"
        
        # Tạo thư mục backup
        ui_info "Tạo thư mục n8n-backups..."
        if rclone mkdir "${remote_name}:n8n-backups" 2>/dev/null || rclone lsd "${remote_name}:n8n-backups" >/dev/null 2>&1; then
            ui_success "Thư mục n8n-backups đã sẵn sàng trên Google Drive"
        else
            ui_error "Không thể tạo thư mục backup" "GDRIVE_MKDIR_FAILED" "Kiểm tra permissions"
            return 1
        fi
    else
        ui_error "Không thể kết nối Google Drive với remote '$remote_name'" "GDRIVE_CONNECTION_FAILED" "Kiểm tra credentials"
        return 1
    fi
}

# Upload backup lên Google Drive 
upload_to_gdrive() {
    local backup_file="$1"
    
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        ui_error "Chưa cấu hình Google Drive" "GDRIVE_NOT_CONFIGURED" "Chạy setup_google_drive trước"
        return 1
    fi
    
    # Auto-detect remote name
    local remote_name
    if ! remote_name=$(get_gdrive_remote_name); then
        ui_error "Không tìm thấy Google Drive remote" "GDRIVE_REMOTE_NOT_FOUND" "Chạy setup_google_drive"
        return 1
    fi
    
    ui_info "Đang upload lên Google Drive (remote: $remote_name)..."
    
    if rclone copy "$backup_file" "${remote_name}:n8n-backups/" --progress; then
        ui_success "Upload thành công"
        return 0
    else
        ui_error "Upload thất bại" "GDRIVE_UPLOAD_FAILED" "Kiểm tra network và permissions"
        return 1
    fi
}

# Export functions
export -f setup_google_drive upload_to_gdrive

