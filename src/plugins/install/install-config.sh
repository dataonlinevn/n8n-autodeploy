set -euo pipefail

collect_installation_configuration() {
    ui_section "CẤU HÌNH HỆ THỐNG"

    # Sử dụng các giá trị mặc định
    N8N_PORT=$N8N_DEFAULT_PORT
    POSTGRES_PORT=$POSTGRES_DEFAULT_PORT
    
    # Prompt for domain
    echo -e "${UI_CYAN}Gợi ý: Nếu bạn có tên miền, hệ thống sẽ tự động cấu hình bảo mật HTTPS.${UI_NC}"
    echo -e "${UI_CYAN}Nếu không, ứng dụng sẽ chạy qua địa chỉ IP của VPS.${UI_NC}"
    N8N_DOMAIN=$(ui_prompt "Nhập tên miền của bạn (để trống nếu không dùng)" "")
    
    if [[ -n "$N8N_DOMAIN" ]]; then
        if ! ui_validate_domain "$N8N_DOMAIN"; then
            ui_error "Tên miền không hợp lệ. Quy trình sẽ tiếp tục với địa chỉ IP."
            N8N_DOMAIN=""
        fi
    fi

    local public_ip=$(get_public_ip || echo "localhost")
    
    if [[ -n "$N8N_DOMAIN" ]]; then
        N8N_WEBHOOK_URL="https://$N8N_DOMAIN"
        # we'll use https protocol in env/config if domain is present
    else
        N8N_WEBHOOK_URL="http://$public_ip:$N8N_PORT"
    fi

    # Summary
    ui_info_box "TÓM TẮT THÔNG SỐ CÀI ĐẶT" \
        "Dịch vụ n8n:      Cổng $N8N_PORT" \
        "Dữ liệu:          PostgreSQL" \
        "Tên miền:         ${N8N_DOMAIN:-'[Sử dụng IP]'}" \
        "Địa chỉ truy cập: $N8N_WEBHOOK_URL"

    echo ""
    if ! ui_confirm "Bắt đầu cài đặt với cấu hình trên?"; then
        return 1
    fi

    return 0
}

export -f collect_installation_configuration
