# ArgoCD ApplicationSets for eShop (multi-cluster fan-out, manual sync)

Three `ApplicationSet`s + one `AppProject`. Each ApplicationSet uses a **cluster generator** matching every cluster labeled `env: multi`, producing one `Application` per (environment, region) pair.

Currently 6 generated Applications (2 clusters × 3 envs). Add a new cluster with `env=multi` and 3 more Applications appear automatically.

**Sync policy is manual on all 6.** Rollouts happen only when Kargo runs an `argocd-update` step during a promotion. Direct git edits do not trigger deploys.

## Files

| File | What it creates |
|---|---|
| `00-project.yaml` | `AppProject eshop` — repo allowlist + name-wildcard destinations (any cluster, the 3 eshop-* namespaces) |
| `01-eshop-dev.yaml` | `ApplicationSet eshop-dev` → `eshop-dev-<region>` Apps, manual sync |
| `02-eshop-staging.yaml` | `ApplicationSet eshop-staging` → `eshop-staging-<region>` Apps, manual sync |
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

## Sync policy

| Stage | Kargo `autoPromotionEnabled` | ApplicationSet `automated` |
|---|---|---|
| dev | false | **no** |
| staging | false | **no** |
| prod | false | **no** |

Promotions are the only way to roll out a new image. The `argocd-update` step inside each Kargo Stage's promotionTemplate (a) syncs both regional Apps and (b) blocks until both report Healthy. See `../kargo/README.md` for the full flow.

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

Expected output (6 Apps, all "Manual"):

```
eshop-dev-local             in-cluster         eshop-dev      Manual
eshop-dev-europe-west1      gke-cloud-cluster  eshop-dev      Manual
eshop-staging-local         in-cluster         eshop-staging  Manual
eshop-staging-europe-west1  gke-cloud-cluster  eshop-staging  Manual
eshop-prod-local            in-cluster         eshop-prod     Manual
eshop-prod-europe-west1     gke-cloud-cluster  eshop-prod     Manual
```

## Out-of-band sync (debugging only)

If you need to force-sync without going through Kargo (e.g. while developing a manifest):

```bash
argocd app sync eshop-dev-local --prune
```

Don't make a habit of it — it bypasses the freight gate and Kargo's view of stage state will diverge from reality.

## Removing a region

Delete the cluster Secret (or remove the `env=multi` label) and ArgoCD prunes that region's generated Applications:

```bash
kubectl -n argocd label secret gke-cloud-cluster env-
```
