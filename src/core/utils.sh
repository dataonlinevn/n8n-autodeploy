#!/bin/bash

# DataOnline N8N Manager - Tiện ích Hệ thống
# Phiên bản: 1.0.0

set -euo pipefail

# Source logger nếu chưa được load
if [[ -z "${LOGGER_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/logger.sh"
fi

# Đánh dấu utils đã được load
UTILS_LOADED=true

# Kiểm tra command tồn tại
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Kiểm tra service đang chạy
is_service_running() {
    local service="$1"
    
    if systemctl is-active --quiet "$service"; then
        return 0
    else
        return 1
    fi
}

# Kiểm tra chạy với quyền root
is_root() {
    [[ $(id -u) -eq 0 ]]
}

# Lấy phiên bản Ubuntu
get_ubuntu_version() {
    if [[ -f /etc/lsb-release ]]; then
        source /etc/lsb-release
        echo "$DISTRIB_RELEASE"
    else
        echo "unknown"
    fi
}

# Kiểm tra yêu cầu hệ thống
check_system_requirements() {
    local errors=0
    
    log_debug "Đang kiểm tra yêu cầu hệ thống..."
    
    # Kiểm tra OS
    if [[ ! -f /etc/lsb-release ]]; then
        log_error "Không phải Ubuntu Linux"
        ((errors++))
    else
        local version
        version=$(get_ubuntu_version)
        log_debug "Ubuntu version: $version"
        
        # Kiểm tra phiên bản tối thiểu (20.04)
        if [[ "${version%%.*}" -lt 20 ]]; then
            log_error "Yêu cầu Ubuntu 20.04 trở lên (hiện tại: $version)"
            ((errors++))
        fi
    fi
    
    # Kiểm tra RAM (tối thiểu 1GB)
    local total_ram
    total_ram=$(free -m | awk '/^Mem:/ {print $2}')
    if [[ "$total_ram" -lt 1024 ]]; then
        log_warn "RAM thấp: ${total_ram}MB (khuyến nghị >= 1GB)"
    fi
    
    # Kiểm tra đĩa trống (tối thiểu 5GB)
    local free_disk
    free_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$free_disk" -lt 5 ]]; then
        log_warn "Ổ đĩa trống thấp: ${free_disk}GB (khuyến nghị >= 5GB)"
    fi
    
    # Kiểm tra các command cần thiết
    local required_commands=("curl" "wget" "git" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_warn "Thiếu command: $cmd"
        fi
    done
    
    return $errors
}

# Tạo chuỗi ngẫu nhiên
generate_random_string() {
    local length="${1:-32}"
    tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w "$length" | head -n 1
}

# Backup file với timestamp
backup_file() {
    local file="$1"
    local backup_dir="${2:-}"
    
    if [[ ! -f "$file" ]]; then
        log_error "File không tồn tại: $file"
        return 1
    fi
    
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local filename
    filename=$(basename "$file")
    
    if [[ -n "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        cp "$file" "$backup_dir/${filename}.${timestamp}.backup"
    else
        cp "$file" "${file}.${timestamp}.backup"
    fi
    
    log_debug "Đã backup: $file"
}

# Kiểm tra port có sẵn
is_port_available() {
    local port="$1"
    local host="${2:-0.0.0.0}"
    
    if ! nc -z "$host" "$port" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Lấy IP công khai
get_public_ip() {
    local ip
    
    # Thử nhiều service để lấy IP
    for service in "https://ipv4.icanhazip.com" "https://api.ipify.org" "https://ifconfig.me"; do
        if ip=$(curl -s --connect-timeout 2 "$service" 2>/dev/null); then
            # Validate IP format
            if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    return 1
}

# Kiểm tra domain hợp lệ
is_valid_domain() {
    local domain="$1"
    local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    
    if [[ "$domain" =~ $domain_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Kiểm tra email hợp lệ
is_valid_email() {
    local email="$1"
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    if [[ "$email" =~ $email_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Kiểm tra IP hợp lệ
is_valid_ip() {
    local ip="$1"
    local ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
    if [[ "$ip" =~ $ip_regex ]]; then
        # Kiểm tra từng octet
        IFS='.' read -ra OCTETS <<< "$ip"
        for octet in "${OCTETS[@]}"; do
            if [[ "$octet" -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Chờ service khởi động
wait_for_service() {
    local service="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    log_debug "Đang chờ service $service khởi động..."
    
    while ! is_service_running "$service"; do
        sleep 1
        ((elapsed++))
        
        if [[ $elapsed -ge $timeout ]]; then
            log_error "Timeout chờ service $service"
            return 1
        fi
    done
    
    log_debug "Service $service đã sẵn sàng"
    return 0
}

# Retry command với backoff
retry_with_backoff() {
    local max_attempts="${1:-3}"
    local delay="${2:-1}"
    shift 2
    local command=("$@")
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if "${command[@]}"; then
            return 0
        fi
        
        log_warn "Lần thử $attempt/$max_attempts thất bại, chờ ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        ((attempt++))
    done
    
    log_error "Command thất bại sau $max_attempts lần thử"
    return 1
}

# Kiểm tra kết nối internet
check_internet_connection() {
    local test_sites=("8.8.8.8" "1.1.1.1")
    
    for site in "${test_sites[@]}"; do
        if ping -c 1 -W 2 "$site" >/dev/null 2>&1; then
            return 0
        fi
    done
    
    return 1
}

# Format bytes sang human readable
format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while [[ $bytes -gt 1024 && $unit -lt ${#units[@]} ]]; do
        bytes=$((bytes / 1024))
        ((unit++))
    done
    
    echo "$bytes${units[$unit]}"
}

# Chuyển đổi seconds sang human readable
seconds_to_human() {
    local seconds="$1"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    local result=""
    [[ $days -gt 0 ]] && result="${days} ngày "
    [[ $hours -gt 0 ]] && result="${result}${hours} giờ "
    [[ $minutes -gt 0 ]] && result="${result}${minutes} phút "
    [[ $secs -gt 0 || -z "$result" ]] && result="${result}${secs} giây"
    
    echo "${result% }"
}

# Tạo thư mục an toàn
safe_mkdir() {
    local dir="$1"
    local mode="${2:-755}"
    
    if [[ ! -d "$dir" ]]; then
        if ! mkdir -p -m "$mode" "$dir"; then
            log_error "Không thể tạo thư mục: $dir"
            return 1
        fi
    fi
    
    return 0
}

# Kiểm tra và cài đặt package
ensure_package_installed() {
    local package="$1"
    
    if ! dpkg -l | grep -q "^ii  $package "; then
        log_info "Đang cài đặt $package..."
        if ! sudo apt-get update -qq && sudo apt-get install -y "$package"; then
            log_error "Không thể cài đặt $package"
            return 1
        fi
    fi
    
    return 0
}

# Lấy process ID từ port
get_pid_by_port() {
    local port="$1"
    local pid
    
    if pid=$(sudo lsof -t -i:"$port" 2>/dev/null); then
        echo "$pid"
        return 0
    fi
    
    return 1
}

# Kiểm tra file lock
is_locked() {
    local lockfile="$1"
    
    if [[ -f "$lockfile" ]]; then
        local pid
        pid=$(cat "$lockfile")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Process không tồn tại, xóa lock cũ
            rm -f "$lockfile"
        fi
    fi
    
    return 1
}

# Tạo file lock
create_lock() {
    local lockfile="$1"
    echo $$ > "$lockfile"
}

# Xóa file lock
remove_lock() {
    local lockfile="$1"
    rm -f "$lockfile"
}