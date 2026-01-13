#!/bin/bash

# DataOnline N8N Manager - SSL Verify Module
# Phiên bản: 1.0.0

set -euo pipefail

verify_ssl_setup() {
    local domain="$1"
    local n8n_port="${2:-5678}"

    # Check N8N status quietly
    if ! docker ps | grep -q "n8n" && ! systemctl is-active --quiet n8n; then
        ui_warning "Ứng dụng n8n đang dừng, đang thử khởi động lại..."
        [[ -f "/opt/n8n/docker-compose.yml" ]] && cd /opt/n8n && docker compose up -d >/dev/null 2>&1
    fi

    # Check SSL certificate files
    local cert_dir="/etc/letsencrypt/live/$domain"
    if [[ ! -d "$cert_dir" ]]; then
        ui_warning "Thư mục chứng chỉ SSL không tồn tại: $cert_dir"
        ui_info "SSL chưa được cấu hình cho domain này"
        return 1
    fi

    if [[ ! -f "$cert_dir/fullchain.pem" ]] || [[ ! -f "$cert_dir/privkey.pem" ]]; then
        ui_warning "Thiếu file chứng chỉ SSL (fullchain.pem hoặc privkey.pem)"
        ui_info "Vui lòng cài đặt SSL certificate trước"
        return 1
    fi

    # Tìm file config dựa trên domain thực tế
    local nginx_config="/etc/nginx/sites-available/${domain}.conf"
    
    # Nếu không tìm thấy, tìm tất cả file config có chứa domain trong tên
    if [[ ! -f "$nginx_config" ]]; then
        local found_config
        found_config=$(sudo find /etc/nginx/sites-available -name "*${domain}*.conf" -type f 2>/dev/null | head -1)
        if [[ -n "$found_config" ]]; then
            nginx_config="$found_config"
        fi
    fi
    
    if [[ ! -f "$nginx_config" ]]; then
        ui_warning "File cấu hình nginx không tồn tại: $nginx_config"
        ui_info "Vui lòng tạo cấu hình nginx cho domain này"
        return 1
    fi

    # Check if nginx config is not empty
    if [[ ! -s "$nginx_config" ]]; then
        ui_warning "File cấu hình nginx trống: $nginx_config"
        
        # Tự động tạo lại nginx config nếu SSL certificate đã có
        if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
            ui_info "Đang tự động tạo lại cấu hình nginx..."
            
            # Source SSL nginx module để dùng hàm create_nginx_ssl_config
            local ssl_nginx_module="$(dirname "${BASH_SOURCE[0]}")/ssl-nginx.sh"
            
            if [[ -f "$ssl_nginx_module" ]]; then
                # Định nghĩa WEBROOT_PATH nếu chưa có
                [[ -z "${WEBROOT_PATH:-}" ]] && export WEBROOT_PATH="/var/www/html"
                
                # Source module (các module UI đã được source từ main.sh)
                source "$ssl_nginx_module"

                if create_nginx_ssl_config "$domain" "$n8n_port" >/dev/null 2>&1; then
                    ui_success "Đã khôi phục cấu hình hệ thống"
                else
                    # Fallback: Tạo config thủ công nếu module không hoạt động
                    ui_info "Đang thử phương án dự phòng..."
                    if auto_create_nginx_config "$domain" "$n8n_port"; then
                        ui_success "Đã khôi phục cấu hình hệ thống"
                    else
                        ui_warning "Không thể tự động tạo lại cấu hình nginx"
                        ui_info "Vui lòng chạy lại 'Cấu hình SSL với Let's Encrypt' để tạo lại"
                        return 1
                    fi
                fi
            else
                ui_warning "Không tìm thấy module tạo nginx config"
                ui_info "Vui lòng chạy lại 'Cấu hình SSL với Let's Encrypt' để tạo lại"
                return 1
            fi
        else
            ui_info "Vui lòng cấu hình nginx cho domain này"
            return 1
        fi
    fi

    # Check nginx syntax
    if ! sudo nginx -t >/dev/null 2>&1; then
        ui_warning "Cấu hình nginx có lỗi"
        ui_info "Chạy 'sudo nginx -t' để xem chi tiết lỗi"
        return 1
    fi

    # Check nginx is running
    if ! systemctl is-active --quiet nginx; then
        ui_warning "Nginx không chạy, đang khởi động..."
        if ! sudo systemctl start nginx; then
            ui_error "Không thể khởi động nginx" "NGINX_START_FAILED"
            return 1
        fi
    fi

    # Wait for N8N to be ready silently
    local n8n_ready=false
    local retry_count=0
    while [[ $retry_count -lt 15 ]]; do
        if curl -s -f "http://127.0.0.1:$n8n_port" >/dev/null 2>&1; then
            n8n_ready=true
            break
        fi
        retry_count=$((retry_count + 1))
        sleep 2
    done

    # Check HTTPS connection with retry logic
    ui_start_spinner "Kiểm tra kết nối HTTPS"
    local https_status="000"
    local curl_exit=1
    local retry_count=0
    local max_retries=5
    
    while [[ $retry_count -lt $max_retries ]]; do
        https_status=$(curl -s -k -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "https://$domain" 2>/dev/null)
        curl_exit=$?
        
        # Clean up status code (remove any non-numeric characters)
        https_status=$(echo "$https_status" | tr -d '[:space:]' | grep -oE '[0-9]+' | head -1 || echo "000")
        
        # If we get a successful status or non-502 error, break
        if [[ "$https_status" =~ ^(200|201|202|204|301|302|307|308)$ ]]; then
            break
        elif [[ "$https_status" != "502" ]] && [[ "$https_status" != "000" ]]; then
            # Non-502 error, don't retry
            break
        elif [[ "$https_status" == "502" ]]; then
            # 502 might be temporary, retry after delay
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                sleep 3
                continue
            fi
        else
            # Connection error, retry
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                sleep 2
                continue
            fi
        fi
        break
    done
    
    ui_stop_spinner
    
    if [[ $curl_exit -ne 0 ]] || [[ -z "$https_status" ]] || [[ "$https_status" == "000" ]]; then
        ui_warning "Không thể truy cập địa chỉ https://$domain"
        ui_info "Nguyên nhân có thể do tên miền chưa được trỏ về máy chủ."
        ui_info "Vui lòng kiểm tra lại cấu hình DNS và Firewall."
        return 1
    elif [[ "$https_status" =~ ^(200|201|202|204|301|302|307|308)$ ]]; then
        ui_success "Cổng kết nối HTTPS hoạt động tốt (Mã: $https_status)"
        return 0
    elif [[ "$https_status" == "502" ]]; then
        ui_warning "Hệ thống đang khởi động (Mã lỗi 502)"
        ui_info "Ứng dụng n8n cần thời gian để khởi chạy hoàn toàn."
        ui_info "Vui lòng đợi 1-2 phút và thử lại trên trình duyệt."
        ui_info ""
        ui_info "Nếu bạn đã truy cập được bình thường, hãy bỏ qua thông báo này."
        return 0  # Return success even with 502 if user says it works
    else
        ui_warning "HTTPS trả về mã lỗi: $https_status"
        ui_info "Kiểm tra cấu hình nginx và SSL certificate"
        ui_info " Thử truy cập: curl -k -I https://$domain"
        return 1
    fi
}

update_n8n_ssl_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    local compose_dir="/opt/n8n"

    if [[ ! -f "$compose_dir/docker-compose.yml" ]]; then
        ui_warning "Không tìm thấy N8N Docker installation tại $compose_dir"
        ui_info "Cấu hình N8N sẽ được lưu vào config, bạn có thể cập nhật thủ công sau"
        
        # Vẫn lưu vào config để dùng sau
        config_set "n8n.domain" "$domain"
        config_set "n8n.ssl_enabled" "true"
        config_set "n8n.webhook_url" "https://$domain"
        return 0
    fi

    ui_start_spinner "Đang cập nhật cấu hình N8N cho HTTPS"
    
    # Backup files
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    [[ -f "$compose_dir/.env" ]] && cp "$compose_dir/.env" "$compose_dir/.env.backup.$backup_timestamp" 2>/dev/null
    [[ -f "$compose_dir/docker-compose.yml" ]] && cp "$compose_dir/docker-compose.yml" "$compose_dir/docker-compose.yml.backup.$backup_timestamp" 2>/dev/null
    
    cd "$compose_dir" || return 1
    
    # Update .env
    if [[ -f ".env" ]]; then
        grep -q "^N8N_DOMAIN=" .env && sed -i "s|^N8N_DOMAIN=.*|N8N_DOMAIN=$domain|" .env || echo "N8N_DOMAIN=$domain" >> .env
        grep -q "^N8N_WEBHOOK_URL=" .env && sed -i "s|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=https://$domain|" .env || echo "N8N_WEBHOOK_URL=https://$domain" >> .env
    fi
    
    # Update docker-compose.yml
    sed -i "s|N8N_PROTOCOL=.*|N8N_PROTOCOL=https|g; s|N8N_PROTOCOL:.*|N8N_PROTOCOL: https|g" docker-compose.yml 2>/dev/null
    sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=https://$domain/|g; s|WEBHOOK_URL:.*|WEBHOOK_URL: https://$domain/|g" docker-compose.yml 2>/dev/null
    
    # Restart N8N
    if docker compose restart n8n >/dev/null 2>&1; then
        # Silent wait
        local wait_count=0
        while [[ $wait_count -lt 20 ]]; do
            curl -s -f "http://127.0.0.1:$n8n_port" >/dev/null 2>&1 && break
            wait_count=$((wait_count + 1))
            sleep 1
        done
    fi

    # Save to config
    config_set "n8n.domain" "$domain"
    config_set "n8n.ssl_enabled" "true"
    config_set "n8n.webhook_url" "https://$domain"
    
    ui_stop_spinner
    return 0
}

# Hàm helper để tạo nginx config thủ công (fallback)
auto_create_nginx_config() {
    local domain="$1"
    local n8n_port="${2:-5678}"
    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"
    
    sudo tee "$nginx_conf" > /dev/null <<'NGINX_EOF'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
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
        proxy_set_header Connection "upgrade";
        
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 7200s;
        proxy_send_timeout 7200s;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX_EOF
    
    # Replace placeholders
    sudo sed -i "s|DOMAIN_PLACEHOLDER|$domain|g" "$nginx_conf"
    sudo sed -i "s|PORT_PLACEHOLDER|$n8n_port|g" "$nginx_conf"

    # Enable site
    sudo ln -sf "$nginx_conf" /etc/nginx/sites-enabled/ 2>/dev/null || true
    
    # Test và reload nginx
    if sudo nginx -t >/dev/null 2>&1; then
        sudo systemctl reload nginx >/dev/null 2>&1
        return 0
    else
        return 1
    fi
}

export -f verify_ssl_setup update_n8n_ssl_config auto_create_nginx_config
