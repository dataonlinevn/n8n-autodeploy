#!/bin/bash

# DataOnline N8N Manager - Simplified Workflow Manager
# Phiên bản: 1.0.0
# Quản lý workflows N8N với giao diện đơn giản và hiệu quả

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
readonly WORKFLOW_MANAGER_LOADED=true
readonly N8N_API_BASE="http://localhost:5678/api/v1"
readonly N8N_API_KEY_FILE="/opt/n8n/.n8n-api-key"
readonly GDRIVE_FOLDER="n8n-workflows"

# Global variables
N8N_API_KEY=""

# ===== MAIN MENU =====

workflow_manager_main() {
    ui_header "Quản lý Workflows N8N"

    if ! setup_prerequisites; then
        return 1
    fi

    while true; do
        show_simple_menu
        
        echo -n -e "${UI_WHITE}Chọn [0-3]: ${UI_NC}"
        read -r choice

        case "$choice" in
        1) list_workflows ;;
        2) export_menu ;;
        3) import_menu ;;
        0) return 0 ;;
        *) ui_status "error" "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

show_simple_menu() {
    local workflow_count=$(get_workflow_count)
    
    echo ""
    echo "📊 **Workflows hiện tại:** $workflow_count"
    echo ""
    echo "🔄 QUẢN LÝ WORKFLOWS"
    echo ""
    echo "1) 📋 Danh sách workflows"
    echo "2) 📤 Export workflows"
    echo "3) 📥 Import workflows"
    echo "0) ⬅️  Quay lại"
    echo ""
}

# ===== SETUP =====

setup_prerequisites() {
    # Setup API key
    if [[ -f "$N8N_API_KEY_FILE" ]]; then
        N8N_API_KEY=$(cat "$N8N_API_KEY_FILE")
    else
        if ! get_api_key_from_database; then
            ui_status "error" "Cần setup N8N API key"
            ui_info "Truy cập N8N → Settings → API Keys → Create key"
            echo -n -e "${UI_WHITE}Nhập API key: ${UI_NC}"
            read -r api_key
            if [[ -n "$api_key" ]]; then
                echo "$api_key" > "$N8N_API_KEY_FILE"
                chmod 600 "$N8N_API_KEY_FILE"
                N8N_API_KEY="$api_key"
            else
                return 1
            fi
        fi
    fi

    # Test API
    if ! make_api_call "GET" "workflows" >/dev/null; then
        ui_status "error" "N8N API không hoạt động"
        return 1
    fi

    # Check Google Drive
    if ! check_gdrive; then
        ui_status "warning" "Google Drive chưa setup"
    fi

    return 0
}

get_api_key_from_database() {
    local api_key=$(docker exec n8n-postgres psql -U n8n -t -c "
        SELECT token FROM api_key 
        WHERE type = 'api' 
        ORDER BY created_at DESC 
        LIMIT 1;
    " 2>/dev/null | xargs)
    
    if [[ -n "$api_key" && "$api_key" != "null" ]]; then
        N8N_API_KEY="$api_key"
        echo "$api_key" > "$N8N_API_KEY_FILE"
        chmod 600 "$N8N_API_KEY_FILE"
        return 0
    fi
    return 1
}

make_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local curl_args=(-s -H "X-N8N-API-KEY: $N8N_API_KEY")
    
    if [[ "$method" == "POST" ]]; then
        curl_args+=(-X POST -H "Content-Type: application/json")
        [[ -n "$data" ]] && curl_args+=(-d "$data")
    elif [[ "$method" == "PUT" ]]; then
        curl_args+=(-X PUT -H "Content-Type: application/json")
        [[ -n "$data" ]] && curl_args+=(-d "$data")
    fi
    
    curl "${curl_args[@]}" "$N8N_API_BASE/$endpoint"
}

get_workflow_count() {
    make_api_call "GET" "workflows" | jq '.data | length' 2>/dev/null || echo "0"
}

check_gdrive() {
    command -v rclone >/dev/null 2>&1 && [[ -f "$HOME/.config/rclone/rclone.conf" ]]
}

get_gdrive_remote_name() {
    if [[ ! -f "$HOME/.config/rclone/rclone.conf" ]]; then
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

get_gdrive_remote() {
    get_gdrive_remote_name
}

# ===== LIST WORKFLOWS =====

list_workflows() {
    ui_section "Danh sách Workflows"
    
    ui_start_spinner "Lấy danh sách workflows"
    local workflows=$(make_api_call "GET" "workflows")
    ui_stop_spinner
    
    if ! echo "$workflows" | jq -e '.data' >/dev/null 2>&1; then
        ui_status "error" "Không thể lấy danh sách workflows"
        return 1
    fi
    
    echo "📋 **N8N Workflows:**"
    echo ""
    printf "%-20s %-30s %-15s %-15s\n" "ID" "Name" "Status" "Updated"
    echo "────────────────────────────────────────────────────────────────────────────"
    
    echo "$workflows" | jq -r '.data[] | @json' | while read -r workflow_json; do
        local id=$(echo "$workflow_json" | jq -r '.id')
        local name=$(echo "$workflow_json" | jq -r '.name')
        local active=$(echo "$workflow_json" | jq -r '.active')
        local updated=$(echo "$workflow_json" | jq -r '.updatedAt')
        
        local status=$([ "$active" = "true" ] && echo "🟢 Active" || echo "🔴 Inactive")
        local date=$(echo "$updated" | cut -d'T' -f1)
        
        printf "%-20s %-30s %-15s %-15s\n" "${id:0:18}" "${name:0:28}" "$status" "$date"
    done
    
    echo ""
    echo "📊 Total: $(echo "$workflows" | jq '.data | length') workflows"
}

# ===== EXPORT =====

export_menu() {
    ui_section "Export Workflows"
    
    if ! check_gdrive; then
        ui_status "error" "Google Drive chưa được cấu hình"
        return 1
    fi
    
    echo "📤 **Export Options:**"
    echo ""
    echo "1) Export tất cả workflows"
    echo "2) Chọn workflows để export"
    echo "0) Quay lại"
    echo ""
    
    read -p "Chọn [0-2]: " export_choice
    
    case "$export_choice" in
    1) export_all_workflows ;;
    2) export_selected_workflows ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

export_all_workflows() {
    set +e  # Disable exit on error temporarily
    
    local workflows=$(make_api_call "GET" "workflows")
    
    if ! echo "$workflows" | jq -e '.data' >/dev/null 2>&1; then
        ui_status "error" "Không thể lấy workflows"
        set -e
        return 1
    fi
    
    local temp_dir="/tmp/n8n_export_$(date +%s)"
    mkdir -p "$temp_dir"
    
    # Export workflows
    local count=0
    local workflow_ids=($(echo "$workflows" | jq -r '.data[].id'))
    
    echo "🔄 Exporting ${#workflow_ids[@]} workflows..."
    for id in "${workflow_ids[@]}"; do
        local workflow_data=$(echo "$workflows" | jq -r ".data[] | select(.id==\"$id\")")
        local name=$(echo "$workflow_data" | jq -r '.name' | sed 's/[^a-zA-Z0-9_-]/_/g')
        
        echo "$workflow_data" > "$temp_dir/${name}_${id}.json"
        echo "✅ Exported: $name"
        count=$((count + 1))
    done
    
    echo ""
    echo "📊 Total exported: $count workflows"
    echo "📁 Temp directory: $temp_dir"

    # Auto-detect remote name
    echo "☁️  Starting Google Drive upload..."
    
    local remote_name
    if ! remote_name=$(get_gdrive_remote_name); then
        echo "❌ Không tìm thấy Google Drive remote"
        set -e
        return 1
    fi
    
    echo "✅ Detected remote: $remote_name"
    
    # Test connection
    if rclone lsd "$remote_name:" >/dev/null 2>&1; then
        echo "✅ Google Drive connection OK"
    else
        echo "❌ Google Drive connection failed"
        set -e
        return 1
    fi
    
    # Create folder and upload
    rclone mkdir "$remote_name:n8n-workflows" 2>/dev/null || true
    
    echo "📤 Uploading to Google Drive..."
    if rclone copy "$temp_dir/" "$remote_name:n8n-workflows/" --include "*.json" --progress; then
        echo "✅ Upload successful!"
        
        # Verify
        local uploaded=$(rclone ls "$remote_name:n8n-workflows/" --include "*.json" | wc -l)
        echo "📊 Files on Drive: $uploaded"
    else
        echo "❌ Upload failed"
    fi
    
    rm -rf "$temp_dir"
    set -e  # Re-enable strict mode
    return 0
}

export_selected_workflows() {
    set +e  # Disable strict mode
    
    local workflows=$(make_api_call "GET" "workflows")
    
    echo ""
    echo "📋 **Chọn workflows để export:**"
    echo ""
    
    local index=1
    echo "$workflows" | jq -c '.data[]' | while read -r workflow; do
        local id=$(echo "$workflow" | jq -r '.id')
        local name=$(echo "$workflow" | jq -r '.name')
        local active=$(echo "$workflow" | jq -r '.active')
        local status=$([ "$active" = "true" ] && echo "🟢" || echo "🔴")
        
        echo "$index) $status $name (ID: $id)"
        index=$((index + 1))
    done
    
    echo ""
    echo -n -e "${UI_WHITE}Nhập số thứ tự (cách nhau bởi dấu phẩy): ${UI_NC}"
    read -r selections
    
    local temp_dir="/tmp/n8n_export_selected_$(date +%s)"
    mkdir -p "$temp_dir"
    
    local count=0
    IFS=',' read -ra INDICES <<< "$selections"
    for idx in "${INDICES[@]}"; do
        idx=$(echo "$idx" | xargs)
        if [[ "$idx" =~ ^[0-9]+$ ]]; then
            local workflow=$(echo "$workflows" | jq -c ".data[$((idx-1))]")
            if [[ "$workflow" != "null" ]]; then
                local id=$(echo "$workflow" | jq -r '.id')
                local name=$(echo "$workflow" | jq -r '.name' | sed 's/[^a-zA-Z0-9_-]/_/g')
                
                local full_workflow=$(make_api_call "GET" "workflows/$id")
                echo "$full_workflow" > "$temp_dir/${name}_${id}.json"
                echo "Exported: $name"
                count=$((count + 1))
            fi
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        echo "☁️  Uploading $count workflows..."

        # Auto-detect remote name
        local remote_name
        if ! remote_name=$(get_gdrive_remote_name); then
            echo "❌ Không tìm thấy Google Drive remote"
            set -e
            return 1
        fi
        
        echo "✅ Detected remote: $remote_name"
        rclone mkdir "$remote_name:n8n-workflows" 2>/dev/null || true
        
        if rclone copy "$temp_dir/" "$remote_name:n8n-workflows/" --include "*.json" --progress; then
            echo "✅ Upload successful!"
        else
            echo "❌ Upload failed"
        fi
    else
        echo "⚠️  No workflows exported"
    fi
    
    rm -rf "$temp_dir"
    set -e  # Re-enable strict mode
}

upload_to_gdrive() {
    local temp_dir="$1"
    local count="$2"
    
    local remote_name=$(get_gdrive_remote)
    if [[ -z "$remote_name" ]]; then
        ui_status "error" "Google Drive remote không tìm thấy"
        return 1
    fi
    
    ui_start_spinner "Upload $count workflows to Google Drive"
    
    # Create folder if not exists
    rclone mkdir "${remote_name}:${GDRIVE_FOLDER}" 2>/dev/null || true
    
    if rclone copy "$temp_dir/" "${remote_name}:${GDRIVE_FOLDER}/" --include "*.json"; then
        ui_stop_spinner
        ui_status "success" "✅ Đã upload $count workflows lên Google Drive"
    else
        ui_stop_spinner
        ui_status "error" "❌ Upload thất bại"
        return 1
    fi
}

# ===== IMPORT =====

import_menu() {
    ui_section "Import Workflows từ Google Drive"
    
    if ! check_gdrive; then
        ui_status "error" "Google Drive chưa được cấu hình"
        return 1
    fi

    # Auto-detect remote name
    local remote_name
    if ! remote_name=$(get_gdrive_remote_name); then
        ui_status "error" "Không tìm thấy Google Drive remote"
        return 1
    fi
    
    ui_start_spinner "Lấy danh sách files từ Google Drive"
    local files=$(rclone ls "${remote_name}:n8n-workflows/" --include "*.json" 2>/dev/null)
    ui_stop_spinner
    
    if [[ -z "$files" ]]; then
        ui_status "warning" "Không có workflow files trên Google Drive"
        return 1
    fi
    
    echo "📁 **Files trên Google Drive:**"
    echo ""
    
    local -a file_list=()
    local index=1
    
    echo "$files" | while read -r size filename; do
        echo "$index) $filename ($(( size / 1024 ))KB)"
        file_list+=("$filename")
        ((index++))
    done
    
    echo ""
    echo -n -e "${UI_WHITE}Chọn file để import (số thứ tự hoặc 'all'): ${UI_NC}"
    read -r selection
    
    local temp_dir="/tmp/n8n_import_$(date +%s)"
    mkdir -p "$temp_dir"
    
    if [[ "$selection" == "all" ]]; then
        # Download all files
        ui_start_spinner "Download tất cả files"
        rclone copy "${remote_name}:n8n-workflows/" "$temp_dir/" --include "*.json"
        ui_stop_spinner
        
        import_workflow_files "$temp_dir"
    else
        # Download specific file
        local file_index=$((selection))
        local selected_file=$(echo "$files" | sed -n "${file_index}p" | awk '{print $2}')
        
        if [[ -n "$selected_file" ]]; then
            ui_start_spinner "Download $selected_file"
            rclone copy "${remote_name}:n8n-workflows/$selected_file" "$temp_dir/"
            ui_stop_spinner
            
            import_workflow_files "$temp_dir"
        else
            ui_status "error" "File không hợp lệ"
        fi
    fi
    
    rm -rf "$temp_dir"
}

import_workflow_files() {
    set +e  # Disable strict mode
    
    local import_dir="$1"
    local json_files=($(find "$import_dir" -name "*.json" -type f))
    
    if [[ ${#json_files[@]} -eq 0 ]]; then
        echo "⚠️  No JSON files found"
        set -e
        return 1
    fi
    
    local imported=0
    local failed=0
    
    for file in "${json_files[@]}"; do
        local filename=$(basename "$file")
        echo "🔄 Processing: $filename"
        
        # Validate JSON
        if ! jq empty "$file" 2>/dev/null; then
            echo "❌ Invalid JSON: $filename"
            failed=$((failed + 1))
            continue
        fi
        
        # Extract only required fields for N8N API
        local workflow_data=""
        
        # Method 1: Direct workflow object
        if jq -e '.name' "$file" >/dev/null 2>&1; then
            # Extract required fields for N8N API
            workflow_data=$(jq '{
                name: .name,
                nodes: .nodes,
                connections: .connections,
                settings: (.settings // {})
            }' "$file" 2>/dev/null)
            echo "✅ Using direct workflow format (core fields only)"
            
        # Method 2: Nested data format
        elif jq -e '.data.name' "$file" >/dev/null 2>&1; then
            workflow_data=$(jq '.data | {
                name: .name,
                nodes: .nodes,
                connections: .connections,
                settings: (.settings // {})
            }' "$file" 2>/dev/null)
            echo "✅ Using nested data format"
            
        else
            echo "❌ Unknown workflow format: $filename"
            failed=$((failed + 1))
            continue
        fi
        
        if [[ -z "$workflow_data" || "$workflow_data" == "null" ]]; then
            echo "❌ No valid workflow data: $filename"
            failed=$((failed + 1))
            continue
        fi
        
        # Validate required fields
        local workflow_name=$(echo "$workflow_data" | jq -r '.name // ""')
        local has_nodes=$(echo "$workflow_data" | jq -e '.nodes | length > 0' 2>/dev/null)
        
        if [[ -z "$workflow_name" ]]; then
            echo "❌ Missing workflow name: $filename"
            failed=$((failed + 1))
            continue
        fi
        
        if ! $has_nodes; then
            echo "❌ No nodes found: $filename"
            failed=$((failed + 1))
            continue
        fi
        
        # Check if workflow with same name exists
        echo "🔍 Checking for existing workflow: $workflow_name"
        local existing_workflows=$(make_api_call "GET" "workflows")
        local existing_id=$(echo "$existing_workflows" | jq -r ".data[] | select(.name==\"$workflow_name\") | .id" 2>/dev/null)
        
        if [[ -n "$existing_id" ]]; then
            echo "⚠️  Workflow '$workflow_name' already exists (ID: $existing_id)"
            echo -n "   Overwrite? [y/N]: "
            read -r overwrite
            
            if [[ "$overwrite" =~ ^[Yy]$ ]]; then
                # Update existing workflow
                echo "📤 Updating existing workflow..."
                local response=$(make_api_call "PUT" "workflows/$existing_id" "$workflow_data")
                
                if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
                    echo "✅ Updated: $workflow_name (ID: $existing_id)"
                    imported=$((imported + 1))
                else
                    echo "❌ Update failed: $(echo "$response" | jq -r '.message // "Unknown error"')"
                    failed=$((failed + 1))
                fi
            else
                echo "⏭️  Skipped: $workflow_name"
                continue
            fi
        else
            # Create new workflow
            echo "📤 Creating new workflow..."
            local response=$(make_api_call "POST" "workflows" "$workflow_data")
            
            if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
                local new_id=$(echo "$response" | jq -r '.id')
                echo "✅ Created: $workflow_name (ID: $new_id)"
                imported=$((imported + 1))
            else
                echo "❌ Creation failed: $(echo "$response" | jq -r '.message // "Unknown error"')"
                echo "🔍 Response: $response"
                failed=$((failed + 1))
            fi
        fi
    done
    
    echo ""
    echo "📊 Import completed: $imported success, $failed failed"
    set -e  # Re-enable strict mode
}

# Export main function
export -f workflow_manager_main