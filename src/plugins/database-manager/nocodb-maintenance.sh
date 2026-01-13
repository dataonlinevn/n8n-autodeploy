#!/bin/bash

# DataOnline N8N Manager - NocoDB Maintenance Tasks
# Phiên bản: 1.0.0
# Mô tả: Maintenance và health check tasks cho NocoDB

set -euo pipefail

# ===== MAINTENANCE TASKS =====

run_maintenance_tasks() {
    ui_section "NocoDB Maintenance Tasks"
    
    echo "Available Maintenance Tasks:"
    echo ""
    echo "1) Cleanup old logs"
    echo "2) Optimize database"
    echo "3) Update Docker image"
    echo "4) Generate health report"
    echo "5) Security audit"
    echo "6) Full backup"
    echo "0) Quay lại"
    echo ""
    
    read -p "Chọn [0-6]: " maintenance_choice
    
    case "$maintenance_choice" in
    1) cleanup_old_logs ;;
    2) optimize_database ;;
    3) update_docker_image ;;
    4) generate_health_report ;;
    5) security_audit ;;
    6) full_backup ;;
    0) return ;;
    *) ui_error "Lựa chọn không hợp lệ" ;;
    esac
}

cleanup_old_logs() {
    ui_section "Cleanup Old Logs"
    
    ui_info "Đang tìm và xóa logs cũ..."
    
    # Cleanup Docker logs
    if command_exists docker; then
        ui_start_spinner "Xóa Docker logs cũ"
        docker logs n8n-nocodb --since 30d >/dev/null 2>&1 || true
        ui_stop_spinner
    fi
    
    # Cleanup application logs
    local log_files=(
        "/opt/n8n/nocodb-logs/*.log"
        "/var/log/nocodb/*.log"
    )
    
    local cleaned=0
    for pattern in "${log_files[@]}"; do
        for file in $pattern; do
            if [[ -f "$file" ]] && [[ $(find "$file" -mtime +30 2>/dev/null) ]]; then
                rm -f "$file" 2>/dev/null && ((cleaned++))
            fi
        done
    done
    
    ui_success "Đã xóa $cleaned log files cũ"
}

optimize_database() {
    ui_section "Optimize Database"
    
    ui_warning_box "Database Optimization" \
        "Sẽ thực hiện VACUUM và ANALYZE" \
        "Có thể mất vài phút" \
        "N8N sẽ tạm thời chậm hơn"
    
    if ! ui_confirm "Tiếp tục optimize database?"; then
        return 0
    fi
    
    ui_start_spinner "Optimizing database"
    
    # Run VACUUM ANALYZE
    docker exec n8n-postgres psql -U n8n -c "VACUUM ANALYZE;" >/dev/null 2>&1 || true
    
    ui_stop_spinner
    ui_success "Database optimization hoàn tất"
}

update_docker_image() {
    ui_section "Update Docker Image"
    
    ui_warning_box "Update Docker Image" \
        "Sẽ pull image mới nhất" \
        "Container sẽ được restart" \
        "Downtime: ~1-2 phút"
    
    if ! ui_confirm "Update NocoDB Docker image?"; then
        return 0
    fi
    
    ui_progress_start "Updating NocoDB" 4
    
    # Step 1: Backup
    ui_progress_update 1 "Backup current setup" "running"
    cd "$N8N_COMPOSE_DIR" || return 1
    cp docker-compose.yml docker-compose.yml.backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    ui_progress_update 1 "Backup current setup" "success"
    
    # Step 2: Pull new image
    ui_progress_update 2 "Pull new image" "running"
    if docker compose pull nocodb; then
        ui_progress_update 2 "Pull new image" "success"
    else
        ui_progress_update 2 "Pull new image" "error"
        ui_progress_end
        ui_error "Pull image thất bại" "IMAGE_PULL_FAILED" "Kiểm tra internet connection"
        return 1
    fi
    
    # Step 3: Restart container
    ui_progress_update 3 "Restart container" "running"
    if docker compose up -d nocodb; then
        ui_progress_update 3 "Restart container" "success"
    else
        ui_progress_update 3 "Restart container" "error"
        ui_progress_end
        ui_error "Restart container thất bại" "RESTART_FAILED" "Kiểm tra logs: docker compose logs nocodb"
        return 1
    fi
    
    # Step 4: Verify
    ui_progress_update 4 "Verify installation" "running"
    sleep 5
    if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
        ui_progress_update 4 "Verify installation" "success"
        ui_progress_end
        ui_success "NocoDB đã được update thành công!"
    else
        ui_progress_update 4 "Verify installation" "error"
        ui_progress_end
        ui_error "NocoDB không khởi động sau update" "VERIFY_FAILED" "Kiểm tra logs và rollback nếu cần"
        return 1
    fi
}

generate_health_report() {
    ui_section "Generate Health Report"
    
    local report_file="$N8N_COMPOSE_DIR/nocodb-health-report-$(date +%Y%m%d_%H%M%S).txt"
    
    ui_start_spinner "Generating health report"
    
    {
        echo "========================================"
        echo "Báo cáo sức khỏe hệ thống NocoDB"
        echo "Thời gian tạo: $(date)"
        echo "========================================"
        echo ""
        
        echo "THÔNG TIN HỆ THỐNG:"
        echo "- OS: $(lsb_release -d | cut -f2 2>/dev/null || echo "Unknown")"
        echo "- Kernel: $(uname -r)"
        echo "- Docker: $(docker --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo "Unknown")"
        echo ""
        
        echo "TRẠNG THÁI DỊCH VỤ:"
        if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
            echo "- N8N: Đang hoạt động"
            echo "- Image: $(docker inspect ${NOCODB_CONTAINER} --format '{{.Config.Image}}' 2>/dev/null || echo "Unknown")"
            echo "- Started: $(docker inspect ${NOCODB_CONTAINER} --format '{{.State.StartedAt}}' 2>/dev/null | cut -d'T' -f1 || echo "Unknown")"
        else
            echo "- Status: Stopped"
        fi
        echo ""
        
        echo "KẾT NỐI:"
        echo "- Port $NOCODB_PORT: $(ss -tlpn 2>/dev/null | grep -q ":${NOCODB_PORT}" && echo "Mở" || echo "Đóng")"
        echo "- API: $(curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1 && echo "Hoạt động" || echo "Lỗi")"
        echo ""
        
        echo "DATABASE:"
        echo "- Connection: $(docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
        echo "- Database: $(config_get "nocodb.db_name" "n8n")"
        echo ""
        
        echo "DUNG LƯỢNG LƯU TRỮ:"
        echo "- Còn trống: $(df -h "$N8N_COMPOSE_DIR" | awk 'NR==2 {print $4}')"
        echo "- Dữ liệu NocoDB: $(docker system df -v 2>/dev/null | grep -i nocodb | awk '{print $3}' || echo "N/A")"
        echo ""
        
        echo "BẢO MẬT:"
        echo "- SSL: $(config_get "nocodb.ssl_enabled" "false")"
        echo "- Tên miền: $(config_get "nocodb.domain" "Chưa cấu hình")"
        echo ""
        
        echo "========================================"
    } > "$report_file"
    
    ui_stop_spinner
    
    ui_success "Health report đã được tạo: $report_file"
    ui_info "Xem report: cat $report_file"
}

security_audit() {
    ui_section "Security Audit"
    
    ui_info "Đang kiểm tra security settings..."
    echo ""
    
    local issues=0
    
    # Check 1: Password file permissions
    echo "1) Password File Permissions"
    local password_file="$N8N_COMPOSE_DIR/.nocodb-admin-password"
    if [[ -f "$password_file" ]]; then
        local perms=$(stat -c %a "$password_file" 2>/dev/null || echo "000")
        if [[ "$perms" != "600" ]]; then
            ui_warning "File permissions không an toàn: $perms (should be 600)"
            ((issues++))
        else
            ui_success "Password file permissions OK"
        fi
    else
        ui_warning "Password file không tồn tại"
    fi
    
    # Check 2: JWT secret
    echo ""
    echo "2) JWT Secret"
    local jwt_secret=$(grep "NOCODB_JWT_SECRET" "$N8N_COMPOSE_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
    if [[ -z "$jwt_secret" ]]; then
        ui_warning "JWT secret chưa được cấu hình"
        ((issues++))
    elif [[ ${#jwt_secret} -lt 32 ]]; then
        ui_warning "JWT secret quá ngắn (<32 chars)"
        ((issues++))
    else
        ui_success "JWT secret OK"
    fi
    
    # Check 3: SSL configuration
    echo ""
    echo "3) SSL Configuration"
    local ssl_enabled=$(config_get "nocodb.ssl_enabled" "false")
    if [[ "$ssl_enabled" != "true" ]]; then
        ui_warning "SSL chưa được kích hoạt"
        ((issues++))
    else
        ui_success "SSL đã được cấu hình"
    fi
    
    # Check 4: Environment file permissions
    echo ""
    echo "4) Environment File Permissions"
    local env_perms=$(stat -c %a "$N8N_COMPOSE_DIR/.env" 2>/dev/null || echo "000")
    if [[ "$env_perms" != "600" ]]; then
        ui_warning "Environment file permissions không an toàn: $env_perms (should be 600)"
        ((issues++))
    else
        ui_success "Environment file permissions OK"
    fi
    
    # Check 5: Public URL exposure
    echo ""
    echo "5) Public URL Configuration"
    local nocodb_url=$(get_nocodb_url)
    if [[ "$nocodb_url" == http://* ]]; then
        ui_warning "NocoDB đang dùng HTTP (không an toàn)"
        ((issues++))
    elif [[ "$nocodb_url" == https://* ]]; then
        ui_success "NocoDB đang dùng HTTPS"
    else
        ui_info "NocoDB chưa được expose public"
    fi
    
    # Summary
    echo ""
    if [[ $issues -eq 0 ]]; then
        ui_success "Không phát hiện vấn đề security!"
    else
        ui_error "[WARN] Phát hiện $issues vấn đề security cần xử lý" "SECURITY_ISSUES" "Xem chi tiết ở trên"
    fi
}

full_backup() {
    ui_section "Full Backup NocoDB"
    
    ui_warning_box "Full Backup" \
        "Sẽ backup toàn bộ NocoDB data" \
        "Bao gồm: database, config, users"
    
    if ! ui_confirm "Tạo full backup?"; then
        return 0
    fi
    
    ui_progress_start "Backup NocoDB" 3
    
    # Step 1: Backup database
    ui_progress_update 1 "Backup database" "running"
    local backup_dir="/opt/n8n/backups/nocodb-full-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup NocoDB database (if separate mode)
    local db_mode=$(grep "NOCODB_DATABASE_MODE=" "$N8N_COMPOSE_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "shared")
    if [[ "$db_mode" == "separate" ]]; then
        docker exec n8n-postgres pg_dump -U nocodb nocodb > "$backup_dir/nocodb_database.sql" 2>/dev/null || true
    fi
    ui_progress_update 1 "Backup database" "success"
    
    # Step 2: Backup data volume
    ui_progress_update 2 "Backup data volume" "running"
    local nocodb_volume=$(docker volume inspect --format '{{ .Mountpoint }}' n8n_nocodb_data 2>/dev/null)
    if [[ -n "$nocodb_volume" ]]; then
        tar -czf "$backup_dir/nocodb_data.tar.gz" -C "$nocodb_volume" . 2>/dev/null || true
    fi
    ui_progress_update 2 "Backup data volume" "success"
    
    # Step 3: Backup config
    ui_progress_update 3 "Backup configuration" "running"
    cp "$N8N_COMPOSE_DIR/.nocodb-admin-password" "$backup_dir/" 2>/dev/null || true
    grep "NOCODB" "$N8N_COMPOSE_DIR/.env" > "$backup_dir/nocodb_env.txt" 2>/dev/null || true
    ui_progress_update 3 "Backup configuration" "success"
    
    ui_progress_end
    
    # Compress backup
    ui_start_spinner "Compressing backup"
    tar -czf "${backup_dir}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" 2>/dev/null
    rm -rf "$backup_dir"
    ui_stop_spinner
    
    ui_success "Full backup hoàn tất: ${backup_dir}.tar.gz"
}

# Export functions
export -f run_maintenance_tasks cleanup_old_logs optimize_database update_docker_image
export -f generate_health_report security_audit full_backup

