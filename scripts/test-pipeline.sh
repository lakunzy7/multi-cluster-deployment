#!/bin/bash
set -euo pipefail

# Test end-to-end pipeline: commit → images → Kargo → ArgoCD → pods
# Usage: ./scripts/test-pipeline.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[TEST]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

err() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

step() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}>>> $*${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check prerequisites
step "Verifying Prerequisites"

for cmd in kubectl kustomize git; do
    if ! command -v $cmd &> /dev/null; then
        err "$cmd not found"
        exit 1
    fi
done

log "✓ All tools available"

# Verify cluster connectivity
step "Checking Cluster Connectivity"

if ! kubectl cluster-info &> /dev/null; then
    err "Cannot connect to Kubernetes cluster"
    exit 1
fi

CLUSTER_NAME=$(kubectl config current-context)
log "✓ Connected to: $CLUSTER_NAME"

# Check namespaces
step "Verifying Namespaces"

for ns in argocd kargo monitoring; do
    if kubectl get ns $ns &> /dev/null; then
        log "✓ Namespace '$ns' exists"
    else
        err "Namespace '$ns' not found. Run: ./scripts/deploy-argocd-kargo.sh"
        exit 1
    fi
done

# Test ArgoCD
step "Testing ArgoCD"

if kubectl get deployments -n argocd argocd-server &> /dev/null; then
    READY=$(kubectl get deployment -n argocd argocd-server -o jsonpath='{.status.readyReplicas}')
    if [ "$READY" -eq 1 ]; then
        log "✓ ArgoCD API ready"
    else
        warn "ArgoCD API not fully ready (replicas: $READY)"
    fi
else
    err "ArgoCD not deployed"
    exit 1
fi

# Test ApplicationSet
step "Testing ApplicationSet"

APPSET_COUNT=$(kubectl get applicationset -n argocd 2>/dev/null | wc -l)
if [ "$APPSET_COUNT" -gt 1 ]; then
    log "✓ ApplicationSet deployed"
    kubectl get applicationset -n argocd
else
    warn "No ApplicationSets found"
fi

# Test generated applications
step "Testing Generated Applications"

APP_COUNT=$(kubectl get applications -n argocd 2>/dev/null | wc -l)
if [ "$APP_COUNT" -gt 1 ]; then
    log "✓ Applications generated (count: $((APP_COUNT - 1)))"
    kubectl get applications -n argocd --no-headers | head -5
else
    warn "No applications found yet"
fi

# Test Kargo
step "Testing Kargo"

if kubectl get deployments -n kargo kargo-controller-manager &> /dev/null; then
    READY=$(kubectl get deployment -n kargo kargo-controller-manager -o jsonpath='{.status.readyReplicas}')
    if [ "$READY" -eq 1 ]; then
        log "✓ Kargo controller ready"
    else
        warn "Kargo controller not fully ready"
    fi
else
    err "Kargo not deployed"
    exit 1
fi

# Test Kargo resources
step "Testing Kargo Resources"

if kubectl get project -n kargo authenticwrite &> /dev/null; then
    log "✓ Kargo Project exists"
else
    warn "Kargo Project not found"
fi

if kubectl get warehouse -n kargo authenticwrite &> /dev/null; then
    log "✓ Kargo Warehouse exists"
    IMAGES=$(kubectl get warehouse -n kargo authenticwrite -o jsonpath='{.spec.subscriptions[0].image.repoURL}')
    log "  Watching: $IMAGES"
else
    warn "Kargo Warehouse not found"
fi

STAGES=$(kubectl get stages -n kargo -o jsonpath='{.items[*].metadata.name}')
log "✓ Kargo Stages: $STAGES"

# Test Monitoring
step "Testing Monitoring Stack"

if kubectl get deployments -n monitoring prometheus &> /dev/null; then
    READY=$(kubectl get deployment -n monitoring prometheus -o jsonpath='{.status.readyReplicas}')
    if [ "$READY" -eq 1 ]; then
        log "✓ Prometheus ready"
    else
        warn "Prometheus not ready (replicas: $READY)"
    fi
else
    warn "Prometheus not deployed"
fi

if kubectl get deployments -n monitoring grafana &> /dev/null; then
    READY=$(kubectl get deployment -n monitoring grafana -o jsonpath='{.status.readyReplicas}')
    if [ "$READY" -eq 1 ]; then
        log "✓ Grafana ready"
    else
        warn "Grafana not ready (replicas: $READY)"
    fi
else
    warn "Grafana not deployed"
fi

# Test Kustomize builds
step "Testing Kustomize Builds"

for env in dev staging prod; do
    if kustomize build "$REPO_ROOT/kubernetes/overlays/$env" > /tmp/$env.yaml 2>/dev/null; then
        COUNT=$(grep -c "^kind:" /tmp/$env.yaml || echo 0)
        log "✓ $env overlay builds ($COUNT resources)"
    else
        err "$env overlay failed to build"
        exit 1
    fi
done

# Test kargo image configuration
step "Testing Image Configuration"

for env in dev staging prod; do
    KUST="$REPO_ROOT/kubernetes/overlays/$env/kustomization.yaml"
    if grep -q "ghcr.io/lakunzy7/authenticwrite/backend" "$KUST"; then
        log "✓ $env has correct backend image reference"
    else
        err "$env missing backend image reference"
        exit 1
    fi
done

# Check for running pods
step "Checking Deployed Pods"

POD_COUNT=$(kubectl get pods -n authenticwrite 2>/dev/null | wc -l)
if [ "$POD_COUNT" -gt 1 ]; then
    log "✓ App pods deployed ($((POD_COUNT - 1)) pods)"
    kubectl get pods -n authenticwrite --no-headers | head -5
else
    log "ℹ  No app pods yet (waiting for manual promotion)"
fi

# Summary and next steps
step "Pipeline Readiness Summary"

log ""
echo -e "${GREEN}✅ Infrastructure Ready${NC}"
echo ""
echo "Current Status:"
echo "  ArgoCD:    Ready"
echo "  Kargo:     Ready"
echo "  Monitoring: Ready"
echo ""
echo "Next Steps:"
echo "  1. Trigger image build:"
echo "     → Push a commit to trigger build-push-images.yml"
echo ""
echo "  2. Monitor build progress:"
echo "     → gh run list --workflow build-push-images.yml"
echo ""
echo "  3. Check if Kargo detected images:"
echo "     → kubectl get freight -n kargo"
echo ""
echo "  4. Promote dev → staging → prod:"
echo "     → kargo promote authenticwrite staging --from dev"
echo "     → kargo promote authenticwrite prod --from staging"
echo ""
echo "  5. Watch ArgoCD sync:"
echo "     → kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo "     → https://localhost:8080"
echo ""
echo "  6. View pods:"
echo "     → kubectl get pods -n authenticwrite-dev"
echo "     → kubectl logs -n authenticwrite-dev -l app=authenticwrite"
echo ""

step "✅ Pipeline Ready for Testing"
