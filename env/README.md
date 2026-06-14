# `env/` — Per-Environment Helm Overrides

This folder holds **one values file per environment**. Each file overrides the
chart defaults in `../charts/authenticwrite/values.yaml` for that stage.

```
env/
├── dev/values.yaml       # 1 replica  — smallest resources
├── staging/values.yaml   # 2 replicas — mid resources
└── prod/values.yaml      # 3 replicas — largest limits
```

These files are special for **two** reasons:

1. **ArgoCD** layers them onto the chart — the ApplicationSet discovers each
   folder under `env/*` and creates Applications that deploy with that file
   (see `../argocd/README.md`).
2. **Kargo** edits them — every promotion writes the new image tag into the
   target stage's file at `backend.tag` / `frontend.tag`
   (see `../kargo/README.md`).

> So this folder is the **meeting point** of the two tools: Kargo *writes* the
> tag here, ArgoCD *reads* the whole file to deploy.

---

## What each file overrides

Only the fields that differ from the chart defaults appear here — typically
`tag`, `replicas`, and `resources`. The `image` repository stays in the chart
defaults (it never changes per env).

### `dev/values.yaml`
```yaml
backend:  { tag: cfd86357, replicas: 1, resources: {...smallest...} }
frontend: { tag: cfd86357, replicas: 1, resources: {...smallest...} }
```
The `tag` values here (`cfd86357`) are **real promoted SHAs** — they were written
by Kargo on the last `dev` promotion. dev runs 1 replica to save resources.

### `staging/values.yaml`
```yaml
backend:  { tag: latest, replicas: 2, resources: {...mid...} }
frontend: { tag: latest, replicas: 2, resources: {...mid...} }
```
2 replicas. `tag: latest` means nothing has been promoted to staging yet — the
first promotion to staging will replace it with a real SHA.

### `prod/values.yaml`
```yaml
backend:  { tag: latest, replicas: 3, resources: {...highest limits...} }
frontend: { tag: latest, replicas: 3, resources: {...highest limits...} }
```
3 replicas and the highest CPU/memory limits, for production capacity.

---

## How a value flows from here to a running pod

```
env/dev/values.yaml  (backend.tag: cfd86357)
        │  read by
        ▼
ArgoCD renders charts/authenticwrite with this file
        │
        ▼
Deployment image = ghcr.io/.../backend:cfd86357
        │
        ▼
pods in authenticwrite-dev (on BOTH local + gke clusters)
```

And how Kargo *changes* it:

```
You promote Freight to "staging"
        │
        ▼
Kargo's PromotionTask edits env/staging/values.yaml:
   backend.tag  → <new sha>
   frontend.tag → <new sha>
        │ commits & pushes to Git
        ▼
ArgoCD sees the change → redeploys staging
```

---

## Editing by hand vs. letting Kargo do it

- **Replicas / resources** — edit these files by hand and commit; ArgoCD will
  apply the change on its next sync.
- **Image tags** — let **Kargo** manage these through promotion. If you edit a
  tag by hand, the next promotion will overwrite it anyway.

To preview what a file produces:

```bash
# From repo root
helm template authenticwrite charts/authenticwrite \
  -f env/staging/values.yaml \
  --namespace authenticwrite-staging
```

---

**Related:** `../charts/authenticwrite/README.md` (the chart these override) ·
`../kargo/README.md` (writes the tags here) ·
`../argocd/README.md` (reads these to deploy).
