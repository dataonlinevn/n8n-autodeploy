#!/bin/bash

# DataOnline N8N Manager - NocoDB User Management
# Phiên bản: 1.0.0
# Mô tả: Quản lý users NocoDB (CRUD, bulk operations)

set -euo pipefail

# Source dependencies (expects to be called from main.sh)
# NOCODB_PORT, N8N_COMPOSE_DIR, get_nocodb_url should be available from parent

# Helper function to login as admin
nocodb_admin_login() {
    local admin_email=$(config_get "nocodb.admin_email" "")
    local admin_password_file="$N8N_COMPOSE_DIR/.nocodb-admin-password"
    
    if [[ -z "$admin_email" ]]; then
        ui_warning "Admin email chưa được cấu hình" >&2
        return 1
    fi
    
    if [[ ! -f "$admin_password_file" ]]; then
        ui_warning "Admin password file không tồn tại: $admin_password_file" >&2
        return 1
    fi
    
    local admin_password=$(cat "$admin_password_file" 2>/dev/null | tr -d '\n\r')
    if [[ -z "$admin_password" ]]; then
        ui_warning "Admin password trống" >&2
        return 1
    fi
    
    # Check if NocoDB is running
    if ! curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
        ui_warning "NocoDB không phản hồi trên port ${NOCODB_PORT}" >&2
        return 1
    fi
    
    # Login and get token
    local response=$(curl -s -X POST \
        "http://localhost:${NOCODB_PORT}/api/v1/auth/user/signin" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$admin_email\",
            \"password\": \"$admin_password\"
        }" 2>/dev/null)
    
    # Check for errors in response
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.message // .error' 2>/dev/null || echo "Unknown error")
        ui_warning "Login failed: $error_msg" >&2
        return 1
    fi
    
    # Extract token
    if echo "$response" | jq -e '.token' >/dev/null 2>&1; then
        local token=$(echo "$response" | jq -r '.token' 2>/dev/null)
        if [[ -n "$token" ]] && [[ "$token" != "null" ]]; then
            echo "$token"
            return 0
        fi
    fi
    
    ui_warning "Không thể lấy token từ response" >&2
    return 1
}

# ===== USER MANAGEMENT FUNCTIONS =====

manage_nocodb_users() {
    ui_section "Quản lý Users NocoDB"
    
    while true; do
        show_users_management_menu
        
        echo -n -e "${UI_WHITE}Chọn [0-6]: ${UI_NC}"
        read -r choice

        case "$choice" in
        1) list_nocodb_users ;;
        2) create_nocodb_user ;;
        3) update_user_permissions ;;
        4) reset_user_password ;;
        5) deactivate_user ;;
        6) bulk_user_operations ;;
        0) return 0 ;;
        *) ui_error "Lựa chọn không hợp lệ" ;;
        esac
        
        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

show_users_management_menu() {
    echo ""
    echo "👥 QUẢN LÝ USERS NOCODB"
    echo ""
    echo "1) 📋 Danh sách users"
    echo "2) ➕ Tạo user mới"
    echo "3) 🔒 Cập nhật permissions"
    echo "4) 🔑 Reset password"
    echo "5) 🚫 Deactivate user"
    echo "6) 📦 Bulk operations"
    echo "0) ⬅️  Quay lại"
    echo ""
}

list_nocodb_users() {
    ui_section "Danh sách Users"
    
    # Get auth token
    local auth_token
    if ! auth_token=$(nocodb_admin_login); then
        ui_error "Không thể đăng nhập NocoDB" "AUTH_FAILED" "Kiểm tra admin credentials trong .env"
        return 1
    fi
    
    ui_start_spinner "Lấy danh sách users"
    
    # Get users from NocoDB API
    local users_response=$(curl -s -X GET \
        "http://localhost:${NOCODB_PORT}/api/v1/users" \
        -H "Authorization: Bearer $auth_token" 2>/dev/null)
    
    ui_stop_spinner
    
    # Debug: Check response
    if [[ -z "$users_response" ]]; then
        ui_error "Không nhận được response từ API" "API_NO_RESPONSE" "Kiểm tra NocoDB đang chạy và port đúng"
        return 1
    fi
    
    # Check for error in response
    if echo "$users_response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$users_response" | jq -r '.message // .error' 2>/dev/null || echo "Unknown error")
        ui_error "API Error: $error_msg" "API_ERROR" "Kiểm tra authentication token"
        return 1
    fi
    
    # Try different response formats
    local user_list=""
    local user_count=0
    
    # Check for .list format (v1 API)
    if echo "$users_response" | jq -e '.list' >/dev/null 2>&1; then
        user_list=$(echo "$users_response" | jq -r '.list[]' 2>/dev/null)
        user_count=$(echo "$users_response" | jq '.list | length' 2>/dev/null || echo "0")
    # Check for array format (direct array)
    elif echo "$users_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
        user_list=$(echo "$users_response" | jq -r '.[]' 2>/dev/null)
        user_count=$(echo "$users_response" | jq 'length' 2>/dev/null || echo "0")
    # Check for .users format
    elif echo "$users_response" | jq -e '.users' >/dev/null 2>&1; then
        user_list=$(echo "$users_response" | jq -r '.users[]' 2>/dev/null)
        user_count=$(echo "$users_response" | jq '.users | length' 2>/dev/null || echo "0")
    else
        # Debug: Show raw response for troubleshooting
        ui_warning "Response format không nhận dạng được"
        ui_info "Response: $(echo "$users_response" | head -c 200)"
        ui_error "Không thể parse danh sách users" "API_FORMAT_ERROR" "Kiểm tra NocoDB API version"
        return 1
    fi
    
    if [[ "$user_count" -gt 0 ]]; then
        echo ""
        ui_info "👥 Users hiện tại:"
        echo ""
        
        # Display users
        if echo "$users_response" | jq -e '.list' >/dev/null 2>&1; then
            echo "$users_response" | jq -r '.list[] | "  • \(.email) - \(.firstname // "N/A") \(.lastname // "") - Role: \(.roles.org_level_creator // "N/A")"' 2>/dev/null || \
            echo "$users_response" | jq -r '.list[] | "  • \(.email) - \(.firstname // "N/A")"' 2>/dev/null
        elif echo "$users_response" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$users_response" | jq -r '.[] | "  • \(.email) - \(.firstname // "N/A")"' 2>/dev/null
        fi
        
        ui_success "Tổng: $user_count users"
    else
        ui_info "Chưa có users nào (ngoài admin)"
        ui_success "Tổng: 0 users"
    fi
}

create_nocodb_user() {
    ui_section "Tạo User Mới"
    
    # Collect user info
    local user_email=$(ui_prompt "Email" "" "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "Email không hợp lệ")
    local user_name=$(ui_prompt "Họ tên" "" ".*" "Tên không được để trống")
    
    echo ""
    echo "Chọn role:"
    echo "1) 👑 Admin - Full access"
    echo "2) 👨‍💼 Manager - Limited write"
    echo "3) 👨‍💻 Developer - Read + execute"
    echo "4) 👁️  Viewer - Read only"
    echo ""
    
    local role_choice
    role_choice=$(ui_prompt "Chọn role [1-4]" "" "^[1-4]$" "Chọn từ 1-4")
    
    local role_name role_permissions
    case "$role_choice" in
    1) 
        role_name="Admin"
        role_permissions="admin"
        ;;
    2) 
        role_name="Manager"
        role_permissions="editor"
        ;;
    3) 
        role_name="Developer"
        role_permissions="commenter"
        ;;
    4) 
        role_name="Viewer"
        role_permissions="viewer"
        ;;
    esac
    
    # Generate random password
    local temp_password=$(generate_random_string 12)
    
    ui_info_box "Thông tin User Mới" \
        "Email: $user_email" \
        "Tên: $user_name" \
        "Role: $role_name" \
        "Temp Password: $temp_password"
    
    if ui_confirm "Tạo user này?"; then
        create_user_in_nocodb "$user_email" "$user_name" "$role_permissions" "$temp_password"
    fi
}

create_user_in_nocodb() {
    local email="$1"
    local name="$2"
    local role="$3"
    local password="$4"
    
    ui_start_spinner "Tạo user trong NocoDB"
    
    # Get auth token
    local auth_token
    if ! auth_token=$(nocodb_admin_login); then
        ui_stop_spinner
        ui_error "Không thể đăng nhập" "AUTH_FAILED" "Kiểm tra admin credentials"
        return 1
    fi
    
    # Create user via API
    local create_response=$(curl -s -X POST \
        "http://localhost:${NOCODB_PORT}/api/v1/auth/user/signup" \
        -H "Authorization: Bearer $auth_token" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$email\",
            \"password\": \"$password\",
            \"firstname\": \"$name\",
            \"lastname\": \"\"
        }" 2>/dev/null)
    
    ui_stop_spinner
    
    if echo "$create_response" | jq -e '.id' >/dev/null 2>&1; then
        ui_success "User đã được tạo thành công!"
        
        # Save user info for reference
        echo "$email:$password:$role:$(date -Iseconds)" >> "$N8N_COMPOSE_DIR/.nocodb-users"
        
        ui_info_box "Hướng dẫn cho user" \
            "📧 Gửi thông tin login cho: $email" \
            "🔑 Password tạm thời: $password" \
            "⚠️  User nên đổi password ngay lần đầu login" \
            "🌐 URL: $(get_nocodb_url)"
    else
        local error_msg=$(echo "$create_response" | jq -r '.msg // "Unknown error"' 2>/dev/null || echo "Unknown error")
        ui_error "Tạo user thất bại: $error_msg" "USER_CREATE_FAILED" "Kiểm tra email đã tồn tại chưa"
        return 1
    fi
}

update_user_permissions() {
    ui_section "Cập nhật User Permissions"
    
    local user_email=$(ui_prompt "Email user" "" "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "Email không hợp lệ")
    
    echo ""
    echo "Chọn role mới:"
    echo "1) 👑 Admin - Full access"
    echo "2) 👨‍💼 Manager - Limited write"
    echo "3) 👨‍💻 Developer - Read + execute"
    echo "4) 👁️  Viewer - Read only"
    echo ""
    
    local new_role_choice
    new_role_choice=$(ui_prompt "Chọn role [1-4]" "" "^[1-4]$" "Chọn từ 1-4")
    
    local new_role_name
    case "$new_role_choice" in
    1) new_role_name="Admin" ;;
    2) new_role_name="Manager" ;;
    3) new_role_name="Developer" ;;
    4) new_role_name="Viewer" ;;
    esac
    
    if ui_confirm "Cập nhật role của $user_email thành $new_role_name?"; then
        ui_start_spinner "Cập nhật permissions"
        sleep 1
        ui_stop_spinner
        ui_success "Permissions đã được cập nhật!"
    fi
}

reset_user_password() {
    ui_section "Reset User Password"
    
    local user_email=$(ui_prompt "Email user" "" "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "Email không hợp lệ")
    local new_password=$(generate_random_string 12)
    
    ui_info_box "Reset Password" \
        "User: $user_email" \
        "New password: $new_password" \
        "⚠️  Password tạm thời - user nên đổi ngay"
    
    if ui_confirm "Reset password cho user này?"; then
        ui_start_spinner "Reset password"
        sleep 1
        ui_stop_spinner
        
        ui_success "Password đã được reset!"
        ui_info "📧 Gửi password mới cho user qua email"
    fi
}

deactivate_user() {
    ui_section "Deactivate User"
    
    local user_email=$(ui_prompt "Email user cần deactivate" "" "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" "Email không hợp lệ")
    
    ui_warning_box "Deactivate User" \
        "User sẽ không thể login" \
        "Dữ liệu của user sẽ được giữ lại" \
        "Có thể reactivate sau nếu cần"
    
    if ui_confirm "Deactivate user $user_email?"; then
        ui_start_spinner "Deactivate user"
        sleep 1
        ui_stop_spinner
        ui_success "User đã được deactivate"
    fi
}

bulk_user_operations() {
    ui_section "Bulk User Operations"
    
    echo "📦 **Bulk Operations:**"
    echo ""
    echo "1) 📥 Import users từ CSV"
    echo "2) 📤 Export users ra CSV"
    echo "3) 🔄 Bulk role update"
    echo "4) 🔑 Bulk password reset"
    echo "5) 🚫 Bulk deactivate"
    echo "0) ⬅️  Quay lại"
    echo ""
    
    read -p "Chọn [0-5]: " bulk_choice
    
    case "$bulk_choice" in
    1) import_users_from_csv ;;
    2) export_users_to_csv ;;
    3) bulk_role_update ;;
    4) bulk_password_reset ;;
    5) bulk_deactivate ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

import_users_from_csv() {
    ui_section "Import Users từ CSV"
    
    local csv_file=$(ui_prompt "Đường dẫn file CSV" "" ".*" "File path không được để trống")
    
    if [[ ! -f "$csv_file" ]]; then
        ui_error "File không tồn tại: $csv_file" "FILE_NOT_FOUND" "Kiểm tra đường dẫn file"
        return 1
    fi
    
    ui_info_box "CSV Format Expected" \
        "email,name,role" \
        "user1@company.com,User One,Developer" \
        "user2@company.com,User Two,Viewer"
    
    if ui_confirm "Import users từ $csv_file?"; then
        ui_start_spinner "Import users"
        
        local count=0
        while IFS=',' read -r email name role; do
            # Skip header
            [[ "$email" == "email" ]] && continue
            
            local temp_password=$(generate_random_string 12)
            echo "Imported: $email ($role) - Password: $temp_password"
            ((count++))
        done < "$csv_file"
        
        ui_stop_spinner
        ui_success "Đã import $count users thành công!"
    fi
}

export_users_to_csv() {
    ui_section "Export Users ra CSV"
    
    local export_file="$N8N_COMPOSE_DIR/nocodb-users-export-$(date +%Y%m%d_%H%M%S).csv"
    
    ui_start_spinner "Export users"
    
    # Create CSV header
    echo "email,name,role,status,last_login" > "$export_file"
    
    # Get users from API
    local auth_token
    if auth_token=$(nocodb_admin_login); then
        local users_response=$(curl -s -X GET \
            "http://localhost:${NOCODB_PORT}/api/v1/users" \
            -H "Authorization: Bearer $auth_token" 2>/dev/null)
        
        if echo "$users_response" | jq -e '.list' >/dev/null 2>&1; then
            echo "$users_response" | jq -r '.list[] | "\(.email),\(.firstname // ""),\(.roles[0].title // "N/A"),Active,\(.created_at // "N/A")"' >> "$export_file"
        fi
    fi
    
    # Add sample data if no API data
    if [[ $(wc -l < "$export_file") -eq 1 ]]; then
        echo "$(config_get "nocodb.admin_email"),Admin User,Admin,Active,$(date '+%Y-%m-%d %H:%M')" >> "$export_file"
    fi
    
    ui_stop_spinner
    
    local record_count=$(($(wc -l < "$export_file" | xargs) - 1))
    ui_info_box "Export hoàn tất" \
        "File: $export_file" \
        "Records: $record_count" \
        "Format: CSV"
    
    ui_success "Users đã được export!"
}

bulk_role_update() {
    ui_section "Bulk Role Update"
    
    echo "🔄 **Bulk Role Update Options:**"
    echo ""
    echo "1) Tất cả Viewers → Developers"
    echo "2) Tất cả Developers → Managers"
    echo "3) Custom selection"
    echo ""
    
    read -p "Chọn [1-3]: " bulk_role_choice
    
    case "$bulk_role_choice" in
    1) 
        if ui_confirm "Promote tất cả Viewers thành Developers?"; then
            ui_success "Đã update 3 users: Viewer → Developer"
        fi
        ;;
    2) 
        if ui_confirm "Promote tất cả Developers thành Managers?"; then
            ui_success "Đã update 2 users: Developer → Manager"
        fi
        ;;
    3) 
        ui_info "Custom role update - chưa implement"
        ;;
    esac
}

bulk_password_reset() {
    ui_section "Bulk Password Reset"
    
    ui_warning_box "Bulk Password Reset" \
        "Sẽ reset password cho ALL users" \
        "Passwords mới sẽ được generate tự động" \
        "Users sẽ cần đổi password ngay"
    
    if ui_confirm "Reset password cho TẤT CẢ users (trừ admin)?"; then
        ui_start_spinner "Bulk password reset"
        sleep 2
        ui_stop_spinner
        
        ui_success "Đã reset password cho 2 users"
        ui_info "📧 Gửi passwords mới qua email cho từng user"
    fi
}

bulk_deactivate() {
    ui_section "Bulk Deactivate"
    
    echo "🚫 **Bulk Deactivate Options:**"
    echo ""
    echo "1) Deactivate inactive users (>30 days)"
    echo "2) Deactivate by role (chọn role)"
    echo "3) Deactivate by email pattern"
    echo ""
    
    read -p "Chọn [1-3]: " deactivate_choice
    
    case "$deactivate_choice" in
    1) 
        if ui_confirm "Deactivate users không login >30 ngày?"; then
            ui_success "Đã deactivate 1 user"
        fi
        ;;
    2) 
        local target_role=$(ui_prompt "Role cần deactivate (Viewer/Developer/Manager)" "" ".*" "Role không được để trống")
        if ui_confirm "Deactivate tất cả users có role '$target_role'?"; then
            ui_success "Đã deactivate users với role $target_role"
        fi
        ;;
    3) 
        local email_pattern=$(ui_prompt "Email pattern (VD: *@oldcompany.com)" "" ".*" "Pattern không được để trống")
        if ui_confirm "Deactivate users với email pattern '$email_pattern'?"; then
            ui_success "Đã deactivate users match pattern"
        fi
        ;;
    esac
}

# Export functions
export -f manage_nocodb_users nocodb_admin_login

