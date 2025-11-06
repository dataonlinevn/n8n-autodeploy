#!/bin/bash

# DataOnline N8N Manager - Install Configuration Module
# Phiên bản: 1.0.0

set -euo pipefail

collect_installation_configuration() {
    ui_header "Cấu hình N8N"

    # N8N Port
    while true; do
        echo -n -e "${UI_WHITE}Port cho N8N (mặc định $N8N_DEFAULT_PORT): ${UI_NC}"
        read -r N8N_PORT
        N8N_PORT=${N8N_PORT:-$N8N_DEFAULT_PORT}

        if ui_validate_port "$N8N_PORT"; then
            if is_port_available "$N8N_PORT"; then
                ui_success "Port N8N: $N8N_PORT"
                break
            else
                ui_error "Port $N8N_PORT đã được sử dụng" "PORT_IN_USE"
            fi
        else
            ui_error "Port không hợp lệ: $N8N_PORT" "INVALID_PORT"
        fi
    done

    # PostgreSQL Port
    while true; do
        echo -n -e "${UI_WHITE}Port cho PostgreSQL (mặc định $POSTGRES_DEFAULT_PORT): ${UI_NC}"
        read -r POSTGRES_PORT
        POSTGRES_PORT=${POSTGRES_PORT:-$POSTGRES_DEFAULT_PORT}

        if ui_validate_port "$POSTGRES_PORT"; then
            if is_port_available "$POSTGRES_PORT"; then
                ui_success "Port PostgreSQL: $POSTGRES_PORT"
                break
            else
                ui_error "Port $POSTGRES_PORT đã được sử dụng" "PORT_IN_USE"
            fi
        else
            ui_error "Port không hợp lệ: $POSTGRES_PORT" "INVALID_PORT"
        fi
    done

    # Domain & Webhook URL
    echo -n -e "${UI_WHITE}Domain cho N8N (bỏ trống nếu chưa dùng domain): ${UI_NC}"
    read -r N8N_DOMAIN

    if [[ -n "$N8N_DOMAIN" ]]; then
        if ui_validate_domain "$N8N_DOMAIN"; then
            ui_success "Domain: $N8N_DOMAIN"
            N8N_WEBHOOK_URL="http://$N8N_DOMAIN"
        else
            ui_warning "Domain không hợp lệ, bỏ qua domain"
            N8N_DOMAIN=""
            N8N_WEBHOOK_URL="http://localhost:$N8N_PORT"
        fi
    else
        N8N_WEBHOOK_URL="http://localhost:$N8N_PORT"
    fi

    # Summary
    ui_info_box "Tóm tắt cấu hình" \
        "N8N Port: $N8N_PORT" \
        "PostgreSQL Port: $POSTGRES_PORT" \
        "Domain: ${N8N_DOMAIN:-'Chưa cấu hình'}" \
        "Webhook URL: $N8N_WEBHOOK_URL"

    return 0
}

export -f collect_installation_configuration
