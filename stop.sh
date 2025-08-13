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
    
    # No systemd services to stop since we removed them from start.sh
    
    # Delete in reverse order for clean shutdown
    echo "Deleting Kubernetes resources in proper order..."
    
    # Delete applications first
    if kubectl get -f kubernetes/apps/ >/dev/null 2>&1; then
        echo "  Deleting applications..."
        kubectl delete -f kubernetes/apps/ --timeout=60s 2>/dev/null || true
        sleep 3
    fi
    
    # Delete updated apps if they exist
    if [ -d "/tmp/updated-apps" ]; then
        echo "  Deleting updated applications..."
        kubectl delete -f /tmp/updated-apps/ --timeout=60s 2>/dev/null || true
        sleep 2
    fi
    
    # Delete monitoring
    if kubectl get -f kubernetes/monitoring/ >/dev/null 2>&1; then
        echo "  Deleting monitoring stack..."
        kubectl delete -f kubernetes/monitoring/ --timeout=60s 2>/dev/null || true
        sleep 3
    fi
    
    # Delete security resources
    if kubectl get -f kubernetes/security/ >/dev/null 2>&1; then
        echo "  Deleting security resources..."
        kubectl delete -f kubernetes/security/ --timeout=60s 2>/dev/null || true
        sleep 2
    fi
    
    # Delete core resources
    if kubectl get -f kubernetes/core/ >/dev/null 2>&1; then
        echo "  Deleting core resources..."
        kubectl delete -f kubernetes/core/ --timeout=60s 2>/dev/null || true
        sleep 2
    fi
    
    # Delete chaos engineering if exists
    if [ -d "kubernetes/chaos" ] && kubectl get -f kubernetes/chaos/ >/dev/null 2>&1; then
        echo "  Deleting chaos engineering resources..."
        kubectl delete -f kubernetes/chaos/ --timeout=60s 2>/dev/null || true
    fi
    
    # Skip cert-manager deletion (wasn't installed)
    
    # Stop Minikube
    echo "Stopping Minikube..."
    minikube stop
    
    # Reset Docker environment to host
    echo "Resetting Docker environment to host..."
    unset DOCKER_TLS_VERIFY DOCKER_HOST DOCKER_CERT_PATH DOCKER_MACHINE_NAME
    echo "Docker environment reset to host"
else
    echo "Minikube is not running"
fi

# Clean up temporary files
echo "Cleaning up temporary files..."
rm -rf /tmp/updated-apps/ 2>/dev/null || true
rm -f /tmp/registry-forward.log /tmp/health-check-result.log 2>/dev/null || true
rm -rf /tmp/sre-logs/ 2>/dev/null || true

# Clean Docker images if desired
echo "Docker images from this project:"
docker images | grep -E "(api-service|auth-service|image-service|frontend|localhost:30500)" || echo "No project images found"

# Optional: Delete Minikube cluster  
if [[ "${1:-}" == "--delete-cluster" ]]; then
    echo "Deleting Minikube cluster..."
    minikube delete
    
    # No systemd service files to remove since we simplified start.sh
    
    echo -e "${GREEN}✓ Minikube cluster deleted${NC}"
else
    echo -e "${YELLOW}Tip: Use './stop.sh --delete-cluster' to also delete the minikube cluster${NC}"
fi

echo -e "${GREEN}✓ Cleanup complete${NC}"