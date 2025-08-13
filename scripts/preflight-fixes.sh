#!/bin/bash

# Preflight fixes for fresh machine setup
# This script ensures all dependencies and configurations are in place

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Preflight Setup & Fixes${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. Check and install missing system packages
log_info "Checking system dependencies..."

# Function to check if running on Ubuntu/Debian
is_debian_based() {
    [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]
}

# Function to check if running on RHEL/CentOS/Fedora
is_rhel_based() {
    [ -f /etc/redhat-release ] || [ -f /etc/centos-release ] || [ -f /etc/fedora-release ]
}

# Install basic dependencies based on OS
if is_debian_based; then
    log_info "Debian-based system detected"
    
    # Check for essential packages
    PACKAGES_TO_INSTALL=""
    
    for pkg in curl wget jq netstat bc htpasswd; do
        case $pkg in
            netstat)
                if ! command -v netstat &> /dev/null; then
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL net-tools"
                fi
                ;;
            htpasswd)
                if ! command -v htpasswd &> /dev/null; then
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL apache2-utils"
                fi
                ;;
            *)
                if ! command -v $pkg &> /dev/null; then
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
                fi
                ;;
        esac
    done
    
    if [ -n "$PACKAGES_TO_INSTALL" ]; then
        log_warning "Installing missing packages: $PACKAGES_TO_INSTALL"
        sudo apt-get update -qq
        sudo apt-get install -y -qq $PACKAGES_TO_INSTALL
    else
        log_success "All system packages are installed"
    fi
    
elif is_rhel_based; then
    log_info "RHEL-based system detected"
    
    PACKAGES_TO_INSTALL=""
    
    for pkg in curl wget jq netstat bc htpasswd; do
        case $pkg in
            netstat)
                if ! command -v netstat &> /dev/null; then
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL net-tools"
                fi
                ;;
            htpasswd)
                if ! command -v htpasswd &> /dev/null; then
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL httpd-tools"
                fi
                ;;
            *)
                if ! command -v $pkg &> /dev/null; then
                    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg"
                fi
                ;;
        esac
    done
    
    if [ -n "$PACKAGES_TO_INSTALL" ]; then
        log_warning "Installing missing packages: $PACKAGES_TO_INSTALL"
        sudo yum install -y -q $PACKAGES_TO_INSTALL
    else
        log_success "All system packages are installed"
    fi
else
    log_warning "Unknown Linux distribution - skipping package installation"
    log_info "Please ensure these tools are installed: curl, wget, jq, netstat, bc, htpasswd"
fi

# 2. Check Docker configuration
log_info "Checking Docker configuration..."

# Ensure Docker daemon config directory exists
sudo mkdir -p /etc/docker

# Check if Docker daemon.json exists and has proper insecure-registries
if [ ! -f /etc/docker/daemon.json ]; then
    log_warning "Docker daemon.json not found, creating..."
    echo '{
  "insecure-registries": ["10.0.0.0/8", "localhost:5000", "localhost:30500"]
}' | sudo tee /etc/docker/daemon.json > /dev/null
    
    # Restart Docker to apply changes
    if systemctl is-active docker &>/dev/null; then
        log_info "Restarting Docker daemon..."
        sudo systemctl restart docker
        sleep 5
    fi
    log_success "Docker configuration created"
else
    # Check if insecure-registries is configured
    if ! grep -q "insecure-registries" /etc/docker/daemon.json; then
        log_warning "Adding insecure-registries to Docker config..."
        # Backup existing config
        sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup
        
        # Add insecure-registries using jq if available, otherwise use sed
        if command -v jq &> /dev/null; then
            jq '. + {"insecure-registries": ["10.0.0.0/8", "localhost:5000", "localhost:30500"]}' /etc/docker/daemon.json.backup | sudo tee /etc/docker/daemon.json > /dev/null
        else
            # Simple sed approach for basic JSON
            sudo sed -i 's/^{/{\n  "insecure-registries": ["10.0.0.0\/8", "localhost:5000", "localhost:30500"],/' /etc/docker/daemon.json
        fi
        
        # Restart Docker
        if systemctl is-active docker &>/dev/null; then
            log_info "Restarting Docker daemon..."
            sudo systemctl restart docker
            sleep 5
        fi
        log_success "Docker configuration updated"
    else
        log_success "Docker insecure-registries already configured"
    fi
fi

# 3. Create required directories
log_info "Creating required directories..."
mkdir -p /tmp/updated-apps
mkdir -p kubernetes/monitoring/dashboards
log_success "Directories created"

# 4. Check httpd image for htpasswd generation
log_info "Pulling httpd image for registry authentication..."
if ! docker image inspect httpd:2.4-alpine &>/dev/null; then
    docker pull httpd:2.4-alpine || log_warning "Failed to pull httpd image (will retry during setup)"
else
    log_success "httpd image already available"
fi

# 5. Set execute permissions on all scripts
log_info "Setting executable permissions on scripts..."
chmod +x *.sh 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
log_success "Script permissions set"

# 6. Verify Minikube driver compatibility
log_info "Checking Minikube driver..."
if command -v minikube &> /dev/null; then
    # Check if Docker is running
    if ! docker info &>/dev/null; then
        log_error "Docker is not running. Starting Docker..."
        sudo systemctl start docker || log_error "Failed to start Docker"
        sleep 5
    fi
    
    # Set default driver to docker if not set
    current_driver=$(minikube config get driver 2>/dev/null || echo "")
    if [ -z "$current_driver" ] || [ "$current_driver" = "none" ]; then
        log_info "Setting Minikube driver to docker..."
        minikube config set driver docker
        log_success "Minikube driver set to docker"
    else
        log_success "Minikube driver: $current_driver"
    fi
fi

# 7. Clean up any stale Minikube state
log_info "Checking for stale Minikube state..."
if command -v minikube &> /dev/null; then
    if minikube status &>/dev/null; then
        # Check if cluster is in a bad state
        if minikube status | grep -q "Stopped\|Paused"; then
            log_warning "Minikube in stopped/paused state, cleaning up..."
            minikube delete --all --purge
            log_success "Cleaned up stale Minikube state"
        else
            log_info "Minikube cluster appears healthy"
        fi
    fi
fi

# 8. Verify network connectivity
log_info "Checking network connectivity..."
if curl -s --connect-timeout 5 https://k8s.gcr.io &>/dev/null; then
    log_success "Internet connectivity verified"
else
    log_warning "Cannot reach k8s.gcr.io - may have issues pulling images"
fi

# 9. Check for conflicting services on required ports
log_info "Checking for port conflicts..."
PORTS_TO_CHECK=(80 443 5000 30000-32767)
CONFLICTS_FOUND=false

for port in 80 443 5000; do
    if netstat -tln 2>/dev/null | grep -q ":$port "; then
        log_warning "Port $port is already in use"
        CONFLICTS_FOUND=true
        
        # Try to identify the process
        if command -v lsof &>/dev/null; then
            log_info "Process using port $port:"
            sudo lsof -i :$port | head -3
        fi
    fi
done

if [ "$CONFLICTS_FOUND" = true ]; then
    log_warning "Port conflicts detected. The deployment may need to use alternative ports."
else
    log_success "No port conflicts detected"
fi

# 10. Create systemd service directory if needed
log_info "Preparing systemd configuration..."
if [ -d /etc/systemd/system ]; then
    log_success "Systemd directory exists"
else
    log_warning "Systemd not found - port forwarding service will not be available"
fi

# 11. Pre-create ConfigMaps to avoid race conditions
log_info "Preparing for ConfigMap creation..."
# This will be done during main deployment, just check if kubectl is available
if command -v kubectl &> /dev/null; then
    log_success "kubectl is available"
else
    log_info "kubectl not found - will be installed by main setup script"
fi

# 12. Set up environment variables if config doesn't exist
if [ ! -f config/config.env ]; then
    log_error "config/config.env not found!"
    log_info "Creating default configuration..."
    
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
    log_success "Default configuration created"
fi

# 13. Validate helm is installed (optional but recommended)
if ! command -v helm &> /dev/null; then
    log_warning "Helm not installed - some advanced features may not be available"
    log_info "To install helm: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
fi

# 14. Clean up any existing port-forward processes
log_info "Cleaning up existing port-forward processes..."
pkill -f "kubectl port-forward" 2>/dev/null || true
log_success "Port-forward cleanup complete"

# 15. Ensure temp directory permissions
log_info "Setting up temporary directories..."
mkdir -p /tmp/registry-data
chmod 777 /tmp/registry-data 2>/dev/null || true
log_success "Temporary directories configured"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Preflight checks and fixes complete!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Summary:${NC}"
echo "- System packages: Checked and installed"
echo "- Docker configuration: Verified/Updated"
echo "- Script permissions: Set"
echo "- Directories: Created"
echo "- Port conflicts: Checked"
echo "- Configuration: Verified"

echo -e "\n${BLUE}You can now run: ${GREEN}./start.sh${NC}"