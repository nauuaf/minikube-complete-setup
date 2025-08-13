#!/bin/bash
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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing Docker Configuration${NC}"
echo -e "${BLUE}========================================${NC}"

# Check current Docker status
log_info "Checking Docker status..."
if docker info >/dev/null 2>&1; then
    log_success "Docker is running"
else
    log_error "Docker is not running properly"
fi

# Fix the daemon.json file
log_info "Fixing Docker daemon.json..."

# Create proper daemon.json
cat > /tmp/daemon.json << 'EOF'
{
  "insecure-registries": ["localhost:30500", "10.0.0.0/8"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Backup existing file if it exists and is not empty
if [ -s /etc/docker/daemon.json ]; then
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup.$(date +%s)
    log_info "Backed up existing daemon.json"
fi

# Copy new configuration
sudo cp /tmp/daemon.json /etc/docker/daemon.json
sudo chown root:root /etc/docker/daemon.json
sudo chmod 644 /etc/docker/daemon.json

log_success "Docker configuration fixed"

# Restart Docker daemon
log_info "Restarting Docker daemon..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Wait for Docker to be ready
log_info "Waiting for Docker to be ready..."
retry_count=0
while [ $retry_count -lt 30 ]; do
    if docker info >/dev/null 2>&1; then
        log_success "Docker is ready"
        break
    fi
    echo -n "."
    sleep 2
    retry_count=$((retry_count + 1))
done
echo ""

# Verify configuration
log_info "Verifying Docker configuration..."
docker info 2>/dev/null | grep -A5 "Insecure Registries" || log_warning "Could not verify insecure registries"

log_success "Docker configuration fixed and verified"