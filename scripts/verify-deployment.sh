#!/bin/bash

# Comprehensive deployment verification script
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Comprehensive Deployment Verification${NC}"
echo -e "${BLUE}========================================${NC}"

# Track overall status
total_checks=0
failed_checks=0

check_status() {
    local name=$1
    local success=$2
    
    ((total_checks++))
    if [ "$success" -eq 0 ]; then
        echo -e "  ${GREEN}✅ $name${NC}"
    else
        echo -e "  ${RED}❌ $name${NC}"
        ((failed_checks++))
    fi
}

# 1. Check cluster status
echo -e "\n${YELLOW}🔍 1. Cluster Status Check${NC}"
minikube status >/dev/null 2>&1
check_status "Minikube cluster running" $?

kubectl cluster-info >/dev/null 2>&1
check_status "Kubectl connectivity" $?

# 2. Check namespaces
echo -e "\n${YELLOW}🔍 2. Namespace Check${NC}"
kubectl get namespace production >/dev/null 2>&1
check_status "Production namespace exists" $?

kubectl get namespace monitoring >/dev/null 2>&1
check_status "Monitoring namespace exists" $?

# 3. Check registry
echo -e "\n${YELLOW}🔍 3. Registry Check${NC}"
kubectl get pods -l app=docker-registry --no-headers | grep -q "Running"
check_status "Registry pod running" $?

# Test registry connectivity
if curl -s -u admin:admin123 http://localhost:30500/v2/ >/dev/null 2>&1; then
    check_status "Registry accessible from host" 0
else
    # Try with port-forward if direct access fails
    kubectl port-forward --address=127.0.0.1 svc/docker-registry 30500:5000 -n default >/dev/null 2>&1 &
    PF_PID=$!
    sleep 3
    if curl -s -u admin:admin123 http://localhost:30500/v2/ >/dev/null 2>&1; then
        check_status "Registry accessible via port-forward" 0
    else
        check_status "Registry accessible" 1
    fi
    kill $PF_PID 2>/dev/null || true
fi

# 4. Check application pods
echo -e "\n${YELLOW}🔍 4. Application Pods Check${NC}"
services=("api-service" "auth-service" "image-service" "frontend")

for service in "${services[@]}"; do
    running_pods=$(kubectl get pods -n production -l app=$service --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$running_pods" -gt 0 ]; then
        check_status "$service pods running ($running_pods)" 0
    else
        check_status "$service pods running" 1
    fi
done

# 5. Check monitoring pods
echo -e "\n${YELLOW}🔍 5. Monitoring Pods Check${NC}"
monitoring_services=("prometheus" "grafana" "alertmanager")

for service in "${monitoring_services[@]}"; do
    running_pods=$(kubectl get pods -n monitoring -l app=$service --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$running_pods" -gt 0 ]; then
        check_status "$service pods running ($running_pods)" 0
    else
        check_status "$service pods running" 1
    fi
done

# 6. Check ingress controller
echo -e "\n${YELLOW}🔍 6. Ingress Controller Check${NC}"
kubectl get pods -n ingress-nginx | grep -q "Running.*1/1"
check_status "Ingress controller ready" $?

# 7. Check port forwards
echo -e "\n${YELLOW}🔍 7. Port Forwarding Check${NC}"
critical_ports=(80 443 30004 30030 30090)

for port in "${critical_ports[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        check_status "Port $port accessible externally" 0
    else
        check_status "Port $port accessible externally" 1
    fi
done

# 8. Check systemd service
echo -e "\n${YELLOW}🔍 8. Port Forwarding Service Check${NC}"
if systemctl is-active --quiet sre-platform-forward 2>/dev/null; then
    check_status "Port forwarding service running" 0
else
    check_status "Port forwarding service running" 1
fi

# 9. Run health checks
echo -e "\n${YELLOW}🔍 9. Application Health Checks${NC}"
./scripts/health-checks.sh >/tmp/health-check-result.log 2>&1
health_exit_code=$?
if [ $health_exit_code -eq 0 ]; then
    check_status "All health checks passed" 0
else
    check_status "Health checks ($health_exit_code services failed)" 1
fi

# 10. Test external access
echo -e "\n${YELLOW}🔍 10. External Access Test${NC}"
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || echo "unknown")

# Test frontend access
if timeout 10 curl -s http://localhost:30004 >/dev/null 2>&1; then
    check_status "Frontend accessible on port 30004" 0
else
    check_status "Frontend accessible on port 30004" 1
fi

# Test HTTP access
if timeout 10 curl -s -H "Host: nawaf.thmanyah.com" http://localhost >/dev/null 2>&1; then
    check_status "HTTP ingress accessible" 0
else
    check_status "HTTP ingress accessible" 1
fi

# Final summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Deployment Status Summary${NC}"
echo -e "${BLUE}========================================${NC}"

if [ $failed_checks -eq 0 ]; then
    echo -e "\n${GREEN}🎉 SUCCESS! All checks passed ($total_checks/$total_checks)${NC}"
    echo -e "${GREEN}The SRE platform is fully operational!${NC}"
    
    echo -e "\n${YELLOW}📋 Access Information:${NC}"
    echo -e "  Frontend: http://$PUBLIC_IP:30004"
    echo -e "  Grafana: http://$PUBLIC_IP:30030 (admin/admin123)"
    echo -e "  Prometheus: http://$PUBLIC_IP:30090"
    echo -e "  HTTPS: https://nawaf.thmanyah.com (requires DNS)"
    
    exit 0
else
    echo -e "\n${RED}❌ ISSUES DETECTED: $failed_checks/$total_checks checks failed${NC}"
    echo -e "${YELLOW}🔧 Recommended actions:${NC}"
    
    if [ $health_exit_code -ne 0 ]; then
        echo -e "  1. Check health check details: cat /tmp/health-check-result.log"
        echo -e "  2. Restart failed pods: kubectl delete pods -l app=<service> -n production"
    fi
    
    if ! systemctl is-active --quiet sre-platform-forward 2>/dev/null; then
        echo -e "  3. Restart port forwarding: sudo systemctl restart sre-platform-forward"
    fi
    
    echo -e "  4. Check service logs: kubectl logs -l app=<service> -n production"
    echo -e "  5. Re-run deployment: ./start.sh"
    
    exit $failed_checks
fi