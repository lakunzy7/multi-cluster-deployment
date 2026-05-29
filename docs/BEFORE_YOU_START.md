# Before You Start Deployment

## ⚠️ IMPORTANT: Missing Action Items

The CloudOpsHub + eShop platform is **95% configured** but requires the following **manual action items** before deployment can begin.

---

## Action Item 1: Clone eShop Application Code

**Status**: ❌ NOT YET DONE
**Reason**: Application source code repository needs to be available locally

### Steps:

```bash
# 1. Clone eShop repository
git clone https://github.com/dotnet/eShop.git ~/projects/eshop-app
cd ~/projects/eshop-app

# 2. Create integration branch
git checkout -b cloudopshub/k8s-integration
git push -u origin cloudopshub/k8s-integration

# 3. Create .github directory (if not exists)
mkdir -p .github/workflows

# 4. Copy GitHub Actions workflow
cp ~/Ai-workstation/multi-cluster-deployment/ci-cd/.github/workflows/eshop-gitops-cd.yml \
   .github/workflows/eshop-gitops-cd.yml

# 5. Commit and push
git add .github/workflows/eshop-gitops-cd.yml
git commit -m "chore: add CloudOpsHub GitHub Actions workflow"
git push origin cloudopshub/k8s-integration

# 6. Create pull request to develop branch
# (Instructions for your Git hosting platform)
```

### Verification:
```bash
# Verify structure
ls -la ~/projects/eshop-app/.github/workflows/
# Should show: eshop-gitops-cd.yml
```

---

## Action Item 2: Create GitOps Configuration Repository

**Status**: ❌ NOT YET DONE
**Reason**: Kubernetes manifests must be in separate GitOps repository

### Steps:

```bash
# 1. Create repository on GitHub/GitLab
# Go to: https://github.com/new
# Repository name: eshop-config
# Description: GitOps configuration for eShop
# Make it PUBLIC or PRIVATE (as needed)
# Do NOT initialize with README (we'll push our own)

# 2. Clone the empty repository
git clone https://github.com/YOUR_ORG/eshop-config.git ~/projects/eshop-config
cd ~/projects/eshop-config

# 3. Create directory structure
mkdir -p base overlays/{dev,staging,prod} docs

# 4. Copy eShop Kubernetes manifests to base/
cp ~/Ai-workstation/multi-cluster-deployment/kubernetes/eshop-*.yml base/

# 5. Create base/kustomization.yml
cat > base/kustomization.yml << 'EOF'
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
EOF

# 6. Create overlays/dev/kustomization.yml
cat > overlays/dev/kustomization.yml << 'EOF'
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
EOF

# 7. Create overlays/staging/kustomization.yml
cat > overlays/staging/kustomization.yml << 'EOF'
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
EOF

# 8. Create overlays/prod/kustomization.yml
cat > overlays/prod/kustomization.yml << 'EOF'
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
EOF

# 9. Create README
cat > docs/README.md << 'EOF'
# eShop GitOps Configuration

This repository contains Kubernetes manifests and Kustomize configurations
for deploying eShop application to CloudOpsHub multi-cluster platform.

## Environments

- **base/**: Common Kubernetes manifests
- **overlays/dev/**: Development environment (1 replica)
- **overlays/staging/**: Staging environment (2 replicas)
- **overlays/prod/**: Production environment (3 replicas)

## Deployment

Manifests are deployed via ArgoCD from eShop CI/CD pipeline.
See docs in main eShop repository for deployment procedures.
EOF

# 10. Initial commit and push
git config user.email "you@example.com"
git config user.name "Your Name"
git add .
git commit -m "chore: initialize GitOps configuration for eShop"
git push -u origin main
```

### Verification:
```bash
# Verify structure
tree ~/projects/eshop-config/
# Should show base/ and overlays/{dev,staging,prod}/

# Verify Kustomize files
kustomize build ~/projects/eshop-config/overlays/dev | head -20
# Should show Kubernetes YAML output
```

---

## Action Item 3: Prepare GCP Infrastructure

**Status**: ❌ NOT YET DONE
**Reason**: Google Cloud Platform needs configuration before Terraform can deploy

### Steps:

```bash
# 1. Set project ID
export GCP_PROJECT="your-project-id"
gcloud config set project $GCP_PROJECT

# 2. Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable secretmanager.googleapis.com

# 3. Verify APIs are enabled
gcloud services list --enabled | grep -E "compute|container|sql|storage|servicenetworking"

# 4. Create terraform.tfvars
cd ~/Ai-workstation/multi-cluster-deployment/terraform
cat > terraform.tfvars << EOF
gcp_project = "$GCP_PROJECT"
gcp_region  = "europe-west1"
project_name = "cloudopshub"
environment = "dev"
node_count = 3
instance_type = "e2-medium"
EOF

# 5. Verify GCP authentication
gcloud auth list
gcloud account list
```

### Verification:
```bash
gcloud projects describe $GCP_PROJECT
# Should show project details
```

---

## Action Item 4: Deploy Infrastructure with Terraform

**Status**: ❌ NOT YET DONE
**Reason**: Cloud infrastructure must be provisioned

### Steps:

```bash
cd ~/Ai-workstation/multi-cluster-deployment/terraform

# 1. Initialize Terraform
terraform init

# 2. Review planned changes
terraform plan -out=tfplan

# 3. Deploy infrastructure
terraform apply tfplan

# 4. Save outputs
terraform output -json > outputs.json

# 5. Verify deployment
gcloud container clusters list
gcloud sql instances list
gcloud storage buckets list
```

### Verification:
```bash
# Get GKE cluster credentials
gcloud container clusters get-credentials cloud-cluster --region europe-west1

# Verify cluster access
kubectl get nodes
# Should show 3 GKE nodes
```

**Time required**: 15-20 minutes

---

## Action Item 5: Setup Local Kubernetes Cluster

**Status**: ❌ NOT YET DONE
**Reason**: Local cluster needed for ArgoCD and dev environment

### Option A: Using Kind (Recommended)

```bash
# 1. Create local cluster
kind create cluster --name local-cluster --image kindest/node:v1.28.0

# 2. Verify cluster
kubectl cluster-info --context kind-local-cluster
kubectl get nodes --context kind-local-cluster
```

### Option B: Using k3s

```bash
# 1. Install k3s
curl -sfL https://get.k3s.io | sh -

# 2. Get kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/local-config
sudo chown $USER:$USER ~/.kube/local-config

# 3. Verify cluster
export KUBECONFIG=~/.kube/local-config
kubectl get nodes
```

**Time required**: 5-10 minutes

---

## Action Item 6: Setup Kubernetes Namespaces and Storage

**Status**: ❌ NOT YET DONE
**Reason**: Cluster must be configured with required namespaces

### Steps:

```bash
# 1. Deploy CloudOpsHub platform components
kubectl apply -f ~/Ai-workstation/multi-cluster-deployment/kubernetes/namespaces.yml
kubectl apply -f ~/Ai-workstation/multi-cluster-deployment/kubernetes/storage-class.yml
kubectl apply -f ~/Ai-workstation/multi-cluster-deployment/kubernetes/network-policies.yml

# 2. Verify namespaces
kubectl get namespaces
# Should show: default, kube-system, dev, staging, production, monitoring, logging, ci-cd, security

# 3. Verify storage classes
kubectl get storageclasses
# Should show: fast-ssd, standard, backup-storage

# 4. Setup kubeconfig for both clusters
export KUBECONFIG=~/.kube/kind-local-cluster:~/.kube/gke-config

# 5. Verify both clusters accessible
kubectl get nodes --context kind-local-cluster
kubectl get nodes --context gke_${GCP_PROJECT}_europe-west1_cloud-cluster
```

**Time required**: 5 minutes

---

## Action Item 7: Install and Configure ArgoCD

**Status**: ❌ NOT YET DONE
**Reason**: GitOps controller must be installed

### Steps:

```bash
# 1. Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Install ArgoCD on local cluster
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 5.46.7

# 3. Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# 4. Get admin password
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n argocd -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD Admin Password: $ARGOCD_PASSWORD"

# 5. Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# 6. Login via CLI
argocd login localhost:8080 --username admin --password $ARGOCD_PASSWORD

# 7. Deploy eShop ArgoCD applications
kubectl apply -f ~/Ai-workstation/multi-cluster-deployment/kubernetes/eshop-argocd-app.yml

# 8. Verify applications
argocd app list | grep eshop
```

**Time required**: 10 minutes

---

## Action Item 8: Configure GitHub Webhook for ArgoCD

**Status**: ❌ NOT YET DONE
**Reason**: Automatic sync requires webhook from Git to ArgoCD

### Steps:

```bash
# 1. Get ArgoCD webhook URL
ARGOCD_URL="https://argocd.your-domain.com"  # Replace with your domain
WEBHOOK_URL="$ARGOCD_URL/api/webhook"

# 2. Go to eshop-config repository on GitHub
# https://github.com/YOUR_ORG/eshop-config/settings/hooks

# 3. Add new webhook:
#    - Payload URL: $WEBHOOK_URL
#    - Content type: application/json
#    - Events: Push events
#    - Active: ✓

# 4. Test delivery
# GitHub will show successful delivery in webhook history
```

---

## Complete Deployment Checklist

Before starting deployment, complete these items in order:

```
PREREQUISITES:
  [ ] GCP account with billing enabled
  [ ] GitHub account (personal or organization)
  [ ] Local machine with tools: git, kubectl, gcloud, terraform, helm, docker
  [ ] Domain name for ArgoCD (optional but recommended)

ACTION ITEMS:
  [ ] 1. Clone eShop application code
  [ ] 2. Create eshop-config GitOps repository
  [ ] 3. Prepare GCP project and enable APIs
  [ ] 4. Deploy infrastructure with Terraform
  [ ] 5. Setup local Kubernetes cluster (Kind/k3s)
  [ ] 6. Setup Kubernetes namespaces and storage
  [ ] 7. Install and configure ArgoCD
  [ ] 8. Configure GitHub webhook

TESTING:
  [ ] Verify GKE cluster access
  [ ] Verify local cluster access
  [ ] Verify ArgoCD is running
  [ ] Push test commit to develop branch
  [ ] Verify GitHub Actions workflow runs
  [ ] Verify GitOps repo is updated
  [ ] Verify ArgoCD syncs changes
  [ ] Verify pods deployed in eshop-dev

DOCUMENTATION:
  [ ] Read: docs/QUICK_START.md
  [ ] Read: docs/SETUP.md (full guide)
  [ ] Read: docs/ESHOP_DEPLOYMENT_GUIDE.md
  [ ] Keep: DEPLOYMENT_RUNBOOK.md open for reference
```

---

## Time Estimate

| Item | Time |
|------|------|
| Clone eShop | 2 min |
| Create GitOps repo | 5 min |
| Prepare GCP | 5 min |
| Terraform deployment | 20 min |
| Local cluster setup | 10 min |
| K8s namespaces | 5 min |
| ArgoCD installation | 10 min |
| GitHub webhook | 5 min |
| **TOTAL** | **62 minutes** |

---

## After Completing These Items

Once all action items are complete:

1. **Read**: docs/ESHOP_DEPLOYMENT_GUIDE.md for detailed eShop setup
2. **Test**: Push code to develop branch and watch CI/CD pipeline
3. **Monitor**: Use ArgoCD dashboard to track deployments
4. **Verify**: Check pods running in eshop-dev namespace

---

## Support & Troubleshooting

Refer to:
- **Setup Issues**: docs/SETUP.md
- **Deployment Issues**: docs/DEPLOYMENT_RUNBOOK.md
- **Monitoring Issues**: docs/MONITORING_RUNBOOK.md
- **Project Requirements**: PROJECT_REQUIREMENTS_VERIFICATION.md

---

## CRITICAL NOTE

**The infrastructure configuration is 95% complete and production-ready.**

However, **deployment cannot proceed without completing these action items.**

These items require:
1. Manual repository setup on GitHub
2. Manual GCP project configuration
3. Manual execution of Terraform
4. Manual Kubernetes cluster setup

All steps are documented and straightforward. Expected total time: **1 hour**

Good luck with your deployment! 🚀
