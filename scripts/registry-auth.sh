#!/bin/bash

source config/config.env

# Generate htpasswd for registry auth
docker run --rm httpd:2.4-alpine htpasswd -Bbn $REGISTRY_USER $REGISTRY_PASS > /tmp/htpasswd

# Create Kubernetes secret for registry auth
kubectl create secret generic registry-auth \
    --from-file=/tmp/htpasswd \
    --namespace=default \
    --dry-run=client -o yaml | kubectl apply -f -

# Create docker-registry secret for pulling images
kubectl create secret docker-registry registry-creds \
    --docker-server=localhost:$REGISTRY_PORT \
    --docker-username=$REGISTRY_USER \
    --docker-password=$REGISTRY_PASS \
    --namespace=$NAMESPACE_PROD \
    --dry-run=client -o yaml | kubectl apply -f -

rm /tmp/htpasswd
echo "✅ Registry authentication configured"