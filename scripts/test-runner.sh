#!/bin/bash

source config/config.env

echo "🧪 Running SRE Test Runner..."

# Function to run load test with port-forward
run_load_test() {
    local service=$1
    local port=$2
    local namespace=$3
    
    echo "Running load test on $service..."
    
    # Use port-forward for reliable connection
    kubectl port-forward --address=127.0.0.1 svc/$service $port:$port -n $namespace > /dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    
    # Run load test
    for i in {1..10}; do
        curl -s http://localhost:$port/health > /dev/null &
    done
    wait
    
    # Cleanup
    kill $PF_PID 2>/dev/null || true
    echo "Load test completed for $service"
}

echo "🔥 Starting load tests..."
run_load_test "api-service" "3000" "$NAMESPACE_PROD" &
run_load_test "auth-service" "8080" "$NAMESPACE_PROD" &  
run_load_test "image-service" "5000" "$NAMESPACE_PROD" &
wait

echo "📊 Checking HPA scaling..."
kubectl get hpa -n $NAMESPACE_PROD

echo "🏥 Final health check..."
./scripts/health-checks.sh

echo "✅ Test runner completed"