#!/bin/bash

source config/config.env

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🏥 Running Comprehensive Health Checks...${NC}"

# First check if pods are actually running and ready
echo -e "\n${YELLOW}📋 Pod Status Check:${NC}"
echo "Checking pod readiness (not just phase)..."

# Use a more robust check that properly parses ready/total containers
failed_pods=0
total_pods=0

kubectl get pods -n production --no-headers | while read line; do
    pod_name=$(echo $line | awk '{print $1}')
    pod_status=$(echo $line | awk '{print $3}')
    ready_status=$(echo $line | awk '{print $2}')
    
    # Parse ready containers (e.g., "1/1", "0/2")
    ready_count=$(echo $ready_status | cut -d'/' -f1)
    total_count=$(echo $ready_status | cut -d'/' -f2)
    
    ((total_pods++))
    
    if [[ "$pod_status" == "Running" ]] && [[ "$ready_count" == "$total_count" ]] && [[ "$ready_count" -gt 0 ]]; then
        echo -e "  $pod_name: ${GREEN}✅ Ready ($ready_status containers)${NC}"
    elif [[ "$pod_status" == "Running" ]]; then
        echo -e "  $pod_name: ${YELLOW}⚠️  Running but not ready ($ready_status containers)${NC}"
        ((failed_pods++))
        
        # Show container status details
        echo "    Container status:"
        kubectl get pod $pod_name -n production -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.ready}{"\n"}{end}' | sed 's/^/      /'
    else
        echo -e "  $pod_name: ${RED}❌ $pod_status ($ready_status containers)${NC}"
        ((failed_pods++))
        
        # Show more details for failed pods
        echo "    Recent events:"
        kubectl get events --field-selector involvedObject.name=$pod_name -n production --sort-by='.lastTimestamp' | tail -3 | sed 's/^/      /' || true
    fi
done

if [ $failed_pods -gt 0 ]; then
    echo -e "\n${RED}⚠️  $failed_pods out of $total_pods pods are not ready${NC}"
else
    echo -e "\n${GREEN}✅ All $total_pods pods are running and ready${NC}"
fi

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
    
    # Check if pods are running AND ready (not just running)
    local ready_pods=$(kubectl get pods -n $namespace -l app=$service -o jsonpath='{range .items[*]}{.status.phase},{.metadata.name},{range .status.containerStatuses[*]}{.ready},{end}{"\n"}{end}' 2>/dev/null | grep "^Running," | grep -c "true," | tr -d ' ')
    local total_pods=$(kubectl get pods -n $namespace -l app=$service --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$total_pods" -eq 0 ]; then
        echo -e "  ${RED}❌ No pods found for $service${NC}"
        return 1
    elif [ "$ready_pods" -eq 0 ]; then
        echo -e "  ${RED}❌ No ready pods found for $service (found $total_pods total pods)${NC}"
        kubectl get pods -n $namespace -l app=$service -o wide
        echo "    Pod readiness details:"
        kubectl get pods -n $namespace -l app=$service -o jsonpath='{range .items[*]}{.metadata.name}: {range .status.containerStatuses[*]}{.name}={.ready} {end}{"\n"}{end}' | sed 's/^/      /'
        return 1
    fi
    
    echo "  📍 Found $ready_pods ready pod(s) for $service (out of $total_pods total)"
    
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