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

# Sửa /etc/hosts nếu hostname chưa có để tránh cảnh báo sudo
fix_hostname_in_hosts() {
    local hostname
    hostname=$(hostname 2>/dev/null || echo "")
    
    # Bỏ qua nếu không lấy được hostname
    [[ -z "$hostname" ]] && return 0
    
    # Kiểm tra xem hostname đã có trong /etc/hosts chưa
    if ! grep -qE "^\s*127\.0\.0\.1\s+.*\b${hostname}\b" /etc/hosts 2>/dev/null; then
        # Thêm hostname vào /etc/hosts nếu chưa có (thêm vào dòng localhost nếu có)
        if grep -q "^127.0.0.1.*localhost" /etc/hosts 2>/dev/null; then
            # Thêm vào dòng localhost hiện có
            sudo sed -i "s/^\(127\.0\.0\.1.*localhost\)/\1 ${hostname}/" /etc/hosts 2>/dev/null || true
        else
            # Thêm dòng mới
            sudo sh -c "echo '127.0.0.1 localhost ${hostname}' >> /etc/hosts" 2>/dev/null || true
        fi
    fi
}

check_docker_installation() {
    # Biến để lưu lệnh docker (có thể cần sudo)
    local docker_cmd="docker"
    
    # Sửa /etc/hosts để tránh cảnh báo sudo
    fix_hostname_in_hosts
    
    # Kiểm tra và cài đặt Docker nếu chưa có
    if ! command_exists docker; then
        ui_warning "Docker chưa được cài đặt" "DOCKER_NOT_INSTALLED"
        echo ""
        
        if ! ui_confirm "Bạn có muốn tự động cài đặt Docker không?" "y"; then
            ui_error "Docker là bắt buộc để cài đặt N8N" "DOCKER_REQUIRED"
            return 1
        fi
        
        ui_info "Đang cài đặt Docker..."
        
        # Tải và chạy script cài đặt Docker chính thức
        local docker_install_script="/tmp/get-docker.sh"
        if ! curl -fsSL https://get.docker.com -o "$docker_install_script"; then
            ui_error "Không thể tải script cài đặt Docker" "DOCKER_DOWNLOAD_FAILED"
            return 1
        fi
        
        if ! sudo sh "$docker_install_script"; then
            ui_error "Cài đặt Docker thất bại" "DOCKER_INSTALL_FAILED"
            rm -f "$docker_install_script"
            return 1
        fi
        
        rm -f "$docker_install_script"
        
        # Thêm user vào docker group
        if ! groups | grep -q docker; then
            ui_info "Thêm user vào docker group..."
            sudo usermod -aG docker "$USER"
            ui_warning "User đã được thêm vào docker group"
            ui_info "Để áp dụng thay đổi, bạn có thể:"
            ui_info "  1. Đăng xuất và đăng nhập lại"
            ui_info "  2. Hoặc chạy: newgrp docker"
            ui_info "  3. Hoặc tiếp tục với sudo (nếu cần)"
            echo ""
            
            # Thử sử dụng sg để chạy docker command với group mới
            # Nếu không được, sẽ dùng sudo
            if ! sg docker -c "docker info" >/dev/null 2>&1; then
                ui_info "Sử dụng sudo để chạy Docker commands..."
            fi
        fi
        
        ui_success "Docker đã được cài đặt thành công"
    fi

    # Kiểm tra và khởi động Docker daemon
    # Thử chạy docker info, nếu không được thì thử với sudo
    if ! docker info >/dev/null 2>&1; then
        # Thử với sudo nếu user chưa có quyền
        if sudo docker info >/dev/null 2>&1; then
            docker_cmd="sudo docker"
            ui_info "Sử dụng sudo để chạy Docker commands"
        else
            ui_warning "Docker daemon không chạy, đang khởi động..."
            
            if ! sudo systemctl start docker; then
                ui_error "Không thể khởi động Docker daemon" "DOCKER_DAEMON_START_FAILED"
                return 1
            fi
            
            # Enable Docker để tự động khởi động khi boot
            sudo systemctl enable docker >/dev/null 2>&1
            
            # Chờ một chút để Docker daemon khởi động hoàn toàn
            sleep 2
            
            # Kiểm tra lại
            if ! docker info >/dev/null 2>&1 && ! sudo docker info >/dev/null 2>&1; then
                ui_error "Docker daemon vẫn không chạy" "DOCKER_DAEMON_NOT_RUNNING"
                return 1
            fi
            
            if ! docker info >/dev/null 2>&1; then
                docker_cmd="sudo docker"
            fi
            
            ui_success "Docker daemon đã được khởi động"
        fi
    fi

    # Xác định lại lệnh docker để sử dụng (có thể cần sudo)
    if ! docker --version >/dev/null 2>&1; then
        if sudo docker --version >/dev/null 2>&1; then
            docker_cmd="sudo docker"
        fi
    fi

    # Kiểm tra và cài đặt Docker Compose nếu thiếu
    if ! command_exists docker-compose && ! $docker_cmd compose version >/dev/null 2>&1; then
        ui_warning "Docker Compose chưa được cài đặt, đang cài đặt..."
        
        if ! sudo apt-get update -qq; then
            ui_error "Không thể cập nhật package list" "APT_UPDATE_FAILED"
            return 1
        fi
        
        if ! sudo apt-get install -y docker-compose-plugin; then
            ui_error "Cài đặt Docker Compose thất bại" "DOCKER_COMPOSE_INSTALL_FAILED"
            return 1
        fi
        
        ui_success "Docker Compose đã được cài đặt"
    fi

    # Hiển thị thông tin phiên bản
    
    local docker_version=$($docker_cmd --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo "unknown")
    ui_success "Docker: $docker_version"
    
    # Kiểm tra Docker Compose
    if $docker_cmd compose version >/dev/null 2>&1; then
        local compose_version=$($docker_cmd compose version 2>/dev/null | cut -d' ' -f4 || echo "unknown")
        ui_success "Docker Compose: $compose_version"
    elif command_exists docker-compose; then
        local compose_version=$(docker-compose --version 2>/dev/null | cut -d' ' -f4 | cut -d',' -f1 || echo "unknown")
        ui_success "Docker Compose: $compose_version"
    fi

    return 0
}

export -f check_n8n_requirements check_os_version check_ram_requirements check_disk_space check_cpu_cores check_internet_connection check_required_commands check_docker_installation fix_hostname_in_hosts
