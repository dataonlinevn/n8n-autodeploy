#!/bin/bash

# DataOnline N8N Manager - Simplified Workflow Manager
# Phiên bản: 1.0.0
# Quản lý workflows N8N với giao diện đơn giản và hiệu quả

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
    
    ui_section "Trạng thái hệ thống"
    echo "Tổng số kịch bản: $workflow_count"
    echo ""
    
    echo "CHỨC NĂNG QUẢN LÝ"
    echo "  1) Danh sách kịch bản (Workflows)"
    echo "  2) Xuất kịch bản (Export to Drive)"
    echo "  3) Nhập kịch bản (Import from Drive)"
    echo ""
    echo "  0) Quay lại"
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
        ui_error "Không thể kết nối với n8n API. Vui lòng kiểm tra lại API Key."
        return 1
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
    local RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"
    
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        return 1
    fi
    
    # Ưu tiên 1: Sử dụng remote đã được lưu trong config (nếu có backup-utils được load)
    if command -v get_saved_gdrive_remote_name >/dev/null 2>&1; then
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

get_gdrive_remote() {
    get_gdrive_remote_name
}

# ===== LIST WORKFLOWS =====

list_workflows() {
    ui_section "Danh sách Kịch bản (Workflows)"
    
    ui_start_spinner "Đang tải danh sách..."
    local workflows=$(make_api_call "GET" "workflows")
    ui_stop_spinner
    
    if ! echo "$workflows" | jq -e '.data' >/dev/null 2>&1; then
        ui_error "Lỗi lấy dữ liệu từ n8n"
        return 1
    fi
    
    echo ""
    printf "%-10s %-40s %-15s\n" "ID" "Tên Kịch Bản" "Trạng Thái"
    echo "────────────────────────────────────────────────────────────────────────────"
    
    echo "$workflows" | jq -r '.data[] | @json' | while read -r workflow_json; do
        local id=$(echo "$workflow_json" | jq -r '.id')
        local name=$(echo "$workflow_json" | jq -r '.name')
        local active=$(echo "$workflow_json" | jq -r '.active')
        
        local status=$([ "$active" = "true" ] && echo "Đang chạy" || echo "Đã dừng")
        
        printf "%-10s %-40s %-15s\n" "${id:0:8}" "${name:0:38}" "$status"
    done
    
    echo ""
    ui_info "Tổng cộng: $(echo "$workflows" | jq '.data | length') kịch bản."
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
    set +e
    
    ui_start_spinner "Đang chuẩn bị dữ liệu kịch bản..."
    local workflows=$(make_api_call "GET" "workflows")
    
    if ! echo "$workflows" | jq -e '.data' >/dev/null 2>&1; then
        ui_stop_spinner
        ui_error "Không thể lấy dữ liệu từ n8n"
        set -e
        return 1
    fi
    
    local temp_dir="/tmp/n8n_export_$(date +%s)"
    mkdir -p "$temp_dir"
    
    local count=0
    local workflow_ids=($(echo "$workflows" | jq -r '.data[].id'))
    
    for id in "${workflow_ids[@]}"; do
        local workflow_data=$(echo "$workflows" | jq -r ".data[] | select(.id==\"$id\")")
        local name=$(echo "$workflow_data" | jq -r '.name' | sed 's/[^a-zA-Z0-9_-]/_/g')
        echo "$workflow_data" > "$temp_dir/${name}_${id}.json"
        count=$((count + 1))
    done
    ui_stop_spinner
    
    ui_start_spinner "Đang tải $count kịch bản lên Google Drive..."
    local remote_name
    if ! remote_name=$(get_gdrive_remote_name); then
        ui_stop_spinner
        ui_error "Không tìm thấy kết nối Google Drive"
        set -e
        return 1
    fi
    
    rclone mkdir "$remote_name:n8n-workflows" 2>/dev/null || true
    
    if rclone copy "$temp_dir/" "$remote_name:n8n-workflows/" --include "*.json" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_success "Đã sao lưu $count kịch bản lên Google Drive thành công."
    else
        ui_stop_spinner
        ui_error "Lỗi tải dữ liệu lên Google Drive"
    fi
    
    rm -rf "$temp_dir"
    set -e
    return 0
}

export_selected_workflows() {
    set +e
    
    local workflows=$(make_api_call "GET" "workflows")
    
    echo ""
    ui_info "Danh sách kịch bản để chọn:"
    echo ""
    
    local index=1
    echo "$workflows" | jq -c '.data[]' | while read -r workflow; do
        local name=$(echo "$workflow" | jq -r '.name')
        local active=$(echo "$workflow" | jq -r '.active')
        local status=$([ "$active" = "true" ] && echo "(Đang chạy)" || echo "(Dừng)")
        echo "  $index) $name $status"
        index=$((index + 1))
    done
    
    echo ""
    echo -n -e "${UI_WHITE}Nhập số thứ tự (ví dụ: 1,3,5): ${UI_NC}"
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
                count=$((count + 1))
            fi
        fi
    done
    
    if [[ $count -gt 0 ]]; then
        ui_start_spinner "Đang tải $count kịch bản đã chọn lên Google Drive..."
        local remote_name
        if ! remote_name=$(get_gdrive_remote_name); then
            ui_stop_spinner
            ui_error "Không tìm thấy kết nối Google Drive"
            set -e
            return 1
        fi
        
        rclone mkdir "$remote_name:n8n-workflows" >/dev/null 2>&1 || true
        
        if rclone copy "$temp_dir/" "$remote_name:n8n-workflows/" --include "*.json" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_success "Đã sao lưu $count kịch bản lên Google Drive thành công."
        else
            ui_stop_spinner
            ui_error "Lỗi tải dữ liệu lên Google Drive"
        fi
    else
        ui_info "Không có kịch bản nào được chọn để xuất."
    fi
    
    rm -rf "$temp_dir"
    set -e
}

upload_to_gdrive() {
    local temp_dir="$1"
    local count="$2"
    
    local remote_name=$(get_gdrive_remote)
    if [[ -z "$remote_name" ]]; then
        return 1
    fi
    
    ui_start_spinner "Đang tải kịch bản lên Google Drive..."
    rclone mkdir "${remote_name}:${GDRIVE_FOLDER}" 2>/dev/null || true
    
    if rclone copy "$temp_dir/" "${remote_name}:${GDRIVE_FOLDER}/" --include "*.json" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_success "Đã sao lưu kịch bản thành công."
    else
        ui_stop_spinner
        ui_error "Lỗi tải dữ liệu lên Drive."
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
    echo -n -e "${UI_WHITE}Nhập số thứ tự (hoặc 'all' để lấy tất cả): ${UI_NC}"
    read -r selection
    
    local temp_dir="/tmp/n8n_import_$(date +%s)"
    mkdir -p "$temp_dir"
    
    if [[ "$selection" == "all" ]]; then
        # Download all files
        ui_start_spinner "Đang tải về toàn bộ kịch bản..."
        rclone copy "${remote_name}:n8n-workflows/" "$temp_dir/" --include "*.json"
        ui_stop_spinner
        
        import_workflow_files "$temp_dir"
    else
        # Download specific file
        local file_index=$((selection))
        local selected_file=$(echo "$files" | sed -n "${file_index}p" | awk '{print $2}')
        
        if [[ -n "$selected_file" ]]; then
            ui_start_spinner "Đang tải về kịch bản đã chọn..."
            rclone copy "${remote_name}:n8n-workflows/$selected_file" "$temp_dir/"
            ui_stop_spinner
            
            import_workflow_files "$temp_dir"
        else
            ui_error "Lựa chọn không hợp lệ."
        fi
    fi
    
    rm -rf "$temp_dir"
}

import_workflow_files() {
    set +e
    
    local import_dir="$1"
    local json_files=($(find "$import_dir" -name "*.json" -type f))
    
    if [[ ${#json_files[@]} -eq 0 ]]; then
        ui_error "Không tìm thấy tệp kịch bản hợp lệ"
        set -e
        return 1
    fi
    
    local imported=0
    local failed=0
    
    ui_info "Đang xử lý ${#json_files[@]} tệp kịch bản..."
    
    for file in "${json_files[@]}"; do
        local filename=$(basename "$file")
        
        # Validate JSON
        if ! jq empty "$file" 2>/dev/null; then
            failed=$((failed + 1))
            continue
        fi
        
        local workflow_data=""
        if jq -e '.name' "$file" >/dev/null 2>&1; then
            workflow_data=$(jq '{name: .name, nodes: .nodes, connections: .connections, settings: (.settings // {})}' "$file" 2>/dev/null)
        elif jq -e '.data.name' "$file" >/dev/null 2>&1; then
            workflow_data=$(jq '.data | {name: .name, nodes: .nodes, connections: .connections, settings: (.settings // {})}' "$file" 2>/dev/null)
        fi
        
        if [[ -z "$workflow_data" || "$workflow_data" == "null" ]]; then
            failed=$((failed + 1))
            continue
        fi
        
        local workflow_name=$(echo "$workflow_data" | jq -r '.name // ""')
        if [[ -z "$workflow_name" ]]; then
            failed=$((failed + 1))
            continue
        fi
        
        # Check if workflow exists
        local existing_workflows=$(make_api_call "GET" "workflows")
        local existing_id=$(echo "$existing_workflows" | jq -r ".data[] | select(.name==\"$workflow_name\") | .id" 2>/dev/null)
        
        if [[ -n "$existing_id" ]]; then
            if ui_confirm "Kịch bản '$workflow_name' đã tồn tại. Ghi đè?"; then
                local response=$(make_api_call "PUT" "workflows/$existing_id" "$workflow_data")
                if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
                    imported=$((imported + 1))
                else
                    failed=$((failed + 1))
                fi
            fi
        else
            local response=$(make_api_call "POST" "workflows" "$workflow_data")
            if echo "$response" | jq -e '.id' >/dev/null 2>&1; then
                imported=$((imported + 1))
            else
                failed=$((failed + 1))
            fi
        fi
    done
    
    echo ""
    if [[ $failed -eq 0 ]]; then
        ui_success "Đã nhập thành công $imported kịch bản."
    else
        ui_info "Hoàn tất: $imported thành công, $failed thất bại."
    fi
    set -e
}

# Export main function
export -f workflow_manager_main