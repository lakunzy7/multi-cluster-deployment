# Kargo promotion pipeline

```
Warehouse(eshop) ──> dev (auto) ──> staging (auto) ──> prod (manual)
```

## Apply

```bash
kubectl --context kind-cloudopshub-local apply -f eshop-config/kargo/
```

## Prereqs (not in this dir)

1. Replace `https://github.com/CHANGE-ME/multi-cluster-deployment.git` in
   stage manifests with the real repo URL once it's pushed to GitHub.
2. Create the git credentials secret in the `eshop` namespace so Kargo can
   commit image tag updates back to the overlays (see task #10).

## Promotion gating

- `dev`   — `autoPromotionEnabled: true`  → new image auto-deploys
- `staging` — `autoPromotionEnabled: true` → auto after dev healthy
- `prod`  — `autoPromotionEnabled: false` → requires manual
            `kargo promote eshop --stage prod --freight <id>` or UI click
