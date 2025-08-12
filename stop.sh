#!/bin/bash

source config/config.env

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Stopping SRE Assignment...${NC}"

# Check if minikube is running
if minikube status >/dev/null 2>&1; then
    # Delete Kubernetes resources in proper order
    echo "Cleaning up Kubernetes resources..."
    
    # Kill any port-forward processes
    echo "Stopping port forwarding..."
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    # Stop the systemd service if it exists
    if systemctl list-units --full -all | grep -Fq "minikube-expose.service"; then
        echo "Stopping minikube-expose service..."
        sudo systemctl stop minikube-expose.service 2>/dev/null || true
        sudo systemctl disable minikube-expose.service 2>/dev/null || true
    fi
    
    # Kill any minikube tunnel processes
    pkill -f "minikube tunnel" 2>/dev/null || true
    
    # Kill any socat forwarding processes
    sudo pkill -f "socat.*30004" 2>/dev/null || true
    sudo pkill -f "socat.*30030" 2>/dev/null || true
    sudo pkill -f "socat.*30090" 2>/dev/null || true
    sudo pkill -f "socat.*30501" 2>/dev/null || true
    sudo pkill -f "socat.*30901" 2>/dev/null || true
    
    # Delete in reverse order for clean shutdown
    kubectl delete -f kubernetes/apps/ 2>/dev/null || true
    sleep 2
    kubectl delete -f kubernetes/monitoring/ 2>/dev/null || true
    sleep 2
    kubectl delete -f kubernetes/security/ 2>/dev/null || true
    sleep 2
    kubectl delete -f kubernetes/core/ 2>/dev/null || true
    kubectl delete -f kubernetes/chaos/ 2>/dev/null || true
    
    # Delete cert-manager if it exists
    kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml 2>/dev/null || true
    
    # Stop Minikube
    echo "Stopping Minikube..."
    minikube stop
else
    echo "Minikube is not running"
fi

# Clean Docker images if desired
echo "Docker images from this project:"
docker images | grep -E "(api-service|auth-service|image-service|localhost:30500)" || echo "No project images found"

# Optional: Delete Minikube cluster  
if [[ "${1:-}" == "--delete-cluster" ]]; then
    echo "Deleting Minikube cluster..."
    minikube delete
    
    # Also remove the systemd service files if doing complete cleanup
    if [ -f /etc/systemd/system/minikube-expose.service ]; then
        echo "Removing minikube-expose service..."
        sudo rm -f /etc/systemd/system/minikube-expose.service
        sudo rm -f /usr/local/bin/minikube-expose.sh
        sudo systemctl daemon-reload
    fi
    
    echo -e "${GREEN}✓ Minikube cluster deleted${NC}"
else
    echo -e "${YELLOW}Tip: Use './stop.sh --delete-cluster' to also delete the minikube cluster${NC}"
fi

echo -e "${GREEN}✓ Cleanup complete${NC}"