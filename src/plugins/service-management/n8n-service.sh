#!/bin/bash

# DataOnline N8N Manager - N8N Service Management
# Phiên bản: 1.0.0
# Quản lý dịch vụ N8N

set -euo pipefail

[[ -z "${N8N_COMPOSE_DIR:-}" ]] && readonly N8N_COMPOSE_DIR="/opt/n8n"

# ===== STATUS FUNCTIONS =====

get_n8n_status() {
    if is_docker_installation; then
        if docker ps --format '{{.Names}}' | grep -q "n8n"; then
            echo -e "${UI_GREEN}[OK] Đang chạy${UI_NC}"
        else
            echo -e "${UI_RED}[STOP] Đã dừng${UI_NC}"
        fi
    else
        if systemctl is-active --quiet n8n 2>/dev/null; then
            echo -e "${UI_GREEN}[OK] Đang chạy${UI_NC}"
        else
            echo -e "${UI_RED}[STOP] Đã dừng${UI_NC}"
        fi
    fi
}

show_n8n_detailed_status() {
    if is_docker_installation; then
        show_docker_n8n_status
    else
        show_systemd_n8n_status
    fi
}

show_docker_n8n_status() {
    local container_id=$(docker ps -q --filter "name=^n8n$" 2>/dev/null)

    if [[ -z "$container_id" ]]; then
        # Fallback: get container that matches exactly "n8n"
        container_id=$(docker ps --format "{{.ID}} {{.Names}}" | grep -E "\sn8n$" | cut -d' ' -f1)
    fi

    if [[ -n "$container_id" ]]; then
        echo "Container ID: $container_id"
        echo "Image: $(docker inspect $container_id --format '{{.Config.Image}}')"
        echo "Started: $(docker inspect $container_id --format '{{.State.StartedAt}}' | cut -d'T' -f1)"
        echo "Status: $(docker inspect $container_id --format '{{.State.Status}}')"

        # Resource usage
        local stats=$(docker stats $container_id --no-stream --format "{{.CPUPerc}} {{.MemUsage}}")
        echo "Resources:"
        echo "  CPU: $(echo $stats | cut -d' ' -f1)"
        echo "  Memory: $(echo $stats | cut -d' ' -f2-)"

        # Port mapping
        echo "Ports:"
        docker port $container_id 2>/dev/null | sed 's/^/  /' || echo "  No port mappings"
    else
        echo "N8N container không chạy"
    fi
}

show_systemd_n8n_status() {
    if systemctl is-active --quiet n8n 2>/dev/null; then
        systemctl status n8n --no-pager -l
    else
        echo "Service không chạy"
    fi
}

# ===== CONTROL FUNCTIONS =====

start_n8n_service() {
    if is_docker_installation; then
        ui_run_command "Khởi động N8N (Docker)" "
            cd $N8N_COMPOSE_DIR && docker compose up -d n8n
        "
    else
        ui_run_command "Khởi động N8N (Systemd)" "
            systemctl start n8n
        "
    fi

    # Wait and verify
    sleep 5
    if verify_n8n_health; then
        ui_status "success" "N8N đã khởi động thành công"
    else
        ui_status "warning" "N8N khởi động nhưng chưa sẵn sàng"
    fi
}

stop_n8n_service() {
    ui_warning_box "Cảnh báo" "Việc dừng N8N sẽ ngắt kết nối người dùng"

    if ! ui_confirm "Tiếp tục dừng N8N?"; then
        return
    fi

    if is_docker_installation; then
        ui_run_command "Dừng N8N (Docker)" "
            cd $N8N_COMPOSE_DIR && docker compose stop n8n
        "
    else
        ui_run_command "Dừng N8N (Systemd)" "
            systemctl stop n8n
        "
    fi

    ui_status "success" "N8N đã dừng"
}

restart_n8n_service() {
    ui_info "Đang khởi động lại ứng dụng n8n..."

    if is_docker_installation; then
        ui_run_command "Restart n8n" "
            cd $N8N_COMPOSE_DIR && docker compose restart n8n
        "
    else
        ui_run_command "Restart n8n" "
            systemctl restart n8n
        "
    fi

    # Wait and verify
    sleep 5
    if verify_n8n_health; then
        ui_success "Ứng dụng n8n đã được khởi động lại"
    else
        ui_warning "Ứng dụng n8n phản hồi chậm, vui lòng kiểm tra lại sau"
    fi
}

# ===== AUTO-START MANAGEMENT =====

is_n8n_autostart_enabled() {
    if is_docker_installation; then
        # Check restart policy
        local restart_policy=$(docker inspect n8n --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
        [[ "$restart_policy" == "unless-stopped" || "$restart_policy" == "always" ]]
    else
        systemctl is-enabled --quiet n8n 2>/dev/null
    fi
}

toggle_n8n_autostart() {
    if is_n8n_autostart_enabled; then
        disable_n8n_autostart
    else
        enable_n8n_autostart
    fi
}

enable_n8n_autostart() {
    if is_docker_installation; then
        ui_run_command "Enable N8N auto-start" "
            cd $N8N_COMPOSE_DIR
            # Update restart policy in docker-compose.yml
            sed -i 's/restart:.*/restart: unless-stopped/' docker-compose.yml
            docker compose up -d n8n
        "
    else
        ui_run_command "Enable N8N auto-start" "
            systemctl enable n8n
        "
    fi

    ui_status "success" "N8N auto-start đã bật"
}

disable_n8n_autostart() {
    if is_docker_installation; then
        ui_run_command "Disable N8N auto-start" "
            cd $N8N_COMPOSE_DIR
            sed -i 's/restart:.*/restart: \"no\"/' docker-compose.yml
            docker compose up -d n8n
        "
    else
        ui_run_command "Disable N8N auto-start" "
            systemctl disable n8n
        "
    fi

    ui_status "success" "N8N auto-start đã tắt"
}

# ===== HEALTH CHECK =====

verify_n8n_health() {
    local n8n_port=$(config_get "n8n.port" "5678")
    local max_wait=30
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$n8n_port/healthz" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        ((waited += 2))
    done

    return 1
}

# ===== LOG MANAGEMENT =====

show_n8n_logs() {
    ui_header "Nhật ký ứng dụng n8n"

    echo "1) Xem trực tiếp (Real-time)"
    echo "2) Xem 50 dòng gần nhất"
    echo "3) Chỉ xem Nhật ký Lỗi (Errors)"
    echo "0) Quay lại"
    echo ""

    choice=$(ui_prompt "Lựa chọn của bạn" "0" "^[0-3]$")

    case "$choice" in
    1) follow_n8n_logs ;;
    2) show_recent_n8n_logs ;;
    3) show_n8n_error_logs ;;
    0) return ;;
    esac
}

follow_n8n_logs() {
    echo "📝 Live N8N logs (Ctrl+C để thoát):"
    echo ""

    if is_docker_installation; then
        docker logs -f n8n
    else
        journalctl -u n8n -f
    fi
}

show_recent_n8n_logs() {
    echo "📝 50 dòng log gần nhất:"
    echo ""

    if is_docker_installation; then
        docker logs --tail 50 n8n
    else
        journalctl -u n8n -n 50 --no-pager
    fi
}

show_n8n_error_logs() {
    echo "📝 Error logs:"
    echo ""

    if is_docker_installation; then
        docker logs n8n 2>&1 | grep -i "error\|exception\|fail"
    else
        journalctl -u n8n -p err --no-pager
    fi
}

# ===== UTILITY FUNCTIONS =====

is_docker_installation() {
    [[ -f "$N8N_COMPOSE_DIR/docker-compose.yml" ]]
}

get_n8n_version() {
    if is_docker_installation; then
        docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    else
        n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
    fi
}

get_n8n_uptime() {
    if is_docker_installation; then
        local started=$(docker inspect n8n --format '{{.State.StartedAt}}' 2>/dev/null)
        if [[ -n "$started" ]]; then
            local start_epoch=$(date -d "$started" +%s)
            local now_epoch=$(date +%s)
            local uptime_seconds=$((now_epoch - start_epoch))
            seconds_to_human $uptime_seconds
        fi
    else
        systemctl show n8n --property=ActiveEnterTimestamp --value 2>/dev/null
    fi
}

export -f get_n8n_status show_n8n_detailed_status start_n8n_service stop_n8n_service restart_n8n_service
export -f is_n8n_autostart_enabled toggle_n8n_autostart enable_n8n_autostart disable_n8n_autostart
export -f verify_n8n_health show_n8n_logs
