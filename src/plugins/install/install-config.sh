set -euo pipefail

collect_installation_configuration() {
    ui_section "CẤU HÌNH HỆ THỐNG"

    # Sử dụng các giá trị mặc định
    N8N_PORT=$N8N_DEFAULT_PORT
    POSTGRES_PORT=$POSTGRES_DEFAULT_PORT
    
    # Hiển thị thông tin về hai tùy chọn cài đặt
    echo ""
    echo -e "${UI_BOLD}${UI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_NC}"
    echo -e "${UI_BOLD}${UI_WHITE}  CẤU HÌNH TRUY CẬP N8N${UI_NC}"
    echo -e "${UI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_NC}"
    echo ""
    echo -e "${UI_BOLD}${UI_WHITE}Bạn có thể chọn một trong hai cách để truy cập N8N:${UI_NC}"
    echo ""
    echo -e "${UI_GREEN}  ✓ TÙY CHỌN 1: Sử dụng TÊN MIỀN (Khuyến nghị)${UI_NC}"
    echo -e "    ${UI_GRAY}• Ví dụ: n8n.example.com${UI_NC}"
    echo -e "    ${UI_GRAY}• Tự động cài đặt chứng chỉ SSL (HTTPS)${UI_NC}"
    echo -e "    ${UI_GRAY}• Bảo mật cao, phù hợp cho môi trường production${UI_NC}"
    echo -e "    ${UI_GRAY}• Yêu cầu: Domain đã trỏ DNS về IP của server này${UI_NC}"
    echo ""
    echo -e "${UI_YELLOW}  ✓ TÙY CHỌN 2: Sử dụng ĐỊA CHỈ IP${UI_NC}"
    echo -e "    ${UI_GRAY}• Ví dụ: http://123.45.67.89:5678${UI_NC}"
    echo -e "    ${UI_GRAY}• Không cần tên miền, truy cập trực tiếp qua IP${UI_NC}"
    echo -e "    ${UI_GRAY}• Phù hợp cho môi trường test hoặc mạng nội bộ${UI_NC}"
    echo -e "    ${UI_GRAY}• Lưu ý: Không có SSL, dữ liệu truyền không mã hóa${UI_NC}"
    echo ""
    echo -e "${UI_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_NC}"
    echo ""
    
    # Prompt for domain với allow_empty=true
    N8N_DOMAIN=$(ui_prompt "Nhập tên miền của bạn (nhấn Enter để bỏ qua và dùng IP)" "" ".*" "Tên miền không hợp lệ" "true")
    
    if [[ -n "$N8N_DOMAIN" ]]; then
        if ! ui_validate_domain "$N8N_DOMAIN"; then
            ui_error "Tên miền không hợp lệ. Quy trình sẽ tiếp tục với địa chỉ IP."
            N8N_DOMAIN=""
        else
            # Ask for email if domain is present - Bắt buộc nhập
            N8N_SSL_EMAIL=$(ui_prompt "Email nhận thông báo bảo mật SSL (ví dụ: example@dataonline.vn)" "" "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "Email không hợp lệ" "false")
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
    local access_mode=""
    if [[ -n "$N8N_DOMAIN" ]]; then
        access_mode="${UI_GREEN}Tên miền (HTTPS)${UI_NC}"
    else
        access_mode="${UI_YELLOW}Địa chỉ IP (HTTP)${UI_NC}"
    fi
    
    echo ""
    ui_info_box "TÓM TẮT THÔNG SỐ CÀI ĐẶT" \
        "Chế độ truy cập:  $access_mode" \
        "Dịch vụ N8N:      Cổng $N8N_PORT" \
        "Cơ sở dữ liệu:    PostgreSQL (Cổng $POSTGRES_PORT)" \
        "Tên miền:         ${N8N_DOMAIN:-'[Không sử dụng]'}" \
        "Email SSL:        ${N8N_SSL_EMAIL:-'[Không áp dụng]'}" \
        "" \
        "${UI_BOLD}Địa chỉ truy cập:${UI_NC} $N8N_WEBHOOK_URL"

    echo ""
    if ! ui_confirm "Bắt đầu cài đặt với cấu hình trên?"; then
        return 1
    fi

    return 0
}

export -f collect_installation_configuration
