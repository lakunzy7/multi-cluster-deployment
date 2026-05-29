# Cloud SQL Database for application data
resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-postgres"
  database_version = "POSTGRES_15"
  region           = var.gcp_region
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL"
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
      require_ssl     = true
    }

    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    user_labels = var.labels
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "cloudopshub" {
  name     = "cloudopshub"
  instance = google_sql_database_instance.main.name
  charset  = "UTF8"
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "db_user" {
  name     = "admin"
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
}

# Private VPC connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "${var.project_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

# Secret Manager for database credentials
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_name}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = jsonencode({
    username = google_sql_user.db_user.name
    password = random_password.db_password.result
    host     = google_sql_database_instance.main.private_ip_address
    port     = 5432
    dbname   = google_sql_database.cloudopshub.name
  })
}

# Grant GKE service account access to Secret Manager
resource "google_secret_manager_secret_iam_member" "gke_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_client_config.default.project}@cloudservices.gserviceaccount.com"
}
