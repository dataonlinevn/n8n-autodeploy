#!/bin/bash

# DataOnline N8N Manager - Install Verification Module
# Phiên bản: 1.0.0

set -euo pipefail

verify_installation() {
    ui_header "Xác minh hệ thống"
    
    local errors=0
    
    # 1. Kiểm tra ứng dụng chính
    ui_start_spinner "Đang kiểm tra ứng dụng n8n..."
    if sudo docker inspect -f '{{.State.Running}}' "n8n" 2>/dev/null | grep -q "true"; then
        ui_stop_spinner
        ui_success "Ứng dụng n8n đang hoạt động"
    else
        ui_stop_spinner
        ui_error "Ứng dụng n8n gặp lỗi khởi động"
        ((errors++))
    fi
    
    # 2. Kiểm tra cơ sở dữ liệu
    ui_start_spinner "Đang kiểm tra cơ sở dữ liệu..."
    if sudo docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_stop_spinner
        ui_success "Cơ sở dữ liệu PostgreSQL đã sẵn sàng"
    else
        ui_stop_spinner
        ui_error "Không thể kết nối với cơ sở dữ liệu"
        ((errors++))
    fi

    # 3. Kiểm tra bộ nhớ đệm (Redis)
    ui_start_spinner "Đang kiểm tra bộ nhớ đệm..."
    if sudo docker inspect -f '{{.State.Running}}' "n8n-redis" 2>/dev/null | grep -q "true"; then
        ui_stop_spinner
        ui_success "Dịch vụ Redis hoạt động ổn định"
    else
        ui_stop_spinner
        ui_error "Dịch vụ Redis đang dừng"
        ((errors++))
    fi

    # 4. Kiểm tra khả năng truy cập
    ui_start_spinner "Đang kiểm tra cổng kết nối..."
    if curl -s "http://localhost:$N8N_PORT/healthz" >/dev/null 2>&1; then
        ui_stop_spinner
        ui_success "Cổng kết nối n8n phản hồi tốt"
    else
        ui_stop_spinner
        ui_error "Không thể truy cập ứng dụng qua mạng local"
        ((errors++))
    fi

    echo ""
    if [[ $errors -eq 0 ]]; then
        ui_success "XÁC MINH HOÀN TẤT: Hệ thống của bạn đã sẵn sàng sử dụng!"
        return 0
    else
        ui_error "PHÁT HIỆN VẤN ĐỀ: Có $errors thành phần hoạt động chưa đúng."
        return 1
    fi
}

export -f verify_installation
