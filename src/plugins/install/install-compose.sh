#!/bin/bash

# DataOnline N8N Manager - Install Compose Module
# Phiên bản: 1.0.0

set -euo pipefail

create_docker_compose() {
    ui_section "Tạo Docker Compose Configuration"

    local compose_dir="/opt/n8n"

    if ! ui_run_command "Tạo thư mục cài đặt" "sudo mkdir -p $compose_dir"; then
        return 1
    fi

    local postgres_password=$(generate_random_string 32)

    # Create temp files
    local temp_compose="/tmp/docker-compose-n8n.yml"
    local temp_env="/tmp/env-n8n"

    ui_start_spinner "Tạo docker-compose.yml"

    cat >"$temp_compose" <<'DOCKER_EOF'
version: '3.8'

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

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=PORT_PLACEHOLDER
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=WEBHOOK_PLACEHOLDER
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=PASSWORD_PLACEHOLDER
      - EXECUTIONS_MODE=regular
      - EXECUTIONS_PROCESS=main
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
  n8n_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
DOCKER_EOF

    # Replace placeholders
    sed -i "s#PASSWORD_PLACEHOLDER#$postgres_password#g" "$temp_compose"
    sed -i "s#PG_PORT_PLACEHOLDER#$POSTGRES_PORT#g" "$temp_compose"
    sed -i "s#PORT_PLACEHOLDER#$N8N_PORT#g" "$temp_compose"
    sed -i "s#WEBHOOK_PLACEHOLDER#$N8N_WEBHOOK_URL#g" "$temp_compose"

    ui_stop_spinner

    # Create .env file
    ui_start_spinner "Tạo file environment"

    cat >"$temp_env" <<EOF
# DataOnline N8N Manager - Environment Variables
# Generated at: $(date)

# N8N Configuration
N8N_PORT=$N8N_PORT
N8N_DOMAIN=$N8N_DOMAIN
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL

# PostgreSQL Configuration
POSTGRES_PORT=$POSTGRES_PORT
POSTGRES_PASSWORD=$postgres_password

# Backup Configuration
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=30
EOF

    ui_stop_spinner

    # Copy files
    if ! ui_run_command "Sao chép docker-compose.yml" "sudo cp $temp_compose $compose_dir/docker-compose.yml"; then
        rm -f "$temp_compose" "$temp_env"
        return 1
    fi

    if ! ui_run_command "Sao chép .env file" "sudo cp $temp_env $compose_dir/.env"; then
        rm -f "$temp_compose" "$temp_env"
        return 1
    fi

    # Set permissions
    if ! ui_run_command "Cấp quyền files" "sudo chmod 644 $compose_dir/docker-compose.yml && sudo chmod 600 $compose_dir/.env"; then
        return 1
    fi

    # Cleanup
    rm -f "$temp_compose" "$temp_env"

    # Save config
    config_set "n8n.install_type" "docker"
    config_set "n8n.compose_dir" "$compose_dir"
    config_set "n8n.port" "$N8N_PORT"
    config_set "n8n.webhook_url" "$N8N_WEBHOOK_URL"

    ui_success "Docker Compose configuration tạo thành công"
    return 0
}

start_n8n_docker() {
    ui_section "Khởi động N8N với Docker"

    local compose_dir="/opt/n8n"
    cd "$compose_dir" || return 1

    if ! ui_run_command "Tải Docker images" "sudo docker compose pull"; then
        return 1
    fi

    if ! ui_run_command "Khởi động containers" "sudo docker compose up -d"; then
        return 1
    fi

    # Wait for N8N to be ready
    ui_start_spinner "Chờ N8N khởi động"
    local max_wait=60
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$N8N_PORT/healthz" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_success "N8N đã khởi động thành công!"
            break
        fi
        sleep 2
        ((waited += 2))
    done

    if [[ $waited -ge $max_wait ]]; then
        ui_stop_spinner
        ui_error "Timeout chờ N8N khởi động" "N8N_START_TIMEOUT" "Kiểm tra logs: sudo docker compose logs -f"
        return 1
    fi

    cd - >/dev/null
    return 0
}

export -f create_docker_compose start_n8n_docker
