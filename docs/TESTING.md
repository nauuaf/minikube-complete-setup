# Testing Guide

## Overview

This document describes the comprehensive testing strategy for the SRE Assignment, covering functional testing, load testing, chaos engineering, and failure scenario validation.

## Test Categories

### 1. Smoke Tests

Basic functionality and health checks for all services.

**Run Command:**
```bash
./scripts/health-checks.sh
```

**What it tests:**
- Service health endpoints
- Basic connectivity
- Monitoring stack availability

### 2. Integration Tests

End-to-end service communication and workflow testing.

**Run Command:**
```bash
./test-scenarios.sh
```

**Test Scenarios:**
1. **Pod Recovery Test**: Validates automatic pod restart
2. **Inter-Service Communication**: Tests service-to-service calls
3. **Secret Management**: Verifies Kubernetes Secrets integration
4. **HPA Scaling**: Validates auto-scaling behavior
5. **Registry Access**: Tests private Docker registry

### 3. Load Testing

Performance and scalability validation.

**Run Command:**
```bash
./scripts/test-runner.sh
```

**Test Characteristics:**
- Concurrent requests to all services
- HPA scaling trigger validation
- Resource utilization monitoring
- Performance metrics collection

### 4. Chaos Engineering

Failure injection and recovery validation.

**Manual Tests:**

#### Pod Failure Simulation
```bash
# Delete a random pod
POD=$(kubectl get pods -n production -l app=api-service -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $POD -n production

# Verify automatic recovery
kubectl get pods -n production -l app=api-service -w
```

#### Network Partition Test
```bash
# Apply restrictive network policy
kubectl apply -f kubernetes/chaos/network-partition-test.yaml

# Wait and observe
kubectl get pods -n production

# Restore connectivity
kubectl delete -f kubernetes/chaos/network-partition-test.yaml
```

#### Resource Exhaustion
```bash
# Generate CPU load
kubectl run cpu-load --image=progrium/stress -- --cpu 2 --timeout 60s

# Monitor HPA scaling
kubectl get hpa -n production -w
```

## Automated Test Scenarios

### Test Results Format

All automated tests generate JSON results in `tests/test-results/`:

```json
{
  "timestamp": "20240101_120000",
  "tests": [
    {
      "name": "pod-recovery",
      "status": "PASS",
      "details": "Pod recovered successfully"
    }
  ],
  "summary": {
    "total": "5",
    "passed": "5",
    "failed": "0"
  }
}
```

### Expected Test Results

| Test | Expected Result | Recovery Time |
|------|----------------|---------------|
| Pod Recovery | PASS | < 30 seconds |
| Service Communication | PASS | Immediate |
| Secret Management | PASS | Immediate |
| HPA Scaling | PASS | 1-2 minutes |
| Registry Access | PASS | Immediate |

## Monitoring During Tests

### Grafana Dashboards

Monitor these dashboards during testing:

1. **System Overview**: Overall system health
2. **API Service**: Request rates and response times
3. **Auth Service**: Authentication success rates
4. **Image Service**: Processing performance

### Prometheus Queries

Key metrics to monitor:

```promql
# Request rate
sum(rate(http_requests_total[5m])) by (service)

# Error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Response time
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Pod count
count(up{job=~".*-service"}) by (job)
```

## Load Test Specifications

### Test Parameters
- **Duration**: 5 minutes
- **Concurrent Users**: 50
- **Ramp-up Time**: 30 seconds
- **Target RPS**: 100 per service

### Success Criteria
- **Error Rate**: < 1%
- **Response Time**: 95th percentile < 500ms
- **HPA Trigger**: Scaling within 2 minutes
- **Service Availability**: > 99.5%

## Failure Recovery Scenarios

### 1. Single Pod Failure
- **Trigger**: Delete one pod manually
- **Expected**: New pod starts within 30 seconds
- **Validation**: Service remains available

### 2. Service Overload
- **Trigger**: Generate high CPU load
- **Expected**: HPA scales to maximum replicas
- **Validation**: Response times remain acceptable

### 3. Network Partition
- **Trigger**: Apply restrictive NetworkPolicy
- **Expected**: Affected services become unreachable
- **Validation**: Other services continue operating

### 4. Registry Unavailability
- **Trigger**: Stop registry service
- **Expected**: Existing pods continue running
- **Validation**: No new deployments until registry restored

## Continuous Testing

### Pre-deployment Tests
Run before any deployment:
```bash
./prereq-check.sh
./test-scenarios.sh
```

### Post-deployment Validation
Run after deployment:
```bash
./scripts/health-checks.sh
./scripts/test-runner.sh
```

### Scheduled Testing
Recommended schedule:
- **Health checks**: Every 5 minutes
- **Integration tests**: Every hour
- **Load tests**: Daily
- **Chaos tests**: Weekly

## Test Environment Requirements

### Minimum Resources
- **CPU**: 4 cores available
- **Memory**: 8GB available
- **Storage**: 20GB available
- **Network**: Stable internet connection

### Test Data
- No sensitive data required
- All tests use mock/simulated data
- Test results stored locally in `tests/test-results/`

## Troubleshooting Test Failures

### Common Issues

1. **Pod Recovery Fails**
   - Check resource availability
   - Verify image availability in registry
   - Review pod events: `kubectl describe pod <pod-name>`

2. **Service Communication Fails**
   - Verify NetworkPolicies
   - Check service DNS resolution
   - Validate secret configuration

3. **HPA Scaling Issues**
   - Ensure metrics-server is running
   - Check resource requests are set
   - Verify CPU load generation

4. **Registry Tests Fail**
   - Confirm registry authentication
   - Check registry service availability
   - Verify network connectivity

### Debug Commands

```bash
# Check pod status
kubectl get pods --all-namespaces

# View pod logs
kubectl logs -f <pod-name> -n <namespace>

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp

# Test service connectivity
kubectl run debug --image=curlimages/curl -it --rm -- sh
```