#!/bin/bash

# DataOnline N8N Manager - SSL Certbot Module
# Phiên bản: 1.0.0

set -euo pipefail

install_certbot() {
    if command_exists certbot; then
        ui_success "Certbot đã cài đặt"
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

    # Kiểm tra xem certificate đã tồn tại chưa
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        ui_info "SSL certificate đã tồn tại cho domain $domain"
        
        # Kiểm tra ngày hết hạn
        local expiry_date
        expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$domain/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [[ -n "$expiry_date" ]]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
            local now_epoch
            now_epoch=$(date +%s)
            local days_remaining
            days_remaining=$(((expiry_epoch - now_epoch) / 86400))
            
            if [[ $days_remaining -gt 30 ]]; then
                ui_success "Certificate còn $days_remaining ngày, sử dụng certificate hiện có"
                return 0
            else
                ui_info "Certificate sắp hết hạn ($days_remaining ngày), đang gia hạn..."
            fi
        fi
    fi

    ui_start_spinner "Lấy chứng chỉ SSL từ Let's Encrypt"
    
    local certbot_output
    local certbot_exit_code=0
    
    # Không dùng --force-renewal để tránh rate limit, chỉ renew nếu cần
    certbot_output=$(certbot certonly --webroot \
        -w $WEBROOT_PATH \
        -d $domain \
        --agree-tos \
        --email $email \
        --non-interactive \
        --preferred-challenges http \
        --keep-until-expiring 2>&1) || certbot_exit_code=$?
    
    ui_stop_spinner
    
    if [[ $certbot_exit_code -ne 0 ]]; then
        if echo "$certbot_output" | grep -qi "too many certificates.*already issued\|rate limit"; then
            ui_error "Let's Encrypt rate limit exceeded" "LE_RATE_LIMIT"
            
            ui_warning_box "Rate Limit Exceeded" \
                "Domain đã vượt quá 5 certificates/tuần" \
                "Cần chờ đến tuần sau để thử lại" \
                "Hoặc sử dụng subdomain khác"
            
            # Nếu certificate đã tồn tại, sử dụng nó
            if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
                ui_info "Sử dụng certificate hiện có"
                return 0
            fi
            
            echo -n -e "${UI_YELLOW}Tạo self-signed certificate tạm thời? [Y/n]: ${UI_NC}"
            read -r use_self_signed
            
            if [[ ! "$use_self_signed" =~ ^[Nn]$ ]]; then
                return create_self_signed_certificate "$domain"
            else
                return 1
            fi
        elif echo "$certbot_output" | grep -qi "already exists\|duplicate"; then
            ui_warning "Certificate đã tồn tại cho domain này"
            if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
                ui_success "Sử dụng certificate hiện có"
                return 0
            fi
        else
            ui_error "Certbot failed" "CERTBOT_FAILED"
            echo ""
            echo -e "${UI_YELLOW}Chi tiết lỗi:${UI_NC}"
            echo "$certbot_output" | tail -10
            echo ""
            ui_info "💡 Kiểm tra:"
            ui_info "   • DNS đã trỏ về server này chưa?"
            ui_info "   • Port 80 đã mở và nginx đang chạy chưa?"
            ui_info "   • Domain có đang được sử dụng cho certificate khác không?"
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

    ui_success "Let's Encrypt certificate thành công"
    return 0
}

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
    
    ui_success "Self-signed certificate created"
    
    ui_warning_box "Self-Signed Certificate Warning" \
        "⚠️  Browser sẽ hiển thị cảnh báo security" \
        "✅ HTTPS vẫn hoạt động (với warning)" \
        "💡 Có thể thử Let's Encrypt lại sau 1 tuần"
        
    return 0
}

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

    ui_success "Auto-renewal đã được cấu hình"
}

export -f install_certbot obtain_ssl_certificate create_self_signed_certificate setup_auto_renewal
