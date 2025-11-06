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
    
    # Find Google Drive remote (type = drive)
    local remote_name=$(rclone listremotes | grep -E "^.*:$" | while read -r line; do
        local name="${line%:}"
        local type=$(rclone config show "$name" | grep "type = " | cut -d' ' -f3)
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

