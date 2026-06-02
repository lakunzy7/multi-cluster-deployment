# CloudOpsHub: Multi-Cluster Deployment Infrastructure

**Status**: Ready for integration (Tasks A–I complete, Task B pending AuthenticWrite repo access)

**Commit**: `daea78a` (2026-06-02)

## What This Is

CloudOpsHub is an automated multi-cluster infrastructure platform for a SaaS analytics company. It deploys **AuthenticWrite** (a proprietary analytics app) to two Kubernetes clusters:

1. **Kind** on WSL2 (local control plane) — runs ArgoCD, Kargo, monitoring
2. **GKE** in europe-west1 (production region) — runs workloads

Three environments fan out to both clusters via ArgoCD ApplicationSets, managed by Kargo for safe, multi-region promotion.

## Architecture at a Glance

```
GitHub (lakunzy7/multi-cluster-deployment)
  ↓
ArgoCD (on Kind) watches repo
  ↓
Kargo (on Kind) monitors GHCR for new images
  ↓
Manual promotion: dev → staging → prod
  ↓
Sync to both clusters with health gates (both regions must be Healthy)
```

## Quick Start

### 1. Create Kind Cluster
```bash
kind create cluster --config=kubernetes/kind-cluster-config.yml --name cloudopshub-local
```

### 2. Deploy ArgoCD
```bash
kubectl apply -f kubernetes/argocd-namespace.yml
kubectl apply -f kubernetes/argocd-install.yml
kubectl apply -f kubernetes/cluster-secrets.yml
```

### 3. Register GKE Cluster
```bash
# Get GKE kubeconfig
gcloud container clusters get-credentials cloud-cluster --zone europe-west1-b --project expandox-cloudehub

# Add to ArgoCD (with kubeconfig server IP patched — see DEPLOYMENT_RUNBOOK.md)
argocd cluster add gke_expandox-cloudehub_europe-west1-b_cloud-cluster
```

### 4. Deploy Application Sets
```bash
kubectl apply -f argocd-apps/applicationset-authenticwrite.yaml
```

This generates 6 Applications (3 envs × 2 clusters).

### 5. Deploy Kargo
```bash
# Install Kargo CRDs and controller (not included; use Kargo helm chart)
kubectl apply -f kargo/kargo-project.yaml
```

### 6. Deploy Monitoring
```bash
kubectl apply -f monitoring/prometheus-deployment.yaml
kubectl apply -f monitoring/grafana-deployment.yaml
```

### 7. Deploy Backup Infrastructure
```bash
# Velero requires AWS S3 credentials
kubectl apply -f kubernetes/velero-install.yaml
# Then initialize: velero schedule get
```

## Key Files

### Dockerfiles
- **Dockerfile.backend** — Flask + RoBERTa (~2.5 GB, single worker, 1.5GB model resident)
- **Dockerfile.frontend** — React + nginx (~30 MB, proxies /api/* to backend)
- **nginx.conf** — Proxy config and SPA fallback

### Kubernetes Manifests
- **kubernetes/manifests/base/** — Base resources (env-agnostic)
- **kubernetes/overlays/{dev,staging,prod}/** — Per-env configs (replicas, hostnames, resources)

### GitOps & Promotion
- **argocd-apps/applicationset-authenticwrite.yaml** — Auto-generates 6 Applications
- **kargo/kargo-project.yaml** — Manual promotion with multi-region health gates

### Observability & Safety
- **monitoring/prometheus-deployment.yaml** — Metrics scraping
- **monitoring/grafana-deployment.yaml** — Dashboards
- **kubernetes/sealed-secrets-install.yaml** — Secret encryption
- **kubernetes/velero-install.yaml** — Automated backups

## Environment Config

| Env | Replicas | Hostname | Kargo Source | Notes |
|-----|----------|----------|--------------|-------|
| dev | 1 | dev.authenticwrite.local | Warehouse | Manual promotion |
| staging | 2 | staging.authenticwrite.local | dev | Manual promotion |
| prod | 3 | authenticwrite.example.com | staging | Manual promotion |

**Manual Promotion**: User must explicitly trigger each stage transition via Kargo CLI or UI. Both regional Applications must be Healthy before proceeding.

## Kargo Promotion Flow

```
New image pushed to GHCR (e.g., ghcr.io/lakunzy7/authenticwrite/backend:v1.2.3)
  ↓
Kargo Warehouse detects tag
  ↓
User promotes dev → staging (manual click/CLI)
  ↓
Kargo edits overlays/staging/kustomization.yaml (new image tags)
  ↓
ArgoCD detects git change, syncs to both clusters
  ↓
Kargo polls both regional dev Apps for Healthy status
  ↓
Once BOTH Healthy, staging promotion is complete
  ↓
User can then promote staging → prod (same flow)
```

## Security & Secrets

### GHCR Pull Credentials
1. Create secret from Docker credentials:
   ```bash
   kubectl create secret docker-registry ghcr-pull-secret \
     --docker-server=ghcr.io \
     --docker-username=<github-user> \
     --docker-password=<github-pat> \
     -n authenticwrite --dry-run=client -o yaml > secret.yaml
   ```

2. Seal it:
   ```bash
   kubeseal -f secret.yaml -w sealed-secret.yaml
   ```

3. Apply:
   ```bash
   kubectl apply -f sealed-secret.yaml
   ```

### Sealed-Secrets Key Management
- Keys are generated on first controller start and stored in `sealed-secrets/sealed-secrets-keys` Secret
- **Back them up**: `kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key.backup`
- **Sync across clusters**: Copy the backup Secret to GKE so both clusters can unseal the same secrets

## Monitoring

### Prometheus
- Scrapes all K8s components (APIServer, nodes, pods, services)
- Accessible at `kubectl port-forward -n monitoring svc/prometheus 9090:9090`

### Grafana
- Datasource: Prometheus (auto-provisioned)
- Access: `kubectl port-forward -n monitoring svc/grafana 3000:3000`
- Default credentials: admin/admin (change immediately post-deployment)

## Backup & Recovery

### Automatic Backups
- **Schedule**: 2 AM UTC daily
- **Retention**: 30 days
- **Includes**: authenticwrite, argocd, monitoring namespaces + all PVs

### Manual Backup
```bash
velero backup create my-backup --include-namespaces authenticwrite
velero backup logs my-backup
```

### Restore
```bash
velero restore create --from-backup my-backup --include-namespaces authenticwrite
```

See **docs/BACKUP_RUNBOOK.md** for full procedures.

## Next Steps: Task B (CI on AuthenticWrite)

To complete the pipeline, implement GitHub Actions on the **lakunzy7/AuthenticWrite** repo:

1. Build Dockerfile.backend and Dockerfile.frontend
2. Scan with Trivy for vulnerabilities
3. Push to ghcr.io/lakunzy7/authenticwrite/{backend,frontend}:$SHA
4. Trigger this repo's Kargo (optional: via webhook, or manual)

Once images start flowing to GHCR, Kargo watches for them and the promotion pipeline kicks off.

## Deployment Checklist

- [ ] Create Kind cluster
- [ ] Deploy ArgoCD
- [ ] Register GKE cluster with ArgoCD
- [ ] Apply ApplicationSets (generates 6 Applications)
- [ ] Deploy Kargo
- [ ] Setup sealed-secrets and sync keys to GKE
- [ ] Create GHCR pull secret (seal it first)
- [ ] Deploy monitoring stack
- [ ] Setup Velero backups
- [ ] Build first AuthenticWrite images and push to GHCR
- [ ] Trigger Kargo: dev → staging → prod (smoke test)
- [ ] Verify both regional apps are Healthy
- [ ] Run full end-to-end backup/restore test
- [ ] Push to GitHub

See **docs/DEPLOYMENT_RUNBOOK.md** for detailed instructions.

## User Rules

- **No bash wrappers**: Use `kubectl`, `argocd`, `kargo` CLI directly. No `scripts/deploy.sh`.
- **Kind kubeconfig patch**: `kind get kubeconfig` needs server IP patched to in-cluster IP before registering with ArgoCD.
- **No GH push until verified**: Commit locally, push only after full end-to-end test.

## References

- **ArgoCD**: https://argo-cd.readthedocs.io/
- **Kargo**: https://kargo.akuity.io/
- **Velero**: https://velero.io/
- **Sealed-Secrets**: https://github.com/bitnami-labs/sealed-secrets
- **Prometheus**: https://prometheus.io/
- **Grafana**: https://grafana.com/

---

**Infrastructure complete.** Ready for CI integration and end-to-end testing.
