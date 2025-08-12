#!/bin/bash
# Manual MinIO bucket initialization script
# Use this if the automatic job fails during deployment

set -euo pipefail

# Load configuration
source config/config.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Manual MinIO Bucket Initialization${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if MinIO pod is running
log_info "Checking MinIO pod status..."
if ! kubectl get pods -n $NAMESPACE_PROD -l app=minio --no-headers | grep -q "Running"; then
    log_error "MinIO pod is not running. Please ensure MinIO is deployed first:"
    log_error "  kubectl apply -f kubernetes/data/14-minio.yaml"
    exit 1
fi

log_success "MinIO pod is running"

# Delete any existing initialization job
log_info "Cleaning up any existing initialization job..."
kubectl delete job minio-bucket-init -n $NAMESPACE_PROD 2>/dev/null || true
sleep 5

# Create a new initialization job
log_info "Creating new bucket initialization job..."
kubectl apply -f kubernetes/data/14-minio.yaml

# Wait for the job to start
sleep 10

# Monitor the job progress
log_info "Monitoring bucket initialization progress..."
job_name="minio-bucket-init"

# Wait up to 15 minutes for completion
timeout_seconds=900
elapsed=0
check_interval=10

while [ $elapsed -lt $timeout_seconds ]; do
    # Check job status
    job_status=$(kubectl get job $job_name -n $NAMESPACE_PROD -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
    failed_status=$(kubectl get job $job_name -n $NAMESPACE_PROD -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
    
    if [ "$job_status" = "True" ]; then
        log_success "MinIO bucket initialization completed successfully!"
        
        # Show job logs
        log_info "Initialization job logs:"
        job_pod=$(kubectl get pods -n $NAMESPACE_PROD -l app=minio-init --no-headers | head -1 | awk '{print $1}')
        if [ -n "$job_pod" ]; then
            kubectl logs "$job_pod" -n $NAMESPACE_PROD || true
        fi
        
        log_success "Buckets are now ready for use!"
        exit 0
    elif [ "$failed_status" = "True" ]; then
        log_error "MinIO bucket initialization job failed!"
        
        # Show detailed failure information
        log_info "Job details:"
        kubectl describe job $job_name -n $NAMESPACE_PROD || true
        
        log_info "Pod logs:"
        job_pod=$(kubectl get pods -n $NAMESPACE_PROD -l app=minio-init --no-headers | head -1 | awk '{print $1}')
        if [ -n "$job_pod" ]; then
            kubectl logs "$job_pod" -n $NAMESPACE_PROD --all-containers=true || true
            kubectl describe pod "$job_pod" -n $NAMESPACE_PROD || true
        fi
        
        exit 1
    else
        # Job is still running
        active_jobs=$(kubectl get job $job_name -n $NAMESPACE_PROD -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
        log_info "Bucket initialization in progress... (${elapsed}s elapsed, active jobs: $active_jobs)"
        
        # Show current pod status every minute
        if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            kubectl get pods -n $NAMESPACE_PROD -l app=minio-init 2>/dev/null || true
        fi
    fi
    
    sleep $check_interval
    elapsed=$((elapsed + check_interval))
done

# Timeout reached
log_error "Bucket initialization timed out after $timeout_seconds seconds"
log_info "Current job status:"
kubectl get job $job_name -n $NAMESPACE_PROD || true
kubectl get pods -n $NAMESPACE_PROD -l app=minio-init || true

log_warning "You may need to check MinIO logs and network connectivity:"
log_warning "  kubectl logs -f deployment/minio -n $NAMESPACE_PROD"
log_warning "  kubectl get svc minio-service -n $NAMESPACE_PROD"

exit 1