# Architecture Documentation

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           External Traffic                           │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        Ingress Controller                           │
│                    (TLS Termination)                                │
└─────────────────┬───────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Production Namespace                           │
├─────────────────┬─────────────────┬───────────────────────────────────┤
│                 │                 │                                 │
│  ┌─────────────▼──┐  ┌────────────▼──┐  ┌─────────────▼──────────┐   │
│  │  API Service   │  │ Auth Service  │  │   Image Service       │   │
│  │   (Node.js)    │  │    (Go)       │  │    (Python)           │   │
│  │                │  │               │  │                       │   │
│  │ - HPA enabled  │  │ - HPA enabled │  │ - HPA enabled         │   │
│  │ - 2 replicas   │  │ - 2 replicas  │  │ - 2 replicas          │   │
│  │ - Port 3000    │  │ - Port 8080   │  │ - Port 5000           │   │
│  └────────────────┘  └───────────────┘  └───────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                  │
                  ▼ (Network Policies Applied)
┌─────────────────────────────────────────────────────────────────────┐
│                     External Dependencies                           │
├─────────────────┬─────────────────┬───────────────────────────────────┤
│                 │                 │                                 │
│ ┌──────────────▼┐ ┌──────────────▼┐ ┌────────────────▼─────────────┐ │
│ │  PostgreSQL   │ │   Redis       │ │        S3 Storage           │ │
│ │  Database     │ │   Cache       │ │     (Image Storage)         │ │
│ └───────────────┘ └───────────────┘ └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                  
┌─────────────────────────────────────────────────────────────────────┐
│                      Monitoring Namespace                           │
├─────────────────┬─────────────────┬───────────────────────────────────┤
│                 │                 │                                 │
│ ┌──────────────▼┐ ┌──────────────▼┐ ┌────────────────▼─────────────┐ │
│ │  Prometheus   │ │   Grafana     │ │      Alertmanager           │ │
│ │   (Metrics)   │ │ (Dashboards)  │ │    (Notifications)          │ │
│ │               │ │               │ │                             │ │
│ │ - Scrapes all │ │ - 4 Custom    │ │ - Email alerts             │ │
│ │   services    │ │   dashboards  │ │ - Slack integration        │ │
│ │ - Port 9090   │ │ - Port 3000   │ │ - Port 9093                │ │
│ └───────────────┘ └───────────────┘ └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        Default Namespace                            │
├─────────────────┬───────────────────────────────────────────────────┤
│                 │                                                   │
│ ┌──────────────▼┐ ┌────────────────▼─────────────────────────────┐   │
│ │Docker Registry│ │              Registry UI                    │   │
│ │               │ │                                             │   │
│ │ - Private     │ │ - Web interface                             │   │
│ │ - Secured     │ │ - Port 80                                   │   │
│ │ - Port 5000   │ │                                             │   │
│ └───────────────┘ └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Component Details

### Services Communication Flow

1. **External Request** → Ingress Controller
2. **Ingress** → Routes to appropriate service based on path
3. **Services** → Communicate internally via ClusterIP
4. **Database Access** → Services connect to external PostgreSQL
5. **Image Storage** → Image service uploads to S3
6. **Authentication Flow** → API service validates tokens with Auth service

### Security Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Security Layers                             │
├─────────────────────────────────────────────────────────────────────┤
│ Layer 1: TLS Termination (Let's Encrypt certificates)              │
│ Layer 2: Network Policies (Restrict pod-to-pod communication)      │
│ Layer 3: RBAC (Service accounts with minimal permissions)          │
│ Layer 4: Secrets Management (Encrypted credential storage)         │
│ Layer 5: Container Security (Non-root users, readonly filesystem)  │
└─────────────────────────────────────────────────────────────────────┘
```

### Monitoring & Alerting Flow

```
Services (metrics) → Prometheus (scraping) → Grafana (visualization)
                                    ↓
                              Alert Rules → Alertmanager → External Notifications
                                                               ├─ Email
                                                               └─ Slack
```

### High Availability & Scaling

- **HPA**: Auto-scales based on CPU/Memory/Request metrics
- **Multiple Replicas**: Each service runs 2+ instances
- **PodDisruptionBudgets**: Ensures minimum availability during updates
- **Health Checks**: Liveness/Readiness probes for all services
- **Load Balancing**: Kubernetes services distribute traffic

### Network Isolation

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Network Policies                                 │
├─────────────────────────────────────────────────────────────────────┤
│ • API Service: Can communicate with Auth + Database                │
│ • Auth Service: Can communicate with Database only                 │
│ • Image Service: Can communicate with S3 + Database               │
│ • Monitoring: Can scrape metrics from all services                │
│ • Default deny all other traffic                                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Authentication Flow
1. Client → API Service (with JWT token)
2. API Service → Auth Service (validate token)
3. Auth Service → Database (check user)
4. Response back through chain

### Image Upload Flow
1. Client → Image Service (upload request)
2. Image Service → S3 Storage (store image)
3. Image Service → Database (store metadata)
4. Response to client with image URL

### Monitoring Data Flow
1. Services → Export metrics on /metrics endpoint
2. Prometheus → Scrapes metrics every 15s
3. Grafana → Queries Prometheus for dashboard data
4. Alert Rules → Evaluate conditions → Alertmanager
5. Alertmanager → Send notifications to configured channels

## Deployment Architecture

### Build & Deploy Pipeline
```
Source Code → Docker Build → Private Registry → Kubernetes Deploy
                                ↓
                          Registry Authentication
                                ↓
                        Pull Images in Cluster
```

### Namespace Isolation
- **production**: Application services
- **monitoring**: Observability stack  
- **default**: Infrastructure services (registry)
- **cert-manager**: TLS certificate management
- **ingress-nginx**: Ingress controller