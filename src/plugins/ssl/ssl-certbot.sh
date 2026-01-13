#!/bin/bash

# DataOnline N8N Manager - SSL Certbot Module
# Phiên bản: 1.0.0

set -euo pipefail

install_certbot() {
    if command_exists certbot; then
        ui_success "Công cụ Certbot đã sẵn sàng"
        return 0
    fi

    ui_run_command "Cài đặt Certbot" "
        apt update -qq
        apt install -y certbot python3-certbot-nginx -qq
    "
}

obtain_ssl_certificate() {
    local domain="$1"
    local email="$2"

    # Kiểm tra xem certificate đã tồn tại chưa
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        ui_info "Phát hiện chứng chỉ đã tồn tại cho tên miền $domain"
        
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
                ui_success "Chứng chỉ còn $days_remaining ngày, hệ thống sẽ sử dụng bản hiện có."
                return 0
            else
                ui_info "Chứng chỉ sắp hết hạn ($days_remaining ngày), đang tiến hành gia hạn..."
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
            ui_error "Lỗi: Đã vượt quá giới hạn đăng ký của Let's Encrypt"
            
            ui_warning_box "VƯỢT QUÁ GIỚI HẠN (RATE LIMIT)" \
                "Tên miền này đã đăng ký quá 5 lần trong tuần." \
                "Vui lòng đợi đến tuần sau để thử lại," \
                "hoặc sử dụng một tên miền phụ khác."
            
            if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
                ui_info "Hệ thống sẽ chuyển sang sử dụng bản chứng chỉ hiện có."
                return 0
            fi
            
            if ui_confirm "Bạn có muốn tạo chứng chỉ tạm thời (Self-signed) để sử dụng ngay không?"; then
                return create_self_signed_certificate "$domain"
            else
                return 1
            fi
        elif echo "$certbot_output" | grep -qi "already exists\|duplicate"; then
            ui_warning "Bản ghi chứng chỉ đã tồn tại cho tên miền này."
            if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
                ui_success "Đang sử dụng bản ghi hiện có."
                return 0
            fi
        else
            ui_error "Quá trình đăng ký gặp lỗi kỹ thuật"
            echo ""
            echo -e "${UI_YELLOW}Chi tiết lỗi:${UI_NC}"
            echo "$certbot_output" | tail -5
            echo ""
            ui_info " Vui lòng kiểm tra:"
            ui_info "   - Tên miền đã trỏ đúng về địa chỉ IP của VPS chưa?"
            ui_info "   - Cổng 80 đã được mở trên Firewall chưa?"
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
    
    ui_success "Hoàn tất tạo chứng chỉ tạm thời"
    
    ui_warning_box "LƯU Ý VỀ CHỨNG CHỈ TẠM THỜI" \
        "Trình duyệt sẽ hiển thị cảnh báo không an toàn." \
        "Kết nối HTTPS vẫn được mã hóa nhưng không được xác thực." \
        "Bạn nên nâng cấp lên Let's Encrypt sau 1 tuần."
        
    return 0
}

setup_auto_renewal() {
    # Enable certbot timer
    ui_run_command "Kích hoạt auto-renewal" "
        systemctl enable certbot.timer
        systemctl start certbot.timer
    " || return 1

    # Test renewal
    ui_run_command "Test renewal" "certbot renew --dry-run" || return 1

    # Create renewal hook
    local renewal_hook="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
    ui_run_command "Tạo renewal hook" "
        mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        cat > $renewal_hook << 'EOF'
#!/bin/bash
systemctl reload nginx
EOF
        chmod +x $renewal_hook
    " || return 1
}

export -f install_certbot obtain_ssl_certificate create_self_signed_certificate setup_auto_renewal
