#!/bin/bash

# DataOnline N8N Manager - Install Requirements Module
# Phiên bản: 1.0.0

set -euo pipefail

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
        "check_docker_installation"
    )

    for check in "${checks[@]}"; do
        if ! $check; then
            ((errors++))
        fi
    done

    echo ""
    if [[ $errors -eq 0 ]]; then
        ui_success "Tất cả yêu cầu hệ thống đều được đáp ứng"
        return 0
    else
        ui_error "Phát hiện $errors lỗi yêu cầu hệ thống" "REQUIREMENTS_FAILED"
        return 1
    fi
}

check_os_version() {
    local ubuntu_version=$(get_ubuntu_version)

    if [[ "${ubuntu_version%%.*}" -lt 18 ]]; then
        ui_error "Ubuntu ${ubuntu_version} - Yêu cầu 18.04+" "UBUNTU_VERSION_UNSUPPORTED"
        return 1
    else
        ui_success "Ubuntu ${ubuntu_version}"
        return 0
    fi
}

check_ram_requirements() {
    local total_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')

    if [[ "$total_ram_mb" -lt "$REQUIRED_RAM_MB" ]]; then
        ui_error "RAM: ${total_ram_mb}MB (yêu cầu ${REQUIRED_RAM_MB}MB+)" "LOW_RAM"
        return 1
    else
        ui_success "RAM: ${total_ram_mb}MB"
        return 0
    fi
}

check_disk_space() {
    local free_disk_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ "$free_disk_gb" -lt "$REQUIRED_DISK_GB" ]]; then
        ui_error "Disk: ${free_disk_gb}GB (yêu cầu ${REQUIRED_DISK_GB}GB+)" "LOW_DISK"
        return 1
    else
        ui_success "Disk: ${free_disk_gb}GB available"
        return 0
    fi
}

check_cpu_cores() {
    local cpu_cores=$(nproc)

    if [[ "$cpu_cores" -lt 2 ]]; then
        ui_warning "CPU: $cpu_cores core (khuyến nghị 2+)"
        return 0
    else
        ui_success "CPU: $cpu_cores cores"
        return 0
    fi
}

check_internet_connection() {
    if ping -c 1 -W 2 google.com >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        ui_success "Kết nối internet OK"
        return 0
    else
        ui_error "Không có kết nối internet" "NO_INTERNET"
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
        ui_success "Tất cả commands cần thiết đã có"
        return 0
    else
        ui_warning "Thiếu commands: ${missing[*]} (sẽ cài đặt tự động)"
        return 0
    fi
}

check_docker_installation() {
    if ! command_exists docker; then
        ui_error "Docker chưa được cài đặt" "DOCKER_NOT_INSTALLED"
        echo ""
        echo "Docker là bắt buộc để cài đặt N8N. Vui lòng cài đặt Docker trước:"
        echo ""
        echo "  curl -fsSL https://get.docker.com -o get-docker.sh"
        echo "  sudo sh get-docker.sh"
        echo "  sudo usermod -aG docker \$USER"
        echo ""
        echo "Sau đó đăng xuất và đăng nhập lại, hoặc chạy: newgrp docker"
        echo ""
        return 1
    fi

    # Kiểm tra Docker daemon đang chạy
    if ! docker info >/dev/null 2>&1; then
        ui_error "Docker daemon không chạy" "DOCKER_DAEMON_NOT_RUNNING"
        echo ""
        echo "Vui lòng khởi động Docker daemon:"
        echo "  sudo systemctl start docker"
        echo "  sudo systemctl enable docker"
        echo ""
        return 1
    fi

    # Kiểm tra Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        ui_error "Docker Compose chưa được cài đặt" "DOCKER_COMPOSE_NOT_INSTALLED"
        echo ""
        echo "Vui lòng cài đặt Docker Compose:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y docker-compose-plugin"
        echo ""
        return 1
    fi

    local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    ui_success "Docker: $docker_version"
    
    if docker compose version >/dev/null 2>&1; then
        local compose_version=$(docker compose version | cut -d' ' -f4)
        ui_success "Docker Compose: $compose_version"
    elif command_exists docker-compose; then
        local compose_version=$(docker-compose --version | cut -d' ' -f4 | cut -d',' -f1)
        ui_success "Docker Compose: $compose_version"
    fi

    return 0
}

export -f check_n8n_requirements check_os_version check_ram_requirements check_disk_space check_cpu_cores check_internet_connection check_required_commands check_docker_installation
