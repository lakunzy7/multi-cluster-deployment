# Terraform settings, providers, and backend live in backend.tf + providers.tf.
# This file holds the actual GCP infrastructure: VPC, GKE (zonal + Spot), GCS buckets.
#
# Lab/free-tier optimizations:
#   - GKE is ZONAL (location = var.gcp_zone) -> qualifies for the monthly free-tier
#     control-plane credit (~$73/mo saved vs regional)
#   - Default node pool removed; custom pool uses Spot e2-medium ×2 (~$22/mo)
#   - No Cloud SQL: Postgres will run as an in-cluster StatefulSet

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

# GKE Cluster (Cloud Cluster) — ZONAL for free-tier credit
resource "google_container_cluster" "cloud" {
  name     = var.cloud_cluster_name
  location = var.gcp_zone

  # Best practice: create the cluster with a tiny default pool, then replace it
  # with a custom Spot node pool defined below.
  remove_default_node_pool = true
  initial_node_count       = 1

  network = google_compute_network.main.name

  network_policy {
    enabled = true
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

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

# Custom node pool: 2 × e2-medium Spot nodes, no autoscaling
resource "google_container_node_pool" "cloud_pool" {
  name       = "${var.cloud_cluster_name}-pool"
  cluster    = google_container_cluster.cloud.name
  location   = var.gcp_zone
  node_count = var.node_count

  node_config {
    machine_type = var.instance_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    # Slash compute cost (~60-90% vs on-demand). Spot nodes can be preempted
    # at any time; that's fine for a lab. Workloads should tolerate restarts.
    spot = true

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

    labels = {
      "cluster" = var.cloud_cluster_name
      "tier"    = "spot"
    }
  }
}

# GCS bucket for backups (still useful even without Cloud SQL — for app data,
# k8s manifests, velero snapshots, etc.)
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
