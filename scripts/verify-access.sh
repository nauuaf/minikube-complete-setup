#!/bin/bash

# Verify external access is working properly
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Verifying External Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Get network information
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)
echo -e "${YELLOW}Your Ubuntu Public IP: $PUBLIC_IP${NC}"

# Check systemd service status
echo -e "\n${YELLOW}Port Forwarding Service Status:${NC}"
if systemctl is-active --quiet sre-platform-forward; then
    echo -e "  sre-platform-forward: ${GREEN}✅ Running${NC}"
else
    echo -e "  sre-platform-forward: ${RED}❌ Not running${NC}"
    echo -e "  ${YELLOW}Restarting service...${NC}"
    sudo systemctl restart sre-platform-forward
    sleep 5
fi

# Check if ports are listening on all interfaces
echo -e "\n${BLUE}Port Status Check:${NC}"
required_ports=(80 443 30004 30030 30090)

for port in "${required_ports[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        echo -e "  Port $port: ${GREEN}✅ Accessible externally${NC}"
    else
        echo -e "  Port $port: ${RED}❌ Not accessible${NC}"
    fi
done

# Test local connectivity to services
echo -e "\n${BLUE}Local Service Connectivity:${NC}"
services=(
    "Frontend:30004"
    "Grafana:30030"
    "Prometheus:30090"
)

for service_info in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service_info"
    printf "  %-12s " "$name:"
    if timeout 5 curl -s "http://localhost:$port" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Responding${NC}"
    else
        echo -e "${RED}❌ Not responding${NC}"
    fi
done

# Check Kubernetes services
echo -e "\n${BLUE}Kubernetes Service Status:${NC}"
kubectl get pods -n production --no-headers | while read line; do
    pod_name=$(echo $line | awk '{print $1}')
    pod_status=$(echo $line | awk '{print $3}')
    if [[ "$pod_status" == "Running" ]]; then
        echo -e "  $pod_name: ${GREEN}✅ Running${NC}"
    else
        echo -e "  $pod_name: ${RED}❌ $pod_status${NC}"
    fi
done

# Check ingress controller
echo -e "\n${BLUE}Ingress Controller Status:${NC}"
if kubectl get pods -n ingress-nginx | grep -q "Running"; then
    echo -e "  Ingress Controller: ${GREEN}✅ Running${NC}"
else
    echo -e "  Ingress Controller: ${RED}❌ Not running${NC}"
fi

# Check TLS certificate
echo -e "\n${BLUE}TLS Certificate Status:${NC}"
cert_status=$(kubectl get certificate sre-platform-tls -n production -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
if [ "$cert_status" = "True" ]; then
    echo -e "  Certificate: ${GREEN}✅ Ready${NC}"
elif [ "$cert_status" = "NotFound" ]; then
    echo -e "  Certificate: ${YELLOW}⚠ Not found${NC}"
else
    echo -e "  Certificate: ${YELLOW}⚠ Pending${NC} (Let's Encrypt needs DNS configuration)"
fi

# Provide access information
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Access Information${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}🌐 From your macOS machine:${NC}"
echo -e "  Frontend:   ${GREEN}http://$PUBLIC_IP:30004${NC}"
echo -e "  Grafana:    ${GREEN}http://$PUBLIC_IP:30030${NC} (admin / admin123)"
echo -e "  Prometheus: ${GREEN}http://$PUBLIC_IP:30090${NC}"

echo -e "\n${YELLOW}🔗 Domain-based HTTPS:${NC}"
echo -e "  Main App: ${GREEN}https://nawaf.thmanyah.com${NC}"
echo -e "  (Requires DNS: nawaf.thmanyah.com → $PUBLIC_IP)"

echo -e "\n${YELLOW}🧪 Test Commands (from macOS):${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP:30004${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP:30030${NC}"
echo -e "  ${GREEN}telnet $PUBLIC_IP 30004${NC}"
echo -e "  ${GREEN}open http://$PUBLIC_IP:30030${NC}  # Grafana"

echo -e "\n${YELLOW}🔧 Troubleshooting:${NC}"
echo -e "  Service status: ${GREEN}sudo systemctl status sre-platform-forward${NC}"
echo -e "  Service logs:   ${GREEN}sudo journalctl -u sre-platform-forward -f${NC}"
echo -e "  Manual restart: ${GREEN}sudo systemctl restart sre-platform-forward${NC}"
echo -e "  Check logs:     ${GREEN}ls -la /tmp/sre-logs/${NC}"

# Final summary
working_ports=0
for port in "${required_ports[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        ((working_ports++))
    fi
done

echo -e "\n${BLUE}========================================${NC}"
if [ $working_ports -ge 3 ]; then
    echo -e "${GREEN}✅ External access is working! ($working_ports/5 ports accessible)${NC}"
    echo -e "${GREEN}You should be able to access services from your macOS machine.${NC}"
else
    echo -e "${RED}❌ External access needs attention ($working_ports/5 ports accessible)${NC}"
    echo -e "${YELLOW}Try: sudo systemctl restart sre-platform-forward${NC}"
fi
echo -e "${BLUE}========================================${NC}"