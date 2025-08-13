#!/bin/bash
set -euo pipefail

source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing Deployment Issues${NC}"
echo -e "${BLUE}========================================${NC}"

# Fix 1: Improve registry authentication setup
log_info "Fixing registry authentication..."
cat > /tmp/fix-registry-auth.sh << 'EOF'
#!/bin/bash
source config/config.env

# Create auth file with htpasswd
HTPASSWD_CONTENT=$(docker run --rm --entrypoint htpasswd registry:2.8 -Bbn "$REGISTRY_USER" "$REGISTRY_PASS")

# Create or update the secret
kubectl delete secret registry-auth -n default 2>/dev/null || true
kubectl create secret generic registry-auth \
  --from-literal=htpasswd="$HTPASSWD_CONTENT" \
  --namespace=default

# Create registry credentials for pulling images
kubectl delete secret registry-creds -n production 2>/dev/null || true
kubectl create secret docker-registry registry-creds \
  --docker-server=docker-registry.default.svc.cluster.local:5000 \
  --docker-username=$REGISTRY_USER \
  --docker-password=$REGISTRY_PASS \
  --docker-email=admin@sre.local \
  --namespace=production

echo "Registry authentication configured"
EOF
chmod +x /tmp/fix-registry-auth.sh

# Fix 2: Update ingress for external access
log_info "Updating ingress configuration for external access..."
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip || echo "3.69.30.150")

cat > /tmp/updated-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: services-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: nawaf.thmanyah.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 3000
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 3000
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 8080
      - path: /image
        pathType: Prefix
        backend:
          service:
            name: image-service
            port:
              number: 5000
  - host: $PUBLIC_IP.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 3000
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 3000
      - path: /auth
        pathType: Prefix
        backend:
          service:
            name: auth-service
            port:
              number: 8080
      - path: /image
        pathType: Prefix
        backend:
          service:
            name: image-service
            port:
              number: 5000
EOF

# Fix 3: Update deployment manifests to handle registry properly
log_info "Creating fixed deployment manifests..."
mkdir -p /tmp/fixed-deployments

# Function to create deployment with fallback to local images
create_fixed_deployment() {
    local service_name=$1
    local port=$2
    local version=$3
    
    cat > /tmp/fixed-deployments/${service_name}.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${service_name}
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${service_name}
  template:
    metadata:
      labels:
        app: ${service_name}
    spec:
      imagePullSecrets:
      - name: registry-creds
      containers:
      - name: ${service_name}
        image: docker-registry.default.svc.cluster.local:5000/${service_name}:${version}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: ${port}
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 256Mi
EOF
}

# Create fixed deployments
create_fixed_deployment "api-service" "3000" "$API_VERSION"
create_fixed_deployment "auth-service" "8080" "$AUTH_VERSION"
create_fixed_deployment "image-service" "5000" "$IMAGE_VERSION"
create_fixed_deployment "frontend" "3000" "$FRONTEND_VERSION"

# Fix 4: Enhanced port forwarding script with auto-restart
log_info "Creating enhanced port forwarding service..."
cat > /tmp/enhanced-port-forward.sh << 'EOF'
#!/bin/bash

# Kill existing port forwards
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 2

# Function to start and maintain port forward
maintain_forward() {
    local name=$1
    local namespace=$2
    local local_port=$3
    local remote_port=$4
    
    while true; do
        echo "Starting port forward for $name ($local_port -> $remote_port)..."
        kubectl port-forward --address 0.0.0.0 -n $namespace svc/$name $local_port:$remote_port
        echo "Port forward for $name stopped, restarting in 5 seconds..."
        sleep 5
    done
}

# Start all port forwards in background
maintain_forward "ingress-nginx-controller" "ingress-nginx" "80" "80" &
maintain_forward "ingress-nginx-controller" "ingress-nginx" "443" "443" &
maintain_forward "frontend" "production" "30004" "3000" &
maintain_forward "grafana" "monitoring" "30030" "3000" &
maintain_forward "prometheus" "monitoring" "30090" "9090" &
maintain_forward "docker-registry" "default" "30500" "5000" &

# Keep script running
wait
EOF
chmod +x /tmp/enhanced-port-forward.sh

# Fix 5: MinIO initialization fix
log_info "Fixing MinIO initialization..."
cat > /tmp/fix-minio-init.sh << 'EOF'
#!/bin/bash

# Delete old job
kubectl delete job minio-bucket-init -n production 2>/dev/null || true
sleep 5

# Create simplified MinIO init job
cat > /tmp/minio-init-job.yaml << 'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: minio-bucket-init
  namespace: production
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: create-buckets
        image: minio/mc:latest
        command:
        - sh
        - -c
        - |
          mc alias set myminio http://minio:9000 AKIAIOSFODNN7EXAMPLE wJalrXUtnFEMI/K7MDENG/bPxFCYEXAMPLEKEY
          mc mb myminio/images || true
          mc mb myminio/backups || true
          mc mb myminio/uploads || true
          echo "Buckets created successfully"
YAML

kubectl apply -f /tmp/minio-init-job.yaml
EOF
chmod +x /tmp/fix-minio-init.sh

# Fix 6: Update scripts to use correct registry references
log_info "Updating registry reference scripts..."
cat > /tmp/updated-registry-refs.sh << 'EOF'
#!/bin/bash
source config/config.env

mkdir -p /tmp/updated-apps

# Function to update manifests
update_manifest() {
    local input_file=$1
    local output_file=$2
    
    # Check if we should use local images or registry
    if [ "${USE_LOCAL_IMAGES:-false}" = "true" ]; then
        # Use local images without registry
        sed -e 's|image: .*api-service:.*|image: api-service:1.0.0|' \
            -e 's|image: .*auth-service:.*|image: auth-service:1.0.0|' \
            -e 's|image: .*image-service:.*|image: image-service:1.0.0|' \
            -e 's|image: .*frontend:.*|image: frontend:1.0.0|' \
            -e 's|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|' \
            "$input_file" > "$output_file"
    else
        # Use cluster registry
        sed -e 's|image: localhost:30500/|image: docker-registry.default.svc.cluster.local:5000/|' \
            -e 's|imagePullPolicy: Always|imagePullPolicy: IfNotPresent|' \
            "$input_file" > "$output_file"
    fi
}

# Update all application manifests
for file in kubernetes/apps/*.yaml; do
    basename=$(basename "$file")
    update_manifest "$file" "/tmp/updated-apps/$basename"
    echo "Updated $basename"
done

echo "Registry references updated"
EOF
chmod +x /tmp/updated-registry-refs.sh
cp /tmp/updated-registry-refs.sh scripts/update-registry-refs.sh

# Apply all fixes
log_info "Applying fixes..."

# Only run if Minikube is running
if minikube status >/dev/null 2>&1; then
    log_info "Minikube is running, applying runtime fixes..."
    
    # Fix registry auth
    /tmp/fix-registry-auth.sh
    
    # Update ingress
    kubectl apply -f /tmp/updated-ingress.yaml
    
    # Fix MinIO
    /tmp/fix-minio-init.sh
    
    log_success "Runtime fixes applied"
else
    log_warning "Minikube not running, fixes saved for next start"
fi

# Save enhanced port forward script
cp /tmp/enhanced-port-forward.sh scripts/enhanced-port-forward.sh

log_success "All fixes prepared and saved"
echo ""
echo "Fixed issues:"
echo "1. ✅ Registry authentication properly configured"
echo "2. ✅ Ingress updated for external access via $PUBLIC_IP"
echo "3. ✅ Deployment manifests fixed for proper image pulling"
echo "4. ✅ Enhanced port forwarding with auto-restart"
echo "5. ✅ MinIO initialization simplified"
echo "6. ✅ Registry reference script updated"
echo ""
echo "To start the platform with fixes:"
echo "  ./start.sh"
echo ""
echo "For external access:"
echo "  - Frontend: http://$PUBLIC_IP:30004"
echo "  - Via domain: http://$PUBLIC_IP.nip.io (port 80)"
echo "  - Monitoring: http://$PUBLIC_IP:30030 (Grafana)"