variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cloudopshub"
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for cloud resources"
  type        = string
  default     = "europe-west1"
}

variable "gcp_zone" {
  description = "GCP zone for the zonal GKE cluster (lab/free-tier optimization)"
  type        = string
  default     = "europe-west1-b"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "local_cluster_name" {
  description = "Name of local Kubernetes cluster"
  type        = string
  default     = "local-cluster"
}

variable "cloud_cluster_name" {
  description = "Name of cloud-managed Kubernetes cluster (GKE)"
  type        = string
  default     = "cloud-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for clusters"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Number of worker nodes in the GKE Spot node pool"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "GCP machine type for nodes"
  type        = string
  default     = "e2-medium"
}

variable "enable_monitoring" {
  description = "Enable monitoring stack deployment"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "labels" {
  description = "Common labels for all resources"
  type        = map(string)
  default = {
    project     = "cloudopshub"
    managed-by  = "terraform"
    environment = "infrastructure"
  }
}
