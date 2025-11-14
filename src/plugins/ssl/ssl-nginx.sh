#!/bin/bash

# DataOnline N8N Manager - SSL Nginx Module
# Phiên bản: 1.0.0

set -euo pipefail

create_nginx_http_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    
    # Tìm file config hiện có dựa trên domain thực tế
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    # Nếu không tìm thấy, tìm tất cả file config có chứa domain trong tên
    if [[ ! -f "$nginx_conf" ]]; then
        local found_config
        found_config=$(sudo find /etc/nginx/sites-available -name "*${domain}*.conf" -type f 2>/dev/null | head -1)
        if [[ -n "$found_config" ]]; then
            nginx_conf="$found_config"
        fi
    fi

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

    sudo tee "$nginx_conf" > /dev/null <<'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root WEBROOT_PLACEHOLDER;
        allow all;
    }

    # Temporary: Proxy to N8N for testing
    location / {
        proxy_pass http://127.0.0.1:PORT_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        proxy_buffering off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }
}
NGINX_EOF
    
    # Replace placeholders
    sudo sed -i "s|DOMAIN_PLACEHOLDER|$domain|g" "$nginx_conf"
    sudo sed -i "s|WEBROOT_PLACEHOLDER|$WEBROOT_PATH|g" "$nginx_conf"
    sudo sed -i "s|PORT_PLACEHOLDER|$n8n_port|g" "$nginx_conf"

    ui_stop_spinner
    ui_success "HTTP config tạo thành công"

    # Step 3: Enable site
    if ! ui_run_command "Enable nginx site" "
        ln -sf $nginx_conf /etc/nginx/sites-enabled/
    "; then
        return 1
    fi

    # Step 4: Test nginx config
    if ! ui_run_command "Test nginx configuration" "nginx -t"; then
        ui_error "Nginx config có lỗi" "NGINX_CONFIG_ERROR" "Kiểm tra config"
        rm -f "/etc/nginx/sites-enabled/$(basename $nginx_conf)"
        return 1
    fi

    # Step 5: Reload nginx
    if ! ui_run_command "Reload nginx" "systemctl reload nginx"; then
        return 1
    fi

    ui_success "Nginx HTTP config hoạt động"
    return 0
}

create_nginx_ssl_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    
    # Tìm file config hiện có dựa trên domain thực tế
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    # Nếu không tìm thấy, tìm tất cả file config có chứa domain trong tên
    if [[ ! -f "$nginx_conf" ]]; then
        local found_config
        found_config=$(sudo find /etc/nginx/sites-available -name "*${domain}*.conf" -type f 2>/dev/null | head -1)
        if [[ -n "$found_config" ]]; then
            nginx_conf="$found_config"
        fi
    fi

    ui_section "Nâng cấp lên HTTPS config"

    # Verify SSL files exist
    if [[ ! -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        ui_error "SSL certificate không tồn tại" "CERT_NOT_FOUND"
        return 1
    fi

    ui_start_spinner "Tạo HTTPS config"

    sudo tee "$nginx_conf" > /dev/null <<'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location /.well-known/acme-challenge/ {
        root WEBROOT_PLACEHOLDER;
        allow all;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;

    ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;
    
    # Include Let's Encrypt options if available
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    client_max_body_size 100M;
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    access_log /var/log/nginx/DOMAIN_PLACEHOLDER.access.log;
    error_log /var/log/nginx/DOMAIN_PLACEHOLDER.error.log;

    location / {
        proxy_pass http://127.0.0.1:PORT_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }

    location ~ /\.
    {
        deny all;
    }
}
NGINX_EOF
    
    # Replace placeholders
    sudo sed -i "s|DOMAIN_PLACEHOLDER|$domain|g" "$nginx_conf"
    sudo sed -i "s|WEBROOT_PLACEHOLDER|$WEBROOT_PATH|g" "$nginx_conf"
    sudo sed -i "s|PORT_PLACEHOLDER|$n8n_port|g" "$nginx_conf"

    ui_stop_spinner

    # Test nginx config
    if ! ui_run_command "Test HTTPS configuration" "nginx -t"; then
        ui_error "HTTPS config có lỗi" "NGINX_HTTPS_ERROR"
        return 1
    fi

    # Reload nginx
    if ! ui_run_command "Reload nginx với HTTPS" "systemctl reload nginx"; then
        return 1
    fi

    ui_success "HTTPS config hoạt động"
    return 0
}

create_self_signed_nginx_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    cat >"$nginx_conf" <<'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;

    ssl_certificate /etc/ssl/self-signed/DOMAIN_PLACEHOLDER.crt;
    ssl_certificate_key /etc/ssl/self-signed/DOMAIN_PLACEHOLDER.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    client_max_body_size 100M;
    
    access_log /var/log/nginx/DOMAIN_PLACEHOLDER.access.log;
    error_log /var/log/nginx/DOMAIN_PLACEHOLDER.error.log;

    location / {
        proxy_pass http://127.0.0.1:PORT_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        
        proxy_buffering off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }
}
NGINX_EOF
    
    # Replace placeholders
    sed -i "s|DOMAIN_PLACEHOLDER|$domain|g" "$nginx_conf"
    sed -i "s|PORT_PLACEHOLDER|$n8n_port|g" "$nginx_conf"

    # Test and reload
    nginx -t && systemctl reload nginx
}

export -f create_nginx_http_config create_nginx_ssl_config create_self_signed_nginx_config
