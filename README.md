# AuthenticWrite — Multi-Cluster Kubernetes Deployment

Deploy the **AuthenticWrite** app (backend + frontend) across **two Kubernetes
clusters** using **GitOps**. ArgoCD keeps the clusters matching Git; Kargo
promotes images through a `dev → staging → prod` pipeline.

This root README is the **A-to-Z walkthrough**. Each folder has its own deep-dive
README — this page tells you the order to read them and run them in.

---

## What you'll build

```
                ┌──────────────── LOCAL cluster (Kind/k3s) ────────────────┐
                │  ArgoCD ─── watches Git, syncs both clusters             │
   Git repo ───►│  Kargo  ─── promotes images, writes tags back to Git     │──► GKE cluster
   (this repo)  │  Sealed Secrets ─── stores the GKE access token safely   │    (Terraform)
                └──────────────────────────────────────────────────────────┘
                        deploys to        deploys to
                        "in-cluster"      "k8slab-second-cluster"
```

- **Two clusters:** a **local** cluster (runs ArgoCD + Kargo + a copy of the app)
  and a **GKE** cluster (a second deploy target).
- **Three environments** per cluster: `dev`, `staging`, `prod` — so the
  ApplicationSet generates **6 deployments** (3 envs × 2 clusters).
- **GitOps:** you never `kubectl apply` the app. You change Git; ArgoCD deploys.
- **Promotion:** Kargo detects new images, and on promotion writes the new tag
  into Git, which ArgoCD then rolls out.

---

## The folder guides (read in this order)

| Order | Folder | What it teaches |
|-------|--------|-----------------|
| 1 | [`terraform/`](terraform/README.md) | Create the **local cluster** and the **GKE cluster** (Terraform). |
| 2 | [`helm/`](helm/README.md) | Install **ArgoCD** + **Kargo** with Helm, and **register the GKE cluster** into ArgoCD. |
| 3 | [`argocd/`](argocd/README.md) | The **AppProject** + **ApplicationSet** that generate the 6 apps. |
| 4 | [`kargo/`](kargo/README.md) | The **promotion pipeline** (Warehouse → Stages → PromotionTask) + git credentials. |
| 5 | [`charts/authenticwrite/`](charts/authenticwrite/README.md) | The **Helm chart** for the app (backend + frontend). |
| 6 | [`env/`](env/README.md) | The **per-environment** value overrides (replicas, tags). |

---

## Requirements

Install these CLIs locally first:

| Tool | Why | Check |
|------|-----|-------|
| `terraform` (≥1.0) | Builds the GKE cluster | `terraform -version` |
| `gcloud` + `gke-gcloud-auth-plugin` | GCP auth, kubectl→GKE | `gcloud version` |
| `kubectl` | Talk to both clusters | `kubectl version --client` |
| `helm` (≥3) | Install ArgoCD/Kargo | `helm version` |
| `kind` (or k3s/minikube) | The local cluster | `kind version` |
| `kargo` CLI (v1.3+) | Manage promotions | `kargo version` |
| `kubeseal` | Encrypt the GKE cluster token | `kubeseal --version` |

You also need:
- A **GCP project** with billing enabled.
- A **GitHub Personal Access Token (PAT)** with `repo` scope.
- Both GHCR images set to **public**: https://github.com/lakunzy7?tab=packages

---

## A-to-Z deployment

Each step below is a summary — follow the linked folder README for the details.

### Step 1 — Create the clusters → [`terraform/`](terraform/README.md)

```bash
# Local cluster (control plane home)
kind create cluster --name cloudopshub-local

# GKE cluster (second target) via Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set gcp_project
terraform init && terraform apply              # type 'yes'

# Wire kubectl to GKE (Terraform prints this exact command)
gcloud container clusters get-credentials cloud-cluster \
  --zone europe-west1-b --project YOUR_GCP_PROJECT_ID
cd ..

kubectl config get-contexts        # you should now have BOTH clusters
```

### Step 2 — Install ArgoCD & Kargo → [`helm/`](helm/README.md)

```bash
# ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -f helm/argocd/values.yaml -n argocd --create-namespace

# cert-manager (Kargo prerequisite) then Kargo
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
helm repo add kargo https://charts.kargo.io && helm repo update
helm install kargo kargo/kargo -f helm/kargo/values.yaml -n kargo --create-namespace

kubectl get pods -n argocd && kubectl get pods -n kargo
```

### Step 3 — Register the GKE cluster into ArgoCD → [`helm/`](helm/README.md) (Part C)

Install the Sealed Secrets controller, mint a ServiceAccount token in **GKE**,
fill the `helm/argocd/add-cluster.yaml` template, seal it, and apply the sealed
output to the **local** cluster:

```bash
kubectl apply -f helm/argocd/add-cluster-sealed.yaml
argocd cluster list      # expect in-cluster AND k8slab-second-cluster
```

### Step 4 — Open the Kargo CLI connection → [`helm/`](helm/README.md)

```bash
# Keep this port-forward open in a separate terminal
kubectl port-forward -n kargo svc/kargo-api 3100:443 --address 0.0.0.0

# Log in (default admin password from helm/kargo/values.yaml)
kargo login --admin https://localhost:3100 --insecure-skip-tls-verify
```

### Step 5 — Apply the Kargo pipeline → [`kargo/`](kargo/README.md)

```bash
kargo apply -f ./kargo/
kubectl get project,warehouse,stages,promotiontasks -n authenticwrite
```

### Step 6 — Give Kargo write access to Git → [`kargo/`](kargo/README.md)

```bash
kargo create repo-credentials github-creds \
  --project=authenticwrite \
  --git \
  --username=lakunzy7 \
  --repo-url=https://github.com/lakunzy7/multi-cluster-deployment.git \
  --password=YOUR_GITHUB_PAT

kubectl get secret github-creds -n authenticwrite --show-labels
```

> The kargo CLI needs **`=` flag syntax** and the **port-forward open**. See
> [Important Notes](#important-notes).

### Step 7 — Apply the ArgoCD apps → [`argocd/`](argocd/README.md)

```bash
kubectl apply -f argocd/appproj.yaml
kubectl apply -f argocd/appset.yaml
kubectl get applications -n argocd | grep authenticwrite
```

`OutOfSync` / `Missing` before the first promotion is **normal**.

### Step 8 — Confirm Kargo found the images → [`kargo/`](kargo/README.md)

```bash
kubectl get freight -n authenticwrite
# Empty? Your GHCR images probably aren't public. Then refresh:
kubectl annotate warehouse authenticwrite -n authenticwrite kargo.akuity.io/refresh=true
```

### Step 9 — Promote dev → staging → prod → [`kargo/`](kargo/README.md)

Use the **Kargo UI** (http://localhost:3100 → authenticwrite → click the target
icon on `dev` → pick Freight → confirm), then repeat for staging and prod. Watch:

```bash
kubectl get promotions -n authenticwrite -w
```

Each promotion writes a new image tag into [`env/<stage>/values.yaml`](env/README.md),
which ArgoCD then deploys to **both** clusters.

### Step 10 — Reach the running app → [`charts/`](charts/authenticwrite/README.md)

```bash
kubectl port-forward -n authenticwrite-dev svc/frontend 8080:80   --address 0.0.0.0
kubectl port-forward -n authenticwrite-dev svc/backend  5000:5000 --address 0.0.0.0
```

---

## The promotion pipeline (how it flows)

```
1. CI builds backend/frontend images → pushes to ghcr.io  (tag = git short SHA)
2. Kargo Warehouse detects the new tags → creates Freight
3. You promote Freight: dev → staging → prod
4. PromotionTask runs per stage:
     git-clone → yaml-update(backend) → yaml-update(frontend)
              → git-commit → git-push → argocd-update
5. Git now has the new tag in env/<stage>/values.yaml
6. ArgoCD syncs charts/authenticwrite (with that values file) to BOTH clusters
7. New pods running in authenticwrite-<stage> on local + GKE
```

### Stages

| Stage | Namespace | Replicas | Source of Freight | Approval |
|-------|-----------|----------|-------------------|----------|
| **dev** | authenticwrite-dev | 1 | Warehouse (direct) | Manual |
| **staging** | authenticwrite-staging | 2 | dev | Manual |
| **prod** | authenticwrite-prod | 3 | staging | Manual |

---

## Port Forwards & Firewall

All in-cluster services are `ClusterIP` (internal only). To reach them from
outside the VM, port-forward with `--address 0.0.0.0`, then open the matching GCP
firewall rule.

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
kubectl port-forward -n authenticwrite-dev svc/frontend 8080:80 --address 0.0.0.0
kubectl port-forward -n authenticwrite-dev svc/backend 5000:5000 --address 0.0.0.0
kubectl port-forward -n argocd svc/argocd-server 8081:80 --address 0.0.0.0
kubectl port-forward -n kargo svc/kargo-api 3100:443 --address 0.0.0.0
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093 --address 0.0.0.0
```

### Opening GCP Firewall Ports

```bash
gcloud compute firewall-rules create allow-<name> \
  --allow=tcp:<port> \
  --source-ranges=0.0.0.0/0 \
  --description="<purpose>"
```

> **Security note:** `--source-ranges=0.0.0.0/0` exposes the port to the entire
> internet — fine for short demos. For anything longer-lived, restrict to your
> own IP (`--source-ranges=YOUR_IP/32`), since ArgoCD/Kargo/Grafana login pages
> would otherwise be publicly reachable.

---

## Important Notes

### PromotionTask: No Inline Credentials
In Kargo v1.3+, `git-clone`/`git-push` steps do **not** accept an inline
`credentials` block — it fails with `Additional property credentials is not
allowed`. Register credentials at the project level with
`kargo create repo-credentials` (Step 6).

### kargo CLI Flag Syntax
Use `=` between flag and value: `--project=authenticwrite`, **not**
`--project authenticwrite`.

### Port-Forward Must Stay Open
The kargo CLI talks to the API over the port-forward. If you get `connection
refused`, restart `kubectl port-forward -n kargo svc/kargo-api 3100:443`.

### GHCR Images Must Be Public
The Warehouse can't discover images from private GHCR packages. Set both packages
to public at https://github.com/lakunzy7?tab=packages.

---

## Directory Structure

```
.
├── README.md                  # ← you are here (A-Z guide + reference)
├── terraform/                 # GKE + VPC infrastructure        → terraform/README.md
├── helm/                      # ArgoCD + Kargo install values    → helm/README.md
│   ├── argocd/                #   + add-cluster (Sealed Secret)
│   └── kargo/
├── argocd/                    # AppProject + ApplicationSet      → argocd/README.md
├── kargo/                     # Project/Warehouse/Stages/Task    → kargo/README.md
├── charts/authenticwrite/     # The app's Helm chart             → charts/authenticwrite/README.md
└── env/                       # Per-env overrides (dev/stg/prod) → env/README.md
```

---

## Useful Commands

```bash
# ArgoCD apps
kubectl get applications -n argocd | grep authenticwrite

# Kargo pipeline state
kubectl get stages,freight,promotions -n authenticwrite

# Pods per environment
kubectl get pods -n authenticwrite-dev
kubectl get pods -n authenticwrite-staging
kubectl get pods -n authenticwrite-prod

# Logs
kubectl logs -n authenticwrite-dev deployment/backend -f
kubectl logs -n authenticwrite-dev deployment/frontend -f
kubectl logs -n kargo deployment/kargo-controller -f
kubectl logs -n argocd deployment/argocd-application-controller -f

# Simulate a new release
kubectl annotate warehouse authenticwrite -n authenticwrite kargo.akuity.io/refresh=true
kubectl get freight -n authenticwrite -w
```

---

## Troubleshooting

| Symptom | Where | Fix |
|---------|-------|-----|
| `Additional property credentials is not allowed` | [kargo](kargo/README.md) | Remove `credentials` from git steps; use `kargo create repo-credentials`. |
| git-push: `could not read Username` | [kargo](kargo/README.md) | `github-creds` Secret missing/mislabelled — re-run Step 6; needs label `kargo.akuity.io/cred-type=git`. |
| kargo CLI `connection refused` | [helm](helm/README.md) | Port-forward to `kargo-api` isn't running. |
| kargo CLI `token expired` | [helm](helm/README.md) | `kargo login --admin https://localhost:3100 --insecure-skip-tls-verify`. |
| Warehouse shows no freight | [kargo](kargo/README.md) | Images not public, or tag doesn't match `^[0-9a-f]{8}$`. Make public + refresh. |
| Apps stuck `OutOfSync/Missing` | [argocd](argocd/README.md) | Normal before first promotion; or force-sync the app. |
| GKE cluster missing in ArgoCD | [helm](helm/README.md) | Sealed Secret not applied/decrypted — see Part C. |
| Kargo pods crashloop on install | [helm](helm/README.md) | cert-manager wasn't ready first — install it, wait, reinstall Kargo. |

---

## References

* Kargo: https://kargo.akuity.io
* ArgoCD: https://argo-cd.readthedocs.io
* Helm: https://helm.sh/docs
* Sealed Secrets: https://github.com/bitnami-labs/sealed-secrets
* GHCR Packages: https://github.com/lakunzy7?tab=packages

---

**Status:** Production Ready ✅
