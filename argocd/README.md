# ArgoCD — GitOps Sync Layer

ArgoCD's job in this project: **keep both clusters matching what's in Git.**
You never run `kubectl apply` for the app — you change Git, and ArgoCD syncs it.

This folder has just two manifests:

```
argocd/
├── appproj.yaml   # AppProject — a security boundary for what these apps may do
└── appset.yaml    # ApplicationSet — auto-generates one Application per (env × cluster)
```

Apply them **after** ArgoCD is installed (see `../helm/README.md`) and cluster 2
is registered:

```bash
kubectl apply -f argocd/appproj.yaml
kubectl apply -f argocd/appset.yaml

# Verify the generated Applications
kubectl get applications -n argocd | grep authenticwrite
```

---

## 1. `appproj.yaml` — the AppProject (security boundary)

An **AppProject** restricts what its Applications are allowed to do. Think of it
as a guardrail. Ours says:

```yaml
sourceRepos:
- https://github.com/lakunzy7/multi-cluster-deployment.git   # may ONLY deploy from this repo
destinations:
- name: '*'                      # any registered cluster...
  namespace: authenticwrite-*    # ...but only into authenticwrite-* namespaces
  server: '*'
clusterResourceWhitelist:
- group: ""                      # cluster-scoped resources allowed:
  kind: Namespace                #   only Namespaces
namespaceResourceWhitelist:
- group: '*'                     # any namespaced resource allowed
  kind: '*'
```

In plain English: applications in this project can **only** pull from our repo,
**only** deploy into `authenticwrite-*` namespaces, and the only cluster-wide
object they may create is a `Namespace`. This stops a misconfigured app from
touching unrelated parts of the cluster.

---

## 2. `appset.yaml` — the ApplicationSet (the clever part)

An **ApplicationSet** is a factory that **generates many Applications** from a
template. Ours uses a **matrix** of two generators, so it produces one
Application for **every combination of environment × cluster**.

### Generator 1 — Git directories (the environments)

```yaml
- git:
    repoURL: https://github.com/lakunzy7/multi-cluster-deployment.git
    revision: HEAD
    directories:
    - path: env/*          # finds env/dev, env/staging, env/prod
```

This scans the repo and yields one item per folder under `env/` →
`dev`, `staging`, `prod`. The folder name becomes `{{path.basename}}`.

### Generator 2 — A static list (the clusters)

```yaml
- list:
    elements:
    - clusterAlias: cluster1
      clusterName: in-cluster              # cluster 1 — ArgoCD lives here
    - clusterAlias: cluster2
      clusterName: k8slab-second-cluster   # cluster 2 (registered via Sealed Secret)
```

`clusterName` must match an ArgoCD **registered cluster** name. `in-cluster` is
built in; `k8slab-second-cluster` is the one you added in `../helm/README.md`.
`clusterAlias` is just a cosmetic label that becomes part of the app name — it is
**not** referenced anywhere else (Kargo selects apps by label, not by this name —
see Section 3), so you can rename it freely or add more list entries.

### The matrix → 6 Applications

3 environments × 2 clusters = **6 Applications**:

```
authenticwrite-dev-cluster1        authenticwrite-dev-cluster2
authenticwrite-staging-cluster1    authenticwrite-staging-cluster2
authenticwrite-prod-cluster1       authenticwrite-prod-cluster2
```

### The template — what each generated Application looks like

```yaml
template:
  metadata:
    name: authenticwrite-{{path.basename}}-{{clusterAlias}}
    labels:
      stage: "{{path.basename}}"                                          # (A)
    annotations:
      kargo.akuity.io/authorized-stage: authenticwrite:{{path.basename}}   # (A)
  spec:
    destination:
      namespace: authenticwrite-{{path.basename}}    # e.g. authenticwrite-dev
      name: "{{clusterName}}"                          # which cluster to deploy to
    project: authenticwrite                            # uses the AppProject above
    source:
      path: charts/authenticwrite                      # the Helm chart
      repoURL: https://github.com/lakunzy7/multi-cluster-deployment.git
      helm:
        valueFiles:
        - "/env/{{path.basename}}/values.yaml"         # (B) per-env overrides
```

Two things to notice:

- **(A) The `stage` label + `kargo.akuity.io/authorized-stage` annotation** —
  together these are the handshake with Kargo. The **annotation** gives Kargo
  permission to trigger a sync for the matching stage; the **label** is how
  Kargo *finds* the apps to sync — its `argocd-update` step selects by
  `matchLabels: {stage: <stage>}` rather than naming each app (see Section 3).
  This is what lets you add/rename clusters in the `list` above without touching
  the Kargo PromotionTask.
- **(B) `valueFiles`** — each Application renders the **same chart**
  (`charts/authenticwrite`) but layers the environment's override file on top
  (`env/dev/values.yaml`, etc.). That's how dev gets 1 replica and prod gets 3.

---

## 3. How ArgoCD and Kargo work together

They have **separate jobs** and meet in Git:

```
        Kargo's job                         ArgoCD's job
  ┌──────────────────────┐           ┌───────────────────────────┐
  │ Pick the image tag,  │   commit  │ See the changed values.yaml│
  │ write it into        │ ───────►  │ in Git, sync the Helm chart│
  │ env/<stage>/values   │   to Git  │ to the target cluster(s)   │
  └──────────────────────┘           └───────────────────────────┘
```

1. Kargo promotes a stage → edits `env/<stage>/values.yaml` (new image tag) →
   commits & pushes to Git.
2. Kargo's final promotion step (`argocd-update`) **nudges** the matching ArgoCD
   Applications to sync now (instead of waiting for the poll).
3. ArgoCD renders `charts/authenticwrite` with the updated values file and applies
   it to **both** clusters for that environment.

The `argocd-update` step in `../kargo/promotiontask.yaml` selects apps by the
**`stage` label** (`matchLabels: {stage: <stage>}`) that this ApplicationSet
stamps on every generated app — so it nudges *all* clusters for that stage at
once, regardless of how many clusters or what they're named. And it's allowed to
do so because of the `authorized-stage` annotation in the template. (Earlier this
step listed app names like `authenticwrite-<stage>-local` literally; the label
selector replaces that so cluster changes only touch `appset.yaml`.)

---

## 4. Verify & operate

```bash
# List the generated apps and their sync/health status
kubectl get applications -n argocd | grep authenticwrite

# Before the first promotion you'll see OutOfSync / Missing — that's NORMAL,
# because env/*/values.yaml may not yet have a real image tag deployed.

# Force a sync manually if needed
kubectl patch application authenticwrite-dev-cluster1 -n argocd \
  --type merge -p '{"operation":{"sync":{}}}'
```

In the ArgoCD UI (port-forward `8081`, see root `README.md`) you can click any
of the 6 apps to see the live resource tree, diffs, and sync history.

---

## 5. Common issues

| Symptom | Fix |
|---------|-----|
| Only 3 apps generated, not 6 | The cluster `list` generator or a `clusterName` is wrong — confirm both clusters are registered (`argocd cluster list`). |
| App stuck `OutOfSync/Missing` | Expected before first promotion. Promote via Kargo, or force-sync (above). |
| `cluster "k8slab-second-cluster" not found` | The cluster 2 Secret isn't applied/decrypted — see `../helm/README.md` Part C. |
| App can't deploy — destination not permitted | The namespace isn't `authenticwrite-*`, which the AppProject forbids. |

---

**Related:** `../kargo/README.md` (what triggers the syncs) ·
`../charts/authenticwrite/README.md` (the chart being deployed) ·
`../env/README.md` (the per-environment values).
