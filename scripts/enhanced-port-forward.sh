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
