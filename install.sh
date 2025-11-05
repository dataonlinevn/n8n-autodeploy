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
REPO_URL="https://github.com/HungNM1486/DataOnline_N8N_Manager.git"
INSTALL_DIR="/opt/datalonline-n8n-manager"
BINARY_PATH="/usr/local/bin/datalonline-n8n-manager"

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
│                   Version 1.0.0                         │
│               https://datalonline.vn                     │
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
    log_info "Installing DataOnline N8N Manager..."
    
    # Remove existing installation
    if [[ -d "$INSTALL_DIR" ]]; then
        log_warn "Removing existing installation"
        sudo rm -rf "$INSTALL_DIR"
    fi
    
    # Clone repository
    log_info "Downloading latest version..."
    sudo git clone "$REPO_URL" "$INSTALL_DIR"
    
    # Set permissions
    sudo chmod +x "$INSTALL_DIR/scripts/manager.sh"
    sudo chmod +x "$INSTALL_DIR/src"/**/*.sh 2>/dev/null || true
    
    # Create global command
    sudo ln -sf "$INSTALL_DIR/scripts/manager.sh" "$BINARY_PATH"
    
    log_success "Manager installed to $INSTALL_DIR"
}

# Setup completion
complete_setup() {
    log_success "Installation completed successfully!"
    echo ""
    echo -e "${GREEN}Quick Start:${NC}"
    echo -e "  ${BLUE}datalonline-n8n-manager${NC}     # Start manager"
    echo -e "  ${BLUE}$INSTALL_DIR/scripts/manager.sh${NC}  # Alternative command"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  1. Run the manager and install N8N"
    echo "  2. Configure domain and SSL (optional)"
    echo "  3. Setup automated backups"
    echo ""
    echo -e "${GREEN}Documentation:${NC}"
    echo "  • Installation Guide: $INSTALL_DIR/INSTALLATION.md"
    echo "  • User Manual: $INSTALL_DIR/USER_MANUAL.md"
    echo "  • Troubleshooting: $INSTALL_DIR/TROUBLESHOOTING.md"
    echo ""
    echo -e "${GREEN}Support:${NC}"
    echo "  • GitHub: https://github.com/dataonline-vn/n8n-manager"
    echo "  • Email: support@dataonline.vn"
    echo ""
}

# Main installation function
main() {
    show_header
    
    log_info "Starting DataOnline N8N Manager installation..."
    echo ""
    
    # Confirm installation
    echo -n "Continue with installation? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    echo ""
    check_requirements
    echo ""
    install_manager
    echo ""
    complete_setup
}

# Run main function
main "$@"
EOF

# Make executable
chmod +x install.sh

# Test installation script
./install.sh --help 2>/dev/null || echo "Install script created"