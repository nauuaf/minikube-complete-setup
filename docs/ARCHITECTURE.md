# SRE Platform Architecture

## Overview

This document describes the architecture of the production-ready microservices platform, featuring HTTPS/TLS with Let's Encrypt, comprehensive monitoring, and security best practices on Kubernetes.

## System Architecture

### High-Level Architecture

```
🌐 Internet (HTTPS - nawaf.thmanyah.com)
                    │
          ┌─────────▼─────────┐
          │ NGINX Ingress +   │ ◄─── Let's Encrypt TLS Certificates
          │  cert-manager     │      Automatic SSL renewal
          └─────────┬─────────┘
                    │ Single entry point (HTTPS only)
            ┌───────▼───────┐
            │   Frontend    │ ◄─── React SPA + nginx proxy
            │ (React/nginx) │      Routes all backend calls
            │   Port 3000   │
            │   HPA: 2-10   │
            └───────┬───────┘
                    │ Internal ClusterIP routing
        ┌───────────┼───────────┐
        │           │           │
    ┌───▼──┐   ┌────▼───┐   ┌──▼────┐
    │ API  │   │  Auth  │   │ Image │ ◄─── Backend Services (ClusterIP only)
    │Node.js│   │   Go   │   │Python │     No external access
    │ 3000 │   │  8080  │   │ 5000  │     Auto-scaling enabled  
    │HPA:2-5│   │HPA:2-5 │   │HPA:2-5│
    └───┬──┘   └────┬───┘   └───┬───┘
        │           │           │
        └───────────┼───────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
    ┌───▼──┐   ┌────▼────┐  ┌──▼────┐
    │PostgreSQL│ │Redis   │  │MinIO  │ ◄─── Data Layer (Persistent)
    │ 10GB  │  │ Cache  │  │  S3   │      Secure internal access
    │ 5432  │  │ 6379   │  │ 9000  │      Network policies applied
    └───────┘  └─────────┘  └───────┘
```

### Service Details

#### API Service (Node.js)
- **Purpose**: API Gateway and main entry point
- **Technology**: Node.js with Express.js
- **Port**: 3000
- **Features**:
  - JWT token validation
  - Service orchestration
  - Prometheus metrics collection
  - Health checks and readiness probes

#### Auth Service (Go)
- **Purpose**: Authentication and authorization
- **Technology**: Go (Golang)
- **Port**: 8080
- **Features**:
  - Token generation and validation
  - Service-to-service authentication
  - High-performance authentication
  - Built-in metrics endpoint

#### Image Service (Python)
- **Purpose**: Image processing operations
- **Technology**: Python with Flask
- **Port**: 5000
- **Features**:
  - Image processing simulation
  - S3-compatible storage integration
  - Prometheus metrics with custom instrumentation
  - Processing time tracking

### Infrastructure Components

#### Kubernetes Resources
- **Deployments**: Each service has its own deployment with 2+ replicas
- **Services**: Frontend (NodePort), Backend services (ClusterIP only)  
- **Ingress**: Single HTTPS ingress with Let's Encrypt (nawaf.thmanyah.com)
- **HPA**: Horizontal Pod Autoscaler with 70% CPU threshold
- **PDB**: Pod Disruption Budget to ensure availability
- **NetworkPolicies**: Strict service isolation and security

#### Security Components
- **Secrets**: All sensitive data stored in Kubernetes Secrets
- **TLS/SSL**: cert-manager with Let's Encrypt integration
- **Registry Auth**: Private Docker registry with authentication
- **RBAC**: Proper role-based access control

#### Monitoring Stack
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization with 6 pre-configured dashboards
- **AlertManager**: Automated alerting and notifications
- **Custom Metrics**: Application-specific metrics from all services
- **Data Layer Monitoring**: PostgreSQL, Redis, MinIO metrics

### Data Flow

1. **External HTTPS Request** → NGINX Ingress (nawaf.thmanyah.com)
2. **Ingress** → Frontend Service (React SPA)
3. **Frontend nginx** → API/Auth/Image Services (Internal routing)
4. **Backend Services** → PostgreSQL/Redis/MinIO (Data layer)
5. **Response** ← Data Layer ← Backend Services ← Frontend ← Client

### Scalability Features

- **Horizontal Pod Autoscaler**: Automatic scaling based on CPU utilization
- **Multiple Replicas**: Each service runs with 2-5 replicas
- **Load Balancing**: Kubernetes native load balancing
- **Resource Limits**: Proper CPU and memory limits set

### High Availability

- **Pod Disruption Budgets**: Minimum 1 pod always available
- **Health Checks**: Liveness and readiness probes
- **Multiple Replicas**: Redundancy across all services
- **Graceful Shutdown**: Proper SIGTERM handling

### Security Architecture

- **Network Segmentation**: NetworkPolicies isolate services
- **Secrets Management**: No hardcoded credentials
- **TLS Encryption**: End-to-end encryption
- **Private Registry**: Secure container image storage

## Deployment Strategy

### Blue-Green Deployment Ready
- Service mesh compatibility
- Rolling updates with zero downtime
- Health check integration

### Monitoring & Observability
- Comprehensive metrics collection
- Dashboard visualization
- Alert management integration
- Distributed tracing ready

## Disaster Recovery

- **Backup Strategy**: Configuration stored in Git
- **Recovery Time**: < 10 minutes full recovery
- **Data Persistence**: Stateless services design
- **Infrastructure as Code**: Complete automation

## Performance Characteristics

- **Response Time**: < 100ms average
- **Throughput**: 1000+ requests/second per service
- **Scalability**: 2-5 pods per service automatically
- **Availability**: 99.9% uptime target