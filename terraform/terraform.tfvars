# GCP Configuration
gcp_project = "expandox-cloudehub"
gcp_region  = "europe-west1"

# Project Configuration
project_name          = "cloudopshub"
environment           = "dev"
local_cluster_name    = "local-cluster"
cloud_cluster_name    = "cloud-cluster"
kubernetes_version    = "1.28"

# Node Configuration (Spot pool)
node_count    = 2
instance_type = "e2-medium"

# Zonal GKE for free-tier control-plane credit
gcp_zone      = "europe-west1-b"

# Storage and Backup
backup_retention_days = 30
enable_monitoring     = true
