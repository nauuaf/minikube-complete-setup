#!/bin/bash
set -uo pipefail

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
echo -e "${BLUE}   Fixing DNS Issues${NC}"
echo -e "${BLUE}========================================${NC}"

# Check current DNS configuration
log_info "Checking current DNS configuration..."
echo "Current DNS servers:"
cat /etc/resolv.conf

# Test DNS resolution
log_info "Testing DNS resolution..."
if nslookup google.com >/dev/null 2>&1; then
    log_success "DNS is working for google.com"
else
    log_error "DNS resolution failed for google.com"
fi

if nslookup github.com >/dev/null 2>&1; then
    log_success "DNS is working for github.com"
else
    log_error "DNS resolution failed for github.com"
fi

if nslookup registry-1.docker.io >/dev/null 2>&1; then
    log_success "DNS is working for registry-1.docker.io"
else
    log_error "DNS resolution failed for registry-1.docker.io"
fi

# Fix 1: Update systemd-resolved configuration
log_info "Configuring systemd-resolved with reliable DNS servers..."

# Create resolved configuration
sudo tee /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=8.8.8.8 1.1.1.1 8.8.4.4
FallbackDNS=1.0.0.1 9.9.9.9
Domains=~.
DNSSEC=no
DNSOverTLS=no
Cache=yes
DNSStubListener=yes
ReadEtcHosts=yes
EOF

# Restart systemd-resolved
log_info "Restarting systemd-resolved..."
sudo systemctl restart systemd-resolved
sleep 2

# Fix 2: Update Docker daemon DNS
log_info "Configuring Docker daemon DNS..."

# Update Docker daemon.json with DNS
sudo tee /etc/docker/daemon.json << EOF
{
  "insecure-registries": ["localhost:30500", "10.0.0.0/8"],
  "dns": ["8.8.8.8", "1.1.1.1"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Restart Docker
log_info "Restarting Docker daemon..."
sudo systemctl restart docker
sleep 5

# Fix 3: Configure Minikube DNS
log_info "Configuring Minikube DNS..."

# Check if Minikube is running
if minikube status >/dev/null 2>&1; then
    log_info "Configuring DNS in running Minikube..."
    
    # Update CoreDNS in Minikube
    kubectl get configmap coredns -n kube-system -o yaml > /tmp/coredns-backup.yaml
    
    # Create updated CoreDNS config
    cat > /tmp/coredns-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 8.8.8.8 1.1.1.1
        cache 30
        loop
        reload
        loadbalance
    }
EOF
    
    kubectl apply -f /tmp/coredns-config.yaml
    kubectl rollout restart deployment/coredns -n kube-system
fi

# Fix 4: Verify DNS resolution
log_info "Waiting for DNS changes to take effect..."
sleep 10

log_info "Testing DNS resolution after fixes..."
test_domains=("google.com" "github.com" "registry-1.docker.io" "docker.io")
all_working=true

for domain in "${test_domains[@]}"; do
    if timeout 10 nslookup "$domain" >/dev/null 2>&1; then
        log_success "DNS working for $domain"
    else
        log_warning "DNS still failing for $domain"
        all_working=false
    fi
done

if [ "$all_working" = true ]; then
    log_success "All DNS resolution working!"
else
    log_warning "Some DNS issues remain, trying alternative approach..."
    
    # Alternative: Use alternative DNS temporarily
    log_info "Setting up alternative DNS as backup..."
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf.backup
    echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf.backup
    
    # Test with backup DNS
    if dig @8.8.8.8 github.com >/dev/null 2>&1; then
        log_success "Alternative DNS working"
    fi
fi

# Fix 5: Configure Docker to use specific registry mirrors (as fallback)
log_info "Adding Docker registry mirrors as fallback..."

sudo tee /etc/docker/daemon.json << EOF
{
  "insecure-registries": ["localhost:30500", "10.0.0.0/8"],
  "dns": ["8.8.8.8", "1.1.1.1", "8.8.4.4"],
  "registry-mirrors": [
    "https://mirror.gcr.io",
    "https://docker.mirrors.ustc.edu.cn"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
sleep 3

# Test Docker functionality
log_info "Testing Docker image pull..."
if timeout 30 docker pull hello-world >/dev/null 2>&1; then
    log_success "Docker image pull working"
    docker rmi hello-world >/dev/null 2>&1 || true
else
    log_warning "Docker image pull still having issues"
fi

echo ""
log_success "DNS fix attempts completed"
echo ""
echo -e "${YELLOW}Current DNS status:${NC}"
echo "Resolved config: /etc/systemd/resolved.conf updated"
echo "Docker config: /etc/docker/daemon.json updated"
if minikube status >/dev/null 2>&1; then
    echo "Minikube CoreDNS: Updated"
fi

echo ""
echo -e "${YELLOW}Troubleshooting commands:${NC}"
echo "Check DNS: nslookup github.com"
echo "Check Docker: docker pull alpine:latest"
echo "Check systemd-resolved: systemctl status systemd-resolved"