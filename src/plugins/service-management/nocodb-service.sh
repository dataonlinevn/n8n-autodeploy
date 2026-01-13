#!/bin/bash

# DataOnline N8N Manager - NocoDB Service Management
# Phien ban: 1.0.0
# Quan ly dich vu NocoDB

set -euo pipefail

[[ -z "${N8N_COMPOSE_DIR:-}" ]] && readonly N8N_COMPOSE_DIR="/opt/n8n"
[[ -z "${NOCODB_PORT:-}" ]] && readonly NOCODB_PORT=8080

# ===== STATUS FUNCTIONS =====

get_nocodb_service_status() {
    if docker ps --format '{{.Names}}' | grep -q "^n8n-nocodb$"; then
        if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
            echo -e "${UI_GREEN}[OK] Dang chay${UI_NC}"
        else
            echo -e "${UI_YELLOW}[...] Dang khoi dong${UI_NC}"
        fi
    else
        echo -e "${UI_RED}[STOP] Da dung${UI_NC}"
    fi
}

show_nocodb_detailed_status() {
    local container_id=$(docker ps -q --filter "name=^n8n-nocodb$" 2>/dev/null)

    if [[ -n "$container_id" ]]; then
        echo "Container: $container_id"
        echo "Image: $(docker inspect $container_id --format '{{.Config.Image}}')"
        echo "Status: $(docker inspect $container_id --format '{{.State.Status}}')"
        echo "Port: $NOCODB_PORT"
        
        # Check API health
        if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
            echo "API: Hoat dong"
        else
            echo "API: Khong phan hoi"
        fi
        
        # Memory usage
        local mem=$(docker stats $container_id --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")
        echo "Bo nho: $mem"
        
        # Show URL
        local domain=$(config_get "nocodb.domain" "")
        if [[ -n "$domain" ]]; then
            echo "URL: https://$domain"
        else
            local public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
            echo "URL: http://$public_ip:$NOCODB_PORT"
        fi
    else
        echo "NocoDB container khong chay"
    fi
}

# ===== CONTROL FUNCTIONS =====

start_nocodb_service() {
    ui_info "Dang khoi dong NocoDB..."
    cd "$N8N_COMPOSE_DIR" && docker compose up -d nocodb >/dev/null 2>&1
    
    ui_start_spinner "Dang cho NocoDB khoi dong..."
    local waited=0
    while [[ $waited -lt 30 ]]; do
        if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_success "NocoDB da san sang"
            return 0
        fi
        sleep 2
        ((waited += 2)) || true
    done
    
    ui_stop_spinner
    ui_warning "NocoDB dang khoi dong, co the can them thoi gian"
}

stop_nocodb_service() {
    ui_warning "Dung NocoDB se khong the truy cap giao dien quan ly database"
    
    if ! ui_confirm "Tiep tuc dung NocoDB?"; then
        return
    fi
    
    ui_info "Dang dung NocoDB..."
    cd "$N8N_COMPOSE_DIR" && docker compose stop nocodb >/dev/null 2>&1
    ui_success "NocoDB da dung"
}

restart_nocodb_service() {
    ui_info "Dang khoi dong lai NocoDB..."
    cd "$N8N_COMPOSE_DIR" && docker compose restart nocodb >/dev/null 2>&1
    
    ui_start_spinner "Dang cho NocoDB khoi dong..."
    local waited=0
    while [[ $waited -lt 30 ]]; do
        if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_success "NocoDB da khoi dong lai"
            return 0
        fi
        sleep 2
        ((waited += 2)) || true
    done
    
    ui_stop_spinner
    ui_warning "NocoDB chua phan hoi, vui long kiem tra logs"
}

# ===== AUTO-START =====

is_nocodb_autostart_enabled() {
    local restart_policy=$(docker inspect n8n-nocodb --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
    [[ "$restart_policy" == "unless-stopped" || "$restart_policy" == "always" ]]
}

toggle_nocodb_autostart() {
    if is_nocodb_autostart_enabled; then
        ui_info "Dang tat auto-start NocoDB..."
        docker update --restart=no n8n-nocodb >/dev/null 2>&1
        ui_success "Da tat auto-start NocoDB"
    else
        ui_info "Dang bat auto-start NocoDB..."
        docker update --restart=unless-stopped n8n-nocodb >/dev/null 2>&1
        ui_success "Da bat auto-start NocoDB"
    fi
}

# ===== LOGS =====

show_nocodb_logs() {
    echo "NocoDB Logs (50 dong cuoi):"
    echo ""
    docker logs --tail 50 n8n-nocodb 2>&1
}

# ===== CHECK INSTALLED =====

is_nocodb_installed() {
    docker ps -a --format '{{.Names}}' | grep -q "^n8n-nocodb$"
}

# ===== CONNECTION INFO =====

show_nocodb_connection_info() {
    ui_section "Thong tin ket noi NocoDB"
    
    local host="n8n-nocodb"
    local port="$NOCODB_PORT"
    local container_id=$(docker ps -q --filter "name=^n8n-nocodb$" 2>/dev/null)
    local public_ip=$(get_public_ip 2>/dev/null || echo "localhost")
    
    # Kiem tra xem port co duoc map ra ngoai khong
    local mapped_port=""
    if [[ -n "$container_id" ]]; then
        mapped_port=$(docker port "$container_id" "$port/tcp" 2>/dev/null | cut -d':' -f2 | head -1 || echo "")
    fi

    echo "Ket noi noi bo (Docker):"
    echo "  Host: $host"
    echo "  Port: $port"
    echo ""
    
    # Show URL nhung uu tien domain
    local domain=$(config_get "nocodb.domain" "")
    if [[ -n "$domain" ]]; then
        echo "Ket noi ben ngoai (Public):"
        echo "  URL: https://$domain"
    else
        echo "Ket noi ben ngoai (Public):"
        if [[ -n "$mapped_port" ]]; then
            echo "  URL: http://$public_ip:$mapped_port"
        else
            echo "  Trang thai: Chua mo port ra ngoai (chi dung duoc qua Proxy/VPN)"
        fi
    fi
}

export -f get_nocodb_service_status show_nocodb_detailed_status start_nocodb_service stop_nocodb_service
export -f restart_nocodb_service is_nocodb_autostart_enabled toggle_nocodb_autostart
export -f show_nocodb_logs is_nocodb_installed show_nocodb_connection_info
