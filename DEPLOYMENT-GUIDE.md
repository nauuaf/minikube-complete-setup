# SRE Assignment Deployment Guide

## Fixed Issues Summary

### 1. ✅ Docker Configuration
- **Issue**: Empty `/etc/docker/daemon.json` causing registry authentication failures
- **Fix**: Created `scripts/fix-docker-config.sh` that properly configures insecure registries
- **Auto-applied**: Yes, in start.sh

### 2. ✅ Unbound Variable Errors
- **Issue**: `SKIP_LOGIN` and other variables were not initialized
- **Fix**: Added proper variable initialization at script start
- **Result**: No more "unbound variable" errors

### 3. ✅ External Access via Domain
- **Issue**: Application not accessible via `nawaf.thmanyah.com`
- **Fix**: Created `scripts/setup-domain-access.sh` using socat to forward ports 80/443
- **Result**: Domain properly routes to Kubernetes services

### 4. ✅ Registry Push/Pull Issues
- **Issue**: Registry authentication and push failures
- **Fix**: Enhanced registry setup with proper authentication and fallback to local images
- **Result**: Graceful handling of registry failures

### 5. ✅ Port Forwarding
- **Issue**: Port forwarding not persistent and not binding to external interface
- **Fix**: Changed binding from `127.0.0.1` to `0.0.0.0` and created systemd services
- **Result**: Services accessible from external machines

## Deployment Instructions

### Prerequisites
```bash
# Verify everything is ready
./test-start-script.sh
```

### Deploy the Platform
```bash
# Start everything
./start.sh

# The script will automatically:
# 1. Fix Docker configuration
# 2. Start Minikube
# 3. Deploy all services
# 4. Setup domain forwarding
# 5. Configure external access
```

### Access Points

#### Via Domain (nawaf.thmanyah.com)
- **Frontend**: http://nawaf.thmanyah.com/
- **API Service**: http://nawaf.thmanyah.com/api
- **Auth Service**: http://nawaf.thmanyah.com/auth
- **Image Service**: http://nawaf.thmanyah.com/image

#### Via Public IP (3.69.30.150)
- **Frontend**: http://3.69.30.150:30004
- **Grafana**: http://3.69.30.150:30030 (admin/admin123)
- **Prometheus**: http://3.69.30.150:30090
- **Registry UI**: http://3.69.30.150:30501

#### Internal Services
- **PostgreSQL**: postgres-service.production:5432
- **Redis**: redis-service.production:6379
- **MinIO**: http://3.69.30.150:30900 (API) / :30901 (Console)

## Testing

### Test Deployment Status
```bash
./test-deployment.sh
```

### Test External Access
```bash
# From external machine
curl http://nawaf.thmanyah.com
curl http://3.69.30.150:30004
```

### Run Chaos Tests
```bash
./test-scenarios.sh
```

## Troubleshooting

### If Registry Login Fails
```bash
# Fix Docker config
sudo ./scripts/fix-docker-config.sh

# Use local images instead
./scripts/fix-local-images.sh
```

### If Domain Access Doesn't Work
```bash
# Setup domain forwarding manually
sudo ./scripts/setup-domain-access.sh

# Check socat services
sudo systemctl status domain-forward-combined.service
```

### If Services Don't Start
```bash
# Check pod status
kubectl get pods -n production

# Fix deployment issues
./scripts/fix-deployment-issues.sh
```

## Architecture

```
Internet → nawaf.thmanyah.com (DNS)
    ↓
Your Server (3.69.30.150)
    ↓
socat (Port 80/443)
    ↓
Minikube Ingress Controller
    ↓
Kubernetes Services (Frontend, API, Auth, Image)
    ↓
Data Layer (PostgreSQL, Redis, MinIO)
```

## Key Scripts Created

1. **fix-docker-config.sh** - Fixes Docker daemon configuration
2. **setup-domain-access.sh** - Sets up socat forwarding for domain access
3. **fix-deployment-issues.sh** - Comprehensive fixes for common issues
4. **test-deployment.sh** - Tests all components
5. **test-start-script.sh** - Validates script readiness

## Stop Everything
```bash
./stop.sh

# To completely remove cluster
./stop.sh --delete-cluster
```

## Notes

- The platform uses Minikube with Docker driver
- All services are production-ready with monitoring, security, and auto-scaling
- Domain must point to public IP (3.69.30.150) for external access
- Registry uses HTTP with basic auth (admin/SecurePass123!)
- Grafana dashboards are auto-imported during deployment