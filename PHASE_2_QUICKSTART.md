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

> **⚠️ Reality check (June 2026):** Kargo `v0.6.0` on Kubernetes `v1.36.1` will *not* install with a bare `helm install kargo/kargo`. You **must** pin the chart version, pre-install cert-manager, raise host inotify limits, inject a bcrypt admin password, and disable Argo Rollouts integration. The clean, repeatable recipe is below — see [Lessons Learned](#lessons-learned-kargo-installation-on-a-modern-cluster) at the bottom for the why.

```bash
kubectl config use-context kind-cloudopshub-local

# --- Host-level prep (one-time per VM) ---
# Kargo controller watches a lot of files; default inotify limits cause it to crash.
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512

# --- Cluster-level prep ---
# cert-manager is required for Kargo's webhook certificates.
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml
kubectl wait --for=condition=Available --timeout=180s \
  deployment/cert-manager deployment/cert-manager-webhook deployment/cert-manager-cainjector \
  -n cert-manager

# --- Namespace ---
kubectl create namespace kargo

# --- Install Kargo (pinned, hardened) ---
# Values are committed at kargo/values.yaml — see "Lessons Learned" for what each key does.
helm upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version 0.6.0 \
  --namespace kargo \
  -f kargo/values.yaml \
  --wait

# Deploy project
kubectl apply -f kargo/kargo-project.yaml -n kargo

# Verify all four Kargo pods are 1/1 Running (no CrashLoopBackOff)
kubectl get pods -n kargo

# Port-forward
kubectl port-forward -n kargo svc/kargo-api 8080:8080
# Visit: http://localhost:8080  (user: admin / password: admin)
```

**`kargo/values.yaml`** (committed in the repo):

```yaml
api:
  adminAccount:
    # bcrypt("admin") — chart 0.6.0 refuses to start without a hash.
    passwordHash: $2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm
    tokenSigningKey: cloudopshub-local-dev-key
  rollouts:
    integrationEnabled: false   # No Argo Rollouts CRDs in this cluster.
controller:
  rollouts:
    integrationEnabled: false   # Same — otherwise controller logs flood with
                                # "no kind is registered for v1alpha1.AnalysisRun".
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

### Kargo controller stuck in CrashLoopBackOff with `"the server has asked for the client to provide credentials"`?

The `kargo-controller` ServiceAccount is stuck in `Terminating` because of a
leftover `kargo.akuity.io/finalizer` from a prior install. The pod mounts a
projected token for an SA the API server now treats as gone — every API call
the controller makes is rejected at scheme-discovery time.

```bash
# Confirm: deletionTimestamp set + finalizer present
kubectl get sa -n kargo kargo-controller -o yaml | grep -E "deletionTimestamp|finalizers" -A1

# Strip the finalizer so the SA fully deletes
kubectl patch sa kargo-controller -n kargo --type=merge \
  -p '{"metadata":{"finalizers":[]}}'

# Re-apply Helm to recreate a clean SA with a fresh token
helm upgrade kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version 0.6.0 -n kargo -f kargo/values.yaml

# Restart the controller pod
kubectl delete pod -n kargo -l app.kubernetes.io/component=controller
```

### Kargo controller logs flooded with `"no kind is registered for v1alpha1.AnalysisRun"`?
Argo Rollouts integration is enabled but its CRDs aren't installed. Make sure
your values use the chart-0.6.0 keys — `controller.rollouts.integrationEnabled`
and `api.rollouts.integrationEnabled` — **not** the legacy
`kargoController.argoRolloutsIntegration` (which 0.6.0 silently ignores).
Confirm with:
```bash
kubectl get cm -n kargo kargo-controller -o jsonpath='{.data.ROLLOUTS_INTEGRATION_ENABLED}'
# Should print: false
```

### Namespace stuck in `Terminating`?
```bash
kubectl get ns <name> -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw "/api/v1/namespaces/<name>/finalize" -f -
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

---

## Lessons Learned: Kargo Installation on a Modern Cluster

The original copy-paste recipe (`helm install kargo kargo/kargo --wait`) assumes
defaults that no longer hold on a Kubernetes `v1.36.1` cluster running chart
`kargo-0.6.0`. This section documents the five interventions that turn the
naive install into a deterministic one, and **why each one is required**.

### The Strategy: "Clean Slate" Orchestration

Treat the Kargo install not as one command but as a five-stage orchestration.
Skip any stage and the install fails — usually silently, sometimes loudly.

#### Step 1 — Cluster preparation (host kernel tuning)
The Kargo controller watches a large number of CRD informers and Git working
trees. On default Ubuntu/Debian VMs the inotify limits are too low and the
controller dies with `too many open files` or stalls during informer startup.

```bash
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512
```

Persist by writing the same lines to `/etc/sysctl.d/99-kargo.conf`.

#### Step 2 — Dependency resolution (cert-manager)
Kargo's admission webhook is served over TLS by certificates issued by
`cert-manager`. Without it, the Helm install completes but the webhook
endpoint fails its readiness gate and every subsequent `kubectl apply` of a
Kargo CR (`Project`, `Stage`, `Warehouse`) is rejected with a TLS handshake error.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.3/cert-manager.yaml
```

#### Step 3 — Version pinning & security injection
Chart `0.6.0` **mandates** a bcrypt password hash and signing key for the API
server. Omitting them aborts the Helm install with
`api.adminAccount.passwordHash is required`. We pin both the chart version and
the credentials in `kargo/values.yaml` so the recipe stays reproducible:

```yaml
api:
  adminAccount:
    passwordHash: $2a$10$Zrhhie4vLz5ygtVSaif6o.qN36jgs6vjtMBdM6yrU1FOeiAAMMxOm  # bcrypt("admin")
    tokenSigningKey: cloudopshub-local-dev-key
```

#### Step 4 — Integration decoupling (Argo Rollouts off)
Out of the box, the controller and API server both try to watch
`AnalysisRun` / `AnalysisTemplate` CRDs from Argo Rollouts. If those CRDs
aren't installed, the controller logs an endless stream of
`no kind is registered for the type v1alpha1.AnalysisRun` errors.

**Important:** the chart-0.6.0 keys are `controller.rollouts.integrationEnabled`
and `api.rollouts.integrationEnabled`. The older flag
`kargoController.argoRolloutsIntegration` (which appears in some blog posts
and earlier drafts of this guide) is **silently ignored** by 0.6.0 — the
ConfigMap will still report `ROLLOUTS_INTEGRATION_ENABLED=true`.

#### Step 5 — Finalizer rescue (when a previous install is wedged)
If a prior `helm uninstall` or namespace delete was interrupted, the
`kargo-controller` ServiceAccount can end up stuck in `Terminating` with the
`kargo.akuity.io/finalizer` still attached. The new pod then mounts a
projected token for an SA the API server considers gone, and the controller
crashes at startup with:

```
error initializing Kargo controller manager: failed to determine if *v1.Secret
is namespaced: failed to get restmapping: failed to get server groups:
the server has asked for the client to provide credentials
```

The fix is to remove the finalizer directly, then let Helm reconcile a fresh
SA (with a fresh projected token):

```bash
kubectl patch sa kargo-controller -n kargo --type=merge \
  -p '{"metadata":{"finalizers":[]}}'
helm upgrade kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version 0.6.0 -n kargo -f kargo/values.yaml
kubectl delete pod -n kargo -l app.kubernetes.io/component=controller
```

### Delta vs. the original quick-start

| Concern | Original expectation | Actual June-2026 reality |
| --- | --- | --- |
| Chart versioning | Implicit (`kargo/kargo` latest) | **Pinned** to `oci://ghcr.io/akuity/kargo-charts/kargo` `v0.6.0` |
| Admin password | None | **Mandatory** bcrypt `passwordHash` + `tokenSigningKey` |
| System tuning | Not mentioned | **Required**: raise `fs.inotify.max_user_watches` + `max_user_instances` |
| Webhook TLS | Assumed available | **Required**: install `cert-manager` first |
| Argo Rollouts | "Just works" | Must **explicitly disable** via the correct 0.6.0 keys |
| Stuck SA / namespace recovery | Not documented | **Manual finalizer strip** required when uninstall left wreckage |

### Why these matter

Strictly following the legacy recipe fails at every stage: the controller
panics on inotify limits, the chart aborts on missing credentials, the webhook
never gets a certificate, the controller crashes looking for Rollouts CRDs,
and any uninstall leaves a wedged SA that breaks the next install. The
defensive configuration above wraps the original logic so that it runs
deterministically on a high-version (`v1.36.1`) cluster.

After Step 5, the four Kargo pods (`kargo-api`, `kargo-controller`,
`kargo-management-controller`, `kargo-webhooks-server`) should all report
`1/1 Running`. You're ready to move on to Step 6 (deploy ApplicationSets).
