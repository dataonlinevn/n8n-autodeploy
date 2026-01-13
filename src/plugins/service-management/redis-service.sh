#!/bin/bash

# DataOnline N8N Manager - Redis Service Management
# Phien ban: 1.0.0
# Quan ly dich vu Redis (Cache)

set -euo pipefail

[[ -z "${N8N_COMPOSE_DIR:-}" ]] && readonly N8N_COMPOSE_DIR="/opt/n8n"

# ===== STATUS FUNCTIONS =====

get_redis_status() {
    if docker ps --format '{{.Names}}' | grep -q "^n8n-redis$"; then
        echo -e "${UI_GREEN}[OK] Dang chay${UI_NC}"
    else
        echo -e "${UI_RED}[STOP] Da dung${UI_NC}"
    fi
}

show_redis_detailed_status() {
    local container_id=$(docker ps -q --filter "name=^n8n-redis$" 2>/dev/null)

    if [[ -n "$container_id" ]]; then
        echo "Container: $container_id"
        echo "Image: $(docker inspect $container_id --format '{{.Config.Image}}')"
        echo "Status: $(docker inspect $container_id --format '{{.State.Status}}')"
        
        # Test connection
        if test_redis_connection_silent; then
            echo "Ket noi: OK"
        else
            echo "Ket noi: Loi"
        fi
        
        # Memory usage
        local mem=$(docker stats $container_id --no-stream --format "{{.MemUsage}}" 2>/dev/null || echo "N/A")
        echo "Bo nho: $mem"
    else
        echo "Redis container khong chay"
    fi
}

# ===== CONTROL FUNCTIONS =====

start_redis_service() {
    ui_info "Dang khoi dong Redis..."
    cd "$N8N_COMPOSE_DIR" && docker compose up -d redis >/dev/null 2>&1
    
    sleep 2
    if test_redis_connection_silent; then
        ui_success "Redis da san sang"
    else
        ui_warning "Redis dang khoi dong..."
    fi
}

stop_redis_service() {
    ui_warning "Dung Redis co the anh huong den hieu suat N8N"
    
    if ! ui_confirm "Tiep tuc dung Redis?"; then
        return
    fi
    
    ui_info "Dang dung Redis..."
    cd "$N8N_COMPOSE_DIR" && docker compose stop redis >/dev/null 2>&1
    ui_success "Redis da dung"
}

restart_redis_service() {
    ui_info "Dang khoi dong lai Redis..."
    cd "$N8N_COMPOSE_DIR" && docker compose restart redis >/dev/null 2>&1
    
    sleep 2
    if test_redis_connection_silent; then
        ui_success "Redis da khoi dong lai"
    else
        ui_error "Redis khong phan hoi"
    fi
}

# ===== CONNECTION TEST =====

test_redis_connection() {
    ui_info "Dang kiem tra ket noi Redis..."
    
    if test_redis_connection_silent; then
        ui_success "Ket noi Redis thanh cong"
        
        # Show Redis info
        local info=$(docker exec n8n-redis redis-cli INFO server 2>/dev/null | grep -E "^(redis_version|uptime_in_days):" | head -2)
        echo "$info" | sed 's/^/  /'
    else
        ui_error "Khong the ket noi Redis"
    fi
}

test_redis_connection_silent() {
    docker exec n8n-redis redis-cli ping >/dev/null 2>&1
}

# ===== AUTO-START =====

is_redis_autostart_enabled() {
    local restart_policy=$(docker inspect n8n-redis --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)
    [[ "$restart_policy" == "unless-stopped" || "$restart_policy" == "always" ]]
}

toggle_redis_autostart() {
    if is_redis_autostart_enabled; then
        ui_info "Dang tat auto-start Redis..."
        cd "$N8N_COMPOSE_DIR"
        docker update --restart=no n8n-redis >/dev/null 2>&1
        ui_success "Da tat auto-start Redis"
    else
        ui_info "Dang bat auto-start Redis..."
        cd "$N8N_COMPOSE_DIR"
        docker update --restart=unless-stopped n8n-redis >/dev/null 2>&1
        ui_success "Da bat auto-start Redis"
    fi
}

# ===== LOGS =====

show_redis_logs() {
    echo "Redis Logs (50 dong cuoi):"
    echo ""
    docker logs --tail 50 n8n-redis 2>&1
}

# ===== FLUSH CACHE =====

flush_redis_cache() {
    ui_warning "Xoa cache se xoa tat ca du lieu tam thoi"
    
    if ! ui_confirm "Ban chac chan muon xoa cache?"; then
        return
    fi
    
    ui_info "Dang xoa cache..."
    if docker exec n8n-redis redis-cli FLUSHALL >/dev/null 2>&1; then
        ui_success "Da xoa cache thanh cong"
    else
        ui_error "Khong the xoa cache"
    fi
}

# ===== CONNECTION INFO =====

show_redis_connection_info() {
    ui_section "Thong tin ket noi Redis"
    
    local host="n8n-redis"
    local port="6379"
    local container_id=$(docker ps -q --filter "name=^n8n-redis$" 2>/dev/null)
    local public_ip=$(get_public_ip 2>/dev/null || echo "localhost")
    
    # Kiem tra xem port co duoc map ra ngoai khong
    local mapped_port=""
    if [[ -n "$container_id" ]]; then
        mapped_port=$(docker port "$container_id" 6379/tcp 2>/dev/null | cut -d':' -f2 | head -1 || echo "")
    fi

    echo "Ket noi noi bo (Docker):"
    echo "  Host: $host"
    echo "  Port: $port"
    echo ""
    
    if [[ -n "$mapped_port" ]]; then
        echo "Ket noi ben ngoai (Public):"
        echo "  Host: $public_ip"
        echo "  Port: $mapped_port"
        echo ""
    fi
    
    echo "Huong dan su dung trong N8N Workflow:"
    echo "  - Host: n8n-redis"
    echo "  - Port: 6379"
    echo "  - Password: (De trong)"
    echo ""
    echo "Ghi chu: Mac dinh Redis trong bo cai nay khong su dung mat khau."
}

export -f get_redis_status show_redis_detailed_status start_redis_service stop_redis_service
export -f restart_redis_service test_redis_connection is_redis_autostart_enabled toggle_redis_autostart
export -f show_redis_logs flush_redis_cache show_redis_connection_info
