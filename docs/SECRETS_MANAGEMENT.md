# Secrets Management Guide for CloudOpsHub

Complete guide on how to manage secrets securely in this multi-cluster project.

## Overview

**What needs to be secret?**
- GHCR pull credentials (to pull Docker images)
- Database passwords (when added)
- API tokens (GitHub PAT for GitOps, cloud providers)
- TLS certificates (for HTTPS)

**How we manage them:**
- Sealed-Secrets: encrypts secrets in git (recommended, already in project)
- Alternative: External-Secrets, SOPS, HashiCorp Vault

---

## 1. Sealed-Secrets (Recommended)

**Why Sealed-Secrets?**
- ✅ Secrets stored in git (encrypted)
- ✅ No external service needed
- ✅ Automatic unsealing in-cluster
- ✅ Per-cluster encryption keys
- ❌ Keys must be synced between clusters

### 1.1 How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                    Plain Secret (secret.yaml)                   │
│  apiVersion: v1                                                  │
│  kind: Secret                                                    │
│  data:                                                           │
│    password: "my-secret-password"  ← PLAINTEXT (DANGEROUS!)     │
└─────────────────────────────────────────────────────────────────┘
                              │
                    kubeseal -f secret.yaml
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│               Sealed Secret (sealed-secret.yaml)                │
│  apiVersion: bitnami.com/v1                                      │
│  kind: SealedSecret                                              │
│  spec:                                                           │
│    encryptedData:                                               │
│      password: AgBkL2n4F8q8F8q8F8q8F8q8F8q8F8q8F8q8...  ← SAFE  │
└─────────────────────────────────────────────────────────────────┘
                              │
                    git commit & push
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Sealed-Secrets Controller                       │
│  (Runs in sealed-secrets namespace on each cluster)              │
│                                                                   │
│  When sealed-secret applied:                                    │
│  1. Controller reads encrypted data                             │
│  2. Decrypts with cluster's private key                         │
│  3. Creates plain Secret (in-memory only)                       │
│  4. Application reads plain Secret                              │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Setup Sealed-Secrets on Both Clusters

#### Step 1: Deploy Controller

```bash
# On Kind cluster
kubectl config use-context kind-cloudopshub-local
kubectl apply -f kubernetes/sealed-secrets-install.yaml

# Wait for controller to start
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=sealed-secrets-controller \
  -n sealed-secrets --timeout=60s

# On GKE cluster
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f kubernetes/sealed-secrets-install.yaml

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=sealed-secrets-controller \
  -n sealed-secrets --timeout=60s
```

#### Step 2: Backup Keys from Kind

```bash
# Kind generates keys automatically on first startup
# Backup the sealing key so we can use it on other clusters

kubectl config use-context kind-cloudopshub-local

kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key-backup.yaml

# IMPORTANT: Keep this file safe! It's your encryption key!
# Do NOT commit to git without encryption
```

#### Step 3: Sync Keys to GKE

```bash
# Apply the Kind cluster's sealing key to GKE
# This allows GKE to unseal secrets sealed by Kind

kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster

kubectl apply -f sealing-key-backup.yaml

# Restart sealed-secrets controller to reload keys
kubectl rollout restart deployment/sealed-secrets-controller -n sealed-secrets
```

### 1.3 Create & Seal Your First Secret (GHCR Pull Credentials)

#### Step 1: Create Plain Secret

```bash
kubectl config use-context kind-cloudopshub-local

# Create a plain secret with GHCR credentials
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=lakunzy7 \
  --docker-password=ghp_YourGitHubPATHere \
  --docker-email=your-email@example.com \
  -n authenticwrite \
  --dry-run=client -o yaml > secret.yaml

# Verify it's created correctly
cat secret.yaml
```

#### Step 2: Seal the Secret

```bash
# Install kubeseal CLI (if not already installed)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar xfz kubeseal-0.24.0-linux-amd64.tar.gz
sudo mv kubeseal /usr/local/bin/

# Seal the secret
kubeseal -f secret.yaml -w sealed-secret.yaml

# View sealed secret (encrypted, safe to commit)
cat sealed-secret.yaml
```

#### Step 3: Apply Sealed Secret

```bash
# Apply to Kind
kubectl config use-context kind-cloudopshub-local
kubectl apply -f sealed-secret.yaml -n authenticwrite

# Verify the secret was created (controller automatically unsealed it)
kubectl get secret -n authenticwrite ghcr-pull-secret -o yaml

# Apply to GKE (using same sealed-secret file, different key)
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f sealed-secret.yaml -n authenticwrite

# Verify
kubectl get secret -n authenticwrite ghcr-pull-secret -o yaml
```

#### Step 4: Update Deployment to Use Secret

The deployment already references the secret:

```yaml
# In kubernetes/manifests/base/backend.yaml
spec:
  imagePullSecrets:
    - name: ghcr-pull-secret  # ← References sealed secret
```

When the pod starts, Kubernetes automatically uses `ghcr-pull-secret` to pull images from GHCR.

#### Step 5: Commit Sealed Secret to Git

```bash
# Sealed secret is safe to commit (encrypted)
git add sealed-secret.yaml
git commit -m "chore: add sealed GHCR credentials"
git push origin main

# But NEVER commit the plain secret!
rm secret.yaml
```

---

## 2. Creating Other Types of Secrets

### 2.1 Generic Secret (API Keys, Passwords)

```bash
# Create a generic secret
kubectl create secret generic app-secrets \
  --from-literal=database-password=mypassword123 \
  --from-literal=api-key=sk_live_abc123def456 \
  -n authenticwrite \
  --dry-run=client -o yaml > secret-api.yaml

# Seal it
kubeseal -f secret-api.yaml -w sealed-secret-api.yaml

# Apply
kubectl apply -f sealed-secret-api.yaml -n authenticwrite
```

### 2.2 TLS Certificate Secret

```bash
# Create a TLS secret (for HTTPS)
kubectl create secret tls tls-secret \
  --cert=path/to/certificate.crt \
  --key=path/to/private.key \
  -n authenticwrite \
  --dry-run=client -o yaml > secret-tls.yaml

# Seal it
kubeseal -f secret-tls.yaml -w sealed-secret-tls.yaml

# Apply
kubectl apply -f sealed-secret-tls.yaml -n authenticwrite
```

### 2.3 ConfigMap with Non-Sensitive Data

**Don't seal ConfigMaps** — they're for non-sensitive config:

```bash
kubectl create configmap app-config \
  --from-literal=log-level=info \
  --from-literal=database-host=db.default.svc.cluster.local \
  -n authenticwrite

# Apply directly (no sealing needed)
kubectl apply -f configmap.yaml -n authenticwrite
```

---

## 3. Secret Rotation

### 3.1 Rotate GHCR Token

```bash
# 1. Generate new GitHub PAT
#    Go to: https://github.com/settings/personal-access-tokens
#    Create new token with 'repo' scope

# 2. Create new sealed secret
kubectl config use-context kind-cloudopshub-local

kubectl create secret docker-registry ghcr-pull-secret-new \
  --docker-server=ghcr.io \
  --docker-username=lakunzy7 \
  --docker-password=ghp_NewTokenHere \
  -n authenticwrite \
  --dry-run=client -o yaml > secret-new.yaml

kubeseal -f secret-new.yaml -w sealed-secret-new.yaml

# 3. Update deployment to use new secret
kubectl patch deployment backend \
  -n authenticwrite \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret-new"}]}}}}'

# 4. Delete old secret after pods restart
kubectl delete secret ghcr-pull-secret -n authenticwrite

# 5. Rename new secret
kubectl create secret docker-registry ghcr-pull-secret \
  --from-file=.dockerconfigjson=<(kubectl get secret ghcr-pull-secret-new -n authenticwrite -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d) \
  -n authenticwrite

# 6. Update deployment back to ghcr-pull-secret
# 7. Delete ghcr-pull-secret-new
```

---

## 4. Alternative: External-Secrets Operator

If you want to use external secret management (AWS Secrets Manager, Vault, etc.):

### 4.1 Install External-Secrets

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace
```

### 4.2 Configure AWS Secrets Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: authenticwrite
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa

---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: ghcr-pull-secret
  namespace: authenticwrite
spec:
  secretStoreRef:
    name: aws-secrets
    kind: SecretStore
  target:
    name: ghcr-pull-secret
    creationPolicy: Owner
  data:
    - secretKey: .dockerconfigjson
      remoteRef:
        key: ghcr-credentials  # Name in AWS Secrets Manager
```

**Advantages:**
- Centralized secret management
- Easier rotation (update in Secrets Manager, external-secrets syncs automatically)
- Multi-cluster support (same secret store)
- Audit trail

**Disadvantages:**
- Requires AWS account + permissions
- Additional dependency (external-secrets controller)
- More complex setup

---

## 5. Best Practices

### ✅ DO

- ✅ Encrypt secrets in git (sealed-secrets or SOPS)
- ✅ Rotate secrets every 90 days
- ✅ Use separate secrets per environment (dev/staging/prod)
- ✅ Backup sealing keys securely (not in git)
- ✅ Use minimal IAM permissions (least privilege)
- ✅ Monitor secret access (audit logs)
- ✅ Use RBAC to limit who can view secrets

### ❌ DON'T

- ❌ Commit plain secrets to git
- ❌ Share sealing keys in plaintext
- ❌ Use same token for all environments
- ❌ Store secrets in ConfigMaps
- ❌ Log secrets (configure app to not log sensitive data)
- ❌ Use default/weak passwords

---

## 6. Secret Management Checklist

```
Phase 1: Setup (Now)
  [ ] Install sealed-secrets on Kind
  [ ] Install sealed-secrets on GKE
  [ ] Backup sealing key from Kind
  [ ] Sync sealing key to GKE
  [ ] Install kubeseal CLI

Phase 2: Create Secrets
  [ ] Create GHCR pull secret (plain)
  [ ] Seal GHCR pull secret
  [ ] Apply sealed secret to both clusters
  [ ] Commit sealed-secret.yaml to git
  [ ] Delete plain secret.yaml

Phase 3: Verify Secrets Work
  [ ] Deploy test pod that pulls from GHCR
  [ ] Verify pod can pull images
  [ ] Check secret is unsealed automatically
  [ ] Test on both Kind and GKE

Phase 4: Rotation Plan
  [ ] Set calendar reminder (every 90 days)
  [ ] Document rotation process
  [ ] Test rotation procedure
```

---

## 7. Summary Table

| Method | Sealed-Secrets | External-Secrets | SOPS | Vault |
|--------|---|---|---|---|
| **Setup** | Easy | Medium | Easy | Hard |
| **Storage** | In git (encrypted) | External service | In git (encrypted) | Dedicated server |
| **Rotation** | Manual | Automatic | Manual | Automatic |
| **Multi-cluster** | Need to sync keys | ✅ Built-in | ✅ Same secret | ✅ Built-in |
| **Cost** | Free | Free (if AWS) | Free | $$ |
| **Recommended for** | Simple projects | Large orgs | Teams using git | Enterprise |

---

## 8. For This Project

**Recommendation: Use Sealed-Secrets + Backup Keys**

```bash
# 1. Deploy sealed-secrets on both clusters ✓
# 2. Backup Kind's sealing key
kubectl get secret -n sealed-secrets sealed-secrets-keys -o yaml > sealing-key-backup.yaml

# 3. Sync to GKE
kubectl config use-context gke_expandox-cloudehub_europe-west1-b_cloud-cluster
kubectl apply -f sealing-key-backup.yaml

# 4. Create sealed GHCR credentials
# (See Section 1.3 above)

# 5. Commit sealed-secret.yaml to git ✓

# 6. Set calendar reminder for key rotation (every 6 months)
```

**Backup Location:** `/home/lakunzy/.kube/sealed-secrets-key.yaml` (keep offline)

---

## Reference

- [Sealed-Secrets Docs](https://github.com/bitnami-labs/sealed-secrets)
- [External-Secrets Docs](https://external-secrets.io/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [RBAC for Secrets](https://kubernetes.io/docs/concepts/security/rbac-good-practices/#secret-access)
