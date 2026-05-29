# CloudOpsHub Setup and Deployment Guide

## Prerequisites

- Terraform >= 1.0
- Google Cloud SDK (gcloud) configured with credentials
- Ansible >= 2.9
- kubectl >= 1.28
- Docker for building images
- GCP project with billing enabled
- Appropriate IAM permissions (Compute Admin, Kubernetes Engine Admin)

## Step 1: GCP Project Setup

```bash
# Set GCP project
export GCP_PROJECT="your-project-id"
gcloud config set project $GCP_PROJECT

# Verify authentication
gcloud auth list

# Enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable sqladmin.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable servicenetworking.googleapis.com
gcloud services enable secretmanager.googleapis.com
```

## Step 2: Infrastructure Provisioning with Terraform

```bash
cd terraform

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
gcp_project = "$GCP_PROJECT"
gcp_region  = "europe-west1"
node_count  = 3
instance_type = "e2-medium"
EOF

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -out=tfplan

# Apply infrastructure
terraform apply tfplan

# Save outputs for next steps
terraform output -json > outputs.json
```

**Key outputs:**
- `cloud_cluster_name`: GKE cluster name
- `cloud_cluster_endpoint`: Kubernetes API endpoint
- `gke_kubeconfig_command`: Command to configure kubectl
- `vpc_network`: VPC network name
- `backup_bucket`: GCS bucket for backups

## Step 3: Configure Local Cluster

### Option A: Using Kind (Development - Recommended)
```bash
# Install Kind if not already installed
GO111MODULE="on" go get sigs.k8s.io/kind@v0.20.0

# Create local cluster
kind create cluster --name local-cluster --image kindest/node:v1.28.0

# Verify cluster
kubectl cluster-info --context kind-local-cluster
```

### Option B: Using k3s (Lightweight)
```bash
# Install k3s
curl -sfL https://get.k3s.io | sh -

# Get kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/local-config
sudo chown $USER:$USER ~/.kube/local-config

# Verify cluster
export KUBECONFIG=~/.kube/local-config
kubectl get nodes
```

## Step 4: Configure Kubernetes Clusters

```bash
# Merge kubeconfigs
# Local cluster (Kind)
export KUBECONFIG=~/.kube/kind-local-cluster:~/.kube/gke-cloud-cluster

# For GKE cloud cluster
gcloud container clusters get-credentials cloud-cluster \
  --region europe-west1 \
  --project $GCP_PROJECT

# Verify both clusters accessible
kubectl get nodes --context kind-local-cluster
kubectl get nodes --context gke_${GCP_PROJECT}_europe-west1_cloud-cluster

# Create namespaces and storage classes on both clusters
for context in kind-local-cluster gke_${GCP_PROJECT}_europe-west1_cloud-cluster; do
  kubectl apply -f kubernetes/namespaces.yml --context=$context
  kubectl apply -f kubernetes/storage-class.yml --context=$context
done
```

## Step 5: Install ArgoCD (Primary Cluster)

```bash
# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD on local cluster
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values argocd-values.yml

# Expose ArgoCD API
kubectl port-forward -n argocd svc/argocd-server 8080:443 &

# Get initial admin password
argocd admin initial-password -n argocd

# Login to ArgoCD
argocd login localhost:8080 --username admin
```

## Step 6: Register Clusters with ArgoCD

```bash
# Add cloud cluster to ArgoCD
argocd cluster add <cloud-cluster-context> \
  --name cloud-cluster \
  --server https://<cloud-cluster-endpoint>

# Verify cluster registration
argocd cluster list
```

## Step 7: Configure Monitoring

```bash
# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-values.yml

# Install Loki for logs
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace logging \
  --create-namespace

# Install Jaeger for tracing
helm repo add jaegertracing https://jaegertracing.github.io
helm install jaeger jaegertracing/jaeger \
  --namespace monitoring \
  --create-namespace
```

## Step 8: Deploy Applications via ArgoCD

```bash
# Create ArgoCD Application manifest
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: analytics-platform
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/cloudopshub/app-config
    targetRevision: HEAD
    path: kubernetes/
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# Sync application
argocd app sync analytics-platform
```

## Step 9: Configure CI/CD Pipeline

```bash
# Create Docker registry secrets
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n dev

# Copy to other namespaces
kubectl get secret regcred -n dev -o yaml | sed 's/namespace: dev/namespace: staging/' | kubectl apply -f -
kubectl get secret regcred -n dev -o yaml | sed 's/namespace: dev/namespace: production/' | kubectl apply -f -

# Configure GitLab CI variables
# In GitLab: Settings → CI/CD → Variables
# DOCKER_USERNAME, DOCKER_PASSWORD, REGISTRY_URL
```

## Step 10: Configure Backup Strategy

```bash
# Install Velero for Kubernetes backups
wget https://github.com/vmware-tanzu/velero/releases/download/v1.11.0/velero-v1.11.0-linux-amd64.tar.gz
tar xzf velero-v1.11.0-linux-amd64.tar.gz
sudo mv velero-v1.11.0-linux-amd64/velero /usr/local/bin/

# Create GCP service account for Velero
gcloud iam service-accounts create velero-sa \
  --display-name "Velero Service Account"

gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member serviceAccount:velero-sa@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role roles/compute.disks.get
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member serviceAccount:velero-sa@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role roles/compute.disks.create
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member serviceAccount:velero-sa@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role roles/compute.snapshots.create
gcloud projects add-iam-policy-binding $GCP_PROJECT \
  --member serviceAccount:velero-sa@${GCP_PROJECT}.iam.gserviceaccount.com \
  --role roles/storage.admin

# Create key for service account
gcloud iam service-accounts keys create credentials-velero \
  --iam-account=velero-sa@${GCP_PROJECT}.iam.gserviceaccount.com

# Install Velero with GCP plugin
velero install \
  --provider gcp \
  --bucket $(terraform output -raw backup_bucket) \
  --secret-file ./credentials-velero \
  --plugins velero/velero-plugin-for-gcp:v1.7.0

# Create backup schedule
velero schedule create daily --schedule="0 2 * * *"
```

## Verification

```bash
# Verify cluster access
kubectl get nodes

# Check ArgoCD status
argocd app list

# Verify monitoring stack
kubectl get all -n monitoring

# Check application deployment
kubectl get deployments -n dev
kubectl get pods -n dev

# View logs
kubectl logs -n dev -l app=analytics-platform -f
```

## Cleanup

```bash
# Destroy infrastructure (BE CAREFUL!)
terraform destroy

# Delete local clusters
kind delete cluster --name local-cluster
```

## Troubleshooting

### Cluster not accessible
```bash
# Update kubeconfig for GKE
gcloud container clusters get-credentials cloud-cluster \
  --region europe-west1 \
  --project $GCP_PROJECT

# For local cluster (Kind)
kubectl cluster-info --context kind-local-cluster

# Verify access
kubectl get nodes
```

### Pods not deploying
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check resource availability
kubectl top nodes
kubectl top pods -n <namespace>
```

### ArgoCD sync issues
```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# Force sync
argocd app sync <app-name> --force
```

## Next Steps

1. Configure ingress for external access
2. Set up certificate management with Cert-Manager
3. Implement pod security policies
4. Configure auto-scaling based on metrics
5. Set up cross-region failover
