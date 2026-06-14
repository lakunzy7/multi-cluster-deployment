# Helm — Installing ArgoCD & Kargo, and Adding the 2nd Cluster

This folder holds the **Helm values** used to install the two control-plane
tools, plus the manifests that **register the GKE cluster into ArgoCD** so
ArgoCD can deploy to both clusters.

Everything here runs against your **local cluster** (the one ArgoCD/Kargo live in).

```
helm/
├── argocd/
│   ├── values.yaml             # Helm values for the ArgoCD install
│   ├── add-cluster.yaml        # TEMPLATE secret to register the GKE cluster (no real secrets)
│   └── add-cluster-sealed.yaml # The ENCRYPTED version of that secret (safe to commit)
└── kargo/
    └── values.yaml             # Helm values for the Kargo install
```

> New to Helm? Helm is a package manager for Kubernetes. A *chart* is a package;
> a *values file* customizes that package. `helm install <name> <chart> -f values.yaml`
> renders the chart's templates with your values and applies them to the cluster.

---

## Part A — Install ArgoCD

ArgoCD is the **GitOps engine**: it watches this Git repo and makes the cluster
match what's in Git.

```bash
# 1. Add the Argo Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Install ArgoCD into its own namespace, using our values
helm install argocd argo/argo-cd \
  -f helm/argocd/values.yaml \
  -n argocd --create-namespace

# 3. Wait for it to come up
kubectl get pods -n argocd -w
```

### What `argocd/values.yaml` configures

- `server.service.type: ClusterIP` — internal only; you reach the UI via
  port-forward (see the root `README.md` port table). Switch to `LoadBalancer`
  for a real cloud setup.
- `configs.secret.argocdServerAdminPassword` — a **bcrypt hash** of the admin
  password. **Change this** before any real use.
- `applicationSet.enabled: true` — required, because this project uses an
  ApplicationSet (see `../argocd/README.md`).
- Single replicas for controller/repo-server/redis/dex — fine for a lab.

### Get the admin password & log in

If you did **not** set a custom password hash, ArgoCD generates one:

```bash
# Auto-generated initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Port-forward the UI (keep open in a separate terminal)
kubectl port-forward -n argocd svc/argocd-server 8081:80 --address 0.0.0.0
# UI: https://localhost:8081  (user: admin)
```

---

## Part B — Install Kargo

Kargo handles **image promotion** (`dev → staging → prod`). It needs cert-manager
present first (its CRDs/webhooks rely on TLS), then the Kargo chart.

```bash
# 1. cert-manager (Kargo prerequisite)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true

# 2. Kargo
helm repo add kargo https://charts.kargo.io
helm repo update
helm install kargo kargo/kargo \
  -f helm/kargo/values.yaml \
  -n kargo --create-namespace

# 3. Wait for it to come up
kubectl get pods -n kargo -w
```

### What `kargo/values.yaml` configures

- `image.tag: v1.10.5` — pins the Kargo version (server + CLI should match).
- `api.adminAccount` — enables the admin login; holds the **password hash** and
  **token signing key**. Change both for real use.
- `api.service.type: ClusterIP` — reach the API/UI via port-forward on `3100`.
- `controller.gitClient` — the name/email Kargo uses for the commits it makes
  when it bumps image tags, and `pushIntegrationPolicy: AlwaysRebase` so pushes
  don't fail on a moving branch.
- `garbageCollector` — auto-cleans old Promotion objects.

### Log into the Kargo CLI

```bash
# Port-forward the Kargo API (keep open in a separate terminal)
kubectl port-forward -n kargo svc/kargo-api 3100:443 --address 0.0.0.0

# Log in (matches the admin account in values.yaml)
kargo login --admin https://localhost:3100 --insecure-skip-tls-verify
```

> The kargo CLI **requires** this port-forward to be open and uses `=` flag
> syntax (`--project=x`, not `--project x`). See the root `README.md` for the
> full list of these gotchas.

---

## Part C — Add the GKE cluster to ArgoCD (multi-cluster)

ArgoCD runs in the **local** cluster. It already knows about that one as the
built-in `in-cluster`. To let it *also* deploy to **GKE**, you register the GKE
cluster as an ArgoCD "cluster Secret" named **`k8slab-second-cluster`** — the
same name the ApplicationSet uses (`../argocd/appset.yaml`).

A cluster Secret needs three things from the **GKE** cluster:
1. its **API server URL**,
2. a **bearer token** for a ServiceAccount ArgoCD can use,
3. the cluster's **CA certificate** (base64).

Because that token is a real credential, it is **not** committed in plaintext —
it's encrypted with **Sealed Secrets** and committed as `add-cluster-sealed.yaml`.

### The two files

| File | Contains secrets? | Commit it? |
|------|-------------------|-----------|
| `add-cluster.yaml` | No — it's a template with `REPLACE_WITH_...` placeholders | Yes (it's harmless) |
| `add-cluster-sealed.yaml` | Yes, but **encrypted** | Yes (only the controller can decrypt it) |

### Step 1 — Install the Sealed Secrets controller (local cluster, once)

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  -n sealed-secrets --create-namespace
# install the kubeseal CLI too (matches the controller version)
```

### Step 2 — Create a ServiceAccount + token in the GKE cluster

Point kubectl at GKE (`kubectl config use-context <gke-context>`), then create
a ServiceAccount with cluster-admin and mint a token:

```bash
kubectl create serviceaccount argocd-manager -n kube-system
kubectl create clusterrolebinding argocd-manager \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager

# Bearer token (Kubernetes 1.24+)
kubectl create token argocd-manager -n kube-system --duration=8760h
```

Gather the three values:

```bash
# Server URL
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# CA data (already base64 in kubeconfig)
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
```

### Step 3 — Fill in the template

Copy the three values into a **filled-in copy** of `add-cluster.yaml`
(`server`, `bearerToken`, `caData`). Do **not** commit this filled-in file.

### Step 4 — Seal it (encrypt)

Point kubectl back at the **local** cluster (where the Sealed Secrets controller
lives), then:

```bash
kubeseal \
  --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  --context kind-cloudopshub-local \
  --format yaml \
  < helm/argocd/add-cluster.yaml \
  > helm/argocd/add-cluster-sealed.yaml
```

### Step 5 — Apply the sealed secret to the local cluster

```bash
kubectl --context=kind-cloudopshub-local apply -f helm/argocd/add-cluster-sealed.yaml
```

The Sealed Secrets controller decrypts it into a normal `Secret` labelled
`argocd.argoproj.io/secret-type: cluster`. ArgoCD picks it up automatically.

### Step 6 — Verify ArgoCD sees both clusters

```bash
# In the ArgoCD UI: Settings → Clusters, OR via CLI:
argocd cluster list
# Expect: in-cluster (local) AND k8slab-second-cluster (GKE)
```

---

## How it all fits together

```
            ┌──────────────────────── LOCAL cluster ────────────────────────┐
            │  ArgoCD  ──────────────┐                                       │
 Git repo ──┤  Kargo                 │ deploys to "in-cluster" (itself)      │
   (this)   │  Sealed Secrets ctrl   └─ deploys to "k8slab-second-cluster" ──┼──► GKE cluster
            └────────────────────────────────────────────────────────────────┘
```

ArgoCD = sync (Git → clusters). Kargo = decide *which image tag* and write it
back to Git. Details: `../argocd/README.md` and `../kargo/README.md`.

---

## Common issues

| Symptom | Fix |
|---------|-----|
| Kargo pods crashloop right after install | cert-manager wasn't ready first. Install cert-manager, wait, reinstall Kargo. |
| `kubeseal` can't find the controller | Check `--controller-namespace`/`--controller-name` match your install (`sealed-secrets`). |
| GKE cluster missing in ArgoCD | The sealed secret didn't decrypt — check the Sealed Secrets controller logs; confirm the `argocd.argoproj.io/secret-type: cluster` label exists on the resulting Secret. |
| Token expired after a year | Re-run `kubectl create token ...`, re-seal, re-apply. |
