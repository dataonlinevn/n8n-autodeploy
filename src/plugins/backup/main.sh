[[ -n "${BACKUP_MAIN_LOADED:-}" ]] && return 0
readonly BACKUP_MAIN_LOADED=true

set -euo pipefail

# Source core modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$PLUGIN_DIR")")")"

# Source modules if not loaded
[[ -z "${LOGGER_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
[[ -z "${CONFIG_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
[[ -z "${UTILS_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
[[ -z "${UI_LOADED:-}" ]] && source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"

# Load backup sub-modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_DIR/backup-utils.sh"
source "$PLUGIN_DIR/backup-gdrive.sh"
source "$PLUGIN_DIR/backup-scheduler.sh"

# Constants
readonly BACKUP_BASE_DIR="/opt/n8n/backups"
readonly RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
readonly CRON_JOB_NAME="n8n-backup"

# ===== BACKUP FUNCTIONS =====

# Tạo backup toàn diện N8N + NocoDB
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="n8n_backup_${timestamp}"
    local backup_dir="$BACKUP_BASE_DIR/$backup_name"

    log_info " Bắt đầu quy trình sao lưu hệ thống..." >&2

    # Tạo thư mục backup (only use sudo when needed)
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        if [[ -w "$(dirname "$BACKUP_BASE_DIR")" ]]; then
            mkdir -p "$BACKUP_BASE_DIR"
        else
            sudo mkdir -p "$BACKUP_BASE_DIR"
        fi
    fi
    
    if [[ -w "$BACKUP_BASE_DIR" ]]; then
        mkdir -p "$backup_dir"
    else
        sudo mkdir -p "$backup_dir"
    fi

    # 1. Backup PostgreSQL N8N database
    log_info "Đang sao lưu cơ sở dữ liệu..." >&2
    if docker exec n8n-postgres pg_dump -U n8n n8n >"$backup_dir/n8n_database.sql" 2>/dev/null; then
        log_success "Sao lưu dữ liệu thành công" >&2
    else
        log_error "Sao lưu dữ liệu thất bại" >&2
        return 1
    fi

    # 2. Backup N8N data files
    log_info "Đang sao lưu tệp tin cấu hình..." >&2
    local n8n_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_n8n_data 2>/dev/null)

    if [[ -n "$n8n_volume" ]]; then
        if [[ -w "$backup_dir" ]]; then
            tar -czf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume" . 2>/dev/null || {
                sudo tar -czf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume" . 2>/dev/null
            }
        else
            sudo tar -czf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume" . 2>/dev/null
        fi
        log_success "Sao lưu tệp tin thành công" >&2
    else
        log_error "Lỗi: Không tìm thấy thư mục lưu trữ ứng dụng" >&2
        return 1
    fi

    # 3. Backup NocoDB (nếu có cài đặt)
    local nocodb_installed=false
    if docker ps --format '{{.Names}}' | grep -q "^n8n-nocodb$" || [[ -f "/opt/n8n/.nocodb-admin-password" ]]; then
        nocodb_installed=true
        log_info "Đang sao lưu NocoDB..." >&2
        
        # 3a. Backup NocoDB database
        local nocodb_db_mode=$(grep "NOCODB_DATABASE_MODE=" "/opt/n8n/.env" 2>/dev/null | cut -d'=' -f2 || echo "shared")
        if [[ "$nocodb_db_mode" == "separate" ]]; then
            if docker exec n8n-postgres pg_dump -U nocodb nocodb >"$backup_dir/nocodb_database.sql" 2>/dev/null; then
                log_success "Sao lưu dữ liệu NocoDB thành công" >&2
            else
                log_warning "Lỗi sao lưu cơ sở dữ liệu NocoDB" >&2
            fi
        fi
        
        # 3b. Backup NocoDB data volume
        local nocodb_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_nocodb_data 2>/dev/null)
        if [[ -n "$nocodb_volume" ]]; then
            if [[ -w "$backup_dir" ]]; then
                tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null || {
                    sudo tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null
                }
            else
                sudo tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null
            fi
            log_success "Sao lưu tệp tin NocoDB thành công" >&2
        fi
    fi

    # 4. Backup docker-compose và config chung
    log_info "Đang sao lưu thông số hệ thống..." >&2
    if [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        cp /opt/n8n/docker-compose.yml "$backup_dir/" 2>/dev/null || \
        sudo cp /opt/n8n/docker-compose.yml "$backup_dir/"
    fi
    
    if [[ -f "/opt/n8n/.env" ]]; then
        cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || \
        sudo cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || true
    fi
    log_success "Sao lưu thông số hoàn tất" >&2

    # 5. Tạo comprehensive metadata
    local n8n_version=$(docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    local nocodb_version=$(docker inspect n8n-nocodb --format '{{.Config.Image}}' 2>/dev/null | cut -d':' -f2 || echo "not_installed")
    
    cat >"$backup_dir/metadata.json" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "backup_type": "comprehensive",
    "components": {
        "n8n": {
            "version": "$n8n_version",
            "database": "included",
            "data_volume": "included",
            "config": "included"
        },
        "nocodb": {
            "installed": $nocodb_installed,
            "version": "$nocodb_version",
            "database_mode": "${nocodb_db_mode:-none}",
            "database": "$( [ "${nocodb_db_mode:-}" == "separate" ] && echo "included" || echo "shared_with_n8n" )",
            "data_volume": "$( [ "$nocodb_installed" == "true" ] && echo "included" || echo "not_applicable" )",
            "admin_password": "$( [ -f "/opt/n8n/.nocodb-admin-password" ] && echo "included" || echo "not_found" )",
            "ssl_config": "$( [ -n "${nocodb_domain:-}" ] && echo "included" || echo "not_configured" )"
        }
    },
    "manager_config": "included",
    "docker_compose": "included",
    "environment": "included",
    "backup_size": "$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "calculating...")"
}
EOF

    # 6. Nén toàn bộ backup
    log_info " Đang nén comprehensive backup..." >&2
    cd "$BACKUP_BASE_DIR"
    
    if [[ -w "$BACKUP_BASE_DIR" ]]; then
        tar -czf "${backup_name}.tar.gz" "$backup_name" 2>/dev/null && \
        rm -rf "$backup_name"
    else
        sudo tar -czf "${backup_name}.tar.gz" "$backup_name" 2>/dev/null && \
        sudo rm -rf "$backup_name"
    fi

    # 7. Tạo backup summary
    local final_size=$(du -sh "${BACKUP_BASE_DIR}/${backup_name}.tar.gz" 2>/dev/null | cut -f1 || echo "unknown")
    log_success "[OK] Quy trình sao lưu hoàn tất: ${backup_name}.tar.gz ($final_size)" >&2
    
    ui_info_box "Tổng kết sao lưu" \
        "Tên file: ${backup_name}.tar.gz" \
        "Kích thước: $final_size" \
        "Nội dung: n8n Database, n8n Data, Cấu hình hệ thống$([[ "$nocodb_installed" == "true" ]] && echo ", NocoDB Data")" \
        "Vị trí: $BACKUP_BASE_DIR"

    # Chỉ echo đường dẫn file, không có log messages
    echo "$BACKUP_BASE_DIR/${backup_name}.tar.gz"
}

# Cleanup backup cũ 
cleanup_old_backups() {
    local retention_days=$(config_get "backup.retention_days" "30")

    # Xử lý trường hợp retention = 0 (xóa tất cả)
    if [[ $retention_days -eq 0 ]]; then
        log_info " Dọn dẹp TẤT CẢ backup (retention = 0 ngày)..."
    else
        log_info " Dọn dẹp backup cũ hơn $retention_days ngày..."
    fi

    # Local cleanup - đếm số files trước khi xóa
    local local_files_before=$(find "$BACKUP_BASE_DIR" -name "n8n_backup_*.tar.gz" 2>/dev/null | wc -l)
    local deleted_local=0
    
    # Tìm và xóa files cũ
    if [[ $retention_days -eq 0 ]]; then
        # Retention = 0: xóa tất cả files
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                rm -f "$file" 2>/dev/null && ((deleted_local++)) || true
            fi
        done < <(find "$BACKUP_BASE_DIR" -name "n8n_backup_*.tar.gz" 2>/dev/null)
    else
        # Retention > 0: chỉ xóa files cũ hơn retention_days
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                rm -f "$file" 2>/dev/null && ((deleted_local++)) || true
            fi
        done < <(find "$BACKUP_BASE_DIR" -name "n8n_backup_*.tar.gz" -mtime +$retention_days 2>/dev/null)
    fi
    
    local local_files_after=$(find "$BACKUP_BASE_DIR" -name "n8n_backup_*.tar.gz" 2>/dev/null | wc -l)
    
    if [[ $deleted_local -gt 0 ]]; then
        if [[ $retention_days -eq 0 ]]; then
            log_success "[OK] Đã xóa TẤT CẢ $deleted_local file backup local"
        else
            log_success "[OK] Đã xóa $deleted_local file backup local (còn lại: $local_files_after files)"
        fi
    else
        if [[ $retention_days -eq 0 ]]; then
            log_info "  Không có file backup local nào để xóa"
        else
            log_info "  Không có file backup local nào cũ hơn $retention_days ngày (tổng: $local_files_after files)"
        fi
    fi

    # Google Drive cleanup (if configured)
    if [[ -f "$RCLONE_CONFIG" ]]; then
        local remote_name
        if remote_name=$(get_gdrive_remote_name); then
            # Đếm số files trên Google Drive trước khi xóa
            local gdrive_files_before=$(rclone ls "${remote_name}:n8n-backups/" --include "n8n_backup_*.tar.gz" 2>/dev/null | wc -l)
            
            # Xóa files cũ
            if [[ $retention_days -eq 0 ]]; then
                # Retention = 0: xóa tất cả files
                rclone delete "${remote_name}:n8n-backups" --include "n8n_backup_*.tar.gz" 2>/dev/null || true
            else
                # Retention > 0: chỉ xóa files cũ hơn retention_days
                rclone delete "${remote_name}:n8n-backups" --min-age "${retention_days}d" --include "n8n_backup_*.tar.gz" 2>/dev/null || true
            fi
            
            # Đếm số files sau khi xóa
            local gdrive_files_after=$(rclone ls "${remote_name}:n8n-backups/" --include "n8n_backup_*.tar.gz" 2>/dev/null | wc -l)
            local deleted_gdrive=$((gdrive_files_before - gdrive_files_after))
            
            if [[ $deleted_gdrive -gt 0 ]]; then
                if [[ $retention_days -eq 0 ]]; then
                    log_success "[OK] Đã xóa TẤT CẢ $deleted_gdrive file backup trên Google Drive"
                else
                    log_success "[OK] Đã xóa $deleted_gdrive file backup trên Google Drive (còn lại: $gdrive_files_after files)"
                fi
            else
                if [[ $retention_days -eq 0 ]]; then
                    log_info "  Không có file backup nào trên Google Drive để xóa"
                else
                    log_info "  Không có file backup nào trên Google Drive cũ hơn $retention_days ngày (tổng: $gdrive_files_after files)"
                fi
            fi
        else
            log_warn "[WARN]  Không tìm thấy Google Drive remote để dọn dẹp"
        fi
    fi
}

# ===== RESTORE FUNCTIONS =====

restore_backup() {
    local backup_file="$1"

    log_info " Bắt đầu restore từ backup..."

    # Kiểm tra file backup
    if [[ ! -f "$backup_file" ]]; then
        log_error "[FAIL] File backup không tồn tại: $backup_file"
        return 1
    fi

    # Extract backup
    local temp_dir="/tmp/n8n_restore_$(date +%s)"
    mkdir -p "$temp_dir"

    log_info "📦 Đang giải nén backup..."
    tar -xzf "$backup_file" -C "$temp_dir"

    # FIX: Tìm backup directory đúng cách
    local backup_dir=$(find "$temp_dir" -name "n8n_backup_*" -type d | head -1)
    
    if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then
        log_error "[FAIL] Không tìm thấy backup directory trong archive"
        rm -rf "$temp_dir"
        return 1
    fi

    # FIX: Kiểm tra file database tồn tại với tên chính xác
    local db_file=""
    if [[ -f "$backup_dir/n8n_database.sql" ]]; then
        db_file="$backup_dir/n8n_database.sql"
    elif [[ -f "$backup_dir/database.sql" ]]; then
        db_file="$backup_dir/database.sql"
    elif [[ -f "$backup_dir/n8n_database.sql.gz" ]]; then
        # Giải nén nếu file bị compress
        gunzip "$backup_dir/n8n_database.sql.gz"
        db_file="$backup_dir/n8n_database.sql"
    else
        log_error "[FAIL] Không tìm thấy database backup file"
        log_info " Files có sẵn trong backup:"
        ls -la "$backup_dir"
        rm -rf "$temp_dir"
        return 1
    fi

    # Stop n8n
    log_info " Dừng n8n services..."
    cd /opt/n8n
    docker compose down 2>/dev/null || sudo docker compose down

    # Restore database
    log_info " Restore database..."
    docker compose up -d postgres 2>/dev/null || sudo docker compose up -d postgres
    sleep 5

    # Wait for PostgreSQL to be ready
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
            break
        fi
        sleep 1
        ((waited++))
    done

    # Drop and recreate schema
    docker exec -i n8n-postgres psql -U n8n -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" 2>/dev/null
    
    # FIX: Restore với file đúng
    if docker exec -i n8n-postgres psql -U n8n n8n < "$db_file"; then
        log_success "[OK] Database restore thành công"
    else
        log_error "[FAIL] Database restore thất bại"
        rm -rf "$temp_dir"
        return 1
    fi

    # Restore data files nếu có
    if [[ -f "$backup_dir/n8n_data.tar.gz" ]]; then
        log_info "📁 Restore data files..."
        local n8n_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_n8n_data 2>/dev/null)
        
        if [[ -n "$n8n_volume" ]]; then
            # Remove old data and restore
            if [[ -w "$n8n_volume" ]]; then
                rm -rf "$n8n_volume"/*
                tar -xzf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume"
            else
                sudo rm -rf "$n8n_volume"/*
                sudo tar -xzf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume"
            fi
            log_success "[OK] Data files restore thành công"
        else
            log_warning "[WARN] Không tìm thấy N8N data volume"
        fi
    fi

    # Restore NocoDB nếu có
    if [[ -f "$backup_dir/nocodb_data.tar.gz" ]]; then
        log_info " Restore NocoDB data..."
        local nocodb_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_nocodb_data 2>/dev/null)
        
        if [[ -n "$nocodb_volume" ]]; then
            if [[ -w "$nocodb_volume" ]]; then
                rm -rf "$nocodb_volume"/*
                tar -xzf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume"
            else
                sudo rm -rf "$nocodb_volume"/*
                sudo tar -xzf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume"
            fi
            log_success "[OK] NocoDB data restore thành công"
        fi
    fi

    # Restore configuration files
    if [[ -f "$backup_dir/docker-compose.yml" ]]; then
        log_info " Restore configuration..."
        cp "$backup_dir/docker-compose.yml" /opt/n8n/ 2>/dev/null || \
        sudo cp "$backup_dir/docker-compose.yml" /opt/n8n/
        
        if [[ -f "$backup_dir/.env" ]]; then
            cp "$backup_dir/.env" /opt/n8n/ 2>/dev/null || \
            sudo cp "$backup_dir/.env" /opt/n8n/
        fi
        
        log_success "[OK] Configuration restore thành công"
    fi

    # Start n8n
    log_info " Khởi động lại n8n..."
    docker compose up -d 2>/dev/null || sudo docker compose up -d

    # Wait for N8N to be ready
    log_info " Chờ N8N khởi động..."
    local n8n_port=$(grep "N8N_PORT=" /opt/n8n/.env | cut -d'=' -f2 2>/dev/null || echo "5678")
    
    local max_wait=60
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$n8n_port/healthz" >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((waited += 2))
    done

    # Cleanup
    rm -rf "$temp_dir"

    if [[ $waited -lt $max_wait ]]; then
        ui_success "Khôi phục hệ thống thành công!"
        
        # Show restored info
        local metadata_file="$backup_dir/metadata.json"
        if [[ -f "$metadata_file" ]] && command_exists jq; then
            local backup_timestamp=$(jq -r '.timestamp' "$metadata_file" 2>/dev/null || echo "unknown")
            local n8n_version=$(jq -r '.components.n8n.version' "$metadata_file" 2>/dev/null || echo "unknown")
            
            ui_info_box "Thông tin khôi phục" \
                "Thời điểm sao lưu: $backup_timestamp" \
                "Phiên bản n8n: $n8n_version" \
                "Trạng thái: Hoàn thành khôi phục toàn bộ dữ liệu"
        fi
        
        return 0
    else
        ui_error "Lỗi: Ứng dụng n8n không thể khởi động lại sau khi khôi phục"
        return 1
    fi
}

# ===== MENU FUNCTIONS =====

# Menu chính backup
backup_menu_main() {
    ui_header "Quản lý Sao lưu & Khôi phục"

    while true; do
        # Show current Google Drive status
        local remote_name=$(get_saved_gdrive_remote_name)
        local status_str="Chưa cấu hình"
        [[ -n "$remote_name" ]] && status_str="Đã cấu hình (remote: $remote_name)"
        
        ui_section "Kết nối Đám mây"
        echo -e "Google Drive: $status_str"
        echo ""

        echo "CÔNG CỤ SAO LƯU"
        echo "  1) Tạo bản sao lưu ngay"
        echo "  2) Khôi phục từ bản sao lưu"
        echo "  3) Danh sách các bản sao lưu"
        echo ""
        echo "CẤU HÌNH & TỰ ĐỘNG"
        echo "  4) Cấu hình tự động sao lưu"
        echo "  5) Thiết lập Google Drive"
        echo "  6) Dọn dẹp dữ liệu cũ"
        echo ""
        echo "  0) Quay lại"
        echo ""

        choice=$(ui_prompt "Chọn chức năng" "0" "^[0-6]$")

        case "$choice" in
        1) backup_create_now ;;
        2) backup_restore_menu ;;
        3) backup_list ;;
        4) backup_schedule_menu ;;
        5) setup_google_drive ;;
        6) backup_cleanup_menu ;;
        0) return ;;
        *) ui_error "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
        ui_header "Quản lý Sao lưu & Khôi phục"
    done
}

# Cải thiện function backup_create_now
backup_create_now() {
    ui_header "Tạo bản sao lưu"

    local backup_file
    backup_file=$(create_backup)

    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        # Hỏi upload Google Drive
        if [[ -f "$RCLONE_CONFIG" ]]; then
            local remote_name=$(get_gdrive_remote_name || echo "")
            if [[ -n "$remote_name" ]]; then
                echo ""
                if ui_confirm "Bạn có muốn tải bản sao lưu này lên Google Drive ngay không?"; then
                    upload_to_gdrive "$backup_file"
                fi
            fi
        fi
    else
        ui_error "Quy trình sao lưu gặp lỗi"
    fi
}

# Menu restore
backup_restore_menu() {
    ui_header "Khôi phục dữ liệu"

    # Liệt kê backup local
    echo "Danh sách bản sao lưu hiện có:"
    local backups=($(ls -t "$BACKUP_BASE_DIR"/n8n_backup_*.tar.gz 2>/dev/null))

    if [[ ${#backups[@]} -eq 0 ]]; then
        ui_warning "Không tìm thấy bản sao lưu nào trong hệ thống"
        return 1
    fi

    for i in "${!backups[@]}"; do
        local backup="${backups[$i]}"
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1)
        echo "$((i + 1))) $(basename "$backup") ($size) - $date"
    done

    echo ""
    local choice=$(ui_prompt "Chọn bản sao lưu muốn khôi phục" "1" "^[0-9]+$")

    if [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice - 1))]}"

        ui_warning_box "CẢNH BÁO QUAN TRỌNG" \
            "Hành động khôi phục sẽ GHI ĐÈ toàn bộ dữ liệu hiện tại." \
            "Dữ liệu mới phát sinh sau thời điểm sao lưu sẽ bị mất." \
            "Tên file: $(basename "$selected_backup")"

        if ui_confirm "Bạn có chắc chắn muốn thực hiện khôi phục không?"; then
            restore_backup "$selected_backup"
        fi
    else
        ui_error "Lựa chọn không hợp lệ"
    fi
}

# Menu lịch backup
backup_schedule_menu() {
    ui_section "Cấu hình Tự động Sao lưu"

    echo "Tần suất sao lưu:"
    echo "1) Hàng ngày"
    echo "2) Hàng tuần"
    echo "3) Hàng tháng (mặc định)"
    echo ""

    freq_choice=$(ui_prompt "Chọn tần suất" "3" "^[1-3]$")

    local frequency="monthly"
    case "$freq_choice" in
    1) frequency="daily" ;;
    2) frequency="weekly" ;;
    3) frequency="monthly" ;;
    esac

    hour=$(ui_prompt "Giờ thực hiện (0-23)" "2" "^([0-9]|1[0-9]|2[0-3])$")

    if setup_cron_job "$frequency" "$hour"; then
        config_set "backup.schedule" "$frequency"
        config_set "backup.hour" "$hour"
        
        ui_success "Đã cấu hình tự động sao lưu: $frequency lúc $hour:00"
    else
        ui_error "Cấu hình tự động sao lưu thất bại"
    fi
}

# Liệt kê backup
backup_list() {
    log_info " DANH SÁCH BACKUP"
    echo ""

    echo "=== Backup Local ==="
    if [[ -d "$BACKUP_BASE_DIR" ]]; then
        ls -lh "$BACKUP_BASE_DIR"/n8n_backup_*.tar.gz 2>/dev/null || echo "Không có backup"
    fi

    echo ""

    if [[ -f "$RCLONE_CONFIG" ]]; then
        local remote_name=$(get_gdrive_remote_name || echo "")
        if [[ -n "$remote_name" ]]; then
            echo "=== Backup Google Drive (remote: $remote_name) ==="
            rclone ls "${remote_name}:n8n-backups/" 2>/dev/null || echo "Không thể truy cập Google Drive hoặc chưa có backup"
        else
            echo "=== Google Drive ==="
            echo "Chưa cấu hình hoặc không tìm thấy remote"
        fi
    fi
}

# Menu cleanup
backup_cleanup_menu() {
    log_info " DỌN DẸP BACKUP CŨ"
    echo ""

    local retention_days=$(config_get "backup.retention_days" "30")
    echo "Retention hiện tại: $retention_days ngày"
    echo ""

    read -p "Nhập số ngày retention mới (Enter để giữ nguyên): " new_retention

    if [[ -n "$new_retention" ]] && [[ "$new_retention" =~ ^[0-9]+$ ]]; then
        config_set "backup.retention_days" "$new_retention"
        retention_days=$new_retention
    fi

    cleanup_old_backups
}

# ===== INIT FUNCTION =====

# Khởi tạo backup khi cài n8n
init_backup_on_install() {
    log_info " Khởi tạo backup tự động..."

    # Tạo thư mục backup
    if [[ -w "/opt/n8n" ]]; then
        mkdir -p "$BACKUP_BASE_DIR"
    else
        sudo mkdir -p "$BACKUP_BASE_DIR"
    fi

    # Setup cron job mặc định (monthly)
    setup_cron_job "monthly" "2"

    # Tạo manager environment file
    cat > /tmp/manager-env.sh << EOF
# DataOnline N8N Manager Environment
export MANAGER_PATH="$PLUGIN_PROJECT_ROOT"
export BACKUP_DIR="$BACKUP_BASE_DIR"
EOF

    if [[ -w "/opt/n8n" ]]; then
        cp /tmp/manager-env.sh /opt/n8n/manager-env.sh
    else
        sudo cp /tmp/manager-env.sh /opt/n8n/manager-env.sh
    fi
    rm -f /tmp/manager-env.sh

    log_success "[OK] Đã cài đặt backup tự động hàng tháng"
}

# Export functions
export -f backup_menu_main
export -f init_backup_on_install
export -f create_backup
export -f cleanup_old_backups