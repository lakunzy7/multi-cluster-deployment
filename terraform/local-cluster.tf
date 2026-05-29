# Local Kubernetes Cluster Configuration
# This represents a self-managed Kubernetes cluster for development/staging
# Options: Kind, kubeadm, k3s, or minikube
#
# NOTE: Local cluster infrastructure is outside Terraform scope
# Set up locally using:
#   - Kind: kind create cluster --name local-cluster
#   - k3s: curl -sfL https://get.k3s.io | sh -
#   - kubeadm: see ../scripts/setup-control-plane.sh
#
# Store kubeconfig at ~/.kube/local-config

# Logging bucket for local cluster logs
resource "google_storage_bucket" "local_cluster_logs" {
  name          = "${var.project_name}-local-logs-${data.google_client_config.default.project}"
  location      = var.gcp_region
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
}

# Logging bucket for cloud cluster logs
resource "google_storage_bucket" "cloud_cluster_logs" {
  name          = "${var.project_name}-cloud-logs-${data.google_client_config.default.project}"
  location      = var.gcp_region
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
}
