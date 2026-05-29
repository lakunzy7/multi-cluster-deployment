# ArgoCD Applications for eShop

Three `Application`s + one `AppProject`, one per environment. All point at the same git repo (this one) but at different overlays and different destination clusters.

## Files

| File | What it creates |
|---|---|
| `00-project.yaml` | `AppProject eshop` — allowlist of repos, clusters, and namespaces |
| `01-eshop-dev.yaml` | `Application eshop-dev` → in-cluster (Kind), ns `eshop-dev`, **auto-sync** |
| `02-eshop-staging.yaml` | `Application eshop-staging` → in-cluster (Kind), ns `eshop-staging`, **auto-sync** |
| `03-eshop-prod.yaml` | `Application eshop-prod` → `gke-cloud-cluster`, ns `eshop-prod`, **manual sync** |

## Topology

```
                ┌────────────────────────────────────────┐
                │   Kind cluster: cloudopshub-local      │
                │   (ArgoCD + Kargo + cert-manager)      │
                │                                        │
                │   ns: eshop-dev      ← Application     │
                │   ns: eshop-staging  ← Application     │
                └────────────────────────────────────────┘
                                  │
                                  │   Application: eshop-prod
                                  ▼
                ┌────────────────────────────────────────┐
                │   GKE cluster: cloud-cluster           │
                │   (zonal europe-west1-b, 2× Spot)      │
                │                                        │
                │   ns: eshop-prod                       │
                └────────────────────────────────────────┘
```

## Sync policy alignment with Kargo

This matches the Kargo gating in `eshop-config/kargo/`:

| Stage | Kargo `autoPromotionEnabled` | ArgoCD `syncPolicy.automated` |
|---|---|---|
| dev | true | yes |
| staging | true | yes |
| prod | **false** | **no** (manual sync only) |

When Kargo promotes to prod, it does the **git commit** that updates `eshop-config/overlays/prod/kustomization.yaml` with the new image tag. The actual rollout still requires `argocd app sync eshop-prod` (or a click in the UI). Two gates instead of one — deliberate for prod.

## Bootstrap

Prerequisite: GKE cluster registered (see `../argocd-clusters/HOW-TO-ADD-CLUSTER.md`).

```bash
kubectl --context kind-cloudopshub-local apply -f eshop-config/argocd-apps/
```

## Verify

```bash
argocd app list
# expected: eshop-dev, eshop-staging, eshop-prod

argocd app get eshop-dev
argocd app get eshop-prod    # SYNC STATUS will be OutOfSync until you sync manually
```

## Manual prod sync

```bash
# Preview
argocd app diff eshop-prod

# Apply
argocd app sync eshop-prod

# Watch rollout
argocd app wait eshop-prod --health
```

## Self-management (optional next step)

These Application manifests themselves can be put under ArgoCD management via an **App-of-Apps** pattern — a single `Application` that watches this directory and creates/updates the others. That makes the registration declarative end-to-end. Not set up yet.
