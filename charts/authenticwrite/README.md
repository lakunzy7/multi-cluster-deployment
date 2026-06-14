# Helm Chart — `authenticwrite`

This is the **application** itself, packaged as a Helm chart. ArgoCD renders this
chart (layered with a per-environment values file) and deploys the result to
each cluster. The app is two services:

- **backend** — a Flask API on port `5000` (has a `/health` endpoint).
- **frontend** — a web UI on port `80` (has a `/health` endpoint).

```
charts/authenticwrite/
├── Chart.yaml              # Chart metadata (name, version)
├── values.yaml            # DEFAULT values (overridden per env — see ../../env/)
└── templates/
    ├── namespace.yaml      # Creates the release namespace
    ├── backend.yaml        # backend Deployment + Service
    ├── frontend.yaml       # frontend Deployment + Service
    └── _helpers.tpl        # Reusable label/name template snippets
```

> New to Helm charts? `templates/` holds Kubernetes YAML with `{{ ... }}`
> placeholders. `values.yaml` supplies the values that fill those placeholders.
> `helm template` (or ArgoCD) renders them into final manifests.

---

## 1. `Chart.yaml`

Basic metadata — chart `version: 0.1.0`, `appVersion: 1.0.0`. Bump the chart
version when you change the templates.

---

## 2. `values.yaml` — the defaults

```yaml
backend:
  image: ghcr.io/lakunzy7/authenticwrite/backend
  tag: latest          # ← overridden per-env, and bumped by Kargo
  replicas: 1
  resources: { requests: {memory: 2Gi, cpu: 500m}, limits: {memory: 3Gi, cpu: 1000m} }

frontend:
  image: ghcr.io/lakunzy7/authenticwrite/frontend
  tag: latest
  replicas: 1
  resources: { ... }

imagePullSecrets:
  - name: ghcr-pull-secret
```

These are **base defaults**. Each environment overrides `tag`, `replicas`, and
`resources` via its own file in `../../env/` (see `../../env/README.md`). The
`image` (repository) lives here because it never changes between environments —
only the **tag** does.

> `imagePullSecrets` references `ghcr-pull-secret`. If your GHCR images are
> **public** (as this project requires for Kargo), pods can pull without it and a
> missing secret is harmless. If you ever make images private, create that
> Secret in each `authenticwrite-*` namespace.

---

## 3. `templates/` — what gets deployed

### `namespace.yaml`
Creates the release namespace (`{{ .Release.Namespace }}` →
`authenticwrite-dev`, etc.). This is why the AppProject whitelists `Namespace`
as a cluster-scoped resource (see `../../argocd/README.md`).

### `backend.yaml`
A `Deployment` + `ClusterIP` `Service`:
- Image: `{{ .Values.backend.image }}:{{ .Values.backend.tag }}` — the tag is the
  value Kargo bumps on each promotion.
- `replicas: {{ .Values.backend.replicas }}` — 1/2/3 by environment.
- Liveness & readiness probes hit `/health` on port `5000`.
- Sets `FLASK_ENV=production`.
- Service exposes port `5000` (ClusterIP → reach via port-forward).

### `frontend.yaml`
Same shape:
- Image `{{ .Values.frontend.image }}:{{ .Values.frontend.tag }}`.
- Probes hit `/health` on port `80`.
- Injects the pod's namespace as env var `NAMESPACE` (via the downward API).
- Service exposes port `80`.

### `_helpers.tpl`
Defines reusable template functions for consistent **labels** and **names**
(`authenticwrite.labels`, `authenticwrite.selectorLabels`, etc.), following the
standard Helm convention. Both Deployments `include` these so every object gets
matching `app.kubernetes.io/*` labels and selectors.

---

## 4. Render it yourself (debugging)

You don't normally run Helm by hand — ArgoCD does. But to preview what ArgoCD
will apply for, say, dev:

```bash
# From the repo root
helm template authenticwrite charts/authenticwrite \
  -f env/dev/values.yaml \
  --namespace authenticwrite-dev
```

This prints the final Namespace + Deployments + Services with the dev overrides
applied (1 replica, dev image tag).

---

## 5. How this chart is consumed

```
ArgoCD Application (authenticwrite-dev-local)
   source.path: charts/authenticwrite        ← this chart
   helm.valueFiles: /env/dev/values.yaml      ← the override layer
        │
        ▼ render
   Namespace authenticwrite-dev
   Deployment/Service backend  (tag from env/dev/values.yaml)
   Deployment/Service frontend
        │
        ▼ applied to
   the target cluster (local AND gke)
```

The image **tag** in the rendered output is whatever Kargo last wrote into
`env/<stage>/values.yaml`. That's the link between the promotion pipeline and the
running pods.

---

## 6. Reach the running app

Services are `ClusterIP` (internal). Port-forward to reach them (see the root
`README.md` port/firewall table):

```bash
kubectl port-forward -n authenticwrite-dev svc/frontend 8080:80   --address 0.0.0.0
kubectl port-forward -n authenticwrite-dev svc/backend  5000:5000 --address 0.0.0.0
```

---

**Related:** `../../env/README.md` (the override files) ·
`../../argocd/README.md` (what renders this chart) ·
`../../kargo/README.md` (what bumps the image tag).
