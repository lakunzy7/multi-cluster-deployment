# CI/CD Setup for AuthenticWrite

## Overview

The GitHub Actions workflow on `lakunzy7/AuthenticWrite` (`.github/workflows/build-push.yml`) automatically:

1. **Build** backend (Flask+RoBERTa) and frontend (React+nginx) Docker images
2. **Push** to ghcr.io/lakunzy7/authenticwrite/{backend,frontend} with tags:
   - `:latest` (always points to main)
   - `:${{ github.sha }}` (unique per commit)
3. **Scan** both images with Trivy for vulnerabilities
4. **Upload** scan results to GitHub Security tab
5. **Update** multi-cluster-deployment repo's kustomize overlays with new image tags
6. **Trigger** Kargo to watch for new tags and begin promotion

## Triggers

The workflow runs automatically when:
- Any commit to `main` branch modifies:
  - `backend/**`
  - `frontend/**`
  - `.github/workflows/build-push.yml`

Manual trigger: Push a commit to main that touches backend or frontend.

## Required Secrets

### GITOPS_REPO_TOKEN (Required)

This GitHub PAT allows the workflow to push updates to the multi-cluster-deployment repo.

**Setup**:
1. Go to https://github.com/settings/personal-access-tokens
2. Create new token with:
   - **Scopes**: `repo` (full control of private repositories)
   - **Expiration**: 90 days
3. Copy token value
4. Add to AuthenticWrite repo secrets:
   - Go to `Settings > Secrets and variables > Actions`
   - Click "New repository secret"
   - Name: `GITOPS_REPO_TOKEN`
   - Value: paste token
5. **Important**: Rotate every 90 days before expiration

**Note**: GitHub Actions automatically provides `GITHUB_TOKEN` for pushing to GHCR, so no separate GHCR secret needed.

## Workflow Steps Explained

### 1. Build & Push Backend
```yaml
docker build -f backend/Dockerfile -t ghcr.io/lakunzy7/authenticwrite/backend:$SHA .
docker push ghcr.io/lakunzy7/authenticwrite/backend:$SHA
docker push ghcr.io/lakunzy7/authenticwrite/backend:latest
```

### 2. Build & Push Frontend
```yaml
docker build -f frontend/authenticwrite/Dockerfile -t ghcr.io/lakunzy7/authenticwrite/frontend:$SHA .
docker push ghcr.io/lakunzy7/authenticwrite/frontend:$SHA
docker push ghcr.io/lakunzy7/authenticwrite/frontend:latest
```

### 3. Trivy Vulnerability Scan
Scans each image for vulnerabilities (CVEs), outputs SARIF format.

```bash
trivy image ghcr.io/lakunzy7/authenticwrite/backend:$SHA --format sarif --output trivy-backend.sarif
trivy image ghcr.io/lakunzy7/authenticwrite/frontend:$SHA --format sarif --output trivy-frontend.sarif
```

**Results appear in**:
- GitHub UI: Security tab → Vulnerability alerts
- Can block merge if policy enforced (optional)

### 4. Update Kustomize Overlays

The workflow updates `multi-cluster-deployment` repo:

```bash
# In kubernetes/overlays/dev/kustomization.yaml:
kustomize edit set image \
  ghcr.io/lakunzy7/authenticwrite/backend=ghcr.io/lakunzy7/authenticwrite/backend:$SHA \
  ghcr.io/lakunzy7/authenticwrite/frontend=ghcr.io/lakunzy7/authenticwrite/frontend:$SHA

# Same for overlays/staging/ and overlays/prod/
```

This edits the `images:` section in each overlay's `kustomization.yaml`.

### 5. Commit & Push to Multi-Cluster Deployment

```bash
cd multi-cluster-deployment
git add kubernetes/overlays/*/kustomization.yaml
git commit -m "chore: update AuthenticWrite images to $SHA"
git push origin main
```

## How Kargo Picks Up Changes

**Flow**:

1. AuthenticWrite CI pushes new image to GHCR (e.g., `ghcr.io/lakunzy7/authenticwrite/backend:abc123`)
2. **Kargo Warehouse** watches the registry, detects new tag
3. **Dev stage** (automatic): Kargo patches `overlays/dev/kustomization.yaml` with new tag
4. **Staging stage** (manual): User clicks "Promote" in Kargo UI or CLI
   - Kargo patches `overlays/staging/kustomization.yaml`
   - ArgoCD syncs to both clusters
   - Kargo polls both regional apps until Healthy
5. **Prod stage** (manual): User promotes staging → prod (same flow)

## Testing the Workflow

### Manual Test

1. Make a small change to backend or frontend (e.g., add a comment)
2. Push to main:
   ```bash
   git add backend/app.py
   git commit -m "test: minor change to trigger CI"
   git push origin main
   ```
3. Watch the workflow:
   - Go to AuthenticWrite repo → Actions tab
   - See "Build and Push Images" workflow running
   - Wait for all steps to complete (~5-10 mins, depending on image size)
4. Verify results:
   - Check GHCR: https://github.com/lakunzy7?tab=packages
   - Look for new images with latest git SHA tag
   - Check Security tab for Trivy scan results
   - Verify `multi-cluster-deployment` repo has updated `kubernetes/overlays/*/kustomization.yaml`

### Kargo Test

1. After CI completes and images are in GHCR:
   ```bash
   kubectl port-forward -n kargo svc/kargo 8080:8080
   ```
2. Open http://localhost:8080 → Kargo UI
3. Select "authenticwrite" project
4. Click "dev" stage → see new images detected
5. (Optional) Manually promote dev → staging:
   ```bash
   kargo promote authenticwrite staging --from dev
   ```
6. Watch ArgoCD sync:
   ```bash
   kubectl get applications -n argocd | grep staging
   ```

## Troubleshooting

### Workflow Fails at "Update deployment repo"

**Error**: `GITOPS_REPO_TOKEN secret not found`

**Fix**: Add secret to AuthenticWrite repo (see "Required Secrets" section above).

### Kustomize Edit Fails

**Error**: `kustomize edit set image` doesn't find images

**Cause**: Image names don't match between Dockerfile and kustomization.yaml

**Verify**:
```bash
# Check what kustomization.yaml expects:
grep -A 5 "images:" kubernetes/overlays/dev/kustomization.yaml

# Ensure it matches what the workflow sets:
# ghcr.io/lakunzy7/authenticwrite/backend
# ghcr.io/lakunzy7/authenticwrite/frontend
```

### Images Don't Appear in GHCR

**Cause**: GITHUB_TOKEN permissions issue

**Fix**: GitHub Actions automatically has permission to push to GHCR — if images don't appear after 5 mins, check workflow logs for docker login errors.

### Trivy Scan Takes Too Long

**Cause**: First scan of large images (especially backend with RoBERTa model) can take 2-3 mins.

**Expected**: Scans are cached between runs, so subsequent builds are faster.

## Security Best Practices

1. **Rotate GITOPS_REPO_TOKEN** every 90 days (set a calendar reminder)
2. **Review Trivy scan results** before merging (GitHub will flag in Security tab)
3. **Don't commit secrets** (use GitHub Secrets, not plaintext in workflow)
4. **Monitor image sizes**: Backend ~2.5GB is expected; if it grows unexpectedly, review dependencies
5. **Test images locally** before pushing:
   ```bash
   docker build -f backend/Dockerfile -t authenticwrite-backend:test .
   docker run --rm authenticwrite-backend:test curl http://localhost:5000/health
   ```

## Manual Image Push (If Workflow Fails)

As a fallback, you can build and push images manually:

```bash
# Build backend
docker build -f backend/Dockerfile -t ghcr.io/lakunzy7/authenticwrite/backend:v1.0 .
docker tag ghcr.io/lakunzy7/authenticwrite/backend:v1.0 ghcr.io/lakunzy7/authenticwrite/backend:latest

# Push (requires docker login)
docker login ghcr.io --username lakunzy7 --password <PAT>
docker push ghcr.io/lakunzy7/authenticwrite/backend:v1.0
docker push ghcr.io/lakunzy7/authenticwrite/backend:latest

# Update kustomize manually
cd /path/to/multi-cluster-deployment
cd kubernetes/overlays/dev
kustomize edit set image ghcr.io/lakunzy7/authenticwrite/backend=ghcr.io/lakunzy7/authenticwrite/backend:v1.0
git add kustomization.yaml
git commit -m "chore: manual image push to v1.0"
git push origin main
```

## References

- [GitHub Actions Docker Build/Push](https://github.com/docker/build-push-action)
- [Aqua Trivy GitHub Action](https://github.com/aquasecurity/trivy-action)
- [Kustomize Image Setting](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/#images)
- [GitHub Secrets Management](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
