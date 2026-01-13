#!/bin/bash
# DataOnline N8N Manager - One-Click Installer
# Version: 1.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/vanntpt/n8n-autodeploy"
INSTALL_DIR="/opt/dataonline-n8n-manager"
BINARY_PATH="/usr/local/bin/dataonline-n8n-manager"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Header
show_header() {
    echo -e "${BLUE}"
    cat << 'EOF'
╭──────────────────────────────────────────────────────────╮
│                DataOnline N8N Manager                    │
│                   Version 1.0.0                          │ 
│               https://dataonline.vn                      │
╰──────────────────────────────────────────────────────────╯
EOF
    echo -e "${NC}"
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/lsb-release ]]; then
        log_error "This installer requires Ubuntu Linux"
        exit 1
    fi
    
    source /etc/lsb-release
    local version=${DISTRIB_RELEASE%%.*}
    
    if [[ "$version" -lt 20 ]]; then
        log_error "Ubuntu 20.04 or higher required (current: $DISTRIB_RELEASE)"
        exit 1
    fi
    
    log_success "Ubuntu $DISTRIB_RELEASE detected"
    
    # Check dependencies
    local deps=("curl" "git" "sudo")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_warn "Installing missing dependency: $dep"
            sudo apt update
            sudo apt install -y "$dep"
        fi
    done
    
    log_success "System requirements satisfied"
}

# Install manager
install_manager() {
    echo -e "${BLUE}[INFO]${NC} Đang cài đặt DataOnline N8N Manager..."
    
    # Remove existing installation
    sudo rm -rf "$INSTALL_DIR"
    
    # Check if we're in a git repository (development mode)
    local current_dir
    current_dir="$(pwd)"
    if [[ -d "$current_dir/.git" ]] && [[ -f "$current_dir/scripts/manager.sh" ]]; then
        sudo cp -r "$current_dir" "$INSTALL_DIR"
        sudo rm -rf "$INSTALL_DIR/.git"
    else
        # Clone repository
        sudo git clone -q "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
    fi
    
    # Set permissions
    sudo chmod +x "$INSTALL_DIR/scripts/manager.sh"
    sudo find "$INSTALL_DIR/src" -type f -name '*.sh' -exec chmod +x {} +
    
    # Create global command
    sudo ln -sf "$INSTALL_DIR/scripts/manager.sh" "$BINARY_PATH"
    
    log_success "Đã cài đặt bộ quản lý tại $INSTALL_DIR"
}

# Setup completion
complete_setup() {
    ui_success "Cài đặt thành công!"
    echo ""
    echo -e "${UI_GREEN}Khởi động nhanh:${UI_NC}"
    echo -e "  ${UI_BLUE}dataonline-n8n-manager${UI_NC}     # Mở bộ quản lý"
    echo ""
    echo -e "${UI_GREEN}Bước tiếp theo:${UI_NC}"
    echo "  1. Chạy lệnh trên để bắt đầu cài đặt n8n"
    echo "  2. Cấu hình tên miền và SSL (tùy chọn)"
    echo "  3. Thiết lập sao lưu tự động"
    echo ""
}

# Main installation function
main() {
    # Check for UI module
    if [[ -f "./src/core/ui.sh" ]]; then
        source "./src/core/ui.sh"
    fi

    show_header
    
    echo -e "${UI_BLUE}[HỆ THỐNG]${UI_NC} Đang khởi động trình cài đặt DataOnline N8N Manager..."
    echo ""
    
    # Confirm installation
    echo -n "Bạn có muốn tiếp tục cài đặt không? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${UI_YELLOW}[HỦY]${UI_NC} Đã dừng quá trình cài đặt."
        exit 0
    fi
    
    echo ""
    install_manager
    echo ""
    complete_setup
}

# Run main function
main "$@"