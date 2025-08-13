#!/bin/bash
set -uo pipefail

# Enhanced SRE Assignment Deployment Script for Fresh Machines
# This version includes comprehensive error handling and recovery

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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   SRE Assignment - Fresh Machine Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Step 0: Run preflight fixes
log_info "Running preflight fixes for fresh machine..."
if [ -f scripts/preflight-fixes.sh ]; then
    chmod +x scripts/preflight-fixes.sh
    ./scripts/preflight-fixes.sh || {
        log_error "Preflight fixes failed!"
        exit 1
    }
else
    log_warning "Preflight fixes script not found, continuing anyway..."
fi

# Load configuration
if [ ! -f config/config.env ]; then
    log_error "Configuration file not found!"
    exit 1
fi
source config/config.env

# Initialize variables
SKIP_LOGIN=false
USE_LOCAL_IMAGES=false
PUSH_FAILED=false
LOGIN_SUCCESS=false
REGISTRY_FORWARD_PID=""
START_TIME=$(date +%s)

# Error handling
set +e
trap 'handle_error $? $LINENO' ERR

handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Error occurred at line $line_number (exit code: $exit_code)"
    
    # Cleanup on error
    if [ -n "${REGISTRY_FORWARD_PID:-}" ]; then
        kill $REGISTRY_FORWARD_PID 2>/dev/null || true
    fi
    pkill -f "kubectl port-forward" 2>/dev/null || true
    
    # Show troubleshooting tips
    echo -e "\n${YELLOW}Troubleshooting Tips:${NC}"
    echo "1. Check pod status: kubectl get pods --all-namespaces"
    echo "2. Check events: kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
    echo "3. View logs: kubectl logs -l app=<service-name> -n production"
    echo "4. Restart Minikube: minikube stop && minikube start"
    
    exit $exit_code
}

# Enhanced health check with better error recovery
health_check() {
    local service=$1
    local namespace=${2:-default}
    local max_attempts=60
    local attempt=0
    
    log_info "Waiting for $service to be ready..."
    
    # First, ensure the namespace exists
    if ! kubectl get namespace $namespace &>/dev/null; then
        log_error "Namespace $namespace does not exist!"
        return 1
    fi
    
    # Try kubectl wait first (most reliable)
    if kubectl wait --for=condition=ready pod -l app=$service -n $namespace --timeout=120s 2>/dev/null; then
        local pod_count=$(kubectl get pods -n $namespace -l app=$service --no-headers 2>/dev/null | wc -l | tr -d ' ')
        log_success "$service is ready ($pod_count pod(s) running)"
        return 0
    fi
    
    # Fallback to manual checking
    log_info "Using fallback health check for $service..."
    
    while [ $attempt -lt $max_attempts ]; do
        # Check for various pod issues
        local pods_info=$(kubectl get pods -n $namespace -l app=$service --no-headers 2>/dev/null)
        
        if [ -z "$pods_info" ]; then
            log_warning "No pods found for $service, waiting..."
            sleep 5
            ((attempt++))
            continue
        fi
        
        # Check for specific error states
        if echo "$pods_info" | grep -q "ErrImagePull\|ImagePullBackOff"; then
            log_warning "$service has image pull issues, attempting to fix..."
            
            # Try to use local images
            kubectl patch deployment $service -n $namespace -p '{"spec":{"template":{"spec":{"imagePullPolicy":"IfNotPresent"}}}}' 2>/dev/null || true
            sleep 10
        fi
        
        if echo "$pods_info" | grep -q "CrashLoopBackOff"; then
            log_warning "$service is crash looping, checking logs..."
            kubectl logs -l app=$service -n $namespace --tail=20 2>/dev/null || true
            
            # Restart the deployment
            kubectl rollout restart deployment/$service -n $namespace 2>/dev/null || true
            sleep 15
        fi
        
        # Check if pods are ready
        local running_pods=$(echo "$pods_info" | grep -c "Running" || echo "0")
        local ready_pods=$(echo "$pods_info" | awk '{print $2}' | grep -c "1/1\|2/2" || echo "0")
        
        if [[ "$ready_pods" -gt 0 ]]; then
            log_success "$service is ready ($ready_pods pod(s))"
            return 0
        fi
        
        # Show progress
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "Still waiting for $service (attempt $attempt/$max_attempts)..."
            echo "$pods_info"
        fi
        
        sleep 3
        ((attempt++))
    done
    
    log_error "$service failed to become ready after $max_attempts attempts"
    kubectl describe deployment $service -n $namespace 2>/dev/null || true
    return 1
}

# Step 1: Prerequisites check
log_info "Checking prerequisites..."
./prereq-check.sh || {
    log_error "Prerequisites check failed!"
    log_info "Please install missing dependencies and try again"
    exit 1
}

# Step 2: Clean Minikube state if requested
if [ "${CLEAN_START:-false}" = "true" ]; then
    log_warning "Clean start requested, removing existing Minikube cluster..."
    minikube delete --all --purge
    sleep 5
fi

# Step 3: Start Minikube with proper configuration
log_info "Starting Minikube cluster..."

# Check if Minikube is already running
if minikube status &>/dev/null; then
    log_info "Minikube is already running"
    
    # Verify it's healthy
    if ! kubectl cluster-info &>/dev/null; then
        log_warning "Minikube is running but not healthy, restarting..."
        minikube stop
        sleep 5
    else
        log_success "Using existing Minikube cluster"
    fi
fi

# Start Minikube if not running
if ! minikube status &>/dev/null; then
    minikube start \
        --memory=$MEMORY \
        --cpus=$CPUS \
        --disk-size=$DISK_SIZE \
        --driver=docker \
        --insecure-registry="10.0.0.0/8,localhost:5000,localhost:30500" || {
        log_error "Failed to start Minikube!"
        log_info "Try: minikube delete && minikube start --driver=docker"
        exit 1
    }
fi

# Step 4: Enable required addons
log_info "Enabling Minikube addons..."
minikube addons enable ingress || log_warning "Ingress addon failed"
minikube addons enable ingress-dns || log_warning "Ingress DNS addon failed"
minikube addons enable metrics-server || log_warning "Metrics server addon failed"
minikube addons enable dashboard || log_warning "Dashboard addon failed"

# Wait for core components
log_info "Waiting for Kubernetes core components..."
kubectl wait --for=condition=ready --timeout=300s -n kube-system pod -l component=kube-apiserver 2>/dev/null || true
kubectl wait --for=condition=ready --timeout=300s -n kube-system pod -l k8s-app=kube-dns 2>/dev/null || true

# Step 5: Create namespaces
log_info "Creating namespaces..."
kubectl apply -f kubernetes/core/00-namespaces.yaml || {
    log_warning "Failed to create namespaces, creating manually..."
    kubectl create namespace $NAMESPACE_PROD --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace $NAMESPACE_MONITORING --dry-run=client -o yaml | kubectl apply -f -
}

# Step 6: Deploy private registry with enhanced error handling
log_info "Deploying private registry..."

# Ensure registry auth script exists and is executable
if [ -f scripts/registry-auth.sh ]; then
    chmod +x scripts/registry-auth.sh
    ./scripts/registry-auth.sh || log_warning "Registry auth setup had issues"
else
    log_warning "Registry auth script not found, creating secret manually..."
    
    # Generate htpasswd manually
    docker run --rm httpd:2.4-alpine htpasswd -Bbn $REGISTRY_USER $REGISTRY_PASS > /tmp/htpasswd || {
        log_warning "Failed to generate htpasswd with Docker, using fallback..."
        echo "$REGISTRY_USER:$(openssl passwd -apr1 $REGISTRY_PASS)" > /tmp/htpasswd
    }
    
    kubectl create secret generic registry-auth \
        --from-file=/tmp/htpasswd \
        --namespace=default \
        --dry-run=client -o yaml | kubectl apply -f -
    
    rm -f /tmp/htpasswd
fi

# Deploy registry
kubectl apply -f kubernetes/core/01-registry.yaml || {
    log_error "Failed to deploy registry!"
    exit 1
}

# Wait for registry with enhanced checks
if ! health_check "docker-registry" "default"; then
    log_error "Registry failed to start!"
    kubectl describe deployment docker-registry -n default
    kubectl logs -l app=docker-registry -n default --tail=50
    exit 1
fi

# Get registry details
REGISTRY_IP=$(kubectl get service docker-registry -n default -o jsonpath='{.spec.clusterIP}')
MINIKUBE_IP=$(minikube ip)
log_success "Registry deployed - Cluster IP: $REGISTRY_IP:5000"

# Step 7: Build and prepare images
log_info "Configuring Docker to use Minikube..."
eval $(minikube docker-env) || {
    log_error "Failed to configure Docker environment!"
    exit 1
}

log_info "Building Docker images..."

# Build images with error handling
for service in api-service auth-service image-service frontend; do
    service_dir="./services/$service"
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory $service_dir not found!"
        exit 1
    fi
    
    log_info "Building $service..."
    if ! docker build -t $service:1.0.0 $service_dir; then
        log_error "Failed to build $service!"
        
        # Check for common issues
        if [ ! -f "$service_dir/Dockerfile" ]; then
            log_error "Dockerfile not found in $service_dir"
        fi
        
        exit 1
    fi
done

log_success "All images built successfully"

# Step 8: Setup registry access with better error handling
log_info "Setting up registry access..."

# Port forward for registry
kubectl port-forward --address 0.0.0.0 -n default svc/docker-registry 30500:5000 > /tmp/registry-forward.log 2>&1 &
REGISTRY_FORWARD_PID=$!
sleep 5

# Test registry connectivity
REGISTRY_URL="http://localhost:30500"
retry_count=0
while [ $retry_count -lt 30 ]; do
    if curl -s -u $REGISTRY_USER:$REGISTRY_PASS $REGISTRY_URL/v2/_catalog &>/dev/null; then
        log_success "Registry accessible at $REGISTRY_URL"
        break
    fi
    sleep 2
    ((retry_count++))
done

# Try to push images to registry, fall back to local if it fails
log_info "Attempting to push images to registry..."
PUSH_SUCCESS=true

for service in api-service auth-service image-service frontend; do
    docker tag $service:1.0.0 localhost:30500/$service:1.0.0 2>/dev/null || true
    
    if ! docker push localhost:30500/$service:1.0.0 2>/dev/null; then
        log_warning "Failed to push $service to registry, will use local image"
        PUSH_SUCCESS=false
    fi
done

if [ "$PUSH_SUCCESS" = false ]; then
    log_warning "Registry push failed, using local image deployment"
    USE_LOCAL_IMAGES=true
else
    log_success "All images pushed to registry"
    USE_LOCAL_IMAGES=false
fi

# Clean up registry port forward
if [ -n "$REGISTRY_FORWARD_PID" ]; then
    kill $REGISTRY_FORWARD_PID 2>/dev/null || true
fi

# Step 9: Deploy data layer
log_info "Deploying data infrastructure..."

# Clean up any existing jobs
kubectl delete job minio-bucket-init -n $NAMESPACE_PROD 2>/dev/null || true
sleep 2

# Deploy databases
for manifest in kubernetes/data/*.yaml; do
    log_info "Applying $(basename $manifest)..."
    kubectl apply -f $manifest || log_warning "Issues with $(basename $manifest)"
done

# Wait for data services
health_check "postgres" $NAMESPACE_PROD || log_warning "PostgreSQL not fully ready"
health_check "redis" $NAMESPACE_PROD || log_warning "Redis not fully ready"
health_check "minio" $NAMESPACE_PROD || log_warning "MinIO not fully ready"

# Step 10: Deploy applications with proper image references
log_info "Deploying applications..."

# Update and deploy manifests
export USE_LOCAL_IMAGES
if [ -f scripts/update-registry-refs.sh ]; then
    chmod +x scripts/update-registry-refs.sh
    ./scripts/update-registry-refs.sh
    kubectl apply -f /tmp/updated-apps/
else
    log_warning "Registry update script not found, deploying with original manifests"
    kubectl apply -f kubernetes/apps/
fi

# Wait for applications
for service in api-service auth-service image-service frontend; do
    health_check $service $NAMESPACE_PROD || log_warning "$service not fully ready"
done

# Step 11: Deploy monitoring
log_info "Deploying monitoring stack..."
for manifest in kubernetes/monitoring/*.yaml; do
    if [ -f "$manifest" ] && [[ ! "$manifest" == *"dashboards"* ]]; then
        kubectl apply -f $manifest || log_warning "Issues with $(basename $manifest)"
    fi
done

# Wait for monitoring services
health_check "prometheus" $NAMESPACE_MONITORING || log_warning "Prometheus not ready"
health_check "grafana" $NAMESPACE_MONITORING || log_warning "Grafana not ready"

# Step 12: Import dashboards
log_info "Importing Grafana dashboards..."
if [ -f scripts/import-dashboards.sh ]; then
    chmod +x scripts/import-dashboards.sh
    sleep 10
    ./scripts/import-dashboards.sh || log_warning "Dashboard import had issues"
else
    log_warning "Dashboard import script not found"
fi

# Step 13: Setup access
log_info "Setting up service access..."

# Kill existing port forwards
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Start essential port forwards
log_info "Starting port forwarding..."

# Get ingress service name
INGRESS_SVC=$(kubectl get svc -n ingress-nginx --no-headers 2>/dev/null | grep controller | awk '{print $1}' | head -1)

if [ -n "$INGRESS_SVC" ]; then
    kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/$INGRESS_SVC 80:80 > /tmp/http-forward.log 2>&1 &
    kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/$INGRESS_SVC 443:443 > /tmp/https-forward.log 2>&1 &
fi

# Frontend
kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:3000 > /tmp/frontend-forward.log 2>&1 &

# Monitoring
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /tmp/grafana-forward.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /tmp/prometheus-forward.log 2>&1 &

sleep 5

# Step 14: Run verification
log_info "Running deployment verification..."
if [ -f scripts/verify-deployment.sh ]; then
    chmod +x scripts/verify-deployment.sh
    ./scripts/verify-deployment.sh || log_warning "Some verification checks failed"
else
    log_warning "Verification script not found"
fi

# Calculate deployment time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Display final status
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com 2>/dev/null || hostname -I | awk '{print $1}')

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "${GREEN}   Time: ${MINUTES}m ${SECONDS}s${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}📋 Access Information:${NC}"
echo -e "  Frontend: ${GREEN}http://$PUBLIC_IP:30004${NC}"
echo -e "  Grafana: ${GREEN}http://$PUBLIC_IP:30030${NC} (admin/$GRAFANA_ADMIN_PASSWORD)"
echo -e "  Prometheus: ${GREEN}http://$PUBLIC_IP:30090${NC}"

echo -e "\n${YELLOW}🔧 Management:${NC}"
echo "  Dashboard: minikube dashboard"
echo "  Logs: kubectl logs -f <pod> -n production"
echo "  Stop: ./stop.sh"

echo -e "\n${YELLOW}⚠️  Important Notes:${NC}"
if [ "$USE_LOCAL_IMAGES" = true ]; then
    echo "  - Using local images (registry push failed)"
fi
echo "  - Services may take a few minutes to fully stabilize"
echo "  - Run './scripts/health-checks.sh' to verify all services"

exit 0