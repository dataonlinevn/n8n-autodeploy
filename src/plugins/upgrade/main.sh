#!/bin/bash

# DataOnline N8N Manager - Upgrade Plugin
# Phiên bản: 1.0.0
# Tự động nâng cấp N8N lên phiên bản mới nhất

set -euo pipefail

# Source core modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$PLUGIN_DIR")")")"

[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
[[ -z "${SPINNER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"

# Load upgrade modules
source "$PLUGIN_DIR/version-manager.sh"
source "$PLUGIN_DIR/backup-manager.sh"

# Constants
if [[ -z "${UPGRADE_LOADED:-}" ]]; then
    readonly UPGRADE_LOADED=true
fi
readonly N8N_COMPOSE_DIR="/opt/n8n"
readonly BACKUP_BASE_DIR="/opt/n8n/backups/upgrades"

# Global variables
CURRENT_VERSION=""
TARGET_VERSION=""
BACKUP_ID=""

# ===== MAIN UPGRADE ORCHESTRATOR =====

upgrade_n8n_main() {
    ui_header "Nâng cấp Phiên bản n8n"

    ui_info "Đang kiểm tra các điều kiện nâng cấp..."
    if ! check_upgrade_prerequisites; then
        return 1
    fi

    if ! select_upgrade_version; then
        return 0
    fi

    if ! create_upgrade_backup; then
        ui_error "Dừng nâng cấp do không thể sao lưu dữ liệu"
        return 1
    fi

    ui_info "Đang tiến hành quá trình nâng cấp..."
    if ! execute_upgrade; then
        ui_error "Nâng cấp thất bại, đang hoàn tác (Rollback)..."
        rollback_upgrade "$BACKUP_ID"
        return 1
    fi

    if ! verify_upgrade; then
        ui_error "Hệ thống gặp lỗi sau nâng cấp, đang hoàn tác..."
        rollback_upgrade "$BACKUP_ID"
        return 1
    fi

    ui_success "Chúc mừng! Ứng dụng n8n đã được nâng cấp thành công."
    show_upgrade_summary
    return 0
}

# ===== PRE-UPGRADE CHECKS =====

check_upgrade_prerequisites() {
    ui_section "Kiểm tra hệ thống"

    local errors=0

    # Check N8N installation
    if ! is_n8n_installed; then
        ui_error "Ứng dụng n8n chưa được cài đặt"
        ((errors++))
    fi

    # Check Docker
    if ! command_exists docker; then
        ui_error "Không tìm thấy môi trường Docker"
        ((errors++))
    fi

    # Check docker-compose file
    if [[ ! -f "$N8N_COMPOSE_DIR/docker-compose.yml" ]]; then
        ui_error "Thiếu tệp tin cấu hình docker-compose.yml"
        ((errors++))
    fi

    # Check disk space (minimum 2GB)
    local free_space_gb=$(df -BG "$N8N_COMPOSE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$free_space_gb" -lt 2 ]]; then
        ui_error "Dung lượng trống không đủ (cần tối thiểu 2GB)"
        ((errors++))
    fi

    # Check current version
    CURRENT_VERSION=$(get_current_n8n_version)
    if [[ "$CURRENT_VERSION" == "unknown" ]]; then
        ui_error "Không thể xác định phiên bản hiện tại"
        ((errors++))
    fi

    # Check internet connection
    if ! check_internet_connection; then
        ui_error "Không có kết nối Internet"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        ui_info "Phiên bản hiện tại: v$CURRENT_VERSION"
        ui_info "Hệ thống đã sẵn sàng để nâng cấp."
    fi

    return $errors
}

is_n8n_installed() {
    if command_exists docker && docker ps --format '{{.Names}}' | grep -q "n8n"; then
        return 0
    elif systemctl is-active --quiet n8n 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ===== VERSION SELECTION =====

select_upgrade_version() {
    ui_section "Chọn phiên bản nâng cấp"

    # Get top 5 versions
    ui_start_spinner "Lấy 5 phiên bản mới nhất"
    local versions=($(get_available_versions 5))
    ui_stop_spinner

    if [[ ${#versions[@]} -eq 0 ]]; then
        ui_status "error" "Không thể lấy danh sách phiên bản"
        return 1
    fi

    ui_info_box "Phiên bản hiện tại" "N8N: $CURRENT_VERSION"

    echo " Chọn phiên bản để nâng cấp:"
    for i in "${!versions[@]}"; do
        local version="${versions[$i]}"
        local status=""

        if [[ "$version" == "$CURRENT_VERSION" ]]; then
            status=" ${UI_GREEN}(hiện tại)${UI_NC}"
        fi

        echo -e "$((i + 1))) 🚀 N8N v$version$status"
    done
    echo "$((${#versions[@]} + 1)))  Nhập phiên bản khác"
    echo "$((${#versions[@]} + 2))) ↩️  Rollback"
    echo "0) [FAIL] Hủy bỏ"
    echo ""

    while true; do
        echo -n -e "${UI_WHITE}Chọn [0-$((${#versions[@]} + 2))]: ${UI_NC}"
        read -r choice

        if [[ "$choice" == "0" ]]; then
            ui_status "info" "Hủy nâng cấp"
            return 1
        elif [[ "$choice" =~ ^[1-5]$ ]] && [[ "$choice" -le ${#versions[@]} ]]; then
            TARGET_VERSION="${versions[$((choice - 1))]}"
            break
        elif [[ "$choice" == "$((${#versions[@]} + 1))" ]]; then
            select_specific_version
            break
        elif [[ "$choice" == "$((${#versions[@]} + 2))" ]]; then
            show_rollback_menu
            return $?
        else
            ui_status "error" "Lựa chọn không hợp lệ"
        fi
    done

    # Confirm upgrade
    if ! confirm_upgrade; then
        return 1
    fi

    return 0
}

select_specific_version() {
    echo -n -e "${UI_WHITE}Nhập phiên bản (ví dụ: 1.45.0): ${UI_NC}"
    read -r version_input

    if [[ -z "$version_input" ]]; then
        ui_status "error" "Phiên bản không được để trống"
        return 1
    fi

    # Basic version validation
    if [[ ! "$version_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ui_status "warning" "Format phiên bản có thể không đúng"
    fi

    TARGET_VERSION="$version_input"
    ui_status "info" "Đã chọn phiên bản: $TARGET_VERSION"
}

confirm_upgrade() {
    echo ""
    ui_warning_box "XÁC NHẬN NÂNG CẤP" \
        "Từ phiên bản: $CURRENT_VERSION" \
        "Lên phiên bản: $TARGET_VERSION" \
        "Ứng dụng sẽ tự động khởi động lại trong giây lát."

    if ! ui_confirm "Bạn có chắc chắn muốn bắt đầu nâng cấp?"; then
        ui_info "Đã hủy bỏ quy trình."
        return 1
    fi
    
    ui_info "Bắt đầu nâng cấp..."
    return 0
}

# ===== UPGRADE EXECUTION =====

execute_upgrade() {
    ui_section "Thực hiện nâng cấp"

    local compose_file="$N8N_COMPOSE_DIR/docker-compose.yml"
    local backup_compose="$BACKUP_BASE_DIR/$BACKUP_ID/docker-compose.yml.backup"

    # Step 1: Update docker-compose.yml
    if ! ui_run_command "Backup docker-compose.yml" "
        cp '$compose_file' '$backup_compose'
    "; then
        return 1
    fi

    # Step 2: Update N8N image version
    if ! ui_run_command "Cập nhật image version" "
        cd '$N8N_COMPOSE_DIR'
        sed -i 's|n8nio/n8n:.*|n8nio/n8n:$TARGET_VERSION|g' docker-compose.yml
    "; then
        return 1
    fi

    # Step 3: Pull new image
    if ! ui_run_command "Tải image mới" "
        cd '$N8N_COMPOSE_DIR'
        docker compose pull n8n
    "; then
        return 1
    fi

    # Step 4: Stop N8N gracefully
    if ! ui_run_command "Dừng N8N" "
        cd '$N8N_COMPOSE_DIR'
        docker compose stop n8n
    "; then
        return 1
    fi

    # Step 5: Start with new version
    if ! ui_run_command "Cập nhật ứng dụng" "
        cd '$N8N_COMPOSE_DIR'
        docker compose up -d n8n
    "; then
        return 1
    fi

    # Step 6: Wait for startup
    ui_start_spinner "Đang khởi động lại ứng dụng n8n..."
    local max_wait=30
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$(config_get "n8n.port" "5678")/healthz" >/dev/null 2>&1; then
            ui_stop_spinner
            return 0
        fi
        sleep 2
        ((waited += 2))
    done

    ui_stop_spinner
    ui_error "Ứng dụng không phản hồi sau thời gian cài đặt"
    return 1
}

# ===== VERIFICATION =====

verify_upgrade() {
    ui_section "Xác minh nâng cấp"

    local errors=0

    # Check container is running
    if docker ps --format '{{.Names}}' | grep -q "n8n"; then
        ui_status "success" "Container N8N đang chạy"
    else
        ui_status "error" "Container N8N không chạy"
        ((errors++))
    fi

    # Check API health
    local n8n_port=$(config_get "n8n.port" "5678")
    if curl -s "http://localhost:$n8n_port/healthz" >/dev/null 2>&1; then
        ui_status "success" "N8N API phản hồi"
    else
        ui_status "error" "N8N API không phản hồi"
        ((errors++))
    fi

    # Check database connection
    if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_status "success" "Database kết nối OK"
    else
        ui_status "error" "Database lỗi kết nối"
        ((errors++))
    fi

    # Verify new version
    local new_version=$(get_current_n8n_version)
    if [[ "$new_version" != "$CURRENT_VERSION" ]]; then
        ui_status "success" "Phiên bản đã cập nhật: $new_version"
    else
        ui_status "warning" "Phiên bản chưa thay đổi"
    fi

    return $errors
}

# ===== ROLLBACK MENU =====

show_rollback_menu() {
    ui_section "Rollback N8N"

    local backups=($(ls -t "$BACKUP_BASE_DIR" 2>/dev/null | head -10))

    if [[ ${#backups[@]} -eq 0 ]]; then
        ui_status "warning" "Không có backup để rollback"
        return 1
    fi

    echo "Các backup có sẵn:"
    for i in "${!backups[@]}"; do
        local backup_info=$(get_backup_info "${backups[$i]}")
        echo "$((i + 1))) ${backups[$i]} - $backup_info"
    done
    echo ""

    echo -n -e "${UI_WHITE}Chọn backup để rollback [1-${#backups[@]}]: ${UI_NC}"
    read -r choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice - 1))]}"

        if ui_confirm "Rollback về backup $selected_backup?"; then
            rollback_upgrade "$selected_backup"
        fi
    else
        ui_status "error" "Lựa chọn không hợp lệ"
        return 1
    fi

    return 0
}

# ===== UPGRADE SUMMARY =====

show_upgrade_summary() {
    local new_version=$(get_current_n8n_version)
    local n8n_url="http://localhost:$(config_get "n8n.port" "5678")"

    ui_info_box "Tóm tắt nâng cấp" \
        "[OK] Từ: $CURRENT_VERSION" \
        "[OK] Đến: $new_version" \
        "[OK] Backup ID: $BACKUP_ID" \
        " URL: $n8n_url" \
        "📁 Backup: $BACKUP_BASE_DIR/$BACKUP_ID"

    ui_status "info" "Lưu ý: Backup sẽ tự động xóa sau 30 ngày"
}

# Export main function
export -f upgrade_n8n_main
