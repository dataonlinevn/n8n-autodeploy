#!/bin/bash

# DataOnline N8N Manager - SSL Domain Module
# Phiên bản: 1.0.0

set -euo pipefail

validate_domain_dns() {
    local domain="$1"
    local server_ip=$(get_public_ip)

    ui_start_spinner "Đang kiểm tra kết nối tên miền..."

    local resolved_ip=$(dig +short A "$domain" @1.1.1.1 | tail -n1)

    ui_stop_spinner

    if [[ -z "$resolved_ip" ]]; then
        ui_error "Tên miền $domain chưa được trỏ DNS"
        if ui_confirm "Bạn có muốn tiếp tục cài đặt dù tên miền chưa trỏ đúng không?"; then
            return 0
        else
            return 1
        fi
    fi

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        ui_success "Tên miền đã kết nối thành công: $domain"
        return 0
    else
        ui_warning "Tên miền chưa trỏ về máy chủ hiện tại ($server_ip)"
        ui_info "Địa chỉ hiện tại: $resolved_ip"
        if ui_confirm "Vẫn tiếp tục cài đặt?"; then
            return 0
        else
            return 1
        fi
    fi
}

export -f validate_domain_dns
