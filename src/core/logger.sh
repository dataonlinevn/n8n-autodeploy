#!/bin/bash

# DataOnline N8N Manager - Hệ thống Logging
# Phiên bản: 1.0.0

set -euo pipefail

# Đánh dấu logger đã được load
LOGGER_LOADED=true

# Màu sắc cho log
readonly LOG_RED='\033[0;31m'
readonly LOG_GREEN='\033[0;32m'
readonly LOG_YELLOW='\033[1;33m'
readonly LOG_BLUE='\033[0;34m'
readonly LOG_CYAN='\033[0;36m'
readonly LOG_WHITE='\033[1;37m'
readonly LOG_GRAY='\033[0;37m'
readonly LOG_NC='\033[0m'

# Cấp độ log
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_SUCCESS=4

# Cấp độ log hiện tại
LOG_CURRENT_LEVEL=${LOG_CURRENT_LEVEL:-$LOG_LEVEL_INFO}

# File log
LOG_FILE=${LOG_FILE:-"/var/log/datalonline-manager.log"}

# Khởi tạo logging
init_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    
    # Tạo thư mục log nếu chưa có
    if [[ ! -d "$log_dir" ]]; then
        if ! sudo mkdir -p "$log_dir" 2>/dev/null; then
            # Fallback về home directory nếu không tạo được system log
            LOG_FILE="$HOME/.datalonline-manager.log"
        fi
    fi
    
    # Kiểm tra quyền ghi
    if ! touch "$LOG_FILE" 2>/dev/null; then
        LOG_FILE="$HOME/.datalonline-manager.log"
    fi
}

# Lấy timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Ghi vào file log
write_log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(get_timestamp)
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Log debug
log_debug() {
    [[ $LOG_CURRENT_LEVEL -le $LOG_LEVEL_DEBUG ]] || return 0
    
    local message="$1"
    echo -e "${LOG_GRAY}[DEBUG]${LOG_NC} $message" >&2
    write_log "DEBUG" "$message"
}

# Log thông tin
log_info() {
    [[ $LOG_CURRENT_LEVEL -le $LOG_LEVEL_INFO ]] || return 0
    
    local message="$1"
    echo -e "${LOG_CYAN}[THÔNG TIN]${LOG_NC} $message"
    write_log "INFO" "$message"
}

# Log cảnh báo
log_warn() {
    [[ $LOG_CURRENT_LEVEL -le $LOG_LEVEL_WARN ]] || return 0
    
    local message="$1"
    echo -e "${LOG_YELLOW}[CẢNH BÁO]${LOG_NC} $message" >&2
    write_log "WARN" "$message"
}

# Log lỗi
log_error() {
    [[ $LOG_CURRENT_LEVEL -le $LOG_LEVEL_ERROR ]] || return 0
    
    local message="$1"
    echo -e "${LOG_RED}[LỖI]${LOG_NC} $message" >&2
    write_log "ERROR" "$message"
}

# Log thành công
log_success() {
    [[ $LOG_CURRENT_LEVEL -le $LOG_LEVEL_SUCCESS ]] || return 0
    
    local message="$1"
    echo -e "${LOG_GREEN}[THÀNH CÔNG]${LOG_NC} $message"
    write_log "SUCCESS" "$message"
}

# Log với prefix tùy chỉnh
log_custom() {
    local prefix="$1"
    local message="$2"
    local color="${3:-$LOG_WHITE}"
    
    echo -e "${color}[$prefix]${LOG_NC} $message"
    write_log "$prefix" "$message"
}

# Thiết lập cấp độ log
set_log_level() {
    local level="$1"
    
    case "$level" in
        "debug"|"DEBUG") LOG_CURRENT_LEVEL=$LOG_LEVEL_DEBUG ;;
        "info"|"INFO") LOG_CURRENT_LEVEL=$LOG_LEVEL_INFO ;;
        "warn"|"WARN") LOG_CURRENT_LEVEL=$LOG_LEVEL_WARN ;;
        "error"|"ERROR") LOG_CURRENT_LEVEL=$LOG_LEVEL_ERROR ;;
        *) log_error "Cấp độ log không hợp lệ: $level" ;;
    esac
}

# Hiển thị tiến trình với spinner
show_progress() {
    local message="$1"
    local command="$2"
    
    echo -n -e "${LOG_CYAN}[TIẾN TRÌNH]${LOG_NC} $message... "
    
    local spin='-\|/'
    local i=0
    
    while kill -0 $! 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${LOG_CYAN}[TIẾN TRÌNH]${LOG_NC} $message... ${spin:$i:1}"
        sleep 0.1
    done
    
    printf "\r${LOG_CYAN}[TIẾN TRÌNH]${LOG_NC} $message... "
    
    if wait $!; then
        echo -e "${LOG_GREEN}✅${LOG_NC}"
    else
        echo -e "${LOG_RED}❌${LOG_NC}"
        return 1
    fi
}

# Khởi tạo logging khi source
init_logging