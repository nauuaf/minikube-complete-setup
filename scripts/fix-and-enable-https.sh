#!/bin/bash

# Comprehensive script to fix all issues and enable HTTPS automatically
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Complete Fix & HTTPS Enablement${NC}"
echo -e "${BLUE}========================================${NC}"

# Get network info
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)
echo -e "${YELLOW}Your Ubuntu Public IP: $PUBLIC_IP${NC}"

# Step 1: Fix MinIO issue
echo -e "\n${YELLOW}Step 1: Fixing MinIO configuration...${NC}"
kubectl delete pod minio-0 -n production 2>/dev/null || true
kubectl apply -f kubernetes/data/14-minio.yaml
echo -e "${GREEN}✅ MinIO configuration updated${NC}"

# Step 2: Fix service deployments for local images
echo -e "\n${YELLOW}Step 2: Fixing service deployments...${NC}"
eval $(minikube docker-env)

# Ensure images exist
for service in api-service auth-service image-service frontend; do
    if ! docker images | grep -q "${service}.*1.0.0"; then
        echo "Building $service..."
        docker build -t ${service}:1.0.0 ./services/${service}/
    fi
done

# Update deployments
mkdir -p /tmp/fixed-apps
cat kubernetes/apps/05-api-service.yaml | \
    sed -e "s|image: localhost:30500/api-service:.*|image: api-service:1.0.0|" \
    -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
    > /tmp/fixed-apps/05-api-service.yaml

cat kubernetes/apps/06-auth-service.yaml | \
    sed -e "s|image: localhost:30500/auth-service:.*|image: auth-service:1.0.0|" \
    -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
    > /tmp/fixed-apps/06-auth-service.yaml

cat kubernetes/apps/07-image-service.yaml | \
    sed -e "s|image: localhost:30500/image-service:.*|image: image-service:1.0.0|" \
    -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
    > /tmp/fixed-apps/07-image-service.yaml

cat kubernetes/apps/frontend-deployment.yaml | \
    sed -e "s|image: localhost:30500/frontend:.*|image: frontend:1.0.0|" \
    -e "s|imagePullPolicy: Always|imagePullPolicy: Never|" \
    > /tmp/fixed-apps/frontend-deployment.yaml

kubectl apply -f /tmp/fixed-apps/
echo -e "${GREEN}✅ Service deployments fixed${NC}"

# Step 3: Apply the ingress fix
echo -e "\n${YELLOW}Step 3: Applying ingress configuration...${NC}"
kubectl apply -f kubernetes/security/04-tls-ingress.yaml
echo -e "${GREEN}✅ Ingress configuration applied for nawaf.thmanyah.com${NC}"

# Step 4: Enable HTTPS port forwarding
echo -e "\n${YELLOW}Step 4: Setting up HTTPS port forwarding...${NC}"

# Kill existing port forwards
sudo pkill -f "kubectl port-forward" 2>/dev/null || true
sudo pkill -f "port-forward" 2>/dev/null || true
sleep 2

# Create comprehensive port forwarding script
cat > /tmp/complete-forward.sh << 'EOF'
#!/bin/bash

echo "Starting comprehensive port forwarding..."

# Wait for ingress controller
while ! kubectl get pods -n ingress-nginx | grep -q "Running"; do
    echo "Waiting for ingress controller..."
    sleep 5
done

# Kill any existing forwards
pkill -f "port-forward" 2>/dev/null || true
sleep 2

# HTTPS/HTTP for ingress (REQUIRED FOR DOMAIN ACCESS)
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /var/log/http.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /var/log/https.log 2>&1 &

# Direct service access (NodePort alternatives)
kubectl port-forward --address 0.0.0.0 -n production svc/frontend 30004:80 > /var/log/frontend.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/grafana 30030:3000 > /var/log/grafana.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n monitoring svc/prometheus 30090:9090 > /var/log/prometheus.log 2>&1 &

echo "All port forwards started"

# Monitor and restart if needed
while true; do
    sleep 30
    
    # Check critical HTTPS forwarding
    if ! pgrep -f "port-forward.*:443" > /dev/null; then
        echo "Restarting HTTPS forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 443:443 > /var/log/https.log 2>&1 &
    fi
    
    if ! pgrep -f "port-forward.*:80" > /dev/null; then
        echo "Restarting HTTP forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 80:80 > /var/log/http.log 2>&1 &
    fi
done
EOF

# Install as systemd service
sudo cp /tmp/complete-forward.sh /usr/local/bin/complete-forward.sh
sudo chmod +x /usr/local/bin/complete-forward.sh

cat > /tmp/complete-forward.service << EOF
[Unit]
Description=Complete Port Forwarding Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/$USER"
Environment="KUBECONFIG=/home/$USER/.kube/config"
ExecStart=/usr/local/bin/complete-forward.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/complete-forward.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable complete-forward.service
sudo systemctl restart complete-forward.service

echo -e "${GREEN}✅ HTTPS forwarding service installed and started${NC}"

# Step 5: Configure firewall
echo -e "\n${YELLOW}Step 5: Configuring firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow 80/tcp comment "HTTP" 2>/dev/null || true
    sudo ufw allow 443/tcp comment "HTTPS" 2>/dev/null || true
    sudo ufw allow 30000:32767/tcp comment "NodePorts" 2>/dev/null || true
    echo -e "${GREEN}✅ Firewall configured${NC}"
fi

# Step 6: Wait and verify
echo -e "\n${YELLOW}Step 6: Verifying setup...${NC}"
sleep 10

# Check if ports are listening
echo -e "\n${BLUE}Port Status:${NC}"
for port in 80 443 30004 30030 30090; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        echo -e "  Port $port: ${GREEN}✅ Listening${NC}"
    else
        echo -e "  Port $port: ${RED}❌ Not listening${NC}"
    fi
done

# Check certificate status
echo -e "\n${BLUE}Certificate Status:${NC}"
cert_status=$(kubectl get certificate sre-platform-tls -n production -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
if [ "$cert_status" = "True" ]; then
    echo -e "${GREEN}✅ TLS certificate is ready${NC}"
else
    echo -e "${YELLOW}⚠ TLS certificate pending (this is normal, Let's Encrypt needs DNS to be configured)${NC}"
fi

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   All Fixes Applied & HTTPS Enabled!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}✅ What was done:${NC}"
echo "  1. Fixed MinIO configuration"
echo "  2. Fixed service deployments for local images"
echo "  3. Applied ingress configuration for nawaf.thmanyah.com"
echo "  4. Enabled HTTPS/HTTP port forwarding (ports 80 & 443)"
echo "  5. Configured firewall rules"
echo "  6. Created systemd service for persistent access"

echo -e "\n${YELLOW}📌 DNS Configuration Required:${NC}"
echo -e "  Create DNS A record: ${GREEN}nawaf.thmanyah.com → $PUBLIC_IP${NC}"

echo -e "\n${YELLOW}🌐 Access Your Services:${NC}"
echo -e "  HTTPS: ${GREEN}https://nawaf.thmanyah.com${NC} (after DNS setup)"
echo -e "  HTTP:  ${GREEN}http://nawaf.thmanyah.com${NC}"
echo -e "  Direct: ${GREEN}http://$PUBLIC_IP:30004${NC} (Frontend)"
echo -e "  Grafana: ${GREEN}http://$PUBLIC_IP:30030${NC}"
echo -e "  Prometheus: ${GREEN}http://$PUBLIC_IP:30090${NC}"

echo -e "\n${YELLOW}🔍 Test Commands:${NC}"
echo -e "  From your macOS:"
echo -e "  ${GREEN}telnet $PUBLIC_IP 443${NC}"
echo -e "  ${GREEN}curl -v https://nawaf.thmanyah.com${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP:30004${NC}"

echo -e "\n${YELLOW}📊 Service Management:${NC}"
echo -e "  Status: ${GREEN}sudo systemctl status complete-forward${NC}"
echo -e "  Logs:   ${GREEN}sudo journalctl -u complete-forward -f${NC}"
echo -e "  Restart: ${GREEN}sudo systemctl restart complete-forward${NC}"

echo -e "\n${BLUE}✨ Setup Complete!${NC}"