#!/bin/bash

# DataOnline N8N Manager - Simplified Install Plugin
# Phiên bản: 1.0.0

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$PLUGIN_DIR")")"

if [[ -z "${LOGGER_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
fi
if [[ -z "${CONFIG_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
fi
if [[ -z "${UTILS_LOADED:-}" ]] ; then
    source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
fi
if [[ -z "${UI_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
fi
if [[ -z "${SPINNER_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"
fi

# Load sub-modules
source "$PLUGIN_DIR/install-requirements.sh"
source "$PLUGIN_DIR/install-config.sh"
source "$PLUGIN_DIR/install-compose.sh"
source "$PLUGIN_DIR/install-verify.sh"
source "$PLUGIN_DIR/install-uninstall.sh"

readonly INSTALL_DOCKER_COMPOSE_VERSION="2.24.5"
readonly REQUIRED_RAM_MB=2048
readonly REQUIRED_DISK_GB=10
readonly N8N_DEFAULT_PORT=5678
readonly POSTGRES_DEFAULT_PORT=5432

# Global variables
N8N_PORT=""
POSTGRES_PORT=""
N8N_DOMAIN=""
N8N_WEBHOOK_URL=""

# ===== MAIN INSTALLATION MENU =====

install_n8n_main() {
    ui_header "Quản lý Cài đặt N8N"

    while true; do
        show_install_menu
        
        echo -n -e "${UI_WHITE}Chọn [0-2]: ${UI_NC}"
        read -r choice

        case "$choice" in
        1) handle_n8n_installation ;;
        2) handle_n8n_uninstall ;;
        0) return 0 ;;
        *) ui_error "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

show_install_menu() {
    local n8n_status=$(check_n8n_installation_status)
    
    echo ""
    echo "📦 QUẢN LÝ CÀI ĐẶT N8N"
    echo ""
    echo "Trạng thái hiện tại: $n8n_status"
    echo ""
    echo "1) 🚀 Cài đặt N8N với Docker"
    echo "2) 🗑️  Gỡ cài đặt N8N"
    echo "0) ⬅️  Quay lại"
    echo ""
}

check_n8n_installation_status() {
    if [[ -f "/opt/n8n/docker-compose.yml" ]] && docker ps --format '{{.Names}}' | grep -q "n8n"; then
        echo -e "${UI_GREEN}✅ Đã cài đặt và đang chạy${UI_NC}"
    elif [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        echo -e "${UI_YELLOW}⚠️  Đã cài đặt nhưng không chạy${UI_NC}"
    else
        echo -e "${UI_RED}❌ Chưa cài đặt${UI_NC}"
    fi
}

# ===== INSTALLATION HANDLER =====

handle_n8n_installation() {
    ui_header "Cài đặt N8N với Docker"

    # Check for existing installation
    if [[ -d "/opt/n8n" && -f "/opt/n8n/docker-compose.yml" ]]; then
        ui_warning_box "Cảnh báo" \
            "Phát hiện N8N đã được cài đặt" \
            "Tiếp tục sẽ cài đặt lại từ đầu"

        if ! ui_confirm "Tiếp tục cài đặt lại?"; then
            return 0
        fi
        
        # Backup existing installation
        backup_existing_installation
    fi

    # Step 1: System requirements
    ui_info "🔍 Bước 1/5: Kiểm tra yêu cầu hệ thống"
    if ! check_n8n_requirements; then
        ui_error "Hệ thống không đáp ứng yêu cầu" "REQUIREMENTS_FAILED"
        return 1
    fi

    if ! ui_confirm "Tiếp tục cài đặt?"; then
        return 0
    fi

    # Step 2: Configuration
    ui_info "⚙️  Bước 2/5: Thu thập cấu hình"
    if ! collect_installation_configuration; then
        return 1
    fi

    # Step 3: Generate compose
    ui_info "🧩 Bước 3/5: Tạo Docker Compose"
    create_docker_compose || return 1

    # Step 4: Start stack
    ui_info "▶️  Bước 4/5: Khởi động N8N"
    start_n8n_docker || return 1

    # Step 5: Verify
    ui_info "✅ Bước 5/5: Xác minh cài đặt"
    if verify_installation; then
        ui_success "🎉 Cài đặt N8N thành công!"
        config_set "n8n.installed" "true"
        config_set "n8n.installed_date" "$(date +%Y-%m-%d)"
        return 0
    else
        ui_error "Cài đặt thất bại" "INSTALL_FAILED" "Kiểm tra logs và thử lại"
        return 1
    fi
}

# Export entry
export -f install_n8n_main