# ArgoCD ApplicationSets for eShop (multi-cluster fan-out)

Three `ApplicationSet`s + one `AppProject`. Each ApplicationSet uses a **cluster generator** that matches every cluster labeled `env: multi`, producing one `Application` per (environment, region) pair.

Currently 6 generated Applications (2 clusters × 3 envs). Add a new cluster with `env=multi` and 3 more Applications appear automatically.

## Files

| File | What it creates |
|---|---|
| `00-project.yaml` | `AppProject eshop` — repo allowlist + name-wildcard destinations (any cluster, the 3 eshop-* namespaces) |
| `01-eshop-dev.yaml` | `ApplicationSet eshop-dev` → `eshop-dev-<region>` Apps, auto-sync |
| `02-eshop-staging.yaml` | `ApplicationSet eshop-staging` → `eshop-staging-<region>` Apps, auto-sync |
| `03-eshop-prod.yaml` | `ApplicationSet eshop-prod` → `eshop-prod-<region>` Apps, manual sync |

## Topology

```
                                       eshop-config/overlays/
                                       ├── dev/
                                       ├── staging/
                                       └── prod/
                                              │
                              ┌───────────────┴───────────────┐
                              │ ApplicationSet (cluster gen)  │
                              └───────┬───────────────┬───────┘
                                      │               │
                                      ▼               ▼
                            ┌──────────────┐  ┌──────────────┐
                            │ Kind         │  │ GKE          │
                            │ region=local │  │ region=eu-w1 │
                            │              │  │              │
                            │ ns: eshop-dev│  │ ns: eshop-dev│
                            │ ns: eshop-stg│  │ ns: eshop-stg│
                            │ ns: eshop-prd│  │ ns: eshop-prd│
                            └──────────────┘  └──────────────┘
```

Both clusters get every environment in their own namespace. They serve different geographic regions; the same git overlay drives both.

## Cluster selection

ApplicationSets target via label, not name:

```yaml
generators:
  - clusters:
      selector:
        matchLabels:
          env: multi
```

Cluster Secrets must carry that label. Currently labeled:

| Cluster | env | region |
|---|---|---|
| `in-cluster` (Kind) | `multi` | `local` |
| `gke-cloud-cluster` (GKE) | `multi` | `europe-west1` |

To add a new region, register the cluster (see `../argocd-clusters/HOW-TO-ADD-CLUSTER.md`) with labels `env=multi, region=<name>`. The ApplicationSets fan out to it automatically — no edits here.

## Sync policy alignment with Kargo

| Stage | Kargo `autoPromotionEnabled` | ApplicationSet `automated` |
|---|---|---|
| dev | true | yes |
| staging | true | yes |
| prod | **false** | **no** (manual per region) |

Prod requires:
1. Kargo promotion (commits the new image tag to `overlays/prod/`)
2. Manual `argocd app sync eshop-prod-local` **and** `argocd app sync eshop-prod-europe-west1`

Two gates per region — deliberate.

## Bootstrap

Prerequisites: both clusters registered + labeled (see `../argocd-clusters/`).

```bash
kubectl --context kind-cloudopshub-local apply -f eshop-config/argocd-apps/
```

## Verify

```bash
kubectl -n argocd get applicationsets
kubectl -n argocd get applications
argocd app list
```

Expected output (6 Apps):

```
eshop-dev-local             in-cluster         eshop-dev      Auto-Prune
eshop-dev-europe-west1      gke-cloud-cluster  eshop-dev      Auto-Prune
eshop-staging-local         in-cluster         eshop-staging  Auto-Prune
eshop-staging-europe-west1  gke-cloud-cluster  eshop-staging  Auto-Prune
eshop-prod-local            in-cluster         eshop-prod     Manual
eshop-prod-europe-west1     gke-cloud-cluster  eshop-prod     Manual
```

## Manual prod rollout

```bash
# Roll out to one region at a time (canary-style)
argocd app sync eshop-prod-europe-west1
argocd app wait eshop-prod-europe-west1 --health
# Then the other region
argocd app sync eshop-prod-local

# OR: roll out everywhere at once
argocd app sync -l app.kubernetes.io/instance=eshop-prod
```

## Removing a region

Delete the cluster Secret (or remove the `env=multi` label) and ArgoCD will prune that region's generated Applications:

```bash
kubectl -n argocd label secret gke-cloud-cluster env-
```

The ApplicationSet controller detects the cluster no longer matches and deletes the corresponding Applications. Workloads in the removed region are torn down (because `prune: true` on dev/staging) — for prod, you'd want to disable pruning first.
