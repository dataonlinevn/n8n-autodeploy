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
readonly UI_BOLD='\033[1m'
readonly UI_DIM='\033[2m'
readonly UI_ITALIC='\033[3m'
readonly UI_UNDERLINE='\033[4m'

# Unicode characters for enhanced UI
# Unicode characters - Disabled for clean look
readonly UI_CHECK="[OK]"
readonly UI_CROSS="[FAIL]"
readonly UI_WARNING="[WARN]"
readonly UI_INFO="[INFO]"
readonly UI_ROCKET=""
readonly UI_GEAR=""
readonly UI_CLOUD=""
readonly UI_LOCK=""

# Global spinner PID
UI_SPINNER_PID=0

# ===== SPINNER SYSTEM =====

# Advanced spinner with Unicode characters
_ui_spinner() {
    local message="$1"
    local spin_chars=('|' '/' '-' '\')
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
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    
    echo -e "\r${UI_CYAN}[$bar] ${percentage}% ${message}${UI_NC}"
}

# Multi-step progress tracker
# Usage: 
#   ui_progress_start "title" total_steps
#   ui_progress_update step_number "step_name" "status"
#   ui_progress_end
UI_PROGRESS_TOTAL=0
UI_PROGRESS_TITLE=""
declare -a UI_PROGRESS_STEPS=()
declare -a UI_PROGRESS_STATUS=()

ui_progress_start() {
    local title="$1"
    
    UI_PROGRESS_TITLE="$title"
    UI_PROGRESS_TOTAL="$2"
    UI_PROGRESS_STEPS=()
    UI_PROGRESS_STATUS=()
    
    echo ""
    echo -e "${UI_BOLD}${UI_CYAN}$title${UI_NC}"
    echo -e "${UI_CYAN}$(printf '─%.0s' $(seq 1 40))${UI_NC}"
}

ui_progress_update() {
    local step="$1"
    local step_name="$2"
    local status="${3:-pending}"  # pending, running, success, error
    
    UI_PROGRESS_STEPS[$step]="$step_name"
    UI_PROGRESS_STATUS[$step]="$status"
    
    local percentage=$((step * 100 / UI_PROGRESS_TOTAL))
    local bar_width=30
    local filled=$((step * bar_width / UI_PROGRESS_TOTAL))
    local empty=$((bar_width - filled))
    
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    
    # Clear previous progress line
    echo -ne "\r\033[K"
    
    # Show progress bar
    echo -e "${UI_CYAN}[${bar}] ${percentage}% (${step}/${UI_PROGRESS_TOTAL})${UI_NC}"
    
    # Show step status
    local icon="-"
    local color="$UI_GRAY"
    case "$status" in
        "success")
            icon="+"
            color="$UI_GREEN"
            ;;
        "error")
            icon="!"
            color="$UI_RED"
            ;;
        "running")
            icon=">"
            color="$UI_CYAN"
            ;;
    esac
    
    echo -e "${color}${icon} Step ${step}: $step_name${UI_NC}"
}

ui_progress_end() {
    echo -e "${UI_CYAN}$(printf '─%.0s' $(seq 1 40))${UI_NC}"
    echo ""
    
    # Reset
    UI_PROGRESS_TOTAL=0
    UI_PROGRESS_TITLE=""
    UI_PROGRESS_STEPS=()
    UI_PROGRESS_STATUS=()
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
        # Echo prompt text to stderr để không bị capture vào output
        echo -n -e "${UI_WHITE}$prompt_text${display_default}: ${UI_NC}" >&2
        read -r user_input
        
        # Use default if empty
        if [[ -z "$user_input" && -n "$default_value" ]]; then
            user_input="$default_value"
        fi
        
        # Check if empty is allowed
        if [[ -z "$user_input" && "$allow_empty" == "false" ]]; then
            echo -e "${UI_RED}${UI_CROSS} Giá trị không được để trống${UI_NC}" >&2
            continue
        fi
        
        # Validate input
        if [[ "$user_input" =~ $validation_pattern ]]; then
            # Chỉ echo user_input ra stdout (để capture)
            echo "$user_input"
            return 0
        else
            echo -e "${UI_RED}${UI_CROSS} $error_message${UI_NC}" >&2
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

# ===== UNIFIED UI SYSTEM =====
# Unified UI functions that replace both ui_status() and log_* functions
# These functions automatically log to file if logger is available

ui_info() {
    local message="$1"
    local silent="${2:-false}"
    
    echo -e "${UI_BLUE}${UI_INFO} $message${UI_NC}"
    
    # Log to file only if logger available
    if [[ "${LOGGER_LOADED:-}" == "true" ]] && [[ "$silent" != "true" ]]; then
        write_log "INFO" "$message" 2>/dev/null || true
    fi
}

ui_success() {
    local message="$1"
    local silent="${2:-false}"
    
    echo -e "${UI_GREEN}${UI_CHECK} $message${UI_NC}"
    
    # Log to file only if logger available
    if [[ "${LOGGER_LOADED:-}" == "true" ]] && [[ "$silent" != "true" ]]; then
        write_log "SUCCESS" "$message" 2>/dev/null || true
    fi
}

ui_error() {
    local message="$1"
    local error_code="${2:-}"
    local suggestions="${3:-}"
    local silent="${4:-false}"
    
    echo -e "${UI_RED}${UI_CROSS} $message${UI_NC}" >&2
    
    # Log to file only if logger available
    if [[ "${LOGGER_LOADED:-}" == "true" ]] && [[ "$silent" != "true" ]]; then
        write_log "ERROR" "$message" 2>/dev/null || true
    fi
    
    [[ -n "$suggestions" ]] && echo -e "  Gợi ý: $suggestions" >&2
}

ui_warning() {
    local message="$1"
    local silent="${2:-false}"
    
    echo -e "${UI_YELLOW}${UI_WARNING} $message${UI_NC}" >&2
    
    # Log to file only if logger available
    if [[ "${LOGGER_LOADED:-}" == "true" ]] && [[ "$silent" != "true" ]]; then
        write_log "WARN" "$message" 2>/dev/null || true
    fi
}

# ===== STATUS DISPLAY (Backward Compatibility) =====

# Show status with icon (kept for backward compatibility)
ui_status() {
    local status="$1"
    local message="$2"
    
    # Map to unified functions
    case "$status" in
        "success"|"ok")
            ui_success "$message" "true"
            ;;
        "error"|"fail")
            ui_error "$message" "" "" "true"
            ;;
        "warning"|"warn")
            ui_warning "$message" "true"
            ;;
        "info")
            ui_info "$message" "true"
            ;;
        *)
            echo -e "${UI_WHITE}• $message${UI_NC}"
            ;;
    esac
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

# Display header simple
ui_header() {
    local title="$1"
    local version="${2:-""}"
    
    clear
    echo -e "${UI_BOLD}${UI_CYAN}>>> $title${UI_NC}"
    if [[ -n "$version" ]]; then
        echo -e "${UI_GRAY}    Phiên bản: $version${UI_NC}"
    fi
    echo -e "${UI_CYAN}$(printf '═%.0s' $(seq 1 60))${UI_NC}"
    echo ""
}

# Display section simple
ui_section() {
    local title="$1"
    echo ""
    echo -e "${UI_BOLD}${UI_WHITE}[ $title ]${UI_NC}"
    echo ""
}

# Display info without box
ui_info_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo -e "${UI_BOLD}${UI_BLUE}# $title${UI_NC}"
    for line in "${lines[@]}"; do
        echo -e "  $line"
    done
    echo ""
}

# Display warning without box
ui_warning_box() {
    local title="$1"
    shift
    local lines=("$@")
    
    echo -e "${UI_BOLD}${UI_YELLOW}# $title${UI_NC}"
    for line in "${lines[@]}"; do
        echo -e "  $line"
    done
    echo ""
}

# Display error without box
ui_error_box() {
    local title="$1"
    local error_code="${2:-}"
    local error_message="$3"
    shift 3
    local suggestions=("$@")
    
    echo -e "${UI_BOLD}${UI_RED}!!! $title${UI_NC}"
    echo -e "    $error_message"
    
    if [[ -n "$error_code" ]]; then
        echo -e "    ${UI_GRAY}Code: $error_code${UI_NC}"
    fi
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo -e "    ${UI_YELLOW}Gợi ý:${UI_NC}"
        for suggestion in "${suggestions[@]}"; do
            echo -e "    - $suggestion"
        done
    fi
    echo ""
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

# ===== TABLE FORMATTING =====

# Print table without ASCII borders
ui_table() {
    local headers="$1"
    shift
    local rows=("$@")
    
    IFS='|' read -ra HEADER_ARRAY <<< "$headers"
    local col_count=${#HEADER_ARRAY[@]}
    
    declare -a col_widths
    for i in "${!HEADER_ARRAY[@]}"; do
        col_widths[$i]=${#HEADER_ARRAY[$i]}
    done
    
    for row in "${rows[@]}"; do
        IFS='|' read -ra ROW_ARRAY <<< "$row"
        for i in "${!ROW_ARRAY[@]}"; do
            if [[ ${#ROW_ARRAY[$i]} -gt ${col_widths[$i]} ]]; then
                col_widths[$i]=${#ROW_ARRAY[$i]}
            fi
        done
    done
    
    # Add minimal padding
    for i in "${!col_widths[@]}"; do
        col_widths[$i]=$((col_widths[$i] + 2))
    done
    
    # Print header
    echo -e "${UI_DIM}${UI_CYAN}$(printf '%.0s─' $(seq 1 40))${UI_NC}"
    for i in "${!HEADER_ARRAY[@]}"; do
        printf "${UI_CYAN}%-${col_widths[$i]}s${UI_NC} " "${HEADER_ARRAY[$i]}"
    done
    echo ""
    echo -e "${UI_DIM}${UI_CYAN}$(printf '%.0s─' $(seq 1 40))${UI_NC}"
    
    # Print data rows
    for row in "${rows[@]}"; do
        IFS='|' read -ra ROW_ARRAY <<< "$row"
        for i in "${!ROW_ARRAY[@]}"; do
            local cell_value="${ROW_ARRAY[$i]:-}"
            printf "%-${col_widths[$i]}s " "$cell_value"
        done
        echo ""
    done
    echo -e "${UI_DIM}${UI_CYAN}$(printf '%.0s─' $(seq 1 40))${UI_NC}"
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
export -f ui_start_spinner ui_stop_spinner ui_prompt ui_confirm ui_select ui_run_command
export -f ui_info ui_success ui_error ui_warning ui_status
export -f ui_progress_start ui_progress_update ui_progress_end ui_show_progress
export -f ui_header ui_section ui_info_box ui_warning_box ui_error_box
export -f ui_validate_domain ui_validate_email ui_validate_port ui_table