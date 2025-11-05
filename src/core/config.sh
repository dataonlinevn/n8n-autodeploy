#!/bin/bash

# DataOnline N8N Manager - Quản lý Cấu hình
# Phiên bản: 1.0.0

set -euo pipefail

# Source logger (chỉ source nếu chưa được source)
if [[ -z "${LOGGER_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/logger.sh"
fi

readonly DEFAULT_CONFIG_DIR="/etc/datalonline-n8n"
readonly USER_CONFIG_DIR="$HOME/.config/datalonline-n8n"
readonly PROJECT_CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

CONFIG_DIR=""
CONFIG_FILE=""

# Cấu hình mặc định
declare -A DEFAULT_CONFIG=(
    ["app.name"]="DataOnline N8N Manager"
    ["app.version"]="1.0.0"
    ["app.debug"]="false"
    ["logging.level"]="info"
    ["logging.file"]="/var/log/datalonline-manager.log"
    ["n8n.port"]="5678"
    ["n8n.host"]="localhost"
    ["n8n.protocol"]="http"
    ["nginx.port"]="80"
    ["nginx.ssl_port"]="443"
    ["backup.retention_days"]="30"
    ["backup.enabled"]="true"
    ["ssl.auto_setup"]="true"
    ["ssl.provider"]="letsencrypt"
)

# Cache cấu hình
declare -A CONFIG_CACHE=()

# Khởi tạo cấu hình
init_config() {
    log_debug "Đang khởi tạo hệ thống cấu hình..."
    
    # Xác định thư mục config
    if [[ -w "/etc" ]] && [[ $(id -u) -eq 0 ]]; then
        CONFIG_DIR="$DEFAULT_CONFIG_DIR"
    elif [[ -d "$USER_CONFIG_DIR" ]] || mkdir -p "$USER_CONFIG_DIR" 2>/dev/null; then
        CONFIG_DIR="$USER_CONFIG_DIR"
    else
        CONFIG_DIR="$PROJECT_CONFIG_DIR"
    fi
    
    CONFIG_FILE="$CONFIG_DIR/settings.conf"
    
    log_debug "Thư mục config: $CONFIG_DIR"
    log_debug "File config: $CONFIG_FILE"
    
    # Tạo thư mục config nếu cần
    if [[ ! -d "$CONFIG_DIR" ]]; then
        if ! mkdir -p "$CONFIG_DIR"; then
            log_error "Không thể tạo thư mục config: $CONFIG_DIR"
            return 1
        fi
    fi
    
    # Tạo config mặc định nếu chưa có
    if [[ ! -f "$CONFIG_FILE" ]]; then
        create_default_config
    fi
    
    # Load cấu hình vào cache
    load_config
}

# Tạo file cấu hình mặc định
create_default_config() {
    log_info "Đang tạo cấu hình mặc định..."
    
    cat > "$CONFIG_FILE" << 'CONFIG_EOF'
# DataOnline N8N Manager - Cấu hình
# Được tạo tự động - chỉnh sửa cẩn thận

[app]
name="DataOnline N8N Manager"
version="1.0.0"
debug=false

[logging]
level=info
file=/var/log/datalonline-manager.log

[n8n]
port=5678
host=localhost
protocol=http

[nginx]
port=80
ssl_port=443

[backup]
retention_days=30
enabled=true

[ssl]
auto_setup=true
provider=letsencrypt
CONFIG_EOF

    log_success "Đã tạo cấu hình mặc định: $CONFIG_FILE"
}

# Load cấu hình vào cache
load_config() {
    log_debug "Đang load cấu hình từ: $CONFIG_FILE"
    
    # Xóa cache
    CONFIG_CACHE=()
    
    # Load mặc định trước
    for key in "${!DEFAULT_CONFIG[@]}"; do
        CONFIG_CACHE["$key"]="${DEFAULT_CONFIG[$key]}"
    done
    
    # Load từ file nếu có
    if [[ -f "$CONFIG_FILE" ]]; then
        local current_section=""
        
        while IFS= read -r line; do
            # Bỏ qua comment và dòng trống
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            
            # Parse section headers
            if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
                current_section="${BASH_REMATCH[1]}"
                continue
            fi
            
            # Parse key=value pairs
            if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]// /}"  # Xóa spaces
                local value="${BASH_REMATCH[2]}"
                
                # Xóa quotes khỏi value
                value="${value#\"}"
                value="${value%\"}"
                
                # Lưu với section prefix
                if [[ -n "$current_section" ]]; then
                    CONFIG_CACHE["$current_section.$key"]="$value"
                else
                    CONFIG_CACHE["$key"]="$value"
                fi
            fi
        done < "$CONFIG_FILE"
    fi
    
    log_debug "Đã load cấu hình với ${#CONFIG_CACHE[@]} entries"
}

# Lấy giá trị cấu hình
config_get() {
    local key="$1"
    local default_value="${2:-}"
    
    if [[ -n "${CONFIG_CACHE[$key]:-}" ]]; then
        echo "${CONFIG_CACHE[$key]}"
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
    else
        log_debug "Không tìm thấy khóa cấu hình: $key"
        return 1
    fi
}

# Thiết lập giá trị cấu hình
config_set() {
    local key="$1"
    local value="$2"
    local persist="${3:-true}"
    
    CONFIG_CACHE["$key"]="$value"
    
    if [[ "$persist" == "true" ]]; then
        save_config
    fi
}

# Lưu cấu hình vào file
save_config() {
    log_debug "Đang lưu cấu hình vào: $CONFIG_FILE"
    
    # Tạo backup
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
    fi
    
    # Nhóm keys theo section
    declare -A sections
    
    for key in "${!CONFIG_CACHE[@]}"; do
        if [[ "$key" =~ ^([^.]+)\.(.+)$ ]]; then
            local section="${BASH_REMATCH[1]}"
            local setting="${BASH_REMATCH[2]}"
            sections["$section"]+="$setting=\"${CONFIG_CACHE[$key]}\"\n"
        else
            sections["general"]+="$key=\"${CONFIG_CACHE[$key]}\"\n"
        fi
    done
    
    # Ghi file config
    {
        echo "# DataOnline N8N Manager - Cấu hình"
        echo "# Cập nhật: $(date)"
        echo ""
        
        for section in "${!sections[@]}"; do
            if [[ "$section" != "general" ]]; then
                echo "[$section]"
                echo -e "${sections[$section]}"
                echo ""
            fi
        done
        
        # Ghi general settings nếu có
        if [[ -n "${sections[general]:-}" ]]; then
            echo "[general]"
            echo -e "${sections[general]}"
        fi
    } > "$CONFIG_FILE"
    
    log_success "Đã lưu cấu hình"
}

# Hiển thị cấu hình hiện tại
show_config() {
    echo ""
    log_info "CẤU HÌNH HIỆN TẠI:"
    echo ""
    
    for key in $(printf '%s\n' "${!CONFIG_CACHE[@]}" | sort); do
        printf "  %-25s = %s\n" "$key" "${CONFIG_CACHE[$key]}"
    done
    
    echo ""
    echo "File cấu hình: $CONFIG_FILE"
    echo ""
}

# Kiểm tra tính hợp lệ của cấu hình
validate_config() {
    log_info "Đang kiểm tra cấu hình..."
    local errors=0
    
    # Kiểm tra các thiết lập bắt buộc
    local required_keys=(
        "app.name"
        "n8n.port"
        "n8n.host"
    )
    
    for key in "${required_keys[@]}"; do
        if ! config_get "$key" >/dev/null 2>&1; then
            log_error "Thiếu cấu hình bắt buộc: $key"
            ((errors++))
        fi
    done
    
    # Kiểm tra port numbers
    local n8n_port
    n8n_port=$(config_get "n8n.port")
    if ! [[ "$n8n_port" =~ ^[0-9]+$ ]] || [[ "$n8n_port" -lt 1 ]] || [[ "$n8n_port" -gt 65535 ]]; then
        log_error "Port N8N không hợp lệ: $n8n_port"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Kiểm tra cấu hình thành công"
        return 0
    else
        log_error "Kiểm tra cấu hình thất bại với $errors lỗi"
        return 1
    fi
}

# Đánh dấu config đã được load
CONFIG_LOADED=true

# Khởi tạo khi source
init_config