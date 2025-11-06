#!/bin/bash

# DataOnline N8N Manager - Install Verification Module
# Phiên bản: 1.0.0

set -euo pipefail

verify_installation() {
    ui_section "Kiểm tra cài đặt"

    local errors=0

    # Check containers
    local containers=("n8n" "n8n-postgres")
    for container in "${containers[@]}"; do
        if sudo docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            ui_success "Container $container đang chạy"
        else
            ui_error "Container $container không chạy" "CONTAINER_NOT_RUNNING"
            ((errors++))
        fi
    done

    # Check N8N API
    if curl -s "http://localhost:$N8N_PORT/healthz" >/dev/null 2>&1; then
        ui_success "N8N API hoạt động"
    else
        ui_error "N8N API không phản hồi" "N8N_API_FAILED"
        ((errors++))
    fi

    # Check database
    if sudo docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_success "PostgreSQL sẵn sàng"
    else
        ui_error "PostgreSQL không sẵn sàng" "POSTGRES_NOT_READY"
        ((errors++))
    fi

    if [[ $errors -eq 0 ]]; then
        ui_success "Cài đặt hợp lệ"
        return 0
    else
        ui_error "Có $errors lỗi cài đặt" "VERIFY_FAILED" "Xem chi tiết ở trên"
        return 1
    fi
}

export -f verify_installation
