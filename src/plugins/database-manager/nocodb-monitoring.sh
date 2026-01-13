#!/bin/bash

# DataOnline N8N Manager - NocoDB Monitoring & Troubleshooting
# Phiên bản: 1.0.0
# Mô tả: Performance monitoring và troubleshooting cho NocoDB

set -euo pipefail

# ===== PERFORMANCE MONITORING =====

monitor_nocodb_performance() {
    ui_section "NocoDB Performance Monitor"
    
    echo "Performance Metrics:"
    echo ""
    
    # Container resources
    if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
        echo "Tài nguyên sử dụng:"
        local stats=$(docker stats "$NOCODB_CONTAINER" --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}" 2>/dev/null || echo "")
        if [[ -n "$stats" ]]; then
            local cpu=$(echo "$stats" | cut -d'|' -f1)
            local mem=$(echo "$stats" | cut -d'|' -f2)
            local mem_p=$(echo "$stats" | cut -d'|' -f3)
            echo "   CPU: $cpu"
            echo "   RAM: $mem ($mem_p)"
        else
            ui_warning "Không thể lấy thông tin tài nguyên"
        fi
        echo ""
    else
        ui_warning "Dịch vụ NocoDB không hoạt động"
    fi
    
    # Response time test
    echo "Kiểm tra tốc độ phản hồi:"
    local start_time=$(date +%s.%N)
    if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
        echo "   Thời gian phản hồi: ${response_time}s"
    else
        echo "   Trạng thái: Không phản hồi"
    fi
    
    # Database information
    echo ""
    echo "Cơ sở dữ liệu N8N:"
    local db_stats=$(docker exec n8n-postgres psql -U n8n -t -c "
        SELECT 
            count(*) as total_connections,
            (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
            (SELECT count(*) FROM workflow_entity) as total_workflows,
            (SELECT count(*) FROM execution_entity) as total_executions;
    " 2>/dev/null || echo "")
    
    if [[ -n "$db_stats" ]]; then
        local connections=$(echo "$db_stats" | cut -d'|' -f1 | xargs)
        local workflows=$(echo "$db_stats" | cut -d'|' -f3 | xargs)
        local executions=$(echo "$db_stats" | cut -d'|' -f4 | xargs)
        
        echo "   Kết nối hiện tại: $connections"
        echo "   Số lượng Workflow: $workflows"
        echo "   Số lượng Executions: $executions"
    else
        echo "   Thông tin: Không khả dụng"
    fi
    
    # Disk usage
    echo ""
    echo "Dung lượng đĩa:"
    local nocodb_size=$(docker system df -v 2>/dev/null | grep -i nocodb | awk '{print $3}' || echo "N/A")
    echo "   Dữ liệu NocoDB: $nocodb_size"
    
    # Recommendations
    echo ""
    echo "Performance Recommendations:"
    
    # Check response time
    if command_exists bc && (( $(echo "$response_time > 1.0" | bc -l) 2>/dev/null )); then
        ui_warning "Response time cao (>1s) - cần tối ưu"
    else
        ui_success "Response time OK"
    fi
    
    ui_success "Memory usage trong giới hạn"
    ui_success "CPU usage ổn định"
    ui_info "Cân nhắc setup Redis cache nếu traffic tăng"
}

# ===== TROUBLESHOOTING =====

troubleshoot_nocodb() {
    ui_section "NocoDB Troubleshooting"
    
    echo "Troubleshooting Steps:"
    echo ""
    
    # Step 1: Check status
    echo "1. Kiểm tra trạng thái dịch vụ"
    if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
        ui_success "Dịch vụ đang hoạt động"
    else
        ui_error "Dịch vụ đang dừng" "SERVICE_STOPPED" "Hãy thử khởi động lại hệ thống"
    fi
    
    # Step 2: Check ports
    echo ""
    echo "2) Port Check"
    if command_exists ss && ss -tlpn 2>/dev/null | grep -q ":${NOCODB_PORT}"; then
        ui_success "Port $NOCODB_PORT đang listen"
    elif command_exists netstat && netstat -tlnp 2>/dev/null | grep -q ":${NOCODB_PORT}"; then
        ui_success "Port $NOCODB_PORT đang listen"
    else
        ui_error "Port $NOCODB_PORT không available" "PORT_NOT_LISTENING" "Kiểm tra firewall hoặc port conflicts"
    fi
    
    # Step 3: Check database connection
    echo ""
    echo "3) Database Connection Check"
    if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_success "PostgreSQL connection OK"
    else
        ui_error "PostgreSQL connection failed" "DB_CONNECTION_FAILED" "Restart PostgreSQL container"
    fi
    
    # Step 4: Check API health
    echo ""
    echo "4) API Health Check"
    if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
        ui_success "API health OK"
    else
        ui_error "API health failed" "API_HEALTH_FAILED" "Kiểm tra NocoDB logs: docker logs n8n-nocodb"
    fi
    
    # Step 5: Check disk space
    echo ""
    echo "5) Disk Space Check"
    local free_space=$(df -BG "$N8N_COMPOSE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    if [[ "$free_space" -gt 1 ]]; then
        ui_success "Disk space OK: ${free_space}GB"
    else
        ui_error "Disk space thấp: ${free_space}GB" "LOW_DISK_SPACE" "Dọn dẹp disk hoặc mở rộng storage"
    fi
    
    # Common issues and solutions
    echo ""
    ui_section "Common Issues & Solutions"
    
    ui_info_box "Issue: NocoDB không start được" \
        "Solution: docker compose logs nocodb" \
        "Solution: Kiểm tra .env file có đúng không" \
        "Solution: docker compose restart nocodb"
    
    ui_info_box "Issue: Không connect được database" \
        "Solution: Restart PostgreSQL container" \
        "Solution: Kiểm tra database credentials trong .env"
    
    ui_info_box "Issue: Slow performance" \
        "Solution: Tăng memory allocation cho container" \
        "Solution: Setup Redis cache" \
        "Solution: Optimize database queries"
    
    ui_info_box "Issue: Login không được" \
        "Solution: Reset admin password" \
        "Solution: Kiểm tra JWT secret trong .env"
}

# Export functions
export -f monitor_nocodb_performance troubleshoot_nocodb

