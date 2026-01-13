#!/bin/bash

# DataOnline N8N Manager - Google Drive Backup Integration
# Phiên bản: 1.0.0
# Mô tả: Google Drive integration cho backup operations (Sử dụng SSH Port Forwarding)

set -euo pipefail

save_token_json_to_remote() {
    local remote_name="$1"
    local token_json="$2"

    if [[ -z "${token_json// }" ]]; then
        ui_error "Token JSON trong" "TOKEN_JSON_EMPTY"
        return 1
    fi

    # Trich xuat va lam sach JSON (dam bao 1 dong duy nhat, không co khoang trang thua)
    local compact_token
    compact_token=$(echo "$token_json" | jq -c '.' 2>/dev/null | tr -d '\r\n') || \
    compact_token=$(echo "$token_json" | grep -o '{.*}' | tr -d '\r\n')
    
    if [[ -z "$compact_token" ]]; then
        ui_error "Token JSON khong hop le" "TOKEN_JSON_INVALID"
        return 1
    fi

    ui_info "Đang lưu cấu hình vào remote '$remote_name'..."
    
    # Đảm bảo thư mục config tồn tại
    local config_dir="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
    config_dir=$(dirname "$config_dir")
    mkdir -p "$config_dir" 2>/dev/null || true
    
    # Đảm bảo remote tồn tại trước khi cập nhật
    if ! rclone config show "$remote_name" >/dev/null 2>&1; then
        rclone config create "$remote_name" drive --non-interactive >/dev/null 2>&1 || true
    fi

    # Phương pháp 1: Sử dụng rclone config update với cú pháp đúng
    if rclone config update "$remote_name" token "$compact_token" --non-interactive 2>/dev/null; then
        if rclone config show "$remote_name" 2>/dev/null | grep -qE "token\\s*="; then
            chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
            ui_success "Lưu cấu hình thành công"
            save_gdrive_remote_name "$remote_name"
            return 0
        fi
    fi

    # Phương pháp 2: Ghi trực tiếp vào file rclone.conf
    local rclone_config_file="${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
    
    # Xóa section cũ nếu có
    if [[ -f "$rclone_config_file" ]]; then
        sed -i "/^\[$remote_name\]/,/^\[/{ /^\[/!d; /^\[$remote_name\]/d }" "$rclone_config_file" 2>/dev/null || true
    fi
    
    # Tạo section mới
    {
        echo ""
        echo "[$remote_name]"
        echo "type = drive"
        echo "token = $compact_token"
        echo "team_drive = "
    } >> "$rclone_config_file"
    
    chmod 600 "$rclone_config_file" 2>/dev/null || true
    
    # Kiểm tra lại
    if rclone config show "$remote_name" 2>/dev/null | grep -qE "token\\s*="; then
        ui_success "Lưu cấu hình thành công"
        save_gdrive_remote_name "$remote_name"
        return 0
    fi

    ui_error "Khong thể luu token. Vui long kiem tra file rclone.conf" "TOKEN_SAVE_FAILED"
    return 1
}

# Xóa cấu hình Google Drive khỏi rclone
remove_google_drive_remote() {
    local remote_name="${1:-}"

    if [[ -z "$remote_name" ]]; then
        if ! remote_name=$(get_gdrive_remote_name); then
            ui_warning "Không tìm thấy remote Google Drive để xóa"
            return 1
        fi
    fi

    ui_warning_box "Xóa cấu hình Google Drive" \
        "Tên Remote: $remote_name" \
        "Hành động này sẽ xóa mã truy cập (token) khỏi VPS" \
        "Các bản sao lưu đã có trên Google Drive vẫn được giữ nguyên"

    if ! ui_confirm "Bạn chắc chắn muốn xóa cấu hình này?"; then
        ui_info "Đã hủy thao tác xóa"
        return 1
    fi

    if rclone config show "$remote_name" >/dev/null 2>&1; then
        if rclone config delete "$remote_name" >/dev/null 2>&1; then
            ui_success "Da xoa remote '$remote_name' khoi rclone"
        else
            ui_error "Không thể xóa remote '$remote_name'" "RCLONE_DELETE_FAILED" "Kiểm tra permissions hoặc file rclone.conf"
            return 1
        fi
    else
        ui_warning "Remote '$remote_name' không tồn tại trong rclone config"
    fi

    save_gdrive_remote_name ""
    return 0
}




# ===== GOOGLE DRIVE SETUP =====

# Cau hinh Google Drive
setup_google_drive() {
    ui_section "Cấu hình Sao lưu Google Drive"
    
    # Cài đặt rclone nếu chưa có
    if ! command_exists rclone; then
        ui_info "Đang cài đặt công cụ rclone..."
        if ! curl -fsSL https://rclone.org/install.sh | sudo bash; then
            ui_error "Không thể cài đặt rclone"
            return 1
        fi
    fi
    
    # Kiểm tra cấu hình hiện tại
    local existing_remote=""
    if [[ -f "$RCLONE_CONFIG" ]]; then
        existing_remote=$(get_gdrive_remote_name || echo "")
    fi
    
    if [[ -n "$existing_remote" ]]; then
        ui_success "Google Drive đã được cấu hình (remote: $existing_remote)"
        ui_info_box "Lựa chọn thao tác" \
            "1) Giữ nguyên cấu hình hiện tại" \
            "2) Cấu hình lại / Cập nhật mã truy cập" \
            "3) Xóa cấu hình Google Drive"

        local existing_choice
        read -p "Lựa chọn [1-3] (Mặc định = 1): " existing_choice
        existing_choice="${existing_choice:-1}"

        case "$existing_choice" in
            1)
                save_gdrive_remote_name "$existing_remote"
                return 0
                ;;
            2)
                ui_info "Bắt đầu quy trình cấu hình lại..."
                ;;
            3)
                if remove_google_drive_remote "$existing_remote"; then
                    if ui_confirm "Bạn có muốn thiết lập cấu hình mới ngay không?"; then
                        existing_remote=""
                    else
                        return 0
                    fi
                else
                    return 1
                fi
                ;;
            *)
                save_gdrive_remote_name "$existing_remote"
                return 0
                ;;
        esac
    fi

    ui_info "Khởi tạo kết nối Google Drive..."
    local remote_name="gdrive"
    setup_google_drive_ssh_port_forward "$remote_name"
}

# Setup Google Drive với SSH Port Forwarding
setup_google_drive_ssh_port_forward() {
    local remote_name="$1"
    local RCLONE_AUTH_PORT="${RCLONE_AUTH_PORT:-53682}"
    
    ui_section "Kết nối Google Drive (SSH Tunnel)"
    
    # 1. Tự động dọn dẹp port
    ui_info "Đang chuẩn bị cổng kết nối $RCLONE_AUTH_PORT..."
    local existing_pid=$(lsof -t -i:"$RCLONE_AUTH_PORT" 2>/dev/null || true)
    if [[ -n "$existing_pid" ]]; then
        kill -9 $existing_pid 2>/dev/null || true
        sleep 1
    fi

    # 2. Hướng dẫn Tunnel
    echo ""
    ui_info_box "HƯỚNG DẪN THIẾT LẬP KẾT NỐI (SSH TUNNEL)" \
        "Để xác thực thành công, bạn CẦN thực hiện các bước sau:" \
        "1. Mở một cửa sổ Terminal MỚI trên máy tính của bạn (Laptop/PC)" \
        "2. Copy và chạy lệnh sau để thiết lập đường truyền bảo mật:" \
        "   ssh -L ${RCLONE_AUTH_PORT}:127.0.0.1:${RCLONE_AUTH_PORT} user@$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'server-ip')" \
        "3. GIỮ NGUYÊN terminal đó cho đến khi hoàn tất"
    echo ""
    
    if ! ui_confirm "Bạn đã sẵn sàng và thiết lập đường truyền chưa?"; then
        return 1
    fi
    
    # Khởi tạo remote
    if ! rclone config show "$remote_name" >/dev/null 2>&1; then
        rclone config create "$remote_name" drive --non-interactive >/dev/null 2>&1 || true
    fi
    
    echo ""
    ui_info_box "HƯỚNG DẪN XÁC THỰC" \
        "1. Hệ thống sẽ hiển thị một đường dẫn (URL) bên dưới" \
        "2. Copy và mở link này trên trình duyệt máy tính của bạn" \
        "3. Đăng nhập Google và nhấn 'Cho phép' (Allow)" \
        "4. Quay lại đây sau khi trình duyệt báo 'Success!'"
    echo ""
    
    read -p "Nhấn Enter để lấy liên kết xác thực..."
    echo ""
    
    ui_info "Vui lòng truy cập đường dẫn sau:"
    echo ""
    echo "-----------------------------------------------------------"
    
    local auth_output_file=$(mktemp)
    local auth_success=false
    
    # Chay rclone authorize
    if rclone authorize "drive" --auth-no-open-browser 2>&1 | tee "$auth_output_file"; then
        auth_success=true
    fi
    
    echo "-----------------------------------------------------------"
    echo ""
    
    if [[ "$auth_success" == "true" ]]; then
        ui_info "Đang xử lý mã truy cập..."
        local token_json=""
        if [[ -f "$auth_output_file" ]]; then
            token_json=$(sed -n '/--->/,/<---/p' "$auth_output_file" | grep "{" | head -1 | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
            
            if [[ -z "$token_json" ]]; then
                token_json=$(grep -oE '\{"access_token":[^\}]+\}' "$auth_output_file" | head -1 | tr -d '\r\n' || echo "")
            fi
        fi
        
        if [[ -n "$token_json" ]]; then
            if save_token_json_to_remote "$remote_name" "$token_json"; then
                rm -f "$auth_output_file" 2>/dev/null || true
                ui_success "Cấu hình Google Drive thành công!"
                return 0
            fi
        else
            ui_warning "Không thể tự động lấy mã truy cập"
            echo ""
            ui_info "Vui lòng copy đoạn mã (JSON token) hiển thị ở trên và dán vào đây:"
            read -r manual_token
            if [[ -n "$manual_token" ]]; then
                if save_token_json_to_remote "$remote_name" "$manual_token"; then
                    rm -f "$auth_output_file" 2>/dev/null || true
                    ui_success "Cấu hình Google Drive thành công!"
                    return 0
                fi
            fi
        fi
    fi
    
    rm -f "$auth_output_file" 2>/dev/null || true
    ui_error "Xác thực thất bại" "SSH_FORWARD_AUTH_FAILED" "Kiểm tra lại đường truyền Tunnel và thử lại"
    return 1
}
# Upload backup lên Google Drive 
upload_to_gdrive() {
    local backup_file="$1"
    
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        ui_error "Chưa cấu hình Google Drive"
        return 1
    fi
    
    # Auto-detect remote name
    local remote_name
    if ! remote_name=$(get_gdrive_remote_name); then
        ui_error "Không tìm thấy cấu hình Google Drive"
        return 1
    fi
    
    ui_info "Đang tải bản sao lưu lên Google Drive (remote: $remote_name)..."
    
    if rclone copy "$backup_file" "${remote_name}:n8n-backups/" --progress; then
        ui_success "Tải lên thành công"
        return 0
    else
        ui_error "Tải lên thất bại"
        return 1
    fi
}

# Export functions
export -f setup_google_drive upload_to_gdrive remove_google_drive_remote
