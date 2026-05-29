# eShop Application Deployment Guide

## Overview

This guide explains how to deploy the eShop .NET 9 application to the CloudOpsHub multi-cluster Kubernetes platform using GitOps principles with ArgoCD.

## Architecture

The eShop application consists of the following microservices:

```
┌─────────────────────────────────────┐
│        eShop Web (Frontend)          │
│        ASP.NET Core Blazor           │
│        Port: 8080/8443               │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┬──────────┬──────────┐
       │               │          │          │
┌──────▼─────┐ ┌──────▼────┐ ┌──▼──────┐ ┌──▼──────┐
│  Catalog   │ │   Basket  │ │  Order  │ │ Payment │
│    API     │ │    API    │ │   API   │ │   API   │
│ Port: 8080 │ │ 8080      │ │ 8080    │ │ 8080    │
└──────┬─────┘ └──────┬────┘ └──┬──────┘ └──┬──────┘
       │              │         │           │
       └──────────────┼─────────┴───────────┘
                      │
           ┌──────────┴──────────┐
           │                     │
      ┌────▼────┐         ┌─────▼──┐
      │ Cloud   │         │ Redis  │
      │ SQL DB  │         │ Cache  │
      │         │         │        │
      └─────────┘         └────────┘
```

## Prerequisites

1. **Kubernetes Cluster**: Local (Kind/k3s) + GCP GKE cluster
2. **kubectl**: Configured access to both clusters
3. **ArgoCD**: Installed on local cluster
4. **Git Repositories**:
   - `https://github.com/dotnet/eShop` - Application code
   - `https://github.com/cloudopshub/eshop-config` - Kubernetes manifests (GitOps source)
5. **Container Registry**: GitHub Container Registry (ghcr.io)
6. **GitHub**: Personal access token with repo access

## Repository Structure

### Application Repository (dotnet/eShop)

```
eShop/
├── src/
│   ├── Catalog.API/
│   ├── Basket.API/
│   ├── Order.API/
│   ├── Payment.API/
│   ├── Identity.API/
│   └── Web/
├── build/
├── tests/
└── .github/workflows/
    └── eshop-gitops-cd.yml
```

### GitOps Configuration Repository (cloudopshub/eshop-config)

```
eshop-config/
├── base/
│   ├── kustomization.yml
│   ├── namespace.yml
│   ├── configmap.yml
│   ├── secrets.yml
│   ├── catalog-api.yml
│   ├── basket-api.yml
│   ├── order-api.yml
│   ├── web.yml
│   ├── redis.yml
│   ├── cloudsql-proxy.yml
│   └── ingress.yml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yml
│   │   └── values.yml
│   ├── staging/
│   │   ├── kustomization.yml
│   │   └── values.yml
│   └── prod/
│       ├── kustomization.yml
│       ├── values.yml
│       └── network-policy.yml
└── docs/
    └── README.md
```

## Step-by-Step Deployment

### Step 1: Clone and Prepare Application Repository

```bash
# Clone eShop application
git clone https://github.com/dotnet/eShop.git ~/projects/eshop-app
cd ~/projects/eshop-app

# Add upstream remote for updates
git remote add upstream https://github.com/dotnet/eShop.git

# Create integration branch
git checkout -b cloudopshub/k8s-integration
```

### Step 2: Setup GitOps Configuration Repository

Create a new GitHub repository: `cloudopshub/eshop-config`

```bash
# Clone GitOps configuration repository
git clone https://github.com/cloudopshub/eshop-config.git ~/projects/eshop-config
cd ~/projects/eshop-config

# Create directory structure
mkdir -p base overlays/{dev,staging,prod} docs
```

### Step 3: Create Base Kustomization

Create `base/kustomization.yml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: eshop

resources:
  - namespace.yml
  - configmap.yml
  - secrets.yml
  - catalog-api.yml
  - basket-api.yml
  - order-api.yml
  - web.yml
  - redis.yml
  - cloudsql-proxy.yml
  - ingress.yml

commonLabels:
  app.kubernetes.io/part-of: eshop
  managed-by: argocd

commonAnnotations:
  argocd.argoproj.io/compare-result: "true"

images:
  - name: catalog-api
    newName: ghcr.io/dotnet/eshop/catalog-api
    newTag: latest
  - name: basket-api
    newName: ghcr.io/dotnet/eshop/basket-api
    newTag: latest
  - name: order-api
    newName: ghcr.io/dotnet/eshop/order-api
    newTag: latest
  - name: web
    newName: ghcr.io/dotnet/eshop/web
    newTag: latest
```

### Step 4: Create Environment Overlays

#### Dev Environment (overlays/dev/kustomization.yml)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: eshop-dev

bases:
  - ../../base

namePrefix: dev-
commonSuffix: -dev

replicas:
  - name: catalog-api
    count: 1
  - name: basket-api
    count: 1
  - name: order-api
    count: 1
  - name: eshop-web
    count: 1

images:
  - name: catalog-api
    newTag: develop
  - name: basket-api
    newTag: develop
  - name: order-api
    newTag: develop
  - name: web
    newTag: develop
```

#### Staging Environment (overlays/staging/kustomization.yml)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: eshop-staging

bases:
  - ../../base

namePrefix: staging-
commonSuffix: -staging

replicas:
  - name: catalog-api
    count: 2
  - name: basket-api
    count: 2
  - name: order-api
    count: 2
  - name: eshop-web
    count: 2

images:
  - name: catalog-api
    newTag: main
  - name: basket-api
    newTag: main
  - name: order-api
    newTag: main
  - name: web
    newTag: main
```

#### Production Environment (overlays/prod/kustomization.yml)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: eshop

bases:
  - ../../base

replicas:
  - name: catalog-api
    count: 3
  - name: basket-api
    count: 3
  - name: order-api
    count: 2
  - name: eshop-web
    count: 3

images:
  - name: catalog-api
    newTag: v1.0.0
  - name: basket-api
    newTag: v1.0.0
  - name: order-api
    newTag: v1.0.0
  - name: web
    newTag: v1.0.0
```

### Step 5: Copy Kubernetes Manifests to Base

Copy all eShop Kubernetes manifest files to `base/`:

```bash
cp ~/Ai-workstation/multi-cluster-deployment/kubernetes/eshop-*.yml base/
```

### Step 6: Create GitHub Actions Workflow

Add to eShop repository: `.github/workflows/eshop-gitops-cd.yml`

The workflow file already created includes:
- Build & Test stage
- Security scanning
- Container image building
- Pushing to GitHub Container Registry
- Automatic GitOps repository updates

### Step 7: Create ArgoCD Applications

Create `kubernetes/eshop-argocd-applications.yml` with ArgoCD Application definitions:

**Development Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eshop-dev
  namespace: argocd
spec:
  project: eshop
  source:
    repoURL: https://github.com/cloudopshub/eshop-config
    targetRevision: main
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: eshop-dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Staging Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eshop-staging
  namespace: argocd
spec:
  project: eshop
  source:
    repoURL: https://github.com/cloudopshub/eshop-config
    targetRevision: main
    path: overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: eshop-staging
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Production Application:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eshop-prod
  namespace: argocd
spec:
  project: eshop
  source:
    repoURL: https://github.com/cloudopshub/eshop-config
    targetRevision: main
    path: overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: eshop
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    # Manual sync for production
```

### Step 8: Deploy ArgoCD Applications

Deploy the ArgoCD applications to the cluster:

```bash
kubectl apply -f kubernetes/eshop-argocd-applications.yml
```

Verify applications are created:

```bash
kubectl get applications -n argocd
argocd app list | grep eshop
```

### Step 9: Configure GitHub Webhook for ArgoCD

1. Go to GitHub: `https://github.com/cloudopshub/eshop-config/settings/hooks`
2. Add webhook:
   - Payload URL: `https://argocd.your-domain.com/api/webhook`
   - Content type: `application/json`
   - Events: Push events
   - Active: ✓

This allows ArgoCD to sync automatically when changes are pushed to the GitOps repository.

## GitOps Workflow

### Development Workflow

1. **Feature Branch Development**
   ```bash
   cd ~/projects/eshop-app
   git checkout -b feature/new-feature
   # Make code changes
   git commit -am "feat: add new feature"
   git push origin feature/new-feature
   ```

2. **Pull Request & CI**
   - GitHub Actions runs automatically
   - Builds, tests, and scans code
   - Builds Docker images
   - PR must pass all checks

3. **Merge to develop**
   - After approval, merge to develop branch
   - GitHub Actions builds images with `develop` tag
   - Automatically updates `overlays/dev/kustomization.yml` in eshop-config
   - ArgoCD detects change and syncs (auto-sync enabled)
   - Dev environment updates automatically

### Staging Workflow

1. **Create Release Branch**
   ```bash
   cd ~/projects/eshop-app
   git checkout -b release/v1.0.0
   # Update version numbers
   git commit -am "chore: bump version to v1.0.0"
   git push origin release/v1.0.0
   ```

2. **Merge to main**
   - Create PR from release branch to main
   - All CI checks must pass
   - Requires code review approval
   - Merge to main

3. **Automatic Staging Update**
   - GitHub Actions builds images with `main` tag
   - Updates `overlays/staging/kustomization.yml`
   - ArgoCD syncs staging automatically

### Production Workflow

1. **Create Release Tag**
   ```bash
   cd ~/projects/eshop-app
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

2. **Image Building**
   - GitHub Actions detects tag
   - Builds Docker images with semantic version tag (v1.0.0)
   - Updates `overlays/prod/kustomization.yml` in eshop-config

3. **Manual Production Deployment**
   - Production uses manual sync (no auto-sync)
   - Review changes via ArgoCD UI or CLI:
     ```bash
     argocd app diff eshop-prod
     argocd app get eshop-prod
     ```
   - Manually approve and sync:
     ```bash
     argocd app sync eshop-prod
     ```
   - Or via ArgoCD UI: Applications → eshop-prod → Sync button

## Monitoring Deployments

### Check Application Status

```bash
# List all eShop applications
kubectl get applications -n argocd | grep eshop

# Detailed status
argocd app get eshop-dev
argocd app get eshop-staging
argocd app get eshop-prod

# Watch sync status
argocd app wait eshop-prod
```

### View Deployment Pods

```bash
# Dev environment
kubectl get pods -n eshop-dev

# Staging environment
kubectl get pods -n eshop-staging

# Production environment
kubectl get pods -n eshop
```

### Check Application Logs

```bash
# Web service logs
kubectl logs -n eshop-dev -l app=dev-eshop-web -f

# Catalog API logs
kubectl logs -n eshop-dev -l app=dev-catalog-api -f

# View recent events
kubectl get events -n eshop-dev --sort-by='.lastTimestamp'
```

### Monitor via ArgoCD Dashboard

```bash
# Port-forward to ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Access: https://localhost:8080
# Login with admin credentials
argocd admin initial-password -n argocd
```

## Rollback Procedures

### Rollback via ArgoCD

```bash
# View deployment history
argocd app history eshop-prod

# Rollback to previous revision
argocd app rollback eshop-prod 1

# Or to specific revision
argocd app rollback eshop-prod 2
```

### Rollback via Git

```bash
cd ~/projects/eshop-config

# View commit history
git log --oneline overlays/prod/kustomization.yml

# Revert to previous commit
git revert <commit-sha>
git push origin main

# ArgoCD automatically syncs the revert
```

### Rollback Specific Service

```bash
# Edit the overlay to change image tag
# overlays/prod/kustomization.yml
# Change: newTag: v1.0.0 → newTag: v0.9.0

git commit -am "fix: rollback web service to v0.9.0"
git push origin main

# ArgoCD syncs automatically
```

## Troubleshooting

### Application Not Syncing

```bash
# Check application status
argocd app get eshop-prod

# View error details
argocd app logs eshop-prod --follow

# Force sync
argocd app sync eshop-prod --force
```

### Pod Startup Issues

```bash
# Describe pod for events
kubectl describe pod <pod-name> -n eshop

# View pod logs
kubectl logs <pod-name> -n eshop

# Check resource limits
kubectl top pods -n eshop
```

### Database Connection Errors

```bash
# Check Cloud SQL proxy
kubectl get pods -n eshop -l app=cloudsql-proxy
kubectl logs -n eshop -l app=cloudsql-proxy -f

# Verify database credentials
kubectl get secret eshop-db-credentials -n eshop -o yaml
```

### Redis Connection Issues

```bash
# Check Redis statefulset
kubectl get statefulsets -n eshop
kubectl logs -n eshop -l app=redis -f

# Test Redis connection
kubectl exec -it redis-0 -n eshop -- redis-cli ping
```

## Advanced Topics

### Custom Image Tags per Environment

Edit the respective overlay's `kustomization.yml`:

```yaml
images:
  - name: web
    newTag: custom-tag-v2.0.0
```

Then push to Git and ArgoCD syncs.

### Environment Variables by Environment

Create `overlays/ENV/configmap.yml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eshop-env-overrides
data:
  ASPNETCORE_ENVIRONMENT: "Staging"
  LOG_LEVEL: "Information"
```

Add to overlay's `kustomization.yml`:

```yaml
resources:
  - ../../base
  - configmap.yml
```

### Network Policies per Environment

Create `overlays/prod/network-policy.yml` with strict policies, then reference in kustomization.yml.

## Best Practices

1. **Single Source of Truth**: All configuration in Git
2. **Automated Deployments**: Dev/Staging use auto-sync
3. **Manual Approval**: Production requires manual sync
4. **Version Everything**: Use semantic versioning for releases
5. **Test First**: All PRs must pass CI before merge
6. **Audit Trail**: Every change tracked in Git history
7. **Quick Rollback**: Revert Git commit to rollback
8. **Environment Parity**: Overlays ensure consistent configuration

## Security Considerations

1. **Secrets Management**:
   - Use Kubernetes Secrets for credentials
   - Consider external secret managers (Google Secret Manager)
   - Never commit secrets to Git

2. **RBAC**:
   - Service accounts per deployment
   - Limit permissions to needed resources
   - Use network policies for traffic control

3. **Image Security**:
   - Scan images in CI/CD
   - Use specific image tags (not `latest`)
   - Sign images for production

4. **Deployment Safety**:
   - Manual approval for production
   - Gradual rollout with canary deployments
   - Health checks on all pods
   - Pod disruption budgets for high availability

This GitOps workflow ensures reliable, auditable, and repeatable deployments of the eShop application across multiple environments.
