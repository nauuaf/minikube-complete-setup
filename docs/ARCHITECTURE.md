# SRE Assignment Architecture

## Overview

This document describes the architecture of the SRE Assignment microservices platform, designed to demonstrate production-ready Kubernetes practices.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Ingress Controller                    │
│                 (NGINX + cert-manager)                   │
└─────────────┬───────────────┬───────────────┬───────────┘
              │               │               │
    ┌─────────▼─────┐ ┌───────▼──────┐ ┌─────▼──────┐
    │  API Service  │ │ Auth Service │ │Image Service│
    │   (Node.js)   │ │     (Go)     │ │  (Python)   │
    │   Port 3000   │ │  Port 8080   │ │  Port 5000  │
    └───────────────┘ └──────────────┘ └─────────────┘
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
- **Deployments**: Each service has its own deployment with 2 replicas minimum
- **Services**: NodePort services for external access
- **HPA**: Horizontal Pod Autoscaler with 70% CPU threshold
- **PDB**: Pod Disruption Budget to ensure availability
- **NetworkPolicies**: Service isolation and security

#### Security Components
- **Secrets**: All sensitive data stored in Kubernetes Secrets
- **TLS/SSL**: cert-manager with Let's Encrypt integration
- **Registry Auth**: Private Docker registry with authentication
- **RBAC**: Proper role-based access control

#### Monitoring Stack
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization with 4 pre-configured dashboards
- **Custom Metrics**: Application-specific metrics from all services

### Data Flow

1. **External Request** → Ingress Controller (NGINX)
2. **Ingress** → API Service (Load Balancer)
3. **API Service** → Auth Service (Token validation)
4. **API Service** → Image Service (Processing request)
5. **Response** ← Image Service ← API Service ← Client

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