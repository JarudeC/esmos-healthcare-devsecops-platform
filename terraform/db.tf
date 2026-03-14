resource "google_sql_database_instance" "odoo" {
  name             = "${var.project_name}-postgres"
  database_version = "POSTGRES_15"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc]

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_HDD"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled = true
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "odoo" {
  name     = "odoo"
  instance = google_sql_database_instance.odoo.name
}

resource "google_sql_user" "odoo" {
  name     = "odooadmin"
  instance = google_sql_database_instance.odoo.name
  password = var.db_admin_password
}

output "db_host" {
  value = google_sql_database_instance.odoo.private_ip_address
}
