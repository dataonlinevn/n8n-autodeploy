#!/bin/bash

# DataOnline N8N Manager - Upgrade Plugin
# Phiên bản: 1.1.0
# Tự động nâng cấp N8N lên phiên bản mới nhất

set -euo pipefail

# Source core modules
UPGRADE_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$UPGRADE_PLUGIN_DIR")")")"

[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
[[ -z "${SPINNER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"

# Load backup plugin chính để tích hợp backup system
[[ -z "${BACKUP_MAIN_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/plugins/backup/main.sh"

# Load upgrade modules
source "$UPGRADE_PLUGIN_DIR/version-manager.sh"
source "$UPGRADE_PLUGIN_DIR/backup-manager.sh"

# Constants
if [[ -z "${UPGRADE_LOADED:-}" ]]; then
    readonly UPGRADE_LOADED=true
    [[ -z "${N8N_COMPOSE_DIR:-}" ]] && readonly N8N_COMPOSE_DIR="/opt/n8n"
    [[ -z "${BACKUP_BASE_DIR:-}" ]] && readonly BACKUP_BASE_DIR="/opt/n8n/backups"
fi

# Global variables
CURRENT_VERSION=""
TARGET_VERSION=""
BACKUP_ID=""

# ===== MAIN UPGRADE ORCHESTRATOR =====

upgrade_n8n_main() {
    ui_header "Nang cap N8N"

    if ! check_upgrade_prerequisites; then
        return 1
    fi

    if ! select_upgrade_version; then
        return 0
    fi

    if ! create_upgrade_backup; then
        ui_error "Khong the sao luu du lieu. Dung nang cap."
        return 1
    fi

    if ! execute_upgrade; then
        ui_error "Nang cap that bai. Dang khoi phuc..."
        rollback_upgrade "$UPGRADE_BACKUP_FILE"
        return 1
    fi

    if ! verify_upgrade; then
        ui_error "He thong gap loi. Dang khoi phuc..."
        rollback_upgrade "$UPGRADE_BACKUP_FILE"
        return 1
    fi

    ui_success "Nang cap thanh cong!"
    show_upgrade_summary
    return 0
}

# ===== PRE-UPGRADE CHECKS =====

check_upgrade_prerequisites() {
    ui_section "Kiem tra he thong"

    local errors=0

    # Check N8N installation
    if ! is_n8n_installed; then
        ui_error "N8N chua duoc cai dat"
        ((errors++))
    else
        ui_success "N8N da cai dat"
    fi

    # Check Docker
    if ! command_exists docker; then
        ui_error "Khong tim thay Docker"
        ((errors++))
    else
        ui_success "Docker san sang"
    fi

    # Check docker-compose file
    if [[ ! -f "$N8N_COMPOSE_DIR/docker-compose.yml" ]]; then
        ui_error "Thieu file cau hinh"
        ((errors++))
    fi

    # Check disk space (minimum 2GB)
    local free_space_gb=$(df -BG "$N8N_COMPOSE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$free_space_gb" -lt 2 ]]; then
        ui_error "Dung luong khong du (can 2GB)"
        ((errors++))
    else
        ui_success "Dung luong: ${free_space_gb}GB"
    fi

    # Check current version
    CURRENT_VERSION=$(get_current_n8n_version)
    if [[ "$CURRENT_VERSION" == "unknown" ]]; then
        ui_error "Khong xac dinh duoc phien ban"
        ((errors++))
    fi

    # Check internet connection
    if ! check_internet_connection; then
        ui_error "Khong co ket noi mang"
        ((errors++))
    else
        ui_success "Ket noi mang OK"
    fi

    if [[ $errors -eq 0 ]]; then
        echo ""
        ui_info "Phien ban hien tai: v$CURRENT_VERSION"
    fi

    return $errors
}

is_n8n_installed() {
    if command_exists docker && docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
        return 0
    elif systemctl is-active --quiet n8n 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ===== VERSION SELECTION =====

select_upgrade_version() {
    ui_section "Chon phien ban"

    ui_start_spinner "Dang lay danh sach phien ban..."
    local versions=($(get_available_versions 5))
    ui_stop_spinner

    if [[ ${#versions[@]} -eq 0 ]]; then
        ui_error "Khong the lay danh sach phien ban"
        return 1
    fi

    echo ""
    echo "Phien ban hien tai: v$CURRENT_VERSION"
    echo ""
    echo "Cac phien ban co san:"
    for i in "${!versions[@]}"; do
        local version="${versions[$i]}"
        local status=""

        if [[ "$version" == "$CURRENT_VERSION" ]]; then
            status=" (hien tai)"
        fi

        echo "  $((i + 1))) v$version$status"
    done
    echo ""
    echo "  $((${#versions[@]} + 1))) Nhap phien ban khac"
    echo "  $((${#versions[@]} + 2))) Khoi phuc tu ban sao luu"
    echo "  0) Quay lai"
    echo ""

    while true; do
        echo -n "Lua chon cua ban: "
        read -r choice

        if [[ "$choice" == "0" ]]; then
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
            echo "Lua chon khong hop le"
        fi
    done

    # Confirm upgrade
    if ! confirm_upgrade; then
        return 1
    fi

    return 0
}

select_specific_version() {
    echo -n "Nhap phien ban (vi du: 1.45.0): "
    read -r version_input

    if [[ -z "$version_input" ]]; then
        echo "Phien ban khong duoc de trong"
        return 1
    fi

    TARGET_VERSION="$version_input"
    echo "Da chon: v$TARGET_VERSION"
}

confirm_upgrade() {
    echo ""
    echo "=========================================="
    echo "XAC NHAN NANG CAP"
    echo "=========================================="
    echo "  Tu phien ban: v$CURRENT_VERSION"
    echo "  Len phien ban: v$TARGET_VERSION"
    echo ""
    echo "  Ung dung se tam dung trong qua trinh nang cap."
    echo "=========================================="
    echo ""

    if ! ui_confirm "Ban chac chan muon nang cap?"; then
        ui_info "Da huy"
        return 1
    fi
    
    return 0
}

# ===== UPGRADE EXECUTION =====

execute_upgrade() {
    ui_section "Thuc hien nang cap"

    local compose_file="$N8N_COMPOSE_DIR/docker-compose.yml"

    # Step 1: Update N8N image version
    ui_info "Buoc 1/4: Cap nhat cau hinh..."
    cd "$N8N_COMPOSE_DIR"
    sed -i "s|n8nio/n8n:.*|n8nio/n8n:$TARGET_VERSION|g" docker-compose.yml

    # Step 2: Pull new image
    ui_info "Buoc 2/4: Tai phien ban moi..."
    if ! docker compose pull n8n >/dev/null 2>&1; then
        ui_error "Khong the tai phien ban moi"
        return 1
    fi

    # Step 3: Stop N8N gracefully
    ui_info "Buoc 3/4: Dung ung dung..."
    docker compose stop n8n >/dev/null 2>&1

    # Step 4: Start with new version
    ui_info "Buoc 4/4: Khoi dong phien ban moi..."
    if ! docker compose up -d n8n >/dev/null 2>&1; then
        ui_error "Khong the khoi dong"
        return 1
    fi

    # Wait for startup
    ui_start_spinner "Dang khoi dong lai..."
    local max_wait=60
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
    ui_error "Ung dung khong phan hoi"
    return 1
}

# ===== VERIFICATION =====

verify_upgrade() {
    ui_section "Kiem tra ket qua"

    local errors=0

    # Check container is running
    if docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
        ui_success "N8N dang chay"
    else
        ui_error "N8N khong chay"
        ((errors++))
    fi

    # Check API health
    local n8n_port=$(config_get "n8n.port" "5678")
    if curl -s "http://localhost:$n8n_port/healthz" >/dev/null 2>&1; then
        ui_success "Ung dung phan hoi tot"
    else
        ui_error "Ung dung khong phan hoi"
        ((errors++))
    fi

    # Check database connection
    if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_success "Co so du lieu OK"
    else
        ui_error "Loi co so du lieu"
        ((errors++))
    fi

    # Verify new version
    local new_version=$(get_current_n8n_version)
    if [[ "$new_version" != "$CURRENT_VERSION" ]]; then
        ui_success "Phien ban moi: v$new_version"
    else
        ui_warning "Phien ban chua thay doi"
    fi

    return $errors
}

# ===== UPGRADE SUMMARY =====

show_upgrade_summary() {
    local new_version=$(get_current_n8n_version)
    local n8n_domain=$(config_get "n8n.domain" "")
    local n8n_port=$(config_get "n8n.port" "5678")
    
    local access_url=""
    if [[ -n "$n8n_domain" ]]; then
        access_url="https://$n8n_domain"
    else
        access_url="http://localhost:$n8n_port"
    fi

    echo ""
    echo "=========================================="
    echo "NANG CAP HOAN TAT"
    echo "=========================================="
    echo "  Phien ban cu:  v$CURRENT_VERSION"
    echo "  Phien ban moi: v$new_version"
    echo "  Dia chi: $access_url"
    echo ""
    echo "  Ban sao luu da duoc tao tu dong."
    echo "  Su dung menu 'Sao luu' de quan ly."
    echo "=========================================="
}

# Export main function
export -f upgrade_n8n_main
