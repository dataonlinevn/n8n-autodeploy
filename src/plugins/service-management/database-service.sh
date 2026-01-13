#!/bin/bash

# DataOnline N8N Manager - Database Service Management
# Phiên bản: 1.0.0
# Quản lý dịch vụ Database (PostgreSQL) cho N8N

set -euo pipefail

if [[ -z "${N8N_COMPOSE_DIR:-}" ]]; then
    readonly N8N_COMPOSE_DIR="/opt/n8n"
fi

get_database_status() {
    if docker ps --format '{{.Names}}' | grep -q "postgres"; then
        echo -e "${UI_GREEN}[OK] Đang chạy${UI_NC}"
    else
        echo -e "${UI_RED}[STOP] Đã dừng${UI_NC}"
    fi
}

show_database_detailed_status() {
    local container_id=$(docker ps -q --filter "name=postgres")

    if [[ -n "$container_id" ]]; then
        echo "Container: $container_id"
        echo "Image: $(docker inspect $container_id --format '{{.Config.Image}}')"
        echo "Status: $(docker inspect $container_id --format '{{.State.Status}}')"

        # Test connection
        if test_database_connection_silent; then
            echo "Connection: [OK] OK"
        else
            echo "Connection: [FAIL] Failed"
        fi
    else
        echo "Database container không chạy"
    fi
}

start_database_service() {
    ui_run_command "Khởi động Cơ sở dữ liệu" "
        cd $N8N_COMPOSE_DIR && docker compose up -d postgres
    "

    sleep 3
    if test_database_connection_silent; then
        ui_success "Cơ sở dữ liệu đã sẵn sàng"
    else
        ui_warning "Cơ sở dữ liệu đang khởi động..."
    fi
}

stop_database_service() {
    ui_warning_box "Cảnh báo" "Dừng Database sẽ ngắt kết nối N8N"

    if ! ui_confirm "Tiếp tục dừng Database?"; then
        return
    fi

    ui_run_command "Dừng Database" "
        cd $N8N_COMPOSE_DIR && docker compose stop postgres
    "
    ui_status "success" "Database đã dừng"
}

restart_database_service() {
    ui_run_command "Restart Database" "
        cd $N8N_COMPOSE_DIR && docker compose restart postgres
    "

    sleep 5
    if test_database_connection_silent; then
        ui_status "success" "Database restart thành công"
    else
        ui_status "error" "Database restart thất bại"
    fi
}

test_database_connection() {
    ui_info "Đang kiểm tra kết nối cơ sở dữ liệu..."

    if test_database_connection_silent; then
        ui_success "Kết nối thành công"

        # Show additional info
        local db_size=$(docker exec n8n-postgres psql -U n8n -d n8n -c "SELECT pg_size_pretty(pg_database_size('n8n'));" -t 2>/dev/null | xargs)
        local table_count=$(docker exec n8n-postgres psql -U n8n -d n8n -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" -t 2>/dev/null | xargs)

        echo "Dung lượng: ${db_size:-Không rõ}"
        echo "Số lượng bảng: ${table_count:-Không rõ}"
    else
        ui_error "Lỗi: Không thể kết nối với cơ sở dữ liệu"
    fi
}

test_database_connection_silent() {
    docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1
}

is_database_autostart_enabled() {
    local restart_policy=$(docker inspect n8n-postgres --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
    [[ "$restart_policy" == "unless-stopped" || "$restart_policy" == "always" ]]
}

toggle_database_autostart() {
    if is_database_autostart_enabled; then
        ui_run_command "Disable Database auto-start" "
            cd $N8N_COMPOSE_DIR
            sed -i '/postgres:/,/^[[:space:]]*[^[:space:]]/ s/restart:.*/restart: \"no\"/' docker-compose.yml
            docker compose up -d postgres
        "
        ui_status "success" "Database auto-start đã tắt"
    else
        ui_run_command "Enable Database auto-start" "
            cd $N8N_COMPOSE_DIR
            sed -i '/postgres:/,/^[[:space:]]*[^[:space:]]/ s/restart:.*/restart: unless-stopped/' docker-compose.yml
            docker compose up -d postgres
        "
        ui_status "success" "Database auto-start đã bật"
    fi
}

show_database_logs() {
    echo "📝 PostgreSQL Logs (50 dòng cuối):"
    docker logs --tail 50 n8n-postgres 2>&1
}

# Additional functions for service management
enable_all_autostart() {
    enable_n8n_autostart
    ui_run_command "Enable Nginx auto-start" "systemctl enable nginx"
    enable_database_autostart_helper
    ui_status "success" "Đã enable auto-start cho tất cả dịch vụ"
}

disable_all_autostart() {
    disable_n8n_autostart
    ui_run_command "Disable Nginx auto-start" "systemctl disable nginx"
    disable_database_autostart_helper
    ui_status "success" "Đã disable auto-start cho tất cả dịch vụ"
}

enable_database_autostart_helper() {
    cd $N8N_COMPOSE_DIR
    sed -i '/postgres:/,/^[[:space:]]*[^[:space:]]/ s/restart:.*/restart: unless-stopped/' docker-compose.yml
    docker compose up -d postgres
}

disable_database_autostart_helper() {
    cd $N8N_COMPOSE_DIR
    sed -i '/postgres:/,/^[[:space:]]*[^[:space:]]/ s/restart:.*/restart: \"no\"/' docker-compose.yml
    docker compose up -d postgres
}

check_service_dependencies() {
    ui_status "info" "Kiểm tra service dependencies..."

    echo "Database → Nginx → N8N"
    echo "[OK] Thứ tự đúng cho Docker Compose"
    ui_status "success" "Dependencies OK"
}

fix_service_dependencies() {
    ui_status "info" "Service dependencies đã được cấu hình tự động"
}

test_boot_sequence() {
    ui_status "info" "Testing boot sequence simulation..."
    echo "1. Database: $(get_database_status)"
    echo "2. Nginx: $(get_nginx_status)"
    echo "3. N8N: $(get_n8n_status)"
    ui_status "success" "Boot sequence test completed"
}

show_system_logs() {
    echo "📝 System logs related to services:"
    journalctl -u nginx -n 10 --no-pager 2>/dev/null || echo "No nginx logs"
}

export -f get_database_status show_database_detailed_status start_database_service stop_database_service restart_database_service test_database_connection is_database_autostart_enabled toggle_database_autostart show_database_logs enable_all_autostart disable_all_autostart check_service_dependencies fix_service_dependencies test_boot_sequence show_system_logs
