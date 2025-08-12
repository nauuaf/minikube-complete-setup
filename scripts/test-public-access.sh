#!/bin/bash

# Test public access to services
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Testing Public Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Get public IP
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)
LOCAL_IP=$(hostname -I | awk '{print $1}')
MINIKUBE_IP=$(minikube ip)

echo -e "${YELLOW}IP Addresses:${NC}"
echo "  Public IP:   $PUBLIC_IP"
echo "  Local IP:    $LOCAL_IP"
echo "  Minikube IP: $MINIKUBE_IP"

# Check NodePort services
echo -e "\n${YELLOW}NodePort Services:${NC}"
kubectl get svc --all-namespaces | grep NodePort

# Test local access first
echo -e "\n${YELLOW}Testing Local Access (from Ubuntu machine):${NC}"
services=(
    "Frontend:30004:/"
    "Grafana:30030:/"
    "Prometheus:30090:/-/healthy"
    "Registry:30500:/v2/"
    "MinIO:30900:/minio/health/live"
)

for service_info in "${services[@]}"; do
    IFS=':' read -r name port path <<< "$service_info"
    printf "  %-15s " "$name ($port):"
    if curl -s --max-time 2 "http://localhost:$port$path" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Accessible${NC}"
    else
        echo -e "${RED}❌ Not accessible${NC}"
    fi
done

# Check firewall status
echo -e "\n${YELLOW}Firewall Status:${NC}"
if command -v ufw >/dev/null 2>&1; then
    sudo ufw status | grep -E "30000:32767|Status" || echo "  UFW not configured for NodePorts"
else
    echo "  UFW not installed"
fi

# Check if ports are listening
echo -e "\n${YELLOW}Listening Ports (NodePort range):${NC}"
sudo netstat -tlnp | grep -E ":300[0-9]{2}" | head -10 || sudo ss -tlnp | grep -E ":300[0-9]{2}" | head -10

# Security group reminder
echo -e "\n${YELLOW}AWS Security Group Requirements:${NC}"
echo "  Ensure your EC2 Security Group allows:"
echo "  - TCP ports 30000-32767 from 0.0.0.0/0"
echo "  - TCP port 80 (HTTP) from 0.0.0.0/0"
echo "  - TCP port 443 (HTTPS) from 0.0.0.0/0"

# Generate test commands
echo -e "\n${YELLOW}Test from External Machine:${NC}"
echo "  From your local computer, run:"
echo -e "${GREEN}  curl http://$PUBLIC_IP:30004${NC}     # Frontend"
echo -e "${GREEN}  curl http://$PUBLIC_IP:30030${NC}     # Grafana"
echo -e "${GREEN}  curl http://$PUBLIC_IP:30090${NC}     # Prometheus"

# HTTPS access via domain
echo -e "\n${YELLOW}HTTPS Access (if DNS configured):${NC}"
echo "  https://nawaf.thmanyah.com         # Main application"
echo "  Note: Requires DNS A record pointing to $PUBLIC_IP"

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Test Complete${NC}"
echo -e "${BLUE}========================================${NC}"