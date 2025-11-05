#!/bin/bash

# DataOnline N8N Manager - SSL Automation Plugin
# Phiên bản: 1.0.0
# Tự động hóa cài đặt SSL cho N8N với Let's Encrypt

set -euo pipefail

# Source core modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$PLUGIN_DIR")")"

[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
[[ -z "${SPINNER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"

# Constants
readonly SSL_LOADED=true
readonly WEBROOT_PATH="/var/www/html"
readonly CERTBOT_LOG="/var/log/letsencrypt"

# ===== DNS VALIDATION =====

validate_domain_dns() {
    local domain="$1"
    local server_ip=$(get_public_ip)

    ui_start_spinner "Kiểm tra DNS cho $domain"

    local resolved_ip=$(dig +short A "$domain" @1.1.1.1 | tail -n1)

    ui_stop_spinner

    if [[ -z "$resolved_ip" ]]; then
        ui_status "error" "Không thể phân giải DNS cho $domain"
        echo -n -e "${UI_YELLOW}Bỏ qua kiểm tra DNS? [y/N]: ${UI_NC}"
        read -r skip_dns
        return $([[ "$skip_dns" =~ ^[Yy]$ ]] && echo 0 || echo 1)
    fi

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        ui_status "success" "DNS đã trỏ đúng: $domain → $server_ip"
        return 0
    else
        ui_status "error" "DNS không trỏ đúng: $domain → $resolved_ip (cần: $server_ip)"
        echo -n -e "${UI_YELLOW}Bỏ qua kiểm tra DNS? [y/N]: ${UI_NC}"
        read -r skip_dns
        return $([[ "$skip_dns" =~ ^[Yy]$ ]] && echo 0 || echo 1)
    fi
}

# ===== NGINX CONFIGURATION =====

create_nginx_http_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"

    ui_section "Tạo cấu hình Nginx HTTP"

    # Step 1: Create webroot directory
    if ! ui_run_command "Tạo webroot directory" "
        mkdir -p $WEBROOT_PATH/.well-known/acme-challenge
        chown www-data:www-data $WEBROOT_PATH -R
        chmod 755 $WEBROOT_PATH -R
    "; then
        return 1
    fi

    # Step 2: Create HTTP-only nginx config for certification
    ui_start_spinner "Tạo HTTP config cho Let's Encrypt"

    cat >"$nginx_conf" <<EOF
server {
    listen 80;
    server_name $domain;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root $WEBROOT_PATH;
        allow all;
    }

    # Temporary: Proxy to N8N for testing
    location / {
        proxy_pass http://127.0.0.1:$n8n_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        proxy_buffering off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }
}
EOF

    ui_stop_spinner
    ui_status "success" "HTTP config tạo thành công"

    # Step 3: Enable site
    if ! ui_run_command "Enable nginx site" "
        ln -sf $nginx_conf /etc/nginx/sites-enabled/
    "; then
        return 1
    fi

    # Step 4: Test nginx config
    if ! ui_run_command "Test nginx configuration" "nginx -t"; then
        ui_status "error" "Nginx config có lỗi"
        rm -f "/etc/nginx/sites-enabled/$(basename $nginx_conf)"
        return 1
    fi

    # Step 5: Reload nginx
    if ! ui_run_command "Reload nginx" "systemctl reload nginx"; then
        return 1
    fi

    ui_status "success" "Nginx HTTP config hoạt động"
    return 0
}

# Create HTTPS config after obtaining certificate
create_nginx_ssl_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"

    ui_section "Nâng cấp lên HTTPS config"

    # Verify SSL files exist
    if [[ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        ui_status "error" "SSL certificate không tồn tại"
        return 1
    fi

    ui_start_spinner "Tạo HTTPS config"

    cat >"$nginx_conf" <<EOF
server {
    listen 80;
    server_name $domain;

    location /.well-known/acme-challenge/ {
        root $WEBROOT_PATH;
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
    
    # Include Let's Encrypt options if available
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    client_max_body_size 100M;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    location / {
        proxy_pass http://127.0.0.1:$n8n_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }

    location ~ /\\. {
        deny all;
    }
}
EOF

    ui_stop_spinner

    # Test nginx config
    if ! ui_run_command "Test HTTPS configuration" "nginx -t"; then
        ui_status "error" "HTTPS config có lỗi"
        return 1
    fi

    # Reload nginx
    if ! ui_run_command "Reload nginx với HTTPS" "systemctl reload nginx"; then
        return 1
    fi

    ui_status "success" "HTTPS config hoạt động"
    return 0
}

verify_ssl_setup() {
    local domain="$1"
    local n8n_port="${2:-5678}"

    ui_section "Xác minh cài đặt SSL"

    # Check N8N running
    if command_exists docker && docker ps | grep -q "n8n"; then
        ui_status "success" "N8N đang chạy trong Docker"
    elif systemctl is-active --quiet n8n; then
        ui_status "success" "N8N service đang chạy"
    else
        ui_status "warning" "N8N có thể không chạy"
        if [[ -f "/opt/n8n/docker-compose.yml" ]]; then
            ui_run_command "Khởi động N8N" "cd /opt/n8n && docker compose up -d"
        fi
    fi

    # Check HTTPS connection
    ui_start_spinner "Kiểm tra kết nối HTTPS"
    if curl -s -k "https://$domain" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_status "success" "HTTPS hoạt động: https://$domain"
        return 0
    else
        ui_stop_spinner
        ui_status "error" "HTTPS không hoạt động"
        return 1
    fi
}

# ===== SSL CERTIFICATE =====

install_certbot() {
    if command_exists certbot; then
        ui_status "success" "Certbot đã cài đặt"
        return 0
    fi

    ui_run_command "Cài đặt Certbot" "
        apt update
        apt install -y certbot python3-certbot-nginx
    "
}

obtain_ssl_certificate() {
    local domain="$1"
    local email="$2"

    ui_start_spinner "Lấy chứng chỉ SSL từ Let's Encrypt"
    
    local certbot_output
    local certbot_exit_code=0
    
    certbot_output=$(certbot certonly --webroot \
        -w $WEBROOT_PATH \
        -d $domain \
        --agree-tos \
        --email $email \
        --non-interactive \
        --force-renewal 2>&1) || certbot_exit_code=$?
    
    ui_stop_spinner
    
    # Check for rate limit error
    if [[ $certbot_exit_code -ne 0 ]]; then
        if echo "$certbot_output" | grep -q "too many certificates.*already issued"; then
            ui_status "error" "❌ Let's Encrypt rate limit exceeded"
            
            ui_warning_box "Rate Limit Exceeded" \
                "Domain đã vượt quá 5 certificates/tuần" \
                "Cần chờ đến tuần sau để thử lại" \
                "Hoặc sử dụng subdomain khác"
            
            echo "Giải pháp thay thế:"
            echo "1) Sử dụng subdomain: app.$domain"
            echo "2) Test với staging: certbot --staging"
            echo "3) Sử dụng self-signed certificate tạm thời"
            echo ""
            
            echo -n -e "${UI_YELLOW}Tạo self-signed certificate tạm thời? [Y/n]: ${UI_NC}"
            read -r use_self_signed
            
            if [[ ! "$use_self_signed" =~ ^[Nn]$ ]]; then
                return create_self_signed_certificate "$domain"
            else
                return 1
            fi
        else
            ui_status "error" "❌ Certbot failed with other error"
            echo "Error details:"
            echo "$certbot_output" | tail -5
            return 1
        fi
    fi

    # Download SSL options after successful certificate
    if [[ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
        ui_run_command "Tải cấu hình SSL" "
            curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf -o /etc/letsencrypt/options-ssl-nginx.conf
        "
    fi

    if [[ ! -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
        ui_run_command "Tạo DH parameters" "
            openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
        "
    fi

    ui_status "success" "✅ Let's Encrypt certificate thành công"
    return 0
}

# Create self-signed certificate as fallback
create_self_signed_certificate() {
    local domain="$1"
    
    ui_start_spinner "Tạo self-signed certificate cho $domain"
    
    # Create directory for self-signed certs
    mkdir -p "/etc/ssl/self-signed"
    
    # Generate private key and certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "/etc/ssl/self-signed/$domain.key" \
        -out "/etc/ssl/self-signed/$domain.crt" \
        -subj "/C=VN/ST=HN/L=Hanoi/O=DataOnline/CN=$domain" 2>/dev/null
    
    ui_stop_spinner
    
    # Create self-signed HTTPS config
    create_self_signed_nginx_config "$domain"
    
    ui_status "success" "✅ Self-signed certificate created"
    
    ui_warning_box "Self-Signed Certificate Warning" \
        "⚠️  Browser sẽ hiển thị cảnh báo security" \
        "✅ HTTPS vẫn hoạt động (với warning)" \
        "💡 Có thể thử Let's Encrypt lại sau 1 tuần"
        
    return 0
}

create_self_signed_nginx_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    cat >"$nginx_conf" <<EOF
server {
    listen 80;
    server_name $domain;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/ssl/self-signed/$domain.crt;
    ssl_certificate_key /etc/ssl/self-signed/$domain.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 100M;
    
    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    location / {
        proxy_pass http://127.0.0.1:$n8n_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        proxy_buffering off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }
}
EOF

    # Test and reload
    nginx -t && systemctl reload nginx
}

# ===== AUTO-RENEWAL =====

setup_auto_renewal() {
    ui_section "Cấu hình tự động gia hạn SSL"

    # Enable certbot timer
    if ! ui_run_command "Kích hoạt auto-renewal" "
        systemctl enable certbot.timer
        systemctl start certbot.timer
    "; then
        return 1
    fi

    # Test renewal
    ui_run_command "Test renewal process" "certbot renew --dry-run"

    # Create renewal hook
    local renewal_hook="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
    ui_run_command "Tạo renewal hook" "
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > $renewal_hook << 'EOF'
#!/bin/bash
systemctl reload nginx
EOF
        chmod +x $renewal_hook
    "

    ui_status "success" "Auto-renewal đã được cấu hình"
}

# ===== DOCKER CONFIGURATION UPDATE =====

update_n8n_ssl_config() {
    local domain="$1"
    local compose_dir="/opt/n8n"

    if [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
        ui_status "error" "Không tìm thấy N8N Docker installation"
        return 1
    fi

    ui_run_command "Cập nhật cấu hình N8N cho SSL" "
        cd $compose_dir
        
        # Update .env file
        sed -i 's|^N8N_DOMAIN=.*|N8N_DOMAIN=$domain|' .env
        sed -i 's|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=https://$domain|' .env
        
        # Update docker-compose environment
        sed -i 's|N8N_PROTOCOL=http|N8N_PROTOCOL=https|' docker-compose.yml
        sed -i 's|WEBHOOK_URL=http://.*|WEBHOOK_URL=https://$domain/|' docker-compose.yml
        sed -i 's|N8N_HOST=0.0.0.0|N8N_HOST=$domain|' docker-compose.yml
        
        # Restart N8N
        docker compose restart n8n
    "

    # Save to config
    config_set "n8n.domain" "$domain"
    config_set "n8n.ssl_enabled" "true"
    config_set "n8n.webhook_url" "https://$domain"
}

# ===== MAIN SSL SETUP FUNCTION =====

setup_ssl_main() {
    ui_header "Cài đặt SSL với Let's Encrypt"

    # Get domain
    echo -n -e "${UI_WHITE}Nhập domain cho N8N: ${UI_NC}"
    read -r domain

    if [[ -z "$domain" ]]; then
        ui_status "error" "Domain không được để trống"
        return 1
    fi

    if ! ui_validate_domain "$domain"; then
        ui_status "error" "Domain không hợp lệ: $domain"
        return 1
    fi

    # Get email
    echo -n -e "${UI_WHITE}Nhập email cho Let's Encrypt: ${UI_NC}"
    read -r email

    if [[ -z "$email" ]]; then
        email="admin@$domain"
        ui_status "info" "Sử dụng email mặc định: $email"
    fi

    if ! ui_validate_email "$email"; then
        ui_status "error" "Email không hợp lệ: $email"
        return 1
    fi

    # Get N8N port
    local n8n_port=$(config_get "n8n.port" "5678")
    echo -n -e "${UI_WHITE}Port N8N (hiện tại: $n8n_port): ${UI_NC}"
    read -r port_input
    if [[ -n "$port_input" ]]; then
        n8n_port="$port_input"
    fi

    ui_info_box "Thông tin SSL setup" \
        "Domain: $domain" \
        "Email: $email" \
        "N8N Port: $n8n_port"

    echo -n -e "${UI_YELLOW}Tiếp tục cài đặt SSL? [Y/n]: ${UI_NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        return 0
    fi

    # Validate DNS
    if ! validate_domain_dns "$domain"; then
        ui_status "warning" "DNS validation thất bại nhưng tiếp tục"
    fi

    # Install dependencies
    install_certbot || return 1

    # Create HTTP config first
    if ! create_nginx_http_config "$domain" "$n8n_port"; then
        return 1
    fi

    # Attempt to obtain SSL certificate
    if ! obtain_ssl_certificate "$domain" "$email"; then
        ui_status "error" "❌ SSL certificate setup thất bại"
        return 1
    fi

    # Only create HTTPS config after certificate exists
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        # Create full HTTPS config
        create_nginx_ssl_config "$domain" "$n8n_port" || return 1
        
        # Setup auto-renewal
        setup_auto_renewal || return 1
    fi

    # Update N8N configuration
    update_n8n_ssl_config "$domain" || return 1

    # Final verification
    if verify_ssl_setup "$domain" "$n8n_port"; then
        ui_info_box "SSL setup hoàn tất!" \
            "✅ Chứng chỉ SSL đã được cài đặt" \
            "✅ N8N đã được cập nhật cho HTTPS" \
            "🌐 Truy cập: https://$domain"
    else
        ui_status "warning" "SSL đã cấu hình nhưng có thể cần điều chỉnh"
    fi

    return 0
}

# Export main function
export -f setup_ssl_main