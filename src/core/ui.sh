#!/bin/bash

# DataOnline N8N Manager - Advanced UI System
# Phiên bản: 1.0.0

set -euo pipefail

# Source logger if not loaded
if [[ -z "${LOGGER_LOADED:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/logger.sh"
fi

# UI Components
readonly UI_LOADED=true

# Colors for UI
readonly UI_RED='\033[0;31m'
readonly UI_GREEN='\033[0;32m'
readonly UI_YELLOW='\033[1;33m'
readonly UI_BLUE='\033[0;34m'
readonly UI_CYAN='\033[0;36m'
readonly UI_WHITE='\033[1;37m'
readonly UI_GRAY='\033[0;37m'
readonly UI_NC='\033[0m'

# Unicode characters for enhanced UI
readonly UI_CHECK="✅"
readonly UI_CROSS="❌"
readonly UI_WARNING="⚠️"
readonly UI_INFO="ℹ️"
readonly UI_ROCKET="🚀"
readonly UI_GEAR="⚙️"
readonly UI_CLOUD="☁️"
readonly UI_LOCK="🔒"

# Global spinner PID
UI_SPINNER_PID=0

# ===== SPINNER SYSTEM =====

# Advanced spinner with Unicode characters
_ui_spinner() {
    local message="$1"
    local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    
    tput civis # Hide cursor
    trap 'tput cnorm; return' INT TERM
    
    while true; do
        echo -n -e "\r${UI_CYAN}${spin_chars[$i]} $message${UI_NC}"
        i=$(( (i+1) % ${#spin_chars[@]} ))
        sleep 0.1
    done
}

# Start spinner
ui_start_spinner() {
    local message="$1"
    
    if [[ $UI_SPINNER_PID -ne 0 ]]; then
        ui_stop_spinner
    fi
    
    _ui_spinner "$message" &
    UI_SPINNER_PID=$!
    trap "ui_stop_spinner;" SIGINT SIGTERM
}

# Stop spinner
ui_stop_spinner() {
    if [[ $UI_SPINNER_PID -ne 0 ]]; then
        kill "$UI_SPINNER_PID" &>/dev/null || true
        wait "$UI_SPINNER_PID" &>/dev/null || true
        echo -n -e "\r\033[K" # Clear line
        UI_SPINNER_PID=0
    fi
    tput cnorm # Show cursor
}

# ===== PROGRESS INDICATORS =====

# Show progress with steps
ui_show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    local width=40
    
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    
    echo -e "\r${UI_CYAN}[$bar] ${percentage}% ${message}${UI_NC}"
}

# ===== INTERACTIVE PROMPTS =====

# Enhanced prompt with validation
ui_prompt() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local validation_pattern="${3:-.*}"
    local error_message="${4:-Giá trị không hợp lệ}"
    local allow_empty="${5:-false}"
    
    local user_input
    local display_default=""
    
    if [[ -n "$default_value" ]]; then
        display_default=" (mặc định: $default_value)"
    fi
    
    while true; do
        echo -n -e "${UI_WHITE}$prompt_text${display_default}: ${UI_NC}"
        read -r user_input
        
        # Use default if empty
        if [[ -z "$user_input" && -n "$default_value" ]]; then
            user_input="$default_value"
        fi
        
        # Check if empty is allowed
        if [[ -z "$user_input" && "$allow_empty" == "false" ]]; then
            echo -e "${UI_RED}${UI_CROSS} Giá trị không được để trống${UI_NC}"
            continue
        fi
        
        # Validate input
        if [[ "$user_input" =~ $validation_pattern ]]; then
            echo "$user_input"
            return 0
        else
            echo -e "${UI_RED}${UI_CROSS} $error_message${UI_NC}"
        fi
    done
}

# Yes/No confirmation
ui_confirm() {
    local message="$1"
    local default="${2:-y}"
    local response
    
    while true; do
        if [[ "$default" == "y" ]]; then
            echo -n -e "${UI_YELLOW}$message [Y/n]: ${UI_NC}"
        else
            echo -n -e "${UI_YELLOW}$message [y/N]: ${UI_NC}"
        fi
        
        read -r response
        
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo -e "${UI_RED}Vui lòng nhập Y hoặc N${UI_NC}" ;;
        esac
    done
}

# Select from menu
ui_select() {
    local title="$1"
    shift
    local options=("$@")
    
    echo -e "${UI_CYAN}$title${UI_NC}"
    echo ""
    
    for i in "${!options[@]}"; do
        echo -e "${UI_WHITE}$((i+1))) ${options[$i]}${UI_NC}"
    done
    echo ""
    
    while true; do
        echo -n -e "${UI_WHITE}Chọn [1-${#options[@]}]: ${UI_NC}"
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            echo $((choice-1))
            return 0
        else
            echo -e "${UI_RED}${UI_CROSS} Lựa chọn không hợp lệ${UI_NC}"
        fi
    done
}

# ===== STATUS DISPLAY =====

# Show status with icon
ui_status() {
    local status="$1"
    local message="$2"
    local icon color
    
    case "$status" in
        "success"|"ok")
            icon="$UI_CHECK"
            color="$UI_GREEN"
            ;;
        "error"|"fail")
            icon="$UI_CROSS"
            color="$UI_RED"
            ;;
        "warning"|"warn")
            icon="$UI_WARNING"
            color="$UI_YELLOW"
            ;;
        "info")
            icon="$UI_INFO"
            color="$UI_BLUE"
            ;;
        *)
            icon="•"
            color="$UI_WHITE"
            ;;
    esac
    
    echo -e "${color}${icon} $message${UI_NC}"
}

# ===== COMMAND EXECUTION WITH UI =====

# Execute command with progress
ui_run_command() {
    local message="$1"
    local command="$2"
    local show_output="${3:-false}"
    local log_file="/tmp/ui_command_$(date +%s%N).log"
    
    ui_start_spinner "$message"
    
    if [[ "$show_output" == "true" ]]; then
        if eval "$command" 2>&1 | tee "$log_file"; then
            ui_stop_spinner
            ui_status "success" "$message - Hoàn thành"
            rm -f "$log_file"
            return 0
        else
            ui_stop_spinner
            ui_status "error" "$message - Thất bại"
            echo -e "${UI_YELLOW}Log chi tiết:${UI_NC}"
            tail -n 5 "$log_file" | sed 's/^/  /'
            return 1
        fi
    else
        if eval "$command" >> "$log_file" 2>&1; then
            ui_stop_spinner
            ui_status "success" "$message - Hoàn thành"
            rm -f "$log_file"
            return 0
        else
            ui_stop_spinner
            ui_status "error" "$message - Thất bại"
            echo -e "${UI_YELLOW}Log chi tiết tại: $log_file${UI_NC}"
            echo -e "${UI_YELLOW}5 dòng cuối:${UI_NC}"
            tail -n 5 "$log_file" | sed 's/^/  /'
            return 1
        fi
    fi
}

# ===== ADVANCED UI COMPONENTS =====

# Display header
ui_header() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title}) / 2 ))
    
    echo -e "${UI_CYAN}╭$(printf '─%.0s' $(seq 1 $((width-2))))╮${UI_NC}"
    echo -e "${UI_CYAN}│$(printf ' %.0s' $(seq 1 $padding))$title$(printf ' %.0s' $(seq 1 $((width-2-padding-${#title}))))│${UI_NC}"
    echo -e "${UI_CYAN}╰$(printf '─%.0s' $(seq 1 $((width-2))))╯${UI_NC}"
    echo ""
}

# Display section
ui_section() {
    local title="$1"
    echo ""
    echo -e "${UI_WHITE}═══ $title ═══${UI_NC}"
    echo ""
}

# Display info box
ui_info_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo -e "${UI_BLUE}┌─ $title ─┐${UI_NC}"
    for line in "${lines[@]}"; do
        echo -e "${UI_BLUE}│${UI_NC} $line"
    done
    echo -e "${UI_BLUE}└$(printf '─%.0s' $(seq 1 $((${#title}+3))))┘${UI_NC}"
}

# Display warning box
ui_warning_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo -e "${UI_YELLOW}┌─ ${UI_WARNING} $title ─┐${UI_NC}"
    for line in "${lines[@]}"; do
        echo -e "${UI_YELLOW}│${UI_NC} $line"
    done
    echo -e "${UI_YELLOW}└$(printf '─%.0s' $(seq 1 $((${#title}+5))))┘${UI_NC}"
}

# ===== VALIDATION HELPERS =====

# Validate domain format
ui_validate_domain() {
    local domain="$1"
    local domain_regex="^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    
    if [[ "$domain" =~ $domain_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Validate email format
ui_validate_email() {
    local email="$1"
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    if [[ "$email" =~ $email_regex ]]; then
        return 0
    else
        return 1
    fi
}

# Validate port number
ui_validate_port() {
    local port="$1"
    
    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

# ===== CLEANUP ON EXIT =====

# Cleanup function
ui_cleanup() {
    ui_stop_spinner
    tput cnorm
}

# Set trap for cleanup
trap ui_cleanup EXIT

# Export functions
export -f ui_start_spinner ui_stop_spinner ui_prompt ui_confirm ui_select ui_status ui_run_command
export -f ui_header ui_section ui_info_box ui_warning_box
export -f ui_validate_domain ui_validate_email ui_validate_port