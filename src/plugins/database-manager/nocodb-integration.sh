#!/bin/bash

# DataOnline N8N Manager - NocoDB Integration Helpers
# Phiên bản: 1.0.0
# Mô tả: Integration helpers cho main manager

set -euo pipefail

# ===== INTEGRATION WITH MAIN MANAGER =====

add_to_main_manager() {
    ui_section "Tích hợp vào Main Manager"
    
    local main_script="$PLUGIN_PROJECT_ROOT/scripts/manager.sh"
    
    if [[ ! -f "$main_script" ]]; then
        ui_error "Không tìm thấy main manager script" "FILE_NOT_FOUND" "Kiểm tra đường dẫn: $main_script"
        return 1
    fi
    
    # Check if already integrated
    if grep -q "database_manager_main" "$main_script"; then
        ui_warning "Database Manager đã được tích hợp"
        return 0
    fi
    
    ui_info_box "Tích hợp Database Manager" \
        "Sẽ thêm menu option vào main manager" \
        "Option 6: Quản lý Database" \
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
    sed -i '/^echo -e "5) .*Cập nhật phiên bản"/a echo -e "6) Quản lý Database"' "$main_script"
    
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
    ui_success "Database Manager đã được tích hợp!"
    
    ui_info_box "Hoàn tất tích hợp" \
        "[OK] Đã thêm lựa chọn vào menu chính" \
        "[OK] Đã cấu hình bộ xử lý tự động" \
        "[OK] Đã tạo bản sao lưu an toàn" \
        "Bạn có thể kiểm tra bằng cách chạy lại Menu chính"
}

# Export functions
export -f add_to_main_manager integrate_database_manager_menu

