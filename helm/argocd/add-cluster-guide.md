# How to Add a Second Cluster to ArgoCD (Beginner Guide)

This guide shows you how to connect a second Kubernetes cluster (a GKE cluster)
to your existing ArgoCD, so ArgoCD can deploy apps to it.

---

## What you have

- **ArgoCD cluster** → `kind-cloudopshub-local` (where ArgoCD is installed)
- **Second cluster** → your GKE cluster (the one you want to add)

ArgoCD needs a **Secret** that tells it:
1. The second cluster's **address** (server URL)
2. A **token** to log in
3. The **CA certificate** to trust it

That Secret is the file below.

---

## Where the file is

```
helm/argocd/add-cluster.yaml
```

Full path on this machine:

```
/home/lakunzy/multi-cluster-deployment/helm/argocd/add-cluster.yaml
```

---

## Steps

### Step 1 — Create a user (ServiceAccount) on the GKE cluster

ArgoCD logs in as this user. Run these against the GKE cluster:

```bash
# Point these commands at the GKE cluster
GKE_CTX="gke_expandox-cloudehub_europe-west1-b_cloud-cluster"

# Create the user
kubectl --context="$GKE_CTX" create serviceaccount argocd-manager -n kube-system

# Give it full admin rights so ArgoCD can deploy anything
kubectl --context="$GKE_CTX" create clusterrolebinding argocd-manager-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kube-system:argocd-manager
```

### Step 2 — Create a login token for that user

```bash
cat <<'EOF' | kubectl --context="$GKE_CTX" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
EOF
```

### Step 3 — Collect the 3 values you need

```bash
# 1. Server URL (the cluster's address)
kubectl config view --minify --context="$GKE_CTX" \
  -o jsonpath='{.clusters[0].cluster.server}'

# 2. The login token
kubectl --context="$GKE_CTX" get secret argocd-manager-token -n kube-system \
  -o jsonpath='{.data.token}' | base64 -d

# 3. The CA certificate
kubectl config view --minify --context="$GKE_CTX" --flatten \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'
```

### Step 4 — Fill in `add-cluster.yaml`

Paste the 3 values into the file. It should look like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: k8slab-second-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster   # <-- tells ArgoCD "this is a cluster"
type: Opaque
stringData:
  name: k8slab-second-cluster                  # name shown in the ArgoCD UI
  server: https://34.156.236.159               # value #1 from Step 3
  config: |
    {
      "bearerToken": "PASTE_TOKEN_HERE",       # value #2 from Step 3
      "tlsClientConfig": {
        "insecure": false,
        "caData": "PASTE_CA_HERE"              # value #3 from Step 3
      }
    }
```

### Step 5 — Seal the secret (so it's safe for git)

`add-cluster.yaml` now holds a **real token**, so we never commit or apply it directly.
Instead we encrypt it into a **SealedSecret** that only the in-cluster controller can open.

> One-time setup of the Sealed Secrets controller is in `helm/sealed-secrets/values.yaml`.

```bash
kubeseal --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  --context kind-cloudopshub-local \
  --format yaml \
  < helm/argocd/add-cluster.yaml \
  > helm/argocd/add-cluster-sealed.yaml
```

`add-cluster-sealed.yaml` is **encrypted** — safe to commit to git.

### Step 6 — Apply the SEALED file to the ArgoCD cluster

Runs against the cluster where **ArgoCD lives**, not GKE. The controller
automatically decrypts it into the real `Secret` ArgoCD reads:

```bash
kubectl --context=kind-cloudopshub-local apply -f helm/argocd/add-cluster-sealed.yaml

# Confirm the controller unsealed it:
kubectl --context=kind-cloudopshub-local -n argocd get secret k8slab-second-cluster
```

### Step 7 — Check it worked

In the ArgoCD UI: **Settings → Clusters** → you should see
`k8slab-second-cluster` with status **Successful**.

Or with the ArgoCD CLI:

```bash
argocd cluster list
```

---

## What's safe to commit

| File | Commit? | Why |
|------|---------|-----|
| `add-cluster.yaml` | ✅ (placeholders only) | It's a template — fill in real values locally, then seal |
| `add-cluster-sealed.yaml` | ✅ | Encrypted; only the cluster controller can decrypt it |
| `sealed-secrets-master.yaml` | ❌ **NEVER** | The master private key. Gitignored. **Vault this** (e.g. 1Password / GCP Secret Manager) — if the cluster dies, it's the only way to recover sealed secrets |

## Re-sealing later

If the token rotates, re-fill `add-cluster.yaml` with fresh values (Step 3),
re-run Step 5 and Step 6. The old SealedSecret is simply overwritten.
