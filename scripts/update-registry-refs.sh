#!/bin/bash

# Update Kubernetes manifests with correct registry references
# This script dynamically updates image references based on the registry URL

source config/config.env

# Use the correct registry address for Kubernetes pods
# From inside the cluster, pods should access the registry service directly
CLUSTER_REGISTRY_HOST="docker-registry.default.svc.cluster.local:5000"
MINIKUBE_IP=$(minikube ip)
HOST_REGISTRY_HOST="$MINIKUBE_IP:$REGISTRY_PORT"

echo "Updating Kubernetes manifests with cluster registry: $CLUSTER_REGISTRY_HOST"

# Create temporary directory for updated manifests
mkdir -p /tmp/updated-apps

# Check if we should use local images (when registry is not available)
if [ "${USE_LOCAL_IMAGES:-false}" = "true" ]; then
    echo "Using local images (registry unavailable)"
    # Remove registry prefix and set imagePullPolicy to Never
    sed -e "s|localhost:30500/||g" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|g" \
        kubernetes/apps/05-api-service.yaml > /tmp/updated-apps/05-api-service.yaml
    
    sed -e "s|localhost:30500/||g" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|g" \
        kubernetes/apps/06-auth-service.yaml > /tmp/updated-apps/06-auth-service.yaml
    
    sed -e "s|localhost:30500/||g" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|g" \
        kubernetes/apps/07-image-service.yaml > /tmp/updated-apps/07-image-service.yaml
    
    sed -e "s|localhost:30500/||g" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|g" \
        kubernetes/apps/frontend-deployment.yaml > /tmp/updated-apps/frontend-deployment.yaml 2>/dev/null || \
    sed -e "s|localhost:30500/||g" \
        -e "s|imagePullPolicy: Always|imagePullPolicy: Never|g" \
        kubernetes/apps/04-frontend.yaml > /tmp/updated-apps/04-frontend.yaml 2>/dev/null || true
else
    # Update with cluster-internal registry host (what pods see)
    sed "s|localhost:30500/|$CLUSTER_REGISTRY_HOST/|g" kubernetes/apps/05-api-service.yaml > /tmp/updated-apps/05-api-service.yaml
    sed "s|localhost:30500/|$CLUSTER_REGISTRY_HOST/|g" kubernetes/apps/06-auth-service.yaml > /tmp/updated-apps/06-auth-service.yaml
    sed "s|localhost:30500/|$CLUSTER_REGISTRY_HOST/|g" kubernetes/apps/07-image-service.yaml > /tmp/updated-apps/07-image-service.yaml
    
    # Update frontend deployment
    sed "s|localhost:30500/|$CLUSTER_REGISTRY_HOST/|g" kubernetes/apps/frontend-deployment.yaml > /tmp/updated-apps/frontend-deployment.yaml
fi

# Copy other files as-is
cp kubernetes/apps/08-*.yaml /tmp/updated-apps/ 2>/dev/null || true
cp kubernetes/apps/09-*.yaml /tmp/updated-apps/ 2>/dev/null || true

echo "Manifests updated successfully in /tmp/updated-apps/"