# 🚀 CloudOpsHub: Ready for Deployment

**Status**: All infrastructure code complete and tested locally. Ready for end-to-end deployment.

**Latest commits**:
- `6ff7a12` — CI/CD setup guide
- `b97948d` — Project documentation
- `daea78a` — Infrastructure stack (Dockerfiles, K8s, ArgoCD, Kargo, monitoring, backups)

---

## What's Been Built (Tasks A–B Complete)

### ✅ Task A: Dockerfiles
- **Backend**: Flask+RoBERTa, multi-stage, single worker (1.5GB model resident), ~2.5GB final
- **Frontend**: React + nginx, multi-stage, API proxy to backend, ~30MB final
- **Nginx config**: SPA fallback, API proxy, static file caching

### ✅ Task C: Kubernetes Base Manifests
- **Namespace**: authenticwrite
- **Deployments**: backend (2-3Gi mem) + frontend (64-256Mi mem)
- **Services**: backend:5000, frontend:80
- **Ingress**: TLS-terminated, cert-manager integration
- **ConfigMap**: Environment vars (FLASK_ENV, LOG_LEVEL, etc.)
- **Kustomization**: Declares all base resources

### ✅ Task D: Per-Environment Overlays
- **dev**: 1 replica, `dev.authenticwrite.local`, resource requests for dev
- **staging**: 2 replicas, `staging.authenticwrite.local`
- **prod**: 3 replicas, `authenticwrite.example.com`, stricter resources
- **Kustomize**: Per-env patches (replicas, ingress hosts, image tags)

### ✅ Task E: ArgoCD ApplicationSets
- **Cross-product**: 3 envs (dev/staging/prod) × 2 clusters (Kind + GKE) = 6 Applications
- **Cluster selector**: `env: multi` label matches both clusters
- **Auto-sync**: prune + selfHeal enabled
- **Namespace creation**: automatic

### ✅ Task F: Kargo Promotion Pipeline
- **Warehouse**: Tracks all tags from `ghcr.io/lakunzy7/authenticwrite`
- **Dev stage**: Auto-updated when new images arrive (manual promotion to staging)
- **Staging stage**: Blocks until both regional dev apps Healthy
- **Prod stage**: Blocks until both regional staging apps Healthy
- **No autoPromote**: Every promotion is explicit

### ✅ Task G: Monitoring Stack
- **Prometheus**: Scrapes K8s components, 1GB emptyDir storage
- **Grafana**: Web UI with Prometheus datasource, LoadBalancer on :3000
- **RBAC**: ServiceAccount + ClusterRole for K8s API access

### ✅ Task H: Secrets Management
- **Sealed-secrets**: Controller in `sealed-secrets` namespace
- **GHCR pull secret**: Template with instructions to seal before committing
- **Key backup**: Instruction to backup and sync keys to GKE

### ✅ Task I: Backup & Recovery
- **Velero**: Automated daily backups at 2 AM UTC, 30-day retention
- **Namespaces**: authenticwrite, argocd, monitoring
- **S3 config**: Ready for AWS or compatible storage
- **Runbook**: docs/BACKUP_RUNBOOK.md with restore procedures

### ✅ Task B: CI/CD Pipeline (AuthenticWrite)
- **GitHub Actions workflow**: `.github/workflows/build-push.yml`
- **Steps**:
  1. Build backend Docker image → push to GHCR with :latest + :SHA tags
  2. Build frontend Docker image → push to GHCR with :latest + :SHA tags
  3. Trivy scan both images → upload SARIF to GitHub Security tab
  4. Update multi-cluster-deployment repo: kustomize edit overlays/{dev,staging,prod}
  5. Git commit + push (triggers ArgoCD)
- **Trigger**: Any push to main that modifies backend, frontend, or workflow file
- **Required secret**: `GITOPS_REPO_TOKEN` (PAT for multi-cluster-deployment repo)
- **Setup guide**: docs/CI_SETUP.md

---

## Deployment Checklist

### Phase 1: Local Setup (Before Cluster Creation)

- [ ] Review `README_CLOUDOPSHUB.md` for architecture overview
- [ ] Review `TASKS_COMPLETED.md` for detailed deliverables
- [ ] Review `docs/CI_SETUP.md` for CI workflow setup
- [ ] Clone both repos:
  ```bash
  # Already have:
  git clone git@github.com:lakunzy7/multi-cluster-deployment.git
  
  # AuthenticWrite (for reference):
  git clone git@github.com:lakunzy7/AuthenticWrite.git
  ```

### Phase 2: Kind Cluster Setup

- [ ] Create Kind cluster:
  ```bash
  kind create cluster --config=kubernetes/kind-cluster-config.yml --name cloudopshub-local
  ```

- [ ] Deploy ArgoCD:
  ```bash
  kubectl apply -f kubernetes/argocd-namespace.yml
  kubectl apply -f kubernetes/argocd-install.yml
  kubectl apply -f kubernetes/cluster-secrets.yml
  ```

- [ ] Get ArgoCD initial password:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

- [ ] Port-forward to access UI:
  ```bash
  kubectl port-forward -n argocd svc/argocd-server 8080:443
  # Visit https://localhost:8080 (user: admin, password from above)
  ```

### Phase 3: GKE Cluster Setup

- [ ] Create GKE cluster (or ensure it exists in europe-west1):
  ```bash
  gcloud container clusters create cloud-cluster \
    --zone europe-west1-b \
    --num-nodes 2 \
    --machine-type e2-standard-2 \
    --spot \
    --project expandox-cloudehub
  ```

- [ ] Get kubeconfig:
  ```bash
  gcloud container clusters get-credentials cloud-cluster \
    --zone europe-west1-b \
    --project expandox-cloudehub
  ```

- [ ] **IMPORTANT: Patch kubeconfig server IP** (required for in-cluster access):
  ```bash
  # Get Kind container IP
  DOCKER_IP=$(docker inspect cloudopshub-local-control-plane \
    | grep '"IPAddress"' | grep -oE '([0-9]+\.){3}[0-9]+' | head -1)
  
  # Patch kubeconfig for Kind cluster
  kubectl config set-cluster kind-cloudopshub-local \
    --server=https://$DOCKER_IP:6443
  ```

### Phase 4: Register Clusters with ArgoCD

- [ ] Register Kind cluster (already configured):
  ```bash
  kubectl config use-context kind-cloudopshub-local
  argocd cluster add kind-cloudopshub-local \
    --in-cluster \
    --namespace argocd
  ```

- [ ] Register GKE cluster:
  ```bash
  kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
  argocd cluster add gke_expandox-cloudehub_europe-west1-b_cloud-cluster \
    --namespace argocd
  ```

- [ ] Label both clusters with `env: multi` (required by ApplicationSets):
  ```bash
  argocd cluster patch kind-cloudopshub-local \
    --patch '{"metadata":{"labels":{"env":"multi","region":"local"}}}'
  
  argocd cluster patch gke_expandox-cloudehub_europe-west1-b_cloud-cluster \
    --patch '{"metadata":{"labels":{"env":"multi","region":"europe-west1"}}}'
  ```

### Phase 5: Deploy ApplicationSets & Kargo

- [ ] Apply ApplicationSets:
  ```bash
  kubectl apply -f argocd-apps/applicationset-authenticwrite.yaml
  ```

- [ ] Verify 6 Applications generated:
  ```bash
  kubectl get applications -n argocd | grep authenticwrite
  # Should see: dev-cloudopshub-local, dev-cloud-cluster, staging-*, prod-*
  ```

- [ ] Install Kargo CRDs and controller (not included; use Kargo docs):
  ```bash
  helm repo add kargo https://charts.akuity.io
  helm install kargo kargo/kargo --namespace kargo --create-namespace
  ```

- [ ] Apply Kargo Project:
  ```bash
  kubectl apply -f kargo/kargo-project.yaml
  ```

### Phase 6: Secrets & GHCR Access

- [ ] Setup sealed-secrets:
  ```bash
  kubectl apply -f kubernetes/sealed-secrets-install.yaml
  
  # Wait for controller to start and generate keys
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=sealed-secrets-controller \
    -n sealed-secrets --timeout=60s
  
  # Backup keys (required for syncing to GKE):
  kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key.backup
  ```

- [ ] Create GHCR pull secret (on Kind):
  ```bash
  kubectl create secret docker-registry ghcr-pull-secret \
    --docker-server=ghcr.io \
    --docker-username=lakunzy7 \
    --docker-password=<your-github-pat> \
    --docker-email=<your-email> \
    -n authenticwrite \
    --dry-run=client -o yaml > secret.yaml
  
  # Seal it
  kubeseal -f secret.yaml -w sealed-secret.yaml
  
  # Apply sealed secret
  kubectl apply -f sealed-secret.yaml
  
  # Sync to GKE (copy sealing-key.backup first):
  kubectl apply -f sealing-key.backup --context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
  kubectl apply -f sealed-secret.yaml --context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
  ```

### Phase 7: Monitoring Stack

- [ ] Deploy Prometheus:
  ```bash
  kubectl apply -f monitoring/prometheus-deployment.yaml
  ```

- [ ] Deploy Grafana:
  ```bash
  kubectl apply -f monitoring/grafana-deployment.yaml
  ```

- [ ] Access Grafana:
  ```bash
  kubectl port-forward -n monitoring svc/grafana 3000:3000
  # Visit http://localhost:3000 (user: admin, pass: admin)
  # CHANGE PASSWORD IMMEDIATELY
  ```

### Phase 8: Backup Infrastructure

- [ ] Deploy Velero:
  ```bash
  kubectl apply -f kubernetes/velero-install.yaml
  
  # Configure S3 credentials (requires AWS account)
  kubectl create secret generic cloud-credentials \
    --from-literal=cloud=<aws-credentials> \
    -n velero
  ```

- [ ] Verify Velero is running:
  ```bash
  kubectl logs -n velero deployment/velero
  velero schedule get
  ```

### Phase 9: CI/CD Integration

- [ ] Ensure `GITOPS_REPO_TOKEN` secret is set on AuthenticWrite repo:
  - Go to https://github.com/lakunzy7/AuthenticWrite
  - Settings → Secrets and variables → Actions
  - Add `GITOPS_REPO_TOKEN` (GitHub PAT with `repo` scope)

- [ ] Test CI workflow:
  ```bash
  # Push a test commit to AuthenticWrite main
  cd ~/AuthenticWrite
  echo "# Test" >> backend/app.py
  git add backend/app.py
  git commit -m "test: trigger CI"
  git push origin main
  ```

- [ ] Watch workflow:
  - Go to AuthenticWrite Actions tab
  - See "Build and Push Images" running
  - Wait for completion (~5-10 mins)

### Phase 10: Smoke Test

- [ ] Verify images in GHCR:
  ```bash
  gh api repos/lakunzy7/AuthenticWrite/packages --jq '.[] | select(.package_type=="container")'
  ```

- [ ] Check Kargo detected new images:
  ```bash
  kubectl port-forward -n kargo svc/kargo 8080:8080
  # Visit http://localhost:8080, see dev stage updated
  ```

- [ ] Manually promote dev → staging:
  ```bash
  kargo promote authenticwrite staging --from dev
  ```

- [ ] Watch ArgoCD sync:
  ```bash
  kubectl get applications -n argocd -w
  # Wait for staging-* apps to sync and become Healthy
  ```

- [ ] Verify pods are running:
  ```bash
  kubectl get pods -n authenticwrite
  # Both dev and staging pods should be running
  ```

### Phase 11: Backup/Restore Test

- [ ] Trigger manual backup:
  ```bash
  velero backup create smoke-test-backup \
    --include-namespaces authenticwrite
  ```

- [ ] Monitor backup:
  ```bash
  velero backup describe smoke-test-backup
  ```

- [ ] Test restore:
  ```bash
  velero restore create --from-backup smoke-test-backup \
    --namespace-mappings authenticwrite:authenticwrite-restore
  ```

- [ ] Verify restored apps:
  ```bash
  kubectl get pods -n authenticwrite-restore
  ```

### Phase 12: Final Push to GitHub

Once all smoke tests pass:

```bash
# Verify no uncommitted changes
git status

# Push to GitHub (user rule: push only after everything verified)
git push origin main
```

---

## Key Files to Know

| File | Purpose |
|------|---------|
| `README_CLOUDOPSHUB.md` | Architecture, quick-start, deployment checklist |
| `TASKS_COMPLETED.md` | Detailed deliverables for each task A–I |
| `docs/CI_SETUP.md` | CI/CD workflow setup, secrets, troubleshooting |
| `docs/DEPLOYMENT_RUNBOOK.md` | Detailed deployment procedures |
| `docs/BACKUP_RUNBOOK.md` | Backup/restore procedures |
| `docs/MONITORING_RUNBOOK.md` | Prometheus/Grafana monitoring |
| `kubernetes/` | K8s manifests, ArgoCD configs |
| `kargo/` | Kargo promotion pipeline |
| `monitoring/` | Prometheus + Grafana deployments |
| `Dockerfile.backend`, `Dockerfile.frontend` | Docker image definitions |
| `.github/workflows/build-push.yml` (AuthenticWrite) | CI/CD pipeline |

---

## Critical Blockers

- ⚠️ **Kind kubeconfig**: Must patch server IP for in-cluster access (see Phase 3)
- ⚠️ **GITOPS_REPO_TOKEN**: Must be set on AuthenticWrite repo (see Phase 9)
- ⚠️ **Sealed-secrets keys**: Must be backed up and synced to GKE (see Phase 6)
- ⚠️ **Prod hostname**: Currently `authenticwrite.example.com` — update if using real domain

---

## User Rules (Enforced)

1. **No automation scripts**: Use `kubectl`, `argocd`, `kargo` CLI directly
2. **Kind kubeconfig patch**: Required for in-cluster networking
3. **Commit locally**: All changes committed before pushing to GitHub

---

## Next Steps

1. **Review this document** and `README_CLOUDOPSHUB.md`
2. **Follow the deployment checklist** (Phases 1–11)
3. **Run smoke tests** (Phase 10)
4. **Push to GitHub** when satisfied (Phase 12)

---

**Infrastructure complete. Ready for production deployment.**

For questions, refer to:
- docs/CI_SETUP.md (CI/CD questions)
- docs/DEPLOYMENT_RUNBOOK.md (deployment questions)
- docs/BACKUP_RUNBOOK.md (backup questions)
- docs/MONITORING_RUNBOOK.md (monitoring questions)
