#!/bin/bash

# DataOnline N8N Manager - Simplified Install Plugin
# Phiên bản: 1.0.0

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_PROJECT_ROOT="$(dirname "$(dirname "$PLUGIN_DIR")")"

if [[ -z "${LOGGER_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/logger.sh"
fi
if [[ -z "${CONFIG_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/config.sh"
fi
if [[ -z "${UTILS_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/utils.sh"
fi
if [[ -z "${UI_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/ui.sh"
fi
if [[ -z "${SPINNER_LOADED:-}" ]]; then
    source "$PLUGIN_PROJECT_ROOT/src/core/spinner.sh"
fi

readonly INSTALL_DOCKER_COMPOSE_VERSION="2.24.5"
readonly REQUIRED_RAM_MB=2048
readonly REQUIRED_DISK_GB=10
readonly N8N_DEFAULT_PORT=5678
readonly POSTGRES_DEFAULT_PORT=5432

# Global variables
N8N_PORT=""
POSTGRES_PORT=""
N8N_DOMAIN=""
N8N_WEBHOOK_URL=""

# ===== MAIN INSTALLATION MENU =====

install_n8n_main() {
    ui_header "Quản lý Cài đặt N8N"

    while true; do
        show_install_menu
        
        echo -n -e "${UI_WHITE}Chọn [0-2]: ${UI_NC}"
        read -r choice

        case "$choice" in
        1) handle_n8n_installation ;;
        2) handle_n8n_uninstall ;;
        0) return 0 ;;
        *) ui_status "error" "Lựa chọn không hợp lệ" ;;
        esac

        echo ""
        read -p "Nhấn Enter để tiếp tục..."
    done
}

show_install_menu() {
    local n8n_status=$(check_n8n_installation_status)
    
    echo ""
    echo "📦 QUẢN LÝ CÀI ĐẶT N8N"
    echo ""
    echo "Trạng thái hiện tại: $n8n_status"
    echo ""
    echo "1) 🚀 Cài đặt N8N với Docker"
    echo "2) 🗑️  Gỡ cài đặt N8N"
    echo "0) ⬅️  Quay lại"
    echo ""
}

check_n8n_installation_status() {
    if [[ -f "/opt/n8n/docker-compose.yml" ]] && docker ps --format '{{.Names}}' | grep -q "n8n"; then
        echo -e "${UI_GREEN}✅ Đã cài đặt và đang chạy${UI_NC}"
    elif [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        echo -e "${UI_YELLOW}⚠️  Đã cài đặt nhưng không chạy${UI_NC}"
    else
        echo -e "${UI_RED}❌ Chưa cài đặt${UI_NC}"
    fi
}

# ===== INSTALLATION HANDLER =====

handle_n8n_installation() {
    ui_header "Cài đặt N8N với Docker"

    # Check for existing installation
    if [[ -d "/opt/n8n" && -f "/opt/n8n/docker-compose.yml" ]]; then
        ui_warning_box "Cảnh báo" \
            "Phát hiện N8N đã được cài đặt" \
            "Tiếp tục sẽ cài đặt lại từ đầu"

        if ! ui_confirm "Tiếp tục cài đặt lại?"; then
            return 0
        fi
        
        # Backup existing installation
        backup_existing_installation
    fi

    # Step 1: System requirements
    ui_status "info" "🔍 Bước 1/5: Kiểm tra yêu cầu hệ thống"
    if ! check_n8n_requirements; then
        ui_status "error" "Hệ thống không đáp ứng yêu cầu"
        return 1
    fi

    if ! ui_confirm "Tiếp tục cài đặt?"; then
        return 0
    fi

    # Step 2: Configuration
    ui_status "info" "⚙️  Bước 2/5: Thu thập cấu hình"
    if ! collect_installation_configuration; then
        return 1
    fi

    # Step 3: Install dependencies
    ui_status "info" "📦 Bước 3/5: Cài đặt dependencies"
    install_dependencies || return 1
    install_docker || return 1

    # Step 4: Docker setup
    ui_status "info" "🐳 Bước 4/5: Cài đặt N8N"
    create_docker_compose || return 1
    start_n8n_docker || return 1
    create_systemd_service || return 1

    # Step 5: Verification
    ui_status "info" "✅ Bước 5/5: Xác minh cài đặt"
    if verify_installation; then
        show_post_install_guide
        config_set "n8n.installed" "true"
        config_set "n8n.installed_date" "$(date -Iseconds)"
        
        # Initialize backup system
        if [[ -f "$PLUGIN_PROJECT_ROOT/src/plugins/backup/main.sh" ]]; then
            source "$PLUGIN_PROJECT_ROOT/src/plugins/backup/main.sh"
            init_backup_on_install
        fi
        
        ui_status "success" "🎉 Cài đặt N8N hoàn tất!"
    else
        ui_status "error" "Cài đặt chưa hoàn toàn thành công"
        return 1
    fi

    return 0
}

# ===== UNINSTALL HANDLER =====

handle_n8n_uninstall() {
    ui_header "Gỡ cài đặt N8N"

    # Check if N8N is installed
    if [[ ! -d "/opt/n8n" ]]; then
        ui_status "warning" "N8N chưa được cài đặt"
        return 0
    fi

    # Show current installation info
    show_current_installation_info

    ui_warning_box "⚠️  CẢNH BÁO GỠ CÀI ĐẶT" \
        "Sẽ xóa hoàn toàn N8N và tất cả dữ liệu" \
        "Bao gồm: workflows, executions, credentials" \
        "Hành động này KHÔNG THỂ HOÀN TÁC!"

    # Double confirmation
    if ! ui_confirm "Bạn CHẮC CHẮN muốn gỡ cài đặt N8N?"; then
        return 0
    fi

    echo -n -e "${UI_RED}Nhập 'XAC NHAN' để tiếp tục: ${UI_NC}"
    read -r confirmation
    if [[ "$confirmation" != "XAC NHAN" ]]; then
        ui_status "info" "Hủy gỡ cài đặt"
        return 0
    fi

    # Offer backup before uninstall
    echo -n -e "${UI_YELLOW}Tạo backup trước khi gỡ cài đặt? [Y/n]: ${UI_NC}"
    read -r create_backup
    if [[ ! "$create_backup" =~ ^[Nn]$ ]]; then
        create_final_backup
    fi

    # Proceed with uninstallation
    uninstall_n8n_completely
}

show_current_installation_info() {
    ui_section "Thông tin cài đặt hiện tại"
    
    local n8n_version="unknown"
    local install_date="unknown"
    
    if docker ps --format '{{.Names}}' | grep -q "n8n"; then
        n8n_version=$(docker exec n8n n8n --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    fi
    
    install_date=$(config_get "n8n.installed_date" "unknown")
    
    local n8n_port=$(config_get "n8n.port" "5678")
    local n8n_domain=$(config_get "n8n.domain" "")
    
    echo "📊 **Thông tin N8N:**"
    echo "   Version: $n8n_version"
    echo "   Port: $n8n_port"
    echo "   Domain: ${n8n_domain:-'Chưa cấu hình'}"
    echo "   Ngày cài đặt: $install_date"
    echo ""
    
    # Check disk usage
    if [[ -d "/opt/n8n" ]]; then
        local disk_usage=$(du -sh /opt/n8n 2>/dev/null | cut -f1)
        echo "💾 **Disk Usage:**"
        echo "   N8N folder: $disk_usage"
        
        # Check volumes
        local volumes=$(docker volume ls --filter name=n8n --format "{{.Name}}" 2>/dev/null)
        if [[ -n "$volumes" ]]; then
            echo "   Docker volumes:"
            for volume in $volumes; do
                local vol_size=$(docker system df -v | grep "$volume" | awk '{print $3}' || echo "unknown")
                echo "     - $volume: $vol_size"
            done
        fi
    fi
    echo ""
}

create_final_backup() {
    ui_start_spinner "Tạo backup cuối cùng"
    
    local backup_dir="/tmp/n8n-final-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup docker-compose and config
    if [[ -d "/opt/n8n" ]]; then
        cp -r /opt/n8n "$backup_dir/"
    fi
    
    # Export database
    if docker ps --format '{{.Names}}' | grep -q "n8n-postgres"; then
        docker exec n8n-postgres pg_dump -U n8n n8n > "$backup_dir/database_final.sql" 2>/dev/null || true
    fi
    
    # Compress backup
    tar -czf "/tmp/n8n-final-backup-$(date +%Y%m%d_%H%M%S).tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    ui_stop_spinner
    ui_status "success" "Backup cuối cùng đã được tạo tại /tmp/"
}

uninstall_n8n_completely() {
    ui_section "Thực hiện gỡ cài đặt"
    
    # Step 1: Stop services
    ui_start_spinner "Dừng N8N services"
    if [[ -f "/opt/n8n/docker-compose.yml" ]]; then
        cd /opt/n8n && docker compose down -v 2>/dev/null || true
    fi
    
    # Stop containers manually if compose fails
    docker stop n8n n8n-postgres n8n-nocodb 2>/dev/null || true
    docker rm n8n n8n-postgres n8n-nocodb 2>/dev/null || true
    ui_stop_spinner
    ui_status "success" "✅ Services đã dừng"
    
    # Step 2: Remove Docker volumes
    ui_start_spinner "Xóa Docker volumes"
    local volumes=(
        "n8n_postgres_data"
        "n8n_n8n_data" 
        "n8n_nocodb_data"
    )
    
    for volume in "${volumes[@]}"; do
        docker volume rm "$volume" 2>/dev/null || true
    done
    ui_stop_spinner
    ui_status "success" "✅ Docker volumes đã xóa"
    
    # Step 3: Remove installation directory
    ui_run_command "Xóa thư mục cài đặt" "rm -rf /opt/n8n"
    
    # Step 4: Remove systemd service
    ui_start_spinner "Xóa systemd service"
    systemctl stop n8n 2>/dev/null || true
    systemctl disable n8n 2>/dev/null || true
    rm -f /etc/systemd/system/n8n.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    ui_stop_spinner
    ui_status "success" "✅ Systemd service đã xóa"
    
    # Step 5: Remove Nginx configs (if any)
    ui_start_spinner "Xóa cấu hình Nginx"
    local n8n_domain=$(config_get "n8n.domain" "")
    if [[ -n "$n8n_domain" ]]; then
        rm -f "/etc/nginx/sites-available/${n8n_domain}.conf" 2>/dev/null || true
        rm -f "/etc/nginx/sites-enabled/${n8n_domain}.conf" 2>/dev/null || true
        
        # Also remove NocoDB domain if exists
        rm -f "/etc/nginx/sites-available/db.${n8n_domain}.conf" 2>/dev/null || true
        rm -f "/etc/nginx/sites-enabled/db.${n8n_domain}.conf" 2>/dev/null || true
        
        # Reload nginx if running
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx 2>/dev/null || true
        fi
    fi
    ui_stop_spinner
    ui_status "success" "✅ Nginx configs đã xóa"
    
    # Step 6: Clean up manager config
    ui_start_spinner "Dọn dẹp cấu hình manager"
    config_set "n8n.installed" "false"
    config_set "n8n.domain" ""
    config_set "n8n.port" ""
    config_set "n8n.webhook_url" ""
    config_set "n8n.ssl_enabled" "false"
    config_set "nocodb.installed" "false"
    config_set "nocodb.domain" ""
    ui_stop_spinner
    ui_status "success" "✅ Cấu hình manager đã dọn dẹp"
    
    # Step 7: Remove cron jobs (if any)
    ui_start_spinner "Xóa cron jobs"
    crontab -l 2>/dev/null | grep -v "n8n-backup" | crontab - 2>/dev/null || true
    ui_stop_spinner
    ui_status "success" "✅ Cron jobs đã xóa"
    
    ui_status "success" "🎉 N8N đã được gỡ cài đặt hoàn toàn!"
    
    ui_info_box "Gỡ cài đặt hoàn tất" \
        "✅ Tất cả services đã dừng" \
        "✅ Docker containers và volumes đã xóa" \
        "✅ Files cấu hình đã xóa" \
        "✅ Nginx configs đã xóa" \
        "✅ Systemd service đã xóa" \
        "" \
        "💡 Hệ thống đã sạch và sẵn sàng cài đặt lại"
}

backup_existing_installation() {
    ui_start_spinner "Backup cài đặt hiện tại"
    
    local backup_dir="/opt/n8n/backups/installation_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup current docker-compose and env
    cp /opt/n8n/docker-compose.yml "$backup_dir/" 2>/dev/null || true
    cp /opt/n8n/.env "$backup_dir/" 2>/dev/null || true
    
    ui_stop_spinner
    ui_status "success" "Đã backup cài đặt hiện tại"
}

# ===== SYSTEM REQUIREMENTS CHECK =====

check_n8n_requirements() {
    ui_section "Kiểm tra yêu cầu hệ thống"

    local errors=0
    local checks=(
        "check_os_version"
        "check_ram_requirements"
        "check_disk_space"
        "check_cpu_cores"
        "check_internet_connection"
        "check_required_commands"
    )

    for check in "${checks[@]}"; do
        if ! $check; then
            ((errors++))
        fi
    done

    echo ""
    if [[ $errors -eq 0 ]]; then
        ui_status "success" "Tất cả yêu cầu hệ thống đều được đáp ứng"
        return 0
    else
        ui_status "error" "Phát hiện $errors lỗi yêu cầu hệ thống"
        return 1
    fi
}

check_os_version() {
    local ubuntu_version=$(get_ubuntu_version)

    if [[ "${ubuntu_version%%.*}" -lt 18 ]]; then
        ui_status "error" "Ubuntu ${ubuntu_version} - Yêu cầu 18.04+"
        return 1
    else
        ui_status "success" "Ubuntu ${ubuntu_version}"
        return 0
    fi
}

check_ram_requirements() {
    local total_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')

    if [[ "$total_ram_mb" -lt "$REQUIRED_RAM_MB" ]]; then
        ui_status "error" "RAM: ${total_ram_mb}MB (yêu cầu ${REQUIRED_RAM_MB}MB+)"
        return 1
    else
        ui_status "success" "RAM: ${total_ram_mb}MB"
        return 0
    fi
}

check_disk_space() {
    local free_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ "$free_disk_gb" -lt "$REQUIRED_DISK_GB" ]]; then
        ui_status "error" "Disk: ${free_disk_gb}GB (yêu cầu ${REQUIRED_DISK_GB}GB+)"
        return 1
    else
        ui_status "success" "Disk: ${free_disk_gb}GB available"
        return 0
    fi
}

check_cpu_cores() {
    local cpu_cores=$(nproc)

    if [[ "$cpu_cores" -lt 2 ]]; then
        ui_status "warning" "CPU: $cpu_cores core (khuyến nghị 2+)"
        return 0
    else
        ui_status "success" "CPU: $cpu_cores cores"
        return 0
    fi
}

check_internet_connection() {
    if ping -c 1 -W 2 google.com >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        ui_status "success" "Kết nối internet OK"
        return 0
    else
        ui_status "error" "Không có kết nối internet"
        return 1
    fi
}

check_required_commands() {
    local commands=("curl" "wget" "git" "jq")
    local missing=()

    for cmd in "${commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        ui_status "success" "Tất cả commands cần thiết đã có"
        return 0
    else
        ui_status "warning" "Thiếu commands: ${missing[*]} (sẽ cài đặt tự động)"
        return 0
    fi
}

# ===== CONFIGURATION COLLECTION =====

collect_installation_configuration() {
    ui_header "Cấu hình N8N"

    # N8N Port
    while true; do
        echo -n -e "${UI_WHITE}Port cho N8N (mặc định $N8N_DEFAULT_PORT): ${UI_NC}"
        read -r N8N_PORT
        N8N_PORT=${N8N_PORT:-$N8N_DEFAULT_PORT}

        if ui_validate_port "$N8N_PORT"; then
            if is_port_available "$N8N_PORT"; then
                ui_status "success" "Port N8N: $N8N_PORT"
                break
            else
                ui_status "error" "Port $N8N_PORT đã được sử dụng"
            fi
        else
            ui_status "error" "Port không hợp lệ: $N8N_PORT"
        fi
    done

    # PostgreSQL Port
    while true; do
        echo -n -e "${UI_WHITE}Port cho PostgreSQL (mặc định $POSTGRES_DEFAULT_PORT): ${UI_NC}"
        read -r POSTGRES_PORT
        POSTGRES_PORT=${POSTGRES_PORT:-$POSTGRES_DEFAULT_PORT}

        if ui_validate_port "$POSTGRES_PORT"; then
            if is_port_available "$POSTGRES_PORT"; then
                ui_status "success" "Port PostgreSQL: $POSTGRES_PORT"
                break
            else
                ui_status "error" "Port $POSTGRES_PORT đã được sử dụng"
            fi
        else
            ui_status "error" "Port không hợp lệ: $POSTGRES_PORT"
        fi
    done

    # Domain (optional)
    echo -n -e "${UI_WHITE}Domain cho N8N (để trống nếu chưa có): ${UI_NC}"
    read -r N8N_DOMAIN

    if [[ -n "$N8N_DOMAIN" ]] && ! ui_validate_domain "$N8N_DOMAIN"; then
        echo -n -e "${UI_YELLOW}Domain có vẻ không hợp lệ. Bạn có chắc muốn sử dụng '$N8N_DOMAIN'? [y/N]: ${UI_NC}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            N8N_DOMAIN=""
        fi
    fi

    # Webhook URL
    if [[ -n "$N8N_DOMAIN" ]]; then
        N8N_WEBHOOK_URL="https://$N8N_DOMAIN"
        ui_status "success" "Domain: $N8N_DOMAIN"
    else
        local public_ip=$(get_public_ip || echo "localhost")
        N8N_WEBHOOK_URL="http://$public_ip:$N8N_PORT"
        ui_status "info" "Sử dụng IP: $public_ip"
    fi

    # Configuration summary
    ui_info_box "Tóm tắt cấu hình" \
        "N8N Port: $N8N_PORT" \
        "PostgreSQL Port: $POSTGRES_PORT" \
        "$([ -n "$N8N_DOMAIN" ] && echo "Domain: $N8N_DOMAIN")" \
        "Webhook URL: $N8N_WEBHOOK_URL"

    echo -n -e "${UI_YELLOW}Xác nhận cấu hình? [Y/n]: ${UI_NC}"
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        return 1
    else
        return 0
    fi
}

# ===== DEPENDENCIES INSTALLATION =====

install_docker() {
    ui_section "Cài đặt Docker"

    if command_exists docker; then
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        ui_status "success" "Docker đã cài đặt: $docker_version"
        return 0
    fi

    # Install Docker
    if ! ui_run_command "Cài đặt Docker dependencies" "sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"; then
        return 1
    fi

    if ! ui_run_command "Thêm Docker GPG key" "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"; then
        return 1
    fi

    if ! ui_run_command "Thêm Docker repository" 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null'; then
        return 1
    fi

    if ! ui_run_command "Cài đặt Docker Engine" "sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"; then
        return 1
    fi

    if ! ui_run_command "Cấu hình Docker user" "sudo usermod -aG docker $USER"; then
        return 1
    fi

    if ! ui_run_command "Khởi động Docker" "sudo systemctl enable docker && sudo systemctl start docker"; then
        return 1
    fi

    ui_warning_box "Thông báo quan trọng" \
        "Bạn cần logout và login lại để sử dụng Docker không cần sudo"

    return 0
}

install_dependencies() {
    ui_section "Cài đặt Dependencies"

    local packages=(
        "nginx:Reverse proxy server"
        "postgresql-client:PostgreSQL client tools"
        "jq:JSON processor"
        "curl:HTTP client"
        "wget:Download utility"
        "git:Version control"
        "htop:System monitor"
        "ncdu:Disk usage analyzer"
    )

    ui_show_progress 0 ${#packages[@]} "Chuẩn bị cài đặt packages"

    if ! ui_run_command "Cập nhật package list" "sudo apt-get update"; then
        return 1
    fi

    local i=1
    for package_info in "${packages[@]}"; do
        local package="${package_info%%:*}"
        local description="${package_info##*:}"

        ui_show_progress $i ${#packages[@]} "Cài đặt $package"

        if ! dpkg -l | grep -q "^ii  $package "; then
            if ! install_spinner "Cài đặt $package ($description)" "sudo apt-get install -y $package"; then
                ui_status "error" "Lỗi cài đặt $package"
                return 1
            fi
        else
            ui_status "success" "$package đã cài đặt"
        fi

        ((i++))
    done

    return 0
}

# ===== DOCKER INSTALLATION =====

create_docker_compose() {
    ui_section "Tạo Docker Compose Configuration"

    local compose_dir="/opt/n8n"

    if ! ui_run_command "Tạo thư mục cài đặt" "sudo mkdir -p $compose_dir"; then
        return 1
    fi

    local postgres_password=$(generate_random_string 32)

    # Create temp files
    local temp_compose="/tmp/docker-compose-n8n.yml"
    local temp_env="/tmp/env-n8n"

    ui_start_spinner "Tạo docker-compose.yml"

    cat >"$temp_compose" <<'DOCKER_EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=PASSWORD_PLACEHOLDER
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "PG_PORT_PLACEHOLDER:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - N8N_HOST=0.0.0.0
      - N8N_PORT=PORT_PLACEHOLDER
      - N8N_PROTOCOL=http
      - NODE_ENV=production
      - WEBHOOK_URL=WEBHOOK_PLACEHOLDER
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=PASSWORD_PLACEHOLDER
      - EXECUTIONS_MODE=regular
      - EXECUTIONS_PROCESS=main
      - N8N_METRICS=false
    ports:
      - "PORT_PLACEHOLDER:PORT_PLACEHOLDER"
    volumes:
      - n8n_data:/home/node/.n8n
      - ./backups:/backups
    networks:
      - n8n-network

volumes:
  postgres_data:
    driver: local
  n8n_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
DOCKER_EOF

    # Replace placeholders
    sed -i "s#PASSWORD_PLACEHOLDER#$postgres_password#g" "$temp_compose"
    sed -i "s#PG_PORT_PLACEHOLDER#$POSTGRES_PORT#g" "$temp_compose"
    sed -i "s#PORT_PLACEHOLDER#$N8N_PORT#g" "$temp_compose"
    sed -i "s#WEBHOOK_PLACEHOLDER#$N8N_WEBHOOK_URL#g" "$temp_compose"

    ui_stop_spinner

    # Create .env file
    ui_start_spinner "Tạo file environment"

    cat >"$temp_env" <<EOF
# DataOnline N8N Manager - Environment Variables
# Generated at: $(date)

# N8N Configuration
N8N_PORT=$N8N_PORT
N8N_DOMAIN=$N8N_DOMAIN
N8N_WEBHOOK_URL=$N8N_WEBHOOK_URL

# PostgreSQL Configuration
POSTGRES_PORT=$POSTGRES_PORT
POSTGRES_PASSWORD=$postgres_password

# Backup Configuration
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=30
EOF

    ui_stop_spinner

    # Copy files
    if ! ui_run_command "Sao chép docker-compose.yml" "sudo cp $temp_compose $compose_dir/docker-compose.yml"; then
        rm -f "$temp_compose" "$temp_env"
        return 1
    fi

    if ! ui_run_command "Sao chép .env file" "sudo cp $temp_env $compose_dir/.env"; then
        rm -f "$temp_compose" "$temp_env"
        return 1
    fi

    # Set permissions
    if ! ui_run_command "Cấp quyền files" "sudo chmod 644 $compose_dir/docker-compose.yml && sudo chmod 600 $compose_dir/.env"; then
        return 1
    fi

    # Cleanup
    rm -f "$temp_compose" "$temp_env"

    # Save config
    config_set "n8n.install_type" "docker"
    config_set "n8n.compose_dir" "$compose_dir"
    config_set "n8n.port" "$N8N_PORT"
    config_set "n8n.webhook_url" "$N8N_WEBHOOK_URL"

    ui_status "success" "Docker Compose configuration tạo thành công"
    return 0
}

start_n8n_docker() {
    ui_section "Khởi động N8N với Docker"

    local compose_dir="/opt/n8n"
    cd "$compose_dir" || return 1

    if ! ui_run_command "Tải Docker images" "sudo docker compose pull"; then
        return 1
    fi

    if ! ui_run_command "Khởi động containers" "sudo docker compose up -d"; then
        return 1
    fi

    # Wait for N8N to be ready
    ui_start_spinner "Chờ N8N khởi động"
    local max_wait=60
    local waited=0

    while [[ $waited -lt $max_wait ]]; do
        if curl -s "http://localhost:$N8N_PORT/healthz" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_status "success" "N8N đã khởi động thành công!"
            break
        fi
        sleep 2
        ((waited += 2))
    done

    if [[ $waited -ge $max_wait ]]; then
        ui_stop_spinner
        ui_status "error" "Timeout chờ N8N khởi động"
        ui_status "info" "Kiểm tra logs: sudo docker compose logs -f"
        return 1
    fi

    cd - >/dev/null
    return 0
}

# ===== VERIFICATION =====

verify_installation() {
    ui_section "Kiểm tra cài đặt"

    local errors=0

    # Check containers
    local containers=("n8n" "n8n-postgres")
    for container in "${containers[@]}"; do
        if sudo docker ps --format "table {{.Names}}" | grep -q "^$container$"; then
            ui_status "success" "Container $container đang chạy"
        else
            ui_status "error" "Container $container không chạy"
            ((errors++))
        fi
    done

    # Check N8N API
    if curl -s "http://localhost:$N8N_PORT/healthz" >/dev/null 2>&1; then
        ui_status "success" "N8N API hoạt động"
    else
        ui_status "error" "N8N API không phản hồi"
        ((errors++))
    fi

    # Check database
    if sudo docker exec n8n-postgres pg_isready -U n8n >/dev/null 2>&1; then
        ui_status "success" "PostgreSQL hoạt động"
    else
        ui_status "error" "PostgreSQL lỗi"
        ((errors++))
    fi

    # Show access info
    ui_info_box "Thông tin truy cập N8N" \
        "URL: http://localhost:$N8N_PORT" \
        "$([ -n "$N8N_DOMAIN" ] && echo "Domain: https://$N8N_DOMAIN")" \
        "📝 Lần đầu truy cập sẽ yêu cầu tạo admin account"

    if [[ $errors -eq 0 ]]; then
        ui_status "success" "Cài đặt hoàn tất - Tất cả dịch vụ hoạt động!"
        return 0
    else
        ui_status "error" "Phát hiện $errors lỗi"
        return 1
    fi
}

# ===== HELPER FUNCTIONS =====

create_systemd_service() {
    ui_run_command "Tạo systemd service" "sudo tee /etc/systemd/system/n8n.service > /dev/null << 'EOF'
[Unit]
Description=N8N Workflow Automation
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload && sudo systemctl enable n8n.service"
}

show_post_install_guide() {
    ui_info_box "Hướng dẫn sau cài đặt" \
        "1. Truy cập N8N và tạo admin account" \
        "2. Cấu hình domain và SSL (nếu có)" \
        "3. Thiết lập backup tự động" \
        "4. Kiểm tra firewall cho port 80/443"

    ui_info_box "Quản lý service" \
        "Start: sudo systemctl start n8n" \
        "Stop: sudo systemctl stop n8n" \
        "Restart: sudo systemctl restart n8n" \
        "Logs: sudo docker compose -f /opt/n8n/docker-compose.yml logs -f"
}

export -f install_n8n_main