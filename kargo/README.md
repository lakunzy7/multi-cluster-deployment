# Kargo — Image Promotion Pipeline

Kargo answers one question: **"which image tag should each environment run, and
how does it move from dev → staging → prod?"** It watches your container
registry for new images, and when you promote, it **writes the new tag into Git**
and asks ArgoCD to deploy it.

```
kargo/
├── project.yaml         # Kargo Project (creates the authenticwrite namespace)
├── warehouse.yaml       # Watches GHCR for new backend/frontend images
├── stages.yaml          # dev → staging → prod stage definitions
└── promotiontask.yaml   # The reusable "promote" recipe (clone→edit→commit→push→sync)
```

> **Mental model.** ArgoCD = *sync* (Git → cluster). Kargo = *promotion* (choose
> the tag, advance it through stages, commit it to Git). Kargo never talks to the
> app directly — it changes Git and lets ArgoCD do the deploy.

---

## Key concepts (Kargo vocabulary)

| Term | Meaning |
|------|---------|
| **Project** | A namespace that groups all Kargo resources for one app. |
| **Warehouse** | Watches a registry (here GHCR) and produces **Freight** when it finds new images. |
| **Freight** | An immutable snapshot of image versions ("backend `abc123` + frontend `abc123`"). This is the *thing you promote*. |
| **Stage** | An environment (dev/staging/prod). A Stage receives Freight and runs a promotion. |
| **Promotion** | One run of moving a piece of Freight into a Stage. |
| **PromotionTask** | A reusable, parameterized recipe of steps that every Stage's promotion runs. |

---

## 1. `project.yaml` — the Project

```yaml
kind: Project
metadata:
  name: authenticwrite
```

Creating a Kargo Project also creates a Kubernetes **namespace** called
`authenticwrite` where the Warehouse, Stages, Freight, and Promotions live.
(Not to be confused with the app's runtime namespaces `authenticwrite-dev/...`.)

---

## 2. `warehouse.yaml` — watching the registry

```yaml
kind: Warehouse
spec:
  subscriptions:
  - image:
      repoURL: ghcr.io/lakunzy7/authenticwrite/backend
      imageSelectionStrategy: NewestBuild
      allowTags: '^[0-9a-f]{8}$'    # only 8-char hex tags (git short SHAs)
      discoveryLimit: 10
  - image:
      repoURL: ghcr.io/lakunzy7/authenticwrite/frontend
      ...
```

- Subscribes to the **backend** and **frontend** images on GHCR.
- `allowTags: '^[0-9a-f]{8}$'` only matches **8-character hex** tags (i.e. git
  short commit SHAs like `cfd86357`). It ignores `latest`, version tags, etc.
- `NewestBuild` picks the most recently *pushed* image.
- Each time both images have a new matching tag, the Warehouse emits **Freight**.

> ⚠️ **GHCR images must be PUBLIC.** A Warehouse can't list tags on a private
> package without pull credentials. Make both packages public, or the Warehouse
> produces no Freight.

Force a re-scan anytime:

```bash
kubectl annotate warehouse authenticwrite -n authenticwrite kargo.akuity.io/refresh=true
kubectl get freight -n authenticwrite        # see what it found
```

---

## 3. `stages.yaml` — the dev → staging → prod chain

Three Stages, each pulling Freight from a **different source** — that's what
enforces the order:

```yaml
# dev: takes Freight straight from the Warehouse
sources:
  direct: true

# staging: can only take Freight that already passed through dev
sources:
  stages: [dev]

# prod: can only take Freight that already passed through staging
sources:
  stages: [staging]
```

So Freight must flow **dev → staging → prod**; you can't promote something to
prod that never went through staging. Each Stage runs the **same** promotion
recipe:

```yaml
promotionTemplate:
  spec:
    steps:
    - task:
        name: promote-authenticwrite   # ← the PromotionTask below
```

The `kargo.akuity.io/color` annotations (green/yellow/red) are just UI coloring.

---

## 4. `promotiontask.yaml` — the promotion recipe

This is the heart of Kargo. A **PromotionTask** is a reusable sequence of steps
that every Stage invokes. It has variables at the top and steps below.

```yaml
vars:
  - { name: backendImage,  value: ghcr.io/lakunzy7/authenticwrite/backend }
  - { name: frontendImage, value: ghcr.io/lakunzy7/authenticwrite/frontend }
  - { name: repoURL,       value: https://github.com/lakunzy7/multi-cluster-deployment.git }
  - { name: branch,        value: main }
```

### The steps, in order

| # | Step | What it does |
|---|------|--------------|
| 1 | `git-clone` | Clones the repo's `main` branch into `./out`. |
| 2 | `yaml-update` (backend) | Writes the new backend tag into `out/env/<stage>/values.yaml` at key `backend.tag`. |
| 3 | `yaml-update` (frontend) | Same for `frontend.tag`. |
| 4 | `git-commit` | Commits the change with a message like `chore: promote dev to backend cfd86357 frontend cfd86357`. |
| 5 | `git-push` | Pushes the commit back to GitHub (needs the registered credentials — see below). |
| 6 | `argocd-update` | Nudges ArgoCD apps `authenticwrite-<stage>-local` and `-gke` to sync. |

Notes that make this work:

- `${{ ctx.stage }}` is the current stage's name, so the **same task** edits the
  correct `env/dev`, `env/staging`, or `env/prod` file automatically.
- `${{ imageFrom(vars.backendImage).Tag }}` pulls the tag out of the Freight
  being promoted.
- The two `argocd-update` app names line up exactly with the Applications the
  ApplicationSet generates (see `../argocd/README.md`).

### ⚠️ No inline credentials (Kargo v1.3+)

The `git-clone` and `git-push` steps here have **no `credentials:` block** — and
they must not. In Kargo v1.3+ that block fails validation:

```
invalid git-clone config: (root): Additional property credentials is not allowed
```

Instead, credentials are registered **once at the project level** (next section)
and Kargo injects them into every Git step automatically.

---

## 5. Add Git write-credentials to Kargo

Kargo needs to **push** the tag-bump commit, so it needs a GitHub token with
`repo` scope. Register it as a project-level credential (one time):

```bash
kargo create repo-credentials github-creds \
  --project=authenticwrite \
  --git \
  --username=lakunzy7 \
  --repo-url=https://github.com/lakunzy7/multi-cluster-deployment.git \
  --password=YOUR_GITHUB_PAT
```

> The kargo CLI needs **`=` syntax** on every flag and a running **port-forward**
> to the Kargo API (`kubectl port-forward -n kargo svc/kargo-api 3100:443`).
> See `../helm/README.md` for login details.

Verify the credential Secret exists and is labelled correctly:

```bash
kubectl get secret github-creds -n authenticwrite --show-labels
# must carry label: kargo.akuity.io/cred-type=git
```

---

## 6. Apply everything & run a promotion

```bash
# Apply all Kargo manifests (use the kargo CLI, not kubectl, for these)
kargo apply -f ./kargo/

# Confirm
kubectl get project,warehouse,stages,promotiontasks -n authenticwrite

# Make sure Freight was discovered (images must be public!)
kubectl get freight -n authenticwrite
```

Promote via the **UI** (http://localhost:3100 → authenticwrite project → click
the target icon on the `dev` stage → pick Freight → confirm), then repeat
`dev → staging → prod`. Or watch promotions from the CLI:

```bash
kubectl get promotions -n authenticwrite -w
```

After a successful promotion you'll see a new commit in Git (the tag bump) and
ArgoCD syncing the new pods.

---

## 7. End-to-end flow (the whole pipeline)

```
CI builds & pushes images to ghcr.io  (tag = git short SHA)
        │
        ▼
Warehouse detects new backend+frontend tags  ──►  creates Freight
        │
        ▼
You promote Freight into a Stage (dev, then staging, then prod)
        │
        ▼
PromotionTask runs:
  git-clone → yaml-update(backend) → yaml-update(frontend)
           → git-commit → git-push → argocd-update
        │
        ▼
Git now has the new tag in env/<stage>/values.yaml
        │
        ▼
ArgoCD syncs charts/authenticwrite (with that values file) to BOTH clusters
        │
        ▼
New pods running in authenticwrite-<stage> on local + GKE
```

---

## 8. Common issues

| Symptom | Fix |
|---------|-----|
| `Additional property credentials is not allowed` | Remove any `credentials:` block from git steps; use `kargo create repo-credentials` instead. |
| `git-push` → `could not read Username` | The `github-creds` Secret is missing/mislabelled. Re-run Step 5; confirm `kargo.akuity.io/cred-type=git`. |
| No Freight appears | Images aren't public, or no tag matches `^[0-9a-f]{8}$`. Make packages public, refresh the Warehouse. |
| `kargo` CLI: connection refused | Port-forward to `kargo-api` isn't running. |
| `kargo` CLI: token expired | `kargo login --admin https://localhost:3100 --insecure-skip-tls-verify`. |

---

**Related:** `../argocd/README.md` (what consumes the commits Kargo makes) ·
`../env/README.md` (the files Kargo edits) ·
`../charts/authenticwrite/README.md` (the chart those values feed).
