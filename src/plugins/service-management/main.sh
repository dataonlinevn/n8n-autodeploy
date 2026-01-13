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
source "$PLUGIN_DIR/redis-service.sh"
source "$PLUGIN_DIR/nocodb-service.sh"

[[ -z "${SERVICE_LOADED:-}" ]] && readonly SERVICE_LOADED=true

# ===== MAIN SERVICE MENU =====

service_management_main() {
    ui_header "Quan ly Dich vu"

    while true; do
        show_service_status
        show_service_menu

        echo -n "Lua chon cua ban: "
        read -r choice

        case "$choice" in
        1) control_n8n_service ;;
        2) control_nginx_service ;;
        3) control_database_service ;;
        4) control_redis_service ;;
        5) control_nocodb_service ;;
        6) show_detailed_status ;;
        7) manage_auto_start ;;
        8) restart_all_services ;;
        9) check_service_logs ;;
        0) return 0 ;;
        *) echo "Lua chon khong hop le" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
        ui_header "Quản lý Dịch vụ Hệ thống"
    done
}

show_service_status() {
    ui_section "Trang thai Dich vu"

    local n8n_status=$(get_n8n_status)
    local nginx_status=$(get_nginx_status)
    local db_status=$(get_database_status)
    local redis_status=$(get_redis_status)
    
    # NocoDB - chi hien thi neu da cai dat
    local nocodb_status=""
    if is_nocodb_installed 2>/dev/null; then
        nocodb_status=$(get_nocodb_service_status)
    fi

    echo "  N8N:        $n8n_status"
    echo "  Nginx:      $nginx_status"
    echo "  PostgreSQL: $db_status"
    echo "  Redis:      $redis_status"
    if [[ -n "$nocodb_status" ]]; then
        echo "  NocoDB:     $nocodb_status"
    fi
    echo ""
}

show_service_menu() {
    echo "QUAN LY RIENG BIET"
    echo "  1) N8N (Ung dung chinh)"
    echo "  2) Nginx (Web server)"
    echo "  3) PostgreSQL (Co so du lieu)"
    echo "  4) Redis (Cache)"
    if is_nocodb_installed 2>/dev/null; then
        echo "  5) NocoDB (Database UI)"
    else
        echo "  5) NocoDB (Chua cai dat)"
    fi
    echo ""
    echo "CONG CU HE THONG"
    echo "  6) Xem chi tiet trang thai"
    echo "  7) Tu dong khoi dong"
    echo "  8) Khoi dong lai tat ca"
    echo "  9) Xem nhat ky (Logs)"
    echo ""
    echo "  0) Quay lai"
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
    ui_section "Quan ly Co so du lieu (PostgreSQL)"

    local current_status=$(get_database_status)
    echo "Trang thai hien tai: $current_status"
    echo ""

    echo "1) Khoi dong (Start)"
    echo "2) Dung (Stop)"
    echo "3) Khoi dong lai (Restart)"
    echo "4) Kiem tra ket noi"
    echo "5) Xem trang thai chi tiet"
    echo "0) Quay lai"
    echo ""

    choice=$(ui_prompt "Chon chuc nang" "0" "^[0-5]$")

    case "$choice" in
    1) start_database_service ;;
    2) stop_database_service ;;
    3) restart_database_service ;;
    4) test_database_connection ;;
    5) show_database_detailed_status ;;
    0) return ;;
    *) ui_error "Lua chon khong hop le" ;;
    esac
}

# ===== REDIS SERVICE CONTROL =====

control_redis_service() {
    ui_section "Quan ly Redis"

    local current_status=$(get_redis_status)
    echo "Trang thai hien tai: $current_status"
    echo ""

    echo "1) Khoi dong Redis"
    echo "2) Dung Redis"
    echo "3) Khoi dong lai"
    echo "4) Xoa Cache (Flush)"
    echo "5) Trang thai chi tiet"
    echo "6) Thong tin ket noi"
    echo "0) Quay lai"
    echo ""

    choice=$(ui_prompt "Chon chuc nang" "0" "^[0-6]$")

    case "$choice" in
    1) start_redis_service ;;
    2) stop_redis_service ;;
    3) restart_redis_service ;;
    4) flush_redis_cache ;;
    5) show_redis_detailed_status ;;
    6) show_redis_connection_info ;;
    0) return ;;
    *) ui_error "Lua chon khong hop le" ;;
    esac
}

# ===== NOCODB SERVICE CONTROL =====

control_nocodb_service() {
    if ! is_nocodb_installed 2>/dev/null; then
        ui_error "NocoDB chua duoc cai dat. Vui long cai dat tu menu chinh."
        return 1
    fi

    ui_section "Quan ly NocoDB"

    local current_status=$(get_nocodb_service_status)
    echo "Trang thai hien tai: $current_status"
    echo ""

    echo "1) Khoi dong NocoDB"
    echo "2) Dung NocoDB"
    echo "3) Khoi dong lai"
    echo "4) Trang thai chi tiet"
    echo "5) Thong tin ket noi"
    echo "0) Quay lai"
    echo ""

    choice=$(ui_prompt "Chon chuc nang" "0" "^[0-5]$")

    case "$choice" in
    1) start_nocodb_service ;;
    2) stop_nocodb_service ;;
    3) restart_nocodb_service ;;
    4) show_nocodb_detailed_status ;;
    5) show_nocodb_connection_info ;;
    0) return ;;
    *) ui_error "Lua chon khong hop le" ;;
    esac
}

# ===== DETAILED STATUS =====

show_detailed_status() {
    ui_header "Chi tiet He thong"

    ui_section "Ung dung n8n"
    show_n8n_detailed_status
    echo ""

    ui_section "Cong Nginx"
    show_nginx_detailed_status
    echo ""

    ui_section "Co so du lieu (PostgreSQL)"
    show_database_detailed_status
    echo ""

    ui_section "Redis (Cache)"
    show_redis_detailed_status
    echo ""

    if is_nocodb_installed 2>/dev/null; then
        ui_section "NocoDB"
        show_nocodb_detailed_status
        echo ""
    fi

    ui_section "Tai nguyen May chu"
    echo "CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')% dang su dung"
    echo "RAM: $(free -h | awk '/^Mem:/ {print $3"/"$2}')"
    echo "Dia cung: $(df -h / | awk 'NR==2 {print $3"/"$2" (Da dung "$5")"}')"
}

# ===== AUTO-START MANAGEMENT =====

manage_auto_start() {
    ui_section "Cau hinh Tu dong khoi dong"

    local n8n_enabled=$(is_n8n_autostart_enabled && echo "[OK] Bat" || echo "[STOP] Tat")
    local nginx_enabled=$(is_nginx_autostart_enabled && echo "[OK] Bat" || echo "[STOP] Tat")
    local db_enabled=$(is_database_autostart_enabled && echo "[OK] Bat" || echo "[STOP] Tat")
    local redis_enabled=$(is_redis_autostart_enabled && echo "[OK] Bat" || echo "[STOP] Tat")
    
    local nocodb_enabled="N/A"
    if is_nocodb_installed 2>/dev/null; then
        nocodb_enabled=$(is_nocodb_autostart_enabled && echo "[OK] Bat" || echo "[STOP] Tat")
    fi

    echo "CAI DAT HIEN TAI:"
    echo "  n8n:      $n8n_enabled"
    echo "  Nginx:    $nginx_enabled"
    echo "  Database: $db_enabled"
    echo "  Redis:    $redis_enabled"
    if [[ "$nocodb_enabled" != "N/A" ]]; then
        echo "  NocoDB:   $nocodb_enabled"
    fi
    echo ""

    echo "1) Bat/Tat tu dong n8n"
    echo "2) Bat/Tat tu dong Nginx"
    echo "3) Bat/Tat tu dong Database"
    echo "4) Bat/Tat tu dong Redis"
    if [[ "$nocodb_enabled" != "N/A" ]]; then
        echo "5) Bat/Tat tu dong NocoDB"
    fi
    echo "8) Kich hoat cho tat ca"
    echo "9) Huy bo cho tat ca"
    echo "0) Quay lai"
    echo ""

    choice=$(ui_prompt "Chon [0-9]" "0" "^[0-9]$")

    case "$choice" in
    1) toggle_n8n_autostart ;;
    2) toggle_nginx_autostart ;;
    3) toggle_database_autostart ;;
    4) toggle_redis_autostart ;;
    5) [[ "$nocodb_enabled" != "N/A" ]] && toggle_nocodb_autostart ;;
    8) 
        enable_all_autostart || true
        docker update --restart=unless-stopped n8n-redis >/dev/null 2>&1
        if is_nocodb_installed 2>/dev/null; then
            docker update --restart=unless-stopped n8n-nocodb >/dev/null 2>&1
        fi
        ui_success "Da bat auto-start cho tat ca"
        ;;
    9)
        disable_all_autostart || true
        docker update --restart=no n8n-redis >/dev/null 2>&1
        if is_nocodb_installed 2>/dev/null; then
            docker update --restart=no n8n-nocodb >/dev/null 2>&1
        fi
        ui_success "Da tat auto-start cho tat ca"
        ;;
    0) return ;;
    *) ui_error "Lua chon khong hop le" ;;
    esac
}

# ===== RESTART ALL SERVICES =====

restart_all_services() {
    ui_header "Khoi dong lai toan bo"

    ui_warning_box "XAC NHAN KHOI DONG LAI" \
        "He thong se dung va bat lai tat ca cac thanh phan." \
        "Dieu nay co the gay gian doan cac workflow dang chay."

    if ! ui_confirm "Ban chac chan muon tiep tuc?"; then
        return
    fi

    ui_info "Dang dung cac dich vu..."
    stop_n8n_service
    cd "$N8N_COMPOSE_DIR" && docker compose stop nocodb redis 2>/dev/null || true
    sleep 1

    ui_info "Dang khoi dong lai dich vu nen..."
    start_database_service
    cd "$N8N_COMPOSE_DIR" && docker compose up -d redis 2>/dev/null || true
    if is_nocodb_installed 2>/dev/null; then
        cd "$N8N_COMPOSE_DIR" && docker compose up -d nocodb 2>/dev/null || true
    fi
    
    sleep 2
    ui_info "Dang khoi dong Web server va N8N..."
    start_nginx_service
    start_n8n_service

    ui_success "Toan bo dich vu da duoc khoi dong lai"
}

# ===== LOG MANAGEMENT =====

check_service_logs() {
    ui_header "Nhat ky he thong"

    echo "1) N8N"
    echo "2) Nginx"
    echo "3) PostgreSQL"
    echo "4) Redis"
    if is_nocodb_installed 2>/dev/null; then
        echo "5) NocoDB"
    fi
    echo "6) He thong chung"
    echo "0) Quay lai"
    echo ""

    choice=$(ui_prompt "Chon dich vu" "0" "^[0-6]$")

    case "$choice" in
    1) show_n8n_logs ;;
    2) show_nginx_logs ;;
    3) show_database_logs ;;
    4) show_redis_logs ;;
    5) is_nocodb_installed 2>/dev/null && show_nocodb_logs ;;
    6) show_system_logs ;;
    0) return ;;
    *) ui_error "Lua chon khong hop le" ;;
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
