#!/bin/bash

# DataOnline N8N Manager - Install Compose Module
# Phiên bản: 1.0.0

set -euo pipefail

create_docker_compose() {
    local compose_dir="/opt/n8n"

    ui_start_spinner "Đang khởi tạo cấu hình hệ thống..."

    # 1. Tạo thư mục
    sudo mkdir -p "$compose_dir" >/dev/null 2>&1

    # 2. Tạo nội dung file
    local postgres_password=$(generate_random_string 32)
    
    # Nếu đã có file .env, cố gắng lấy lại password cũ để tránh lỗi DB volume
    if [[ -f "$compose_dir/.env" ]]; then
        local old_pass=$(grep "^POSTGRES_PASSWORD=" "$compose_dir/.env" | cut -d'=' -f2-)
        if [[ -n "$old_pass" ]]; then
            postgres_password="$old_pass"
        fi
    fi
    
    local temp_compose="/tmp/docker-compose-n8n.yml"
    local temp_env="/tmp/env-n8n"

    cat >"$temp_compose" <<'DOCKER_EOF'
services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=PASSWORD_PLACEHOLDER
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "PG_PORT_PLACEHOLDER:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network

  redis:
    image: redis:7-alpine
    container_name: n8n-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=PORT_PLACEHOLDER
      - N8N_PROTOCOL=PROTOCOL_PLACEHOLDER
      - NODE_ENV=production
      - WEBHOOK_URL=WEBHOOK_PLACEHOLDER
      - N8N_SECURE_COOKIE=COOKIE_PLACEHOLDER
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=PASSWORD_PLACEHOLDER
      # Redis Queue Configuration
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_HEALTH_CHECK_ACTIVE=true
      - N8N_METRICS=false
    ports:
      - "PORT_PLACEHOLDER:PORT_PLACEHOLDER"
    volumes:
      - n8n_data:/home/node/.n8n
      - ./backups:/backups
    networks:
      - n8n-network

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  n8n_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
DOCKER_EOF

    # Replace placeholders
    local protocol="http"
    local secure_cookie="false"
    [[ -n "$N8N_DOMAIN" ]] && protocol="https" && secure_cookie="true"

    sed -i "s#PASSWORD_PLACEHOLDER#$postgres_password#g" "$temp_compose"
    sed -i "s#PG_PORT_PLACEHOLDER#$POSTGRES_PORT#g" "$temp_compose"
    sed -i "s#PORT_PLACEHOLDER#$N8N_PORT#g" "$temp_compose"
    sed -i "s#WEBHOOK_PLACEHOLDER#$N8N_WEBHOOK_URL#g" "$temp_compose"
    sed -i "s#PROTOCOL_PLACEHOLDER#$protocol#g" "$temp_compose"
    sed -i "s#COOKIE_PLACEHOLDER#$secure_cookie#g" "$temp_compose"

    # Create .env file
    cat >"$temp_env" <<EOF
# DataOnline N8N Manager - Environment Variables
# Generated at: $(date)

# N8N Configuration
N8N_PORT=$N8N_PORT
N8N_DOMAIN=$N8N_DOMAIN
N8N_PROTOCOL=$protocol
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL
N8N_SECURE_COOKIE=$secure_cookie

# PostgreSQL Configuration
POSTGRES_PORT=$POSTGRES_PORT
POSTGRES_PASSWORD=$postgres_password

# Backup Configuration
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=30
EOF

    # 3. Copy files và set permissions
    sudo cp "$temp_compose" "$compose_dir/docker-compose.yml" >/dev/null 2>&1
    sudo cp "$temp_env" "$compose_dir/.env" >/dev/null 2>&1
    sudo chmod 644 "$compose_dir/docker-compose.yml" >/dev/null 2>&1
    sudo chmod 600 "$compose_dir/.env" >/dev/null 2>&1

    # Cleanup
    rm -f "$temp_compose" "$temp_env"
    
    ui_stop_spinner
    
    # Save config
    config_set "n8n.install_type" "docker"
    config_set "n8n.compose_dir" "$compose_dir"
    config_set "n8n.port" "$N8N_PORT"
    config_set "n8n.domain" "$N8N_DOMAIN"
    config_set "n8n.webhook_url" "$N8N_WEBHOOK_URL"
    config_set "n8n.ssl_enabled" $([[ -n "$N8N_DOMAIN" ]] && echo "true" || echo "false")

    return 0
}

start_n8n_docker() {
    # Kiểm tra môi trường Docker
    check_docker_installation

    local compose_dir="/opt/n8n"
    cd "$compose_dir" || return 1

    if ! ui_run_command "Tải Docker images" "sudo docker compose pull"; then
        return 1
    fi

    if ! ui_run_command "Khởi động containers" "sudo docker compose up -d"; then
        return 1
    fi

    # Wait for N8N to be ready
    ui_start_spinner "Đang khởi động ứng dụng n8n..."
    local max_wait=60
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$N8N_PORT/healthz" >/dev/null 2>&1; then
            ui_stop_spinner
            return 0
        fi
        sleep 2
        ((waited += 2))
    done

    ui_stop_spinner
    ui_error "Ứng dụng không phản hồi sau khi khởi động"
    return 1

    cd - >/dev/null
    return 0
}

export -f create_docker_compose start_n8n_docker
