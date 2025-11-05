#!/bin/bash

# DataOnline N8N Manager - Advanced Spinner System
# Phiên bản: 1.0.0

set -euo pipefail

# Đánh dấu spinner đã được load
SPINNER_LOADED=true

# Colors
readonly SPINNER_CYAN='\033[0;36m'
readonly SPINNER_GREEN='\033[0;32m'
readonly SPINNER_RED='\033[0;31m'
readonly SPINNER_YELLOW='\033[1;33m'
readonly SPINNER_NC='\033[0m'

# Spinner variations
readonly SPINNER_DOTS=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
readonly SPINNER_CLOCK=('🕐' '🕑' '🕒' '🕓' '🕔' '🕕' '🕖' '🕗' '🕘' '🕙' '🕚' '🕛')
readonly SPINNER_ARROWS=('←' '↖' '↑' '↗' '→' '↘' '↓' '↙')
readonly SPINNER_BARS=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' '▇' '▆' '▅' '▄' '▃' '▁')
readonly SPINNER_SIMPLE=('-' '\' '|' '/')

# Global spinner state
SPINNER_PID=0
SPINNER_TYPE="dots" 
SPINNER_DELAY=0.1

# ===== CORE SPINNER FUNCTIONS =====

# Internal spinner function
_spinner_loop() {
    local message="$1"
    local type="$2"
    local delay="$3"
    local color="$4"
    
    local chars_array_name="SPINNER_${type^^}"
    local chars=()
    
    # Get spinner characters based on type
    case "$type" in
        "dots") chars=("${SPINNER_DOTS[@]}") ;;
        "clock") chars=("${SPINNER_CLOCK[@]}") ;;
        "arrows") chars=("${SPINNER_ARROWS[@]}") ;;
        "bars") chars=("${SPINNER_BARS[@]}") ;;
        "simple") chars=("${SPINNER_SIMPLE[@]}") ;;
        *) chars=("${SPINNER_DOTS[@]}") ;;
    esac
    
    local i=0
    tput civis # Hide cursor
    
    trap 'tput cnorm; return' INT TERM
    
    while true; do
        echo -n -e "\r${color}${chars[$i]} $message${SPINNER_NC}"
        i=$(( (i+1) % ${#chars[@]} ))
        sleep "$delay"
    done
}

# Start spinner
start_spinner() {
    local message="$1"
    local type="${2:-$SPINNER_TYPE}"
    local delay="${3:-$SPINNER_DELAY}"
    local color="${4:-$SPINNER_CYAN}"
    
    # Stop existing spinner if running
    if [[ $SPINNER_PID -ne 0 ]]; then
        stop_spinner
    fi
    
    _spinner_loop "$message" "$type" "$delay" "$color" &
    SPINNER_PID=$!
    
    # Set trap to cleanup on script exit
    trap "stop_spinner;" SIGINT SIGTERM EXIT
}

# Stop spinner
stop_spinner() {
    if [[ $SPINNER_PID -ne 0 ]]; then
        kill "$SPINNER_PID" &>/dev/null || true
        wait "$SPINNER_PID" &>/dev/null || true
        echo -n -e "\r\033[K" # Clear line
        SPINNER_PID=0
    fi
    tput cnorm # Show cursor
}

# ===== ENHANCED SPINNER FUNCTIONS =====

# Spinner with success/failure feedback
spinner_with_feedback() {
    local message="$1"
    local command="$2"
    local success_msg="${3:-Hoàn thành}"
    local error_msg="${4:-Thất bại}"
    local type="${5:-dots}"
    
    start_spinner "$message" "$type"
    
    local log_file="/tmp/spinner_cmd_$(date +%s%N).log"
    
    if eval "$command" >> "$log_file" 2>&1; then
        stop_spinner
        echo -e "${SPINNER_GREEN}✅ $message - $success_msg${SPINNER_NC}"
        rm -f "$log_file"
        return 0
    else
        stop_spinner
        echo -e "${SPINNER_RED}❌ $message - $error_msg${SPINNER_NC}"
        
        # Show error details
        if [[ -f "$log_file" ]]; then
            echo -e "${SPINNER_YELLOW}Chi tiết lỗi:${SPINNER_NC}"
            tail -n 3 "$log_file" | sed 's/^/  /'
            echo -e "${SPINNER_YELLOW}Log đầy đủ: $log_file${SPINNER_NC}"
        fi
        return 1
    fi
}

# Progress spinner (with steps)
progress_spinner() {
    local current="$1"
    local total="$2"
    local message="$3"
    local type="${4:-bars}"
    
    local percentage=$((current * 100 / total))
    local progress_msg="[$current/$total - ${percentage}%] $message"
    
    start_spinner "$progress_msg" "$type"
}

# Timed spinner (auto-stop after duration)
timed_spinner() {
    local message="$1"
    local duration="$2"
    local type="${3:-dots}"
    
    start_spinner "$message" "$type"
    sleep "$duration"
    stop_spinner
}

# ===== SPECIALIZED SPINNERS =====

# Network operation spinner
network_spinner() {
    local message="$1"
    local command="$2"
    
    spinner_with_feedback "🌐 $message" "$command" "Kết nối thành công" "Kết nối thất bại" "arrows"
}

# Download spinner
download_spinner() {
    local message="$1"
    local command="$2"
    
    spinner_with_feedback "📥 $message" "$command" "Tải xuống hoàn tất" "Tải xuống thất bại" "bars"
}

# Installation spinner
install_spinner() {
    local message="$1"
    local command="$2"
    
    spinner_with_feedback "📦 $message" "$command" "Cài đặt thành công" "Cài đặt thất bại" "dots"
}

# Configuration spinner
config_spinner() {
    local message="$1"
    local command="$2"
    
    spinner_with_feedback "⚙️ $message" "$command" "Cấu hình hoàn tất" "Cấu hình thất bại" "simple"
}

# Service management spinner
service_spinner() {
    local message="$1"
    local command="$2"
    
    spinner_with_feedback "🔧 $message" "$command" "Service sẵn sàng" "Service lỗi" "clock"
}

# ===== UTILITY FUNCTIONS =====

# Set default spinner type
set_spinner_type() {
    local type="$1"
    
    case "$type" in
        "dots"|"clock"|"arrows"|"bars"|"simple")
            SPINNER_TYPE="$type"
            ;;
        *)
            echo -e "${SPINNER_YELLOW}⚠️ Spinner type không hợp lệ: $type. Sử dụng 'dots'${SPINNER_NC}"
            SPINNER_TYPE="dots"
            ;;
    esac
}

# Set spinner delay
set_spinner_delay() {
    local delay="$1"
    
    if [[ "$delay" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        SPINNER_DELAY="$delay"
    else
        echo -e "${SPINNER_YELLOW}⚠️ Delay không hợp lệ: $delay. Sử dụng 0.1${SPINNER_NC}"
        SPINNER_DELAY=0.1
    fi
}

# Check if spinner is running
is_spinner_running() {
    [[ $SPINNER_PID -ne 0 ]]
}

# Demo function to test spinners
demo_spinners() {
    echo -e "${SPINNER_CYAN}=== Demo Spinner System ===${SPINNER_NC}"
    echo ""
    
    local types=("dots" "clock" "arrows" "bars" "simple")
    
    for type in "${types[@]}"; do
        echo -e "${SPINNER_YELLOW}Testing $type spinner...${SPINNER_NC}"
        start_spinner "Demo $type spinner" "$type"
        sleep 2
        stop_spinner
        echo -e "${SPINNER_GREEN}✅ $type spinner hoạt động${SPINNER_NC}"
        echo ""
    done
    
    echo -e "${SPINNER_CYAN}Testing specialized spinners...${SPINNER_NC}"
    network_spinner "Kiểm tra kết nối" "ping -c 1 google.com"
    install_spinner "Cài đặt demo package" "sleep 1"
    config_spinner "Cấu hình demo" "sleep 1"
    
    echo -e "${SPINNER_GREEN}✅ Demo hoàn tất!${SPINNER_NC}"
}

# Cleanup function
spinner_cleanup() {
    stop_spinner
    tput cnorm
}

# Set cleanup trap
trap spinner_cleanup EXIT

# Export functions
export -f start_spinner stop_spinner spinner_with_feedback progress_spinner
export -f network_spinner download_spinner install_spinner config_spinner service_spinner
export -f set_spinner_type set_spinner_delay is_spinner_running