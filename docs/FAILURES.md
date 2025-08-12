# Failure Scenarios & Recovery

## Overview

This document outlines common failure scenarios, their impact, and recovery procedures for the SRE Assignment microservices platform.

## Failure Categories

### 1. Infrastructure Failures

#### Node Failure
**Scenario**: Kubernetes node becomes unavailable
**Impact**: Pods on the failed node are rescheduled
**Detection**: Pod restarts, node status reports
**Recovery**: Automatic pod rescheduling to healthy nodes
**Prevention**: Multiple replicas, Pod Disruption Budgets

#### Network Partition
**Scenario**: Network connectivity issues between nodes
**Impact**: Service communication disrupted
**Detection**: Service health checks fail, increased error rates
**Recovery**: Network issue resolution, service mesh retry policies
**Prevention**: NetworkPolicies, circuit breakers

### 2. Application Failures

#### Pod Crashes
**Scenario**: Application process exits unexpectedly
**Impact**: Individual pod becomes unavailable
**Detection**: Liveness probe failures, container restarts
**Recovery**: Kubernetes restarts the container automatically
**Prevention**: Proper resource limits, graceful shutdown handling

```bash
# Manual recovery
kubectl get pods -n production
kubectl describe pod <failing-pod> -n production
kubectl delete pod <failing-pod> -n production  # Force restart
```

#### Memory Leaks
**Scenario**: Application consumes excessive memory
**Impact**: Pod gets OOMKilled, potential service degradation
**Detection**: Memory usage monitoring, OOMKilled events
**Recovery**: Pod restart, investigate memory usage patterns
**Prevention**: Memory limits, monitoring, code reviews

### 3. Service Dependencies

#### Auth Service Unavailable
**Scenario**: Authentication service becomes unresponsive
**Impact**: API service cannot validate tokens
**Detection**: API service health checks fail
**Recovery**: Scale auth service, investigate root cause
**Prevention**: Circuit breakers, multiple auth service replicas

```bash
# Recovery steps
kubectl scale deployment auth-service --replicas=5 -n production
kubectl logs -f deployment/auth-service -n production
```

#### Database Connection Loss
**Scenario**: Database becomes unavailable
**Impact**: Services cannot persist or retrieve data
**Detection**: Application error logs, database connection failures
**Recovery**: Database restart, connection pool reset
**Prevention**: Connection pooling, retry logic, read replicas

### 4. Storage & Registry Failures

#### Private Registry Down
**Scenario**: Docker registry becomes unavailable
**Impact**: Cannot pull new images, deployments fail
**Detection**: Image pull errors in pod events
**Recovery**: Registry service restart, use backup registry
**Prevention**: Registry high availability, image caching

```bash
# Check registry status
kubectl get pods -l app=docker-registry
kubectl logs -f deployment/docker-registry

# Recovery
kubectl rollout restart deployment/docker-registry
```

#### Persistent Volume Issues
**Scenario**: Storage volumes become unavailable
**Impact**: Data loss risk, pod startup failures
**Detection**: Pod mounting failures, storage errors
**Recovery**: Volume remount, backup restoration
**Prevention**: Backup strategy, volume replication

### 5. Security Incidents

#### Certificate Expiry
**Scenario**: TLS certificates expire
**Impact**: HTTPS connections fail, browser warnings
**Detection**: Certificate monitoring, SSL handshake failures
**Recovery**: Certificate renewal via cert-manager
**Prevention**: Automated certificate renewal, monitoring

```bash
# Check certificate status
kubectl get certificates -n production
kubectl describe certificate sre-platform-tls -n production

# Force renewal
kubectl delete certificate sre-platform-tls -n production
```

#### Secret Compromise
**Scenario**: Kubernetes secrets are compromised
**Impact**: Security breach, unauthorized access
**Detection**: Audit logs, anomalous behavior
**Recovery**: Secret rotation, affected service restart
**Prevention**: RBAC, secret rotation policies

### 6. Monitoring & Observability

#### Prometheus Down
**Scenario**: Monitoring system becomes unavailable
**Impact**: Loss of metrics, alerting disabled
**Detection**: Grafana shows no data, missing metrics
**Recovery**: Prometheus restart, data recovery from storage
**Prevention**: Prometheus high availability, external monitoring

```bash
# Recovery steps
kubectl get pods -n monitoring
kubectl logs -f deployment/prometheus -n monitoring
kubectl rollout restart deployment/prometheus -n monitoring
```

#### Grafana Inaccessible
**Scenario**: Grafana UI becomes unavailable
**Impact**: Cannot view dashboards, no visual monitoring
**Detection**: HTTP 503 errors, dashboard loading failures
**Recovery**: Grafana service restart, configuration verification
**Prevention**: Grafana clustering, external dashboard backup

## Automated Recovery Mechanisms

### Kubernetes Self-Healing
- **Liveness Probes**: Restart unhealthy containers
- **Readiness Probes**: Remove pods from service endpoints
- **ReplicaSets**: Maintain desired pod count
- **HPA**: Scale based on resource utilization

### Application-Level Recovery
- **Circuit Breakers**: Prevent cascade failures
- **Retry Logic**: Handle transient failures
- **Graceful Degradation**: Maintain core functionality
- **Health Checks**: Report service status accurately

## Recovery Playbooks

### Critical Service Down
```bash
# 1. Assess impact
kubectl get pods -n production
kubectl get services -n production

# 2. Scale up healthy replicas
kubectl scale deployment <service-name> --replicas=5 -n production

# 3. Investigate root cause
kubectl logs -f deployment/<service-name> -n production
kubectl describe pod <pod-name> -n production

# 4. Apply fix and rollout
kubectl set image deployment/<service-name> <container>=<new-image> -n production
kubectl rollout status deployment/<service-name> -n production
```

### Complete System Recovery
```bash
# 1. Check cluster status
kubectl cluster-info
kubectl get nodes

# 2. Restart critical services
./stop.sh
./start.sh

# 3. Verify recovery
./scripts/health-checks.sh
./test-scenarios.sh
```

## Alerting & Escalation

### Alert Levels

#### P1 - Critical (Immediate Response)
- Complete service outage
- Security breaches
- Data corruption

#### P2 - High (Within 30 minutes)
- Degraded performance
- Single service failure
- Certificate expiry

#### P3 - Medium (Within 2 hours)
- Minor functionality issues
- Non-critical monitoring failures
- Configuration drift

#### P4 - Low (Best effort)
- Documentation updates
- Performance optimization
- Capacity planning

### Escalation Procedures

1. **Automated Alerts** → Slack/PagerDuty
2. **P1 Incidents** → Immediate team notification
3. **Unresolved P2** → Escalate after 30 minutes
4. **Communication** → Status page updates

## Post-Incident Analysis

### Root Cause Analysis
1. **Timeline**: When did the incident occur?
2. **Impact**: What was affected and for how long?
3. **Root Cause**: What was the underlying cause?
4. **Recovery**: How was service restored?
5. **Prevention**: How can we prevent recurrence?

### Action Items
- Code fixes
- Infrastructure improvements
- Process updates
- Training requirements

## Testing Failure Scenarios

### Regular Drills
- Monthly chaos engineering exercises
- Quarterly disaster recovery tests
- Annual business continuity validation

### Chaos Testing Commands
```bash
# Pod failure simulation
kubectl delete pod $(kubectl get pods -n production -l app=api-service -o name | head -1) -n production

# Load testing
kubectl run load-test --image=busybox --rm -it -- wget -O- http://api-service.production:3000/health

# Network partition
kubectl apply -f kubernetes/chaos/10-chaos-tests.yaml
```

## Documentation & Communication

### Incident Documentation
- Maintain incident log
- Update runbooks
- Share lessons learned
- Review SLAs and SLOs

### Team Communication
- Clear incident command structure
- Regular status updates
- Post-incident debriefs
- Knowledge sharing sessions

## Recovery Time Objectives

| Failure Type | Detection Time | Recovery Time | Availability Impact |
|--------------|----------------|---------------|-------------------|
| Pod Crash | < 30 seconds | < 2 minutes | Minimal |
| Node Failure | < 2 minutes | < 5 minutes | < 1% requests |
| Service Failure | < 1 minute | < 10 minutes | Single service |
| Complete Outage | < 5 minutes | < 30 minutes | Full system |

## Success Metrics

- **MTTR**: Mean Time To Recovery < 10 minutes
- **MTBF**: Mean Time Between Failures > 7 days
- **Availability**: 99.9% uptime target
- **Error Rate**: < 0.1% error budget consumption