# eShop GitOps Integration Guide

## Overview

This guide sets up a complete GitOps workflow for the eShop application using Git as the single source of truth. ArgoCD syncs application state from Git repositories, ensuring declarative, auditable deployments.

## Repository Structure

```
GitHub Organization:
├── dotnet/eShop (Application Code)
│   ├── src/
│   ├── build/
│   ├── tests/
│   └── .github/workflows/
│
└── cloudopshub/eshop-config (Kubernetes Manifests - GitOps Source)
    ├── base/
    │   ├── namespace.yml
    │   ├── configmap.yml
    │   ├── secrets.yml
    │   ├── catalog-api.yml
    │   ├── basket-api.yml
    │   ├── order-api.yml
    │   ├── web.yml
    │   ├── redis.yml
    │   └── kustomization.yml
    ├── overlays/
    │   ├── dev/
    │   │   ├── kustomization.yml
    │   │   ├── configmap.yml
    │   │   └── values.yml
    │   ├── staging/
    │   │   ├── kustomization.yml
    │   │   ├── configmap.yml
    │   │   └── values.yml
    │   └── prod/
    │       ├── kustomization.yml
    │       ├── configmap.yml
    │       ├── values.yml
    │       └── network-policy.yml
    └── docs/
        └── README.md
```

## Step 1: Clone eShop Application Repository

```bash
# Clone the official eShop repository
git clone https://github.com/dotnet/eShop.git ~/projects/eshop-app
cd ~/projects/eshop-app

# Create feature branch for CloudOpsHub integration
git checkout -b cloudopshub/k8s-integration
git remote add upstream https://github.com/dotnet/eShop.git

# List existing branches
git branch -a
```

## Step 2: Create eShop Configuration Repository (GitOps Source)

This repository holds all Kubernetes manifests and is the single source of truth for ArgoCD.

```bash
# Create new GitHub repository: cloudopshub/eshop-config
git clone https://github.com/cloudopshub/eshop-config.git ~/projects/eshop-config
cd ~/projects/eshop-config

# Initialize directory structure
mkdir -p base overlays/{dev,staging,prod} docs

# Copy Kubernetes manifests we created
cp ~/Ai-workstation/multi-cluster-deployment/kubernetes/eshop-*.yml base/
```

## Step 3: Set Up Kustomize for Environment Overlays

### Base Kustomization (base/kustomization.yml)

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

vars:
  - name: CATALOG_REPLICAS
    objref:
      kind: Deployment
      name: catalog-api
      apiVersion: apps/v1
    fieldref:
      fieldpath: spec.replicas
```

### Dev Overlay (overlays/dev/kustomization.yml)

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

configMapGenerator:
  - name: eshop-env
    files:
      - values.yml
    behavior: merge

images:
  - name: catalog-api
    newTag: develop
  - name: basket-api
    newTag: develop
  - name: order-api
    newTag: develop
  - name: web
    newTag: develop

patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 256Mi
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: 200m
```

### Staging Overlay (overlays/staging/kustomization.yml)

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

configMapGenerator:
  - name: eshop-env
    files:
      - values.yml
    behavior: merge

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

### Production Overlay (overlays/prod/kustomization.yml)

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

configMapGenerator:
  - name: eshop-env
    files:
      - values.yml
    behavior: merge

images:
  - name: catalog-api
    newTag: v1.0.0  # Use semantic versioning
  - name: basket-api
    newTag: v1.0.0
  - name: order-api
    newTag: v1.0.0
  - name: web
    newTag: v1.0.0

patchesStrategicMerge:
  - network-policy.yml

resources:
  - ../../base
```

## Step 4: Update eShop Application Repository for CI/CD

### Add Dockerfile for Each Service

In `src/eShop.AppHost/Dockerfile`:

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ["eShop.AppHost/eShop.AppHost.csproj", "eShop.AppHost/"]
RUN dotnet restore "eShop.AppHost/eShop.AppHost.csproj"
COPY . .
WORKDIR "/src/eShop.AppHost"
RUN dotnet build "eShop.AppHost.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "eShop.AppHost.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "eShop.AppHost.dll"]
```

### GitHub Actions Workflow (.github/workflows/eshop-gitops-cd.yml)

```yaml
name: eShop GitOps CD Pipeline

on:
  push:
    branches:
      - main
      - develop
    paths:
      - 'src/**'
      - 'tests/**'
      - '.github/workflows/eshop-gitops-cd.yml'
  pull_request:
    branches:
      - main
      - develop

env:
  REGISTRY: ghcr.io
  IMAGE_REGISTRY_OWNER: dotnet

jobs:
  build-test:
    name: Build & Test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Setup .NET 9
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '9.0'

    - name: Restore dependencies
      run: dotnet restore

    - name: Build solution
      run: dotnet build --configuration Release --no-restore

    - name: Run unit tests
      run: dotnet test --configuration Release --no-build --verbosity normal

    - name: Run integration tests
      run: dotnet test --configuration Release --filter "Category=Integration" --no-build

  security-scan:
    name: Security Scanning
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Run Trivy vulnerability scan
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: 'fs'
        scan-ref: 'src'
        format: 'sarif'
        output: 'trivy-results.sarif'

    - name: Upload Trivy results
      uses: github/codeql-action/upload-sarif@v2
      with:
        sarif_file: 'trivy-results.sarif'

    - name: Run Gitleaks
      uses: gitleaks/gitleaks-action@v2

  build-push-images:
    name: Build & Push Container Images
    runs-on: ubuntu-latest
    needs: [build-test, security-scan]
    if: github.event_name == 'push'
    permissions:
      contents: read
      packages: write

    strategy:
      matrix:
        service:
          - catalog-api
          - basket-api
          - order-api
          - web
          - payment-api
          - identity-api

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_REGISTRY_OWNER }}/eshop/${{ matrix.service }}
        tags: |
          type=ref,event=branch
          type=semver,pattern={{version}}
          type=semver,pattern={{major}}.{{minor}}
          type=sha,prefix={{branch}}-
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Build and push image
      uses: docker/build-push-action@v5
      with:
        context: ./src
        file: ./src/${{ matrix.service }}/Dockerfile
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_REGISTRY_OWNER }}/eshop/${{ matrix.service }}:buildcache
        cache-to: type=registry,ref=${{ env.REGISTRY }}/${{ env.IMAGE_REGISTRY_OWNER }}/eshop/${{ matrix.service }}:buildcache,mode=max

  update-gitops-repo:
    name: Update GitOps Repository
    runs-on: ubuntu-latest
    needs: build-push-images
    if: github.event_name == 'push'

    steps:
    - name: Checkout GitOps repo
      uses: actions/checkout@v4
      with:
        repository: cloudopshub/eshop-config
        token: ${{ secrets.GITOPS_REPO_TOKEN }}
        path: eshop-config

    - name: Update image tags in overlays
      run: |
        # Determine branch and environment
        BRANCH=${{ github.ref_name }}
        if [ "$BRANCH" == "main" ]; then
          ENV="prod"
          TAG="v${{ github.run_number }}"
        else
          ENV="dev"
          TAG="$BRANCH-${{ github.sha }}"
        fi

        # Update Kustomize image tags
        cd eshop-config/overlays/$ENV
        
        # Update all services
        sed -i "s|newTag: .*|newTag: $TAG|g" kustomization.yml

    - name: Commit and push changes
      run: |
        cd eshop-config
        git config user.name "GitHub Actions"
        git config user.email "github-actions@cloudopshub.com"
        git add overlays/
        git commit -m "chore: update image tags for build ${{ github.run_number }} from ${{ github.ref_name }}"
        git push origin main

    - name: Create deployment notification
      run: |
        echo "## Deployment Update" >> $GITHUB_STEP_SUMMARY
        echo "GitOps repository updated with new image tags" >> $GITHUB_STEP_SUMMARY
        echo "- Environment: $ENV" >> $GITHUB_STEP_SUMMARY
        echo "- Image Tag: $TAG" >> $GITHUB_STEP_SUMMARY
        echo "- Commit: ${{ github.sha }}" >> $GITHUB_STEP_SUMMARY
```

## Step 5: Configure ArgoCD Applications

### Create GitOps Sync Definition (kubernetes/eshop-argocd-applications.yml)

```yaml
---
# Development Environment
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
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas

---
# Staging Environment
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
    syncOptions:
    - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

---
# Production Environment
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
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
  # Manual sync for production
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
```

## Step 6: GitOps Workflow

### Development Workflow

1. **Feature Development**
   ```bash
   cd ~/projects/eshop-app
   git checkout -b feature/new-feature
   # Make code changes
   git commit -am "feat: add new feature"
   git push origin feature/new-feature
   ```

2. **Pull Request & CI**
   - GitHub Actions runs build, test, and security scans
   - PR must pass all checks before merge

3. **Merge to develop**
   ```bash
   # After PR approval and merge
   # ArgoCD watches eshop-app repo for changes
   # New images built and pushed to registry
   # GitOps repo (eshop-config) automatically updated
   # Dev environment automatically syncs (Auto-sync enabled)
   ```

4. **Automatic Deployment to Dev**
   - ArgoCD detects eshop-config changes
   - Applies overlays/dev manifests to eshop-dev namespace
   - Deploys with develop branch image tags

### Staging Workflow

1. **Create Release Branch**
   ```bash
   cd ~/projects/eshop-app
   git checkout -b release/v1.0.0
   # Version bumps in release branch
   git push origin release/v1.0.0
   ```

2. **Merge to main**
   - PR from release branch to main
   - All CI checks pass
   - Manual approval required

3. **Automatic Staging Deployment**
   - GitHub Actions builds images with main branch tag
   - Updates overlays/staging in eshop-config
   - ArgoCD syncs staging environment automatically

### Production Workflow

1. **Create Release Tag**
   ```bash
   cd ~/projects/eshop-app
   git tag -a v1.0.0 -m "Release v1.0.0"
   git push origin v1.0.0
   ```

2. **Images Built with Version Tag**
   - Images tagged as v1.0.0
   - Pushed to container registry

3. **Manual Production Sync**
   ```bash
   # GitOps repo updated with v1.0.0 tags
   # Production uses manual sync (requires approval in ArgoCD)
   argocd app sync eshop-prod
   
   # Or via UI: ArgoCD Dashboard → eshop-prod → Sync
   ```

## Step 7: Monitoring GitOps Sync

```bash
# Watch ArgoCD application status
kubectl get applications -n argocd

# Detailed sync status
argocd app get eshop-dev
argocd app get eshop-staging
argocd app get eshop-prod

# View sync history
argocd app history eshop-prod

# Manual sync with dry-run
argocd app sync eshop-prod --dry-run

# Get application resources
argocd app resources eshop-prod
```

## Step 8: Rollback Procedure

### Using ArgoCD

```bash
# View revision history
argocd app history eshop-prod

# Rollback to previous revision
argocd app rollback eshop-prod 1

# Or using Git commit
argocd app sync eshop-prod --revision=<commit-sha>
```

### Using Git

```bash
cd ~/projects/eshop-config
git log --oneline overlays/prod/

# Revert to previous commit
git revert <commit-sha>
git push origin main

# ArgoCD automatically syncs to new state
```

## Key GitOps Principles

✅ **Single Source of Truth**: Git (eshop-config repo)
✅ **Declarative**: All infrastructure defined in YAML
✅ **Automated**: GitHub Actions → Container Registry → ArgoCD
✅ **Auditable**: All changes tracked in Git history
✅ **Safe**: Automated rollback via Git revert
✅ **Reliable**: Version-controlled deployments
✅ **Repeatable**: Exact same state every time

## Webhook Configuration

### Configure GitHub Webhook for ArgoCD

1. Go to: https://github.com/cloudopshub/eshop-config/settings/hooks
2. Add webhook:
   - Payload URL: `https://argocd.example.com/api/webhook`
   - Content type: `application/json`
   - Events: Push events
   - Active: ✓

3. ArgoCD automatically syncs on Git push

## Continuous Delivery Pipeline

```
Code Push
    ↓
GitHub Actions (CI)
    ├─ Build & Test
    ├─ Security Scan
    └─ Build Images
    ↓
Push to Registry
    ↓
Update GitOps Repo (eshop-config)
    ↓
Webhook Trigger ArgoCD
    ↓
ArgoCD Sync (Auto for dev/staging, Manual for prod)
    ↓
Deployment to Kubernetes
    ↓
Health Checks & Monitoring
```

This approach ensures complete traceability, easy rollback, and true infrastructure-as-code practices.
