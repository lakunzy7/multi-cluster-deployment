# AuthenticWrite: Multi-Cluster Kubernetes Deployment

GitOps repository for deploying AuthenticWrite (backend + frontend) across multiple Kubernetes clusters using ArgoCD and Kargo.

## Features

* **Warehouse** monitoring container registries for new images
* **Three-Stage Pipeline**: dev → staging → prod
* **Image Tag Promotion**: Automatic image discovery and promotion
* **Multi-Cluster Support**: Deploy to Kind (local) and GKE (cloud)
* **Helm-based Deployment**: Templated manifests with environment overrides
* **GitOps Automation**: Kargo commits image updates, ArgoCD syncs

## Requirements

* Kargo v1.3+ (or switch to appropriate release branch)
* ArgoCD v2.8+
* kubectl configured with access to target clusters
* GitHub account with GHCR (GitHub Container Registry) access
* Git installed locally

## Quick Start

### 1. Prerequisites Check

```bash
# Verify kubectl access to clusters
kubectl config get-contexts

# Ensure ArgoCD is running
kubectl get pods -n argocd | head -5

# Verify Kargo is installed
kubectl get pods -n kargo | head -5
```

### 2. Configure Credentials

Add Git credentials to Kargo so it can commit image updates:

```bash
kargo create credentials github-creds \
  --project authenticwrite \
  --git \
  --username <your-github-username> \
  --repo-url https://github.com/lakunzy7/multi-cluster-deployment.git
```

**Important**: The token must have permission to:
- Commit changes to this repository
- Create pull requests (if using PR mode)

### 3. Deploy ArgoCD Resources

```bash
# Create AppProject (defines deployment boundaries)
kubectl apply -f argocd/appproj.yaml

# Create ApplicationSet (generates Applications for each environment)
kubectl apply -f argocd/appset.yaml
```

Verify Applications are created:
```bash
kubectl get applications -n argocd | grep authenticwrite
```

### 4. Deploy Kargo Resources

```bash
# Create Kargo Project namespace
kubectl apply -f kargo/project.yaml

# Create Warehouse (monitors image registries)
kubectl apply -f kargo/warehouse.yaml

# Create Stages (dev → staging → prod pipeline)
kubectl apply -f kargo/stages.yaml

# Create PromotionTask (defines promotion workflow)
kubectl apply -f kargo/promotiontask.yaml
```

Verify Kargo resources:
```bash
kubectl get warehouses -n authenticwrite
kubectl get stages -n authenticwrite
kubectl get promotiontasks -n authenticwrite
```

### 5. Sync Applications

Trigger ArgoCD to deploy applications:

```bash
argocd app sync authenticwrite-dev
argocd app sync authenticwrite-staging
argocd app sync authenticwrite-prod
```

Or use kubectl:
```bash
kubectl patch application authenticwrite-dev -n argocd \
  --type merge -p '{"operation":"sync"}'
```

## Directory Structure

```
.
├── README.md                          # This file
├── argocd/
│   ├── appproj.yaml                  # ArgoCD Project (security boundary)
│   └── appset.yaml                   # ApplicationSet (generates Applications)
├── kargo/
│   ├── project.yaml                  # Kargo Project namespace
│   ├── warehouse.yaml                # Image registry monitoring
│   ├── stages.yaml                   # Three stages: dev, staging, prod
│   └── promotiontask.yaml            # Promotion workflow definition
├── charts/
│   └── authenticwrite/               # Helm chart for AuthenticWrite
│       ├── Chart.yaml
│       ├── values.yaml               # Base values
│       └── templates/
│           ├── namespace.yaml
│           ├── backend.yaml
│           ├── frontend.yaml
├── env/                              # Environment-specific values
│   ├── dev/values.yaml               # Dev environment config
│   ├── staging/values.yaml           # Staging environment config
│   └── prod/values.yaml              # Production environment config
├── helm/                             # Infrastructure Helm values
│   ├── argocd/values.yaml            # ArgoCD installation config
│   └── kargo/values.yaml             # Kargo installation config
├── terraform/                        # GKE infrastructure as code
└── .github/workflows/                # CI/CD pipelines
```

## Deployment Pipeline

### Image Promotion Flow

```
1. AuthenticWrite repo builds images → pushes to ghcr.io
   ↓
2. Kargo Warehouse detects new images
   ↓
3. Freight created with new image tags
   ↓
4. User promotes Freight through stages:
   - dev (auto-promotion)
   - staging (manual approval)
   - prod (manual approval)
   ↓
5. PromotionTask runs:
   - Git clone this repo
   - Update image tags in env/{stage}/values.yaml
   - Commit and push changes
   - Trigger ArgoCD sync
   ↓
6. ArgoCD syncs updated Helm values to clusters
   ↓
7. New images deployed to environment
```

### Stages

| Stage | Environment | Replicas | Approval | Description |
|-------|------------|----------|----------|-------------|
| **dev** | authenticwrite-dev | 1 | Auto | Development environment |
| **staging** | authenticwrite-staging | 2 | Manual | Pre-production testing |
| **prod** | authenticwrite-prod | 3 | Manual | Production deployment |

## Key Files

| File | Purpose |
|------|---------|
| `argocd/appproj.yaml` | Defines which repos/clusters ArgoCD can deploy to |
| `argocd/appset.yaml` | Generates Applications for each env (dev/staging/prod) |
| `kargo/warehouse.yaml` | Monitors `ghcr.io/lakunzy7/authenticwrite/{backend,frontend}` |
| `kargo/stages.yaml` | Defines promotion stages and approval requirements |
| `kargo/promotiontask.yaml` | Script that updates image tags and triggers ArgoCD |
| `charts/authenticwrite/` | Helm chart deployed by ArgoCD |
| `env/{dev,staging,prod}/values.yaml` | Per-environment configurations (replicas, resources, etc.) |

## Useful Commands

### View Status

```bash
# Check ArgoCD Applications
kubectl get applications -n argocd

# Check Kargo Warehouse
kubectl get warehouses -n authenticwrite

# Check Kargo Stages
kubectl get stages -n authenticwrite

# Check created Freight (detected images)
kubectl get freight -n authenticwrite

# Check Promotions
kubectl get promotions -n authenticwrite
```

### Port Forward to UI

```bash
# ArgoCD (https://localhost:8080)
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Kargo (http://localhost:3100)
kubectl port-forward -n kargo svc/kargo-api 3100:3100
```

### Promote Images (CLI)

```bash
# Promote to staging (requires manual approval)
kargo promote authenticwrite staging --from dev

# Promote to prod
kargo promote authenticwrite prod --from staging

# Check promotion status
kargo get promotion -n authenticwrite
```

### Check Application Deployments

```bash
# Check dev environment
kubectl get deployments -n authenticwrite-dev
kubectl get pods -n authenticwrite-dev

# Check staging environment
kubectl get deployments -n authenticwrite-staging
kubectl get pods -n authenticwrite-staging

# Check prod environment
kubectl get deployments -n authenticwrite-prod
kubectl get pods -n authenticwrite-prod
```

### View Logs

```bash
# Kargo controller logs
kubectl logs -n kargo deployment/kargo-controller -f

# ArgoCD application controller
kubectl logs -n argocd deployment/argocd-application-controller -f

# Backend deployment
kubectl logs -n authenticwrite-dev deployment/backend -f

# Frontend deployment
kubectl logs -n authenticwrite-dev deployment/frontend -f
```

## Environment Configuration

Each environment has its own values file that overrides the base chart:

### Dev (`env/dev/values.yaml`)
- 1 replica (fast feedback)
- Lower resource requests

### Staging (`env/staging/values.yaml`)
- 2 replicas (test scaling)
- Production-like resources

### Prod (`env/prod/values.yaml`)
- 3 replicas (high availability)
- Higher resource limits
- Ingress enabled

## Troubleshooting

### Applications not syncing

```bash
# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller

# Check Application status
kubectl describe application authenticwrite-dev -n argocd

# Manual sync
argocd app sync authenticwrite-dev
```

### Kargo not detecting images

```bash
# Check Warehouse status
kubectl describe warehouse authenticwrite -n authenticwrite

# Check if images are public on GHCR
# https://github.com/lakunzy7?tab=packages

# Manually trigger Warehouse refresh
kubectl rollout restart deployment/kargo-controller -n kargo
```

### Promotion failing

```bash
# Check Promotion status
kubectl describe promotion <promotion-name> -n authenticwrite

# Check PromotionTask logs (in promotion pod)
kubectl logs -n authenticwrite -l app=kargo,promotion=<promotion-id>

# Check Git credentials
kubectl get secret github-creds -n authenticwrite -o yaml
```

### Pods not running in environment namespace

```bash
# Check if namespace exists
kubectl get ns authenticwrite-dev

# Check if Helm release exists
helm list -n authenticwrite-dev

# Get application status
kubectl describe application authenticwrite-dev -n argocd

# Check resource quotas
kubectl describe quota -n authenticwrite-dev
```

## Multi-Cluster Setup

This repo supports deploying to multiple clusters. Clusters must be registered in ArgoCD.

Register additional cluster:
```bash
argocd cluster add <cluster-context> --name <cluster-name>
```

The ApplicationSet will automatically deploy to all registered clusters.

## Next Steps

1. **Verify Prerequisites**: Run `./verify-setup.sh` (if available)
2. **Deploy**: Follow "Quick Start" section above
3. **Test Promotion**: Manually promote via Kargo UI or CLI
4. **Monitor**: Watch logs and check pod status
5. **Iterate**: Update values in `env/{stage}/values.yaml` to test changes

## Support & Documentation

- **Kargo Docs**: https://kargo.akuity.io
- **ArgoCD Docs**: https://argo-cd.readthedocs.io
- **Helm Docs**: https://helm.sh/docs

---

**Status**: Ready to deploy 🚀
