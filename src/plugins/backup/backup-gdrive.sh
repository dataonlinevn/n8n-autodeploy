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
        "Remote: $remote_name" \
        "Hành động này sẽ xóa token khỏi file rclone.conf trên VPS" \
        "Các backup đã upload trên Google Drive vẫn được giữ nguyên"

    if ! ui_confirm "Bạn chắc chắn muốn xóa remote này?"; then
        ui_info "Đã hủy thao tác xóa remote"
        return 1
    fi

    if rclone config show "$remote_name" >/dev/null 2>&1; then
        if rclone config delete "$remote_name" >/dev/null 2>&1; then
            ui_success "✅ Đã xóa remote '$remote_name' khỏi rclone"
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

#!/bin/bash

# DataOnline N8N Manager - Google Drive Backup Integration
# Phiên bản: 1.0.0
# Mô tả: Google Drive integration cho backup operations

set -euo pipefail

# ===== HELPER FUNCTIONS =====

# Kiểm tra môi trường headless (không có GUI)
is_headless_environment() {
    # Kiểm tra DISPLAY variable
    if [[ -z "${DISPLAY:-}" ]]; then
        return 0  # Headless
    fi
    
    # Kiểm tra xdg-open có tồn tại không
    if ! command_exists xdg-open; then
        return 0  # Headless
    fi
    
    # Kiểm tra có X11 không
    if ! command_exists xset; then
        return 0  # Headless
    fi
    
    return 1  # Có GUI
}

# Lưu token JSON vào remote chỉ định
save_token_json_to_remote() {
    local remote_name="$1"
    local token_json="$2"

    if [[ -z "${token_json// }" ]]; then
        ui_error "Token JSON trống" "TOKEN_JSON_EMPTY" "Chạy lại rclone authorize và dán lại token"
        return 1
    fi

    if ! command_exists jq; then
        ui_error "Thiếu jq để xử lý token" "JQ_NOT_FOUND" "Cài jq rồi chạy lại"
        return 1
    fi

    if ! echo "$token_json" | jq -e . >/dev/null 2>&1; then
        ui_error "Token JSON không hợp lệ" "TOKEN_JSON_INVALID" "Đảm bảo copy đầy đủ từ { đến }"
        return 1
    fi

    local compact_token
    compact_token=$(echo "$token_json" | jq -c '.')

    mkdir -p "$(dirname "$RCLONE_CONFIG")" 2>/dev/null || true
    touch "$RCLONE_CONFIG"

    if ! grep -q "^\[$remote_name\]" "$RCLONE_CONFIG"; then
        cat >> "$RCLONE_CONFIG" <<EOF

[$remote_name]
type = drive
EOF
    fi

    local config_backup="${RCLONE_CONFIG}.backup.$(date +%s)"
    cp "$RCLONE_CONFIG" "$config_backup" 2>/dev/null || true

    local rclone_err_file
    rclone_err_file=$(mktemp)
    if rclone --config "$RCLONE_CONFIG" config update "$remote_name" token "$compact_token" >/dev/null 2> "$rclone_err_file"; then
        rm -f "$rclone_err_file" 2>/dev/null || true
        chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
        ui_success "✅ Đã lưu token vào remote '$remote_name'"
        return 0
    else
        local rclone_err=""
        if [[ -s "$rclone_err_file" ]]; then
            rclone_err=$(cat "$rclone_err_file")
        fi
        rm -f "$rclone_err_file" 2>/dev/null || true
        if [[ -n "$rclone_err" ]]; then
            ui_warning "Không thể cập nhật token bằng rclone: $rclone_err"
        else
            ui_warning "Không thể cập nhật token bằng rclone (lệnh trả về lỗi)"
        fi
    fi

    if write_token_directly_to_config "$remote_name" "$compact_token"; then
        chmod 600 "$RCLONE_CONFIG" 2>/dev/null || true
        ui_success "✅ Đã lưu token vào remote '$remote_name' (ghi trực tiếp)"
        return 0
    fi

    ui_error "Không thể cập nhật token cho remote '$remote_name'" "TOKEN_SAVE_FAILED"
    return 1
}

write_token_directly_to_config() {
    local remote_name="$1"
    local compact_token="$2"

    local temp_config
    temp_config=$(mktemp)
    local in_section=false
    local token_written=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^\[$remote_name\] ]]; then
            in_section=true
            echo "$line" >> "$temp_config"
            continue
        fi

        if [[ "$in_section" == "true" && "$line" =~ ^\[ ]]; then
            if [[ "$token_written" == "false" ]]; then
                echo "token = $compact_token" >> "$temp_config"
                token_written=true
            fi
            in_section=false
        fi

        if [[ "$in_section" == "true" && "$line" =~ ^token[[:space:]]*= ]]; then
            continue
        fi

        echo "$line" >> "$temp_config"

        if [[ "$in_section" == "true" && "$line" =~ ^type[[:space:]]*=[[:space:]]*drive && "$token_written" == "false" ]]; then
            echo "token = $compact_token" >> "$temp_config"
            token_written=true
        fi
    done < "$RCLONE_CONFIG"

    if [[ "$in_section" == "true" && "$token_written" == "false" ]]; then
        echo "token = $compact_token" >> "$temp_config"
    fi

    if ! grep -q "^\[$remote_name\]" "$temp_config"; then
        {
            echo ""
            echo "[$remote_name]"
            echo "type = drive"
            echo "token = $compact_token"
        } >> "$temp_config"
    fi

    mv "$temp_config" "$RCLONE_CONFIG"
    return 0
}

# Hướng dẫn người dùng authorize trên máy local rồi dán token
setup_google_drive_local_manual_authorize() {
    local remote_name="$1"

    ui_section "Authorize Google Drive trên máy LOCAL"
    ui_info_box "Cách thực hiện" \
        "1. Trên máy cá nhân, cài đặt rclone (https://rclone.org/downloads/)" \
        "2. Mở terminal/PowerShell và chạy: rclone authorize \"drive\"" \
        "   - Windows: .\\rclone.exe authorize \"drive\"" \
        "3. Trình duyệt trên máy bạn sẽ mở, đăng nhập Google và chấp thuận" \
        "4. Rclone sẽ in JSON token (dạng {\"access_token\":...})" \
        "5. Copy toàn bộ JSON token rồi dán vào đây"

    echo ""
    if ! ui_confirm "Bạn đã đọc kỹ hướng dẫn và sẵn sàng thực hiện?"; then
        ui_warning "Đã hủy authorize trên máy local"
        return 1
    fi

    echo ""
    ui_info "⏳ Chờ bạn chạy rclone authorize trên máy local..."
    read -p "Nhấn Enter sau khi đã copy JSON token..." _
    echo ""
    echo -e "${UI_CYAN}Dán token JSON (một dòng, bắt đầu bằng { và kết thúc bằng }):${UI_NC}"
    read -r token_json

    if save_token_json_to_remote "$remote_name" "$token_json"; then
        return 0
    fi

    return 1
}

# ===== GOOGLE DRIVE SETUP =====

# Cấu hình Google Drive
setup_google_drive() {
    ui_section "Cấu hình Google Drive Backup"
    
    # Cài đặt rclone nếu chưa có
    if ! command_exists rclone; then
        ui_info "Cài đặt rclone..."
        if ! curl -fsSL https://rclone.org/install.sh | sudo bash; then
            ui_error "Không thể cài đặt rclone" "RCLONE_INSTALL_FAILED" "Kiểm tra internet connection"
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
        ui_info_box "Chọn thao tác" \
            "1) Giữ nguyên cấu hình hiện tại" \
            "2) Cấu hình lại / cập nhật token" \
            "3) Xóa cấu hình Google Drive khỏi rclone"

        local existing_choice
        read -p "Lựa chọn [1-3] (Enter = 1): " existing_choice
        existing_choice="${existing_choice:-1}"

        case "$existing_choice" in
            1)
                save_gdrive_remote_name "$existing_remote"
                ui_info "Giữ nguyên cấu hình hiện tại"
                return 0
                ;;
            2)
                ui_info "Tiếp tục quy trình cấu hình lại Google Drive..."
                ;;
            3)
                if remove_google_drive_remote "$existing_remote"; then
                    if ui_confirm "Bạn có muốn cấu hình remote Google Drive mới ngay bây giờ không?"; then
                        ui_info "Tiếp tục cấu hình remote mới..."
                        existing_remote=""
                    else
                        ui_info "Bạn có thể chạy lại chức năng này khi cần cấu hình lại."
                        return 0
                    fi
                else
                    ui_warning "Không thể xóa remote hiện tại"
                    return 1
                fi
                ;;
            *)
                ui_warning "Lựa chọn không hợp lệ, giữ nguyên cấu hình hiện tại"
                save_gdrive_remote_name "$existing_remote"
                return 0
                ;;
        esac
    fi
    
    # Detect headless environment
    local is_headless=false
    if is_headless_environment; then
        is_headless=true
        ui_info "🌐 Phát hiện môi trường headless (không có GUI)"
        ui_info "💡 Sẽ sử dụng phương pháp headless authentication"
    fi
    
    echo ""
    ui_info "Bắt đầu cấu hình Google Drive với rclone..."
    echo ""
    
    # Hỏi tên remote
    echo -n -e "${UI_WHITE}Nhập tên remote (Enter để dùng 'gdrive'): ${UI_NC}"
    read -r remote_name_input
    remote_name_input=${remote_name_input:-gdrive}
    
    if [[ "$is_headless" == "true" ]]; then
        setup_google_drive_headless "$remote_name_input"
    else
        setup_google_drive_interactive "$remote_name_input"
    fi
}

# Setup Google Drive với headless mode
setup_google_drive_headless() {
    local remote_name="$1"
    
    ui_section "Cấu hình Google Drive (Headless Mode)"
    
    echo ""
    ui_info_box "Hướng dẫn cấu hình Headless" \
        "1. Script sẽ tạo remote và lấy authorization URL" \
        "2. Bạn cần copy URL và mở trên máy có browser" \
        "3. Login Google và authorize" \
        "4. Copy code từ URL và paste vào đây" \
        "" \
        "💡 URL sẽ có dạng: http://127.0.0.1:xxxxx/?code=4/0Axxx..." \
        "💡 Chỉ copy phần code (sau code= và trước &)"
    echo ""
    
    if ! ui_confirm "Bạn đã hiểu và sẵn sàng tiếp tục?"; then
        return 1
    fi
    
    echo ""
    ui_info "Bước 1: Kiểm tra và tạo remote '$remote_name'..."
    
    # Kiểm tra remote đã tồn tại chưa
    local remote_exists=false
    local existing_type=""
    
    if rclone config show "$remote_name" >/dev/null 2>&1; then
        remote_exists=true
        existing_type=$(rclone config show "$remote_name" 2>/dev/null | grep -E "^type\s*=" | cut -d'=' -f2 | tr -d ' ' || echo "")
        
        if [[ "$existing_type" == "drive" ]]; then
            ui_success "Remote '$remote_name' đã tồn tại và đúng type (drive)"
            if ! ui_confirm "Bạn muốn sử dụng remote hiện tại hay tạo lại?"; then
                ui_info "Sử dụng remote hiện tại, bỏ qua bước tạo"
            else
                ui_info "Xóa remote cũ và tạo lại..."
                rclone config delete "$remote_name" >/dev/null 2>&1 || true
                remote_exists=false
            fi
        else
            ui_warning "Remote '$remote_name' đã tồn tại nhưng type không đúng (type: ${existing_type:-unknown})"
            if ui_confirm "Xóa remote cũ và tạo lại?"; then
                rclone config delete "$remote_name" >/dev/null 2>&1 || true
                remote_exists=false
            else
                ui_error "Không thể tiếp tục với remote không đúng type" "RCLONE_WRONG_TYPE"
                return 1
            fi
        fi
    fi
    
    # Tạo remote nếu chưa tồn tại
    if [[ "$remote_exists" == "false" ]]; then
        ui_info "Đang tạo remote '$remote_name' với type 'drive'..."
        ui_info "💡 Lưu ý: Remote sẽ được tạo với minimal config, cần authorize sau"
        
        # Tạo remote - rclone config create không cần input nếu chỉ có type
        # Nhưng để an toàn, chúng ta sẽ bỏ qua bước này và để rclone authorize tự tạo
        ui_info "💡 Remote sẽ được tạo tự động khi authorize"
        ui_info "💡 Bỏ qua bước tạo remote, chuyển sang authorize"
    fi
    
    echo ""
    
    ui_info_box "Chọn phương pháp authorize" \
        "1) Authorize trên máy LOCAL rồi dán token (Khuyến nghị)" \
        "2) Authorize trực tiếp trên VPS (cần truy cập được 127.0.0.1 của VPS)"
    
    local auth_choice
    read -p "Chọn phương pháp [1/2] (Enter = 1): " auth_choice
    local auth_mode="local"
    [[ "${auth_choice// }" == "2" ]] && auth_mode="vps"
    
    if [[ "$auth_mode" == "local" ]]; then
        if ! setup_google_drive_local_manual_authorize "$remote_name"; then
            ui_warning "Authorize bằng máy local không thành công"
            if ui_confirm "Bạn muốn chuyển sang authorize trực tiếp trên VPS không?"; then
                auth_mode="vps"
            else
                return 1
            fi
        fi
    fi
    
    if [[ "$auth_mode" == "vps" ]]; then
        echo ""
        
        ui_info "Bước 2: Lấy authorization URL..."
        echo ""
        ui_warning_box "QUAN TRỌNG" \
            "Sắp hiển thị authorization URL" \
            "Copy toàn bộ URL và mở trên máy có browser" \
            "Sau khi authorize, copy code từ URL và paste vào đây"
        echo ""
        
        read -p "Nhấn Enter để tiếp tục..." 
        echo ""
        
        # Lấy authorization URL bằng rclone authorize
        ui_info "Đang lấy authorization URL..."
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo -e "${UI_CYAN}📋 RCLONE SẼ HIỂN THỊ URL - COPY VÀ MỞ TRÊN BROWSER:${UI_NC}"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        
        ui_info "💡 Khi rclone hiển thị URL, bạn cần:"
        ui_info "   1. Copy URL và mở trên browser (máy local)"
        ui_info "   2. Login Google và authorize"
        ui_info "   3. Copy code từ URL redirect (sau code=)"
        ui_info "   4. Paste code vào terminal khi rclone hỏi"
        echo ""
        
        read -p "Nhấn Enter để bắt đầu rclone authorize..."
        echo ""
        
        # Chạy rclone authorize (interactive)
        # LƯU Ý: rclone authorize cần backend name ("drive"), không phải remote name
        ui_info "Đang chạy rclone authorize..."
        
        # Nếu remote chưa tồn tại, cần tạo trước với minimal config
        if [[ "$remote_exists" == "false" ]]; then
            ui_info "Tạo remote '$remote_name' với minimal config..."
            # Tạo remote với config file trực tiếp (không interactive)
            mkdir -p "$(dirname "$RCLONE_CONFIG")" 2>/dev/null || true
            cat >> "$RCLONE_CONFIG" <<EOF

[$remote_name]
type = drive
EOF
            ui_success "Remote '$remote_name' đã được tạo với minimal config"
        fi
        
        # Chạy rclone authorize với backend name "drive" (không phải remote name)
        # LƯU Ý: rclone authorize sẽ lưu token vào remote đầu tiên có type drive
        # Nếu có nhiều remote drive, cần đảm bảo remote_name là remote đầu tiên
        ui_info "💡 Rclone authorize sẽ lấy token và lưu vào remote đầu tiên có type drive"
        
        # Nếu có remote khác có type drive, tạm thời đổi tên để đảm bảo remote_name là đầu tiên
        local temp_renamed=false
        local other_drive_remotes=$(rclone listremotes 2>/dev/null | sed 's/:$//' | while read -r r; do
            if [[ "$r" != "$remote_name" ]] && rclone config show "$r" 2>/dev/null | grep -q "^type = drive$"; then
                echo "$r"
            fi
        done)
        
        if [[ -n "$other_drive_remotes" ]]; then
            ui_info "Phát hiện remote drive khác, sẽ tạm thời đổi tên để đảm bảo '$remote_name' là đầu tiên"
            # Tạm thời đổi tên các remote khác
            for other_remote in $other_drive_remotes; do
                if rclone config rename "$other_remote" "${other_remote}_temp_backup" 2>/dev/null; then
                    temp_renamed=true
                    ui_info "Đã tạm thời đổi tên remote '$other_remote'"
                fi
            done
        fi
        
        # Chạy rclone authorize (interactive)
        # Rclone sẽ tự động hiển thị URL và chờ code
        # Sử dụng "drive" là backend name, không phải remote name
        # Capture output để parse token JSON nếu cần
        local auth_output_file=$(mktemp)
        
        ui_info "💡 Lưu ý: Sau khi authorize, rclone sẽ hiển thị token JSON"
        ui_info "💡 Bạn cần copy toàn bộ JSON token (từ { đến }) và paste vào đây nếu cần"
        echo ""
        
        # Chạy rclone authorize và capture output
        if rclone authorize "drive" 2>&1 | tee "$auth_output_file"; then
            ui_success "Authorization thành công!"
            
            # Khôi phục tên remote nếu đã đổi
            if [[ "$temp_renamed" == "true" ]]; then
                for other_remote in $other_drive_remotes; do
                    if rclone config show "${other_remote}_temp_backup" >/dev/null 2>&1; then
                        rclone config rename "${other_remote}_temp_backup" "$other_remote" 2>/dev/null || true
                        ui_info "Đã khôi phục tên remote '$other_remote'"
                    fi
                done
            fi
            
            # Parse token JSON từ output
            local token_json=""
            if [[ -f "$auth_output_file" ]]; then
                # Tìm JSON token trong output (giữa "Paste the following" và "End paste")
                token_json=$(sed -n '/Paste the following/,/<---End paste/p' "$auth_output_file" | sed '1d;$d' | tr -d '\n' || echo "")
            fi
            
            # Kiểm tra xem remote có token chưa
            ui_info "Đang kiểm tra token đã được lưu vào remote '$remote_name'..."
            
            local has_token=false
            if rclone config show "$remote_name" 2>/dev/null | grep -qE "(token|access_token|refresh_token)"; then
                has_token=true
            fi
            
            if [[ "$has_token" == "true" ]]; then
                ui_success "Token đã được lưu vào remote '$remote_name'"
            else
                ui_warning "Token chưa được lưu vào remote '$remote_name'"
                
                # Nếu có token JSON trong output, lưu vào config
                if [[ -n "$token_json" ]]; then
                    if save_token_json_to_remote "$remote_name" "$token_json"; then
                        has_token=true
                    fi
                else
                    ui_info "💡 Không tìm thấy token JSON trong output"
                    ui_info "💡 Đang tìm remote có token..."
                    
                    # Tìm remote nào có token
                    local remote_with_token=""
                    for r in $(rclone listremotes 2>/dev/null | sed 's/:$//'); do
                        if rclone config show "$r" 2>/dev/null | grep -qE "(token|access_token|refresh_token)"; then
                            remote_with_token="$r"
                            ui_info "💡 Tìm thấy token trong remote: $remote_with_token"
                            break
                        fi
                    done
                    
                    if [[ -n "$remote_with_token" ]] && [[ "$remote_with_token" != "$remote_name" ]]; then
                        ui_info "💡 Sử dụng remote '$remote_with_token' thay vì '$remote_name'"
                        remote_name="$remote_with_token"
                        has_token=true
                    else
                        ui_error "Không tìm thấy token trong bất kỳ remote nào" "TOKEN_NOT_FOUND"
                        ui_info "💡 Có thể cần chạy lại: rclone authorize drive"
                    fi
                fi
            fi
            
            # Cleanup
            rm -f "$auth_output_file" 2>/dev/null || true
        else
            # Khôi phục tên remote nếu đã đổi (ngay cả khi authorize thất bại)
            if [[ "$temp_renamed" == "true" ]]; then
                for other_remote in $other_drive_remotes; do
                    if rclone config show "${other_remote}_temp_backup" >/dev/null 2>/dev/null; then
                        rclone config rename "${other_remote}_temp_backup" "$other_remote" 2>/dev/null || true
                    fi
                done
            fi
            
            ui_error "Authorization thất bại" "RCLONE_AUTH_FAILED" "Thử lại hoặc kiểm tra network"
            return 1
        fi
    fi
    
    # Auto-detect remote name (sử dụng remote có token)
    ui_info "Đang kiểm tra cấu hình..."
    
    local detected_remote
    if detected_remote=$(get_gdrive_remote_name); then
        if [[ "$detected_remote" != "$remote_name" ]]; then
            ui_info "Phát hiện remote: $detected_remote (khác với tên đã nhập)"
            # Kiểm tra remote nào có token
            if rclone config show "$detected_remote" 2>/dev/null | grep -q "token"; then
                ui_info "Remote '$detected_remote' có token, sử dụng remote này"
                remote_name="$detected_remote"
            else
                ui_info "Remote '$detected_remote' không có token, giữ nguyên '$remote_name'"
            fi
        fi
        save_gdrive_remote_name "$remote_name"
    else
        ui_warning "Không tự động detect được remote, sử dụng tên đã nhập: $remote_name"
    fi
    
    # Test connection
    echo ""
    ui_info "Bước 3: Kiểm tra kết nối với remote '$remote_name'..."
    
    if rclone lsd "${remote_name}:" >/dev/null 2>&1; then
        ui_success "✅ Kết nối Google Drive thành công!"
        
        # Tạo thư mục backup
        ui_info "Tạo thư mục n8n-backups..."
        if rclone mkdir "${remote_name}:n8n-backups" 2>/dev/null || rclone lsd "${remote_name}:n8n-backups" >/dev/null 2>&1; then
            ui_success "✅ Thư mục n8n-backups đã sẵn sàng trên Google Drive"
        else
            ui_error "Không thể tạo thư mục backup" "GDRIVE_MKDIR_FAILED" "Kiểm tra permissions"
            return 1
        fi
        
        ui_success "🎉 Cấu hình Google Drive hoàn tất!"
        return 0
    else
        ui_error "Không thể kết nối Google Drive" "GDRIVE_CONNECTION_FAILED" "Có thể cần cấu hình lại"
        ui_info "💡 Thử chạy lại: rclone authorize 'drive'"
        return 1
    fi
}

# Setup Google Drive với interactive mode (có GUI)
setup_google_drive_interactive() {
    local remote_name="$1"
    
    ui_info "Bắt đầu cấu hình Google Drive với rclone..."
    ui_info "💡 Rclone sẽ hướng dẫn bạn từng bước để kết nối Google Drive"
    ui_info "💡 Remote name: $remote_name"
    echo ""
    
    # Chạy rclone config interactively
    if rclone config; then
        ui_success "Cấu hình rclone hoàn tất"
    else
        ui_error "Cấu hình rclone thất bại" "RCLONE_CONFIG_FAILED"
        return 1
    fi
    
    # Auto-detect remote name after configuration
    ui_info "Đang tự động nhận diện remote Google Drive..."
    
    local detected_remote
    if detected_remote=$(get_gdrive_remote_name); then
        if [[ "$detected_remote" != "$remote_name" ]]; then
            ui_info "Phát hiện remote: $detected_remote"
            remote_name="$detected_remote"
        fi
        ui_success "Đã nhận diện remote: $remote_name"
        save_gdrive_remote_name "$remote_name"
    else
        ui_warning "Không tìm thấy remote Google Drive, sử dụng tên đã nhập: $remote_name"
    fi
    
    # Test connection
    ui_info "Kiểm tra kết nối với remote '$remote_name'..."
    if rclone lsd "${remote_name}:" >/dev/null 2>&1; then
        ui_success "Kết nối Google Drive thành công!"
        
        # Tạo thư mục backup
        ui_info "Tạo thư mục n8n-backups..."
        if rclone mkdir "${remote_name}:n8n-backups" 2>/dev/null || rclone lsd "${remote_name}:n8n-backups" >/dev/null 2>&1; then
            ui_success "Thư mục n8n-backups đã sẵn sàng trên Google Drive"
        else
            ui_error "Không thể tạo thư mục backup" "GDRIVE_MKDIR_FAILED" "Kiểm tra permissions"
            return 1
        fi
    else
        ui_error "Không thể kết nối Google Drive với remote '$remote_name'" "GDRIVE_CONNECTION_FAILED" "Kiểm tra credentials"
        return 1
    fi
}

# Upload backup lên Google Drive 
upload_to_gdrive() {
    local backup_file="$1"
    
    if [[ ! -f "$RCLONE_CONFIG" ]]; then
        ui_error "Chưa cấu hình Google Drive" "GDRIVE_NOT_CONFIGURED" "Chạy setup_google_drive trước"
        return 1
    fi
    
    # Auto-detect remote name
    local remote_name
    if ! remote_name=$(get_gdrive_remote_name); then
        ui_error "Không tìm thấy Google Drive remote" "GDRIVE_REMOTE_NOT_FOUND" "Chạy setup_google_drive"
        return 1
    fi
    
    ui_info "Đang upload lên Google Drive (remote: $remote_name)..."
    
    if rclone copy "$backup_file" "${remote_name}:n8n-backups/" --progress; then
        ui_success "Upload thành công"
        return 0
    else
        ui_error "Upload thất bại" "GDRIVE_UPLOAD_FAILED" "Kiểm tra network và permissions"
        return 1
    fi
}

# Export functions
export -f setup_google_drive upload_to_gdrive

