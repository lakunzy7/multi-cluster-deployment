output "cloud_cluster_name" {
  description = "Cloud GKE cluster name"
  value       = google_container_cluster.cloud.name
}

output "cloud_cluster_endpoint" {
  description = "Cloud GKE cluster endpoint"
  value       = google_container_cluster.cloud.endpoint
}

output "cloud_cluster_ca_certificate" {
  description = "Cloud GKE cluster CA certificate"
  value       = google_container_cluster.cloud.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cloud_cluster_location" {
  description = "Cloud GKE cluster location"
  value       = google_container_cluster.cloud.location
}

output "gke_kubeconfig_command" {
  description = "Command to configure kubectl for the zonal GKE cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.cloud.name} --zone ${google_container_cluster.cloud.location} --project ${var.gcp_project}"
}

output "vpc_network" {
  description = "VPC network name"
  value       = google_compute_network.main.name
}

output "backup_bucket" {
  description = "GCS bucket for backups"
  value       = google_storage_bucket.backups.name
}

output "terraform_state_file" {
  description = "Path to Terraform state file"
  value       = "terraform.tfstate"
}
