#!/bin/bash

# Fix health checks for Kubernetes Jobs and one-time tasks
# Jobs should be "Completed", not "Running" or "Ready"

source config/config.env

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Fixing Health Checks for Jobs and Admission Controllers...${NC}"

# Function to check job completion status
check_job_completion() {
    local job_name=$1
    local namespace=$2
    local description=$3
    
    echo -e "\n${YELLOW}Checking $description...${NC}"
    
    # Check if job exists
    if ! kubectl get job $job_name -n $namespace >/dev/null 2>&1; then
        echo -e "  ${RED}❌ Job $job_name not found in namespace $namespace${NC}"
        return 1
    fi
    
    # Check job status
    local job_status=$(kubectl get job $job_name -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    
    if [ "$job_status" = "True" ]; then
        echo -e "  ${GREEN}✅ $description completed successfully${NC}"
        
        # Show job details
        local completions=$(kubectl get job $job_name -n $namespace -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        local desired=$(kubectl get job $job_name -n $namespace -o jsonpath='{.spec.completions}' 2>/dev/null || echo "1")
        echo -e "    Completions: $completions/$desired"
        
        return 0
    else
        # Check if it's failed
        local failed_status=$(kubectl get job $job_name -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        if [ "$failed_status" = "True" ]; then
            echo -e "  ${RED}❌ $description failed${NC}"
            
            # Show failure reason
            local failed_reason=$(kubectl get job $job_name -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Failed")].reason}' 2>/dev/null)
            if [ -n "$failed_reason" ]; then
                echo -e "    Reason: $failed_reason"
            fi
            
            # Show pod logs if available
            local job_pods=$(kubectl get pods -n $namespace -l job-name=$job_name --no-headers 2>/dev/null | awk '{print $1}' | head -1)
            if [ -n "$job_pods" ]; then
                echo -e "    Recent logs:"
                kubectl logs "$job_pods" -n $namespace --tail=5 2>/dev/null || true
            fi
            
            return 1
        else
            echo -e "  ${YELLOW}⏳ $description is still running or pending${NC}"
            
            # Show current status
            kubectl get job $job_name -n $namespace
            kubectl get pods -n $namespace -l job-name=$job_name
            
            return 2
        fi
    fi
}

# Function to check pod status for regular deployments
check_pod_status() {
    local app_label=$1
    local namespace=$2
    local description=$3
    local exclude_jobs=${4:-false}
    
    echo -e "\n${YELLOW}Checking $description pods...${NC}"
    
    # Get all pods for this app
    if [ "$exclude_jobs" = "true" ]; then
        # Exclude completed job pods
        local pods=$(kubectl get pods -n $namespace -l app=$app_label --field-selector=status.phase!=Succeeded --no-headers 2>/dev/null)
    else
        local pods=$(kubectl get pods -n $namespace -l app=$app_label --no-headers 2>/dev/null)
    fi
    
    if [ -z "$pods" ]; then
        echo -e "  ${RED}❌ No pods found for $description${NC}"
        return 1
    fi
    
    # Show pod status
    echo "$pods" | while read line; do
        if [ -n "$line" ]; then
            local pod_name=$(echo $line | awk '{print $1}')
            local ready=$(echo $line | awk '{print $2}')
            local status=$(echo $line | awk '{print $3}')
            local restarts=$(echo $line | awk '{print $4}')
            
            if [[ "$status" == "Running" && "$ready" == *"/"* ]]; then
                local ready_count=$(echo $ready | cut -d'/' -f1)
                local total_count=$(echo $ready | cut -d'/' -f2)
                
                if [ "$ready_count" = "$total_count" ]; then
                    echo -e "  ${GREEN}✅ $pod_name: Running ($ready)${NC}"
                else
                    echo -e "  ${YELLOW}⏳ $pod_name: Running but not ready ($ready)${NC}"
                fi
            elif [[ "$status" == "Completed" ]]; then
                echo -e "  ${GREEN}✅ $pod_name: Completed successfully${NC}"
            else
                echo -e "  ${RED}❌ $pod_name: $status ($ready)${NC}"
            fi
        fi
    done
}

# 1. Check MinIO bucket initialization job
echo -e "${BLUE}=== MinIO Bucket Initialization ===${NC}"
check_job_completion "minio-bucket-init" "production" "MinIO bucket initialization"

# 2. Check ingress controller admission jobs
echo -e "\n${BLUE}=== Ingress Controller Admission Jobs ===${NC}"
check_job_completion "ingress-nginx-admission-create" "ingress-nginx" "Ingress admission create job" || true
check_job_completion "ingress-nginx-admission-patch" "ingress-nginx" "Ingress admission patch job" || true

# 3. Check ingress controller pods (should be running)
echo -e "\n${BLUE}=== Ingress Controller Pods ===${NC}"
echo -e "${YELLOW}Checking ingress controller pods...${NC}"
kubectl get pods -n ingress-nginx --no-headers | while read line; do
    if [ -n "$line" ]; then
        pod_name=$(echo $line | awk '{print $1}')
        ready=$(echo $line | awk '{print $2}')
        status=$(echo $line | awk '{print $3}')
        
        # Skip completed admission jobs
        if [[ "$pod_name" == *"admission"* && "$status" == "Completed" ]]; then
            echo -e "  ${GREEN}✅ $pod_name: $status (expected for admission jobs)${NC}"
        elif [[ "$status" == "Running" && "$ready" == *"/"* ]]; then
            ready_count=$(echo $ready | cut -d'/' -f1)
            total_count=$(echo $ready | cut -d'/' -f2)
            
            if [ "$ready_count" = "$total_count" ]; then
                echo -e "  ${GREEN}✅ $pod_name: Running and ready ($ready)${NC}"
            else
                echo -e "  ${YELLOW}⏳ $pod_name: Running but not ready ($ready)${NC}"
            fi
        else
            echo -e "  ${RED}❌ $pod_name: $status ($ready)${NC}"
        fi
    fi
done

# 4. Check cert-manager jobs
echo -e "\n${BLUE}=== Cert-Manager Jobs ===${NC}"
if kubectl get jobs -n cert-manager --no-headers 2>/dev/null | grep -q "webhook"; then
    kubectl get jobs -n cert-manager --no-headers | while read line; do
        if [ -n "$line" ]; then
            job_name=$(echo $line | awk '{print $1}')
            check_job_completion "$job_name" "cert-manager" "Cert-manager $job_name" || true
        fi
    done
else
    echo -e "  ${GREEN}✅ No cert-manager jobs found (normal for some installations)${NC}"
fi

# 5. Summary and recommendations
echo -e "\n${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}✅ Jobs with 'Completed' status are working correctly${NC}"
echo -e "${GREEN}✅ Admission controllers complete their setup and then show as Completed${NC}"
echo -e "${YELLOW}📝 Health check scripts should distinguish between:${NC}"
echo -e "     • Jobs/Init containers: Should be 'Completed'"
echo -e "     • Regular services: Should be 'Running' and 'Ready'"
echo -e "     • Admission controllers: Should be 'Completed' (they're one-time setup jobs)"

echo -e "\n${BLUE}=== Recommended Health Check Logic ===${NC}"
cat << 'EOF'

For Jobs (like minio-bucket-init):
  - Check: kubectl get job <job-name> -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'
  - Expected: "True"

For Admission Controllers (ingress-nginx-admission-*):
  - Check: These are Jobs that run once during installation
  - Expected: Status should be "Completed"
  - These should NOT be checked for "Ready" status

For Regular Pods (like ingress-nginx-controller):
  - Check: kubectl get pods -l <selector> --field-selector=status.phase=Running
  - Expected: Running with all containers ready

EOF

echo -e "${GREEN}🔧 Health check analysis complete!${NC}"