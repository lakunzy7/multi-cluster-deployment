# CloudOpsHub: Multi-Cluster Kubernetes Deployment

A complete infrastructure-as-code setup for deploying AuthenticWrite analytics app across two Kubernetes clusters.

## Quick Overview

- **App**: AuthenticWrite (Flask backend + React frontend)
- **Clusters**: Kind (local) + GKE (production)
- **Promotion**: dev → staging → prod (manual approval at each stage)
- **GitOps**: ArgoCD manages deployments, Kargo manages promotion

## Start Here: Follow the Deployment Checklist

```bash
# Phase 1: Setup Kind cluster
kind create cluster --config=kubernetes/kind-cluster-config.yml --name cloudopshub-local

# Phase 2: Deploy ArgoCD
kubectl apply -f kubernetes/argocd-namespace.yml
kubectl apply -f kubernetes/argocd-install.yml

# Phase 3: Deploy ApplicationSets
kubectl apply -f argocd-apps/applicationset-authenticwrite.yaml

# Phase 4: Deploy Kargo
kubectl apply -f kargo/kargo-project.yaml

# Phase 5: Deploy Monitoring
kubectl apply -f monitoring/prometheus-deployment.yaml
kubectl apply -f monitoring/grafana-deployment.yaml

# Phase 6: Deploy Backup
kubectl apply -f kubernetes/velero-install.yaml
kubectl apply -f kubernetes/sealed-secrets-install.yaml
```

## Directory Structure

```
.
├── Dockerfile.backend              # Flask + RoBERTa backend
├── Dockerfile.frontend             # React + nginx frontend
├── nginx.conf                      # Nginx API proxy config
├── kubernetes/
│   ├── argocd-install.yml         # ArgoCD deployment
│   ├── argocd-namespace.yml       # ArgoCD namespace
│   ├── cluster-secrets.yml        # Cluster credentials for GKE
│   ├── kind-cluster-config.yml    # Kind cluster config
│   ├── sealed-secrets-install.yml # Secret encryption
│   ├── velero-install.yaml        # Backup solution
│   ├── manifests/base/            # Base app manifests
│   │   ├── namespace.yaml
│   │   ├── backend.yaml
│   │   ├── frontend.yaml
│   │   ├── configmap.yaml
│   │   ├── ingress.yaml
│   │   └── kustomization.yaml
│   └── overlays/                  # Per-environment configs
│       ├── dev/kustomization.yaml
│       ├── staging/kustomization.yaml
│       └── prod/kustomization.yaml
├── argocd-apps/
│   └── applicationset-authenticwrite.yaml  # Generates 6 apps (3 envs × 2 clusters)
├── kargo/
│   └── kargo-project.yaml         # Promotion pipeline (dev → staging → prod)
├── monitoring/
│   ├── prometheus-deployment.yaml # Metrics
│   └── grafana-deployment.yaml    # Dashboards
├── docs/
│   ├── DEPLOYMENT_READY.md        # Complete 12-phase checklist
│   ├── DEPLOYMENT_RUNBOOK.md      # Step-by-step deployment
│   ├── CI_SETUP.md                # GitHub Actions setup
│   ├── BACKUP_RUNBOOK.md          # Backup/restore procedures
│   └── MONITORING_RUNBOOK.md      # Prometheus/Grafana setup
└── terraform/                      # GKE infrastructure (optional)
```

## Key Files to Know

| File | Purpose |
|------|---------|
| `kubernetes/kind-cluster-config.yml` | Creates local Kind cluster |
| `kubernetes/argocd-*.yml` | Sets up ArgoCD on Kind |
| `argocd-apps/applicationset-authenticwrite.yaml` | Deploys app to both clusters |
| `kargo/kargo-project.yaml` | Controls promotion (dev → staging → prod) |
| `kubernetes/manifests/base/` | App manifests (k8s-agnostic) |
| `kubernetes/overlays/{dev,staging,prod}/` | Environment-specific overrides |
| `monitoring/prometheus-deployment.yaml` | Metrics scraping |
| `monitoring/grafana-deployment.yaml` | Dashboards |

## Deployment Steps (30 mins for first deployment)

1. **Phase 1-2**: Create Kind cluster + deploy ArgoCD (10 mins)
2. **Phase 3-4**: Deploy ApplicationSets + Kargo (5 mins)
3. **Phase 5-6**: Deploy monitoring + backups (10 mins)
4. **Phase 7-8**: Set up secrets + GKE integration (10 mins)
5. **Phase 9-10**: Test images + smoke test (10 mins)
6. **Phase 11-12**: Backup test + push to GitHub

→ See `docs/DEPLOYMENT_READY.md` for complete phase-by-phase guide

## Critical Setup Items

⚠️ **Before deploying**, ensure you have:
- Docker installed (for Kind)
- kubectl installed
- GitHub PAT (`GITOPS_REPO_TOKEN` secret on AuthenticWrite repo)
- AWS account (for Velero S3 backups)

⚠️ **Important**: Kind kubeconfig needs server IP patched for in-cluster networking (see Phase 3 in `docs/DEPLOYMENT_READY.md`)

## CI/CD Pipeline

GitHub Actions on AuthenticWrite repo (`lakunzy7/AuthenticWrite`):
1. Builds backend + frontend images
2. Scans with Trivy (security)
3. Pushes to ghcr.io
4. Triggers Kargo to update this repo with new image tags
5. ArgoCD syncs to both clusters

→ See `docs/CI_SETUP.md` for setup instructions

## Environments

| Environment | Replicas | Hostname | Where |
|---|---|---|---|
| dev | 1 | dev.authenticwrite.local | Kind + GKE |
| staging | 2 | staging.authenticwrite.local | Kind + GKE |
| prod | 3 | authenticwrite.example.com | Kind + GKE |

**Promotion is manual**: user explicitly approves each stage transition via Kargo CLI or UI.

## Useful Commands

```bash
# View ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443

# View Kargo
kubectl port-forward -n kargo svc/kargo 8080:8080

# View Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Check deployed apps
kubectl get applications -n argocd

# Promote to staging
kargo promote authenticwrite staging --from dev

# Check backups
velero backup get
velero schedule describe daily-backup
```

## Troubleshooting

**Apps not syncing?**
- Check ArgoCD logs: `kubectl logs -n argocd deployment/argocd-application-controller`
- Verify cluster registration: `argocd cluster list`

**Kargo not detecting images?**
- Check Warehouse: `kubectl get warehouses -n kargo`
- Verify image tags in GHCR: https://github.com/lakunzy7?tab=packages

**Sealed-secrets issues?**
- Check controller: `kubectl logs -n sealed-secrets deployment/sealed-secrets-controller`
- Verify keys are synced to GKE (see `docs/DEPLOYMENT_READY.md`)

**Velero backups failing?**
- Check S3 credentials: `kubectl get secret -n velero cloud-credentials -o yaml`
- See `docs/BACKUP_RUNBOOK.md` for detailed troubleshooting

## Next Steps

1. **Read** `docs/DEPLOYMENT_READY.md` (complete checklist)
2. **Follow** phases 1-12 to deploy end-to-end
3. **Run** smoke tests (phase 10)
4. **Push** to GitHub when satisfied

## Support

- **Deployment questions?** → See `docs/DEPLOYMENT_RUNBOOK.md`
- **CI/CD setup?** → See `docs/CI_SETUP.md`
- **Backup questions?** → See `docs/BACKUP_RUNBOOK.md`
- **Monitoring setup?** → See `docs/MONITORING_RUNBOOK.md`

---

**Ready to deploy?** Start with `docs/DEPLOYMENT_READY.md` 🚀
