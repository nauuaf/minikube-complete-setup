#!/bin/bash
set -uo pipefail

source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing Image Pull Issues${NC}"
echo -e "${BLUE}========================================${NC}"

# Method 1: Load images directly into Minikube
log_info "Loading images directly into Minikube's Docker daemon..."

# Switch to Minikube's Docker environment
eval $(minikube docker-env)

# Check if images exist in Minikube
log_info "Checking existing images in Minikube..."
for img in api-service auth-service image-service frontend; do
    if docker images | grep -q "^$img.*1.0.0"; then
        log_success "$img:1.0.0 already exists in Minikube"
    else
        log_warning "$img:1.0.0 not found, building..."
        docker build -t $img:1.0.0 ./services/$img/ || {
            # Frontend is in a different path
            if [ "$img" = "frontend" ]; then
                docker build -t frontend:1.0.0 ./services/frontend/
            fi
        }
    fi
done

# Method 2: Update deployments to use local images
log_info "Updating deployments to use local images..."

# Create updated manifests
mkdir -p /tmp/fixed-apps

# Function to patch deployment to use local images
patch_deployment() {
    local service=$1
    local namespace=${2:-production}
    
    log_info "Patching $service deployment..."
    
    # Create patch to use local image
    cat > /tmp/patch-$service.yaml << EOF
spec:
  template:
    spec:
      containers:
      - name: ${service//-service/}
        image: $service:1.0.0
        imagePullPolicy: Never
EOF
    
    # Apply the patch
    kubectl patch deployment $service -n $namespace --patch-file=/tmp/patch-$service.yaml || {
        log_warning "Patch failed, trying direct update..."
        
        # Alternative: Update the deployment directly
        kubectl set image deployment/$service -n $namespace \
            ${service//-service/}=$service:1.0.0 || \
            kubectl set image deployment/$service -n $namespace \
            $service=$service:1.0.0 || \
            log_error "Failed to update $service image"
    }
    
    # Also update imagePullPolicy
    kubectl patch deployment $service -n $namespace -p \
        '{"spec":{"template":{"spec":{"containers":[{"name":"'${service//-service/}'","imagePullPolicy":"Never"}]}}}}' || true
}

# Patch all service deployments
for service in api-service auth-service image-service; do
    patch_deployment $service production
done

# Frontend has a different container name
log_info "Patching frontend deployment..."
kubectl patch deployment frontend -n production -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"frontend","image":"frontend:1.0.0","imagePullPolicy":"Never"}]}}}}' || {
    kubectl set image deployment/frontend -n production frontend=frontend:1.0.0
}

# Method 3: Remove imagePullSecrets since we're using local images
log_info "Removing imagePullSecrets from deployments..."
for deployment in api-service auth-service image-service frontend; do
    kubectl patch deployment $deployment -n production --type=json -p='[{"op": "remove", "path": "/spec/template/spec/imagePullSecrets"}]' 2>/dev/null || true
done

# Method 4: Restart all deployments
log_info "Restarting deployments with local images..."
kubectl rollout restart deployment -n production

# Wait for rollouts
log_info "Waiting for deployments to roll out..."
for service in api-service auth-service image-service frontend; do
    log_info "Waiting for $service..."
    kubectl rollout status deployment/$service -n production --timeout=120s || {
        log_warning "$service rollout timed out, checking status..."
        kubectl get pods -n production -l app=$service
    }
done

# Verify pods are running
log_info "Verifying pods are running..."
sleep 10

echo ""
echo -e "${YELLOW}Current pod status:${NC}"
kubectl get pods -n production

# Check for any remaining ImagePullBackOff
if kubectl get pods -n production | grep -q "ImagePullBackOff\|ErrImagePull"; then
    log_warning "Some pods still have image pull issues"
    
    # Show which pods have issues
    echo ""
    echo -e "${YELLOW}Pods with issues:${NC}"
    kubectl get pods -n production | grep "ImagePullBackOff\|ErrImagePull"
    
    # Try one more fix - delete pods to force recreation
    log_info "Deleting problematic pods to force recreation..."
    kubectl delete pods -n production --field-selector=status.phase=Pending
    
    sleep 10
    kubectl get pods -n production
else
    log_success "All pods are running without image pull issues!"
fi

# Alternative fix if still having issues
if kubectl get pods -n production | grep -q "ImagePullBackOff\|ErrImagePull"; then
    log_warning "Still having issues. Applying alternative fix..."
    
    # Create simple deployments without registry
    for service in api-service auth-service image-service; do
        cat > /tmp/$service-local.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $service
  template:
    metadata:
      labels:
        app: $service
    spec:
      containers:
      - name: ${service//-service/}
        image: $service:1.0.0
        imagePullPolicy: Never
        ports:
        - containerPort: $([ "$service" = "auth-service" ] && echo "8080" || [ "$service" = "image-service" ] && echo "5000" || echo "3000")
        env:
        - name: NODE_ENV
          value: production
EOF
        kubectl apply -f /tmp/$service-local.yaml
    done
    
    # Frontend
    cat > /tmp/frontend-local.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: frontend:1.0.0
        imagePullPolicy: Never
        ports:
        - containerPort: 3000
EOF
    kubectl apply -f /tmp/frontend-local.yaml
fi

echo ""
log_success "Image pull fix complete!"
echo ""
echo -e "${GREEN}Final status:${NC}"
kubectl get pods -n production