#!/bin/bash
set -euo pipefail

# Deploy ArgoCD + Kargo to Kind cluster
# Usage: ./scripts/deploy-argocd-kargo.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

err() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check prerequisites
log "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    err "kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v kustomize &> /dev/null; then
    err "kustomize not found. Please install kustomize."
    exit 1
fi

# Check Kind cluster exists
if ! kubectl cluster-info &> /dev/null; then
    err "No Kubernetes cluster found. Please create a Kind cluster first."
    echo "  $ kind create cluster --config=kubernetes/kind-cluster-config.yml --name cloudopshub-local"
    exit 1
fi

log "✓ kubectl and kustomize available"

# Phase 1: Deploy ArgoCD
log ""
log "=== Phase 1: Installing ArgoCD ==="

log "Creating argocd namespace..."
kubectl apply -f "$REPO_ROOT/kubernetes/argocd-namespace.yml"

log "Installing ArgoCD..."
kubectl apply -f "$REPO_ROOT/kubernetes/argocd-install.yml"

log "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/part-of=argocd \
    -n argocd \
    --timeout=300s || warn "ArgoCD pods not ready yet, continuing..."

# Phase 2: Deploy ApplicationSet
log ""
log "=== Phase 2: Deploying ApplicationSet ==="

log "Applying ApplicationSet..."
kubectl apply -f "$REPO_ROOT/argocd-apps/applicationset-authenticwrite.yaml"

log "Waiting for ApplicationSet to generate apps..."
sleep 10

log "Generated applications:"
kubectl get applications -n argocd || warn "No applications found yet"

# Phase 3: Deploy Kargo
log ""
log "=== Phase 3: Installing Kargo ==="

log "Adding Kargo Helm repository..."
helm repo add akuity https://charts.akuity.io
helm repo update

log "Creating kargo namespace..."
kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f -

log "Installing Kargo via Helm..."
helm upgrade --install kargo akuity/kargo \
    --namespace kargo \
    --create-namespace \
    --set controller.logLevel=debug \
    --set api.logLevel=debug \
    --wait \
    --timeout=5m

log "Waiting for Kargo API to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=kargo-api \
    -n kargo \
    --timeout=300s || warn "Kargo API not ready yet"

# Phase 4: Deploy Kargo Project + Warehouse + Stages
log ""
log "=== Phase 4: Configuring Kargo Project ==="

log "Applying Kargo Project..."
kubectl apply -f "$REPO_ROOT/kargo/kargo-project.yaml"

log "Verifying Kargo resources..."
kubectl get projects -n kargo
kubectl get warehouses -n kargo
kubectl get stages -n kargo

# Phase 5: Deploy Monitoring Stack
log ""
log "=== Phase 5: Installing Monitoring Stack ==="

log "Deploying Prometheus..."
kubectl apply -f "$REPO_ROOT/monitoring/prometheus-deployment.yaml"

log "Deploying Grafana..."
kubectl apply -f "$REPO_ROOT/monitoring/grafana-deployment.yaml"

log "Waiting for monitoring stack..."
kubectl wait --for=condition=ready pod \
    -l app=prometheus \
    -n monitoring \
    --timeout=300s || warn "Prometheus not ready"

kubectl wait --for=condition=ready pod \
    -l app=grafana \
    -n monitoring \
    --timeout=300s || warn "Grafana not ready"

# Phase 6: Deploy Backup & Sealed Secrets
log ""
log "=== Phase 6: Installing Backup & Secrets ==="

log "Installing Sealed Secrets..."
kubectl apply -f "$REPO_ROOT/kubernetes/sealed-secrets-install.yaml"

log "Waiting for sealed-secrets controller..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=sealed-secrets-controller \
    -n kube-system \
    --timeout=300s || warn "Sealed Secrets not ready"

log "Installing Velero (backup)..."
kubectl apply -f "$REPO_ROOT/kubernetes/velero-install.yaml"

# Summary
log ""
log "=== Deployment Summary ==="
log ""

log "ArgoCD Status:"
kubectl get deployments -n argocd

log ""
log "Kargo Status:"
kubectl get deployments -n kargo

log ""
log "Monitoring Status:"
kubectl get deployments -n monitoring

log ""
log "=== Access URLs ==="
log ""

log "ArgoCD UI:"
echo "  $ kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "  → https://localhost:8080"
echo "  Username: admin"
echo "  Password: \$(kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

log ""
log "Kargo UI:"
echo "  $ kubectl port-forward -n kargo svc/kargo 8080:8080"
echo "  → http://localhost:8080"

log ""
log "Grafana:"
echo "  $ kubectl port-forward -n monitoring svc/grafana 3000:3000"
echo "  → http://localhost:3000"
echo "  Username: admin"
echo "  Password: (check MONITORING_RUNBOOK.md)"

log ""
log "✅ Deployment complete!"
log ""
log "Next steps:"
log "1. Set up GitHub webhooks: see docs/GITHUB-WEBHOOKS-SETUP.md"
log "2. Test image build: push to trigger build-push-images.yml workflow"
log "3. Monitor Kargo: kubectl logs -n kargo deployment/kargo-api -f"
log "4. Check pods: kubectl get pods -A"
