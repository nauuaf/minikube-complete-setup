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
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Setting up Domain Access${NC}"
echo -e "${BLUE}   nawaf.thmanyah.com → Kubernetes${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
   log_warning "This script needs sudo privileges for port 80/443"
   exec sudo "$0" "$@"
fi

# Install socat if not present
if ! command -v socat &> /dev/null; then
    log_info "Installing socat..."
    apt-get update && apt-get install -y socat
fi

# Get Minikube IP
MINIKUBE_IP=$(sudo -u $SUDO_USER minikube ip 2>/dev/null || echo "")
if [ -z "$MINIKUBE_IP" ]; then
    log_error "Minikube is not running. Please run ./start.sh first"
    exit 1
fi

log_info "Minikube IP: $MINIKUBE_IP"

# Check current domain DNS
DOMAIN="nawaf.thmanyah.com"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)
DOMAIN_IP=$(dig +short $DOMAIN | head -1)

log_info "Public IP: $PUBLIC_IP"
log_info "Domain $DOMAIN points to: $DOMAIN_IP"

if [ "$DOMAIN_IP" != "$PUBLIC_IP" ]; then
    log_warning "Domain doesn't point to this server's IP yet"
    log_warning "Please update DNS A record for $DOMAIN to point to $PUBLIC_IP"
fi

# Stop any existing socat processes
log_info "Stopping existing socat processes..."
pkill -f "socat.*TCP-LISTEN:80" 2>/dev/null || true
pkill -f "socat.*TCP-LISTEN:443" 2>/dev/null || true
pkill -f "kubectl port-forward.*:80" 2>/dev/null || true
pkill -f "kubectl port-forward.*:443" 2>/dev/null || true
sleep 2

# Method 1: Direct socat to Minikube Ingress NodePort
log_info "Setting up direct socat forwarding to Ingress..."

# First, get the Ingress NodePort
INGRESS_HTTP_PORT=$(sudo -u $SUDO_USER kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "")
INGRESS_HTTPS_PORT=$(sudo -u $SUDO_USER kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || echo "")

if [ -z "$INGRESS_HTTP_PORT" ]; then
    log_warning "Ingress HTTP NodePort not found, using default 32080"
    INGRESS_HTTP_PORT=32080
fi

if [ -z "$INGRESS_HTTPS_PORT" ]; then
    log_warning "Ingress HTTPS NodePort not found, using default 32443"
    INGRESS_HTTPS_PORT=32443
fi

log_info "Ingress HTTP NodePort: $INGRESS_HTTP_PORT"
log_info "Ingress HTTPS NodePort: $INGRESS_HTTPS_PORT"

# Create systemd service for persistent forwarding
cat > /etc/systemd/system/domain-forward.service << EOF
[Unit]
Description=Domain Traffic Forwarding for nawaf.thmanyah.com
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=root

# HTTP forwarding (port 80 → Ingress HTTP NodePort)
ExecStart=/usr/bin/socat TCP-LISTEN:80,fork,reuseaddr TCP:${MINIKUBE_IP}:${INGRESS_HTTP_PORT}

[Install]
WantedBy=multi-user.target
EOF

# Create HTTPS forwarding service
cat > /etc/systemd/system/domain-forward-https.service << EOF
[Unit]
Description=Domain HTTPS Traffic Forwarding for nawaf.thmanyah.com
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=root

# HTTPS forwarding (port 443 → Ingress HTTPS NodePort)
ExecStart=/usr/bin/socat TCP-LISTEN:443,fork,reuseaddr TCP:${MINIKUBE_IP}:${INGRESS_HTTPS_PORT}

[Install]
WantedBy=multi-user.target
EOF

# Alternative: Create a combined service using a script
cat > /usr/local/bin/domain-forward.sh << EOF
#!/bin/bash
# Forward traffic from standard ports to Kubernetes Ingress

MINIKUBE_IP="${MINIKUBE_IP}"
INGRESS_HTTP_PORT="${INGRESS_HTTP_PORT}"
INGRESS_HTTPS_PORT="${INGRESS_HTTPS_PORT}"

echo "Starting domain forwarding..."
echo "HTTP: 0.0.0.0:80 → \${MINIKUBE_IP}:\${INGRESS_HTTP_PORT}"
echo "HTTPS: 0.0.0.0:443 → \${MINIKUBE_IP}:\${INGRESS_HTTPS_PORT}"

# Start both forwarders
socat TCP-LISTEN:80,fork,reuseaddr TCP:\${MINIKUBE_IP}:\${INGRESS_HTTP_PORT} &
HTTP_PID=\$!

socat TCP-LISTEN:443,fork,reuseaddr TCP:\${MINIKUBE_IP}:\${INGRESS_HTTPS_PORT} &
HTTPS_PID=\$!

# Wait for both processes
wait \$HTTP_PID \$HTTPS_PID
EOF

chmod +x /usr/local/bin/domain-forward.sh

# Create combined service
cat > /etc/systemd/system/domain-forward-combined.service << EOF
[Unit]
Description=Combined Domain Traffic Forwarding
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=root
ExecStart=/usr/local/bin/domain-forward.sh

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start services
log_info "Starting domain forwarding services..."
systemctl daemon-reload
systemctl stop domain-forward.service 2>/dev/null || true
systemctl stop domain-forward-https.service 2>/dev/null || true
systemctl stop domain-forward-combined.service 2>/dev/null || true

# Use combined service
systemctl enable domain-forward-combined.service
systemctl restart domain-forward-combined.service

# Give services time to start
sleep 3

# Check if services are running
if systemctl is-active --quiet domain-forward-combined.service; then
    log_success "Domain forwarding service is running"
else
    log_warning "Service may have issues, trying direct socat..."
    
    # Fallback to direct socat in background
    nohup socat TCP-LISTEN:80,fork,reuseaddr TCP:${MINIKUBE_IP}:${INGRESS_HTTP_PORT} > /tmp/socat-http.log 2>&1 &
    nohup socat TCP-LISTEN:443,fork,reuseaddr TCP:${MINIKUBE_IP}:${INGRESS_HTTPS_PORT} > /tmp/socat-https.log 2>&1 &
    log_info "Started socat processes in background"
fi

# Test the forwarding
log_info "Testing domain access..."
sleep 2

# Check if ports are listening
if netstat -tlnp | grep -q ":80.*LISTEN"; then
    log_success "Port 80 is listening"
else
    log_error "Port 80 is not listening"
fi

if netstat -tlnp | grep -q ":443.*LISTEN"; then
    log_success "Port 443 is listening"
else
    log_error "Port 443 is not listening"
fi

# Create iptables rules as backup (optional)
log_info "Adding iptables rules as backup..."
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${MINIKUBE_IP}:${INGRESS_HTTP_PORT} 2>/dev/null || true
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination ${MINIKUBE_IP}:${INGRESS_HTTPS_PORT} 2>/dev/null || true
iptables -t nat -A POSTROUTING -j MASQUERADE 2>/dev/null || true

# Save iptables rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
fi

echo ""
log_success "Domain forwarding setup complete!"
echo ""
echo -e "${GREEN}Access your application at:${NC}"
echo -e "  ${YELLOW}HTTP:${NC}  http://${DOMAIN}"
echo -e "  ${YELLOW}HTTPS:${NC} https://${DOMAIN}"
echo ""
echo -e "${YELLOW}Service Paths:${NC}"
echo "  Frontend:      http://${DOMAIN}/"
echo "  API Service:   http://${DOMAIN}/api"
echo "  Auth Service:  http://${DOMAIN}/auth"
echo "  Image Service: http://${DOMAIN}/image"
echo ""
echo -e "${YELLOW}Direct NodePort Access (backup):${NC}"
echo "  Frontend: http://${PUBLIC_IP}:30004"
echo "  Grafana:  http://${PUBLIC_IP}:30030"
echo ""
echo -e "${YELLOW}Service Status:${NC}"
systemctl status domain-forward-combined.service --no-pager | head -10
echo ""
echo -e "${YELLOW}To check logs:${NC}"
echo "  journalctl -u domain-forward-combined.service -f"
echo ""
echo -e "${YELLOW}To stop forwarding:${NC}"
echo "  sudo systemctl stop domain-forward-combined.service"