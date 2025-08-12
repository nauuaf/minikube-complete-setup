#!/bin/bash

source config/config.env

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏥 Running Comprehensive Health Checks...${NC}"

# First check if pods are actually running
echo -e "\n${YELLOW}📋 Pod Status Check:${NC}"
echo "Checking if pods are running..."
kubectl get pods -n production --no-headers | while read line; do
    pod_name=$(echo $line | awk '{print $1}')
    pod_status=$(echo $line | awk '{print $3}')
    ready=$(echo $line | awk '{print $2}')
    
    if [[ "$pod_status" == "Running" ]]; then
        echo -e "  $pod_name: ${GREEN}✅ $pod_status ($ready ready)${NC}"
    else
        echo -e "  $pod_name: ${RED}❌ $pod_status ($ready ready)${NC}"
        
        # Show more details for failed pods
        echo "    Debugging $pod_name:"
        kubectl describe pod $pod_name -n production | grep -A5 -B5 "Events\|State\|Ready" || true
    fi
done

# Function to test service with proper port forwarding
test_service_health() {
    local service=$1
    local namespace=$2
    local service_port=$3
    local health_path=$4
    local local_port=$((8000 + RANDOM % 1000))  # Use random high port to avoid conflicts
    
    echo -e "\n${YELLOW}⏳ Testing $service health...${NC}"
    
    # Check if service exists first
    if ! kubectl get svc $service -n $namespace > /dev/null 2>&1; then
        echo -e "  ${RED}❌ Service $service not found in namespace $namespace${NC}"
        return 1
    fi
    
    # Check if pods are running
    local running_pods=$(kubectl get pods -n $namespace -l app=$service --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$running_pods" -eq 0 ]; then
        echo -e "  ${RED}❌ No running pods found for $service${NC}"
        kubectl get pods -n $namespace -l app=$service
        return 1
    fi
    
    echo "  📍 Found $running_pods running pod(s) for $service"
    
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
        local response=$(curl -s --connect-timeout 5 --max-time 10 "http://localhost:$local_port$health_path" 2>/dev/null)
        if echo "$response" | grep -q "healthy\|Prometheus\|ok\|status.*200\|\"status\": \"healthy\""; then
            echo -e "  ${GREEN}✅ $service is healthy${NC}"
            echo "    Response: $(echo "$response" | jq -c . 2>/dev/null || echo "$response" | head -c 50)..."
            success=true
            break
        fi
        attempts=$((attempts + 1))
        if [ $attempts -lt $max_attempts ]; then
            echo "    Attempt $attempts/$max_attempts failed, retrying..."
            sleep 2
        fi
    done
    
    if [ "$success" = false ]; then
        echo -e "  ${RED}❌ $service health check failed${NC}"
        # Debug information
        echo "    URL: http://localhost:$local_port$health_path"
        echo "    Response: $(curl -s --connect-timeout 2 --max-time 5 "http://localhost:$local_port$health_path" 2>/dev/null | head -c 100 || echo 'No response')"
        
        # Try to get more debugging info
        echo "    Pod logs (last 5 lines):"
        kubectl logs -l app=$service -n $namespace --tail=5 | head -10
    fi
    
    # Cleanup port-forward
    kill $PF_PID 2>/dev/null || true
    sleep 1
    
    return $( [ "$success" = true ] && echo 0 || echo 1 )
}

# Check application services  
failed_services=0
total_services=0

echo -e "\n${BLUE}🔍 Testing Application Services...${NC}"

((total_services++))
if ! test_service_health "api-service" "$NAMESPACE_PROD" "3000" "/health"; then
    ((failed_services++))
fi

((total_services++))
if ! test_service_health "auth-service" "$NAMESPACE_PROD" "8080" "/health"; then
    ((failed_services++))
fi

((total_services++))
if ! test_service_health "image-service" "$NAMESPACE_PROD" "5000" "/health"; then
    ((failed_services++))
fi

echo -e "\n${BLUE}🔍 Testing Monitoring Services...${NC}"
((total_services++))
if ! test_service_health "prometheus" "$NAMESPACE_MONITORING" "9090" "/-/healthy"; then
    ((failed_services++))
fi

# Summary
echo -e "\n${BLUE}========================================${NC}"
if [ $failed_services -eq 0 ]; then
    echo -e "${GREEN}✅ All health checks passed! ($total_services/$total_services services healthy)${NC}"
else
    echo -e "${RED}❌ Health checks failed: $failed_services/$total_services services unhealthy${NC}"
    echo -e "${YELLOW}Suggested actions:${NC}"
    echo -e "  1. Check pod logs: kubectl logs -l app=<service-name> -n production"
    echo -e "  2. Check service events: kubectl describe svc <service-name> -n production"
    echo -e "  3. Restart failed pods: kubectl delete pods -l app=<service-name> -n production"
    echo -e "  4. Check secrets: kubectl get secrets -n production"
fi
echo -e "${BLUE}========================================${NC}"

exit $failed_services