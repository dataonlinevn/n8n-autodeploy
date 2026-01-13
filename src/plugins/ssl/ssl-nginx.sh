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

    # Step 1: Create webroot directory
    ui_run_command "Cấu hình Webroot directory" "
        mkdir -p $WEBROOT_PATH/.well-known/acme-challenge
        chown www-data:www-data $WEBROOT_PATH -R
        chmod 755 $WEBROOT_PATH -R
    " || return 1

    # Step 2: Create HTTP-only nginx config for certification
    ui_start_spinner "Đang thiết lập cấu hình máy chủ Nginx..."

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

    # Enable site
    ln -sf "$nginx_conf" /etc/nginx/sites-enabled/ 2>/dev/null || true
    
    # Test and reload nginx
    nginx -t >/dev/null 2>&1 || { ui_error "Cấu hình Nginx gặp lỗi"; return 1; }
    ui_run_command "Kích hoạt máy chủ" "systemctl reload nginx" || return 1

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

    ui_start_spinner "Đang kích hoạt chế độ bảo mật HTTPS..."

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

    # Enable site
    ln -sf "$nginx_conf" /etc/nginx/sites-enabled/ 2>/dev/null || true
    
    # Test and reload nginx
    nginx -t >/dev/null 2>&1 || { ui_error "Cấu hình HTTPS gặp lỗi"; return 1; }
    ui_run_command "Áp dụng cấu hình bảo mật" "systemctl reload nginx" || return 1

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
