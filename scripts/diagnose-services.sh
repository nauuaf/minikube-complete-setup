#!/bin/bash

# Diagnostic script for failed services
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Service Diagnostics${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${YELLOW}1. Checking pod status:${NC}"
kubectl get pods -n $NAMESPACE_PROD -o wide

echo -e "\n${YELLOW}2. Checking deployments:${NC}"
kubectl get deployments -n $NAMESPACE_PROD

echo -e "\n${YELLOW}3. Checking services:${NC}"
kubectl get svc -n $NAMESPACE_PROD

echo -e "\n${YELLOW}4. Checking specific service pods:${NC}"
for service in api-service auth-service image-service frontend; do
    echo -e "\n${GREEN}$service:${NC}"
    pods=$(kubectl get pods -n $NAMESPACE_PROD -l app=$service --no-headers 2>/dev/null)
    if [[ -z "$pods" ]]; then
        echo "  ❌ No pods found for $service"
    else
        echo "$pods"
        # Get pod events
        pod_name=$(echo "$pods" | head -1 | awk '{print $1}')
        if [[ -n "$pod_name" ]]; then
            echo -e "\n  ${YELLOW}Recent events for $pod_name:${NC}"
            kubectl get events -n $NAMESPACE_PROD --field-selector involvedObject.name=$pod_name --sort-by='.lastTimestamp' | tail -5
            
            # Check if pod is stuck in pulling image
            if echo "$pods" | grep -q "ImagePullBackOff\|ErrImagePull"; then
                echo -e "\n  ${RED}⚠ Image pull issues detected${NC}"
                echo "  Checking pod describe for details..."
                kubectl describe pod $pod_name -n $NAMESPACE_PROD | grep -A5 "Events:"
            fi
            
            # Check container status
            echo -e "\n  ${YELLOW}Container status:${NC}"
            kubectl get pod $pod_name -n $NAMESPACE_PROD -o jsonpath='{.status.containerStatuses[*].state}' | jq '.'
        fi
    fi
done

echo -e "\n${YELLOW}5. Checking images used:${NC}"
kubectl get pods -n $NAMESPACE_PROD -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' | column -t

echo -e "\n${YELLOW}6. Checking local Docker images in Minikube:${NC}"
eval $(minikube docker-env)
docker images | grep -E "api-service|auth-service|image-service|frontend" || echo "No service images found in Minikube Docker"

echo -e "\n${YELLOW}7. Checking deployment manifests:${NC}"
if [[ -d "/tmp/updated-apps" ]]; then
    echo "Updated manifests exist in /tmp/updated-apps/"
    echo "Checking image references:"
    grep -h "image:" /tmp/updated-apps/*.yaml 2>/dev/null | sort -u
else
    echo "No updated manifests found"
fi

echo -e "\n${YELLOW}8. Checking service logs (last 20 lines):${NC}"
for service in api-service auth-service image-service; do
    echo -e "\n${GREEN}$service logs:${NC}"
    pod=$(kubectl get pods -n $NAMESPACE_PROD -l app=$service --no-headers 2>/dev/null | head -1 | awk '{print $1}')
    if [[ -n "$pod" ]]; then
        kubectl logs $pod -n $NAMESPACE_PROD --tail=20 2>/dev/null || echo "  No logs available"
    else
        echo "  No pod found"
    fi
done

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Diagnosis Complete${NC}"
echo -e "${BLUE}========================================${NC}"