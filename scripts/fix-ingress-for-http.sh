#!/bin/bash
set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Fixing Ingress for HTTP Access${NC}"
echo -e "${BLUE}========================================${NC}"

# Create HTTP-friendly ingress
log_info "Creating HTTP-friendly ingress..."

cat > /tmp/http-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: services-ingress-http
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
  - http:
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

# Apply the new ingress
kubectl apply -f /tmp/http-ingress.yaml

log_success "HTTP ingress created"

# Test the ingress
log_info "Testing ingress with Host header..."
sleep 5

# Test with Host header
RESPONSE=$(curl -s -H "Host: nawaf.thmanyah.com" http://192.168.49.2:31924 | head -10)
if echo "$RESPONSE" | grep -q "<!doctype html>"; then
    log_success "Ingress is working - frontend is accessible"
else
    log_warning "Ingress may not be working properly"
fi

# Show current ingress status
log_info "Current ingress resources:"
kubectl get ingress -n production

log_success "Ingress fix complete!"