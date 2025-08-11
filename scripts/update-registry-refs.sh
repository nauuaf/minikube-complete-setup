#!/bin/bash

# Update Kubernetes manifests with correct registry references
# This script dynamically updates image references based on the registry URL

source config/config.env

MINIKUBE_IP=$(minikube ip)
REGISTRY_HOST="$MINIKUBE_IP:$REGISTRY_PORT"

echo "Updating Kubernetes manifests with registry: $REGISTRY_HOST"

# Create temporary directory for updated manifests
mkdir -p /tmp/updated-apps

# Update API Service
sed "s|localhost:30500/|$REGISTRY_HOST/|g" kubernetes/apps/05-api-service.yaml > /tmp/updated-apps/05-api-service.yaml

# Update Auth Service  
sed "s|localhost:30500/|$REGISTRY_HOST/|g" kubernetes/apps/06-auth-service.yaml > /tmp/updated-apps/06-auth-service.yaml

# Update Image Service
sed "s|localhost:30500/|$REGISTRY_HOST/|g" kubernetes/apps/07-image-service.yaml > /tmp/updated-apps/07-image-service.yaml

# Update Frontend Service
sed "s|localhost:30500/|$REGISTRY_HOST/|g" kubernetes/apps/frontend-deployment.yaml > /tmp/updated-apps/frontend-deployment.yaml

# Copy other files as-is
cp kubernetes/apps/08-*.yaml /tmp/updated-apps/ 2>/dev/null || true
cp kubernetes/apps/09-*.yaml /tmp/updated-apps/ 2>/dev/null || true

echo "Manifests updated successfully in /tmp/updated-apps/"