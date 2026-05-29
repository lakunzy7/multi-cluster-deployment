# How to add a cluster to ArgoCD (declarative)

This guide walks through registering an external Kubernetes cluster with the ArgoCD instance running on **Kind** (`kind-cloudopshub-local`), without using `argocd cluster add`. Everything is YAML you commit (minus the rendered token).

The example throughout is the **GKE `cloud-cluster`** we provisioned in `terraform/`, but the same recipe works for any cluster ArgoCD can reach over the network.

---

## Mental model

ArgoCD discovers external clusters by reading **Secrets** in the `argocd` namespace that carry the label `argocd.argoproj.io/secret-type: cluster`. Each Secret holds:

- The target cluster's API URL (`server`)
- A credential — bearer token, client cert, or exec plugin (`config.bearerToken` etc.)
- The target cluster's CA cert (`config.tlsClientConfig.caData`)

`argocd cluster add` is just a CLI that creates the SA + RoleBinding on the target, fetches the token, then writes that Secret for you. Going declarative means you do both halves explicitly — and commit them to git.

---

## Recipe (4 steps)

### 1. Create the SA on the **target** cluster

This gives ArgoCD an identity inside the cluster it wants to manage.

```yaml
# gke-argocd-sa.yaml — apply with the TARGET cluster's context
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-role-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin      # tighten for production; cluster-admin is convenient for labs
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
---
# Long-lived token. k8s >= 1.24 no longer auto-creates one for a ServiceAccount,
# so we ask for it explicitly via this annotated Secret.
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
```

Apply on the target:

```bash
kubectl --context <TARGET-CONTEXT> apply -f gke-argocd-sa.yaml
```

Wait a couple of seconds — the token controller populates `data.token` and `data.ca.crt` on the Secret asynchronously.

---

### 2. Extract the token, CA cert, and endpoint

```bash
TARGET_CTX=gke_expandox-cloudehub_europe-west1-b_cloud-cluster

TOKEN=$(kubectl --context "$TARGET_CTX" -n kube-system \
  get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 -d)

CA=$(kubectl --context "$TARGET_CTX" -n kube-system \
  get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')   # already base64

ENDPOINT=$(terraform -chdir=terraform output -raw cloud_cluster_endpoint)
# or: kubectl --context "$TARGET_CTX" config view --minify -o jsonpath='{.clusters[0].cluster.server}'

echo "endpoint=$ENDPOINT  token=${TOKEN:0:10}…  ca=${#CA} chars"
```

---

### 3. Render the cluster Secret for **ArgoCD's** cluster

```yaml
# gke-cluster-secret.yaml — apply with the ARGOCD cluster's context (Kind)
apiVersion: v1
kind: Secret
metadata:
  name: gke-cloud-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    env: cloud                 # optional — useful for ApplicationSet generators
    region: europe-west1
type: Opaque
stringData:
  name: gke-cloud-cluster      # the human-readable name shown in `argocd cluster list`
  server: https://${ENDPOINT}  # full URL, scheme included
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA}"
      }
    }
```

One-liner that substitutes the variables and writes the file:

```bash
cat > gke-cluster-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gke-cloud-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    env: cloud
    region: europe-west1
type: Opaque
stringData:
  name: gke-cloud-cluster
  server: https://${ENDPOINT}
  config: |
    {
      "bearerToken": "${TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA}"
      }
    }
EOF
```

> ⚠️ This file now contains a live bearer token. **Add it to `.gitignore`** before staging.

---

### 4. Apply on the ArgoCD cluster

```bash
kubectl --context kind-cloudopshub-local apply -f gke-cluster-secret.yaml
```

Verify:

```bash
argocd cluster list
# SERVER                          NAME               LABELS
# https://34.156.236.159          gke-cloud-cluster  env=cloud,region=europe-west1
# https://kubernetes.default.svc  in-cluster
```

Status will be `Unknown / not being monitored` until you point an `Application` at the cluster — that's normal. ArgoCD doesn't probe clusters with zero apps.

---

## Verifying the connection works

The simplest way: create a tiny Application that targets the new cluster and watch it sync.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-smoke-test
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    name: gke-cloud-cluster   # match the 'name' field in the cluster Secret
    namespace: smoke-test
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [ "CreateNamespace=true" ]
```

If ArgoCD reports `Synced / Healthy`, the registration works end-to-end. Delete the test app + namespace afterwards.

---

## What goes in git vs. what doesn't

| File | Commit? | Why |
|---|---|---|
| `gke-argocd-sa.yaml` | ✅ | No secrets; just RBAC. Anyone can apply it without leaking anything. |
| `gke-cluster-secret.yaml` (rendered) | ❌ | Contains a live cluster-admin bearer token. |
| `gke-cluster-secret.yaml.tmpl` (placeholders) | optional | If you want a checked-in template, keep the placeholders (`${TOKEN}` etc.) and have a script render it locally. |

Add to `.gitignore`:

```
eshop-config/argocd-clusters/gke-cluster-secret.yaml
```

---

## Refreshing after the GKE endpoint or token rotates

The bearer token is long-lived (until the SA or Secret is deleted), but the GKE public endpoint changes if you `terraform destroy && terraform apply`. Run steps **2 → 3 → 4** again; the Secret is overwritten in place and ArgoCD picks up the new endpoint within a few seconds.

---

## More-robust alternatives (for later)

| Approach | Pros | Cons |
|---|---|---|
| **Connect Gateway** (`connectgateway.googleapis.com/...`) | Stable URL across cluster recreates | Needs GCP SA key OR Workload Identity Federation; blocked here by `iam.disableServiceAccountKeyCreation` org policy |
| **Workload Identity Federation** | No long-lived secrets | Setup is involved; Kind needs an OIDC issuer reachable from GCP |
| **GKE DNS endpoint** (`gke-*.gke.goog`) | Stable hostname, no Fleet API | Needs GKE >= 1.31 and `--enable-dns-access` on the cluster |

For a lab, the bearer-token + public-IP recipe above is the lowest-friction option that still goes through git.
