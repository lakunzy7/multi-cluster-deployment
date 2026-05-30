# Kargo promotion pipeline (fully manual + multi-region health gates)

```
Warehouse(eshop) ──> dev (manual) ──> staging (manual) ──> prod (manual)
                       │                   │                  │
                       │                   │                  │
                  syncs BOTH         syncs BOTH         syncs BOTH
                   regions            regions            regions
                  (must be          (must be           (must be
                   Healthy)          Healthy)           Healthy)
```

Every stage requires a deliberate `kargo promote` (or UI click). A promotion only succeeds when **both regions** of that stage report `Synced + Healthy` via ArgoCD — that's the gate. If one region is sick, the promotion blocks and the freight does **not** become eligible for the next stage downstream.

## How the gate works

Each Stage's `promotionTemplate.steps` ends with an `argocd-update` step listing **both** regional Applications:

```yaml
- uses: argocd-update
  config:
    apps:
      - name: eshop-<stage>-local
        sources: [...]
      - name: eshop-<stage>-europe-west1
        sources: [...]
```

The step blocks until each App is `Synced` **and** `Healthy`. Only then does the Promotion resource transition to `Succeeded`, and only then does the Stage update its `currentFreight` — which is what the next downstream Stage subscribes to (`sources.stages: [<previous>]`).

Result: you cannot promote freight to staging unless both dev regions are healthy. You cannot promote to prod unless both staging regions are healthy.

## Apply

```bash
kubectl --context kind-cloudopshub-local apply -f eshop-config/kargo/
```

## How to promote (the manual flow)

```bash
# 1. List available freight
kargo get freight --project eshop

# 2. Promote the chosen freight into dev (rolls out to BOTH regions)
kargo promote --project eshop --stage dev --freight <freight-id>

# 3. Watch the promotion. The Kargo UI or:
kargo get promotion --project eshop -w

# 4. When dev is green in both regions, promote to staging
kargo promote --project eshop --stage staging --freight <freight-id>

# 5. When staging is green in both regions, promote to prod
kargo promote --project eshop --stage prod --freight <freight-id>
```

## Promotion gating summary

| Stage | `autoPromotionEnabled` | Source freight from | Gates before next stage |
|---|---|---|---|
| dev | false | Warehouse direct | both `eshop-dev-{local,europe-west1}` Healthy |
| staging | false | `dev` stage | both `eshop-staging-{local,europe-west1}` Healthy |
| prod | false | `staging` stage | both `eshop-prod-{local,europe-west1}` Healthy |

The chain (dev → staging → prod) is enforced structurally by `sources.stages` in each Stage, not by a separate promotion policy.

## Why ArgoCD auto-sync is OFF too

The ApplicationSets in `../argocd-apps/` are configured with **no** `syncPolicy.automated`. Direct edits to `overlays/<stage>/kustomization.yaml` in git do **not** auto-deploy. The only path to a rollout is a Kargo promotion, which:

1. Commits the new image tag to the overlay in git
2. Triggers `argocd app sync` for both regional Apps
3. Waits for both to be Healthy
4. Marks the freight successful in this stage

This eliminates two failure modes:
- ArgoCD silently deploying an untested image because someone edited git directly
- Drift between "what Kargo thinks is in the stage" and "what ArgoCD actually deployed"
