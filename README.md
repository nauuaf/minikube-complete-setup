# SRE Assignment - Ubuntu/Linux Kubernetes Platform

**🐧 Optimized for Ubuntu 20.04+ and Linux distributions**

This project provides a complete production-ready Kubernetes microservices platform with private Docker registry, monitoring stack, and security best practices.

## ✅ Implementation Checklist

- [✅] **4 Microservices**: Frontend (React), API (Node.js), Auth (Go), Image (Python) 
- [✅] **Complete Data Layer**: PostgreSQL database, Redis cache, MinIO S3 storage
- [✅] **Private Docker Registry**: Authentication + UI (works natively on Linux)
- [✅] **Kubernetes Deployments**: HPA, resource limits, multiple replicas
- [✅] **Data Persistence**: Persistent volumes for all data layer components
- [✅] **Database Integration**: Full schemas, migrations, service connectivity
- [✅] **Security**: NetworkPolicies, ClusterIP backends, Secrets, TLS
- [✅] **Monitoring**: Prometheus + Grafana + AlertManager with data layer metrics
- [✅] **Auto-scaling**: CPU-based HPA with proper resource management
- [✅] **High Availability**: PodDisruptionBudgets, health probes, data resilience
- [✅] **Ubuntu Optimization**: Native Docker networking, no tunneling
- [✅] **Comprehensive Testing**: Functional tests + chaos engineering scenarios

## 🚀 Quick Start (Ubuntu/Linux)

### System Requirements
- **OS**: Ubuntu 20.04+ or similar Linux distribution
- **RAM**: 8GB minimum (12GB recommended for optimal performance)  
- **CPU**: 4 cores minimum
- **Disk**: 40GB free space
- **Network**: Internet access for pulling base images

### Prerequisites Installation
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Minikube  
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# Install additional tools
sudo apt update && sudo apt install -y jq curl wget bc helm
```

### One-Command Deployment
```bash
# Validate prerequisites
./prereq-check.sh

# Deploy complete platform (10-15 minutes)
./start.sh

# Run comprehensive tests
./test-scenarios.sh

# Stop and cleanup
./stop.sh
```

## 🏗️ Architecture Overview

```
                    External Traffic (HTTPS/TLS)
                                │
        ┌───────────────────────▼─────────────────────────┐
        │              Ingress Controller                 │
        │           (NGINX with TLS/cert-manager)         │
        └───────────────────────┬─────────────────────────┘
                                │
                        ┌───────▼───────┐
                        │   Frontend    │  ◄─── Only Public Service
                        │  (React/Ant)  │
                        │   Port 3000   │
                        │   HPA: 2-10   │
                        └───────┬───────┘
                                │ nginx proxy
                ┌───────────────┼───────────────┐
                │               │               │
        ┌───────▼──────┐ ┌─────▼──────┐ ┌─────▼──────┐
        │  API Service │ │Auth Service│ │Image Service│ ◄─── ClusterIP Only
        │   (Node.js)  │ │    (Go)    │ │  (Python)   │     (Internal Only)
        │   Port 3000  │ │  Port 8080 │ │  Port 5000  │
        │   HPA: 2-5   │ │  HPA: 2-5  │ │  HPA: 2-5   │
        └───────┬──────┘ └─────┬──────┘ └─────┬──────┘
                │              │              │
                └──────────────┼──────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
    ┌───────▼──────┐ ┌────────▼────────┐ ┌──────▼──────┐
    │ PostgreSQL   │ │  Redis Cache    │ │ MinIO S3    │ ◄─── Data Layer
    │  Database    │ │   (Sessions)    │ │ (Storage)   │     (Persistent)
    │  Port 5432   │ │   Port 6379     │ │ Port 9000   │
    │ Persistent   │ │  Persistent     │ │ Persistent  │
    └──────────────┘ └─────────────────┘ └─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │          Private Docker Registry (Auth)       │
        │         Kubernetes Cluster (Secured)          │
        │  • NetworkPolicies  • Secrets  • ConfigMaps  │
        │  • PersistentVolumes • Services • Deployments │
        └─────────────────┬─────────────┬───────────────┘
                          │             │
                ┌─────────▼──────────┐  │  ┌─────────▼──────────┐
                │    Prometheus      │  │  │     Grafana        │
                │  Metrics Storage   │◄─┘  │  6 Dashboards      │
                │ + DB/Redis/S3     │     │ + Data Layer       │
                │   Exporters       │     │   Monitoring       │
                └────────────────────┘     └────────────────────┘
```

## 📊 Complete Service Architecture

### Application Services
| Service | Language | Port | Replicas | CPU Request | Memory Request |
|---------|----------|------|----------|-------------|----------------|
| Frontend | React/Nginx | 3000 | 2-10 | 50m | 64Mi |
| API | Node.js | 3000 | 2-5 | 100m | 128Mi |
| Auth | Go | 8080 | 2-5 | 100m | 128Mi |
| Image | Python | 5000 | 2-5 | 100m | 128Mi |

### Data Layer Services  
| Service | Technology | Port | Storage | CPU Request | Memory Request |
|---------|------------|------|---------|-------------|----------------|
| PostgreSQL | PostgreSQL 15 | 5432 | 10Gi PV | 200m | 256Mi |
| Redis | Redis 7 | 6379 | 2Gi PV | 100m | 128Mi |
| MinIO | MinIO S3 | 9000/9001 | 20Gi PV | 200m | 256Mi |

### Infrastructure Services
| Service | Technology | Port | Purpose | CPU Request | Memory Request |
|---------|------------|------|---------|-------------|----------------|
| Registry | Docker Registry v2 | 5000 | Private images | 100m | 256Mi |
| Prometheus | Prometheus | 9090 | Metrics | 200m | 512Mi |
| Grafana | Grafana | 3000 | Dashboards | 100m | 256Mi |

## 🔐 Security Features

- **Defense in Depth Architecture**: Only frontend exposed publicly
- **Network Segmentation**: Backend services and data layer use ClusterIP only
- **Database Security**: PostgreSQL isolated with authentication and network policies
- **Cache Security**: Redis with password authentication and restricted access
- **Storage Security**: MinIO with access keys and bucket policies
- **Private Docker Registry** with HTTP Basic Auth
- **NetworkPolicies** enforce strict inter-service and data layer communication
- **Frontend Proxy**: All backend access routed through nginx proxy
- **TLS/HTTPS** via cert-manager and Let's Encrypt
- **Kubernetes Secrets** for all sensitive data (DB, Redis, S3 credentials)
- **Zero external backend exposure** - services and data isolated within cluster

## 🧪 Testing Scenarios

### Functional Tests
1. **Infrastructure Layer**: PostgreSQL, Redis, MinIO connectivity and operations
2. **Application Services**: Health checks, database connections, S3 uploads
3. **Frontend Integration**: Proxy configuration and service communication
4. **Data Integration**: User creation, session storage, image uploads
5. **Monitoring Stack**: Metrics collection from all services and data layer
6. **Security**: Network isolation, secrets management, authentication

### Chaos Engineering Tests  
1. **Pod Failure Recovery**: Automatically recovers from pod crashes
2. **Database Resilience**: Services reconnect after PostgreSQL restart
3. **Load Testing**: HPA scales services under load
4. **Network Partition**: Network policies properly isolate services
5. **Storage Performance**: MinIO handles concurrent operations
6. **Cache Failover**: Redis persistence and recovery testing

## 📈 Service Access (Ubuntu/Linux)

After successful deployment, access services using the Minikube IP:

```bash
# Get your Minikube IP
MINIKUBE_IP=$(minikube ip)
echo "Minikube IP: $MINIKUBE_IP"

# Service URLs  
echo "Frontend:    http://$MINIKUBE_IP:30004"
echo "Registry UI: http://$MINIKUBE_IP:30501"  
echo "Prometheus:  http://$MINIKUBE_IP:30090"
echo "Grafana:     http://$MINIKUBE_IP:30030"
```

**Default Credentials:**
- **Registry**: admin / SecurePass123!
- **Grafana**: admin / admin123

## 🔍 Platform Validation

### Automated Testing
```bash
# Run comprehensive test suite
./test-scenarios.sh

# Tests include:
# ✅ Service health and connectivity
# ✅ Registry authentication and image pulling  
# ✅ Auto-scaling under load
# ✅ Network policy enforcement
# ✅ Monitoring stack functionality
# ✅ Failure recovery scenarios
```

### Manual Verification
```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Verify registry contents
curl -u admin:SecurePass123! http://$MINIKUBE_IP:30500/v2/_catalog

# Test frontend connectivity
curl -s http://$MINIKUBE_IP:30004/health

# Monitor resource usage
kubectl top pods --all-namespaces
```

## 🐧 Ubuntu/Linux Advantages

This platform is **optimized for Ubuntu/Linux** and provides:

✅ **Native Docker Registry**: No Docker Desktop limitations  
✅ **Direct NodePort Access**: No tunneling or port-forwarding required  
✅ **Better Resource Utilization**: Native container networking  
✅ **Production-Ready**: Suitable for actual cloud deployment  
✅ **Firewall Integration**: Easy remote access configuration  

### Remote Access Setup
```bash
# Allow NodePort range through firewall
sudo ufw allow 30000:32767/tcp

# Or specific services only
sudo ufw allow 30004/tcp  # Frontend
sudo ufw allow 30030/tcp  # Grafana  
sudo ufw allow 30500/tcp  # Registry
```

## 💡 Key Features Demonstrated

- **High Availability**: Multiple replicas with PodDisruptionBudget
- **Auto-scaling**: CPU-based HPA (70% threshold)
- **Security**: NetworkPolicies, Secrets, TLS, Registry Auth
- **Observability**: Metrics, logs, traces, dashboards
- **Resilience**: Health checks, circuit breakers
- **Best Practices**: Resource limits, proper probes, graceful shutdown

## 🛠️ Management Commands

### Platform Lifecycle
```bash
# Start complete platform
./start.sh

# Stop services (preserve data)
./stop.sh  

# Complete cleanup and cluster deletion
./stop.sh --delete-cluster
```

### Troubleshooting
```bash
# Collect logs for debugging
kubectl logs --all-containers --tail=100 -l app=api-service -n production

# Restart stuck services  
kubectl rollout restart deployment/api-service -n production

# Check resource usage
kubectl top pods --all-namespaces
kubectl describe node minikube
```

### Development Workflow
```bash
# Build and push new image
docker build -t my-service:2.0.0 ./services/my-service/
docker tag my-service:2.0.0 $(minikube ip):30500/my-service:2.0.0  
docker push $(minikube ip):30500/my-service:2.0.0

# Update deployment
kubectl set image deployment/my-service app=$(minikube ip):30500/my-service:2.0.0 -n production
```

## 📂 Project Structure

```
sre-assignment/
├── README.md                    # This comprehensive guide
├── start.sh                     # Main deployment script (Ubuntu optimized)
├── stop.sh                      # Cleanup script
├── prereq-check.sh             # System requirements validation  
├── test-scenarios.sh           # Comprehensive testing suite
├── config/
│   └── config.env              # Platform configuration (Ubuntu tuned)
├── services/                   # Microservices source code
│   ├── api-service/            # Node.js REST API
│   ├── auth-service/           # Go authentication service
│   ├── image-service/          # Python image processing
│   └── frontend/               # React frontend with nginx
├── kubernetes/                 # Kubernetes manifests
│   ├── core/                   # Infrastructure components
│   ├── security/               # NetworkPolicies, Secrets, TLS
│   ├── apps/                   # Application deployments
│   └── monitoring/             # Prometheus, Grafana, AlertManager
├── scripts/                    # Utility scripts
│   ├── registry-auth.sh        # Registry authentication setup
│   ├── health-checks.sh        # System health validation
│   ├── import-dashboards.sh    # Grafana dashboard import
│   └── update-registry-refs.sh # Dynamic registry configuration
└── tests/                      # Test scenarios and validation
```

## 🚀 Production Deployment

This platform is designed for **Ubuntu/Linux production environments**:

### Cloud Deployment (AWS/GCP/Azure)
```bash
# On Ubuntu 20.04+ VM with 8GB RAM, 4 CPUs
git clone <repository>
cd sre-assignment
./prereq-check.sh && ./start.sh

# Configure security groups/firewall for ports 30000-32767
# Access services via <VM_IP>:30004 (frontend)
```

### On-Premises Deployment  
```bash
# Dedicated Ubuntu server
sudo ufw allow 30000:32767/tcp
./start.sh

# Services accessible on local network via server IP
```

### Container Orchestration Migration
- **Kubernetes**: Production-ready manifests in `kubernetes/`
- **Docker Swarm**: Convert using `kompose convert`  
- **OpenShift**: Compatible with minimal modifications

## ⚡ Performance Optimizations

**Ubuntu/Linux Advantages:**
- ✅ Native container networking (no NAT overhead)
- ✅ Direct NodePort access (no tunneling latency)  
- ✅ Efficient resource utilization (no virtualization layer)
- ✅ Production-grade registry functionality
- ✅ Seamless scaling and load balancing

**Recommended VM Sizing:**
- **Development**: 8GB RAM, 4 vCPUs, 40GB disk
- **Production**: 16GB RAM, 8 vCPUs, 100GB disk  
- **High-Load**: 32GB RAM, 16 vCPUs, 200GB disk

---

**🐧 Ubuntu/Linux Kubernetes Platform - Production Ready!**