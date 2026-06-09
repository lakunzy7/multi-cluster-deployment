# Manifest Organization Guide

## Directory Structure

```
multi-cluster-deployment/
├── helm/                                    # Helm chart values (for cluster setup)
│   ├── argocd/
│   │   └── values.yaml                     # ArgoCD Helm installation
│   ├── kargo/
│   │   └── values.yaml                     # Kargo Helm installation
│   ├── prometheus/
│   │   └── values.yaml                     # Prometheus/Grafana stack
│   └── velero/
│       └── values.yaml                     # Velero backup & recovery
│
├── kubernetes/                              # All Kubernetes manifests
│   ├── infrastructure/                     # System components (cluster-wide)
│   │   └── kargo/                         # Kargo GitOps workflow (GitOps config only)
│   │       ├── project.yaml               # Kargo Project (defines authenticwrite)
│   │       ├── warehouse-demo.yaml        # Image registry watcher
│   │       ├── dev-stage.yaml             # Dev environment (auto-promote)
│   │       ├── staging-stage.yaml         # Staging (manual approval required)
│   │       └── prod-stage.yaml            # Production (manual approval required)
│   ├── base/                               # App base configuration
│   │   ├── kustomization.yaml             # Kustomize build config
│   │   ├── namespace.yaml                 # authenticwrite namespace
│   │   ├── backend.yaml                   # Backend deployment
│   │   ├── frontend.yaml                  # Frontend deployment
│   │   ├── ingress.yaml                   # Ingress routes
│   │   ├── configmap.yaml                 # App configuration
│   │   └── ghcr-secret-template.yaml      # Docker registry credentials
│   └── overlays/                           # Environment-specific configs
│       ├── dev/
│       │   └── kustomization.yaml         # dev: 1 replica
│       ├── staging/
│       │   └── kustomization.yaml         # staging: 2 replicas
│       └── prod/
│           └── kustomization.yaml         # prod: 3 replicas
│
├── argocd-apps/                            # ArgoCD application definitions
│   └── applicationset-authenticwrite.yaml # ApplicationSet for multi-env deploy
│
├── terraform/                              # Infrastructure as Code
│   ├── main.tf
│   ├── local-cluster.tf
│   ├── providers.tf
│   ├── backend.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── .github/workflows/                      # CI/CD pipelines
│   ├── build-push-images.yml              # Build + push to GHCR
│   ├── update-kargo-images.yml            # Webhook: trigger Kargo
│   ├── validate.yml                       # Manifest validation
│   └── check-kargo-secrets.yml
│
├── docs/                                   # Documentation
│   └── GITHUB-WEBHOOKS-SETUP.md
│
├── scripts/                                # Helper scripts
│   ├── deploy-argocd-kargo.sh
│   └── test-pipeline.sh
│
└── DEPLOYMENT_STATUS.md                    # Deployment state reference
```

---

## File Purposes

### Helm Values (`helm/`)
Install cluster infrastructure using Helm charts. These are values files for each component.

- **`helm/argocd/values.yaml`** — ArgoCD Helm chart configuration
  - `helm install argocd argo/argo-cd -f helm/argocd/values.yaml -n argocd --create-namespace`

- **`helm/kargo/values.yaml`** — Kargo Helm chart configuration
  - `helm install kargo kargo/kargo -f helm/kargo/values.yaml -n kargo --create-namespace`

- **`helm/prometheus/values.yaml`** — Prometheus/Grafana/AlertManager stack
  - `helm install prometheus prometheus-community/kube-prometheus-stack -f helm/prometheus/values.yaml -n monitoring --create-namespace`

- **`helm/velero/values.yaml`** — Velero backup & disaster recovery
  - `helm install velero vmware-tanzu/velero -f helm/velero/values.yaml -n velero --create-namespace`

### Infrastructure (`kubernetes/infrastructure/`)
GitOps configuration files. Applied AFTER Helm installations.

#### Kargo (`kubernetes/infrastructure/kargo/`)
These define the **GitOps promotion workflow** for your app.

- **`project.yaml`**
  - Creates a Kargo Project named `authenticwrite`
  - Defines auto-promotion policy for `dev` stage only
  - Staging & prod require manual approval

- **`warehouse-demo.yaml`**
  - Watches `ghcr.io/lakunzy7/authenticwrite` for new images
  - Creates "Freight" objects when images detected
  - Filters by semantic version tags (v*.*.*)

- **`dev-stage.yaml`**
  - First promotion stage (dev environment)
  - **Auto-promotes**: Automatically deploys new images from warehouse
  - Updates Git repo with new image tags (Kustomize)

- **`staging-stage.yaml`**
  - Second promotion stage (staging environment)
  - **Manual approval required**: `kargo promote authenticwrite staging --from dev`
  - Gets images from `dev` stage (upstream dependency)

- **`prod-stage.yaml`**
  - Production environment
  - **Manual approval required**: `kargo promote authenticwrite prod --from staging`
  - Gets images from `staging` stage (upstream dependency)


### Application Deployment (`kubernetes/base/` & `kubernetes/overlays/`)
These define your actual application.

- **`kubernetes/base/`** — Shared app configuration
  - Deployments, services, config, secrets for backend & frontend
  - Used by all environments

- **`kubernetes/overlays/{dev,staging,prod}/`** — Environment-specific overrides
  - Replica counts (dev=1, staging=2, prod=3)
  - Resource limits per environment
  - Environment variables per stage

### ArgoCD Applications (`argocd-apps/`)
- **`applicationset-authenticwrite.yaml`** — ApplicationSet that creates ArgoCD Applications
  - Watches repo for changes
  - Automatically syncs to clusters when Kargo updates images in Git
  - Creates 1 app per environment × cluster combination

---

## How It All Works Together

### 1. **You push code** → GitHub
   ```
   git push origin main
   ```

### 2. **CI pipeline builds images** → `.github/workflows/build-push-images.yml`
   ```
   Backend:  ghcr.io/lakunzy7/authenticwrite/backend:v1.2.3
   Frontend: ghcr.io/lakunzy7/authenticwrite/frontend:v1.2.3
   ```

### 3. **Kargo Warehouse detects images** ← `kubernetes/infrastructure/kargo/warehouse-demo.yaml`
   ```
   Creates Freight object with new images
   ```

### 4. **Kargo auto-promotes to dev** ← `kubernetes/infrastructure/kargo/dev-stage.yaml`
   ```
   Updates kubernetes/overlays/dev/kustomization.yaml in Git (main branch)
   Sets image tags to v1.2.3
   ```

### 5. **ArgoCD detects Git change** ← `argocd-apps/applicationset-authenticwrite.yaml`
   ```
   Watches GitHub repo
   Detects changed kustomization.yaml
   ```

### 6. **ArgoCD syncs to cluster** ← `kubernetes/overlays/dev/kustomization.yaml`
   ```
   Applies new pods with updated images
   Dev environment now running v1.2.3
   ```

### 7. **Manual promotion to staging**
   ```bash
   kargo promote authenticwrite staging --from dev
   ```
   Updates `kubernetes/overlays/staging/kustomization.yaml` in Git

### 8. **ArgoCD syncs staging** 
   Applies changes to staging environment

### 9. **Manual promotion to prod**
   ```bash
   kargo promote authenticwrite prod --from staging
   ```

---

## Installation & Deployment Order

When setting up a new cluster:

```bash
# 1. Add Helm repositories
helm repo add argo https://argoproj.github.io/argo-helm
helm repo add kargo https://charts.kargo.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# 2. Install Prometheus (monitoring)
helm install prometheus prometheus-community/kube-prometheus-stack \
  -f helm/prometheus/values.yaml \
  -n monitoring --create-namespace

# 3. Install ArgoCD
helm install argocd argo/argo-cd \
  -f helm/argocd/values.yaml \
  -n argocd --create-namespace

# 4. Install Kargo
helm install kargo kargo/kargo \
  -f helm/kargo/values.yaml \
  -n kargo --create-namespace

# 5. Install Velero (backup)
helm install velero vmware-tanzu/velero \
  -f helm/velero/values.yaml \
  -n velero --create-namespace

# 6. Create app namespace and secrets
kubectl create namespace authenticwrite
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_TOKEN \
  -n authenticwrite

# 7. Apply Kargo workflow config (GitOps)
kubectl apply -f kubernetes/infrastructure/kargo/

# 8. Apply ArgoCD applications
kubectl apply -f argocd-apps/

# 9. Apply app deployment manifests
kubectl apply -k kubernetes/overlays/dev
```

---

## Files Removed (Not Needed)

- ❌ `kargo/kustomization.yaml` — Container file only, manifests applied directly
- ❌ `kargo/kargo-ing.yaml` — Requires NGINX controller; use `kubectl port-forward` instead
- ❌ `kargo/promotiontask.yaml` — Legacy/redundant; Stage resources handle everything

---

## Quick Reference: Which File Does What?

| Task | File |
|------|------|
| Add a new image registry to watch | `kubernetes/infrastructure/kargo/warehouse-demo.yaml` |
| Change dev→staging approval policy | `kubernetes/infrastructure/kargo/staging-stage.yaml` |
| Adjust replica counts per env | `kubernetes/overlays/{dev,staging,prod}/kustomization.yaml` |
| Configure ArgoCD via Helm | `helm/argocd/values.yaml` |
| Configure Kargo via Helm | `helm/kargo/values.yaml` |
| Configure Prometheus/Grafana | `helm/prometheus/values.yaml` |
| Configure Velero backups | `helm/velero/values.yaml` |
| Build images in CI | `.github/workflows/build-push-images.yml` |

---

## Installation Steps

1. **Add Helm repositories** (see Installation & Deployment Order section above)
2. **Install each component via Helm** in order: Prometheus → ArgoCD → Kargo → Velero
3. **Create app namespace and GHCR credentials**
4. **Apply Kargo workflow config**: `kubectl apply -f kubernetes/infrastructure/kargo/`
5. **Apply ArgoCD applications**: `kubectl apply -f argocd-apps/`
6. **Test the promotion flow**: Push code → Check Kargo → Promote to staging/prod
