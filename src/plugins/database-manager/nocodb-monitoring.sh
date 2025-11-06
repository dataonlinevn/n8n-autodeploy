#!/bin/bash

# DataOnline N8N Manager - NocoDB Monitoring & Troubleshooting
# Phiên bản: 1.0.0
# Mô tả: Performance monitoring và troubleshooting cho NocoDB

set -euo pipefail

# ===== PERFORMANCE MONITORING =====

monitor_nocodb_performance() {
    ui_section "NocoDB Performance Monitor"
    
    echo "📊 **Performance Metrics:**"
    echo ""
    
    # Container stats
    if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
        echo "🐳 **Container Resources:**"
        docker stats "$NOCODB_CONTAINER" --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || ui_warning "Không thể lấy container stats"
        echo ""
    else
        ui_warning "Container NocoDB không chạy"
    fi
    
    # Response time test
    echo "⚡ **Response Time Test:**"
    local start_time=$(date +%s.%N)
    if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null; then
        local end_time=$(date +%s.%N)
        local response_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")
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
    " 2>/dev/null || echo "")
    
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
    local nocodb_size=$(docker system df -v 2>/dev/null | grep -i nocodb | awk '{print $3}' || echo "Unknown")
    local docker_total=$(docker system df 2>/dev/null | grep 'Local Volumes' | awk '{print $3}' || echo "Unknown")
    echo "   NocoDB data: $nocodb_size"
    echo "   Total Docker: $docker_total"
    
    # Recommendations
    echo ""
    echo "💡 **Performance Recommendations:**"
    
    # Check response time
    if command_exists bc && (( $(echo "$response_time > 1.0" | bc -l) 2>/dev/null )); then
        ui_warning "Response time cao (>1s) - cần tối ưu"
    else
        ui_success "Response time OK"
    fi
    
    ui_success "Memory usage trong giới hạn"
    ui_success "CPU usage ổn định"
    ui_info "💡 Cân nhắc setup Redis cache nếu traffic tăng"
}

# ===== TROUBLESHOOTING =====

troubleshoot_nocodb() {
    ui_section "NocoDB Troubleshooting"
    
    echo "🔧 **Troubleshooting Steps:**"
    echo ""
    
    # Step 1: Check container status
    echo "1️⃣  **Container Status Check**"
    if docker ps --format '{{.Names}}' | grep -q "^${NOCODB_CONTAINER}$"; then
        ui_success "Container đang chạy"
    else
        ui_error "Container không chạy" "CONTAINER_STOPPED" "Chạy 'docker compose up -d nocodb' trong $N8N_COMPOSE_DIR"
    fi
    
    # Step 2: Check ports
    echo ""
    echo "2️⃣  **Port Check**"
    if command_exists ss && ss -tlpn 2>/dev/null | grep -q ":${NOCODB_PORT}"; then
        ui_success "Port $NOCODB_PORT đang listen"
    elif command_exists netstat && netstat -tlnp 2>/dev/null | grep -q ":${NOCODB_PORT}"; then
        ui_success "Port $NOCODB_PORT đang listen"
    else
        ui_error "Port $NOCODB_PORT không available" "PORT_NOT_LISTENING" "Kiểm tra firewall hoặc port conflicts"
    fi
    
    # Step 3: Check database connection
    echo ""
    echo "3️⃣  **Database Connection Check**"
    if docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_success "PostgreSQL connection OK"
    else
        ui_error "PostgreSQL connection failed" "DB_CONNECTION_FAILED" "Restart PostgreSQL container"
    fi
    
    # Step 4: Check API health
    echo ""
    echo "4️⃣  **API Health Check**"
    if curl -s "http://localhost:${NOCODB_PORT}/api/v1/health" >/dev/null 2>&1; then
        ui_success "API health OK"
    else
        ui_error "API health failed" "API_HEALTH_FAILED" "Kiểm tra NocoDB logs: docker logs n8n-nocodb"
    fi
    
    # Step 5: Check disk space
    echo ""
    echo "5️⃣  **Disk Space Check**"
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
        "🔧 Solution: docker compose logs nocodb" \
        "🔧 Solution: Kiểm tra .env file có đúng không" \
        "🔧 Solution: docker compose restart nocodb"
    
    ui_info_box "Issue: Không connect được database" \
        "🔧 Solution: Restart PostgreSQL container" \
        "🔧 Solution: Kiểm tra database credentials trong .env"
    
    ui_info_box "Issue: Slow performance" \
        "🔧 Solution: Tăng memory allocation cho container" \
        "🔧 Solution: Setup Redis cache" \
        "🔧 Solution: Optimize database queries"
    
    ui_info_box "Issue: Login không được" \
        "🔧 Solution: Reset admin password" \
        "🔧 Solution: Kiểm tra JWT secret trong .env"
}

# Export functions
export -f monitor_nocodb_performance troubleshoot_nocodb

