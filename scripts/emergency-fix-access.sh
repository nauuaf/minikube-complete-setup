#!/bin/bash

# Emergency fix for external access when port forwarding fails
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Emergency Fix for External Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Get IPs
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)
LOCAL_IP=$(hostname -I | awk '{print $1}')
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "Not running")

echo -e "${YELLOW}Network Information:${NC}"
echo "  Public IP:   $PUBLIC_IP"
echo "  Local IP:    $LOCAL_IP" 
echo "  Minikube IP: $MINIKUBE_IP"

# Stop any existing port forwards
echo -e "\n${YELLOW}Stopping existing port forwards...${NC}"
pkill -f "kubectl port-forward" 2>/dev/null || true
sudo systemctl stop sre-platform-forward 2>/dev/null || true
sleep 3

# Method 1: Direct kubectl port-forward (immediate solution)
echo -e "\n${YELLOW}Starting direct port forwarding...${NC}"

# Start port forwards in background, binding to all interfaces
echo "Starting HTTPS (443)..."
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /tmp/https.log 2>&1 &
HTTPS_PID=$!

echo "Starting HTTP (80)..."  
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /tmp/http.log 2>&1 &
HTTP_PID=$!

echo "Starting Frontend (30004)..."
kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:80 > /tmp/frontend.log 2>&1 &
FRONTEND_PID=$!

echo "Starting Grafana (30030)..."
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /tmp/grafana.log 2>&1 &
GRAFANA_PID=$!

echo "Starting Prometheus (30090)..."
kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /tmp/prometheus.log 2>&1 &
PROMETHEUS_PID=$!

# Wait for port forwards to establish
echo -e "\n${YELLOW}Waiting for port forwards to establish...${NC}"
sleep 5

# Verify ports are listening
echo -e "\n${BLUE}Port Status Check:${NC}"
for port in 80 443 30004 30030 30090; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        echo -e "  Port $port: ${GREEN}✅ Listening on all interfaces${NC}"
    else
        echo -e "  Port $port: ${RED}❌ Not accessible externally${NC}"
    fi
done

# Test local connectivity
echo -e "\n${BLUE}Local Connectivity Test:${NC}"
services=(
    "Frontend:30004"
    "Grafana:30030" 
    "Prometheus:30090"
)

for service_info in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service_info"
    printf "  %-12s " "$name:"
    if curl -s --max-time 3 "http://localhost:$port" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Working${NC}"
    else
        echo -e "${RED}❌ Failed${NC}"
    fi
done

# Method 2: Alternative using socat if kubectl port-forward fails
setup_socat_fallback() {
    echo -e "\n${YELLOW}Setting up socat fallback...${NC}"
    
    # Install socat if not present
    if ! command -v socat >/dev/null 2>&1; then
        echo "Installing socat..."
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install -y socat >/dev/null 2>&1
    fi
    
    # Kill existing socat processes
    sudo pkill socat 2>/dev/null || true
    sleep 2
    
    # Start socat forwarding
    echo "Starting socat port forwarding..."
    nohup sudo socat TCP-LISTEN:8080,fork,reuseaddr TCP:$MINIKUBE_IP:30004 > /tmp/socat-frontend.log 2>&1 &
    nohup sudo socat TCP-LISTEN:8030,fork,reuseaddr TCP:$MINIKUBE_IP:30030 > /tmp/socat-grafana.log 2>&1 &
    nohup sudo socat TCP-LISTEN:8090,fork,reuseaddr TCP:$MINIKUBE_IP:30090 > /tmp/socat-prometheus.log 2>&1 &
    
    echo -e "${GREEN}✅ Socat fallback configured${NC}"
    echo "  Alternative URLs:"
    echo "    Frontend: http://$PUBLIC_IP:8080"
    echo "    Grafana:  http://$PUBLIC_IP:8030" 
    echo "    Prometheus: http://$PUBLIC_IP:8090"
}

# Check if main method worked
sleep 3
working_ports=0
for port in 30004 30030 30090; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        ((working_ports++))
    fi
done

if [ $working_ports -lt 2 ]; then
    echo -e "\n${YELLOW}kubectl port-forward may not be working properly. Setting up socat fallback...${NC}"
    setup_socat_fallback
fi

# Configure firewall
echo -e "\n${YELLOW}Configuring firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow 80,443,8080,8030,8090,30004,30030,30090/tcp >/dev/null 2>&1
    echo -e "${GREEN}✅ UFW configured${NC}"
fi

# Final results
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   External Access Configured!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}🌐 Access from your macOS machine:${NC}"
echo -e "  Primary URLs:"
echo -e "    Frontend:   ${GREEN}http://$PUBLIC_IP:30004${NC}"
echo -e "    Grafana:    ${GREEN}http://$PUBLIC_IP:30030${NC}"
echo -e "    Prometheus: ${GREEN}http://$PUBLIC_IP:30090${NC}"

if command -v socat >/dev/null 2>&1; then
    echo -e "\n  Fallback URLs (if primary fails):"
    echo -e "    Frontend:   ${GREEN}http://$PUBLIC_IP:8080${NC}"
    echo -e "    Grafana:    ${GREEN}http://$PUBLIC_IP:8030${NC}" 
    echo -e "    Prometheus: ${GREEN}http://$PUBLIC_IP:8090${NC}"
fi

echo -e "\n  HTTPS (domain-based):"
echo -e "    Main App: ${GREEN}https://nawaf.thmanyah.com${NC}"
echo -e "    (Requires DNS: nawaf.thmanyah.com → $PUBLIC_IP)"

echo -e "\n${YELLOW}🧪 Test Commands (run from your macOS):${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP:30004${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP:30030${NC}"
echo -e "  ${GREEN}telnet $PUBLIC_IP 30004${NC}"

echo -e "\n${YELLOW}🔧 Process IDs (for manual cleanup):${NC}"
echo "  HTTPS: $HTTPS_PID"
echo "  HTTP: $HTTP_PID" 
echo "  Frontend: $FRONTEND_PID"
echo "  Grafana: $GRAFANA_PID"
echo "  Prometheus: $PROMETHEUS_PID"

echo -e "\n${BLUE}To stop manually: kill $HTTPS_PID $HTTP_PID $FRONTEND_PID $GRAFANA_PID $PROMETHEUS_PID${NC}"
echo -e "${BLUE}Or run: ./stop.sh${NC}"