#!/bin/bash

# Expose Minikube services to public access
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Exposing Services for Public Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Method 1: Using kubectl port-forward (Most Reliable)
expose_with_port_forward() {
    echo -e "\n${YELLOW}Starting port forwarding for public access...${NC}"
    echo -e "${YELLOW}This will bind services to 0.0.0.0 (all interfaces)${NC}"
    
    # Kill any existing port-forwards
    pkill -f "kubectl port-forward" 2>/dev/null || true
    sleep 2
    
    # Start port-forward for each service (binding to all interfaces)
    echo -e "\n${GREEN}Starting Frontend (30004)...${NC}"
    kubectl port-forward --address 0.0.0.0 -n $NAMESPACE_PROD svc/frontend 30004:80 > /tmp/frontend-pf.log 2>&1 &
    echo "  PID: $!"
    
    echo -e "${GREEN}Starting Grafana (30030)...${NC}"
    kubectl port-forward --address 0.0.0.0 -n $NAMESPACE_MONITORING svc/grafana 30030:3000 > /tmp/grafana-pf.log 2>&1 &
    echo "  PID: $!"
    
    echo -e "${GREEN}Starting Prometheus (30090)...${NC}"
    kubectl port-forward --address 0.0.0.0 -n $NAMESPACE_MONITORING svc/prometheus 30090:9090 > /tmp/prometheus-pf.log 2>&1 &
    echo "  PID: $!"
    
    echo -e "${GREEN}Starting Registry UI (30501)...${NC}"
    kubectl port-forward --address 0.0.0.0 -n default svc/registry-ui 30501:80 > /tmp/registry-ui-pf.log 2>&1 &
    echo "  PID: $!"
    
    echo -e "${GREEN}Starting MinIO Console (30901)...${NC}"
    kubectl port-forward --address 0.0.0.0 -n $NAMESPACE_PROD svc/minio-nodeport 30901:9001 > /tmp/minio-pf.log 2>&1 &
    echo "  PID: $!"
    
    sleep 5
    
    # Verify ports are listening
    echo -e "\n${YELLOW}Verifying exposed ports:${NC}"
    netstat -tlnp 2>/dev/null | grep -E "30004|30030|30090|30501|30901" | grep "0.0.0.0" || \
    ss -tlnp | grep -E "30004|30030|30090|30501|30901" | grep "0.0.0.0"
}

# Method 2: Using Minikube tunnel (Alternative)
expose_with_tunnel() {
    echo -e "\n${YELLOW}Starting Minikube tunnel...${NC}"
    echo -e "${YELLOW}Note: This requires keeping the terminal open${NC}"
    
    # Start tunnel in background
    sudo minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &
    TUNNEL_PID=$!
    echo "Tunnel PID: $TUNNEL_PID"
    
    sleep 5
    
    # Check tunnel status
    if ps -p $TUNNEL_PID > /dev/null; then
        echo -e "${GREEN}✅ Minikube tunnel is running${NC}"
    else
        echo -e "${RED}❌ Minikube tunnel failed to start${NC}"
        cat /tmp/minikube-tunnel.log
    fi
}

# Method 3: Using socat for port forwarding (if installed)
expose_with_socat() {
    if ! command -v socat >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing socat...${NC}"
        sudo apt-get update && sudo apt-get install -y socat
    fi
    
    echo -e "\n${YELLOW}Starting socat port forwarding...${NC}"
    
    MINIKUBE_IP=$(minikube ip)
    
    # Forward ports using socat
    sudo socat TCP-LISTEN:30004,fork,reuseaddr TCP:$MINIKUBE_IP:30004 &
    sudo socat TCP-LISTEN:30030,fork,reuseaddr TCP:$MINIKUBE_IP:30030 &
    sudo socat TCP-LISTEN:30090,fork,reuseaddr TCP:$MINIKUBE_IP:30090 &
    
    echo -e "${GREEN}✅ Socat forwarding started${NC}"
}

# Main execution
echo -e "\n${BLUE}Choose exposure method:${NC}"
echo "1) kubectl port-forward (Recommended)"
echo "2) Minikube tunnel"
echo "3) socat forwarding"
echo "4) All methods"

read -p "Enter choice (1-4): " choice

case $choice in
    1)
        expose_with_port_forward
        ;;
    2)
        expose_with_tunnel
        ;;
    3)
        expose_with_socat
        ;;
    4)
        expose_with_port_forward
        expose_with_tunnel
        ;;
    *)
        echo "Using default: kubectl port-forward"
        expose_with_port_forward
        ;;
esac

# Get public IP
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Services Exposed Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Access your services from anywhere:${NC}"
echo "  Frontend:    http://$PUBLIC_IP:30004"
echo "  Grafana:     http://$PUBLIC_IP:30030"
echo "  Prometheus:  http://$PUBLIC_IP:30090"
echo "  Registry UI: http://$PUBLIC_IP:30501"
echo "  MinIO:       http://$PUBLIC_IP:30901"

echo -e "\n${YELLOW}Important Notes:${NC}"
echo "  1. Keep this script running to maintain access"
echo "  2. Ensure AWS Security Group allows ports 30000-32767"
echo "  3. Use 'ps aux | grep port-forward' to see running forwards"
echo "  4. Run 'pkill -f port-forward' to stop all forwards"

echo -e "\n${BLUE}Press Ctrl+C to stop port forwarding${NC}"

# Keep script running
while true; do
    sleep 60
    echo -n "."
done