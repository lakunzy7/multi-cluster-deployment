# CloudOpsHub: Multi-Cluster Kubernetes Infrastructure Platform

A complete DevOps infrastructure platform for deploying analytics applications across multiple Kubernetes clusters with centralized continuous delivery, observability, and disaster recovery.

## Overview

CloudOpsHub provides:
- **Multi-Cluster Management**: Local + GCP GKE clusters
- **Centralized CD**: ArgoCD managing all deployments
- **Full Observability**: Prometheus, Grafana, Loki, Jaeger
- **Secure CI/CD**: Vulnerability scanning, secrets management
- **Managed Database**: Cloud SQL with automatic backups
- **Infrastructure-as-Code**: Terraform for reproducible deployments

## Project Structure

```
├── terraform/                   # Infrastructure provisioning
│   ├── main.tf                 # GKE cluster, networking, Cloud SQL
│   ├── variables.tf            # Input variables
│   ├── outputs.tf              # Cluster endpoints, credentials
│   └── rds.tf                  # Cloud SQL database
│
├── kubernetes/                  # Cluster configurations
│   ├── argocd-*.yml            # ArgoCD installation & applications
│   ├── namespaces.yml          # Namespace definitions
│   ├── storage-class.yml       # Storage configuration
│   ├── network-policies.yml    # Network security policies
│   └── cluster-secrets.yml     # Secret templates
│
├── ansible/                     # Post-provisioning configuration
│   ├── site.yml                # Main playbook
│   ├── inventory.yml           # Host definitions
│   └── roles/                  # Ansible roles (common, kubernetes, etc)
│
├── ci-cd/                       # CI/CD pipeline definitions
│   └── .gitlab-ci.yml          # GitLab CI pipeline
│
├── monitoring/                  # Observability stack
│   ├── prometheus-config.yml   # Prometheus configuration
│   └── grafana-datasources.yml # Grafana data sources
│
├── scripts/                     # Operational scripts
│   ├── deploy.sh               # Deployment automation
│   ├── backup.sh               # Backup creation
│   └── restore.sh              # Restore procedures
│
└── docs/                        # Documentation
    ├── ARCHITECTURE.md         # System design
    ├── SETUP.md                # Deployment guide
    ├── QUICK_START.md          # 5-minute setup
    ├── DEPLOYMENT_RUNBOOK.md   # Operational procedures
    └── MONITORING_RUNBOOK.md   # Monitoring & troubleshooting
```

## Getting Started

### Quick Start (5 minutes)
See [Quick Start Guide](docs/QUICK_START.md)

### Full Deployment (30 minutes)
See [Complete Setup Guide](docs/SETUP.md)

### Architecture Overview
See [Architecture Documentation](docs/ARCHITECTURE.md)

## Key Features

### Infrastructure
- **Terraform IaC**: Reproducible, version-controlled infrastructure
- **Multi-cluster**: Local (Kind/k3s) + GCP GKE
- **Managed Services**: Cloud SQL, Cloud Storage, Secret Manager
- **Network Isolation**: VPC, firewall rules, network policies

### Continuous Delivery
- **ArgoCD**: Single control point for all deployments
- **Multi-environment**: Dev → Staging → Production
- **GitOps**: Declarative configuration in Git
- **Automated Sync**: Continuous reconciliation of actual vs desired state

### CI/CD Pipeline
- **Container Building**: Docker image creation
- **Security Scanning**: Trivy vulnerability scanning, Gitleaks secrets detection
- **Registry Management**: Push to Docker Hub / Artifact Registry
- **Automated Testing**: Test in dev, manual approval for prod

### Observability
- **Metrics**: Prometheus + Grafana dashboards
- **Logs**: Loki log aggregation with Grafana UI
- **Traces**: Jaeger distributed tracing
- **Alerts**: Alertmanager with configurable thresholds

### Security
- **Secrets Management**: Kubernetes secrets + Google Secret Manager
- **Network Policies**: Pod-to-pod communication control
- **RBAC**: Role-based access control for clusters
- **Audit Logging**: Track all cluster changes

### Resilience
- **Automated Backups**: Velero for Kubernetes, Cloud SQL snapshots
- **High Availability**: Multi-zone database, cluster autoscaling
- **Disaster Recovery**: Point-in-time recovery, cross-region failover ready
- **Rollback Capabilities**: Git-based and kubectl rollout

## Deployment Timeline

| Phase | Duration | Key Activities |
|-------|----------|-----------------|
| Setup | 5 min | Install tools, authenticate with GCP |
| Infrastructure | 10-15 min | Run Terraform, provision GKE + Cloud SQL |
| Kubernetes Config | 5 min | Deploy namespaces, storage classes, network policies |
| Monitoring | 5 min | Install Prometheus, Grafana, Loki |
| ArgoCD | 10 min | Install and configure centralized CD |
| Applications | 5 min | Deploy applications via ArgoCD |

**Total: ~45 minutes for full deployment**

## Operations

### Deploying Applications
```bash
./scripts/deploy.sh dev v1.0.0       # Deploy to dev
./scripts/deploy.sh staging v1.0.0   # Deploy to staging
./scripts/deploy.sh prod v1.0.0      # Deploy to production
```

### Creating Backups
```bash
./scripts/backup.sh local-cluster    # Backup local cluster
./scripts/backup.sh cloud-cluster    # Backup cloud cluster
```

### Restoring from Backup
```bash
./scripts/restore.sh backup-20240101-120000 local-cluster
```

## Monitoring & Troubleshooting

- **Prometheus**: `kubectl port-forward -n monitoring svc/prometheus 9090:9090`
- **Grafana**: `kubectl port-forward -n monitoring svc/grafana 3000:80`
- **Logs**: Check Loki dashboard in Grafana
- **Traces**: `kubectl port-forward -n monitoring svc/jaeger-query 16686:16686`

See [Monitoring Runbook](docs/MONITORING_RUNBOOK.md) for detailed procedures.

## Configuration

### Terraform Variables
Copy `terraform/terraform.tfvars.example` and customize:
```bash
gcp_project        = "your-project-id"
gcp_region         = "europe-west1"
node_count         = 3
instance_type      = "e2-medium"
```

### Environment Variables
```bash
export GCP_PROJECT="your-project-id"
export KUBECONFIG=~/.kube/kind-local-cluster:~/.kube/gke
```

## Security Considerations

1. **Secrets Management**: Use Google Secret Manager for sensitive data
2. **Network Policies**: Enforce pod-to-pod communication rules
3. **RBAC**: Limit service account permissions
4. **Image Security**: Enable Binary Authorization for prod
5. **Audit Logging**: Enable cluster audit logging
6. **Database Security**: Use private endpoints, IAM authentication

## Cost Optimization

- **Right-sizing**: Use `e2-medium` for dev/staging, larger for prod
- **Spot Instances**: Enable preemptible nodes for non-critical workloads
- **Lifecycle Policies**: Automatic cleanup of old backups
- **Reserved Capacity**: For predictable production workloads

## Support & Documentation

- **Architecture**: [ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Setup Guide**: [SETUP.md](docs/SETUP.md)
- **Deployment Procedures**: [DEPLOYMENT_RUNBOOK.md](docs/DEPLOYMENT_RUNBOOK.md)
- **Monitoring Guide**: [MONITORING_RUNBOOK.md](docs/MONITORING_RUNBOOK.md)

## Contributing

For changes to infrastructure:
1. Update Terraform configurations
2. Run `terraform plan` and review changes
3. Test in dev environment first
4. Apply to staging, then production

For application deployments:
1. Update manifests in application repository
2. Create pull request
3. Wait for CI pipeline
4. Merge to trigger ArgoCD sync

## License

Copyright CloudOpsHub. All rights reserved.
