#!/bin/bash
set -uo pipefail

# Complete SRE Assignment Setup Script
# This script handles everything from OS detection to full deployment
# with user confirmations for major actions

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${CYAN}${BOLD}$1${NC}"; }

# Function to prompt for user confirmation
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        echo -e "${YELLOW}$message [Y/n]:${NC} "
    else
        echo -e "${YELLOW}$message [y/N]:${NC} "
    fi
    
    read -r response
    case $response in
        [yY][eE][sS]|[yY]) return 0 ;;
        [nN][oO]|[nN]) return 1 ;;
        "") [ "$default" = "y" ] && return 0 || return 1 ;;
        *) 
            echo "Please answer yes or no."
            confirm "$message" "$default"
            ;;
    esac
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        
        if [[ "$ID" == "ubuntu" || "$ID_LIKE" == *"debian"* ]]; then
            OS_TYPE="debian"
            PACKAGE_MANAGER="apt"
        elif [[ "$ID" == "centos" || "$ID" == "rhel" || "$ID" == "fedora" || "$ID_LIKE" == *"rhel"* ]]; then
            OS_TYPE="rhel"
            PACKAGE_MANAGER="yum"
            [ "$ID" == "fedora" ] && PACKAGE_MANAGER="dnf"
        else
            OS_TYPE="unknown"
            PACKAGE_MANAGER="unknown"
        fi
    else
        OS_NAME="Unknown"
        OS_TYPE="unknown"
        PACKAGE_MANAGER="unknown"
    fi
}

# Function to install system packages
install_system_packages() {
    log_header "═══ INSTALLING SYSTEM PACKAGES ═══"
    
    case $OS_TYPE in
        "debian")
            log_info "Detected Debian-based system: $OS_NAME"
            
            if confirm "Update package lists and install required packages?" "y"; then
                log_info "Updating package lists..."
                sudo apt-get update -qq || {
                    log_error "Failed to update package lists"
                    return 1
                }
                
                local packages="curl wget jq net-tools bc apache2-utils software-properties-common apt-transport-https ca-certificates gnupg lsb-release"
                log_info "Installing packages: $packages"
                sudo apt-get install -y $packages || {
                    log_error "Failed to install system packages"
                    return 1
                }
                log_success "System packages installed"
            else
                log_warning "Skipping system package installation"
            fi
            ;;
            
        "rhel")
            log_info "Detected RHEL-based system: $OS_NAME"
            
            if confirm "Update packages and install required packages?" "y"; then
                log_info "Updating packages..."
                sudo $PACKAGE_MANAGER update -y -q || {
                    log_error "Failed to update packages"
                    return 1
                }
                
                local packages="curl wget jq net-tools bc httpd-tools"
                log_info "Installing packages: $packages"
                sudo $PACKAGE_MANAGER install -y $packages || {
                    log_error "Failed to install system packages"
                    return 1
                }
                log_success "System packages installed"
            else
                log_warning "Skipping system package installation"
            fi
            ;;
            
        *)
            log_warning "Unknown OS type. You may need to install these packages manually:"
            echo "  - curl, wget, jq, net-tools, bc"
            echo "  - htpasswd (apache2-utils or httpd-tools)"
            if ! confirm "Continue anyway?"; then
                exit 1
            fi
            ;;
    esac
}

# Function to install Docker
install_docker() {
    log_header "═══ DOCKER INSTALLATION ═══"
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version | grep -oE '[0-9]+\.[0-9]+')
        log_success "Docker is already installed (version $docker_version)"
        
        # Check if Docker is running
        if ! docker info &> /dev/null; then
            if confirm "Docker is installed but not running. Start Docker service?" "y"; then
                sudo systemctl start docker
                sudo systemctl enable docker
                log_success "Docker service started"
            fi
        fi
        
        # Check if user is in docker group
        if ! groups | grep -q docker; then
            if confirm "Add current user to docker group (requires logout/login)?" "y"; then
                sudo usermod -aG docker $USER
                log_warning "Please logout and login again, or run 'newgrp docker' to apply group changes"
                if confirm "Run 'newgrp docker' now?"; then
                    exec sg docker "$0 $*"
                fi
            fi
        fi
        return 0
    fi
    
    log_info "Docker not found. Installing Docker..."
    
    if ! confirm "Install Docker CE?" "y"; then
        log_error "Docker is required for this setup"
        exit 1
    fi
    
    case $OS_TYPE in
        "debian")
            log_info "Installing Docker CE for Debian/Ubuntu..."
            
            # Remove old versions
            sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Add Docker repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            sudo apt-get update -qq
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
            
        "rhel")
            log_info "Installing Docker CE for RHEL/CentOS/Fedora..."
            
            # Remove old versions
            sudo $PACKAGE_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            
            # Install Docker CE
            if [ "$PACKAGE_MANAGER" = "dnf" ]; then
                sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                sudo yum install -y yum-utils
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
            
        *)
            log_error "Cannot install Docker automatically on this OS"
            log_info "Please install Docker manually from: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    log_success "Docker installed successfully"
    log_warning "Please logout and login again, or run 'newgrp docker' to apply group changes"
    
    if confirm "Run 'newgrp docker' now to continue?" "y"; then
        exec sg docker "$0 $*"
    else
        log_info "Please run this script again after logging out and back in"
        exit 0
    fi
}

# Function to install kubectl
install_kubectl() {
    log_header "═══ KUBECTL INSTALLATION ═══"
    
    if command -v kubectl &> /dev/null; then
        local kubectl_version=$(kubectl version --client --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        log_success "kubectl is already installed ($kubectl_version)"
        return 0
    fi
    
    log_info "kubectl not found. Installing kubectl..."
    
    if ! confirm "Install kubectl?" "y"; then
        log_error "kubectl is required for this setup"
        exit 1
    fi
    
    log_info "Installing kubectl..."
    
    # Get latest stable version
    local kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    
    case $OS_TYPE in
        "debian")
            # Method 1: Direct download (more reliable)
            curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
            ;;
            
        "rhel")
            # For RHEL-based systems
            curl -LO "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"
            chmod +x kubectl
            sudo mv kubectl /usr/local/bin/
            ;;
            
        *)
            log_error "Cannot install kubectl automatically on this OS"
            log_info "Please install kubectl manually from: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
            exit 1
            ;;
    esac
    
    log_success "kubectl installed successfully"
}

# Function to install Minikube
install_minikube() {
    log_header "═══ MINIKUBE INSTALLATION ═══"
    
    if command -v minikube &> /dev/null; then
        local minikube_version=$(minikube version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        log_success "Minikube is already installed ($minikube_version)"
        return 0
    fi
    
    log_info "Minikube not found. Installing Minikube..."
    
    if ! confirm "Install Minikube?" "y"; then
        log_error "Minikube is required for this setup"
        exit 1
    fi
    
    log_info "Installing Minikube..."
    
    # Download and install Minikube
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    chmod +x minikube-linux-amd64
    sudo mv minikube-linux-amd64 /usr/local/bin/minikube
    
    log_success "Minikube installed successfully"
}

# Function to install Helm (optional but recommended)
install_helm() {
    log_header "═══ HELM INSTALLATION (Optional) ═══"
    
    if command -v helm &> /dev/null; then
        local helm_version=$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        log_success "Helm is already installed ($helm_version)"
        return 0
    fi
    
    if confirm "Install Helm (recommended for advanced Kubernetes management)?" "n"; then
        log_info "Installing Helm..."
        
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
        chmod +x get_helm.sh
        ./get_helm.sh
        rm get_helm.sh
        
        log_success "Helm installed successfully"
    else
        log_info "Skipping Helm installation"
    fi
}

# Function to configure Docker
configure_docker() {
    log_header "═══ DOCKER CONFIGURATION ═══"
    
    log_info "Configuring Docker for insecure registries..."
    
    # Ensure Docker daemon config directory exists
    sudo mkdir -p /etc/docker
    
    local config_needed=false
    
    if [ ! -f /etc/docker/daemon.json ]; then
        config_needed=true
        log_info "Docker daemon.json not found"
    elif ! grep -q "insecure-registries" /etc/docker/daemon.json; then
        config_needed=true
        log_info "Insecure registries not configured in daemon.json"
    fi
    
    if [ "$config_needed" = true ]; then
        if confirm "Configure Docker for insecure registries (required for private registry)?" "y"; then
            # Backup existing config
            [ -f /etc/docker/daemon.json ] && sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
            
            # Create or update daemon.json
            cat << 'EOF' | sudo tee /etc/docker/daemon.json > /dev/null
{
  "insecure-registries": [
    "10.0.0.0/8",
    "localhost:5000",
    "localhost:30500"
  ]
}
EOF
            
            log_success "Docker configuration updated"
            
            if systemctl is-active docker &>/dev/null; then
                if confirm "Restart Docker daemon to apply changes?" "y"; then
                    log_info "Restarting Docker daemon..."
                    sudo systemctl restart docker
                    sleep 5
                    log_success "Docker daemon restarted"
                else
                    log_warning "Please restart Docker manually: sudo systemctl restart docker"
                fi
            fi
        else
            log_warning "Docker configuration skipped - registry may not work properly"
        fi
    else
        log_success "Docker is already configured for insecure registries"
    fi
}

# Function to verify system resources
check_system_resources() {
    log_header "═══ SYSTEM RESOURCES CHECK ═══"
    
    # Check RAM
    local total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_ram_gb=$((total_ram_kb / 1024 / 1024))
    
    log_info "Total RAM: ${total_ram_gb}GB"
    
    if [ $total_ram_gb -lt 8 ]; then
        log_warning "Less than 8GB RAM detected. This may cause performance issues."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_success "RAM check passed"
    fi
    
    # Check CPU cores
    local cpu_cores=$(nproc)
    log_info "CPU Cores: $cpu_cores"
    
    if [ $cpu_cores -lt 2 ]; then
        log_warning "Less than 2 CPU cores detected. This may cause performance issues."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_success "CPU check passed"
    fi
    
    # Check disk space
    local disk_avail_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    log_info "Available disk space: ${disk_avail_gb}GB"
    
    if [ $disk_avail_gb -lt 20 ]; then
        log_warning "Less than 20GB disk space available. This may not be sufficient."
        if ! confirm "Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_success "Disk space check passed"
    fi
}

# Function to verify network connectivity
check_network() {
    log_header "═══ NETWORK CONNECTIVITY CHECK ═══"
    
    local sites=("github.com" "k8s.gcr.io" "docker.io" "storage.googleapis.com")
    local failed=0
    
    for site in "${sites[@]}"; do
        if curl -s --connect-timeout 5 "https://$site" &>/dev/null; then
            log_success "✓ $site reachable"
        else
            log_error "✗ $site unreachable"
            ((failed++))
        fi
    done
    
    if [ $failed -gt 0 ]; then
        log_warning "$failed/$((${#sites[@]})) sites unreachable"
        if ! confirm "Network connectivity issues detected. Continue anyway?" "n"; then
            exit 1
        fi
    else
        log_success "All network checks passed"
    fi
}

# Function to setup project configuration
setup_project_config() {
    log_header "═══ PROJECT CONFIGURATION ═══"
    
    # Ensure we're in the right directory
    if [ ! -f "config/config.env" ] && [ ! -f "start.sh" ]; then
        log_error "Project files not found in current directory"
        log_info "Please run this script from the project root directory"
        exit 1
    fi
    
    # Create config if it doesn't exist
    if [ ! -f "config/config.env" ]; then
        if confirm "Create default configuration file?" "y"; then
            mkdir -p config
            cat > config/config.env << 'EOF'
# SRE Assignment Configuration

# Cluster Settings
MEMORY="8192"
CPUS="4"
DISK_SIZE="50g"

# Registry Settings
REGISTRY_PORT="30500"
REGISTRY_UI_PORT="30501"
REGISTRY_USER="admin"
REGISTRY_PASS="admin123"

# Namespaces
NAMESPACE_PROD="production"
NAMESPACE_MONITORING="monitoring"

# Service Versions
API_VERSION="1.0.0"
AUTH_VERSION="1.0.0"
IMAGE_VERSION="1.0.0"
FRONTEND_VERSION="1.0.0"

# Monitoring
GRAFANA_ADMIN_PASSWORD="admin123"
GRAFANA_NODEPORT="30030"

# MinIO Settings
MINIO_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE"
MINIO_SECRET_KEY="wJalrXUtnFEMI/K7MDENG/bPxRFCYEXAMPLEKEY"
EOF
            log_success "Configuration file created"
        else
            log_error "Configuration file is required"
            exit 1
        fi
    fi
    
    # Set executable permissions
    log_info "Setting executable permissions on scripts..."
    chmod +x *.sh 2>/dev/null || true
    chmod +x scripts/*.sh 2>/dev/null || true
    log_success "Script permissions set"
}

# Function to clean existing Minikube
clean_minikube() {
    if command -v minikube &> /dev/null && minikube status &>/dev/null; then
        log_warning "Existing Minikube cluster detected"
        if confirm "Clean existing Minikube cluster for fresh start?" "n"; then
            log_info "Stopping and deleting existing Minikube cluster..."
            minikube stop
            minikube delete --all --purge
            log_success "Minikube cluster cleaned"
        fi
    fi
}

# Function to run the main deployment
run_deployment() {
    log_header "═══ RUNNING DEPLOYMENT ═══"
    
    echo -e "${YELLOW}Choose deployment script:${NC}"
    echo "1. Enhanced start script (start-fresh.sh) - Recommended for new setups"
    echo "2. Original start script (start.sh) - Standard deployment"
    echo "3. Skip deployment (manual run later)"
    
    read -p "Enter choice (1-3) [1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            if [ -f "start-fresh.sh" ]; then
                log_info "Running enhanced deployment script..."
                chmod +x start-fresh.sh
                ./start-fresh.sh
            else
                log_warning "Enhanced script not found, falling back to standard script"
                chmod +x start.sh
                ./start.sh
            fi
            ;;
        2)
            if [ -f "start.sh" ]; then
                log_info "Running standard deployment script..."
                chmod +x start.sh
                ./start.sh
            else
                log_error "start.sh not found"
                exit 1
            fi
            ;;
        3)
            log_info "Deployment skipped. Run './start.sh' or './start-fresh.sh' when ready."
            return 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Main function
main() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                 SRE Assignment Complete Setup               ║
║              From Zero to Full Deployment                   ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    log_info "This script will install and configure everything needed for the SRE assignment"
    log_info "You will be prompted before any major changes are made to your system"
    
    if ! confirm "Proceed with complete setup?" "y"; then
        log_info "Setup cancelled"
        exit 0
    fi
    
    # Detect OS
    detect_os
    log_info "Detected OS: $OS_NAME ($OS_TYPE)"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        log_error "Please do not run this script as root"
        log_info "The script will prompt for sudo when needed"
        exit 1
    fi
    
    # Main setup steps
    check_system_resources
    check_network
    install_system_packages
    install_docker
    configure_docker
    install_kubectl
    install_minikube
    install_helm
    setup_project_config
    clean_minikube
    
    echo -e "\n${GREEN}${BOLD}═══ SETUP COMPLETE ═══${NC}"
    log_success "All prerequisites installed and configured!"
    
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "1. All required tools are now installed"
    echo "2. Docker is configured for the private registry"
    echo "3. Project configuration is ready"
    
    if confirm "Run the deployment now?" "y"; then
        run_deployment
    else
        echo -e "\n${CYAN}Manual deployment options:${NC}"
        echo "  ./start-fresh.sh    - Enhanced deployment (recommended)"
        echo "  ./start.sh          - Standard deployment"
        echo "  ./scripts/health-checks.sh - Health verification"
    fi
}

# Run main function
main "$@"