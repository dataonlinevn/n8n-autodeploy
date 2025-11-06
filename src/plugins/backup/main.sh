#!/bin/bash

# DataOnline N8N Manager - Plugin Backup
# Phiên bản: 1.0.0

set -euo pipefail

# Source core modules
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$PLUGIN_DIR")")"

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

    log_info "🔄 Bắt đầu backup toàn diện N8N + NocoDB..." >&2

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
    log_info "📦 Backup N8N database PostgreSQL..." >&2
    if docker exec n8n-postgres pg_dump -U n8n n8n >"$backup_dir/n8n_database.sql" 2>/dev/null; then
        log_success "✅ N8N database backup thành công" >&2
    else
        log_error "❌ N8N database backup thất bại" >&2
        return 1
    fi

    # 2. Backup N8N data files
    log_info "📁 Backup N8N data files..." >&2
    local n8n_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_n8n_data 2>/dev/null)

    if [[ -n "$n8n_volume" ]]; then
        if [[ -w "$backup_dir" ]]; then
            tar -czf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume" . 2>/dev/null || {
                # Fallback with sudo if permission denied
                sudo tar -czf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume" . 2>/dev/null
            }
        else
            sudo tar -czf "$backup_dir/n8n_data.tar.gz" -C "$n8n_volume" . 2>/dev/null
        fi
        log_success "✅ N8N data files backup thành công" >&2
    else
        log_error "❌ Không tìm thấy N8N data volume" >&2
        return 1
    fi

    # 3. Backup NocoDB (nếu có cài đặt)
    local nocodb_installed=false
    if docker ps --format '{{.Names}}' | grep -q "^n8n-nocodb$" || [[ -f "/opt/n8n/.nocodb-admin-password" ]]; then
        nocodb_installed=true
        log_info "🗄️  Backup NocoDB..." >&2
        
        # 3a. Backup NocoDB database (nếu separate mode)
        local nocodb_db_mode=$(grep "NOCODB_DATABASE_MODE=" "/opt/n8n/.env" 2>/dev/null | cut -d'=' -f2 || echo "shared")
        if [[ "$nocodb_db_mode" == "separate" ]]; then
            log_info "📦 Backup NocoDB database riêng..." >&2
            if docker exec n8n-postgres pg_dump -U nocodb nocodb >"$backup_dir/nocodb_database.sql" 2>/dev/null; then
                log_success "✅ NocoDB database backup thành công" >&2
            else
                log_warning "⚠️  NocoDB database backup thất bại (có thể chưa tạo)" >&2
            fi
        else
            log_info "📝 NocoDB dùng chung database N8N (đã backup)" >&2
        fi
        
        # 3b. Backup NocoDB data volume
        log_info "📁 Backup NocoDB data volume..." >&2
        local nocodb_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_nocodb_data 2>/dev/null)
        if [[ -n "$nocodb_volume" ]]; then
            if [[ -w "$backup_dir" ]]; then
                tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null || {
                    sudo tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null
                }
            else
                sudo tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null
            fi
            log_success "✅ NocoDB data volume backup thành công" >&2
        else
            log_warning "⚠️  Không tìm thấy NocoDB data volume" >&2
        fi
        
        # 3c. Backup NocoDB admin password
        if [[ -f "/opt/n8n/.nocodb-admin-password" ]]; then
            cp "/opt/n8n/.nocodb-admin-password" "$backup_dir/" 2>/dev/null || \
            sudo cp "/opt/n8n/.nocodb-admin-password" "$backup_dir/" 2>/dev/null || true
            log_success "✅ NocoDB admin password backup thành công" >&2
        fi
        
        # 3d. Backup NocoDB config directory
        if [[ -d "/opt/n8n/nocodb-config" ]]; then
            if [[ -w "$backup_dir" ]]; then
                tar -czf "$backup_dir/nocodb_config.tar.gz" -C "/opt/n8n" nocodb-config 2>/dev/null || {
                    sudo tar -czf "$backup_dir/nocodb_config.tar.gz" -C "/opt/n8n" nocodb-config 2>/dev/null
                }
            else
                sudo tar -czf "$backup_dir/nocodb_config.tar.gz" -C "/opt/n8n" nocodb-config 2>/dev/null
            fi
            log_success "✅ NocoDB config directory backup thành công" >&2
        fi
        
        # 3e. Backup Nginx SSL config cho NocoDB subdomain (nếu có)
        local nocodb_domain=$(grep "nocodb.domain" "$HOME/.config/dataonline-n8n/settings.conf" 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
        if [[ -n "$nocodb_domain" ]] && [[ -f "/etc/nginx/sites-available/${nocodb_domain}.conf" ]]; then
            mkdir -p "$backup_dir/nginx-configs"
            sudo cp "/etc/nginx/sites-available/${nocodb_domain}.conf" "$backup_dir/nginx-configs/" 2>/dev/null || true
            log_success "✅ NocoDB Nginx SSL config backup thành công" >&2
        fi
    else
        log_info "ℹ️  NocoDB chưa được cài đặt, bỏ qua backup NocoDB" >&2
    fi

    # 4. Backup docker-compose và config chung
    log_info "⚙️ Backup cấu hình chung..." >&2
    if [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        cp /opt/n8n/docker-compose.yml "$backup_dir/" 2>/dev/null || \
        sudo cp /opt/n8n/docker-compose.yml "$backup_dir/"
        log_success "✅ docker-compose.yml backup thành công" >&2
    fi
    
    if [[ -f "/opt/n8n/.env" ]]; then
        cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || \
        sudo cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || true
        log_success "✅ .env file backup thành công" >&2
    fi
    
    # Backup manager config
    if [[ -f "$HOME/.config/dataonline-n8n/settings.conf" ]]; then
        mkdir -p "$backup_dir/manager-config"
        cp "$HOME/.config/dataonline-n8n/settings.conf" "$backup_dir/manager-config/" 2>/dev/null || true
        log_success "✅ Manager config backup thành công" >&2
    fi

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
            "database_mode": "$(echo $nocodb_db_mode)",
            "database": "$([ "$nocodb_db_mode" == "separate" ] && echo "included" || echo "shared_with_n8n")",
            "data_volume": "$([ "$nocodb_installed" == "true" ] && echo "included" || echo "not_applicable")",
            "admin_password": "$([ -f "/opt/n8n/.nocodb-admin-password" ] && echo "included" || echo "not_found")",
            "ssl_config": "$([ -n "$nocodb_domain" ] && echo "included" || echo "not_configured")"
        }
    },
    "manager_config": "included",
    "docker_compose": "included",
    "environment": "included",
    "backup_size": "$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "calculating...")"
}
EOF

    # 6. Nén toàn bộ backup
    log_info "🗜️ Đang nén comprehensive backup..." >&2
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
    log_success "✅ Comprehensive backup hoàn tất: ${backup_name}.tar.gz ($final_size)" >&2
    
    if [[ "$nocodb_installed" == "true" ]]; then
        log_info "📋 Backup bao gồm: N8N + NocoDB + SSL configs + Manager settings" >&2
    else
        log_info "📋 Backup bao gồm: N8N + Manager settings" >&2
    fi

    # Chỉ echo đường dẫn file, không có log messages
    echo "$BACKUP_BASE_DIR/${backup_name}.tar.gz"
}

# Cleanup backup cũ 
cleanup_old_backups() {
    local retention_days=$(config_get "backup.retention_days" "30")

    log_info "🧹 Dọn dẹp backup cũ hơn $retention_days ngày..."

    # Local cleanup
    find "$BACKUP_BASE_DIR" -name "n8n_backup_*.tar.gz" -mtime +$retention_days -delete 2>/dev/null || true

    # Google Drive cleanup (if configured)
    if [[ -f "$RCLONE_CONFIG" ]]; then
        local remote_name
        if remote_name=$(get_gdrive_remote_name); then
            rclone delete "${remote_name}:n8n-backups" --min-age "${retention_days}d" --include "n8n_backup_*.tar.gz" 2>/dev/null || true
            log_info "🧹 Đã dọn dẹp Google Drive (remote: $remote_name)"
        fi
    fi
}

# ===== RESTORE FUNCTIONS =====

restore_backup() {
    local backup_file="$1"

    log_info "🔄 Bắt đầu restore từ backup..."

    # Kiểm tra file backup
    if [[ ! -f "$backup_file" ]]; then
        log_error "❌ File backup không tồn tại: $backup_file"
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
        log_error "❌ Không tìm thấy backup directory trong archive"
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
        log_error "❌ Không tìm thấy database backup file"
        log_info "📋 Files có sẵn trong backup:"
        ls -la "$backup_dir"
        rm -rf "$temp_dir"
        return 1
    fi

    # Stop n8n
    log_info "⏹️ Dừng n8n services..."
    cd /opt/n8n
    docker compose down 2>/dev/null || sudo docker compose down

    # Restore database
    log_info "🗄️ Restore database..."
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
        log_success "✅ Database restore thành công"
    else
        log_error "❌ Database restore thất bại"
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
            log_success "✅ Data files restore thành công"
        else
            log_warning "⚠️ Không tìm thấy N8N data volume"
        fi
    fi

    # Restore NocoDB nếu có
    if [[ -f "$backup_dir/nocodb_data.tar.gz" ]]; then
        log_info "🗄️ Restore NocoDB data..."
        local nocodb_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_nocodb_data 2>/dev/null)
        
        if [[ -n "$nocodb_volume" ]]; then
            if [[ -w "$nocodb_volume" ]]; then
                rm -rf "$nocodb_volume"/*
                tar -xzf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume"
            else
                sudo rm -rf "$nocodb_volume"/*
                sudo tar -xzf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume"
            fi
            log_success "✅ NocoDB data restore thành công"
        fi
    fi

    # Restore configuration files
    if [[ -f "$backup_dir/docker-compose.yml" ]]; then
        log_info "⚙️ Restore configuration..."
        cp "$backup_dir/docker-compose.yml" /opt/n8n/ 2>/dev/null || \
        sudo cp "$backup_dir/docker-compose.yml" /opt/n8n/
        
        if [[ -f "$backup_dir/.env" ]]; then
            cp "$backup_dir/.env" /opt/n8n/ 2>/dev/null || \
            sudo cp "$backup_dir/.env" /opt/n8n/
        fi
        
        log_success "✅ Configuration restore thành công"
    fi

    # Start n8n
    log_info "▶️ Khởi động lại n8n..."
    docker compose up -d 2>/dev/null || sudo docker compose up -d

    # Wait for N8N to be ready
    log_info "⏳ Chờ N8N khởi động..."
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
        log_success "✅ Restore hoàn tất thành công!"
        
        # Show restored info
        local metadata_file="$backup_dir/metadata.json"
        if [[ -f "$metadata_file" ]] && command_exists jq; then
            local backup_timestamp=$(jq -r '.timestamp' "$metadata_file" 2>/dev/null || echo "unknown")
            local n8n_version=$(jq -r '.components.n8n.version' "$metadata_file" 2>/dev/null || echo "unknown")
            
            log_info "📋 Restored from backup: $backup_timestamp"
            log_info "📋 N8N version: $n8n_version"
        fi
        
        return 0
    else
        log_error "❌ N8N không khởi động sau restore"
        return 1
    fi
}

# ===== MENU FUNCTIONS =====

# Menu chính backup
backup_menu_main() {
    while true; do
        echo ""
        log_info "💾 QUẢN LÝ BACKUP N8N"
        echo ""
        
        # Show current Google Drive status
        local remote_name=$(get_saved_gdrive_remote_name)
        if [[ -n "$remote_name" ]] && [[ -f "$RCLONE_CONFIG" ]]; then
            echo "☁️  Google Drive: Đã cấu hình (remote: $remote_name)"
        else
            echo "☁️  Google Drive: Chưa cấu hình"
        fi
        echo ""
        
        echo "1) 🔄 Tạo backup ngay"
        echo "2) 📥 Restore từ backup"
        echo "3) ⏰ Cấu hình backup tự động"
        echo "4) ☁️  Cấu hình Google Drive"
        echo "5) 📋 Xem danh sách backup"
        echo "6) 🧹 Dọn dẹp backup cũ"
        echo "0) ⬅️  Quay lại"
        echo ""

        read -p "Chọn [0-6]: " choice

        case "$choice" in
        1) backup_create_now ;;
        2) backup_restore_menu ;;
        3) backup_schedule_menu ;;
        4) setup_google_drive ;;
        5) backup_list ;;
        6) backup_cleanup_menu ;;
        0) return ;;
        *) log_error "Lựa chọn không hợp lệ" ;;
        esac
    done
}

# Cải thiện function backup_create_now
backup_create_now() {
    log_info "🔄 TẠO BACKUP NGAY"

    # Capture chỉ đường dẫn file, logs đã được redirect sang stderr
    local backup_file
    backup_file=$(create_backup)

    if [[ -n "$backup_file" && -f "$backup_file" ]]; then
        log_success "Backup file: $(basename "$backup_file")"

        # Hỏi upload Google Drive
        if [[ -f "$RCLONE_CONFIG" ]]; then
            local remote_name=$(get_gdrive_remote_name || echo "")
            if [[ -n "$remote_name" ]]; then
                read -p "Upload lên Google Drive (remote: $remote_name)? [Y/n]: " upload
                if [[ ! "$upload" =~ ^[Nn]$ ]]; then
                    upload_to_gdrive "$backup_file"
                fi
            else
                log_warn "Google Drive chưa được cấu hình đúng"
            fi
        fi
    else
        log_error "❌ Backup thất bại hoặc file không tồn tại"
    fi
}

# Menu restore
backup_restore_menu() {
    log_info "📥 RESTORE TỪ BACKUP"
    echo ""

    # Liệt kê backup local
    echo "Backup local:"
    local backups=($(ls -t "$BACKUP_BASE_DIR"/n8n_backup_*.tar.gz 2>/dev/null))

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_warn "Không có backup local"
    else
        for i in "${!backups[@]}"; do
            local backup="${backups[$i]}"
            local size=$(du -h "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" | cut -d' ' -f1)
            echo "$((i + 1))) $(basename "$backup") - $size - $date"
        done
    fi

    echo ""
    read -p "Chọn backup để restore [1-${#backups[@]}]: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((choice - 1))]}"

        log_warn "⚠️  CẢNH BÁO: Restore sẽ ghi đè toàn bộ data hiện tại!"
        read -p "Bạn chắc chắn muốn restore? [y/N]: " confirm

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            restore_backup "$selected_backup"
        fi
    else
        log_error "Lựa chọn không hợp lệ"
    fi
}

# Menu lịch backup
backup_schedule_menu() {
    log_info "⏰ CẤU HÌNH BACKUP TỰ ĐỘNG"
    echo ""

    echo "Tần suất backup:"
    echo "1) Hàng ngày"
    echo "2) Hàng tuần"
    echo "3) Hàng tháng (mặc định)"
    echo ""

    read -p "Chọn tần suất [1-3]: " freq_choice

    local frequency="monthly"
    case "$freq_choice" in
    1) frequency="daily" ;;
    2) frequency="weekly" ;;
    3) frequency="monthly" ;;
    esac

    read -p "Giờ backup (0-23, mặc định 2): " hour
    hour=${hour:-2}

    if [[ ! "$hour" =~ ^[0-9]+$ ]] || [[ "$hour" -lt 0 ]] || [[ "$hour" -gt 23 ]]; then
        log_error "Giờ không hợp lệ"
        return
    fi

    if setup_cron_job "$frequency" "$hour"; then
        # Lưu config
        config_set "backup.schedule" "$frequency"
        config_set "backup.hour" "$hour"
        
        log_success "✅ Backup tự động đã được cấu hình: $frequency lúc $hour:00"
        echo ""
        read -p "Nhấn Enter để quay lại menu..."
    else
        log_error "❌ Cấu hình backup tự động thất bại"
        echo ""
        read -p "Nhấn Enter để quay lại menu..."
    fi
}

# Liệt kê backup
backup_list() {
    log_info "📋 DANH SÁCH BACKUP"
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
    log_info "🧹 DỌN DẸP BACKUP CŨ"
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
    log_info "🔧 Khởi tạo backup tự động..."

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

    log_success "✅ Đã cài đặt backup tự động hàng tháng"
}

# Export functions
export -f backup_menu_main
export -f init_backup_on_install
export -f create_backup
export -f cleanup_old_backups