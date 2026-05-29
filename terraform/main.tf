terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

# Data source for current GCP project
data "google_client_config" "default" {}
data "google_compute_zones" "available" {
  project = var.gcp_project
  region  = var.gcp_region
}

# VPC and Networking for Cloud Cluster
resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.compute,
    google_project_service.container
  ]
}

resource "google_compute_subnetwork" "cluster" {
  count         = 2
  name          = "${var.project_name}-subnet-${count.index + 1}"
  ip_cidr_range = "10.0.${count.index + 1}.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id

  private_ip_google_access = true
}

# Firewall rules for cluster communication
resource "google_compute_firewall" "cluster_internal" {
  name    = "${var.project_name}-cluster-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = ["10.0.0.0/16"]
}

resource "google_compute_firewall" "cluster_external" {
  name    = "${var.project_name}-cluster-external"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["6443", "443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Enable required Google Cloud APIs
resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "sql" {
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

# GKE Cluster (Cloud Cluster)
resource "google_container_cluster" "cloud" {
  name     = var.cloud_cluster_name
  location = var.gcp_region

  initial_node_count = var.node_count
  network            = google_compute_network.main.name

  node_config {
    machine_type = var.instance_type
    disk_size_gb = 100
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Network configuration
  network_policy {
    enabled = true
  }

  # Cluster features
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  # Cluster autoscaling
  cluster_autoscaling {
    enabled = true
    resource_limits {
      resource_type = "cpu"
      minimum       = 1
      maximum       = 10
    }
    resource_limits {
      resource_type = "memory"
      minimum       = 1
      maximum       = 64
    }
  }

  # Security
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  depends_on = [
    google_project_service.container,
    google_compute_network.main
  ]
}

# Node pool for additional autoscaling
resource "google_container_node_pool" "cloud_pool" {
  name           = "${var.cloud_cluster_name}-pool"
  cluster        = google_container_cluster.cloud.name
  location       = var.gcp_region
  initial_node_count = var.node_count

  autoscaling {
    min_node_count = var.node_count - 1
    max_node_count = var.node_count + 2
  }

  node_config {
    machine_type = var.instance_type
    disk_size_gb = 100

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      "cluster" = var.cloud_cluster_name
    }
  }
}

# GCS bucket for backups
resource "google_storage_bucket" "backups" {
  name          = "${var.project_name}-backups-${data.google_client_config.default.project}"
  location      = var.gcp_region
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  uniform_bucket_level_access = true
}
