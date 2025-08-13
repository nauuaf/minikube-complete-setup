#!/bin/bash
set -euo pipefail

source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get IPs
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || echo "unknown")
MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "minikube not running")

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Testing Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Public IP: $PUBLIC_IP"
echo "Minikube IP: $MINIKUBE_IP"
echo ""

# Test 1: Check Minikube status
echo -e "${YELLOW}Test 1: Minikube Status${NC}"
if minikube status >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Minikube is running${NC}"
    minikube status
else
    echo -e "${RED}❌ Minikube is not running${NC}"
    echo "Run: ./start.sh"
    exit 1
fi
echo ""

# Test 2: Check namespaces
echo -e "${YELLOW}Test 2: Kubernetes Namespaces${NC}"
namespaces=("default" "production" "monitoring")
for ns in "${namespaces[@]}"; do
    if kubectl get namespace $ns >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Namespace '$ns' exists${NC}"
    else
        echo -e "${RED}❌ Namespace '$ns' missing${NC}"
    fi
done
echo ""

# Test 3: Check registry
echo -e "${YELLOW}Test 3: Docker Registry${NC}"
if kubectl get pod -l app=docker-registry -n default --no-headers 2>/dev/null | grep -q Running; then
    echo -e "${GREEN}✅ Registry is running${NC}"
    
    # Test registry access
    if curl -s -u admin:SecurePass123! http://$MINIKUBE_IP:30500/v2/_catalog >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Registry is accessible via NodePort${NC}"
    else
        echo -e "${YELLOW}⚠️  Registry NodePort not accessible, checking...${NC}"
        kubectl get svc docker-registry -n default
    fi
else
    echo -e "${RED}❌ Registry is not running${NC}"
fi
echo ""

# Test 4: Check application services
echo -e "${YELLOW}Test 4: Application Services${NC}"
services=("api-service" "auth-service" "image-service" "frontend")
for svc in "${services[@]}"; do
    running_pods=$(kubectl get pods -l app=$svc -n production --no-headers 2>/dev/null | grep -c Running || echo "0")
    total_pods=$(kubectl get pods -l app=$svc -n production --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$running_pods" -gt 0 ]; then
        echo -e "${GREEN}✅ $svc: $running_pods/$total_pods pods running${NC}"
    else
        echo -e "${RED}❌ $svc: No pods running${NC}"
    fi
done
echo ""

# Test 5: Check data services
echo -e "${YELLOW}Test 5: Data Services${NC}"
data_services=("postgres" "redis" "minio")
for svc in "${data_services[@]}"; do
    if kubectl get pod -l app=$svc -n production --no-headers 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ $svc is running${NC}"
    else
        echo -e "${RED}❌ $svc is not running${NC}"
    fi
done
echo ""

# Test 6: Check monitoring
echo -e "${YELLOW}Test 6: Monitoring Stack${NC}"
monitoring=("prometheus" "grafana" "alertmanager")
for svc in "${monitoring[@]}"; do
    if kubectl get pod -l app=$svc -n monitoring --no-headers 2>/dev/null | grep -q Running; then
        echo -e "${GREEN}✅ $svc is running${NC}"
    else
        echo -e "${RED}❌ $svc is not running${NC}"
    fi
done
echo ""

# Test 7: Check ingress
echo -e "${YELLOW}Test 7: Ingress Controller${NC}"
if kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q Running; then
    echo -e "${GREEN}✅ Ingress controller is running${NC}"
    kubectl get ingress -n production 2>/dev/null || echo "No ingress resources found"
else
    echo -e "${RED}❌ Ingress controller is not running${NC}"
fi
echo ""

# Test 8: Check port forwards
echo -e "${YELLOW}Test 8: Port Forwarding${NC}"
ports=(80 443 30004 30030 30090)
for port in "${ports[@]}"; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*LISTEN" || lsof -i:$port 2>/dev/null | grep -q LISTEN; then
        echo -e "${GREEN}✅ Port $port is listening${NC}"
    else
        echo -e "${YELLOW}⚠️  Port $port is not listening${NC}"
    fi
done
echo ""

# Test 9: External accessibility
echo -e "${YELLOW}Test 9: External Access URLs${NC}"
echo "Testing local access..."

# Test frontend via NodePort
if timeout 5 curl -s http://localhost:30004 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Frontend accessible via localhost:30004${NC}"
else
    echo -e "${YELLOW}⚠️  Frontend not accessible via localhost:30004${NC}"
fi

# Test via public IP (if port forwarding is set up)
echo ""
echo "External access URLs (requires port forwarding):"
echo "  Frontend: http://$PUBLIC_IP:30004"
echo "  Grafana: http://$PUBLIC_IP:30030"
echo "  Prometheus: http://$PUBLIC_IP:30090"
echo "  Via domain: http://$PUBLIC_IP.nip.io (port 80)"
echo ""

# Test 10: Service health endpoints
echo -e "${YELLOW}Test 10: Service Health Checks${NC}"

# Get a frontend pod for port-forward test
FRONTEND_POD=$(kubectl get pods -n production -l app=frontend --no-headers 2>/dev/null | head -1 | awk '{print $1}')
if [ -n "$FRONTEND_POD" ]; then
    # Test frontend health
    kubectl port-forward -n production pod/$FRONTEND_POD 8888:3000 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    
    if timeout 3 curl -s http://localhost:8888/health >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Frontend health check passed${NC}"
    else
        echo -e "${YELLOW}⚠️  Frontend health check failed or not implemented${NC}"
    fi
    
    kill $PF_PID 2>/dev/null || true
else
    echo -e "${YELLOW}⚠️  No frontend pods available for health check${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"

# Count successes and failures
SUCCESS_COUNT=$(grep -c "✅" /proc/self/fd/1 2>/dev/null || echo "0")
FAILURE_COUNT=$(grep -c "❌" /proc/self/fd/1 2>/dev/null || echo "0")
WARNING_COUNT=$(grep -c "⚠️" /proc/self/fd/1 2>/dev/null || echo "0")

echo "Results:"
echo "  ✅ Passed: $SUCCESS_COUNT"
echo "  ⚠️  Warnings: $WARNING_COUNT"
echo "  ❌ Failed: $FAILURE_COUNT"

if [ "$FAILURE_COUNT" -eq 0 ]; then
    echo -e "\n${GREEN}All critical tests passed!${NC}"
else
    echo -e "\n${YELLOW}Some tests failed. Run './scripts/fix-deployment-issues.sh' to fix common issues.${NC}"
fi