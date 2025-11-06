#!/bin/bash

# DataOnline N8N Manager - SSL Domain Module
# Phiên bản: 1.0.0

set -euo pipefail

validate_domain_dns() {
    local domain="$1"
    local server_ip=$(get_public_ip)

    ui_start_spinner "Kiểm tra DNS cho $domain"

    local resolved_ip=$(dig +short A "$domain" @1.1.1.1 | tail -n1)

    ui_stop_spinner

    if [[ -z "$resolved_ip" ]]; then
        ui_error "Không thể phân giải DNS cho $domain" "DNS_NOT_RESOLVED" "Kiểm tra bản ghi A"
        echo -n -e "${UI_YELLOW}Bỏ qua kiểm tra DNS? [y/N]: ${UI_NC}"
        read -r skip_dns
        return $([[ "$skip_dns" =~ ^[Yy]$ ]] && echo 0 || echo 1)
    fi

    if [[ "$resolved_ip" == "$server_ip" ]]; then
        ui_success "DNS đã trỏ đúng: $domain → $server_ip"
        return 0
    else
        ui_warning "DNS không trỏ đúng: $domain → $resolved_ip (cần: $server_ip)"
        echo -n -e "${UI_YELLOW}Bỏ qua kiểm tra DNS? [y/N]: ${UI_NC}"
        read -r skip_dns
        return $([[ "$skip_dns" =~ ^[Yy]$ ]] && echo 0 || echo 1)
    fi
}

export -f validate_domain_dns
