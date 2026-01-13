#!/bin/bash

# DataOnline N8N Manager - Backup Manager Module
# Phiên bản: 1.0.0
# Quản lý backup trước nâng cấp N8N, bao gồm tạo, phục hồi và xác minh backup

set -euo pipefail

# ===== BACKUP CREATION =====

create_upgrade_backup() {
    ui_section "Sao lưu dữ liệu bảo mật"
    
    # Generate backup ID
    BACKUP_ID="upgrade_$(date +%Y%m%d_%H%M%S)"
    local backup_dir="$BACKUP_BASE_DIR/$BACKUP_ID"
    
    ui_start_spinner "Đang tạo bản sao lưu dữ liệu..."
    
    # Create backup directory
    mkdir -p "$backup_dir"
    chmod 755 "$backup_dir"
    
    # Create backup metadata
    create_backup_metadata "$backup_dir" >/dev/null 2>&1
    
    # Backup database
    if ! backup_database "$backup_dir" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_error "Lỗi sao lưu cơ sở dữ liệu"
        return 1
    fi
    
    # Backup N8N data volume
    if ! backup_n8n_data "$backup_dir" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_error "Lỗi sao lưu tệp tin ứng dụng"
        return 1
    fi
    
    # Backup configuration files
    backup_configuration "$backup_dir" >/dev/null 2>&1
    
    # Verify backup
    if ! verify_backup "$backup_dir" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_error "Bản sao lưu không hợp lệ"
        return 1
    fi
    
    ui_stop_spinner
    ui_success "Đã tạo bản sao lưu an toàn."
    return 0
}

create_backup_metadata() {
    local backup_dir="$1"
    local metadata_file="$backup_dir/metadata.json"
    
    ui_start_spinner "Tạo metadata"
    
    cat > "$metadata_file" << EOF
{
    "backup_id": "$BACKUP_ID",
    "timestamp": "$(date -Iseconds)",
    "n8n_version": "$CURRENT_VERSION",
    "target_version": "$TARGET_VERSION",
    "backup_type": "upgrade",
    "components": ["database", "data_volume", "configuration"],
    "server_info": {
        "hostname": "$(hostname)",
        "os": "$(lsb_release -d | cut -f2)",
        "docker_version": "$(docker --version | cut -d' ' -f3 | cut -d',' -f1)"
    }
}
EOF
    
    ui_stop_spinner
    ui_status "success" "Metadata tạo thành công"
}

# ===== DATABASE BACKUP =====

backup_database() {
    local backup_dir="$1"
    local db_backup_file="$backup_dir/database.sql"
    
    if ! ui_run_command "Backup PostgreSQL database" "
        docker exec n8n-postgres pg_dump -U n8n n8n > '$db_backup_file'
    "; then
        return 1
    fi
    
    # Verify database backup
    if [[ ! -s "$db_backup_file" ]]; then
        ui_status "error" "Database backup file trống"
        return 1
    fi
    
    # Compress database backup
    if ! ui_run_command "Nén database backup" "
        gzip '$db_backup_file'
    "; then
        return 1
    fi
    
    return 0
}

# ===== N8N DATA BACKUP =====

backup_n8n_data() {
    local backup_dir="$1"
    local data_backup_file="$backup_dir/n8n_data.tar.gz"
    
    # Get N8N data volume path
    local n8n_volume=$(docker volume inspect n8n_n8n_data --format '{{ .Mountpoint }}' 2>/dev/null)
    
    if [[ -z "$n8n_volume" ]]; then
        ui_status "error" "Không tìm thấy N8N data volume"
        return 1
    fi
    
    if ! ui_run_command "Backup N8N data volume" "
        tar -czf '$data_backup_file' -C '$n8n_volume' .
    "; then
        return 1
    fi
    
    # Verify data backup
    if [[ ! -s "$data_backup_file" ]]; then
        ui_status "error" "Data backup file trống"
        return 1
    fi
    
    return 0
}

# ===== CONFIGURATION BACKUP =====

backup_configuration() {
    local backup_dir="$1"
    local config_dir="$backup_dir/config"
    
    if ! ui_run_command "Tạo thư mục config backup" "
        mkdir -p '$config_dir'
    "; then
        return 1
    fi
    
    # Backup docker-compose.yml
    if [[ -f "$N8N_COMPOSE_DIR/docker-compose.yml" ]]; then
        cp "$N8N_COMPOSE_DIR/docker-compose.yml" "$config_dir/"
    fi
    
    # Backup .env file
    if [[ -f "$N8N_COMPOSE_DIR/.env" ]]; then
        cp "$N8N_COMPOSE_DIR/.env" "$config_dir/"
    fi
    
    # Backup nginx config (if exists)
    local domain=$(config_get "n8n.domain" "")
    if [[ -n "$domain" && -f "/etc/nginx/sites-available/${domain}.conf" ]]; then
        mkdir -p "$config_dir/nginx"
        cp "/etc/nginx/sites-available/${domain}.conf" "$config_dir/nginx/"
    fi
    
    # Backup DataOnline manager config
    if [[ -f "$CONFIG_FILE" ]]; then
        mkdir -p "$config_dir/manager"
        cp "$CONFIG_FILE" "$config_dir/manager/"
    fi
    
    ui_info "Sao lưu cấu hình hoàn tất"
    return 0
}

# ===== BACKUP VERIFICATION =====

verify_backup() {
    local backup_dir="$1"
    local errors=0
    
    ui_start_spinner "Xác minh backup"
    
    # Check metadata
    if [[ ! -f "$backup_dir/metadata.json" ]]; then
        ui_status "error" "Thiếu metadata file"
        ((errors++))
    fi
    
    # Check database backup
    if [[ ! -f "$backup_dir/database.sql.gz" ]]; then
        ui_status "error" "Thiếu database backup"
        ((errors++))
    fi
    
    # Check data backup
    if [[ ! -f "$backup_dir/n8n_data.tar.gz" ]]; then
        ui_status "error" "Thiếu data backup"
        ((errors++))
    fi
    
    # Check config backup
    if [[ ! -d "$backup_dir/config" ]]; then
        ui_status "error" "Thiếu config backup"
        ((errors++))
    fi
    
    ui_stop_spinner
    
    if [[ $errors -eq 0 ]]; then
        ui_status "success" "Backup verification thành công"
        
        # Calculate backup size
        local backup_size=$(du -sh "$backup_dir" | cut -f1)
        ui_status "info" "Kích thước backup: $backup_size"
        return 0
    else
        ui_status "error" "Backup verification thất bại với $errors lỗi"
        return 1
    fi
}

# ===== ROLLBACK FUNCTIONALITY =====

rollback_upgrade() {
    local backup_id="$1"
    local backup_dir="$BACKUP_BASE_DIR/$backup_id"
    
    if [[ ! -d "$backup_dir" ]]; then
        ui_status "error" "Backup không tồn tại: $backup_id"
        return 1
    fi
    
    ui_section "Rollback từ backup: $backup_id"
    
    ui_warning_box "Cảnh báo Rollback" \
        "Tất cả thay đổi sau backup sẽ bị mất" \
        "Quá trình này không thể hoàn tác"
    
    if ! ui_confirm "Tiếp tục rollback?"; then
        return 1
    fi
    
    # Step 1: Stop N8N
    if ! ui_run_command "Dừng N8N services" "
        cd '$N8N_COMPOSE_DIR'
        docker compose down
    "; then
        return 1
    fi
    
    # Step 2: Restore database
    if ! restore_database "$backup_dir"; then
        ui_status "error" "Database restore thất bại"
        return 1
    fi
    
    # Step 3: Restore data volume
    if ! restore_n8n_data "$backup_dir"; then
        ui_status "error" "Data restore thất bại"
        return 1
    fi
    
    # Step 4: Restore configuration
    if ! restore_configuration "$backup_dir"; then
        ui_status "error" "Config restore thất bại"
        return 1
    fi
    
    # Step 5: Start N8N
    if ! ui_run_command "Khởi động N8N" "
        cd '$N8N_COMPOSE_DIR'
        docker compose up -d
    "; then
        return 1
    fi
    
    # Step 6: Verify rollback
    ui_start_spinner "Chờ N8N khởi động sau rollback"
    sleep 10
    ui_stop_spinner
    
    if verify_n8n_health; then
        ui_status "success" " Rollback thành công!"
        return 0
    else
        ui_status "error" "Rollback thất bại - kiểm tra logs"
        return 1
    fi
}

# ===== RESTORE FUNCTIONS =====

restore_database() {
    local backup_dir="$1"
    local db_backup_file="$backup_dir/database.sql.gz"
    
    if [[ ! -f "$db_backup_file" ]]; then
        ui_status "error" "Database backup không tồn tại"
        return 1
    fi
    
    # Start PostgreSQL
    if ! ui_run_command "Khởi động PostgreSQL" "
        cd '$N8N_COMPOSE_DIR'
        docker compose up -d postgres
        sleep 5
    "; then
        return 1
    fi
    
    # Drop and recreate database
    if ! ui_run_command "Reset database" "
        docker exec n8n-postgres psql -U n8n -c 'DROP SCHEMA public CASCADE; CREATE SCHEMA public;'
    "; then
        return 1
    fi
    
    # Restore database
    if ! ui_run_command "Restore database" "
        gunzip -c '$db_backup_file' | docker exec -i n8n-postgres psql -U n8n n8n
    "; then
        return 1
    fi
    
    return 0
}

restore_n8n_data() {
    local backup_dir="$1"
    local data_backup_file="$backup_dir/n8n_data.tar.gz"
    
    if [[ ! -f "$data_backup_file" ]]; then
        ui_status "error" "Data backup không tồn tại"
        return 1
    fi
    
    # Get volume mountpoint
    local n8n_volume=$(docker volume inspect n8n_n8n_data --format '{{ .Mountpoint }}' 2>/dev/null)
    
    if [[ -z "$n8n_volume" ]]; then
        ui_status "error" "Không tìm thấy N8N data volume"
        return 1
    fi
    
    # Clear and restore data
    if ! ui_run_command "Restore N8N data" "
        rm -rf '$n8n_volume'/*
        tar -xzf '$data_backup_file' -C '$n8n_volume'
    "; then
        return 1
    fi
    
    return 0
}

restore_configuration() {
    local backup_dir="$1"
    local config_dir="$backup_dir/config"
    
    if [[ ! -d "$config_dir" ]]; then
        ui_status "error" "Config backup không tồn tại"
        return 1
    fi
    
    # Restore docker-compose.yml
    if [[ -f "$config_dir/docker-compose.yml" ]]; then
        cp "$config_dir/docker-compose.yml" "$N8N_COMPOSE_DIR/"
    fi
    
    # Restore .env
    if [[ -f "$config_dir/.env" ]]; then
        cp "$config_dir/.env" "$N8N_COMPOSE_DIR/"
    fi
    
    ui_status "success" "Configuration restore hoàn tất"
    return 0
}

# ===== BACKUP MANAGEMENT =====

get_backup_info() {
    local backup_id="$1"
    local metadata_file="$BACKUP_BASE_DIR/$backup_id/metadata.json"
    
    if [[ -f "$metadata_file" ]] && command_exists jq; then
        local timestamp=$(jq -r '.timestamp' "$metadata_file" | cut -d'T' -f1)
        local from_version=$(jq -r '.n8n_version' "$metadata_file")
        echo "$timestamp (v$from_version)"
    else
        echo "No metadata"
    fi
}

cleanup_old_backups() {
    local retention_days="${1:-30}"
    
    ui_start_spinner "Dọn dẹp backup cũ hơn $retention_days ngày"
    
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "upgrade_*" -mtime +$retention_days -exec rm -rf {} \;
    
    ui_stop_spinner
    ui_status "success" "Cleanup backup hoàn tất"
}

verify_n8n_health() {
    local n8n_port=$(config_get "n8n.port" "5678")
    
    # Check API
    if ! curl -s "http://localhost:$n8n_port/healthz" >/dev/null 2>&1; then
        return 1
    fi
    
    # Check container
    if ! docker ps --format '{{.Names}}' | grep -q "n8n"; then
        return 1
    fi
    
    return 0
}

# ===== EXPORT FUNCTIONS =====

export -f create_upgrade_backup rollback_upgrade cleanup_old_backups get_backup_info