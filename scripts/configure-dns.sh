#!/bin/bash

# DNS Configuration Script for SRE Platform
# This script helps configure DNS and TLS for the platform

set -e

DOMAIN=${1:-""}
SERVER_IP=${2:-""}

if [[ -z "$DOMAIN" || -z "$SERVER_IP" ]]; then
    echo "Usage: $0 <domain> <server-ip>"
    echo "Example: $0 nawaf.thmanyah.com 54.123.456.789"
    echo ""
    echo "For temporary testing with /etc/hosts:"
    echo "$0 nawaf.thmanyah.com \$(curl -s ifconfig.me)"
    exit 1
fi

echo "🌐 Configuring DNS for SRE Platform"
echo "Domain: $DOMAIN"
echo "Server IP: $SERVER_IP"
echo ""

# Update TLS configuration with the provided domain
echo "📝 Updating TLS configuration..."
sed -i.bak "s/nawaf\.thmanyah\.com/$DOMAIN/g" kubernetes/security/04-tls-ingress.yaml

# Update email for Let's Encrypt
ADMIN_EMAIL="admin@$(echo $DOMAIN | cut -d. -f2-)"
sed -i.bak "s/admin@nawaf\.thmanyah\.com/$ADMIN_EMAIL/g" kubernetes/security/04-tls-ingress.yaml

echo "✅ Updated kubernetes/security/04-tls-ingress.yaml"
echo "   - Domain: $DOMAIN"  
echo "   - Email: $ADMIN_EMAIL"
echo ""

# For local testing, add to /etc/hosts
if [[ "$DOMAIN" == *".example.com" ]]; then
    echo "🏠 Adding local DNS entry to /etc/hosts..."
    if grep -q "$DOMAIN" /etc/hosts; then
        sudo sed -i.bak "s/.*$DOMAIN.*/$SERVER_IP $DOMAIN/" /etc/hosts
    else
        echo "$SERVER_IP $DOMAIN" | sudo tee -a /etc/hosts
    fi
    echo "✅ Added $SERVER_IP $DOMAIN to /etc/hosts"
    echo ""
fi

# Instructions for production DNS
if [[ "$DOMAIN" != *".example.com" ]]; then
    echo "🌍 Production DNS Configuration Required:"
    echo "   Add this A record to your DNS provider:"
    echo "   Name: $(echo $DOMAIN | cut -d. -f1)"
    echo "   Type: A" 
    echo "   Value: $SERVER_IP"
    echo "   TTL: 300 (5 minutes)"
    echo ""
    echo "   Wait for DNS propagation (5-15 minutes), then test:"
    echo "   nslookup $DOMAIN"
    echo ""
fi

echo "🚀 Next steps:"
echo "1. Ensure cert-manager is installed:"
echo "   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml"
echo ""
echo "2. Ensure nginx-ingress is installed:"
echo "   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml"
echo ""
echo "3. Apply TLS configuration:"
echo "   kubectl apply -f kubernetes/security/04-tls-ingress.yaml"
echo ""
echo "4. Check certificate status:"
echo "   kubectl get certificate -n production"
echo ""
echo "5. Access your platform:"
echo "   https://$DOMAIN"
echo ""
echo "🌐 Default domain configured: nawaf.thmanyah.com"
echo ""
echo "🔒 Let's Encrypt will automatically provision your SSL certificate!"