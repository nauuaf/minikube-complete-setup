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
    
    # Stop all systemd services created by start.sh
    echo "Stopping systemd services..."
    for service in sre-platform-forward minikube-expose minikube-remote-access https-forward complete-forward; do
        if systemctl list-units --full -all | grep -Fq "${service}.service"; then
            echo "  Stopping ${service} service..."
            sudo systemctl stop ${service}.service 2>/dev/null || true
            sudo systemctl disable ${service}.service 2>/dev/null || true
        fi
    done
    
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
    
    # Remove all systemd service files created by start.sh
    echo "Removing systemd service files..."
    for service in sre-platform-forward minikube-expose minikube-remote-access https-forward complete-forward; do
        if [ -f "/etc/systemd/system/${service}.service" ]; then
            echo "  Removing ${service} service files..."
            sudo rm -f "/etc/systemd/system/${service}.service"
            sudo rm -f "/usr/local/bin/${service}.sh" 2>/dev/null || true
        fi
    done
    
    # Clean up port forwarding scripts
    sudo rm -f /usr/local/bin/sre-platform-forward.sh 2>/dev/null || true
    sudo rm -f /usr/local/bin/minikube-expose.sh 2>/dev/null || true
    sudo rm -f /usr/local/bin/https-forward.sh 2>/dev/null || true
    sudo rm -f /usr/local/bin/complete-forward.sh 2>/dev/null || true
    
    sudo systemctl daemon-reload
    
    echo -e "${GREEN}✓ Minikube cluster deleted${NC}"
else
    echo -e "${YELLOW}Tip: Use './stop.sh --delete-cluster' to also delete the minikube cluster${NC}"
fi

echo -e "${GREEN}✓ Cleanup complete${NC}"