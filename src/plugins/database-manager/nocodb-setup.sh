#!/bin/bash

# DataOnline N8N Manager - NocoDB Setup & Docker Integration
# Phiên bản: 1.0.0

set -euo pipefail

# Global variables
NOCODB_DATABASE_MODE=""  # "shared" or "separate"
NOCODB_DB_NAME=""
NOCODB_DB_PASSWORD=""
NOCODB_DOMAIN=""
NOCODB_ADMIN_EMAIL=""
NOCODB_ADMIN_PASSWORD=""
NOCODB_JWT_SECRET=""

# ===== DOMAIN CONFIGURATION =====

configure_nocodb_domain() {
    ui_section "Cấu hình Domain cho NocoDB"
    
    echo "Lựa chọn domain cho NocoDB:"
    echo ""
    echo "1) Nhập domain riêng"
    echo "2) Chỉ sử dụng IP:Port"
    echo ""
    
    while true; do
        read -p "Chọn [1-2]: " domain_choice
        
        case "$domain_choice" in
        1)
            prompt_custom_domain
            if [[ -n "$NOCODB_DOMAIN" ]]; then break; fi
            ;;
        2)
            NOCODB_DOMAIN=""
            break
            ;;
        *)
            ui_status "error" "Lựa chọn không hợp lệ"
            ;;
        esac
    done
    
    return 0
}

prompt_custom_domain() {
    echo ""
    echo -e "${UI_CYAN}Nhập domain cho NocoDB:${UI_NC}"
    echo -e "${UI_GRAY}   • Có thể nhập domain chính (ví dụ: example.com)${UI_NC}"
    echo -e "${UI_GRAY}   • Hoặc subdomain (ví dụ: nocodb.example.com)${UI_NC}"
    echo ""
    echo -n -e "${UI_WHITE}Domain: ${UI_NC}"
    read -r custom_domain
    
    if [[ -z "$custom_domain" ]]; then
        ui_status "error" "Domain không được để trống"
        return 1
    fi
    
    if ui_validate_domain "$custom_domain"; then
        NOCODB_DOMAIN="$custom_domain"
        ui_status "success" "Domain: $NOCODB_DOMAIN"
        return 0
    else
        ui_status "error" "Domain không hợp lệ"
        echo -e "${UI_YELLOW}Ví dụ domain hợp lệ: example.com, nocodb.example.com${UI_NC}"
        return 1
    fi
}

# ===== DATABASE MODE SELECTION =====

configure_database_mode() {
    ui_section "Lựa chọn Database cho NocoDB"
    
    echo "Lựa chọn database:"
    echo ""
    echo "1) Dùng chung database với N8N"
    echo "   [OK] Setup đơn giản, ít tài nguyên"
    echo "   [WARN] Performance và security chung"
    echo ""
    echo "2) Database riêng cho NocoDB"
    echo "   [OK] Độc lập, bảo mật tốt hơn"
    echo "   [WARN] Phức tạp hơn, nhiều tài nguyên"
    echo ""
    
    while true; do
        read -p "Chọn [1-2]: " db_choice
        
        case "$db_choice" in
        1)
            NOCODB_DATABASE_MODE="shared"
            NOCODB_DB_NAME="n8n"
            # Get N8N postgres password
            NOCODB_DB_PASSWORD=$(grep "POSTGRES_PASSWORD=" "$N8N_COMPOSE_DIR/.env" | cut -d'=' -f2)
            break
            ;;
        2)
            NOCODB_DATABASE_MODE="separate"
            NOCODB_DB_NAME="nocodb"
            NOCODB_DB_PASSWORD=$(generate_random_string 32)
            break
            ;;
        *)
            ui_status "error" "Lựa chọn không hợp lệ"
            ;;
        esac
    done
    
    return 0
}

# ===== ADMIN ACCOUNT SETUP =====

setup_admin_account() {
    ui_section "Cấu hình Admin NocoDB"
    
    # Get admin email with validation
    while true; do
        echo -n -e "${UI_WHITE}Email admin cho NocoDB: ${UI_NC}"
        read -r admin_email
        
        if [[ -z "$admin_email" ]]; then
            ui_status "error" "Email không được để trống"
            continue
        fi
        
        if ui_validate_email "$admin_email"; then
            NOCODB_ADMIN_EMAIL="$admin_email"
            ui_status "success" "Email: $admin_email"
            break
        else
            ui_status "error" "Email không hợp lệ"
        fi
    done
    
    # Generate secure password
    NOCODB_ADMIN_PASSWORD=$(generate_random_string 16)
    NOCODB_JWT_SECRET=$(generate_random_string 64)
    
    return 0
}

# ===== DOCKER COMPOSE INTEGRATION =====

setup_nocodb_integration() {
    ui_section "Cài đặt NocoDB Integration"

    if ! configure_nocodb_domain; then return 1; fi
    if ! configure_database_mode; then return 1; fi
    if ! setup_admin_account; then return 1; fi
    if ! save_nocodb_config; then return 1; fi
    if ! backup_current_compose; then return 1; fi
    if ! update_docker_compose; then return 1; fi
    if ! create_separate_database; then return 1; fi
    if ! start_nocodb_containers; then return 1; fi
    if ! wait_for_nocodb_ready; then return 1; fi
    
    # SSL setup if domain configured
    if [[ -n "$NOCODB_DOMAIN" ]]; then
        echo ""
        echo -n -e "${UI_YELLOW}Cấu hình SSL cho $NOCODB_DOMAIN? [Y/n]: ${UI_NC}"
        read -r setup_ssl
        if [[ ! "$setup_ssl" =~ ^[Nn]$ ]]; then
            setup_nocodb_ssl
        fi
    fi
    
    show_installation_summary
    return 0
}

save_nocodb_config() {
    ui_start_spinner "Lưu cấu hình NocoDB"
    
    # Determine public URL
    local public_url
    if [[ -n "$NOCODB_DOMAIN" ]]; then
        public_url="https://$NOCODB_DOMAIN"
    else
        local public_ip=$(get_public_ip || echo "localhost")
        public_url="http://$public_ip:8080"
    fi
    
    # Add to .env file
    if ! grep -q "# NocoDB Configuration" "$N8N_COMPOSE_DIR/.env"; then
        cat >> "$N8N_COMPOSE_DIR/.env" << EOF

# NocoDB Configuration - Added by DataOnline Manager
NOCODB_DATABASE_MODE=$NOCODB_DATABASE_MODE
NOCODB_DOMAIN=$NOCODB_DOMAIN
NOCODB_JWT_SECRET=$NOCODB_JWT_SECRET
NOCODB_ADMIN_EMAIL=$NOCODB_ADMIN_EMAIL
NOCODB_ADMIN_PASSWORD=$NOCODB_ADMIN_PASSWORD
NOCODB_PUBLIC_URL=$public_url

# Database Configuration
NC_DB_TYPE=pg
NC_DB_HOST=postgres
NC_DB_PORT=5432
NC_DB_USER=$([ "$NOCODB_DATABASE_MODE" = "separate" ] && echo "nocodb" || echo "n8n")
NC_DB_PASSWORD=$NOCODB_DB_PASSWORD
NC_DB_DATABASE=$NOCODB_DB_NAME
NC_DB_SSL=false
NC_DB_MIGRATE=true
EOF
    fi
    
    # Save admin password to file
    echo "$NOCODB_ADMIN_PASSWORD" > "$N8N_COMPOSE_DIR/.nocodb-admin-password"
    chmod 600 "$N8N_COMPOSE_DIR/.nocodb-admin-password"
    
    # Update manager config
    config_set "nocodb.admin_email" "$NOCODB_ADMIN_EMAIL"
    config_set "nocodb.domain" "$NOCODB_DOMAIN"
    config_set "nocodb.database_mode" "$NOCODB_DATABASE_MODE"
    config_set "nocodb.installed" "true"
    config_set "nocodb.installed_date" "$(date -Iseconds)"
    
    ui_stop_spinner
    return 0
}

backup_current_compose() {
    ui_start_spinner "Backup docker-compose hiện tại"
    
    local backup_dir="$N8N_COMPOSE_DIR/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir"
    cp "$N8N_COMPOSE_DIR/docker-compose.yml" "$backup_dir/docker-compose.yml.backup_$timestamp"
    cp "$N8N_COMPOSE_DIR/.env" "$backup_dir/.env.backup_$timestamp"
    
    ui_stop_spinner
    return 0
}

update_docker_compose() {
    ui_start_spinner "Cập nhật docker-compose.yml"
    
    local compose_file="$N8N_COMPOSE_DIR/docker-compose.yml"
    
    # Check if NocoDB already exists
    if grep -q "nocodb" "$compose_file"; then
        ui_stop_spinner
        ui_status "warning" "NocoDB đã tồn tại trong compose"
        return 0
    fi
    
    # Create new compose file
    create_updated_compose_file "$compose_file"
    
    # Validate compose file
    if ! docker compose -f "$compose_file" config >/dev/null 2>&1; then
        ui_stop_spinner
        ui_status "error" "Docker compose validation thất bại"
        return 1
    fi
    
    ui_stop_spinner
    ui_status "success" "docker-compose.yml đã được cập nhật"
    return 0
}

create_updated_compose_file() {
    local compose_file="$1"
    
    # Source environment variables
    set -a
    source "$N8N_COMPOSE_DIR/.env"
    set +a
    
    # Create new compose file based on database mode
    if [[ "$NOCODB_DATABASE_MODE" == "separate" ]]; then
        create_separate_mode_compose "$compose_file"
    else
        create_shared_mode_compose "$compose_file"
    fi
}

create_separate_mode_compose() {
    local compose_file="$1"
    
    envsubst < /dev/stdin > "$compose_file" << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
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
      - N8N_HOST=${N8N_DOMAIN:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-https}
      - NODE_ENV=production
      - WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - EXECUTIONS_MODE=regular
      - EXECUTIONS_PROCESS=main
      - N8N_METRICS=false
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
      - ./backups:/backups
    networks:
      - n8n-network

  nocodb:
    image: nocodb/nocodb:latest
    container_name: n8n-nocodb
    restart: unless-stopped
    environment:
      - NC_DB_TYPE=pg
      - NC_DB_HOST=postgres
      - NC_DB_PORT=5432
      - NC_DB_USER=nocodb
      - NC_DB_PASSWORD=${NOCODB_DB_PASSWORD}
      - NC_DB_DATABASE=nocodb
      - NC_DB_SSL=false
      - NC_DB_MIGRATE=true
      - NC_PUBLIC_URL=${NOCODB_PUBLIC_URL}
      - NC_AUTH_JWT_SECRET=${NOCODB_JWT_SECRET}
      - NC_ADMIN_EMAIL=${NOCODB_ADMIN_EMAIL}
      - NC_ADMIN_PASSWORD=${NOCODB_ADMIN_PASSWORD}
      - NC_DISABLE_TELE=true
      - NODE_ENV=production
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - nocodb_data:/usr/app/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

volumes:
  postgres_data:
    driver: local
  n8n_data:
    driver: local
  nocodb_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
EOF
}

create_shared_mode_compose() {
    local compose_file="$1"
    
    envsubst < /dev/stdin > "$compose_file" << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
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
      - N8N_HOST=${N8N_DOMAIN:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-https}
      - NODE_ENV=production
      - WEBHOOK_URL=${N8N_WEBHOOK_URL}
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - EXECUTIONS_MODE=regular
      - EXECUTIONS_PROCESS=main
      - N8N_METRICS=false
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
      - ./backups:/backups
    networks:
      - n8n-network

  nocodb:
    image: nocodb/nocodb:latest
    container_name: n8n-nocodb
    restart: unless-stopped
    environment:
      - NC_DB_TYPE=pg
      - NC_DB_HOST=postgres
      - NC_DB_PORT=5432
      - NC_DB_USER=n8n
      - NC_DB_PASSWORD=${POSTGRES_PASSWORD}
      - NC_DB_DATABASE=n8n
      - NC_DB_SSL=false
      - NC_DB_MIGRATE=true
      - NC_PUBLIC_URL=${NOCODB_PUBLIC_URL}
      - NC_AUTH_JWT_SECRET=${NOCODB_JWT_SECRET}
      - NC_ADMIN_EMAIL=${NOCODB_ADMIN_EMAIL}
      - NC_ADMIN_PASSWORD=${NOCODB_ADMIN_PASSWORD}
      - NC_DISABLE_TELE=true
      - NODE_ENV=production
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - nocodb_data:/usr/app/data
    networks:
      - n8n-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

volumes:
  postgres_data:
    driver: local
  n8n_data:
    driver: local
  nocodb_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
EOF
}

create_separate_database() {
    if [[ "$NOCODB_DATABASE_MODE" != "separate" ]]; then
        return 0
    fi
    
    ui_start_spinner "Tạo database riêng cho NocoDB"
    
    # Wait for PostgreSQL
    local max_wait=30
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
            break
        fi
        sleep 1
        ((waited++))
    done
    
    # Create user and database
    docker exec n8n-postgres psql -U n8n -c "
        CREATE USER nocodb WITH PASSWORD '$NOCODB_DB_PASSWORD';
        CREATE DATABASE nocodb OWNER nocodb;
        GRANT ALL PRIVILEGES ON DATABASE nocodb TO nocodb;
    " >/dev/null 2>&1 || true
    
    ui_stop_spinner
    ui_status "success" "Database riêng đã được tạo"
    return 0
}

start_nocodb_containers() {
    ui_start_spinner "Khởi động NocoDB"
    
    cd "$N8N_COMPOSE_DIR" || return 1
    
    # Pull and start
    if ! docker compose pull nocodb >/dev/null 2>&1; then
        ui_stop_spinner
        ui_status "error" "Không thể pull NocoDB image"
        return 1
    fi
    
    if ! docker compose up -d nocodb >/dev/null 2>&1; then
        ui_stop_spinner
        ui_status "error" "Không thể khởi động NocoDB"
        return 1
    fi
    
    ui_stop_spinner
    ui_status "success" "NocoDB đã khởi động"
    return 0
}

wait_for_nocodb_ready() {
    ui_start_spinner "Chờ NocoDB sẵn sàng"
    
    local max_wait=120
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if curl -s -f "http://localhost:8080/api/v1/health" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_status "success" "NocoDB đã sẵn sàng"
            return 0
        fi
        
        # Check if container failed
        if ! docker ps --format '{{.Names}}' | grep -q "^n8n-nocodb$"; then
            ui_stop_spinner
            ui_status "error" "NocoDB container đã dừng"
            return 1
        fi
        
        sleep 2
        ((waited += 2))
    done
    
    ui_stop_spinner
    ui_status "error" "Timeout chờ NocoDB"
    return 1
}

# ===== SSL SETUP =====

setup_nocodb_ssl() {
    local domain="$NOCODB_DOMAIN"  
    
    ui_section "Cài đặt SSL cho NocoDB"
    ui_status "info" "Domain được set: $domain"
    
    # Step 1: Create HTTP-only nginx config
    if ! create_nocodb_http_config "$domain"; then
        return 1
    fi
    
    # Step 2: Get SSL certificate
    if ! get_nocodb_ssl_certificate "$domain"; then
        return 1
    fi
    
    # Step 3: Create HTTPS config
    if ! create_nocodb_https_config "$domain"; then
        return 1
    fi
    
    # Step 4: Update NocoDB config
    update_nocodb_ssl_settings "$domain"
    
    ui_status "success" "SSL setup hoàn tất"
    return 0
}

create_nocodb_http_config() {
    local domain="$1"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    ui_start_spinner "Tạo HTTP config"
    
    # Create webroot
    sudo mkdir -p /var/www/html/.well-known/acme-challenge
    sudo chown -R www-data:www-data /var/www/html
    
    sudo tee "$nginx_conf" > /dev/null << EOF
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    sudo ln -sf "$nginx_conf" /etc/nginx/sites-enabled/
    
    if ! sudo nginx -t; then
        ui_stop_spinner
        ui_status "error" "Nginx config lỗi"
        return 1
    fi
    
    sudo systemctl reload nginx
    ui_stop_spinner
    ui_status "success" "HTTP config OK"
    return 0
}

get_nocodb_ssl_certificate() {
    local domain="$1"
    local email="admin@$(echo "$domain" | sed 's/^[^.]*\.//')"
    
    ui_start_spinner "Lấy SSL certificate"
    
    if sudo certbot certonly --webroot \
        -w /var/www/html \
        -d "$domain" \
        --agree-tos \
        --email "$email" \
        --non-interactive; then
        
        ui_stop_spinner
        ui_status "success" "Certificate thành công"
        
        # Download SSL configs if needed
        download_ssl_configs
        return 0
    else
        ui_stop_spinner
        ui_status "error" "Certificate thất bại"
        return 1
    fi
}

download_ssl_configs() {
    if [[ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
        sudo curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf \
            -o /etc/letsencrypt/options-ssl-nginx.conf
    fi
    
    if [[ ! -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
        sudo openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
    fi
}

create_nocodb_https_config() {
    local domain="$1"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    # Kiểm tra cert tồn tại trước
    if [[ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        ui_status "error" "SSL certificate không tồn tại cho $domain"
        return 1
    fi
    
    ui_start_spinner "Tạo HTTPS config"
    
    sudo tee "$nginx_conf" > /dev/null << EOF
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    if sudo nginx -t && sudo systemctl reload nginx; then
        ui_stop_spinner
        ui_status "success" "HTTPS config OK"
        return 0
    else
        ui_stop_spinner
        ui_status "error" "HTTPS config lỗi"
        return 1
    fi
}

update_nocodb_ssl_settings() {
    local domain="$1"
    
    ui_start_spinner "Cập nhật SSL settings"
    
    # Update .env
    sed -i "s|NOCODB_PUBLIC_URL=.*|NOCODB_PUBLIC_URL=https://$domain|" "$N8N_COMPOSE_DIR/.env"
    
    # Update config
    config_set "nocodb.ssl_enabled" "true"
    
    # Restart NocoDB
    cd "$N8N_COMPOSE_DIR"
    docker compose restart nocodb >/dev/null 2>&1
    
    ui_stop_spinner
    ui_status "success" "SSL settings cập nhật"
}

# ===== REMOVAL FUNCTIONS =====

remove_nocodb_integration() {
    ui_section "Gỡ bỏ NocoDB"
    
    local database_mode=$(config_get "nocodb.database_mode" "shared")
    
    # Stop and remove container
    stop_nocodb_container
    
    # Remove from compose
    remove_from_docker_compose
    
    # Handle database cleanup
    if [[ "$database_mode" == "separate" ]]; then
        echo -n -e "${UI_YELLOW}Xóa database riêng? [y/N]: ${UI_NC}"
        read -r remove_db
        if [[ "$remove_db" =~ ^[Yy]$ ]]; then
            remove_nocodb_database
        fi
    fi
    
    # Clean volumes and configs
    echo -n -e "${UI_YELLOW}Xóa data volumes? [y/N]: ${UI_NC}"
    read -r remove_data
    if [[ "$remove_data" =~ ^[Yy]$ ]]; then
        clean_nocodb_data
    fi
    
    clean_nocodb_configs
    
    ui_status "success" "NocoDB đã được gỡ bỏ"
    return 0
}

stop_nocodb_container() {
    ui_start_spinner "Dừng NocoDB container"
    
    cd "$N8N_COMPOSE_DIR"
    docker compose stop nocodb >/dev/null 2>&1 || true
    docker compose rm -f nocodb >/dev/null 2>&1 || true
    
    ui_stop_spinner
    ui_status "success" "Container đã dừng"
}

remove_from_docker_compose() {
    ui_start_spinner "Xóa khỏi docker-compose"
    
    local compose_file="$N8N_COMPOSE_DIR/docker-compose.yml"
    local temp_file="/tmp/compose-clean.yml"
    
    # Remove NocoDB service and volume
    awk '
        /^  nocodb:/ { skip=1; next }
        /^  [a-zA-Z]/ && skip { skip=0 }
        /^[a-zA-Z]/ && skip { skip=0; print; next }
        !skip { print }
    ' "$compose_file" | sed '/nocodb_data:/,+1d' > "$temp_file"
    
    if docker compose -f "$temp_file" config >/dev/null 2>&1; then
        mv "$temp_file" "$compose_file"
        ui_stop_spinner
        ui_status "success" "Đã xóa khỏi compose"
    else
        rm -f "$temp_file"
        ui_stop_spinner
        ui_status "error" "Lỗi xóa compose"
        return 1
    fi
}

remove_nocodb_database() {
    ui_start_spinner "Xóa database riêng"
    
    docker exec n8n-postgres psql -U n8n -c "
        DROP DATABASE IF EXISTS nocodb;
        DROP USER IF EXISTS nocodb;
    " >/dev/null 2>&1 || true
    
    ui_stop_spinner
    ui_status "success" "Database đã xóa"
}

clean_nocodb_data() {
    ui_start_spinner "Xóa data volumes"
    
    docker volume rm n8n_nocodb_data >/dev/null 2>&1 || true
    rm -rf "$N8N_COMPOSE_DIR/.nocodb-admin-password" >/dev/null 2>&1 || true
    
    ui_stop_spinner
    ui_status "success" "Data đã xóa"
}

clean_nocodb_configs() {
    # Remove from .env
    if [[ -f "$N8N_COMPOSE_DIR/.env" ]]; then
        sed -i '/# NocoDB Configuration/,/^$/d' "$N8N_COMPOSE_DIR/.env"
    fi
    
    # Clean manager config
    config_set "nocodb.installed" "false"
    config_set "nocodb.admin_email" ""
    config_set "nocodb.domain" ""
    config_set "nocodb.database_mode" ""
    
    ui_status "success" "Configs đã dọn dẹp"
}

# ===== UTILITIES =====

show_installation_summary() {
    local nocodb_url
    if [[ -n "$NOCODB_DOMAIN" ]]; then
        local ssl_enabled=$(config_get "nocodb.ssl_enabled" "false")
        if [[ "$ssl_enabled" == "true" ]]; then
            nocodb_url="https://$NOCODB_DOMAIN"
        else
            nocodb_url="http://$NOCODB_DOMAIN"
        fi
    else
        local public_ip=$(get_public_ip || echo "localhost")
        nocodb_url="http://$public_ip:8080"
    fi
    
    ui_info_box "Cài đặt NocoDB hoàn tất" \
        "Địa chỉ truy cập: $nocodb_url" \
        "Tài khoản email: $NOCODB_ADMIN_EMAIL" \
        "Mật khẩu quản trị: $NOCODB_ADMIN_PASSWORD" \
        "Chế độ lưu trữ: $([[ "$NOCODB_DATABASE_MODE" == "shared" ]] && echo "Dùng chung với N8N" || echo "Cơ sở dữ liệu riêng")"
    
    # Show N8N connection info briefly
    local n8n_db_password="${POSTGRES_PASSWORD:-$(grep 'POSTGRES_PASSWORD=' "$N8N_COMPOSE_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo 'unknown')}"
    echo -e "${UI_GRAY}Mật khẩu cơ sở dữ liệu N8N của bạn là: $n8n_db_password${UI_NC}"
    echo -e "${UI_GRAY}Sử dụng tên đăng nhập 'n8n' để kết nối dữ liệu.${UI_NC}"
}

# Export main function
export -f setup_nocodb_integration remove_nocodb_integration