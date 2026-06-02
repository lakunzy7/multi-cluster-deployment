# Phase 2: Helm Deployment Quick Start

**TL;DR**: Deploy ArgoCD, Kargo, and Monitoring with Helm charts.

---

## Quick Commands (Copy-Paste)

### 1️⃣ Add Helm Repos

```bash
helm repo add argocd https://argoproj.github.io/argo-helm
helm repo add kargo https://charts.akuity.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 2️⃣ Deploy to Kind Cluster

```bash
# Set context
kubectl config use-context kind-cloudopshub-local

# ArgoCD
kubectl create namespace argocd
helm install argocd argocd/argo-cd --namespace argocd --wait

# Get password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Visit: https://localhost:8080 (user: admin)
```

### 3️⃣ Deploy to GKE Cluster

```bash
# Set context
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

# ArgoCD
kubectl create namespace argocd
helm install argocd argocd/argo-cd --namespace argocd --wait

# Monitoring (Prometheus + Grafana)
kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin \
  --wait
```

### 4️⃣ Register Clusters with ArgoCD (From Kind)

```bash
kubectl config use-context kind-cloudopshub-local

# Register Kind (in-cluster)
argocd cluster add kind-cloudopshub-local --in-cluster --name cloudopshub-local -n argocd

# Register GKE
argocd cluster add gke_expandox-cloudehub_europe-west1-b_cloud-cluster --name cloud-cluster -n argocd

# Label both clusters
argocd cluster patch cloudopshub-local --patch '{"metadata":{"labels":{"env":"multi","region":"local"}}}' -n argocd
argocd cluster patch cloud-cluster --patch '{"metadata":{"labels":{"env":"multi","region":"europe-west1"}}}' -n argocd
```

### 5️⃣ Deploy Kargo (To Kind)

```bash
kubectl config use-context kind-cloudopshub-local

# Create namespace
kubectl create namespace kargo

# Install Kargo
helm install kargo kargo/kargo --namespace kargo --wait

# Deploy project
kubectl apply -f kargo/kargo-project.yaml -n kargo

# Port-forward
kubectl port-forward -n kargo svc/kargo-api 8080:8080
# Visit: http://localhost:8080
```

### 6️⃣ Deploy Monitoring to Kind

```bash
kubectl config use-context kind-cloudopshub-local

kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin \
  --wait

# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:3000
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin)
```

### 7️⃣ Deploy ApplicationSets (Generates 6 Apps)

```bash
kubectl config use-context kind-cloudopshub-local

kubectl apply -f argocd-apps/applicationset-authenticwrite.yaml -n argocd

# Verify 6 apps generated
kubectl get applications -n argocd
```

### 8️⃣ Setup Sealed-Secrets

```bash
# Deploy to Kind
kubectl config use-context kind-cloudopshub-local
kubectl apply -f kubernetes/sealed-secrets-install.yaml

# Deploy to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f kubernetes/sealed-secrets-install.yaml

# Backup Key from Kind
kubectl config use-context kind-cloudopshub-local
kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key-backup.yaml

# Sync to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f sealing-key-backup.yaml
```

### 9️⃣ Create & Seal GHCR Credentials

```bash
kubectl config use-context kind-cloudopshub-local

# Create plain secret
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=lakunzy7 \
  --docker-password=YOUR_GITHUB_PAT \
  --docker-email=your-email@example.com \
  -n authenticwrite \
  --dry-run=client -o yaml > secret.yaml

# Seal it
kubeseal -f secret.yaml -w sealed-secret.yaml

# Apply to Kind
kubectl apply -f sealed-secret.yaml -n authenticwrite

# Apply to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f sealed-secret.yaml -n authenticwrite

# Commit to git (sealed-secret is safe)
git add sealed-secret.yaml
git commit -m "chore: add sealed GHCR credentials"
git push origin main

# Delete plain secret
rm secret.yaml
```

---

## Verification Checklist

```bash
# Kind Cluster
kubectl config use-context kind-cloudopshub-local

echo "=== ArgoCD ==="
kubectl get pods -n argocd
kubectl get svc -n argocd

echo "=== Kargo ==="
kubectl get pods -n kargo
kubectl get project -n kargo
kubectl get stage -n kargo

echo "=== Monitoring ==="
kubectl get pods -n monitoring

echo "=== Applications ==="
kubectl get applications -n argocd  # Should see 6 apps

echo "=== Sealed-Secrets ==="
kubectl get secret -n authenticwrite ghcr-pull-secret

# GKE Cluster
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

echo "=== GKE ArgoCD ==="
kubectl get pods -n argocd

echo "=== GKE Monitoring ==="
kubectl get pods -n monitoring
```

---

## Access Dashboard URLs

```bash
# ArgoCD (Kind)
kubectl port-forward -n argocd svc/argocd-server 8080:443
# https://localhost:8080 (admin / <password from step 2>)

# Kargo (Kind)
kubectl port-forward -n kargo svc/kargo-api 8080:8080
# http://localhost:8080

# Prometheus (Kind)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090

# Grafana (Kind)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:3000
# http://localhost:3000 (admin/admin)
```

---

## What Just Happened?

| Component | Purpose | Location | Status |
|-----------|---------|----------|--------|
| **ArgoCD** | GitOps automation (watches repo) | Both clusters | ✅ Deployed |
| **Kargo** | Promotion pipeline (dev→staging→prod) | Kind cluster | ✅ Deployed |
| **Prometheus** | Metrics scraping | Both clusters | ✅ Deployed |
| **Grafana** | Dashboards & visualization | Both clusters | ✅ Deployed |
| **Sealed-Secrets** | Encrypt secrets in git | Both clusters | ✅ Deployed |
| **GHCR Credentials** | Pull images from GitHub registry | Both clusters | ✅ Sealed & applied |
| **ApplicationSets** | Auto-generates 6 apps (3 envs × 2 clusters) | Kind cluster | ✅ Deployed |

---

## Troubleshooting

### ArgoCD pods not starting?
```bash
kubectl logs -n argocd deployment/argocd-application-controller
```

### Kargo not detecting images?
```bash
kubectl logs -n kargo deployment/kargo-controller
kubectl get warehouse -n kargo
```

### Secrets not unsealing?
```bash
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller
```

### Pods can't pull images (ImagePullBackOff)?
```bash
kubectl get secret -n authenticwrite ghcr-pull-secret
kubectl describe pod <pod-name> -n authenticwrite
```

---

## Next Steps (Phase 3)

1. ✅ Deploy ArgoCD (Helm)
2. ✅ Deploy Kargo (Helm)
3. ✅ Deploy Monitoring (Helm)
4. ✅ Setup Sealed-Secrets
5. ✅ Create GHCR credentials
6. ➡️ **Phase 3**: Push first images to GHCR → Kargo picks them up → Promotes through environments

See `docs/HELM_DEPLOYMENT.md` for detailed instructions.

---

**Commit**: `1d69a41`
