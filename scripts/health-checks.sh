#!/bin/bash

source config/config.env

echo "🏥 Running Health Checks..."

# Function to test service with timeout and fallback
test_service_health() {
    local service=$1
    local namespace=$2
    local port=$3
    local health_path=$4
    
    # Try minikube service with timeout
    URL=$(timeout 5 minikube service $service -n $namespace --url 2>/dev/null || echo "TIMEOUT")
    
    if [[ "$URL" == "TIMEOUT" || -z "$URL" ]]; then
        echo "⏳ Using port-forward for $service health check..."
        kubectl port-forward --address=127.0.0.1 svc/$service $port:$port -n $namespace > /dev/null 2>&1 &
        PF_PID=$!
        sleep 2
        URL="http://localhost:$port"
    fi
    
    # Test the health endpoint
    if curl -s --max-time 10 $URL$health_path | grep -q "healthy\|Prometheus\|ok"; then
        echo "✅ $service is healthy"
    else
        echo "❌ $service health check failed"
    fi
    
    # Cleanup port-forward if used
    [[ -n "${PF_PID:-}" ]] && kill $PF_PID 2>/dev/null || true
    unset PF_PID
}

# Check application services  
test_service_health "api-service" "$NAMESPACE_PROD" "3000" "/health"
test_service_health "auth-service" "$NAMESPACE_PROD" "8080" "/health" 
test_service_health "image-service" "$NAMESPACE_PROD" "5000" "/health"

# Check monitoring
test_service_health "prometheus" "$NAMESPACE_MONITORING" "9090" "/-/healthy"

echo "✅ Health checks complete"