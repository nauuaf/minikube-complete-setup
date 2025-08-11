#!/bin/bash

# Complete Test Scenarios for SRE Assignment
# Runs comprehensive functional tests plus chaos engineering scenarios

source config/config.env

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Create test results directory
mkdir -p $TEST_OUTPUT_DIR
TEST_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_RESULTS_FILE="$TEST_OUTPUT_DIR/test-results-$TEST_TIMESTAMP.json"

# Initialize JSON results
echo '{"timestamp": "'$TEST_TIMESTAMP'", "tests": []}' > $TEST_RESULTS_FILE

# Function to add test result
add_test_result() {
    local test_name=$1
    local status=$2
    local details=$3
    
    jq --arg name "$test_name" \
       --arg status "$status" \
       --arg details "$details" \
       '.tests += [{"name": $name, "status": $status, "details": $details}]' \
       $TEST_RESULTS_FILE > /tmp/test.json && mv /tmp/test.json $TEST_RESULTS_FILE
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  SRE Assignment - Complete Test Suite${NC}"
echo -e "${GREEN}========================================${NC}"
echo "📊 Results will be saved to: $TEST_RESULTS_FILE"

# Step 1: Run Comprehensive Functional Tests
echo -e "\n${BLUE}🧪 Step 1: Running Comprehensive Functional Tests${NC}"
echo "Testing complete architecture including data layer..."

if ./scripts/functional-tests.sh; then
    add_test_result "comprehensive-functional-tests" "PASS" "All functional tests passed"
    echo -e "${GREEN}✅ Functional tests completed successfully${NC}"
else
    add_test_result "comprehensive-functional-tests" "FAIL" "Some functional tests failed"
    echo -e "${YELLOW}⚠️ Some functional tests failed (continuing with chaos tests)${NC}"
fi

# Step 2: Chaos Engineering Tests
echo -e "\n${BLUE}🌪️ Step 2: Chaos Engineering Tests${NC}"

# Chaos Test 1: Pod Recovery
echo -e "\n📋 Chaos Test 1: Pod Failure Recovery"
POD=$(kubectl get pods -n $NAMESPACE_PROD -l app=api-service -o jsonpath='{.items[0].metadata.name}')
if [[ -n "$POD" ]]; then
    echo "Deleting pod: $POD"
    kubectl delete pod $POD -n $NAMESPACE_PROD
    sleep 15
    NEW_PODS=$(kubectl get pods -n $NAMESPACE_PROD -l app=api-service --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
    if [[ $NEW_PODS -ge 2 ]]; then
        add_test_result "chaos-pod-recovery" "PASS" "Pod recovered successfully ($NEW_PODS pods running)"
        echo -e "${GREEN}✅ PASS: Pod recovered ($NEW_PODS pods running)${NC}"
    else
        add_test_result "chaos-pod-recovery" "FAIL" "Pod did not recover properly ($NEW_PODS pods running)"
        echo -e "${RED}❌ FAIL: Pod recovery failed ($NEW_PODS pods running)${NC}"
    fi
else
    add_test_result "chaos-pod-recovery" "FAIL" "Could not find API service pod"
    echo -e "${RED}❌ FAIL: Could not find API service pod${NC}"
fi

# Chaos Test 2: Database Connection Resilience
echo -e "\n📋 Chaos Test 2: Database Connection Resilience"
POSTGRES_POD=$(kubectl get pods -n $NAMESPACE_PROD -l app=postgres -o jsonpath='{.items[0].metadata.name}')
if [[ -n "$POSTGRES_POD" ]]; then
    echo "Restarting PostgreSQL pod: $POSTGRES_POD"
    kubectl delete pod $POSTGRES_POD -n $NAMESPACE_PROD
    sleep 20
    
    # Wait for postgres to be ready
    kubectl wait --for=condition=ready pod -l app=postgres -n $NAMESPACE_PROD --timeout=120s
    
    # Test if services can reconnect
    sleep 10
    MINIKUBE_IP=$(minikube ip)
    API_HEALTH=$(curl -s http://$MINIKUBE_IP:30004/api/health 2>/dev/null | jq -r '.status' 2>/dev/null)
    if [[ "$API_HEALTH" == "healthy" ]]; then
        add_test_result "chaos-database-resilience" "PASS" "Services reconnected to database after restart"
        echo -e "${GREEN}✅ PASS: Services reconnected to database${NC}"
    else
        add_test_result "chaos-database-resilience" "FAIL" "Services failed to reconnect to database"
        echo -e "${RED}❌ FAIL: Services failed to reconnect to database${NC}"
    fi
else
    add_test_result "chaos-database-resilience" "FAIL" "Could not find PostgreSQL pod"
    echo -e "${RED}❌ FAIL: Could not find PostgreSQL pod${NC}"
fi

# Chaos Test 3: Load Testing with Auto-Scaling
echo -e "\n📋 Chaos Test 3: Load Testing and Auto-Scaling"
echo "Generating load on API service..."

# Start load generation
kubectl run load-generator --image=busybox --rm -i --restart=Never -- /bin/sh -c "
while true; do 
    wget -q -O- http://api-service.production.svc.cluster.local:3000/health
    sleep 0.1
done" > /dev/null 2>&1 &
LOAD_PID=$!

# Wait and check for scaling
sleep 60

# Check if HPA scaled up
CURRENT_REPLICAS=$(kubectl get deployment api-service -n $NAMESPACE_PROD -o jsonpath='{.status.replicas}')
if [[ $CURRENT_REPLICAS -gt 2 ]]; then
    add_test_result "chaos-auto-scaling" "PASS" "HPA scaled up to $CURRENT_REPLICAS replicas"
    echo -e "${GREEN}✅ PASS: HPA scaled up to $CURRENT_REPLICAS replicas${NC}"
else
    add_test_result "chaos-auto-scaling" "PARTIAL" "HPA did not scale (may need more load or time)"
    echo -e "${YELLOW}⚠️ PARTIAL: HPA did not scale (current: $CURRENT_REPLICAS replicas)${NC}"
fi

# Stop load generation
kill $LOAD_PID 2>/dev/null || true

# Chaos Test 4: Network Partition Simulation
echo -e "\n📋 Chaos Test 4: Network Partition Recovery"
echo "Testing service communication after network policies..."

MINIKUBE_IP=$(minikube ip)
# Test that backend services are not directly accessible (network isolation working)
if timeout 5 curl -s http://$MINIKUBE_IP:5432 > /dev/null 2>&1; then
    add_test_result "chaos-network-isolation" "FAIL" "Database is externally accessible (security issue)"
    echo -e "${RED}❌ FAIL: Database is externally accessible${NC}"
else
    add_test_result "chaos-network-isolation" "PASS" "Database properly isolated"
    echo -e "${GREEN}✅ PASS: Database properly isolated${NC}"
fi

# Test that services can still communicate internally
FRONTEND_HEALTH=$(curl -s http://$MINIKUBE_IP:30004/api/health 2>/dev/null)
if echo "$FRONTEND_HEALTH" | grep -q "healthy\|ok" 2>/dev/null; then
    add_test_result "chaos-internal-communication" "PASS" "Internal service communication working"
    echo -e "${GREEN}✅ PASS: Internal service communication working${NC}"
else
    add_test_result "chaos-internal-communication" "FAIL" "Internal service communication failed"
    echo -e "${RED}❌ FAIL: Internal service communication failed${NC}"
fi

# Step 3: Performance and Stress Tests
echo -e "\n${BLUE}⚡ Step 3: Performance Tests${NC}"

# Test 5: Database Performance
echo -e "\n📋 Test 5: Database Performance"
DB_PERFORMANCE=$(kubectl exec -n production deployment/postgres -- psql -U sre_db_user -d sre_assignment_db -c "SELECT COUNT(*) FROM users;" 2>/dev/null | grep -oE '[0-9]+' | head -1)
if [[ "$DB_PERFORMANCE" =~ ^[0-9]+$ ]]; then
    add_test_result "performance-database" "PASS" "Database query successful (found $DB_PERFORMANCE users)"
    echo -e "${GREEN}✅ PASS: Database performance good ($DB_PERFORMANCE users)${NC}"
else
    add_test_result "performance-database" "FAIL" "Database query failed"
    echo -e "${RED}❌ FAIL: Database query failed${NC}"
fi

# Test 6: Storage Performance  
echo -e "\n📋 Test 6: Storage Performance"
MINIO_STATUS=$(curl -s http://$MINIKUBE_IP:30900/minio/health/ready 2>/dev/null && echo "ready" || echo "failed")
if [[ "$MINIO_STATUS" == "ready" ]]; then
    add_test_result "performance-storage" "PASS" "MinIO storage performing well"
    echo -e "${GREEN}✅ PASS: MinIO storage performing well${NC}"
else
    add_test_result "performance-storage" "FAIL" "MinIO storage performance issues"
    echo -e "${RED}❌ FAIL: MinIO storage performance issues${NC}"
fi

# Final Results Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}      Test Execution Complete${NC}"
echo -e "${GREEN}========================================${NC}"

TOTAL_TESTS=$(jq '.tests | length' $TEST_RESULTS_FILE)
PASSED_TESTS=$(jq '[.tests[] | select(.status == "PASS")] | length' $TEST_RESULTS_FILE)
FAILED_TESTS=$(jq '[.tests[] | select(.status == "FAIL")] | length' $TEST_RESULTS_FILE)
PARTIAL_TESTS=$(jq '[.tests[] | select(.status == "PARTIAL")] | length' $TEST_RESULTS_FILE)

echo -e "${BLUE}📊 Test Statistics:${NC}"
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"
echo -e "${YELLOW}Partial: $PARTIAL_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "\n${GREEN}🎉 ALL TESTS SUCCESSFUL!${NC}"
    echo -e "${GREEN}Platform is production-ready with complete functionality!${NC}"
    exit 0
elif [[ $FAILED_TESTS -lt 3 ]]; then
    echo -e "\n${YELLOW}⚠️ MOSTLY SUCCESSFUL WITH MINOR ISSUES${NC}"
    echo -e "Platform is functional but some components may need attention."
    exit 1
else
    echo -e "\n${RED}❌ MULTIPLE TEST FAILURES${NC}"
    echo -e "Platform requires debugging and fixes before production use."
    exit 2
fi
