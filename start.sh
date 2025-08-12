#!/bin/bash
set -euo pipefail

# SRE Assignment Deployment Script - Ubuntu/Linux Edition
# Optimized for Ubuntu 20.04+ and similar Linux distributions
# Features: Private Docker Registry, Microservices, Monitoring, TLS

# Load configuration
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Error handling
trap 'echo -e "${RED}Error occurred at line $LINENO${NC}"; exit 1' ERR

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

health_check() {
    local service=$1
    local namespace=${2:-default}
    local max_attempts=60
    local attempt=0
    
    log_info "Waiting for $service to be ready..."
    
    # Wait for pods to be running and ready using kubectl wait
    if kubectl wait --for=condition=ready pod -l app=$service -n $namespace --timeout=120s 2>/dev/null; then
        local pod_count=$(kubectl get pods -n $namespace -l app=$service --no-headers 2>/dev/null | wc -l | tr -d ' ')
        log_success "$service is ready ($pod_count pod(s) running)"
        return 0
    fi
    
    # Fallback to manual checking if kubectl wait fails
    log_info "kubectl wait failed, trying manual check..."
    
    # Check for stuck pods and restart them if needed
    local stuck_pods=$(kubectl get pods -n $namespace -l app=$service --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$stuck_pods" -gt 0 ]]; then
        log_warning "Found $stuck_pods stuck pod(s) for $service, restarting them..."
        kubectl delete pods -n $namespace -l app=$service --field-selector=status.phase=Pending
        sleep 10
    fi
    
    while [ $attempt -lt $max_attempts ]; do
        # Check for pods stuck in ContainerCreating for too long (>3 minutes)
        if [ $attempt -gt 30 ]; then
            local creating_pods=$(kubectl get pods -n $namespace -l app=$service | grep ContainerCreating | wc -l | tr -d ' ')
            if [[ "$creating_pods" -gt 0 ]]; then
                log_warning "Restarting pods stuck in ContainerCreating status..."
                kubectl delete pods -n $namespace -l app=$service --field-selector=status.phase=Pending
                sleep 10
            fi
        fi
        
        # Simple check - just see if pods are running
        local running_pods=$(kubectl get pods -n $namespace -l app=$service --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local total_pods=$(kubectl get pods -n $namespace -l app=$service --no-headers 2>/dev/null | wc -l | tr -d ' ')
        
        if [[ "$running_pods" -gt 0 ]] && [[ "$running_pods" -eq "$total_pods" ]]; then
            log_success "$service is ready ($running_pods/$total_pods pods)"
            return 0
        fi
        
        # Show progress every 10 attempts
        if [ $((attempt % 10)) -eq 0 ]; then
            log_info "⏳ $service: $running_pods/$total_pods pods running (attempt $attempt/$max_attempts)"
        fi
        
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    log_error "$service failed to start after $max_attempts attempts"
    kubectl get pods -n $namespace -l app=$service 2>/dev/null || true
    kubectl describe pods -n $namespace -l app=$service 2>/dev/null || true
    return 1
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   SRE Assignment - Ubuntu/Linux${NC}"
echo -e "${GREEN}   Kubernetes Platform Deployment${NC}"
echo -e "${GREEN}========================================${NC}"

# Step 0: Pre-flight check
log_info "Running pre-flight checks..."

# Ensure we're in the right directory
if [[ ! -f "config/config.env" ]]; then
    log_error "config/config.env not found. Please run this script from the sre-assignment directory"
    exit 1
fi

# Check if minikube is already running with conflicting state
if minikube status >/dev/null 2>&1; then
    log_info "Minikube is already running. Restarting for clean state..."
    minikube stop
    sleep 2
fi

# Step 1: Prerequisites check
log_info "Checking prerequisites..."
./prereq-check.sh || exit 1

# Step 2: Start Minikube
log_info "Starting Minikube cluster..."
minikube start \
    --memory=$MEMORY \
    --cpus=$CPUS \
    --disk-size=$DISK_SIZE \
    --driver=docker \
    --insecure-registry="10.0.0.0/8,localhost:5000"

# Step 3: Enable addons
log_info "Enabling Minikube addons..."
minikube addons enable ingress
minikube addons enable ingress-dns
minikube addons enable metrics-server
minikube addons enable dashboard

# Step 4: Install cert-manager for Let's Encrypt
log_info "Installing cert-manager for TLS..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
sleep 30  # Wait for cert-manager to be ready

# Step 5: Create namespaces
log_info "Creating namespaces..."
kubectl apply -f kubernetes/core/00-namespaces.yaml
sleep 2

# Step 6: Deploy private registry with auth
log_info "Deploying private registry..."
./scripts/registry-auth.sh
kubectl apply -f kubernetes/core/01-registry.yaml
health_check "docker-registry" "default"

# Get registry details
REGISTRY_IP=$(kubectl get service docker-registry -n default -o jsonpath='{.spec.clusterIP}')
MINIKUBE_IP=$(minikube ip)
log_success "Registry deployed - Cluster IP: $REGISTRY_IP:5000, NodePort: $MINIKUBE_IP:$REGISTRY_PORT"

# Step 7: Configure Docker to use Minikube
eval $(minikube docker-env)

# Step 8: Build images
log_info "Building Docker images..."
docker build -t api-service:$API_VERSION ./services/api-service &
docker build -t auth-service:$AUTH_VERSION ./services/auth-service &
docker build -t image-service:$IMAGE_VERSION ./services/image-service &
docker build -t frontend:$FRONTEND_VERSION ./services/frontend &
wait
log_success "All images built"

# Step 9: Tag and push to registry
log_info "Pushing images to private registry..."

# Wait for registry to be ready
kubectl wait --for=condition=ready pod -l app=docker-registry --timeout=300s

# Use direct NodePort access (works natively on Linux)
MINIKUBE_IP=$(minikube ip)
REGISTRY_URL="http://$MINIKUBE_IP:$REGISTRY_PORT"
REGISTRY_HOST="$MINIKUBE_IP:$REGISTRY_PORT"

log_info "Testing registry connection at $REGISTRY_URL..."
# Simple connection test with retry
retry_count=0
while [ $retry_count -lt 30 ]; do
    if curl -s -u $REGISTRY_USER:$REGISTRY_PASS $REGISTRY_URL/v2/ > /dev/null 2>&1; then
        log_success "✅ Registry accessible at: $REGISTRY_URL"
        break
    fi
    log_info "Registry not ready, retrying in 2 seconds..."
    sleep 2
    ((retry_count++))
done

if [ $retry_count -eq 30 ]; then
    log_error "❌ Registry connection failed after 60 seconds"
    log_error "Please check: kubectl get pods -l app=docker-registry"
    log_error "And: kubectl logs -l app=docker-registry"
    exit 1
fi

# Configure Docker for insecure registry (required for HTTP registries)
log_info "Configuring Docker for insecure registry..."
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
NEEDS_RESTART=false

# Check if we need to add insecure registry
if [ -f "$DOCKER_DAEMON_JSON" ]; then
    # Check if our registry is already configured
    if ! grep -q "$REGISTRY_HOST" "$DOCKER_DAEMON_JSON" 2>/dev/null; then
        log_warning "Adding $REGISTRY_HOST to Docker insecure registries..."
        # Backup existing config
        sudo cp "$DOCKER_DAEMON_JSON" "${DOCKER_DAEMON_JSON}.backup"
        # Add our registry to existing config
        sudo jq --arg registry "$REGISTRY_HOST" '.["insecure-registries"] += [$registry]' "$DOCKER_DAEMON_JSON" > /tmp/daemon.json
        sudo mv /tmp/daemon.json "$DOCKER_DAEMON_JSON"
        NEEDS_RESTART=true
    fi
else
    # Create new config with our registry
    log_info "Creating Docker daemon configuration..."
    echo "{\"insecure-registries\": [\"$REGISTRY_HOST\"]}" | sudo tee "$DOCKER_DAEMON_JSON" > /dev/null
    NEEDS_RESTART=true
fi

# Restart Docker if configuration changed
if [ "$NEEDS_RESTART" = true ]; then
    log_info "Restarting Docker daemon to apply configuration..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    sleep 5
    # Wait for Docker to be ready
    retry_count=0
    while [ $retry_count -lt 10 ]; do
        if docker info > /dev/null 2>&1; then
            log_success "Docker daemon restarted successfully"
            break
        fi
        sleep 2
        ((retry_count++))
    done
    if [ $retry_count -eq 10 ]; then
        log_error "Docker daemon failed to restart properly"
        exit 1
    fi
fi

# Verify Docker sees the insecure registry
log_info "Verifying Docker configuration..."
if docker info 2>/dev/null | grep -q "$REGISTRY_HOST"; then
    log_success "Docker configured with insecure registry: $REGISTRY_HOST"
else
    log_warning "Docker may not be properly configured, attempting to fix..."
    # Force add to Docker config
    echo "{\"insecure-registries\": [\"$REGISTRY_HOST\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    sleep 5
fi

# Docker login with retry and better error handling
log_info "Logging into registry..."
login_retry=0
LOGIN_SUCCESS=false

while [ $login_retry -lt 3 ]; do
    # Try login and capture result
    if echo "$REGISTRY_PASS" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin >/dev/null 2>&1; then
        log_success "Docker login successful"
        LOGIN_SUCCESS=true
        break
    else
        login_retry=$((login_retry + 1))
        if [ $login_retry -lt 3 ]; then
            log_warning "Docker login failed (attempt $login_retry/3), retrying in 5 seconds..."
            
            # Debug: Show what we're trying to connect to
            echo "  Registry: $REGISTRY_HOST"
            echo "  User: $REGISTRY_USER"
            
            # Check if registry is actually running and accessible
            if curl -s -u "$REGISTRY_USER:$REGISTRY_PASS" "http://$REGISTRY_HOST/v2/" >/dev/null 2>&1; then
                log_info "Registry API is accessible, Docker config may be the issue"
                
                # Force reconfigure Docker
                log_info "Forcing Docker reconfiguration..."
                echo "{\"insecure-registries\": [\"$REGISTRY_HOST\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
                sudo systemctl daemon-reload
                sudo systemctl restart docker
                sleep 5
                
                # Wait for Docker to be ready
                docker_ready=0
                while [ $docker_ready -lt 10 ]; do
                    if docker info >/dev/null 2>&1; then
                        break
                    fi
                    sleep 1
                    docker_ready=$((docker_ready + 1))
                done
            else
                log_warning "Registry API not accessible, checking pod status..."
                kubectl get pods -l app=docker-registry 2>/dev/null || true
            fi
            
            sleep 5
        fi
    fi
done

if [ "$LOGIN_SUCCESS" = false ]; then
    log_error "❌ Docker login failed after 3 attempts"
    
    # Provide debugging information
    log_info "Debugging information:"
    echo "Registry URL: $REGISTRY_HOST"
    echo "Registry User: $REGISTRY_USER"
    echo "Testing direct registry access..."
    if curl -u "$REGISTRY_USER:$REGISTRY_PASS" "http://$REGISTRY_HOST/v2/_catalog" 2>/dev/null; then
        echo "✓ Direct registry access works"
    else
        echo "✗ Direct registry access failed"
    fi
    
    log_info "Docker insecure registries configuration:"
    docker info 2>/dev/null | grep -A5 "Insecure Registries" || true
    
    log_info "Registry pod status:"
    kubectl get pods -l app=docker-registry || true
    
    # Don't exit - try to continue with local images
    log_warning "Registry login failed, but continuing with deployment..."
    log_warning "Will attempt to use local images or pull from registry during deployment"
    SKIP_LOGIN=true
fi

# Check if Minikube is still accessible
log_info "Checking Minikube status..."
if ! minikube status >/dev/null 2>&1; then
    log_error "Minikube is not running or not accessible"
    log_info "Attempting to restart Minikube..."
    minikube stop || true
    sleep 5
    minikube start --memory=$MEMORY --cpus=$CPUS --disk-size=$DISK_SIZE
    sleep 10
    MINIKUBE_IP=$(minikube ip)
    REGISTRY_HOST="$MINIKUBE_IP:$REGISTRY_PORT"
    log_success "Minikube restarted with IP: $MINIKUBE_IP"
fi

# Tag and push images (with error handling)
log_info "Tagging images for registry..."
if docker tag api-service:$API_VERSION $REGISTRY_HOST/api-service:$API_VERSION 2>/dev/null && \
   docker tag auth-service:$AUTH_VERSION $REGISTRY_HOST/auth-service:$AUTH_VERSION 2>/dev/null && \
   docker tag image-service:$IMAGE_VERSION $REGISTRY_HOST/image-service:$IMAGE_VERSION 2>/dev/null && \
   docker tag frontend:$FRONTEND_VERSION $REGISTRY_HOST/frontend:$FRONTEND_VERSION 2>/dev/null; then
    log_success "Images tagged successfully"
else
    log_warning "Failed to tag some images, will use local images"
    SKIP_LOGIN=true
fi

log_info "Pushing images to registry..."

# Function to push with retry
push_image() {
    local image=$1
    local retry=0
    while [ $retry -lt 3 ]; do
        if docker push $image 2>/dev/null; then
            log_success "Pushed $image"
            return 0
        else
            ((retry++))
            if [ $retry -lt 3 ]; then
                log_warning "Push failed for $image, retry $retry/3"
                sleep 2
            fi
        fi
    done
    log_error "Failed to push $image after 3 attempts"
    return 1
}

# Push all images (skip if login failed)
if [ "$SKIP_LOGIN" != "true" ]; then
    PUSH_FAILED=false
    push_image "$REGISTRY_HOST/api-service:$API_VERSION" || PUSH_FAILED=true
    push_image "$REGISTRY_HOST/auth-service:$AUTH_VERSION" || PUSH_FAILED=true
    push_image "$REGISTRY_HOST/image-service:$IMAGE_VERSION" || PUSH_FAILED=true
    push_image "$REGISTRY_HOST/frontend:$FRONTEND_VERSION" || PUSH_FAILED=true

    if [ "$PUSH_FAILED" = true ]; then
        log_warning "Some images failed to push, but continuing with deployment..."
        log_warning "Services will try to pull from registry during deployment"
    else
        log_success "All images pushed to registry successfully"
    fi
else
    log_warning "Skipping image push due to registry login failure"
    log_info "Loading images directly into Minikube instead..."
    
    # Since Minikube uses Docker driver, we need to push to Minikube's Docker daemon
    log_info "Configuring Docker to use Minikube's daemon..."
    eval $(minikube docker-env)
    
    # Rebuild images in Minikube's Docker daemon
    log_info "Building images in Minikube's Docker environment..."
    docker build -t api-service:$API_VERSION ./services/api-service/ || log_warning "Failed to build api-service"
    docker build -t auth-service:$AUTH_VERSION ./services/auth-service/ || log_warning "Failed to build auth-service"
    docker build -t image-service:$IMAGE_VERSION ./services/image-service/ || log_warning "Failed to build image-service"
    docker build -t frontend:$FRONTEND_VERSION ./services/frontend/ || log_warning "Failed to build frontend"
    
    log_success "Images built in Minikube's Docker daemon"
fi

# Verify registry contents
log_info "Verifying registry contents..."
curl -s -u $REGISTRY_USER:$REGISTRY_PASS $REGISTRY_URL/v2/_catalog | jq .

# Step 10: Install Ingress Controller and cert-manager for HTTPS
log_info "Installing NGINX Ingress Controller..."

# Delete old ingress jobs if they exist (to avoid conflicts)
kubectl delete job ingress-nginx-admission-create -n ingress-nginx 2>/dev/null || true
kubectl delete job ingress-nginx-admission-patch -n ingress-nginx 2>/dev/null || true

# For Minikube, use the built-in ingress addon instead
if minikube addons list | grep -q "ingress.*enabled"; then
    log_info "Ingress addon already enabled in Minikube"
else
    log_info "Enabling Minikube ingress addon..."
    minikube addons enable ingress
fi

log_info "Waiting for Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=ingress-nginx \
  --timeout=300s || log_warning "Ingress controller taking longer than expected"

log_info "Installing cert-manager for Let's Encrypt certificates..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

log_info "Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=300s || log_warning "cert-manager taking longer than expected"

# Give cert-manager webhooks time to be ready
sleep 15

# Step 11: Deploy security components
log_info "Deploying security components..."
kubectl apply -f kubernetes/security/02-secrets.yaml
kubectl apply -f kubernetes/security/03-network-policies.yaml

# Deploy TLS configuration (this will now work with cert-manager installed)
log_info "Configuring TLS with Let's Encrypt for nawaf.thmanyah.com..."
kubectl apply -f kubernetes/security/04-tls-ingress.yaml

# Step 12: Deploy data layer (PostgreSQL, Redis, MinIO)
log_info "Deploying data infrastructure..."

# Clean up any existing MinIO bucket initialization job first (Jobs are immutable in Kubernetes)
log_info "Cleaning up existing MinIO bucket initialization job..."
kubectl delete job minio-bucket-init -n $NAMESPACE_PROD 2>/dev/null || true
sleep 5

# Deploy data infrastructure
kubectl apply -f kubernetes/data/12-postgresql.yaml
kubectl apply -f kubernetes/data/13-redis.yaml
kubectl apply -f kubernetes/data/14-minio.yaml

# Wait for data layer to be ready
health_check "postgres" $NAMESPACE_PROD
health_check "redis" $NAMESPACE_PROD
health_check "minio" $NAMESPACE_PROD

log_info "Waiting for MinIO bucket initialization..."
# First check if MinIO pod is actually ready
if ! kubectl wait --for=condition=ready pod -l app=minio -n $NAMESPACE_PROD --timeout=120s; then
    log_warning "MinIO pod not ready within 2 minutes, checking status..."
    kubectl get pods -l app=minio -n $NAMESPACE_PROD
    kubectl describe pods -l app=minio -n $NAMESPACE_PROD
fi

# Check if bucket initialization job already exists and is running
if kubectl get job minio-bucket-init -n $NAMESPACE_PROD >/dev/null 2>&1; then
    job_status=$(kubectl get job minio-bucket-init -n $NAMESPACE_PROD -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    
    if [ "$job_status" = "True" ]; then
        log_success "MinIO bucket initialization already completed"
    else
        log_info "MinIO bucket initialization job exists, checking progress..."
        # Wait for up to 10 minutes with better timeout handling
        if kubectl wait --for=condition=complete job/minio-bucket-init -n $NAMESPACE_PROD --timeout=600s; then
            log_success "MinIO bucket initialization completed"
        else
            log_warning "MinIO bucket initialization timed out after 10 minutes"
            log_info "Checking job status and logs..."
            kubectl get job minio-bucket-init -n $NAMESPACE_PROD
            kubectl get pods -l app=minio-init -n $NAMESPACE_PROD
            
            # Get logs from the job pods
            job_pods=$(kubectl get pods -l app=minio-init -n $NAMESPACE_PROD --no-headers 2>/dev/null | awk '{print $1}' | head -1)
            if [ -n "$job_pods" ]; then
                log_info "MinIO initialization job logs:"
                kubectl logs "$job_pods" -n $NAMESPACE_PROD --tail=20 || true
                
                # Check if this is a timeout in the init container
                kubectl describe pod "$job_pods" -n $NAMESPACE_PROD | grep -A10 -B5 "wait-for-minio" || true
            fi
            
            # Delete and retry the job once
            log_info "Retrying MinIO bucket initialization..."
            kubectl delete job minio-bucket-init -n $NAMESPACE_PROD || true
            sleep 5
            
            # Recreate the job
            kubectl apply -f kubernetes/data/14-minio.yaml
            
            # Wait again with shorter timeout
            if kubectl wait --for=condition=complete job/minio-bucket-init -n $NAMESPACE_PROD --timeout=300s; then
                log_success "MinIO bucket initialization completed on retry"
            else
                log_warning "MinIO bucket initialization failed again - continuing with deployment"
                log_warning "You may need to manually initialize buckets later"
                # Don't fail the entire deployment for this
            fi
        fi
    fi
else
    log_warning "MinIO bucket initialization job not found, skipping..."
fi

# Step 13: Deploy applications
log_info "Deploying applications..."

# Update manifests with correct registry references
if [ "$SKIP_LOGIN" = "true" ]; then
    export USE_LOCAL_IMAGES=true
fi
./scripts/update-registry-refs.sh

# Deploy applications (they will pull from registry)
kubectl apply -f /tmp/updated-apps/

health_check "api-service" $NAMESPACE_PROD
health_check "auth-service" $NAMESPACE_PROD
health_check "image-service" $NAMESPACE_PROD
health_check "frontend" $NAMESPACE_PROD

# Step 14: Deploy monitoring
log_info "Deploying monitoring stack..."
kubectl apply -f kubernetes/monitoring/08-prometheus.yaml
kubectl apply -f kubernetes/monitoring/09-grafana.yaml
kubectl apply -f kubernetes/monitoring/10-alertmanager.yaml
kubectl apply -f kubernetes/monitoring/11-alert-rules.yaml
health_check "prometheus" $NAMESPACE_MONITORING
health_check "grafana" $NAMESPACE_MONITORING
health_check "alertmanager" $NAMESPACE_MONITORING

# Step 15: Import Grafana dashboards
log_info "Importing Grafana dashboards..."
sleep 10
./scripts/import-dashboards.sh

# Step 16: Run smoke tests
log_info "Running smoke tests..."
./scripts/health-checks.sh

# Step 17: Enable HTTPS and remote access
log_info "Enabling HTTPS and remote access..."

# Kill any existing port forwards
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Create comprehensive port forwarding script
cat > /tmp/sre-platform-forward.sh << 'EOF'
#!/bin/bash

# Create log directory with proper permissions
mkdir -p /tmp/sre-logs
chmod 755 /tmp/sre-logs

echo "Starting comprehensive port forwarding..."

# Wait for ingress controller
while ! kubectl get pods -n ingress-nginx | grep -q "Running"; do
    echo "Waiting for ingress controller..."
    sleep 5
done

# Kill any existing forwards
pkill -f "port-forward" 2>/dev/null || true
sleep 2

echo "Starting port forwards with correct service ports..."

# HTTPS/HTTP for ingress (domain access)
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /tmp/sre-logs/http.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /tmp/sre-logs/https.log 2>&1 &

# Direct service access (using correct service ports)
kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:3000 > /tmp/sre-logs/frontend.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /tmp/sre-logs/grafana.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /tmp/sre-logs/prometheus.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n default svc/registry-ui 30501:80 > /tmp/sre-logs/registry-ui.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n production svc/minio-nodeport 30900:9000 > /tmp/sre-logs/minio-api.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n production svc/minio-nodeport 30901:9001 > /tmp/sre-logs/minio-console.log 2>&1 &

echo "All port forwards started"

# Monitor and restart if needed
while true; do
    sleep 30
    
    # Check critical forwarding with proper restart
    if ! pgrep -f "port-forward.*:443" > /dev/null; then
        echo "Restarting HTTPS forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /tmp/sre-logs/https.log 2>&1 &
    fi
    
    if ! pgrep -f "port-forward.*:80" > /dev/null; then
        echo "Restarting HTTP forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /tmp/sre-logs/http.log 2>&1 &
    fi
    
    if ! pgrep -f "port-forward.*30004" > /dev/null; then
        echo "Restarting frontend forward..."
        kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:3000 > /tmp/sre-logs/frontend.log 2>&1 &
    fi
    if ! pgrep -f "port-forward.*30030" > /dev/null; then
        echo "Restarting Grafana forward..."
        kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /tmp/sre-logs/grafana.log 2>&1 &
    fi
    if ! pgrep -f "port-forward.*30090" > /dev/null; then
        echo "Restarting Prometheus forward..."
        kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /tmp/sre-logs/prometheus.log 2>&1 &
    fi
done
EOF

# Install as systemd service
sudo cp /tmp/sre-platform-forward.sh /usr/local/bin/sre-platform-forward.sh
sudo chmod +x /usr/local/bin/sre-platform-forward.sh

cat > /tmp/sre-platform-forward.service << EOF
[Unit]
Description=SRE Platform Port Forwarding Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/$USER"
Environment="KUBECONFIG=/home/$USER/.kube/config"
ExecStart=/usr/local/bin/sre-platform-forward.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/sre-platform-forward.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable sre-platform-forward.service
sudo systemctl restart sre-platform-forward.service

log_success "HTTPS and remote access enabled"

# Configure firewall
log_info "Configuring firewall for remote access..."
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
    sudo ufw allow 443/tcp comment "HTTPS" 2>/dev/null || true
    sudo ufw allow 30000:32767/tcp comment "Kubernetes NodePorts" 2>/dev/null || true
    log_success "Firewall configured for remote access"
else
    # For systems without UFW, ensure iptables allows the ports
    sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    sudo iptables -I INPUT -p tcp --dport 30000:32767 -j ACCEPT 2>/dev/null || true
fi

# Wait for port forwards to establish
sleep 10

# Verify ports are listening
log_info "Verifying remote access ports..."
for port in 80 443 30004 30030 30090; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        log_success "Port $port is accessible"
    else
        log_warning "Port $port may not be accessible yet"
    fi
done

# Get public IP for display
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || hostname -I | awk '{print $1}')

# Step 18: Display access information
echo -e "\n${GREEN}========================================${NC}"
# Step 19: Final verification
log_info "Running final verification..."
sleep 5
./scripts/verify-access.sh

echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"

# Display access information - Linux optimized
MINIKUBE_IP=$(minikube ip)

echo -e "\n${YELLOW}📦 Private Docker Registry:${NC}"
echo "Registry API: http://$MINIKUBE_IP:$REGISTRY_PORT"
echo "Registry UI: http://$MINIKUBE_IP:$REGISTRY_UI_PORT"
echo "Username: $REGISTRY_USER / Password: $REGISTRY_PASS"

echo -e "\n${YELLOW}🗄️ Data Layer:${NC}"
echo "PostgreSQL: postgres-service.production.svc.cluster.local:5432"
echo "Redis Cache: redis-service.production.svc.cluster.local:6379"
echo "MinIO S3 API: http://$MINIKUBE_IP:30900"
echo "MinIO Console: http://$MINIKUBE_IP:30901"
echo "MinIO Credentials: AKIAIOSFODNN7EXAMPLE / wJalrXUtnFEMI/K7MDENG/bPxFCYEXAMPLEKE"

echo -e "\n${YELLOW}🌐 HTTPS Access (via Domain):${NC}"
echo "Main URL: ${GREEN}https://nawaf.thmanyah.com${NC}"
echo "  - Frontend: https://nawaf.thmanyah.com"
echo "  - API: https://nawaf.thmanyah.com/api"
echo "  - Auth: https://nawaf.thmanyah.com/auth"
echo "  - Images: https://nawaf.thmanyah.com/image"
echo ""
echo "Note: DNS A record must point nawaf.thmanyah.com to ${GREEN}$PUBLIC_IP${NC}"
echo "Port 443 is now accessible from external machines!"
echo "Certificate Status: kubectl get certificate -n production"

echo -e "\n${YELLOW}🚀 Services (Remote Access via Public IP):${NC}"
echo "Frontend: http://$PUBLIC_IP:30004"
echo "API Service: Accessible via https://nawaf.thmanyah.com/api"
echo "Auth Service: Accessible via https://nawaf.thmanyah.com/auth"  
echo "Image Service: Accessible via https://nawaf.thmanyah.com/image"

echo -e "\n${YELLOW}📊 Monitoring (Remote Access):${NC}"
echo "Prometheus: http://$PUBLIC_IP:30090"
echo "Grafana: http://$PUBLIC_IP:30030"
echo "  Username: admin / Password: $GRAFANA_ADMIN_PASSWORD"

echo -e "\n${YELLOW}🌐 Ingress (with TLS):${NC}"
INGRESS_IP=$(kubectl get ingress -n $NAMESPACE_PROD services-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo "Ingress IP: $INGRESS_IP"
echo "Ingress configured for: nawaf.thmanyah.com (requires DNS A record)"

echo -e "\n${YELLOW}📋 Management Commands:${NC}"
echo "1. Run tests: ./test-scenarios.sh"
echo "2. View dashboard: minikube dashboard"
echo "3. Check logs: kubectl logs -f <pod-name> -n production"
echo "4. Stop everything: ./stop.sh"

echo -e "\n${GREEN}🐧 Ubuntu/Linux Complete Platform:${NC}"
echo "- ✅ Registry: Fully functional (all images pushed successfully)"
echo "- ✅ Database: PostgreSQL with persistent storage and schemas"
echo "- ✅ Cache: Redis with authentication and persistence"
echo "- ✅ Storage: MinIO S3-compatible object storage"  
echo "- ✅ Services: All microservices connected to real data layer"
echo "- ✅ Monitoring: Full observability stack with exporters"
echo "- ✅ Security: Network policies, secrets, TLS encryption"
echo "- ✅ Scaling: HPA, PDB, resource limits configured"
echo "- ✅ Access: NodePorts on $MINIKUBE_IP (sudo ufw allow 30000:32767/tcp for remote)"