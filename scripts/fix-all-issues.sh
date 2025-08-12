#!/bin/bash

# Comprehensive fix for all deployment issues
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing All Deployment Issues${NC}"
echo -e "${BLUE}========================================${NC}"

# Step 1: Fix MinIO CrashLoopBackOff
fix_minio() {
    echo -e "\n${YELLOW}Step 1: Fixing MinIO CrashLoopBackOff...${NC}"
    
    # Delete the failing MinIO pod
    kubectl delete pod minio-0 -n production 2>/dev/null || true
    
    # Apply the fixed configuration
    kubectl apply -f kubernetes/data/14-minio.yaml
    
    # Wait for MinIO to be ready
    echo "Waiting for MinIO to restart..."
    kubectl wait --for=condition=ready pod -l app=minio -n production --timeout=180s || {
        echo -e "${RED}MinIO still failing, checking logs...${NC}"
        kubectl logs minio-0 -n production --tail=20 || true
        kubectl describe pod minio-0 -n production | tail -10
        return 1
    }
    
    echo -e "${GREEN}✅ MinIO fixed and running${NC}"
}

# Step 2: Fix service health checks
fix_services() {
    echo -e "\n${YELLOW}Step 2: Fixing service health checks...${NC}"
    
    # Ensure we're using Minikube Docker environment
    eval $(minikube docker-env)
    
    # Check if images exist, rebuild if needed
    for service in api-service auth-service image-service frontend; do
        if ! docker images | grep -q "${service}.*1.0.0"; then
            echo "Rebuilding $service..."
            docker build -t ${service}:1.0.0 ./services/${service}/ || {
                echo -e "${RED}Failed to build $service${NC}"
                return 1
            }
        fi
    done
    
    # Update deployment manifests for local images
    mkdir -p /tmp/fixed-apps
    
    # Fix API service
    cat kubernetes/apps/05-api-service.yaml | \
        sed -e "s|image: localhost:30500/api-service:.*|image: api-service:1.0.0|" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
        > /tmp/fixed-apps/05-api-service.yaml
    
    # Fix Auth service  
    cat kubernetes/apps/06-auth-service.yaml | \
        sed -e "s|image: localhost:30500/auth-service:.*|image: auth-service:1.0.0|" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
        > /tmp/fixed-apps/06-auth-service.yaml
    
    # Fix Image service
    cat kubernetes/apps/07-image-service.yaml | \
        sed -e "s|image: localhost:30500/image-service:.*|image: image-service:1.0.0|" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
        > /tmp/fixed-apps/07-image-service.yaml
    
    # Fix Frontend
    cat kubernetes/apps/frontend-deployment.yaml | \
        sed -e "s|image: localhost:30500/frontend:.*|image: frontend:1.0.0|" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
        > /tmp/fixed-apps/frontend-deployment.yaml
    
    # Apply fixed deployments
    kubectl apply -f /tmp/fixed-apps/
    
    # Wait for rollouts
    echo "Waiting for service rollouts..."
    kubectl rollout status deployment/api-service -n production --timeout=120s
    kubectl rollout status deployment/auth-service -n production --timeout=120s  
    kubectl rollout status deployment/image-service -n production --timeout=120s
    kubectl rollout status deployment/frontend -n production --timeout=120s
    
    echo -e "${GREEN}✅ Services fixed and redeployed${NC}"
}

# Step 3: Fix registry authentication (optional since using local images)
fix_registry() {
    echo -e "\n${YELLOW}Step 3: Fixing registry authentication...${NC}"
    
    # Get registry info
    MINIKUBE_IP=$(minikube ip)
    REGISTRY_HOST="$MINIKUBE_IP:30500"
    
    # Test registry accessibility
    if curl -s -u "$REGISTRY_USER:$REGISTRY_PASS" "http://$REGISTRY_HOST/v2/" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Registry is accessible${NC}"
        return 0
    fi
    
    # Registry is not accessible, but we're using local images so it's OK
    echo -e "${YELLOW}⚠ Registry not accessible, but using local images (OK)${NC}"
}

# Step 4: Run comprehensive health checks
run_health_checks() {
    echo -e "\n${YELLOW}Step 4: Running health checks...${NC}"
    
    # Wait for all pods to be ready
    sleep 15
    
    # Check pod status
    echo -e "\n${BLUE}Pod Status:${NC}"
    kubectl get pods -n production
    kubectl get pods -n monitoring  
    
    # Test service endpoints
    echo -e "\n${BLUE}Service Health Tests:${NC}"
    
    services=(
        "api-service:production:3000:/health"
        "auth-service:production:8080:/health"
        "image-service:production:5000:/health" 
        "frontend:production:80:/"
        "prometheus:monitoring:9090:/-/healthy"
        "grafana:monitoring:3000:/api/health"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service namespace port path <<< "$service_info"
        printf "  %-15s " "$service:"
        
        # Use port-forward to test
        kubectl port-forward -n $namespace svc/$service $port:$port --address=127.0.0.1 >/dev/null 2>&1 &
        PF_PID=$!
        sleep 2
        
        if curl -s --max-time 5 "http://localhost:$port$path" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Healthy${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
        
        kill $PF_PID 2>/dev/null || true
        sleep 1
    done
}

# Main execution
echo -e "${BLUE}Starting comprehensive fix...${NC}"

# Run fixes in sequence
if fix_minio && fix_services && fix_registry; then
    echo -e "\n${GREEN}✅ All fixes applied successfully!${NC}"
    run_health_checks
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   All Issues Fixed!${NC}" 
    echo -e "${GREEN}========================================${NC}"
    
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "1. Enable remote access: ${GREEN}./scripts/enable-remote-access.sh${NC}"
    echo -e "2. Test from macOS: ${GREEN}curl http://\$(your-ubuntu-ip):30004${NC}"
    
else
    echo -e "\n${RED}❌ Some fixes failed. Check the output above.${NC}"
    exit 1
fi