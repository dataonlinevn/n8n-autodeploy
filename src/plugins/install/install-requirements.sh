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

    local missing_reqs=0
    for check in "${checks[@]}"; do
        if ! $check >/dev/null 2>&1; then
            # Run again without silence to show error if it failed
            $check || ((missing_reqs++))
        fi
    done

    echo ""
    if [[ $missing_reqs -eq 0 ]]; then
        ui_success "Hệ thống đáp ứng đầy đủ yêu cầu cài đặt"
        return 0
    else
        ui_error "Phát hiện $missing_reqs yêu cầu hệ thống chưa đạt"
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
        ui_error "Dung lượng đĩa: Còn ${free_disk_gb}GB (yêu cầu tối thiểu ${REQUIRED_DISK_GB}GB)"
        return 1
    else
        ui_success "Dung lượng đĩa: Hợp lệ (${free_disk_gb}GB trống)"
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
        echo -e "${UI_YELLOW}Hệ thống cần cài đặt Docker để vận hành ứng dụng.${UI_NC}"
        
        if ! ui_confirm "Bạn có muốn hệ thống tự động cài đặt Docker không?"; then
            ui_error "Lỗi: Docker là thành phần bắt buộc."
            return 1
        fi
        
        ui_start_spinner "Đang cài đặt môi trường Docker..."
        
        # Tải và chạy script cài đặt Docker chính thức
        local docker_install_script="/tmp/get-docker.sh"
        if ! curl -fsSL https://get.docker.com -o "$docker_install_script" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_error "Không thể tải script cài đặt Docker"
            return 1
        fi
        
        if ! sudo sh "$docker_install_script" >/dev/null 2>&1; then
            ui_stop_spinner
            ui_error "Cài đặt Docker thất bại"
            rm -f "$docker_install_script"
            return 1
        fi
        
        rm -f "$docker_install_script"
        
        # Thêm user vào docker group (silent)
        if ! groups | grep -q docker; then
            sudo usermod -aG docker "$USER" >/dev/null 2>&1
        fi
        
        ui_stop_spinner
        ui_success "Cài đặt Docker hoàn tất"
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
                ui_error "Không thể khởi động dịch vụ Docker"
                return 1
            fi
            
            # Enable Docker để tự động khởi động khi boot
            sudo systemctl enable docker >/dev/null 2>&1
            sleep 1
            
            # Kiểm tra lại
            if ! docker info >/dev/null 2>&1 && ! sudo docker info >/dev/null 2>&1; then
                ui_error "Dịch vụ Docker gặp lỗi không thể khởi động"
                return 1
            fi
        fi
    fi

    # Xác định lại lệnh docker để sử dụng (có thể cần sudo)
    if ! docker --version >/dev/null 2>&1; then
        if sudo docker --version >/dev/null 2>&1; then
            docker_cmd="sudo docker"
        fi
    fi

    # Kiểm tra Docker Compose
    if ! command_exists docker-compose && ! $docker_cmd compose version >/dev/null 2>&1; then
        ui_start_spinner "Đang cài đặt Docker Compose..."
        
        if ! sudo apt-get update -qq && sudo apt-get install -y docker-compose-plugin >/dev/null 2>&1; then
            ui_stop_spinner
            ui_error "Cài đặt Docker Compose thất bại"
            return 1
        fi
        
        ui_stop_spinner
        ui_success "Cài đặt Docker Compose hoàn tất"
    fi

    # Hiển thị thông tin phiên bản (Silent if already installed)
    # local docker_version=$($docker_cmd --version 2>/dev/null | cut -d' ' -f3 | cut -d',' -f1 || echo "unknown")
    # ui_success "Docker: $docker_version"
    
    return 0
}

export -f check_n8n_requirements check_os_version check_ram_requirements check_disk_space check_cpu_cores check_internet_connection check_required_commands check_docker_installation fix_hostname_in_hosts
