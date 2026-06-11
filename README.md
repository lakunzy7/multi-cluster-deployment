# AuthenticWrite — Multi-Cluster Kubernetes Deployment Guide

## Overview

This repository deploys **AuthenticWrite** (backend + frontend) across multiple Kubernetes clusters using **ArgoCD** for GitOps sync and **Kargo** for image promotion through a `dev → staging → prod` pipeline.

## Features

* Warehouse monitoring GHCR for new backend and frontend images
* Three-stage promotion pipeline: dev → staging → prod
* Automatic image tag updates committed back to Git
* Helm-based deployment with per-environment value overrides
* ArgoCD ApplicationSet generates apps for each environment automatically

## Requirements

* Kargo v1.3+ installed and accessible
* ArgoCD v2.8+ installed
* kubectl configured with cluster access
* kargo CLI installed and matching server version
* GitHub account with GHCR images set to public
* GitHub Personal Access Token (PAT) with `repo` scope

## Quick Start

### Step 1 — Prerequisites Check

```bash
# Verify kubectl access
kubectl config get-contexts

# Verify ArgoCD is running
kubectl get pods -n argocd | head -5

# Verify Kargo is running
kubectl get pods -n kargo | head -5

# Verify kargo CLI
kargo version
```

### Step 2 — Port-Forward Kargo API (required for CLI)

The kargo CLI communicates with the Kargo API server. Run this in a separate terminal and keep it open:

```bash
kubectl port-forward -n kargo svc/kargo-api 3100:443
```

### Step 3 — Login to Kargo CLI

```bash
kargo login --admin https://localhost:3100 --insecure-skip-tls-verify
```

Default admin password is `Admin123` unless changed during installation.

### Step 4 — Apply Kargo Resources

Apply all Kargo manifests at once using the kargo CLI (recommended over `kubectl apply`):

```bash
kargo apply -f ./kargo/
```

Verify resources are created:

```bash
kubectl get project -n authenticwrite
kubectl get warehouse -n authenticwrite
kubectl get stages -n authenticwrite
kubectl get promotiontasks -n authenticwrite
```

### Step 5 — Add Git Credentials to Kargo

Kargo needs write access to this repository to commit image tag updates. Use the kargo CLI with `=` syntax for flags:

```bash
kargo create repo-credentials github-creds \
  --project=authenticwrite \
  --git \
  --username=<your-github-username> \
  --repo-url=https://github.com/lakunzy7/multi-cluster-deployment.git \
  --password=<your-github-pat>
```

Or as a single line:

```bash
kargo create repo-credentials github-creds --project=authenticwrite --git --username=lakunzy7 --repo-url=https://github.com/lakunzy7/multi-cluster-deployment.git --password=YOUR_PAT
```

Your PAT must have `repo` scope (read + write). Generate at: **GitHub → Settings → Developer settings → Personal access tokens**.

Verify the credential was created:

```bash
kubectl get secret github-creds -n authenticwrite --show-labels
```

### Step 6 — Apply ArgoCD Resources

```bash
kubectl apply -f ./argocd/appproj.yaml
kubectl apply -f ./argocd/appset.yaml
```

Verify ArgoCD applications are created:

```bash
kubectl get applications -n argocd | grep authenticwrite
```

Expected output (`OutOfSync`/`Missing` is normal before first promotion):

```
authenticwrite-dev       OutOfSync     Missing
authenticwrite-staging   OutOfSync     Missing
authenticwrite-prod      OutOfSync     Missing
```

### Step 7 — Verify Warehouse Detected Images

Check that Kargo has detected freight (images) from GHCR:

```bash
kubectl get freight -n authenticwrite
```

If empty, your images may not be public. Make sure both packages are set to public on GitHub: https://github.com/lakunzy7?tab=packages

To manually trigger a warehouse refresh:

```bash
kubectl annotate warehouse authenticwrite -n authenticwrite kargo.akuity.io/refresh=true
```

### Step 8 — Promote Through the Pipeline

**Via Kargo UI**

1. Open the Kargo UI: http://localhost:3100
2. Navigate to the `authenticwrite` project
3. Click the target icon to the left of the dev stage
4. Select the detected freight and click **Yes** to promote
5. Once dev succeeds, repeat for staging then prod

**Via CLI**

```bash
# Watch promotion status
kubectl get promotions -n authenticwrite -w
```

## Deployment Pipeline

The full promotion flow from image build to deployment:

```
1. CI builds backend/frontend images → pushes to ghcr.io
   ↓
2. Kargo Warehouse detects new image tags
   ↓
3. Freight is created containing the new image references
   ↓
4. User promotes Freight: dev → staging → prod
   ↓
5. PromotionTask runs per stage:
   - git-clone: clones this repo
   - yaml-update: writes new image tags to env/{stage}/values.yaml
   - git-commit: commits the change
   - git-push: pushes back to GitHub (uses registered credentials)
   - argocd-update: triggers ArgoCD sync
   ↓
6. ArgoCD syncs updated Helm values to the cluster
   ↓
7. New images are deployed to the environment
```

### Stages

| Stage | Namespace | Replicas | Approval | Description |
|-------|-----------|----------|----------|-------------|
| **dev** | authenticwrite-dev | 1 | Manual | Development environment |
| **staging** | authenticwrite-staging | 2 | Manual | Pre-production testing |
| **prod** | authenticwrite-prod | 3 | Manual | Production deployment |

## Port Forwards & Firewall

All in-cluster services are `ClusterIP` (internal only). To reach them from outside the VM, port-forward to a local port with `--address 0.0.0.0`, then open the matching GCP firewall rule. The table below lists every port used by this project (app + tooling) and its firewall status.

| Service | Local Port | Firewall Rule | Access URL |
|---------|-----------|---------------|------------|
| **Frontend** (app) | 8080 | `allow-frontend-8080` | http://VM_IP:8080 |
| **Backend** (app) | 5000 | `allow-backend-5000` | http://VM_IP:5000 |
| **ArgoCD UI** | 8081 | `allow-argocd-8081` | https://VM_IP:8081 |
| **Kargo UI / API** | 3100 | `allow-kargo-3100` | https://VM_IP:3100 |
| **Grafana** | 3000 | `allow-grafana-3000` | http://VM_IP:3000 |
| **Prometheus** | 9090 | `allow-prometheus-9090` | http://VM_IP:9090 |
| **Alertmanager** | 9093 | `allow-alertmanager-9093` | http://VM_IP:9093 |

### Port-Forward Commands

```bash
# Frontend (app)
kubectl port-forward -n authenticwrite-dev svc/frontend 8080:80 --address 0.0.0.0

# Backend (app)
kubectl port-forward -n authenticwrite-dev svc/backend 5000:5000 --address 0.0.0.0

# ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8081:80 --address 0.0.0.0

# Kargo UI + CLI
kubectl port-forward -n kargo svc/kargo-api 3100:443 --address 0.0.0.0

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0

# Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093 --address 0.0.0.0
```

### Opening GCP Firewall Ports

```bash
gcloud compute firewall-rules create allow-<name> \
  --allow=tcp:<port> \
  --source-ranges=0.0.0.0/0 \
  --description="<purpose>"
```

> **Security note:** `--source-ranges=0.0.0.0/0` exposes the port to the entire internet — acceptable for short-lived demos. For anything longer-lived, restrict to your own IP (e.g. `--source-ranges=YOUR_IP/32`), since ArgoCD/Kargo/Grafana login pages would otherwise be publicly reachable.

## Important Notes

### PromotionTask: No Inline Credentials

In Kargo v1.3+, the `git-clone` and `git-push` steps do **NOT** support inline credentials config. The `credentials` block inside step config will cause promotion to fail with:

```
invalid git-clone config: (root): Additional property credentials is not allowed
```

Credentials must be registered at the project level using `kargo create repo-credentials` (Step 5 above). Kargo automatically injects them for all Git operations in the project namespace.

### kargo CLI Flag Syntax

The kargo CLI requires `=` between flag names and values. Space-separated values will fail:

```bash
# WRONG - will fail
kargo create repo-credentials --project authenticwrite --username lakunzy7

# CORRECT
kargo create repo-credentials --project=authenticwrite --username=lakunzy7
```

### Port-Forward Must Stay Open

The kargo CLI requires the port-forward to be active. If you get `connection refused`, restart it:

```bash
kubectl port-forward -n kargo svc/kargo-api 3100:443
```

### GHCR Images Must Be Public

The Kargo Warehouse cannot discover images from private GHCR repositories without image pull credentials. Set both packages to public:

* Go to https://github.com/lakunzy7?tab=packages
* Click each package → Package settings → Change visibility → Public

## Directory Structure

```
.
├── README.md
├── argocd/
│   ├── appproj.yaml        # ArgoCD Project (security boundary)
│   └── appset.yaml         # ApplicationSet (generates 3 Applications)
├── kargo/
│   ├── project.yaml        # Kargo Project (creates namespace)
│   ├── warehouse.yaml      # Monitors ghcr.io for new images
│   ├── stages.yaml         # dev, staging, prod stage definitions
│   └── promotiontask.yaml  # Git clone → update → commit → push → sync
├── charts/
│   └── authenticwrite/     # Helm chart (templates + base values)
├── env/
│   ├── dev/values.yaml     # Dev overrides (1 replica)
│   ├── staging/values.yaml # Staging overrides (2 replicas)
│   └── prod/values.yaml    # Prod overrides (3 replicas)
├── helm/                   # ArgoCD + Kargo installation values
└── terraform/              # GKE infrastructure
```

## Useful Commands

### View Status

```bash
# All ArgoCD applications
kubectl get applications -n argocd | grep authenticwrite

# Kargo pipeline state
kubectl get stages -n authenticwrite
kubectl get freight -n authenticwrite
kubectl get promotions -n authenticwrite

# Pod status per environment
kubectl get pods -n authenticwrite-dev
kubectl get pods -n authenticwrite-staging
kubectl get pods -n authenticwrite-prod
```

### Simulate a New Release

To test the pipeline with a new image tag, push a new tag to GHCR, then refresh the warehouse:

```bash
# Refresh warehouse to detect new images
kubectl annotate warehouse authenticwrite -n authenticwrite kargo.akuity.io/refresh=true

# Watch for new freight
kubectl get freight -n authenticwrite -w
```

### View Logs

```bash
# Backend logs
kubectl logs -n authenticwrite-dev deployment/backend -f

# Frontend logs
kubectl logs -n authenticwrite-dev deployment/frontend -f

# Kargo controller logs
kubectl logs -n kargo deployment/kargo-controller -f

# ArgoCD controller logs
kubectl logs -n argocd deployment/argocd-application-controller -f
```

## Troubleshooting

### Promotion fails with `Additional property credentials is not allowed`

Remove any `credentials` block from `git-clone` or `git-push` steps in `promotiontask.yaml`. Register credentials using `kargo create repo-credentials` instead (see Step 5).

### git-push fails with `could not read Username`

The project-level credential secret is missing or not labelled correctly. Verify:

```bash
kubectl get secret github-creds -n authenticwrite --show-labels
# Should show label: kargo.akuity.io/cred-type=git
```

If missing, re-run Step 5 to recreate using `kargo create repo-credentials`.

### kargo CLI: `connection refused`

The port-forward is not running. Open a new terminal and run:

```bash
kubectl port-forward -n kargo svc/kargo-api 3100:443
```

### kargo CLI: `token expired`

```bash
kargo login --admin https://localhost:3100 --insecure-skip-tls-verify
```

### Warehouse shows no freight

* Ensure both GHCR images are set to public
* Check the `allowTags` regex matches your image tag format
* Manually refresh: `kubectl annotate warehouse authenticwrite -n authenticwrite kargo.akuity.io/refresh=true`

### ArgoCD apps stuck in OutOfSync/Missing

This is expected before the first promotion. Once you promote to a stage, ArgoCD will sync automatically. You can also force sync:

```bash
kubectl patch application authenticwrite-dev -n argocd --type merge -p '{"operation":{"sync":{}}}'
```

## References

* Kargo Documentation: https://kargo.akuity.io
* ArgoCD Documentation: https://argo-cd.readthedocs.io
* Helm Documentation: https://helm.sh/docs
* GHCR Packages: https://github.com/lakunzy7?tab=packages

---

**Status**: Production Ready ✅
