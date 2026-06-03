# GitHub Webhooks Setup for Kargo Integration

This guide explains how to set up GitHub Container Registry (GHCR) webhooks to trigger Kargo freight detection when new images are pushed.

## Overview

The workflow:
1. **Image Build**: `build-push-images.yml` builds backend/frontend images
2. **GHCR Push**: Images pushed to `ghcr.io/lakunzy7/authenticwrite`
3. **GitHub Webhook**: GHCR notifies Kargo of new images
4. **Kargo Detection**: Warehouse creates Freight object
5. **Manual Promotion**: User approves dev → staging → prod

---

## Prerequisites

- Kargo installed on Kind cluster (namespace: `kargo`)
- GHCR repository configured
- GitHub token with `repo:webhook` and `packages:read` permissions

---

## Step 1: Create GitHub Personal Access Token (PAT)

1. Go to https://github.com/settings/tokens/new
2. Create token with scopes:
   - `repo` (full control of repositories)
   - `write:packages` (push/delete packages)
   - `read:packages` (install packages)
3. Copy token value (will use in Step 3)

---

## Step 2: Get Kargo Webhook URL

Kargo exposes a webhook receiver on the Kargo API. First, port-forward to the Kargo service:

```bash
# Terminal 1: Port-forward Kargo API
kubectl port-forward -n kargo svc/kargo-api 8080:8080

# Terminal 2: Get webhook endpoint
KARGO_API_HOST=localhost:8080
WEBHOOK_TOKEN=$(kubectl get secret -n kargo kargo-api-token -o jsonpath='{.data.token}' | base64 -d)

echo "Kargo Webhook URL:"
echo "http://${KARGO_API_HOST}/api/v1/webhook/github"
echo ""
echo "Token: ${WEBHOOK_TOKEN}"
```

---

## Step 3: Configure GHCR Webhook

### Using GitHub UI (Manual)

1. Go to **GitHub Settings** → **Developer settings** → **Webhooks**
2. Click **Add webhook**
3. Configure:
   - **Payload URL**: `http://<your-kargo-webhook-url>`
   - **Content type**: `application/json`
   - **Secret**: `<WEBHOOK_TOKEN from Step 2>`
   - **Events**: Select "Package published"
4. Click **Add webhook**

### Using GitHub CLI (Automated)

```bash
#!/bin/bash
set -euo pipefail

REPO_OWNER="lakunzy7"
GHCR_REPO="authenticwrite"
KARGO_WEBHOOK_URL="http://your-kargo-url/api/v1/webhook/github"
WEBHOOK_SECRET="your-kargo-webhook-token"

# Create webhook
gh api repos/$REPO_OWNER/$GHCR_REPO/hooks \
  --input - <<EOF
{
  "name": "web",
  "active": true,
  "events": ["package"],
  "config": {
    "url": "$KARGO_WEBHOOK_URL",
    "content_type": "json",
    "secret": "$WEBHOOK_SECRET",
    "insecure_ssl": "0"
  }
}
EOF

echo "✅ Webhook created"
```

---

## Step 4: Verify Kargo Event Notifications

Monitor Kargo event receiver logs:

```bash
# Check if Kargo detected the webhook
kubectl logs -n kargo deployment/kargo-api -f | grep -i "webhook\|freight\|image"

# Verify Warehouse detected images
kubectl get warehouse -n kargo
kubectl describe warehouse authenticwrite -n kargo

# Check Freight objects created
kubectl get freight -n kargo
kubectl describe freight -n kargo | head -50
```

---

## Step 5: Test the Integration

### Trigger a Build Manually

```bash
# Push a commit to main that touches Dockerfile or app code
git commit --allow-empty -m "test: trigger image build"
git push origin main

# Monitor workflow
gh run list --workflow build-push-images.yml --limit 1

# Once complete, check if Kargo detected images
kubectl get freight -n kargo
```

### Manual Kargo Promotion (if webhook fails)

```bash
# If images aren't auto-detected, manually trigger Kargo:
kargo promote authenticwrite dev --from warehouse:authenticwrite
```

---

## Step 6: Create Kargo Webhook Secret (Optional but Recommended)

Store webhook token securely in the cluster:

```bash
kubectl create secret generic -n kargo kargo-github-webhook \
  --from-literal=token="$(kubectl get secret -n kargo kargo-api-token -o jsonpath='{.data.token}' | base64 -d)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## Troubleshooting

### Webhook not firing
- Check GitHub webhook delivery logs: Repo Settings → Webhooks → Recent Deliveries
- Verify webhook URL is accessible from GitHub servers
- Check firewall rules allow inbound GitHub IPs

### Kargo not detecting images
- Verify Warehouse subscription matches image repo: `ghcr.io/lakunzy7/authenticwrite`
- Check image tags match Warehouse constraints
- Monitor: `kubectl logs -n kargo deployment/kargo-api`

### Images not syncing to clusters
- Verify ArgoCD applications are syncing: `kubectl get applications -n argocd`
- Check ApplicationSet generated apps: `kubectl get applicationset -n argocd`
- Review sync status: `argocd app list`

---

## YAML Reference

**Kargo Project with Webhook:**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Project
metadata:
  name: authenticwrite
  namespace: kargo
spec:
  eventNotificationReceiver:
    subscriptions:
      - selector: "registry=github"
```

**Kargo Warehouse:**

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: authenticwrite
  namespace: kargo
spec:
  subscriptions:
    - image:
        repoURL: ghcr.io/lakunzy7/authenticwrite
        semverConstraint: "*"
```

---

## Next Steps

1. ✅ Webhook configured
2. ✅ Kargo monitoring GHCR
3. → Deploy to Kind cluster (see [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md))
4. → Test end-to-end pipeline
