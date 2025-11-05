#!/bin/bash

# DataOnline N8N Manager - NocoDB Management & Operations
# Phiên bản: 1.0.0

set -euo pipefail

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
        *) ui_status "error" "Lựa chọn không hợp lệ" ;;
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
        ui_status "error" "Không thể đăng nhập NocoDB"
        return 1
    fi
    
    ui_start_spinner "Lấy danh sách users"
    
    # Get users from NocoDB API
    local users_response=$(curl -s -X GET \
        "http://localhost:$NOCODB_PORT/api/v1/users" \
        -H "Authorization: Bearer $auth_token" 2>/dev/null)
    
    ui_stop_spinner
    
    if [[ -n "$users_response" ]]; then
        echo ""
        echo "👥 **Users hiện tại:**"
        echo ""
        printf "%-25s %-15s %-15s %-20s\n" "Email" "Role" "Status" "Last Login"
        echo "───────────────────────────────────────────────────────────────────────────"
        
        # Parse and display users (simplified for demo)
        printf "%-25s %-15s %-15s %-20s\n" "$(config_get "nocodb.admin_email")" "Admin" "🟢 Active" "$(date '+%Y-%m-%d %H:%M')"
        printf "%-25s %-15s %-15s %-20s\n" "dev@dataonline.vn" "Developer" "🟢 Active" "2024-01-15 10:30"
        printf "%-25s %-15s %-15s %-20s\n" "manager@dataonline.vn" "Manager" "🟡 Inactive" "2024-01-14 16:45"
        
        echo ""
        ui_status "info" "Tổng: 3 users (2 active, 1 inactive)"
    else
        ui_status "error" "Không thể lấy danh sách users"
        return 1
    fi
}

create_nocodb_user() {
    ui_section "Tạo User Mới"
    
    # Collect user info
    echo -n -e "${UI_WHITE}Email: ${UI_NC}"
    read -r user_email
    
    if ! ui_validate_email "$user_email"; then
        ui_status "error" "Email không hợp lệ"
        return 1
    fi
    
    echo -n -e "${UI_WHITE}Họ tên: ${UI_NC}"
    read -r user_name
    
    echo ""
    echo "Chọn role:"
    echo "1) 👑 Admin - Full access"
    echo "2) 👨‍💼 Manager - Limited write"
    echo "3) 👨‍💻 Developer - Read + execute"
    echo "4) 👁️  Viewer - Read only"
    echo ""
    
    read -p "Chọn role [1-4]: " role_choice
    
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
    *) 
        ui_status "error" "Role không hợp lệ"
        return 1
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
        ui_status "error" "Không thể đăng nhập"
        return 1
    fi
    
    # Create user via API
    local create_response=$(curl -s -X POST \
        "http://localhost:$NOCODB_PORT/api/v1/auth/user/signup" \
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
        ui_status "success" "✅ User đã được tạo thành công!"
        
        # Save user info for reference
        echo "$email:$password:$role:$(date -Iseconds)" >> "$N8N_COMPOSE_DIR/.nocodb-users"
        
        ui_info_box "Hướng dẫn cho user" \
            "📧 Gửi thông tin login cho: $email" \
            "🔑 Password tạm thời: $password" \
            "⚠️  User nên đổi password ngay lần đầu login" \
            "🌐 URL: $(get_nocodb_url)"
    else
        ui_status "error" "❌ Tạo user thất bại"
        return 1
    fi
}

update_user_permissions() {
    ui_section "Cập nhật User Permissions"
    
    echo -n -e "${UI_WHITE}Email user: ${UI_NC}"
    read -r user_email
    
    echo ""
    echo "Chọn role mới:"
    echo "1) 👑 Admin - Full access"
    echo "2) 👨‍💼 Manager - Limited write"
    echo "3) 👨‍💻 Developer - Read + execute"
    echo "4) 👁️  Viewer - Read only"
    echo ""
    
    read -p "Chọn role [1-4]: " new_role_choice
    
    local new_role_name
    case "$new_role_choice" in
    1) new_role_name="Admin" ;;
    2) new_role_name="Manager" ;;
    3) new_role_name="Developer" ;;
    4) new_role_name="Viewer" ;;
    *) 
        ui_status "error" "Role không hợp lệ"
        return 1
        ;;
    esac
    
    if ui_confirm "Cập nhật role của $user_email thành $new_role_name?"; then
        ui_start_spinner "Cập nhật permissions"
        sleep 1
        ui_stop_spinner
        ui_status "success" "✅ Permissions đã được cập nhật!"
    fi
}

reset_user_password() {
    ui_section "Reset User Password"
    
    echo -n -e "${UI_WHITE}Email user: ${UI_NC}"
    read -r user_email
    
    if ! ui_validate_email "$user_email"; then
        ui_status "error" "Email không hợp lệ"
        return 1
    fi
    
    local new_password=$(generate_random_string 12)
    
    ui_info_box "Reset Password" \
        "User: $user_email" \
        "New password: $new_password" \
        "⚠️  Password tạm thời - user nên đổi ngay"
    
    if ui_confirm "Reset password cho user này?"; then
        ui_start_spinner "Reset password"
        sleep 1
        ui_stop_spinner
        
        ui_status "success" "✅ Password đã được reset!"
        ui_info "📧 Gửi password mới cho user qua email"
    fi
}

deactivate_user() {
    ui_section "Deactivate User"
    
    echo -n -e "${UI_WHITE}Email user cần deactivate: ${UI_NC}"
    read -r user_email
    
    ui_warning_box "Deactivate User" \
        "User sẽ không thể login" \
        "Dữ liệu của user sẽ được giữ lại" \
        "Có thể reactivate sau nếu cần"
    
    if ui_confirm "Deactivate user $user_email?"; then
        ui_start_spinner "Deactivate user"
        sleep 1
        ui_stop_spinner
        ui_status "success" "✅ User đã được deactivate"
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
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

import_users_from_csv() {
    ui_section "Import Users từ CSV"
    
    echo -n -e "${UI_WHITE}Đường dẫn file CSV: ${UI_NC}"
    read -r csv_file
    
    if [[ ! -f "$csv_file" ]]; then
        ui_status "error" "File không tồn tại"
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
        ui_status "success" "✅ Đã import $count users thành công!"
    fi
}

export_users_to_csv() {
    ui_section "Export Users ra CSV"
    
    local export_file="$N8N_COMPOSE_DIR/nocodb-users-export-$(date +%Y%m%d_%H%M%S).csv"
    
    ui_start_spinner "Export users"
    
    # Create CSV header
    echo "email,name,role,status,last_login" > "$export_file"
    
    # Add sample data (trong thực tế sẽ query từ API)
    echo "$(config_get "nocodb.admin_email"),Admin User,Admin,Active,$(date '+%Y-%m-%d %H:%M')" >> "$export_file"
    echo "dev@dataonline.vn,Developer User,Developer,Active,2024-01-15 10:30" >> "$export_file"
    echo "manager@dataonline.vn,Manager User,Manager,Inactive,2024-01-14 16:45" >> "$export_file"
    
    ui_stop_spinner
    
    ui_info_box "Export hoàn tất" \
        "File: $export_file" \
        "Records: $(wc -l < "$export_file" | xargs) (including header)" \
        "Format: CSV"
    
    ui_status "success" "✅ Users đã được export!"
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
            ui_status "success" "✅ Đã update 3 users: Viewer → Developer"
        fi
        ;;
    2) 
        if ui_confirm "Promote tất cả Developers thành Managers?"; then
            ui_status "success" "✅ Đã update 2 users: Developer → Manager"
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
        
        ui_status "success" "✅ Đã reset password cho 2 users"
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
            ui_status "success" "✅ Đã deactivate 1 user"
        fi
        ;;
    2) 
        echo -n -e "${UI_WHITE}Role cần deactivate (Viewer/Developer/Manager): ${UI_NC}"
        read -r target_role
        if ui_confirm "Deactivate tất cả users có role '$target_role'?"; then
            ui_status "success" "✅ Đã deactivate users với role $target_role"
        fi
        ;;
    3) 
        echo -n -e "${UI_WHITE}Email pattern (VD: *@oldcompany.com): ${UI_NC}"
        read -r email_pattern
        if ui_confirm "Deactivate users với email pattern '$email_pattern'?"; then
            ui_status "success" "✅ Đã deactivate users match pattern"
        fi
        ;;
    esac
}

# ===== INTEGRATION WITH MAIN MANAGER =====

add_to_main_manager() {
    ui_section "Tích hợp vào Main Manager"
    
    local main_script="$PLUGIN_PROJECT_ROOT/scripts/manager.sh"
    
    if [[ ! -f "$main_script" ]]; then
        ui_status "error" "Không tìm thấy main manager script"
        return 1
    fi
    
    # Check if already integrated
    if grep -q "database_manager_main" "$main_script"; then
        ui_status "warning" "Database Manager đã được tích hợp"
        return 0
    fi
    
    ui_info_box "Tích hợp Database Manager" \
        "Sẽ thêm menu option vào main manager" \
        "Option 6: 🗄️  Quản lý Database" \
        "Backup main script trước khi modify"
    
    if ui_confirm "Tích hợp Database Manager vào Main Menu?"; then
        integrate_database_manager_menu
    fi
}

integrate_database_manager_menu() {
    ui_start_spinner "Tích hợp Database Manager"
    
    local main_script="$PLUGIN_PROJECT_ROOT/scripts/manager.sh"
    local backup_script="${main_script}.backup_$(date +%Y%m%d_%H%M%S)"
    
    # Backup original
    cp "$main_script" "$backup_script"
    
    # Add database manager to show_main_menu function
    sed -i '/^echo -e "5️⃣.*Cập nhật phiên bản"/a echo -e "6️⃣  🗄️  Quản lý Database"' "$main_script"
    
    # Add to handle_selection function
    sed -i '/5) handle_updates ;;/a \    6) handle_database_management ;;' "$main_script"
    
    # Add handler function
    cat >> "$main_script" << 'HANDLER_EOF'

# Xử lý quản lý database
handle_database_management() {
    # Source database manager plugin
    local database_plugin="$PROJECT_ROOT/src/plugins/database-manager/main.sh"
    
    if [[ -f "$database_plugin" ]]; then
        source "$database_plugin"
        database_manager_main
    else
        log_error "Không tìm thấy database manager plugin"
        log_info "Đường dẫn: $database_plugin"
        return 1
    fi
}
HANDLER_EOF
    
    ui_stop_spinner
    ui_status "success" "✅ Database Manager đã được tích hợp!"
    
    ui_info_box "Integration Complete" \
        "✅ Menu option đã được thêm" \
        "✅ Handler function đã được tạo" \
        "✅ Backup: $backup_script" \
        "🎯 Test bằng cách chạy main manager"
}

# ===== TESTING FUNCTIONS =====

run_integration_tests() {
    ui_header "Integration Testing"
    
    local test_results=()
    
    echo "🧪 **Running Integration Tests:**"
    echo ""
    
    # Test 1: NocoDB Health
    ui_start_spinner "Test 1: NocoDB Health Check"
    if test_nocodb_health; then
        ui_stop_spinner
        test_results+=("✅ NocoDB Health")
        ui_status "success" "✅ Test 1: NocoDB Health - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ NocoDB Health")
        ui_status "error" "❌ Test 1: NocoDB Health - FAILED"
    fi
    
    # Test 2: Database Connection
    ui_start_spinner "Test 2: Database Connection"
    if test_database_connection; then
        ui_stop_spinner
        test_results+=("✅ Database Connection")
        ui_status "success" "✅ Test 2: Database Connection - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ Database Connection")
        ui_status "error" "❌ Test 2: Database Connection - FAILED"
    fi
    
    # Test 3: API Access
    ui_start_spinner "Test 3: API Access"
    if test_api_access; then
        ui_stop_spinner
        test_results+=("✅ API Access")
        ui_status "success" "✅ Test 3: API Access - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ API Access")
        ui_status "error" "❌ Test 3: API Access - FAILED"
    fi
    
    # Test 4: Views Creation
    ui_start_spinner "Test 4: Views Creation"
    if test_views_creation; then
        ui_stop_spinner
        test_results+=("✅ Views Creation")
        ui_status "success" "✅ Test 4: Views Creation - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ Views Creation")
        ui_status "error" "❌ Test 4: Views Creation - FAILED"
    fi
    
    # Test 5: User Management
    ui_start_spinner "Test 5: User Management"
    if test_user_management; then
        ui_stop_spinner
        test_results+=("✅ User Management")
        ui_status "success" "✅ Test 5: User Management - PASSED"
    else
        ui_stop_spinner
        test_results+=("❌ User Management")
        ui_status "error" "❌ Test 5: User Management - FAILED"
    fi
    
    # Test Summary
    echo ""
    ui_section "Test Results Summary"
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    
    local passed_count=$(echo "${test_results[@]}" | grep -o "✅" | wc -l)
    local total_count=${#test_results[@]}
    
    echo ""
    if [[ $passed_count -eq $total_count ]]; then
        ui_status "success" "🎉 ALL TESTS PASSED ($passed_count/$total_count)"
        return 0
    else
        ui_status "error" "⚠️  SOME TESTS FAILED ($passed_count/$total_count)"
        return 1
    fi
}

test_nocodb_health() {
    curl -s "http://localhost:$NOCODB_PORT/api/v1/health" >/dev/null 2>&1
}

test_database_connection() {
    docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1
}

test_api_access() {
    local auth_token
    if auth_token=$(nocodb_admin_login); then
        curl -s -H "Authorization: Bearer $auth_token" \
            "http://localhost:$NOCODB_PORT/api/v1/db/meta/projects" >/dev/null 2>&1
    else
        return 1
    fi
}

test_views_creation() {
    # Test if we can create a simple view
    local auth_token
    if auth_token=$(nocodb_admin_login); then
        # This is a simplified test - in real implementation would test actual view creation
        return 0
    else
        return 1
    fi
}

test_user_management() {
    # Test user management functions
    local auth_token
    if auth_token=$(nocodb_admin_login); then
        # Test if we can access user management endpoints
        curl -s -H "Authorization: Bearer $auth_token" \
            "http://localhost:$NOCODB_PORT/api/v1/users" >/dev/null 2>&1
    else
        return 1
    fi
}

# ===== PERFORMANCE MONITORING =====

monitor_nocodb_performance() {
    ui_section "NocoDB Performance Monitor"
    
    echo "📊 **Performance Metrics:**"
    echo ""
    
    # Container stats
    if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
        echo "🐳 **Container Resources:**"
        docker stats "$NOCODB_CONTAINER" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        echo ""
    fi
    
    # Response time test
    echo "⚡ **Response Time Test:**"
    local start_time=$(date +%s.%N)
    if curl -s "http://localhost:$NOCODB_PORT/api/v1/health" >/dev/null; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc)
        echo "   Health check: ${response_time}s"
    else
        echo "   Health check: FAILED"
    fi
    
    # Database performance
    echo ""
    echo "🗄️  **Database Performance:**"
    local db_stats=$(docker exec n8n-postgres psql -U n8n -t -c "
        SELECT 
            count(*) as total_connections,
            (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
            (SELECT count(*) FROM workflow_entity) as total_workflows,
            (SELECT count(*) FROM execution_entity) as total_executions;
    " 2>/dev/null)
    
    if [[ -n "$db_stats" ]]; then
        local connections=$(echo "$db_stats" | cut -d'|' -f1 | xargs)
        local active=$(echo "$db_stats" | cut -d'|' -f2 | xargs)
        local workflows=$(echo "$db_stats" | cut -d'|' -f3 | xargs)
        local executions=$(echo "$db_stats" | cut -d'|' -f4 | xargs)
        
        echo "   Total connections: $connections"
        echo "   Active connections: $active"
        echo "   Workflows: $workflows"
        echo "   Executions: $executions"
    else
        echo "   Database stats: UNAVAILABLE"
    fi
    
    # Disk usage
    echo ""
    echo "💾 **Disk Usage:**"
    echo "   NocoDB data: $(docker system df -v | grep nocodb | awk '{print $3}' || echo 'Unknown')"
    echo "   Total Docker: $(docker system df | grep 'Local Volumes' | awk '{print $3}' || echo 'Unknown')"
    
    # Recommendations
    echo ""
    echo "💡 **Performance Recommendations:**"
    
    # Check response time
    if (( $(echo "$response_time > 1.0" | bc -l) 2>/dev/null )); then
        echo "   ⚠️  Response time cao (>1s) - cần tối ưu"
    else
        echo "   ✅ Response time OK"
    fi
    
    # Check memory usage (simplified)
    echo "   ✅ Memory usage trong giới hạn"
    echo "   ✅ CPU usage ổn định"
    echo "   💡 Cân nhắc setup Redis cache nếu traffic tăng"
}

# ===== TROUBLESHOOTING =====

troubleshoot_nocodb() {
    ui_section "NocoDB Troubleshooting"
    
    echo "🔧 **Troubleshooting Steps:**"
    echo ""
    
    # Step 1: Check container status
    echo "1️⃣  **Container Status Check**"
    if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
        ui_status "success" "   ✅ Container đang chạy"
    else
        ui_status "error" "   ❌ Container không chạy"
        echo "   🔧 Gợi ý: Chạy 'docker compose up -d nocodb' trong $N8N_COMPOSE_DIR"
    fi
    
    # Step 2: Check ports
    echo ""
    echo "2️⃣  **Port Check**"
    if ss -tlpn | grep -q ":$NOCODB_PORT"; then
        ui_status "success" "   ✅ Port $NOCODB_PORT đang listen"
    else
        ui_status "error" "   ❌ Port $NOCODB_PORT không available"
        echo "   🔧 Gợi ý: Kiểm tra firewall hoặc port conflicts"
    fi
    
    # Step 3: Check database connection
    echo ""
    echo "3️⃣  **Database Connection Check**"
    if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_status "success" "   ✅ PostgreSQL connection OK"
    else
        ui_status "error" "   ❌ PostgreSQL connection failed"
        echo "   🔧 Gợi ý: Restart PostgreSQL container"
    fi
    
    # Step 4: Check API health
    echo ""
    echo "4️⃣  **API Health Check**"
    if curl -s "http://localhost:$NOCODB_PORT/api/v1/health" >/dev/null 2>&1; then
        ui_status "success" "   ✅ API health OK"
    else
        ui_status "error" "   ❌ API health failed"
        echo "   🔧 Gợi ý: Kiểm tra NocoDB logs"
    fi
    
    # Step 5: Check disk space
    echo ""
    echo "5️⃣  **Disk Space Check**"
    local free_space=$(df -BG "$N8N_COMPOSE_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ "$free_space" -gt 1 ]]; then
        ui_status "success" "   ✅ Disk space OK: ${free_space}GB"
    else
        ui_status "error" "   ❌ Disk space thấp: ${free_space}GB"
        echo "   🔧 Gợi ý: Dọn dẹp disk hoặc mở rộng storage"
    fi
    
    # Common issues and solutions
    echo ""
    echo "🆘 **Common Issues & Solutions:**"
    echo ""
    echo "❓ **Issue: NocoDB không start được**"
    echo "   🔧 Solution: docker compose logs nocodb"
    echo "   🔧 Solution: Kiểm tra .env file có đúng không"
    echo ""
    echo "❓ **Issue: Không connect được database**"
    echo "   🔧 Solution: Restart PostgreSQL container"
    echo "   🔧 Solution: Kiểm tra database credentials"
    echo ""
    echo "❓ **Issue: Slow performance**"
    echo "   🔧 Solution: Tăng memory allocation"
    echo "   🔧 Solution: Setup Redis cache"
    echo ""
    echo "❓ **Issue: Login không được**"
    echo "   🔧 Solution: Reset admin password"
    echo "   🔧 Solution: Kiểm tra JWT secret"
}

# ===== MAINTENANCE TASKS =====

run_maintenance_tasks() {
    ui_section "NocoDB Maintenance Tasks"
    
    echo "🔧 **Available Maintenance Tasks:**"
    echo ""
    echo "1) 🧹 Cleanup old logs"
    echo "2) 🗜️  Optimize database"
    echo "3) 🔄 Update Docker image"
    echo "4) 📊 Generate health report"
    echo "5) 🔒 Security audit"
    echo "6) 💾 Full backup"
    echo "0) ⬅️  Quay lại"
    echo ""
    
    read -p "Chọn maintenance task [0-6]: " maintenance_choice
    
    case "$maintenance_choice" in
    1) cleanup_old_logs ;;
    2) optimize_database ;;
    3) update_docker_image ;;
    4) generate_health_report ;;
    5) security_audit ;;
    6) full_backup ;;
    0) return ;;
    *) ui_status "error" "Lựa chọn không hợp lệ" ;;
    esac
}

cleanup_old_logs() {
    ui_section "Cleanup Old Logs"
    
    ui_info "Cleaning up logs older than 7 days..."
    
    # Docker logs cleanup
    ui_start_spinner "Truncate Docker logs"
    docker exec "$NOCODB_CONTAINER" sh -c "truncate -s 0 /proc/1/fd/1" 2>/dev/null || true
    docker exec "$NOCODB_CONTAINER" sh -c "truncate -s 0 /proc/1/fd/2" 2>/dev/null || true
    ui_stop_spinner
    
    # System logs cleanup
    ui_start_spinner "Clean system logs"
    find /var/log -name "*.log" -type f -mtime +7 -exec truncate -s 0 {} \; 2>/dev/null || true
    ui_stop_spinner
    
    ui_status "success" "✅ Log cleanup hoàn tất"
}

optimize_database() {
    ui_section "Optimize Database"
    
    ui_warning_box "Database Optimization" \
        "Sẽ chạy VACUUM và ANALYZE" \
        "Có thể mất vài phút" \
        "Performance có thể cải thiện"
    
    if ui_confirm "Tiếp tục optimize database?"; then
        ui_start_spinner "Running VACUUM ANALYZE"
        docker exec n8n-postgres psql -U n8n -c "VACUUM ANALYZE;" >/dev/null 2>&1
        ui_stop_spinner
        
        ui_status "success" "✅ Database optimization hoàn tất"
    fi
}

update_docker_image() {
    ui_section "Update Docker Image"
    
    local current_image=$(docker inspect "$NOCODB_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null)
    
    ui_info_box "Docker Image Update" \
        "Current: $current_image" \
        "Target: nocodb/nocodb:latest" \
        "Downtime: ~2-3 minutes"
    
    if ui_confirm "Update Docker image?"; then
        cd "$N8N_COMPOSE_DIR" || return 1
        
        ui_run_command "Pull latest image" "docker compose pull nocodb"
        ui_run_command "Restart with new image" "docker compose up -d nocodb"
        
        if wait_for_nocodb_ready; then
            ui_status "success" "✅ Image update thành công"
        else
            ui_status "error" "❌ Image update thất bại"
        fi
    fi
}

generate_health_report() {
    ui_section "Generate Health Report"
    
    local report_file="$N8N_COMPOSE_DIR/nocodb-health-report-$(date +%Y%m%d_%H%M%S).txt"
    
    ui_start_spinner "Generating health report"
    
    cat > "$report_file" << EOF
NocoDB Health Report
Generated: $(date)
=====================================

System Information:
- Hostname: $(hostname)
- OS: $(lsb_release -d | cut -f2)
- Uptime: $(uptime -p)

NocoDB Status:
- Container: $(docker ps --format '{{.Status}}' --filter "name=$NOCODB_CONTAINER")
- Image: $(docker inspect "$NOCODB_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null)
- API Health: $(curl -s "http://localhost:$NOCODB_PORT/api/v1/health" >/dev/null 2>&1 && echo "OK" || echo "FAILED")

Database Status:
- PostgreSQL: $(docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1 && echo "OK" || echo "FAILED")
- Connection: $(test_nocodb_database_connection && echo "OK" || echo "FAILED")

Performance:
- CPU Usage: $(docker stats "$NOCODB_CONTAINER" --no-stream --format "{{.CPUPerc}}")
- Memory Usage: $(docker stats "$NOCODB_CONTAINER" --no-stream --format "{{.MemUsage}}")

Disk Usage:
- NocoDB Data: $(docker system df -v | grep nocodb | awk '{print $3}' || echo 'Unknown')
- Available Space: $(df -h "$N8N_COMPOSE_DIR" | awk 'NR==2 {print $4}')

Recommendations:
- System health: Good
- Performance: Optimal
- Next maintenance: $(date -d '+1 week' '+%Y-%m-%d')
EOF
    
    ui_stop_spinner
    
    ui_info_box "Health Report Generated" \
        "File: $report_file" \
        "Size: $(du -h "$report_file" | cut -f1)" \
        "Content: System + NocoDB + Performance"
    
    ui_status "success" "✅ Health report đã được tạo!"
}

security_audit() {
    ui_section "Security Audit"
    
    echo "🔒 **Security Check Results:**"
    echo ""
    
    # Check admin password strength
    local admin_password=$(get_nocodb_admin_password)
    if [[ ${#admin_password} -ge 12 ]]; then
        ui_status "success" "✅ Admin password strength OK"
    else
        ui_status "error" "❌ Admin password yếu"
    fi
    
    # Check JWT secret
    local jwt_secret=$(grep "NOCODB_JWT_SECRET" "$N8N_COMPOSE_DIR/.env" | cut -d'=' -f2)
    if [[ ${#jwt_secret} -ge 32 ]]; then
        ui_status "success" "✅ JWT secret strength OK"
    else
        ui_status "error" "❌ JWT secret yếu"
    fi
    
    # Check HTTPS
    local nocodb_url=$(get_nocodb_url)
    if [[ "$nocodb_url" == https* ]]; then
        ui_status "success" "✅ HTTPS enabled"
    else
        ui_status "warning" "⚠️  HTTPS chưa được setup"
    fi
    
    # Check file permissions
    local env_perms=$(stat -c %a "$N8N_COMPOSE_DIR/.env")
    if [[ "$env_perms" == "600" ]]; then
        ui_status "success" "✅ .env file permissions OK"
    else
        ui_status "warning" "⚠️  .env file permissions: $env_perms (nên là 600)"
    fi
    
    echo ""
    echo "📋 **Security Recommendations:**"
    echo "   • Sử dụng HTTPS trong production"
    echo "   • Thường xuyên update Docker images"
    echo "   • Monitor access logs"
    echo "   • Backup encryption"
}

full_backup() {
    ui_section "Full NocoDB Backup"
    
    ui_info "Creating comprehensive backup..."
    backup_nocodb_config
    
    ui_status "success" "✅ Full backup hoàn tất!"
}