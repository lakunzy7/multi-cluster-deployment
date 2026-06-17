# Helm — Installing ArgoCD & Kargo, and Adding the 2nd Cluster

This folder holds the **Helm values** used to install the two control-plane
tools, plus the manifests that **register cluster 2 into ArgoCD** so
ArgoCD can deploy to both clusters.

Everything here runs against **cluster 1** (the one ArgoCD/Kargo live in).

```
helm/
├── argocd/
│   ├── values.yaml             # Helm values for the ArgoCD install
│   ├── add-cluster.yaml        # TEMPLATE secret to register cluster 2 (no real secrets)
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

# Install Kargo CLI v1.10.5 (matches your values.yaml)
curl -L https://github.com/akuity/kargo/releases/download/v1.10.5/kargo-linux-amd64 \
  -o /tmp/kargo && \
  chmod +x /tmp/kargo && \
  sudo mv /tmp/kargo /usr/local/bin/kargo

# 2. Kargo
helm repo add kargo https://charts.kargo.io
helm repo update
helm install kargo kargo/kargo \
  -f helm/kargo/values.yaml \
  -n kargo --create-namespace

# 2.1 Kargo (via OCI registry - charts.kargo.io is deprecated)
helm install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version 1.10.5 \
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

## Part C — Add cluster 2 to ArgoCD (multi-cluster)

ArgoCD runs in **cluster 1**. It already knows about that one as the
built-in `in-cluster`. To let it *also* deploy to **cluster 2**, you register
cluster 2 as an ArgoCD "cluster Secret" named **`k8slab-second-cluster`** — the
same name the ApplicationSet uses (`../argocd/appset.yaml`).

A cluster Secret needs three things from **cluster 2**:
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

### Step 1 — Install the Sealed Secrets controller (cluster 1, once)

```bash
helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm repo update
helm install sealed-secrets sealed-secrets/sealed-secrets \
  -n sealed-secrets --create-namespace

# Confirm the controller is up and note its version
kubectl get pods -n sealed-secrets
kubectl get deployment sealed-secrets -n sealed-secrets \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

#### Install the `kubeseal` CLI (match the controller version)

`kubeseal` encrypts secrets against the controller's public key (used in Step 4).
Pin the same version as the controller you just installed (e.g. `0.37.0`):

```bash
KUBESEAL_VERSION=0.37.0
curl -OL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"
tar -xzf "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
rm -f kubeseal "kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz"

kubeseal --version   # should print: kubeseal version: 0.37.0
```

> On macOS you can instead `brew install kubeseal`. For other releases see
> https://github.com/bitnami-labs/sealed-secrets/releases

### Step 2 — Create a ServiceAccount + token in cluster 2

Point kubectl at cluster 2 (`kubectl config use-context <cluster-2-context>`),
then create a ServiceAccount with cluster-admin and mint a token:

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

Point kubectl back at **cluster 1** (where the Sealed Secrets controller
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

### Step 5 — Apply the sealed secret to cluster 1

```bash
kubectl --context=kind-cloudopshub-local apply -f helm/argocd/add-cluster-sealed.yaml
```

The Sealed Secrets controller decrypts it into a normal `Secret` labelled
`argocd.argoproj.io/secret-type: cluster`. ArgoCD picks it up automatically.

### Step 6 — Verify ArgoCD sees both clusters

```bash
# In the ArgoCD UI: Settings → Clusters, OR via CLI:
argocd cluster list
# Expect: in-cluster (cluster 1) AND k8slab-second-cluster (cluster 2)
```

---

## How it all fits together

```
            ┌──────────────────────── CLUSTER 1 ────────────────────────────┐
            │  ArgoCD  ──────────────┐                                       │
 Git repo ──┤  Kargo                 │ deploys to "in-cluster" (itself)      │
   (this)   │  Sealed Secrets ctrl   └─ deploys to "k8slab-second-cluster" ──┼──► CLUSTER 2
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
| Cluster 2 missing in ArgoCD | The sealed secret didn't decrypt — check the Sealed Secrets controller logs; confirm the `argocd.argoproj.io/secret-type: cluster` label exists on the resulting Secret. |
| Token expired after a year | Re-run `kubectl create token ...`, re-seal, re-apply. |
