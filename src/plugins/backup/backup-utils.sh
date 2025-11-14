#!/bin/bash

# DataOnline N8N Manager - Backup Utilities
# Phiên bản: 1.0.0
# Mô tả: Helper functions cho backup operations

set -euo pipefail

# ===== HELPER FUNCTIONS FOR REMOTE DETECTION =====

# Get Google Drive remote name
get_gdrive_remote_name() {
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        return 1
    fi
    
    # Ưu tiên 1: Sử dụng remote đã được lưu trong config
    local saved_remote=$(get_saved_gdrive_remote_name)
    if [[ -n "$saved_remote" ]]; then
        # Kiểm tra remote này có tồn tại và có type drive không
        if rclone config show "$saved_remote" >/dev/null 2>&1; then
            local type=$(rclone config show "$saved_remote" 2>/dev/null | grep "type = " | cut -d' ' -f3)
            if [[ "$type" == "drive" ]]; then
                echo "$saved_remote"
                return 0
            fi
        fi
    fi
    
    # Ưu tiên 2: Tìm remote có token (đã được authorize)
    local remote_with_token=""
    for name in $(rclone listremotes 2>/dev/null | sed 's/:$//'); do
        local type=$(rclone config show "$name" 2>/dev/null | grep "type = " | cut -d' ' -f3)
        if [[ "$type" == "drive" ]]; then
            # Kiểm tra có token không
            if rclone config show "$name" 2>/dev/null | grep -qE "(token|access_token|refresh_token)"; then
                remote_with_token="$name"
                break
            fi
        fi
    done
    
    if [[ -n "$remote_with_token" ]]; then
        echo "$remote_with_token"
        return 0
    fi
    
    # Ưu tiên 3: Tìm remote đầu tiên có type drive (fallback)
    local remote_name=$(rclone listremotes 2>/dev/null | sed 's/:$//' | while read -r name; do
        local type=$(rclone config show "$name" 2>/dev/null | grep "type = " | cut -d' ' -f3)
        if [[ "$type" == "drive" ]]; then
            echo "$name"
            break
        fi
    done)
    
    if [[ -n "$remote_name" ]]; then
        echo "$remote_name"
        return 0
    else
        return 1
    fi
}

# Save remote name to config
save_gdrive_remote_name() {
    local remote_name="$1"
    config_set "backup.gdrive_remote" "$remote_name"
}

# Get saved remote name from config
get_saved_gdrive_remote_name() {
    config_get "backup.gdrive_remote" ""
}

# Export functions
export -f get_gdrive_remote_name save_gdrive_remote_name get_saved_gdrive_remote_name

