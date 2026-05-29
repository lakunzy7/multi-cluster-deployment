# Quick Start Guide

## 5-Minute Setup

### Prerequisites
```bash
# Install tools
brew install terraform gcloud kubectl helm

# Authenticate with GCP
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 1. Provision Infrastructure (3 min)
```bash
cd terraform
cat > terraform.tfvars <<EOF
gcp_project = "YOUR_PROJECT_ID"
gcp_region  = "europe-west1"
EOF

terraform init
terraform apply
```

### 2. Configure Clusters (2 min)
```bash
# Local cluster (Kind)
kind create cluster --name local-cluster

# GKE credentials
gcloud container clusters get-credentials cloud-cluster --region europe-west1

# Merge kubeconfigs
export KUBECONFIG=~/.kube/kind-local-cluster:~/.kube/gke

# Create namespaces
kubectl apply -f kubernetes/namespaces.yml
```

### 3. Deploy Monitoring
```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
```

## Next Steps

1. **Install ArgoCD** (see SETUP.md Step 5)
2. **Deploy Applications** (see DEPLOYMENT_RUNBOOK.md)
3. **Configure Monitoring Dashboards** (see MONITORING_RUNBOOK.md)

## Common Commands

```bash
# Check cluster status
kubectl get nodes
kubectl top nodes

# View pods across namespaces
kubectl get pods -A

# Check ArgoCD status
argocd app list

# View logs
kubectl logs -n <namespace> -l app=<app-name> -f

# Execute commands in pod
kubectl exec -it <pod-name> -n <namespace> -- bash
```

## Troubleshooting

### Can't connect to GKE cluster?
```bash
gcloud container clusters get-credentials cloud-cluster --region europe-west1
```

### Pod stuck in pending?
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl top nodes  # Check resource availability
```

### Database connection error?
```bash
# Check Cloud SQL instance
gcloud sql instances describe cloudopshub-postgres

# Get connection info
gcloud sql instances describe cloudopshub-postgres --format="value(privateIpAddress)"
```

## Documentation

- **Full Setup**: See [SETUP.md](SETUP.md)
- **Architecture Details**: See [ARCHITECTURE.md](ARCHITECTURE.md)
- **Deployment Operations**: See [DEPLOYMENT_RUNBOOK.md](DEPLOYMENT_RUNBOOK.md)
- **Monitoring**: See [MONITORING_RUNBOOK.md](MONITORING_RUNBOOK.md)
