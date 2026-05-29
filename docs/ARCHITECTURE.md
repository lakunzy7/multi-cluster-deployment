# CloudOpsHub Architecture

## Overview

CloudOpsHub is an automated multi-cluster Kubernetes infrastructure platform designed to provide:
- Multi-environment deployment (dev, staging, production)
- Distributed cluster management across regions
- Centralized continuous delivery via ArgoCD
- Comprehensive observability and security

## Infrastructure Components

### Clusters
- **Local Cluster**: Self-managed Kubernetes cluster via Kind or k3s (3 worker nodes)
- **Cloud Cluster**: Google GKE managed Kubernetes cluster (3 worker nodes)

### Networking
- VPC with subnets across 2 zones in GCP region
- Cloud NAT for egress traffic from private resources
- Firewall rules for cluster-to-cluster communication
- VPC Peering/Private Service Connection for inter-cluster networking

### Data Storage
- **Cloud SQL PostgreSQL**: Multi-zone database for application data
- **Persistent Volumes**: GCP Compute Engine persistent disks for Kubernetes
- **GCS Buckets**: Cloud Storage buckets for backups with versioning and lifecycle policies

### Container Registry
- Docker Hub, Artifact Registry, or Container Registry for images
- Vulnerability scanning (Trivy) on push
- Image signing and Binary Authorization

## CI/CD Pipeline

```
Git Commit
    ↓
[Build & Test] → docker build
    ↓
[Security Scan] → vulnerability scan + secrets scan
    ↓
[Push Image] → registry push
    ↓
[Deploy Dev] → local cluster (dev namespace)
    ↓
[Deploy Staging] → local cluster (staging namespace) [MANUAL]
    ↓
[Deploy Prod] → cloud cluster (production namespace) [MANUAL]
```

**Tools**: GitLab CI, Docker, Trivy, Gitleaks

## Deployment Architecture

### ArgoCD Multi-Cluster Management

```
                    Local Cluster
                  ┌──────────────┐
                  │   ArgoCD     │ (Primary CD controller)
                  │   - Server   │
                  │   - Controller
                  └──────────────┘
                    /         \
                   /           \
        Dev/Staging (local)   Prod (cloud-eks)
        ┌──────────────┐      ┌──────────────┐
        │ Development  │      │ Cloud EKS    │
        │ Staging      │      │ Production   │
        └──────────────┘      └──────────────┘
```

### Application Deployment Flow
1. Developers push code to Git repository
2. CI pipeline builds and tests containers
3. Vulnerability scanning validates security
4. Images pushed to registry with version tags
5. Git push triggers ArgoCD sync
6. ArgoCD applies manifests to target clusters
7. Kubernetes orchestrates pod deployment

## Observability Stack

### Monitoring
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Alertmanager**: Alert routing and notifications

### Logging
- **Loki**: Log aggregation (lightweight alternative to ELK)
- **Promtail**: Log shipper to Loki
- **Grafana Loki UI**: Log querying and visualization

### Distributed Tracing
- **Jaeger**: Distributed tracing for request flows
- **Instrumentation**: OpenTelemetry SDK in applications

### Alerts
- Pod crash loops
- Node failures
- High resource utilization (CPU, memory, disk)
- PVC usage threshold violations
- API latency spikes

## Security Architecture

### Network Security
- VPC isolation
- Security groups restricting traffic
- Network policies for pod-to-pod communication

### Secrets Management
- AWS Secrets Manager for RDS credentials
- Kubernetes secrets for application secrets
- Secret scanning in CI/CD pipeline

### Access Control
- RBAC for cluster authentication
- Service accounts per deployment
- ArgoCD multi-cluster RBAC

### Compliance
- Audit logging of cluster changes
- Image vulnerability scanning
- Container security scanning (Falco)

## Backup and Recovery

### Backup Strategy
- **Database**: Automated RDS snapshots (daily)
- **Cluster State**: Velero for Kubernetes resource backup
- **Application Data**: PV snapshots via EBS

### Recovery Procedures
- RDS point-in-time recovery
- Velero restore to recover cluster state
- Rollback via ArgoCD Git history

## Resource Allocation

### Development
- Minimal compute: t3.small instances
- 1 control plane + 1 worker node
- Dev database: RDS t3.small

### Staging
- Standard compute: t3.medium instances
- 1 control plane + 2 worker nodes
- Staging database: RDS t3.medium

### Production
- Enhanced compute: t3.large instances
- Multi-AZ setup (3+ worker nodes)
- Multi-AZ RDS with failover

## Cost Optimization

- Right-sizing instances by environment
- Using spot instances for non-critical workloads
- S3 lifecycle policies for old backups
- Reserved capacity for predictable workloads
- VPC Endpoints for AWS service access (no data egress costs)

## Disaster Recovery

- Multi-region deployment ready (cloud cluster in different region)
- Automated failover for RDS (Multi-AZ)
- Cross-cluster networking for failover scenarios
- Regular recovery testing via restore procedures
