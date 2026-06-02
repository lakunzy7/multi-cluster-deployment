# Helm Chart Deployment Guide

Deploy ArgoCD, Kargo, and Monitoring stack using Helm charts instead of raw YAML.

## Prerequisites

```bash
# Install Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify Helm
helm version

# Add Helm repositories
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo add kargo https://charts.akuity.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

---

## 1. Deploy ArgoCD with Helm

### 1.1 Create Values File

Create `helm/argocd-values.yaml`:

```yaml
global:
  domain: argocd.local

server:
  service:
    type: LoadBalancer
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - argocd.local

configs:
  params:
    "application.instanceLabelKey": "argocd.argoproj.io/instance"
    "server.insecure": false
    
  secret:
    argocdServerAdminPassword: "$2a$10$rRyq8Q8n8F8q8F8q8F8q8F8q8F8q8F8q8F8q8F8q8" # Replace with bcrypt hash

repoServer:
  replicas: 1

controller:
  replicas: 1

redis:
  enabled: true
```

### 1.2 Deploy to Kind Cluster

```bash
# Set context to Kind
kubectl config use-context kind-cloudopshub-local

# Create namespace
kubectl create namespace argocd

# Install ArgoCD
helm install argocd argocd/argo-cd \
  --namespace argocd \
  --values helm/argocd-values.yaml \
  --wait

# Verify deployment
kubectl get pods -n argocd
kubectl get svc -n argocd
```

### 1.3 Get ArgoCD Initial Password

```bash
# Get auto-generated password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to access UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Visit: https://localhost:8080 (user: admin)
```

### 1.4 Deploy to GKE Cluster

```bash
# Set context to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

# Create namespace
kubectl create namespace argocd

# Install ArgoCD (same chart)
helm install argocd argocd/argo-cd \
  --namespace argocd \
  --values helm/argocd-values.yaml \
  --wait
```

---

## 2. Deploy Kargo with Helm

### 2.1 Create Values File

Create `helm/kargo-values.yaml`:

```yaml
image:
  repository: ghcr.io/akuity/kargo
  tag: v1.0.0

serviceAccount:
  create: true
  name: kargo

rbac:
  create: true

controller:
  replicas: 1

webhookServer:
  replicas: 1

api:
  enabled: true
  service:
    type: LoadBalancer
    port: 8080

config:
  logLevel: info
  namespace: kargo
```

### 2.2 Deploy to Kind Cluster

```bash
# Set context to Kind
kubectl config use-context kind-cloudopshub-local

# Create namespace
kubectl create namespace kargo

# Install Kargo
helm install kargo kargo/kargo \
  --namespace kargo \
  --values helm/kargo-values.yaml \
  --wait

# Verify deployment
kubectl get pods -n kargo
```

### 2.3 Deploy to GKE Cluster

```bash
# Set context to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

# Create namespace
kubectl create namespace kargo

# Install Kargo
helm install kargo kargo/kargo \
  --namespace kargo \
  --values helm/kargo-values.yaml \
  --wait
```

### 2.4 Access Kargo UI

```bash
# Port-forward on Kind
kubectl port-forward -n kargo svc/kargo-api 8080:8080
# Visit: http://localhost:8080
```

---

## 3. Deploy Monitoring Stack (Prometheus + Grafana) with Helm

### 3.1 Create Prometheus Values File

Create `helm/prometheus-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    replicas: 1
    retention: 30d
    
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    
    resources:
      requests:
        cpu: 500m
        memory: 500Mi
      limits:
        cpu: 1000m
        memory: 1Gi
    
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

alertmanager:
  enabled: true
  alertmanagerSpec:
    replicas: 1

grafana:
  enabled: true
  adminPassword: admin
  service:
    type: LoadBalancer
  persistence:
    enabled: true
    size: 5Gi
```

### 3.2 Deploy to Kind Cluster

```bash
# Set context to Kind
kubectl config use-context kind-cloudopshub-local

# Create namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack (includes Prometheus, Alertmanager, Grafana)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/prometheus-values.yaml \
  --wait

# Verify deployment
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

### 3.3 Deploy to GKE Cluster

```bash
# Set context to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

# Create namespace
kubectl create namespace monitoring

# Install kube-prometheus-stack
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values helm/prometheus-values.yaml \
  --wait
```

### 3.4 Access Monitoring Dashboards

```bash
# Access Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit: http://localhost:9090

# Access Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:3000
# Visit: http://localhost:3000 (user: admin, password: admin)

# Access Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Visit: http://localhost:9093
```

---

## 4. Register Clusters with ArgoCD

### 4.1 Add Kind Cluster (In-Cluster)

```bash
# Set context to Kind
kubectl config use-context kind-cloudopshub-local

# Add as in-cluster
argocd cluster add kind-cloudopshub-local \
  --in-cluster \
  --name cloudopshub-local \
  -n argocd
```

### 4.2 Add GKE Cluster

```bash
# Set context to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

# Add GKE cluster
argocd cluster add gke_expandox-cloudehub_europe-west1-b_cloud-cluster \
  --name cloud-cluster \
  -n argocd  # From Kind context!
```

### 4.3 Label Clusters for ApplicationSets

```bash
# From Kind context, label both clusters
kubectl config use-context kind-cloudopshub-local

argocd cluster patch cloudopshub-local \
  --patch '{"metadata":{"labels":{"env":"multi","region":"local"}}}' \
  -n argocd

argocd cluster patch cloud-cluster \
  --patch '{"metadata":{"labels":{"env":"multi","region":"europe-west1"}}}' \
  -n argocd

# Verify labels
argocd cluster list -n argocd
```

---

## 5. Deploy ApplicationSets (Generate 6 Apps)

### 5.1 Deploy ApplicationSet

```bash
# Set context to Kind (ArgoCD runs here)
kubectl config use-context kind-cloudopshub-local

# Deploy ApplicationSet
kubectl apply -f argocd-apps/applicationset-authenticwrite.yaml -n argocd

# Verify 6 apps generated
kubectl get applications -n argocd
# Should see: dev-cloudopshub-local, dev-cloud-cluster, staging-*, prod-*
```

---

## 6. Deploy Kargo Project

### 6.1 Deploy to Kind (Where Kargo Runs)

```bash
# Set context to Kind
kubectl config use-context kind-cloudopshub-local

# Deploy Kargo project
kubectl apply -f kargo/kargo-project.yaml -n kargo

# Verify
kubectl get project -n kargo
kubectl get warehouse -n kargo
kubectl get stage -n kargo
```

---

## 7. Secret Management (Sealed-Secrets)

### 7.1 Deploy Sealed-Secrets Controller

```bash
# On both clusters
for CONTEXT in kind-cloudopshub-local gke_expandox-cloudehub_europe-west1-b_cloud-cluster; do
  kubectl config use-context $CONTEXT
  kubectl apply -f kubernetes/sealed-secrets-install.yaml
done

# Verify controller is running
kubectl get pods -n sealed-secrets
```

### 7.2 Create & Seal GHCR Pull Secret

#### Step 1: Create the secret on Kind

```bash
kubectl config use-context kind-cloudopshub-local

kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=lakunzy7 \
  --docker-password=<YOUR-GITHUB-PAT> \
  --docker-email=your-email@example.com \
  -n authenticwrite \
  --dry-run=client -o yaml > secret.yaml
```

#### Step 2: Seal the secret

```bash
# Install kubeseal CLI (if not already installed)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/

# Seal the secret
kubeseal -f secret.yaml -w sealed-secret.yaml

# Apply sealed secret
kubectl apply -f sealed-secret.yaml -n authenticwrite
```

#### Step 3: Sync sealed-secret to GKE

```bash
# First, backup sealed-secrets key from Kind
kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key-backup.yaml

# Apply to GKE (so it can unseal the same secrets)
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f sealing-key-backup.yaml

# Apply the sealed secret to GKE
kubectl apply -f sealed-secret.yaml -n authenticwrite
```

---

## 8. Secret Management Strategy

### Option 1: Sealed-Secrets (What You Have)

**How it works:**
1. Create plain secret
2. Seal it with cluster's public key → generates sealed-secret
3. Commit sealed-secret to git (safe)
4. Controller automatically unseals it in-cluster

**Pros:**
- Secrets stored in git (encrypted)
- No external dependencies
- Automatic unsealing

**Cons:**
- Per-cluster keys (must sync keys to all clusters)
- Can't share sealed secrets between clusters

**Setup for this project:**
```bash
# Backup keys from Kind
kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key.yaml

# Apply to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f sealing-key.yaml -n sealed-secrets

# Now both clusters can unseal the same secrets
```

### Option 2: External-Secrets (Alternative)

If you want to use external secret management (AWS Secrets Manager, HashiCorp Vault, etc.):

```bash
# Install external-secrets controller
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace

# Configure SecretStore to fetch from external service
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: ghcr-secret-store
  namespace: authenticwrite
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF
```

### Option 3: SOPS (Simple & Powerful)

```bash
# Install SOPS
brew install sops

# Encrypt secrets with SOPS
sops -e secret.yaml > secret.encrypted.yaml

# Decrypt
sops -d secret.encrypted.yaml

# Commit encrypted version to git
git add secret.encrypted.yaml
```

---

## 9. Verify Everything is Deployed

```bash
# Check Kind cluster
kubectl config use-context kind-cloudopshub-local

echo "=== ArgoCD ==="
kubectl get pods -n argocd
kubectl get svc -n argocd

echo "=== Kargo ==="
kubectl get pods -n kargo

echo "=== Monitoring ==="
kubectl get pods -n monitoring
kubectl get svc -n monitoring

echo "=== Applications ==="
kubectl get applications -n argocd

echo "=== Kargo Project ==="
kubectl get project -n kargo
kubectl get stage -n kargo

# Check GKE cluster
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

echo "=== GKE: ArgoCD ==="
kubectl get pods -n argocd

echo "=== GKE: Monitoring ==="
kubectl get pods -n monitoring
```

---

## 10. Summary: What Each Tool Does

| Component | Purpose | Location | Access |
|-----------|---------|----------|--------|
| **ArgoCD** | GitOps: watches repo, auto-syncs apps | Kind cluster | `localhost:8080` |
| **Kargo** | Promotion: dev → staging → prod | Kind cluster | `localhost:8080` |
| **Prometheus** | Metrics scraping & storage | Both clusters | `localhost:9090` |
| **Grafana** | Dashboards & visualization | Both clusters | `localhost:3000` |
| **Sealed-Secrets** | Encrypt secrets in git | Both clusters | Built-in controller |
| **AuthenticWrite App** | Your app (backend + frontend) | Both clusters | Auto-deployed by ArgoCD |

---

## 11. Next Steps

1. ✅ Verify clusters running
2. ✅ Deploy ArgoCD (Helm)
3. ✅ Deploy Kargo (Helm)
4. ✅ Deploy Monitoring (Helm)
5. ✅ Register clusters with ArgoCD
6. ✅ Deploy ApplicationSets (generates 6 apps)
7. ✅ Deploy Kargo project (enables promotion)
8. ✅ Seal GHCR secrets
9. Push to GitHub when verified

See `docs/DEPLOYMENT_READY.md` for detailed 12-phase checklist.
