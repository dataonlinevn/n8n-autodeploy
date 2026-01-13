# Phiên bản: 1.0.1

[[ -n "${MAIN_INSTALL_LOADED:-}" ]] && return 0
readonly MAIN_INSTALL_LOADED=true

set -euo pipefail

INSTALL_PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$INSTALL_PLUGIN_DIR")")")"

if [[ -z "${LOGGER_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
fi
if [[ -z "${CONFIG_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
fi
if [[ -z "${UTILS_LOADED:-}" ]] ; then
    source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
fi
if [[ -z "${UI_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
fi
# Load SSL plugin for integrated setup
if [[ -d "$PLUGIN_PROJECT_ROOT/src/plugins/ssl" ]]; then
    # we source only main.sh to avoid side effects of sourcing all files
    # main.sh will handle its own sub-modules
    if [[ -f "$PLUGIN_PROJECT_ROOT/src/plugins/ssl/main.sh" ]]; then
        source "$PLUGIN_PROJECT_ROOT/src/plugins/ssl/main.sh"
    fi
fi

# Load sub-modules
source "$INSTALL_PLUGIN_DIR/install-requirements.sh"
source "$INSTALL_PLUGIN_DIR/install-config.sh"
source "$INSTALL_PLUGIN_DIR/install-compose.sh"
source "$INSTALL_PLUGIN_DIR/install-verify.sh"
source "$INSTALL_PLUGIN_DIR/install-uninstall.sh"

readonly INSTALL_DOCKER_COMPOSE_VERSION="2.24.5"
readonly REQUIRED_RAM_MB=2048
readonly REQUIRED_DISK_GB=10
readonly N8N_DEFAULT_PORT=5678
readonly POSTGRES_DEFAULT_PORT=5432

# Global variables
N8N_PORT=""
POSTGRES_PORT=""
N8N_DOMAIN=""
N8N_WEBHOOK_URL=""

# ===== MAIN INSTALLATION MENU =====

install_n8n_main() {
    ui_header "Quản lý Cài đặt"

    while true; do
        show_install_menu
        
        choice=$(ui_prompt "Chọn chức năng" "0" "^[0-2]$")

        case "$choice" in
        1) handle_n8n_installation ;;
        2) handle_n8n_uninstall ;;
        0) return 0 ;;
        *) ui_error "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
        ui_header "Quản lý Cài đặt"
    done
}

show_install_menu() {
    local n8n_status=$(check_n8n_installation_status)
    
    ui_section "Trạng thái Hệ thống"
    echo "Phần mềm: N8N"
    echo -e "Trạng thái: $n8n_status"
    echo ""
    
    echo "CÀI ĐẶT MỚI"
    echo "  1) Cài đặt n8n (Docker)"
    echo ""
    echo "QUẢN LÝ HỆ THỐNG"
    echo "  2) Gỡ cài đặt n8n"
    echo ""
    echo "  0) Quay lại"
    echo ""
}

check_n8n_installation_status() {
    if [[ -f "/opt/n8n/docker-compose.yml" ]] && docker ps --format '{{.Names}}' | grep -q "n8n"; then
        echo -e "${UI_GREEN}Đã cài đặt và đang chạy${UI_NC}"
    elif [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        echo -e "${UI_YELLOW}Đã cài đặt nhưng không chạy${UI_NC}"
    else
        echo -e "${UI_RED}Chưa cài đặt${UI_NC}"
    fi
}

# ===== INSTALLATION HANDLER =====

handle_n8n_installation() {
    ui_header "Cài đặt N8N với Docker"

    # Check for existing installation
    local clean_install=false
    if [[ -d "/opt/n8n" && -f "/opt/n8n/docker-compose.yml" ]]; then
        ui_warning_box "CẢNH BÁO CÀI ĐẶT LẠI" \
            "Phát hiện N8N đã có trên hệ thống." \
            "" \
            "1. Cài đặt lại (Giữ lại dữ liệu cũ)" \
            "2. Cài đặt mới hoàn toàn (XÓA HẾT DỮ LIỆU)"
            
        local re_choice=$(ui_prompt "Lựa chọn của bạn" "1" "^[1-2]$")
        
        if [[ "$re_choice" == "2" ]]; then
            if ui_confirm "Hành động này sẽ XÓA TOÀN BỘ dữ liệu n8n. Bạn chắc chắn chứ?"; then
                clean_install=true
            else
                return 0
            fi
        fi

        # Backup existing installation
        backup_existing_installation
        
        # Dừng các container đang chạy
        ui_start_spinner "Đang dừng các dịch vụ..."
        if [[ "$clean_install" == "true" ]]; then
            cd /opt/n8n && sudo docker compose down -v >/dev/null 2>&1 || true
        else
            cd /opt/n8n && sudo docker compose down >/dev/null 2>&1 || true
        fi
        ui_stop_spinner
    fi

    # Step 1: Configuration
    ui_info "Bước 1/4: Thiết lập cấu thông số"
    if ! collect_installation_configuration; then
        return 1
    fi

    # Step 2: Generate compose
    ui_info "Bước 2/4: Khởi tạo môi trường Docker"
    create_docker_compose || return 1

    # Step 3: Start stack
    ui_info "Bước 3/4: Kích hoạt ứng dụng và bảo mật"
    start_n8n_docker || return 1
    
    # Nếu có domain, thực hiện cài đặt SSL ngay tại đây
    if [[ -n "$N8N_DOMAIN" ]]; then
        ui_info "Phát hiện tên miền, đang tự động cấu hình SSL..."
        local ssl_email="admin@$N8N_DOMAIN" # Default email
        
        # Kiểm tra sự tồn tại của các hàm SSL
        if ! declare -F install_certbot >/dev/null; then
            ui_error "LỖI HỆ THỐNG: Không tìm thấy hàm install_certbot. Có thể do nạp module thất bại."
            return 1
        fi
        
        # Chạy các bước SSL và để hiện log nếu lỗi
        ui_info "Đang cài đặt Certbot..."
        install_certbot || { ui_error "Cài đặt Certbot thất bại"; return 1; }
        
        ui_info "Đang cấu hình Nginx tạm thời..."
        create_nginx_http_config "$N8N_DOMAIN" "$N8N_PORT" || { ui_error "Cấu hình Nginx HTTP thất bại"; return 1; }
        
        ui_info "Đang yêu cầu chứng chỉ SSL (Let's Encrypt)..."
        if obtain_ssl_certificate "$N8N_DOMAIN" "$ssl_email"; then
            ui_info "Đang nâng cấp Nginx lên HTTPS..."
            create_nginx_ssl_config "$N8N_DOMAIN" "$N8N_PORT" || { ui_error "Cấu hình Nginx SSL thất bại"; return 1; }
            
            ui_info "Đang thiết lập tự động gia hạn..."
            setup_auto_renewal || ui_warning "Không thể thiết lập gia hạn tự động"
            
            ui_success "Cấu hình bảo mật SSL thành công"
        else
            ui_warning "Không thể tự động kích hoạt SSL. Bạn có thể cài đặt sau."
        fi
    fi

    # Step 4: Verify
    ui_info "Bước 4/4: Xác minh cài đặt"
    if verify_installation; then
        ui_success "Cài đặt N8N thành công!"
        config_set "n8n.installed" "true"
        config_set "n8n.installed_date" "$(date +%Y-%m-%d)"
        
        # Hiển thị thông tin truy cập
        local access_url="$N8N_WEBHOOK_URL"
        
        echo ""
        ui_info_box "CÀI ĐẶT HOÀN TẤT" \
            "Địa chỉ truy cập: $access_url" \
            "Cơ sở dữ liệu: PostgreSQL" \
            "" \
            "Lưu ý: Nếu không thể truy cập, vui lòng kiểm tra" \
            "Firewall và đảm bảo các cổng 80/443 đã được mở."
            
        # Kiểm tra UFW
        if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "active"; then
            if ui_confirm "Phát hiện UFW đang bật. Bạn có muốn mở port $N8N_PORT không?"; then
                sudo ufw allow "$N8N_PORT"/tcp >/dev/null 2>&1
                ui_success "Đã mở port $N8N_PORT trên UFW"
            fi
        fi
        
        return 0
    else
        ui_error "Cài đặt thất bại" "INSTALL_FAILED" "Kiểm tra logs và thử lại"
        return 1
    fi
}

# Export entry
export -f install_n8n_main