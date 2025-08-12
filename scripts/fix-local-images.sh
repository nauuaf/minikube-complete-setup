#!/bin/bash

# Fix local images deployment issue
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing Local Images Deployment${NC}"
echo -e "${BLUE}========================================${NC}"

# Switch to Minikube Docker environment
echo -e "${YELLOW}Switching to Minikube Docker environment...${NC}"
eval $(minikube docker-env)

# Check existing images
echo -e "\n${YELLOW}Current images in Minikube:${NC}"
docker images | grep -E "api-service|auth-service|image-service|frontend" || echo "No service images found"

# Rebuild images if missing
echo -e "\n${YELLOW}Rebuilding service images in Minikube...${NC}"
docker build -t api-service:1.0.0 ./services/api-service/
docker build -t auth-service:1.0.0 ./services/auth-service/
docker build -t image-service:1.0.0 ./services/image-service/
docker build -t frontend:1.0.0 ./services/frontend/

echo -e "\n${GREEN}Images rebuilt successfully${NC}"

# Verify images exist
echo -e "\n${YELLOW}Verifying images:${NC}"
for img in "api-service:1.0.0" "auth-service:1.0.0" "image-service:1.0.0" "frontend:1.0.0"; do
    if docker images | grep -q "${img%:*}.*${img#*:}"; then
        echo "  ✅ $img exists"
    else
        echo "  ❌ $img missing"
    fi
done

# Update deployment manifests to use local images
echo -e "\n${YELLOW}Updating deployment manifests for local images...${NC}"
mkdir -p /tmp/updated-apps

# Create updated manifests with correct image names and imagePullPolicy
for file in 05-api-service 06-auth-service 07-image-service; do
    service_name=$(echo $file | sed 's/[0-9]*-//')
    cat kubernetes/apps/${file}.yaml | \
        sed -e "s|image: localhost:30500/${service_name}:.*|image: ${service_name}:1.0.0|" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
        > /tmp/updated-apps/${file}.yaml
    echo "  Updated ${file}.yaml"
done

# Handle frontend separately
cat kubernetes/apps/frontend-deployment.yaml | \
    sed -e "s|image: localhost:30500/frontend:.*|image: frontend:1.0.0|" \
    -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
    > /tmp/updated-apps/frontend-deployment.yaml
echo "  Updated frontend-deployment.yaml"

# Restart deployments with new configuration
echo -e "\n${YELLOW}Applying updated deployments...${NC}"
kubectl apply -f /tmp/updated-apps/05-api-service.yaml
kubectl apply -f /tmp/updated-apps/06-auth-service.yaml
kubectl apply -f /tmp/updated-apps/07-image-service.yaml
kubectl apply -f /tmp/updated-apps/frontend-deployment.yaml

# Wait for rollout
echo -e "\n${YELLOW}Waiting for deployments to roll out...${NC}"
kubectl rollout status deployment/api-service -n $NAMESPACE_PROD --timeout=120s || true
kubectl rollout status deployment/auth-service -n $NAMESPACE_PROD --timeout=120s || true
kubectl rollout status deployment/image-service -n $NAMESPACE_PROD --timeout=120s || true
kubectl rollout status deployment/frontend -n $NAMESPACE_PROD --timeout=120s || true

# Check pod status
echo -e "\n${YELLOW}Checking pod status:${NC}"
kubectl get pods -n $NAMESPACE_PROD -l 'app in (api-service,auth-service,image-service,frontend)'

# Run health checks
echo -e "\n${YELLOW}Running health checks...${NC}"
sleep 10
./scripts/health-checks.sh

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Fix Complete${NC}"
echo -e "${BLUE}========================================${NC}"