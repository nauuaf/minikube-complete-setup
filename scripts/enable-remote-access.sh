#!/bin/bash

# Enable remote access from external machines (like macOS to Ubuntu)
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Enabling Remote Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Get public IP
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || hostname -I | awk '{print $1}')
LOCAL_IP=$(hostname -I | awk '{print $1}')

echo -e "${YELLOW}Network Information:${NC}"
echo "  Public IP:  $PUBLIC_IP"
echo "  Local IP:   $LOCAL_IP"
echo "  Minikube:   $(minikube ip 2>/dev/null || echo 'Not accessible')"

# Method 1: Using kubectl port-forward with proper binding
setup_port_forwarding() {
    echo -e "\n${YELLOW}Setting up port forwarding for remote access...${NC}"
    
    # Kill existing port-forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
    
    # Create systemd service for persistent port forwarding
    cat > /tmp/minikube-remote-access.sh << 'EOF'
#!/bin/bash

# Wait for Minikube and kubectl to be ready
while ! kubectl get nodes >/dev/null 2>&1; do
    sleep 5
done

# Kill any existing port-forwards
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

echo "Starting remote access port forwards..."

# Frontend (main application)
kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:80 > /var/log/frontend-remote.log 2>&1 &
sleep 1

# Monitoring
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /var/log/grafana-remote.log 2>&1 &
sleep 1
kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /var/log/prometheus-remote.log 2>&1 &
sleep 1

# Registry and storage
kubectl port-forward --address 0.0.0.0 -n default svc/registry-ui 30501:80 > /var/log/registry-remote.log 2>&1 &
sleep 1
kubectl port-forward --address 0.0.0.0 -n production svc/minio-nodeport 30900:9000 > /var/log/minio-api-remote.log 2>&1 &
sleep 1
kubectl port-forward --address 0.0.0.0 -n production svc/minio-nodeport 30901:9001 > /var/log/minio-console-remote.log 2>&1 &

echo "Remote access port forwards started"

# Keep running and restart failed forwards
while true; do
    sleep 30
    
    # Check and restart if needed
    if ! pgrep -f "port-forward.*30004" > /dev/null; then
        echo "Restarting frontend port-forward..."
        kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:80 > /var/log/frontend-remote.log 2>&1 &
    fi
    if ! pgrep -f "port-forward.*30030" > /dev/null; then
        echo "Restarting Grafana port-forward..."
        kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /var/log/grafana-remote.log 2>&1 &
    fi
    if ! pgrep -f "port-forward.*30090" > /dev/null; then
        echo "Restarting Prometheus port-forward..."
        kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /var/log/prometheus-remote.log 2>&1 &
    fi
done
EOF

    # Make executable and install
    sudo cp /tmp/minikube-remote-access.sh /usr/local/bin/minikube-remote-access.sh
    sudo chmod +x /usr/local/bin/minikube-remote-access.sh

    # Create systemd service
    cat > /tmp/minikube-remote-access.service << EOF
[Unit]
Description=Minikube Remote Access Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
Group=$USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/$USER"
Environment="KUBECONFIG=/home/$USER/.kube/config"
ExecStart=/usr/local/bin/minikube-remote-access.sh
Restart=always
RestartSec=10
KillMode=mixed
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

    # Install and start service
    sudo cp /tmp/minikube-remote-access.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable minikube-remote-access.service
    sudo systemctl start minikube-remote-access.service
    
    echo -e "${GREEN}✅ Remote access service installed and started${NC}"
}

# Method 2: Configure firewall and security
configure_firewall() {
    echo -e "\n${YELLOW}Configuring firewall for remote access...${NC}"
    
    # Check if ufw is available
    if command -v ufw >/dev/null 2>&1; then
        # Enable UFW if not active
        if ! sudo ufw status | grep -q "Status: active"; then
            echo "y" | sudo ufw enable
        fi
        
        # Allow NodePort range
        sudo ufw allow 30000:32767/tcp comment "Kubernetes NodePorts"
        sudo ufw allow 22/tcp comment "SSH"
        sudo ufw allow 80/tcp comment "HTTP"
        sudo ufw allow 443/tcp comment "HTTPS"
        
        # Show status
        sudo ufw status numbered
        echo -e "${GREEN}✅ UFW configured for remote access${NC}"
    else
        echo -e "${YELLOW}⚠ UFW not available, checking iptables...${NC}"
        # For systems without UFW, ensure iptables allows the ports
        sudo iptables -I INPUT -p tcp --dport 30000:32767 -j ACCEPT 2>/dev/null || true
    fi
}

# Method 3: Test connectivity
test_remote_access() {
    echo -e "\n${YELLOW}Testing remote access...${NC}"
    
    # Wait for services to start
    sleep 10
    
    # Test local access first
    services=(
        "Frontend:30004"
        "Grafana:30030"
        "Prometheus:30090"
        "Registry:30501"
    )
    
    echo -e "\n${BLUE}Local Access Tests:${NC}"
    for service_info in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service_info"
        printf "  %-12s " "$name:"
        if curl -s --max-time 3 "http://localhost:$port" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Working${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    done
    
    # Check if ports are listening on all interfaces
    echo -e "\n${BLUE}Port Binding Status:${NC}"
    netstat -tlnp 2>/dev/null | grep -E ":(30004|30030|30090|30501)" | while read line; do
        if echo "$line" | grep -q "0.0.0.0"; then
            port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
            echo -e "  Port $port: ${GREEN}✅ Accessible remotely${NC}"
        else
            port=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
            echo -e "  Port $port: ${YELLOW}⚠ Local only${NC}"
        fi
    done
}

# Main execution
echo -e "\n${BLUE}Enabling remote access from macOS to Ubuntu...${NC}"

# Run all setup methods
setup_port_forwarding
configure_firewall
test_remote_access

# Final instructions
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Remote Access Configured!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}From your macOS machine, you can now access:${NC}"
echo -e "  Frontend:    ${GREEN}http://$PUBLIC_IP:30004${NC}"
echo -e "  Grafana:     ${GREEN}http://$PUBLIC_IP:30030${NC} (admin / admin123)"
echo -e "  Prometheus:  ${GREEN}http://$PUBLIC_IP:30090${NC}"
echo -e "  Registry UI: ${GREEN}http://$PUBLIC_IP:30501${NC}"
echo -e "  MinIO Console: ${GREEN}http://$PUBLIC_IP:30901${NC}"

echo -e "\n${YELLOW}AWS Security Group Requirements:${NC}"
echo -e "  Ensure your EC2 Security Group allows:"
echo -e "  • TCP ports 30000-32767 from 0.0.0.0/0"
echo -e "  • TCP port 80 from 0.0.0.0/0"
echo -e "  • TCP port 443 from 0.0.0.0/0"

echo -e "\n${YELLOW}Service Management:${NC}"
echo -e "  Status: ${GREEN}sudo systemctl status minikube-remote-access${NC}"
echo -e "  Logs:   ${GREEN}sudo journalctl -u minikube-remote-access -f${NC}"
echo -e "  Stop:   ${GREEN}sudo systemctl stop minikube-remote-access${NC}"

echo -e "\n${BLUE}Test from macOS:${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP:30004${NC}"
echo -e "  ${GREEN}open http://$PUBLIC_IP:30030${NC}  # Grafana"