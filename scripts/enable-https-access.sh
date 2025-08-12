#!/bin/bash

# Enable HTTPS access on port 443 for nawaf.thmanyah.com
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Enabling HTTPS Access (Port 443)${NC}"
echo -e "${BLUE}========================================${NC}"

# Get network information
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)
MINIKUBE_IP=$(minikube ip)

echo -e "${YELLOW}Network Information:${NC}"
echo "  Public IP:  $PUBLIC_IP"
echo "  Minikube:   $MINIKUBE_IP"
echo "  Domain:     nawaf.thmanyah.com"

# Check ingress controller status
check_ingress_controller() {
    echo -e "\n${YELLOW}Checking NGINX Ingress Controller...${NC}"
    
    # Check if ingress controller is running
    if ! kubectl get pods -n ingress-nginx | grep -q "Running"; then
        echo -e "${RED}❌ Ingress controller not running properly${NC}"
        return 1
    fi
    
    # Get ingress controller service details
    echo -e "${GREEN}✅ Ingress controller is running${NC}"
    kubectl get svc -n ingress-nginx
    
    return 0
}

# Set up HTTPS port forwarding to the ingress controller
setup_https_forwarding() {
    echo -e "\n${YELLOW}Setting up HTTPS port forwarding...${NC}"
    
    # Kill existing forwards on ports 80 and 443
    sudo pkill -f "port-forward.*:80" 2>/dev/null || true
    sudo pkill -f "port-forward.*:443" 2>/dev/null || true
    sleep 2
    
    # Create script for HTTPS forwarding
    cat > /tmp/https-forward.sh << 'EOF'
#!/bin/bash

# Wait for ingress controller to be ready
while ! kubectl get pods -n ingress-nginx | grep -q "Running"; do
    echo "Waiting for ingress controller..."
    sleep 5
done

# Kill existing forwards
sudo pkill -f "port-forward.*:80" 2>/dev/null || true
sudo pkill -f "port-forward.*:443" 2>/dev/null || true
sleep 2

echo "Starting HTTPS port forwards..."

# Forward HTTP (port 80) to ingress controller
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /var/log/ingress-http.log 2>&1 &

# Forward HTTPS (port 443) to ingress controller  
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /var/log/ingress-https.log 2>&1 &

echo "HTTPS forwarding started"

# Monitor and restart if needed
while true; do
    sleep 30
    
    if ! pgrep -f "port-forward.*:80" > /dev/null; then
        echo "Restarting HTTP port-forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /var/log/ingress-http.log 2>&1 &
    fi
    
    if ! pgrep -f "port-forward.*:443" > /dev/null; then
        echo "Restarting HTTPS port-forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /var/log/ingress-https.log 2>&1 &
    fi
done
EOF

    # Make executable and install
    sudo cp /tmp/https-forward.sh /usr/local/bin/https-forward.sh
    sudo chmod +x /usr/local/bin/https-forward.sh
    
    # Create systemd service for HTTPS forwarding
    cat > /tmp/https-forward.service << EOF
[Unit]
Description=HTTPS Port Forwarding Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
Group=$USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/$USER"  
Environment="KUBECONFIG=/home/$USER/.kube/config"
ExecStart=/usr/local/bin/https-forward.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Install and start the service
    sudo cp /tmp/https-forward.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable https-forward.service
    sudo systemctl start https-forward.service
    
    echo -e "${GREEN}✅ HTTPS forwarding service started${NC}"
}

# Configure firewall for HTTPS
configure_https_firewall() {
    echo -e "\n${YELLOW}Configuring firewall for HTTPS...${NC}"
    
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow 80/tcp comment "HTTP"
        sudo ufw allow 443/tcp comment "HTTPS"
        echo -e "${GREEN}✅ Firewall configured for HTTPS${NC}"
    fi
}

# Test HTTPS access
test_https_access() {
    echo -e "\n${YELLOW}Testing HTTPS access...${NC}"
    
    # Wait for services to start
    sleep 10
    
    # Test local HTTP access
    echo -e "\n${BLUE}Testing local HTTP access:${NC}"
    if curl -s -H "Host: nawaf.thmanyah.com" --max-time 5 "http://localhost" >/dev/null 2>&1; then
        echo -e "  HTTP: ${GREEN}✅ Working${NC}"
    else
        echo -e "  HTTP: ${RED}❌ Failed${NC}"
    fi
    
    # Check if ports are listening
    echo -e "\n${BLUE}Port Status:${NC}"
    if netstat -tlnp 2>/dev/null | grep -q ":80.*0.0.0.0"; then
        echo -e "  Port 80:  ${GREEN}✅ Listening on all interfaces${NC}"
    else
        echo -e "  Port 80:  ${RED}❌ Not accessible${NC}"
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":443.*0.0.0.0"; then
        echo -e "  Port 443: ${GREEN}✅ Listening on all interfaces${NC}"
    else
        echo -e "  Port 443: ${RED}❌ Not accessible${NC}"
    fi
}

# Check TLS certificate status
check_certificate() {
    echo -e "\n${YELLOW}Checking TLS certificate status...${NC}"
    
    # Check certificate resource
    cert_status=$(kubectl get certificate sre-platform-tls -n production -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
    
    if [ "$cert_status" = "True" ]; then
        echo -e "${GREEN}✅ TLS certificate is ready${NC}"
    else
        echo -e "${YELLOW}⚠ TLS certificate not ready yet${NC}"
        echo "Certificate status:"
        kubectl describe certificate sre-platform-tls -n production | tail -10
    fi
}

# Main execution
if check_ingress_controller; then
    setup_https_forwarding
    configure_https_firewall  
    test_https_access
    check_certificate
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   HTTPS Access Configured!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    echo -e "\n${YELLOW}Access your application:${NC}"
    echo -e "  HTTP:  ${GREEN}http://nawaf.thmanyah.com${NC}"
    echo -e "  HTTPS: ${GREEN}https://nawaf.thmanyah.com${NC} (once cert is ready)"
    
    echo -e "\n${YELLOW}DNS Requirements:${NC}"
    echo -e "  Create A record: nawaf.thmanyah.com → $PUBLIC_IP"
    
    echo -e "\n${YELLOW}Test Commands:${NC}"
    echo -e "  ${GREEN}curl -v http://nawaf.thmanyah.com${NC}"
    echo -e "  ${GREEN}curl -v https://nawaf.thmanyah.com${NC}"
    echo -e "  ${GREEN}telnet $PUBLIC_IP 443${NC}"
    
    echo -e "\n${YELLOW}Service Management:${NC}"
    echo -e "  Status: ${GREEN}sudo systemctl status https-forward${NC}"
    echo -e "  Logs:   ${GREEN}sudo journalctl -u https-forward -f${NC}"
    
else
    echo -e "\n${RED}❌ Ingress controller issues detected. Please check your setup.${NC}"
    exit 1
fi