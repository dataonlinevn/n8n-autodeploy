#!/bin/bash

# DataOnline N8N Manager - Nginx Service Management
# Phiên bản: 1.0.0
# Quản lý dịch vụ Nginx

set -euo pipefail

get_nginx_status() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "${UI_GREEN}[OK] Đang chạy${UI_NC}"
    else
        echo -e "${UI_RED}[STOP] Đã dừng${UI_NC}"
    fi
}

show_nginx_detailed_status() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl status nginx --no-pager -l
    else
        echo "Nginx không chạy"
    fi
}

start_nginx_service() {
    ui_run_command "Khởi động Nginx" "systemctl start nginx"
    ui_success "Cổng Nginx đã được kích hoạt"
}

stop_nginx_service() {
    ui_run_command "Dừng Nginx" "systemctl stop nginx"
    ui_status "success" "Nginx đã dừng"
}

restart_nginx_service() {
    ui_run_command "Restart Nginx" "systemctl restart nginx"
    ui_status "success" "Nginx restart thành công"
}

reload_nginx_config() {
    ui_run_command "Reload Nginx config" "systemctl reload nginx"
    ui_status "success" "Nginx config đã reload"
}

test_nginx_config() {
    ui_info "Đang kiểm tra tệp cấu hình Nginx..."
    if nginx -t 2>/dev/null; then
        ui_success "Cấu hình hợp lệ"
    else
        ui_error "Cấu hình có lỗi, vui lòng kiểm tra lại"
        nginx -t
    fi
}

is_nginx_autostart_enabled() {
    systemctl is-enabled --quiet nginx 2>/dev/null
}

toggle_nginx_autostart() {
    if is_nginx_autostart_enabled; then
        ui_run_command "Disable Nginx auto-start" "systemctl disable nginx"
        ui_status "success" "Nginx auto-start đã tắt"
    else
        ui_run_command "Enable Nginx auto-start" "systemctl enable nginx"
        ui_status "success" "Nginx auto-start đã bật"
    fi
}

show_nginx_logs() {
    echo "📝 Nginx Error Log (20 dòng cuối):"
    tail -n 20 /var/log/nginx/error.log 2>/dev/null || echo "Không có error log"
    echo ""
    echo "📝 Nginx Access Log (10 dòng cuối):"
    tail -n 10 /var/log/nginx/access.log 2>/dev/null || echo "Không có access log"
}

export -f get_nginx_status show_nginx_detailed_status start_nginx_service stop_nginx_service restart_nginx_service reload_nginx_config test_nginx_config is_nginx_autostart_enabled toggle_nginx_autostart show_nginx_logs
