#!/bin/bash

# Fix ingress access for ports 80 and 443
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing Ingress Access (80/443)${NC}"
echo -e "${BLUE}========================================${NC}"

# Check what ingress services are available
echo -e "${YELLOW}Checking ingress controller services...${NC}"
kubectl get svc -n ingress-nginx

# Get the correct ingress service name
INGRESS_SVC=$(kubectl get svc -n ingress-nginx --no-headers | grep controller | awk '{print $1}' | head -1)

if [ -z "$INGRESS_SVC" ]; then
    echo -e "${RED}❌ No ingress controller service found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Found ingress service: $INGRESS_SVC${NC}"

# Stop existing port forwards
echo -e "\n${YELLOW}Stopping existing port forwards...${NC}"
pkill -f "port-forward.*:80" 2>/dev/null || true
pkill -f "port-forward.*:443" 2>/dev/null || true
sleep 3

# Check if ingress controller pods are running
echo -e "\n${YELLOW}Checking ingress controller pods...${NC}"
kubectl get pods -n ingress-nginx

if ! kubectl get pods -n ingress-nginx | grep -q "Running.*1/1"; then
    echo -e "${RED}❌ Ingress controller pods not fully ready${NC}"
    echo -e "${YELLOW}Waiting for ingress controller...${NC}"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=120s || {
        echo -e "${RED}❌ Ingress controller failed to become ready${NC}"
        exit 1
    }
fi

echo -e "${GREEN}✅ Ingress controller is ready${NC}"

# Start port forwards with correct service name
echo -e "\n${YELLOW}Starting HTTP/HTTPS port forwards...${NC}"

# Start HTTP (port 80)
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/$INGRESS_SVC 80:80 > /tmp/http-forward.log 2>&1 &
HTTP_PID=$!
echo "HTTP forward PID: $HTTP_PID"

# Start HTTPS (port 443)
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/$INGRESS_SVC 443:443 > /tmp/https-forward.log 2>&1 &
HTTPS_PID=$!
echo "HTTPS forward PID: $HTTPS_PID"

# Wait for forwards to establish
echo -e "\n${YELLOW}Waiting for port forwards to establish...${NC}"
sleep 5

# Verify ports are listening
echo -e "\n${BLUE}Verifying port status:${NC}"
for port in 80 443; do
    if netstat -tlnp 2>/dev/null | grep -q ":$port.*0.0.0.0"; then
        echo -e "  Port $port: ${GREEN}✅ Listening on all interfaces${NC}"
    else
        echo -e "  Port $port: ${RED}❌ Not accessible${NC}"
        # Show what's actually listening on this port
        netstat -tlnp 2>/dev/null | grep ":$port" || echo "    No process listening on port $port"
    fi
done

# Test local HTTP access with Host header
echo -e "\n${BLUE}Testing local HTTP access:${NC}"
if curl -s -H "Host: nawaf.thmanyah.com" --connect-timeout 5 --max-time 10 "http://localhost" >/dev/null 2>&1; then
    echo -e "  HTTP: ${GREEN}✅ Working${NC}"
else
    echo -e "  HTTP: ${RED}❌ Failed${NC}"
    echo "  Trying without Host header..."
    if curl -s --connect-timeout 5 --max-time 10 "http://localhost" >/dev/null 2>&1; then
        echo -e "  HTTP (no host): ${GREEN}✅ Working${NC}"
    else
        echo -e "  HTTP (no host): ${RED}❌ Failed${NC}"
        echo "  HTTP Error: $(curl -s --connect-timeout 2 --max-time 5 "http://localhost" 2>&1 | head -c 100)"
    fi
fi

# Check log files for issues
echo -e "\n${BLUE}Checking port forward logs:${NC}"
if [ -s /tmp/http-forward.log ]; then
    echo -e "  HTTP log (last 3 lines):"
    tail -3 /tmp/http-forward.log
fi
if [ -s /tmp/https-forward.log ]; then
    echo -e "  HTTPS log (last 3 lines):"
    tail -3 /tmp/https-forward.log
fi

# Create a permanent systemd service for HTTP/HTTPS access
echo -e "\n${YELLOW}Creating permanent HTTP/HTTPS forwarding service...${NC}"

cat > /tmp/ingress-forward.sh << EOF
#!/bin/bash

# Wait for ingress controller to be ready
while ! kubectl get pods -n ingress-nginx | grep -q "Running.*1/1"; do
    echo "Waiting for ingress controller..."
    sleep 5
done

# Get ingress service name
INGRESS_SVC=\$(kubectl get svc -n ingress-nginx --no-headers | grep controller | awk '{print \$1}' | head -1)

if [ -z "\$INGRESS_SVC" ]; then
    echo "ERROR: No ingress service found"
    exit 1
fi

echo "Starting HTTP/HTTPS forwarding for service: \$INGRESS_SVC"

# Kill existing forwards
pkill -f "port-forward.*:80" 2>/dev/null || true
pkill -f "port-forward.*:443" 2>/dev/null || true
sleep 2

# Start forwards
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/\$INGRESS_SVC 80:80 > /tmp/sre-logs/http-perm.log 2>&1 &
kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/\$INGRESS_SVC 443:443 > /tmp/sre-logs/https-perm.log 2>&1 &

echo "HTTP/HTTPS forwarding started"

# Monitor and restart if needed
while true; do
    sleep 30
    if ! pgrep -f "port-forward.*:80" > /dev/null; then
        echo "Restarting HTTP forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/\$INGRESS_SVC 80:80 > /tmp/sre-logs/http-perm.log 2>&1 &
    fi
    if ! pgrep -f "port-forward.*:443" > /dev/null; then
        echo "Restarting HTTPS forward..."
        kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/\$INGRESS_SVC 443:443 > /tmp/sre-logs/https-perm.log 2>&1 &
    fi
done
EOF

# Install the service
sudo cp /tmp/ingress-forward.sh /usr/local/bin/ingress-forward.sh
sudo chmod +x /usr/local/bin/ingress-forward.sh

cat > /tmp/ingress-forward.service << EOF
[Unit]
Description=Ingress HTTP/HTTPS Port Forwarding
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=$USER
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/$USER"
Environment="KUBECONFIG=/home/$USER/.kube/config"
ExecStart=/usr/local/bin/ingress-forward.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo cp /tmp/ingress-forward.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ingress-forward.service
sudo systemctl stop ingress-forward.service 2>/dev/null || true
sudo systemctl start ingress-forward.service

echo -e "${GREEN}✅ Permanent ingress forwarding service created${NC}"

# Get public IP for final testing instructions
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s http://ipinfo.io/ip)

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Ingress Access Fixed!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Current Status:${NC}"
echo "  HTTP processes: $(pgrep -f "port-forward.*:80" | wc -l)"
echo "  HTTPS processes: $(pgrep -f "port-forward.*:443" | wc -l)"

echo -e "\n${YELLOW}Test from your macOS machine:${NC}"
echo -e "  ${GREEN}curl http://$PUBLIC_IP${NC}"
echo -e "  ${GREEN}curl https://$PUBLIC_IP${NC} (may show cert error - normal)"
echo -e "  ${GREEN}curl -H \"Host: nawaf.thmanyah.com\" http://$PUBLIC_IP${NC}"

echo -e "\n${YELLOW}Service Management:${NC}"
echo -e "  Status: ${GREEN}sudo systemctl status ingress-forward${NC}"
echo -e "  Logs:   ${GREEN}sudo journalctl -u ingress-forward -f${NC}"
echo -e "  Manual: ${GREEN}kill $HTTP_PID $HTTPS_PID${NC}"

echo -e "\n${BLUE}Note: Configure DNS first for full HTTPS:${NC}"
echo -e "  Create A record: nawaf.thmanyah.com → $PUBLIC_IP"