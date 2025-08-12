#!/bin/bash

# Setup permanent public access to services
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Setting Up Permanent Public Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Create service script
cat > /tmp/minikube-expose.sh << 'EOF'
#!/bin/bash

# Wait for Minikube to be ready
while ! minikube status | grep -q "Running"; do
    echo "Waiting for Minikube to start..."
    sleep 10
done

# Wait for kubectl to be ready
while ! kubectl get nodes >/dev/null 2>&1; do
    echo "Waiting for kubectl to be ready..."
    sleep 5
done

echo "Starting port forwards..."

# Kill any existing port-forwards
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Start port forwards (binding to all interfaces)
kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:80 > /var/log/frontend-pf.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /var/log/grafana-pf.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /var/log/prometheus-pf.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n default svc/registry-ui 30501:80 > /var/log/registry-ui-pf.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n production svc/minio-nodeport 30901:9001 > /var/log/minio-pf.log 2>&1 &

echo "Port forwards started"

# Keep running
while true; do
    sleep 60
    # Check if port-forwards are still running, restart if needed
    if ! pgrep -f "port-forward.*30004" > /dev/null; then
        echo "Restarting frontend port-forward..."
        kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:80 > /var/log/frontend-pf.log 2>&1 &
    fi
    if ! pgrep -f "port-forward.*30030" > /dev/null; then
        echo "Restarting grafana port-forward..."
        kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /var/log/grafana-pf.log 2>&1 &
    fi
done
EOF

# Make script executable
sudo cp /tmp/minikube-expose.sh /usr/local/bin/minikube-expose.sh
sudo chmod +x /usr/local/bin/minikube-expose.sh

# Create systemd service
cat > /tmp/minikube-expose.service << EOF
[Unit]
Description=Minikube Service Exposer
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/$USER"
Environment="KUBECONFIG=/home/$USER/.kube/config"
ExecStart=/usr/local/bin/minikube-expose.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Install systemd service
sudo cp /tmp/minikube-expose.service /etc/systemd/system/
sudo systemctl daemon-reload

echo -e "\n${YELLOW}Starting the service...${NC}"
sudo systemctl enable minikube-expose.service
sudo systemctl start minikube-expose.service

sleep 5

# Check service status
echo -e "\n${YELLOW}Service Status:${NC}"
sudo systemctl status minikube-expose.service --no-pager

# Verify ports
echo -e "\n${YELLOW}Checking exposed ports:${NC}"
sleep 5
netstat -tlnp 2>/dev/null | grep -E "30004|30030|30090" | grep "0.0.0.0" || echo "Ports may take a moment to bind..."

# Get public IP
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Permanent Access Configured!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Your services are now accessible at:${NC}"
echo "  Frontend:    http://$PUBLIC_IP:30004"
echo "  Grafana:     http://$PUBLIC_IP:30030"
echo "  Prometheus:  http://$PUBLIC_IP:30090"
echo "  Registry UI: http://$PUBLIC_IP:30501"
echo "  MinIO:       http://$PUBLIC_IP:30901"

echo -e "\n${YELLOW}Service Management:${NC}"
echo "  Check status:  sudo systemctl status minikube-expose"
echo "  View logs:     sudo journalctl -u minikube-expose -f"
echo "  Restart:       sudo systemctl restart minikube-expose"
echo "  Stop:          sudo systemctl stop minikube-expose"

echo -e "\n${YELLOW}Note:${NC} Ensure AWS Security Group allows TCP 30000-32767"