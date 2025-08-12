#!/bin/bash

source config/config.env

echo "🏥 Running Health Checks..."

# Function to test service with proper port forwarding
test_service_health() {
    local service=$1
    local namespace=$2
    local service_port=$3
    local health_path=$4
    local local_port=$((8000 + RANDOM % 1000))  # Use random high port to avoid conflicts
    
    echo "⏳ Testing $service health..."
    
    # Always use port-forward for reliable access
    kubectl port-forward --address=127.0.0.1 svc/$service $local_port:$service_port -n $namespace > /dev/null 2>&1 &
    PF_PID=$!
    
    # Wait for port-forward to establish
    sleep 3
    
    # Test the health endpoint with multiple attempts
    local attempts=0
    local max_attempts=5
    local success=false
    
    while [ $attempts -lt $max_attempts ]; do
        if curl -s --connect-timeout 5 --max-time 10 "http://localhost:$local_port$health_path" | grep -q "healthy\|Prometheus\|ok\|status.*200"; then
            echo "✅ $service is healthy"
            success=true
            break
        fi
        attempts=$((attempts + 1))
        [ $attempts -lt $max_attempts ] && sleep 2
    done
    
    if [ "$success" = false ]; then
        echo "❌ $service health check failed"
        # Debug information
        echo "   Attempted URL: http://localhost:$local_port$health_path"
        echo "   Response: $(curl -s --connect-timeout 2 --max-time 5 "http://localhost:$local_port$health_path" 2>/dev/null | head -c 100 || echo 'No response')"
    fi
    
    # Cleanup port-forward
    kill $PF_PID 2>/dev/null || true
    sleep 1
}

# Check application services  
test_service_health "api-service" "$NAMESPACE_PROD" "3000" "/health"
test_service_health "auth-service" "$NAMESPACE_PROD" "8080" "/health" 
test_service_health "image-service" "$NAMESPACE_PROD" "5000" "/health"

# Check monitoring
test_service_health "prometheus" "$NAMESPACE_MONITORING" "9090" "/-/healthy"

echo "✅ Health checks complete"