#!/bin/bash

# DataOnline N8N Manager - Service Management Plugin
# Phiên bản: 1.0.0
# Quản lý các dịch vụ N8N, Nginx, Database

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$PLUGIN_DIR")")"

[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"

# Load service modules
source "$PLUGIN_DIR/n8n-service.sh"
source "$PLUGIN_DIR/nginx-service.sh"
source "$PLUGIN_DIR/database-service.sh"

readonly SERVICE_LOADED=true

# ===== MAIN SERVICE MENU =====

service_management_main() {
    ui_header "Quản lý Dịch vụ N8N"

    while true; do
        show_service_status
        show_service_menu

        echo -n -e "${UI_WHITE}Chọn [0-8]: ${UI_NC}"
        read -r choice

        case "$choice" in
        1) control_n8n_service ;;
        2) control_nginx_service ;;
        3) control_database_service ;;
        4) show_detailed_status ;;
        5) manage_auto_start ;;
        6) restart_all_services ;;
        7) check_service_logs ;;
        8) configure_service_dependencies ;;
        0) return 0 ;;
        *) ui_status "error" "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

show_service_status() {
    ui_section "Trạng thái Dịch vụ"

    local n8n_status=$(get_n8n_status)
    local nginx_status=$(get_nginx_status)
    local db_status=$(get_database_status)

    echo "┌─────────────────────────────────────────┐"
    echo "│ Dịch vụ          │ Trạng thái           │"
    echo "├─────────────────────────────────────────┤"
    printf "│ %-15s │ %-18s │\n" "N8N" "$n8n_status"
    printf "│ %-15s │ %-18s │\n" "Nginx" "$nginx_status"
    printf "│ %-15s │ %-18s │\n" "Database" "$db_status"
    echo "└─────────────────────────────────────────┘"
}

show_service_menu() {
    echo ""
    echo "1) 🚀 Quản lý N8N"
    echo "2) 🌐 Quản lý Nginx"
    echo "3) 🗄️  Quản lý Database"
    echo "4) 📊 Trạng thái chi tiết"
    echo "5) ⚙️  Cấu hình Auto-start"
    echo "6) 🔄 Restart tất cả"
    echo "7) 📝 Xem Logs"
    echo "8) 🔗 Cấu hình Dependencies"
    echo "0) ❌ Quay lại"
    echo ""
}

# ===== N8N SERVICE CONTROL =====

control_n8n_service() {
    ui_section "Quản lý N8N Service"

    local current_status=$(get_n8n_status)
    echo "Trạng thái hiện tại: $current_status"
    echo ""

    echo "1) ▶️  Start N8N"
    echo "2) ⏹️  Stop N8N"
    echo "3) 🔄 Restart N8N"
    echo "4) 📊 Status N8N"
    echo "0) ⬅️  Quay lại"
    echo ""

    echo -n -e "${UI_WHITE}Chọn [0-4]: ${UI_NC}"
    read -r choice

    case "$choice" in
    1) start_n8n_service ;;
    2) stop_n8n_service ;;
    3) restart_n8n_service ;;
    4) show_n8n_detailed_status ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== NGINX SERVICE CONTROL =====

control_nginx_service() {
    ui_section "Quản lý Nginx Service"

    echo "1) ▶️  Start Nginx"
    echo "2) ⏹️  Stop Nginx"
    echo "3) 🔄 Restart Nginx"
    echo "4) 🔧 Reload Config"
    echo "5) ✅ Test Config"
    echo "6) 📊 Status Nginx"
    echo "0) ⬅️  Quay lại"
    echo ""

    echo -n -e "${UI_WHITE}Chọn [0-6]: ${UI_NC}"
    read -r choice

    case "$choice" in
    1) start_nginx_service ;;
    2) stop_nginx_service ;;
    3) restart_nginx_service ;;
    4) reload_nginx_config ;;
    5) test_nginx_config ;;
    6) show_nginx_detailed_status ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== DATABASE SERVICE CONTROL =====

control_database_service() {
    ui_section "Quản lý Database Service"

    echo "1) ▶️  Start Database"
    echo "2) ⏹️  Stop Database"
    echo "3) 🔄 Restart Database"
    echo "4) 🔍 Test Connection"
    echo "5) 📊 Status Database"
    echo "0) ⬅️  Quay lại"
    echo ""

    echo -n -e "${UI_WHITE}Chọn [0-5]: ${UI_NC}"
    read -r choice

    case "$choice" in
    1) start_database_service ;;
    2) stop_database_service ;;
    3) restart_database_service ;;
    4) test_database_connection ;;
    5) show_database_detailed_status ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== DETAILED STATUS =====

show_detailed_status() {
    ui_section "Trạng thái Chi tiết"

    # N8N Status
    echo "═══ N8N ═══"
    show_n8n_detailed_status
    echo ""

    # Nginx Status
    echo "═══ NGINX ═══"
    show_nginx_detailed_status
    echo ""

    # Database Status
    echo "═══ DATABASE ═══"
    show_database_detailed_status
    echo ""

    # System Resources
    echo "═══ SYSTEM RESOURCES ═══"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo "Disk: $(df -h / | awk 'NR==2 {print $3"/"$2" ("$5" used)"}')"
}

# ===== AUTO-START MANAGEMENT =====

manage_auto_start() {
    ui_section "Cấu hình Auto-start"

    local n8n_enabled=$(is_n8n_autostart_enabled && echo "✅ Enabled" || echo "❌ Disabled")
    local nginx_enabled=$(is_nginx_autostart_enabled && echo "✅ Enabled" || echo "❌ Disabled")
    local db_enabled=$(is_database_autostart_enabled && echo "✅ Enabled" || echo "❌ Disabled")

    echo "Trạng thái Auto-start:"
    echo "  N8N: $n8n_enabled"
    echo "  Nginx: $nginx_enabled"
    echo "  Database: $db_enabled"
    echo ""

    echo "1) 🔧 Toggle N8N auto-start"
    echo "2) 🔧 Toggle Nginx auto-start"
    echo "3) 🔧 Toggle Database auto-start"
    echo "4) ✅ Enable tất cả"
    echo "5) ❌ Disable tất cả"
    echo "0) ⬅️  Quay lại"
    echo ""

    echo -n -e "${UI_WHITE}Chọn [0-5]: ${UI_NC}"
    read -r choice

    case "$choice" in
    1) toggle_n8n_autostart ;;
    2) toggle_nginx_autostart ;;
    3) toggle_database_autostart ;;
    4) enable_all_autostart ;;
    5) disable_all_autostart ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== RESTART ALL SERVICES =====

restart_all_services() {
    ui_section "Restart Tất cả Dịch vụ"

    ui_warning_box "Cảnh báo" \
        "Sẽ restart tất cả dịch vụ theo thứ tự an toàn" \
        "N8N sẽ tạm thời không khả dụng"

    if ! ui_confirm "Tiếp tục restart tất cả?"; then
        return
    fi

    # Stop services in reverse order
    ui_status "info" "Dừng dịch vụ..."
    stop_n8n_service
    sleep 2

    # Start services in correct order
    ui_status "info" "Khởi động dịch vụ..."
    start_database_service
    sleep 3
    start_nginx_service
    sleep 2
    start_n8n_service

    ui_status "success" "Đã restart tất cả dịch vụ"
}

# ===== LOG MANAGEMENT =====

check_service_logs() {
    ui_section "Xem Service Logs"

    echo "1) 📝 N8N Logs"
    echo "2) 📝 Nginx Logs"
    echo "3) 📝 Database Logs"
    echo "4) 📝 System Logs"
    echo "0) ⬅️  Quay lại"
    echo ""

    echo -n -e "${UI_WHITE}Chọn [0-4]: ${UI_NC}"
    read -r choice

    case "$choice" in
    1) show_n8n_logs ;;
    2) show_nginx_logs ;;
    3) show_database_logs ;;
    4) show_system_logs ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== DEPENDENCY MANAGEMENT =====

configure_service_dependencies() {
    ui_section "Cấu hình Service Dependencies"

    echo "📋 Thứ tự khởi động hiện tại:"
    echo "  1. Database (PostgreSQL)"
    echo "  2. Nginx"
    echo "  3. N8N"
    echo ""

    echo "1) 🔍 Kiểm tra Dependencies"
    echo "2) 🔧 Sửa Dependencies"
    echo "3) ✅ Test Boot Sequence"
    echo "0) ⬅️  Quay lại"
    echo ""

    echo -n -e "${UI_WHITE}Chọn [0-3]: ${UI_NC}"
    read -r choice

    case "$choice" in
    1) check_service_dependencies ;;
    2) fix_service_dependencies ;;
    3) test_boot_sequence ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

export -f service_management_main
