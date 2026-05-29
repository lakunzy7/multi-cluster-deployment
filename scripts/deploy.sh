#!/bin/bash

set -e

ENVIRONMENT=${1:-dev}
NAMESPACE="$([ "$ENVIRONMENT" = "prod" ] && echo "production" || echo "$ENVIRONMENT")"
CLUSTER=$([ "$ENVIRONMENT" = "prod" ] && echo "cloud-cluster" || echo "local-cluster")
IMAGE_TAG=${2:-latest}

echo "Deploying to $ENVIRONMENT ($CLUSTER/$NAMESPACE) with image tag: $IMAGE_TAG"

# Switch to target cluster
kubectl config use-context $CLUSTER

# Verify cluster access
kubectl get nodes || { echo "Failed to access cluster"; exit 1; }

# Create namespace if doesn't exist
kubectl get namespace $NAMESPACE || kubectl create namespace $NAMESPACE

# Update image tag in deployment
kubectl set image deployment/analytics-platform \
  -n $NAMESPACE \
  analytics=docker.io/cloudopshub/analytics-platform:$IMAGE_TAG \
  --record

# Wait for rollout
kubectl rollout status deployment/analytics-platform -n $NAMESPACE --timeout=5m

# Show deployment status
echo "Deployment complete!"
kubectl get deployment analytics-platform -n $NAMESPACE
kubectl get pods -n $NAMESPACE -l app=analytics-platform
