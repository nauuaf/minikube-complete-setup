## SRE Platform - Production Kubernetes Deployment

**🚀 Production-ready microservices platform with HTTPS, monitoring, and auto-scaling**

This project demonstrates enterprise-grade SRE practices on Kubernetes with:

*   **HTTPS/TLS** with automatic Let's Encrypt certificates
*   **4 Microservices**: Frontend (React), API (Node.js), Auth (Go), Image (Python)
*   **Complete Data Layer**: PostgreSQL, Redis, MinIO S3 storage
*   **Monitoring Stack**: Prometheus, Grafana, AlertManager with custom dashboards
*   **Security**: NetworkPolicies, Secrets, Private Registry, Defense-in-depth
*   **Auto-scaling**: HPA, PodDisruptionBudgets, Health probes

## 🏗️ System Architecture

```plaintext
🌐 Internet (HTTPS via Domain)
              │
    ┌─────────▼─────────┐
    │  Route 53 DNS     │ ◄─── thmanyah.com → EC2 IP
    └─────────┬─────────┘
              │
┌─────────────▼──────────────┐
│    NGINX Ingress + cert-manager │ ◄─── Automatic SSL from Let's Encrypt  
│      (Single Entry Point)       │
└─────────────┬──────────────┘
              │ HTTPS Only
      ┌───────▼───────┐
      │   Frontend    │ ◄─── React SPA (Public)
      │   Port 3000   │     Routes: /, /api, /auth, /image
      │   HPA: 2-10   │
      └───────┬───────┘
              │ Internal routing
    ┌─────────┼─────────┐
    │         │         │
┌───▼───┐ ┌──▼───┐ ┌───▼───┐
│  API  │ │ Auth │ │Image  │ ◄─── Microservices (ClusterIP only)
│Node.js│ │  Go  │ │Python │     No external access
│ HPA   │ │ HPA  │ │ HPA   │
└───┬───┘ └──┬───┘ └───┬───┘
    │        │         │
    └────────┼─────────┘
             │
   ┌─────────┼─────────┐
   │         │         │
┌──▼──┐ ┌───▼───┐ ┌───▼────┐
│PostgreSQL │Redis│ │MinIO S3│ ◄─── Persistent Data Layer
│ 10GB │ │2GB  │ │  20GB  │
└─────┘ └─────┘ └────────┘

┌─────────────────────────────┐
│    Monitoring &amp; Security    │
├──────────────┬──────────────┤
│ Prometheus   │   Grafana    │ ◄─── 6 Custom Dashboards
│ AlertManager │ NetworkPolicies│     Automatic Alerts
└──────────────┴──────────────┘
```

## 📋 AWS Resources Required

| Resource | Configuration | Purpose |
| --- | --- | --- |
| **EC2 Instance** | t3.xlarge (4 vCPU, 16GB RAM) | Kubernetes host |
| **EBS Volume** | 50GB gp3 | Storage |
| **Security Group** | Ports 80,443,22,30000-32767 | Network access |
| **Elastic IP** | Static IP address | DNS mapping |
| **Route 53** | Hosted Zone + A record | Domain management |
| **VPC** | Default VPC + Public subnet | Networking |

**Estimated Monthly Cost**: ~$200-250 USD

## 🚀 AWS Deployment Guide

### Step 1: AWS Infrastructure Setup

#### 1.1 Create EC2 Instance

```plaintext
# Via AWS Console:
# 1. Launch Instance → Ubuntu 20.04 LTS
# 2. Instance type: t3.xlarge  
# 3. Storage: 50GB gp3
# 4. Create new key pair: sre-platform-key.pem
# 5. Create security group: sre-platform-sg
```

#### 1.2 Configure Security Group

```plaintext
# Inbound Rules (sre-platform-sg):
Type         Protocol   Port Range    Source
SSH          TCP        22           Your-IP/32
HTTP         TCP        80           0.0.0.0/0
HTTPS        TCP        443          0.0.0.0/0
Custom TCP   TCP        30000-32767  0.0.0.0/0

# Outbound Rules:
All Traffic  All        All          0.0.0.0/0
```

#### 1.3 Allocate Elastic IP

```plaintext
# Via AWS Console:
# EC2 → Elastic IPs → Allocate Elastic IP
# Associate with your EC2 instance
```

#### 1.4 Configure DNS (Route 53)

```plaintext
# Via AWS Console:
# Route 53 → Hosted Zones → Create Hosted Zone
# Domain: thmanyah.com
# Create A record: nawaf.thmanyah.com → ELASTIC_IP
```

### Step 2: Server Preparation

#### 2.1 Connect to EC2

```plaintext
# Download your key pair and connect
chmod 400 sre-platform-key.pem
ssh -i sre-platform-key.pem ubuntu@<elastic_ip>
```

#### 2.2 Install Prerequisites

```plaintext
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Kubernetes tools
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install kubectl /usr/local/bin/kubectl

# Install utilities
sudo apt install -y jq curl wget bc git

# Logout and login to apply docker group
exit
ssh -i sre-platform-key.pem ubuntu@<elastic_ip>
```

### Step 3: Deploy Platform

#### 3.1 Clone and Configure

```plaintext
# Clone repository
git clone https://github.com/your-username/sre-assignment.git
cd sre-assignment

# Update domain configuration
./scripts/configure-dns.sh nawaf.thmanyah.com
```

#### 3.2 Start Platform

```plaintext
# Validate prerequisites
./prereq-check.sh

# Deploy complete platform (15-20 minutes)
./start.sh

# The script will automatically:
# ✅ Start Minikube cluster
# ✅ Build and push all service images  
# ✅ Install NGINX Ingress Controller
# ✅ Install cert-manager for Let's Encrypt
# ✅ Deploy all services with monitoring
# ✅ Configure HTTPS with automatic SSL certificates
# ✅ Set up ingress for nawaf.thmanyah.com
```

#### 3.3 Verify HTTPS Setup

```plaintext
# The start.sh script has already installed everything needed for HTTPS!
# Just verify the components are running:

# Check ingress controller
kubectl get pods -n ingress-nginx

# Check cert-manager
kubectl get pods -n cert-manager

# Check certificate status (Let's Encrypt)
kubectl get certificate -n production
kubectl describe certificate sre-platform-tls -n production

# Check ingress configuration
kubectl get ingress -n production
kubectl describe ingress services-ingress -n production
```

### Step 4: Verification and Access

#### 4.1 Check Deployment Status

```plaintext
# Verify all pods are running
kubectl get pods --all-namespaces

# Check certificate status  
kubectl get certificate -n production
kubectl describe certificate sre-platform-tls -n production

# Monitor ingress
kubectl get ingress -n production
kubectl describe ingress services-ingress -n production
```

#### 4.2 Access Services

```plaintext
# Primary access (HTTPS with SSL)
echo "Frontend:    https://nawaf.thmanyah.com"
echo "Grafana:     https://nawaf.thmanyah.com/grafana"
echo "Prometheus:  https://nawaf.thmanyah.com/prometheus"

# Fallback access (HTTP NodePort) - for debugging only
MINIKUBE_IP=$(minikube ip)
echo "Frontend:    http://$MINIKUBE_IP:30004"
echo "Grafana:     http://$MINIKUBE_IP:30030"
echo "Registry:    http://$MINIKUBE_IP:30501"
```

**Default Credentials:**

*   **Grafana**: admin / admin123
*   **Registry**: admin / SecurePass123!

#### 4.3 Run Tests

```plaintext
# Comprehensive platform testing
./test-scenarios.sh

# Tests include:
# ✅ SSL certificate validation
# ✅ Service connectivity and health  
# ✅ Database operations
# ✅ Auto-scaling under load
# ✅ Failure recovery scenarios
# ✅ Security policy enforcement
```

## 🔧 Configuration Management

### Update Domain

```plaintext
# Change domain after deployment
./scripts/configure-dns.sh new-domain.com

# Apply changes
kubectl apply -f kubernetes/security/04-tls-ingress.yaml
```

### Scale Services

```plaintext
# Manual scaling
kubectl scale deployment frontend --replicas=5 -n production

# Update HPA limits
kubectl patch hpa frontend-hpa -n production -p '{"spec":{"maxReplicas":15}}'
```

### Monitor Resources

```plaintext
# Resource usage
kubectl top pods --all-namespaces
kubectl top nodes

# Logs
kubectl logs -f deployment/frontend -n production
kubectl logs -f deployment/api-service -n production
```

## 🔒 Security Features

*   **HTTPS Everywhere**: All traffic encrypted with Let's Encrypt
*   **Network Isolation**: Backend services only accessible via frontend
*   **Secrets Management**: All credentials stored as Kubernetes secrets
*   **Private Registry**: Container images stored in authenticated registry
*   **Security Policies**: NetworkPolicies restrict pod-to-pod communication
*   **Resource Limits**: CPU/Memory limits prevent resource abuse

## 📊 Monitoring & Alerting

**6 Custom Grafana Dashboards:**

1.  **System Overview**: Cluster health and resource usage
2.  **API Service**: Request rates, latency, error rates
3.  **Auth Service**: Authentication metrics and performance
4.  **Image Service**: Upload/processing statistics
5.  **Database Layer**: PostgreSQL, Redis, MinIO metrics
6.  **Security Dashboard**: Failed authentications, policy violations

**Automatic Alerts:**

*   High CPU/Memory usage
*   Service downtime
*   Database connection failures
*   SSL certificate expiration
*   Storage space warnings

## 🚨 Troubleshooting

### SSL Certificate Issues

```plaintext
# Check certificate status
kubectl get certificate -n production
kubectl describe certificate sre-platform-tls -n production

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Manual certificate request
kubectl delete certificate sre-platform-tls -n production
kubectl apply -f kubernetes/security/04-tls-ingress.yaml
```

### Service Issues

```plaintext
# Check pod status
kubectl get pods -n production
kubectl describe pod <pod-name> -n production

# Check service endpoints
kubectl get endpoints -n production

# Restart deployment
kubectl rollout restart deployment/<service-name> -n production
```

### DNS Issues

```plaintext
# Test DNS resolution
nslookup nawaf.thmanyah.com
dig nawaf.thmanyah.com

# Check ingress
kubectl get ingress -n production -o yaml
```

## 🛠️ Maintenance

### Backup Data

```plaintext
# Database backup
kubectl exec -n production deployment/postgresql -- pg_dump -U postgres sre_db &gt; backup.sql

# Redis backup  
kubectl exec -n production deployment/redis -- redis-cli BGSAVE
```

### Update Services

```plaintext
# Build new image
docker build -t api-service:v2.0 ./services/api-service/

# Push to registry
docker tag api-service:v2.0 $(minikube ip):30500/api-service:v2.0
docker push $(minikube ip):30500/api-service:v2.0

# Update deployment
kubectl set image deployment/api-service api-service=$(minikube ip):30500/api-service:v2.0 -n production
```

### Platform Cleanup

```plaintext
# Stop services (preserve data)
./stop.sh

# Complete cleanup
./stop.sh --delete-cluster

# AWS resource cleanup
# - Terminate EC2 instance
# - Release Elastic IP  
# - Delete security group
# - Remove DNS records
```

## 📈 Performance Optimization

**For Production Traffic:**

*   Upgrade to `c5.2xlarge` (8 vCPU, 16GB RAM)
*   Use Application Load Balancer instead of NodePort
*   Implement Redis Cluster for high availability
*   Consider RDS for managed PostgreSQL
*   Add CloudFront CDN for static assets

**Monitoring Recommendations:**

*   Set up CloudWatch integration
*   Configure automated backups
*   Implement log aggregation with ELK stack
*   Add distributed tracing with Jaeger

**🏆 Complete Production Kubernetes Platform - Ready for Enterprise!**