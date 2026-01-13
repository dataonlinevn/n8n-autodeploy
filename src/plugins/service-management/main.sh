#!/bin/bash

# DataOnline N8N Manager - Service Management Plugin
# Phiên bản: 1.0.0
# Quản lý các dịch vụ N8N, Nginx, Database

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$PLUGIN_DIR")")")"

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
    ui_header "Quản lý Dịch vụ Hệ thống"

    while true; do
        show_service_status
        show_service_menu

        choice=$(ui_prompt "Chọn chức năng" "0" "^[0-8]$")

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
        *) ui_error "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
        ui_header "Quản lý Dịch vụ Hệ thống"
    done
}

show_service_status() {
    ui_section "Trạng thái Dịch vụ"

    local n8n_status=$(get_n8n_status)
    local nginx_status=$(get_nginx_status)
    local db_status=$(get_database_status)

    ui_table "Dịch vụ Hệ thống|Trạng thái hiện tại" \
        "Ứng dụng n8n|$n8n_status" \
        "Cổng Nginx|$nginx_status" \
        "Cơ sở dữ liệu|$db_status"
}

show_service_menu() {
    echo "QUẢN LÝ RIÊNG BIỆT"
    echo "  1) Quản lý ứng dụng n8n"
    echo "  2) Quản lý cổng Nginx"
    echo "  3) Quản lý Cơ sở dữ liệu"
    echo ""
    echo "CÔNG CỤ HỆ THỐNG"
    echo "  4) Xem chi tiết trạng thái"
    echo "  5) Cài đặt Tự động khởi động"
    echo "  6) Khởi động lại toàn bộ dịch vụ"
    echo "  7) Kiểm tra nhật ký (Logs)"
    echo ""
    echo "  0) Quay lại"
    echo ""
}

# ===== N8N SERVICE CONTROL =====

control_n8n_service() {
    ui_section "Quản lý N8N Service"

    local current_status=$(get_n8n_status)
    echo "Trạng thái hiện tại: $current_status"
    echo ""

    echo "1) Khởi động n8n"
    echo "2) Dừng n8n"
    echo "3) Khởi động lại"
    echo "4) Trạng thái chi tiết"
    echo "0) Quay lại"
    echo ""

    choice=$(ui_prompt "Chọn chức năng" "0" "^[0-4]$")

    case "$choice" in
    1) start_n8n_service ;;
    2) stop_n8n_service ;;
    3) restart_n8n_service ;;
    4) show_n8n_detailed_status ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== NGINX SERVICE CONTROL =====

control_nginx_service() {
    ui_section "Quản lý Nginx Service"

    echo "1) Khởi động Nginx"
    echo "2) Dừng Nginx"
    echo "3) Khởi động lại"
    echo "4) Đọc lại cấu hình (Reload)"
    echo "5) Kiểm tra file cấu hình"
    echo "6) Trạng thái chi tiết"
    echo "0) Quay lại"
    echo ""

    choice=$(ui_prompt "Chọn chức năng" "0" "^[0-6]$")

    case "$choice" in
    1) start_nginx_service ;;
    2) stop_nginx_service ;;
    3) restart_nginx_service ;;
    4) reload_nginx_config ;;
    5) test_nginx_config ;;
    6) show_nginx_detailed_status ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== DATABASE SERVICE CONTROL =====

control_database_service() {
    ui_section "Quản lý Cơ sở dữ liệu"

    echo "1) Khởi động (Start)"
    echo "2) Dừng (Stop)"
    echo "3) Khởi động lại (Restart)"
    echo "4) Kiểm tra kết nối"
    echo "5) Xem trạng thái chi tiết"
    echo "0) Quay lại"
    echo ""

    choice=$(ui_prompt "Chọn chức năng" "0" "^[0-5]$")

    case "$choice" in
    1) start_database_service ;;
    2) stop_database_service ;;
    3) restart_database_service ;;
    4) test_database_connection ;;
    5) show_database_detailed_status ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== DETAILED STATUS =====

show_detailed_status() {
    ui_header "Chi tiết Hệ thống"

    # N8N Status
    ui_section "Ứng dụng n8n"
    show_n8n_detailed_status
    echo ""

    ui_section "Cổng Nginx"
    show_nginx_detailed_status
    echo ""

    ui_section "Cơ sở dữ liệu"
    show_database_detailed_status
    echo ""

    ui_section "Tài nguyên Máy chủ"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')% đang sử dụng"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo "Đĩa cứng: $(df -h / | awk 'NR==2 {print $3"/"$2" (Đã dùng "$5")"}')"
}

# ===== AUTO-START MANAGEMENT =====

manage_auto_start() {
    ui_section "Cấu hình Auto-start"

    local n8n_enabled=$(is_n8n_autostart_enabled && echo "[OK] Đã bật" || echo "[FAIL] Đang tắt")
    local nginx_enabled=$(is_nginx_autostart_enabled && echo "[OK] Đã bật" || echo "[FAIL] Đang tắt")
    local db_enabled=$(is_database_autostart_enabled && echo "[OK] Đã bật" || echo "[FAIL] Đang tắt")

    echo "CÀI ĐẶT HIỆN TẠI:"
    echo "  n8n:      $n8n_enabled"
    echo "  Nginx:    $nginx_enabled"
    echo "  Database: $db_enabled"
    echo ""

    echo "1) Bật/Tắt tự động khởi động n8n"
    echo "2) Bật/Tắt tự động khởi động Nginx"
    echo "3) Bật/Tắt tự động khởi động Cơ sở dữ liệu"
    echo "4) Kích hoạt cho tất cả"
    echo "5) Hủy bỏ cho tất cả"
    echo "0) Quay lại"
    echo ""

    choice=$(ui_prompt "Chọn [0-5]" "0" "^[0-5]$")

    case "$choice" in
    1) toggle_n8n_autostart ;;
    2) toggle_nginx_autostart ;;
    3) toggle_database_autostart ;;
    4) enable_all_autostart ;;
    5) disable_all_autostart ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== RESTART ALL SERVICES =====

restart_all_services() {
    ui_header "Khởi động lại toàn bộ"

    ui_warning_box "XÁC NHẬN KHỞI ĐỘNG LẠI" \
        "Hệ thống sẽ dừng và bật lại tất cả các thành phần." \
        "Tiến trình này có thể gây gián đoạn các kịch bản đang chạy."

    if ! ui_confirm "Bạn có chắc chắn muốn tiếp tục?"; then
        return
    fi

    # Stop services in reverse order
    ui_info "Đang dừng các dịch vụ..."
    stop_n8n_service
    sleep 1

    # Start services in correct order
    ui_info "Đang khởi động lại hệ thống..."
    start_database_service
    sleep 2
    start_nginx_service
    sleep 1
    start_n8n_service

    ui_success "Toàn bộ dịch vụ đã được khởi động lại thành công"
}

# ===== LOG MANAGEMENT =====

check_service_logs() {
    ui_header "Nhật ký hệ thống"

    echo "1) Nhật ký n8n"
    echo "2) Nhật ký Nginx"
    echo "3) Nhật ký Cơ sở dữ liệu"
    echo "4) Nhật ký Hệ thống chung"
    echo "0) Quay lại"
    echo ""

    choice=$(ui_prompt "Chọn dịch vụ" "0" "^[0-4]$")

    case "$choice" in
    1) show_n8n_logs ;;
    2) show_nginx_logs ;;
    3) show_database_logs ;;
    4) show_system_logs ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

# ===== DEPENDENCY MANAGEMENT =====

configure_service_dependencies() {
    ui_section "Cấu hình Service Dependencies"

    echo " Thứ tự khởi động hiện tại:"
    echo "  1. Database (PostgreSQL)"
    echo "  2. Nginx"
    echo "  3. N8N"
    echo ""

    echo "1)  Kiểm tra Dependencies"
    echo "2)  Sửa Dependencies"
    echo "3) [OK] Test Boot Sequence"
    echo "0)   Quay lại"
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
