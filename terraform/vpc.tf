resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name          = "gke-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.main.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.10.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.20.0.0/16"
  }

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "db" {
  name          = "db-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.main.id

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "ingress" {
  name          = "ingress-subnet"
  ip_cidr_range = "10.0.3.0/24"
  region        = var.region
  network       = google_compute_network.main.id
}

# Private Service Access for Cloud SQL
resource "google_compute_global_address" "private_ip" {
  name          = "${var.project_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]
}

# Firewall: deny all ingress from internet to GKE nodes
resource "google_compute_firewall" "deny_internet_ingress" {
  name    = "${var.project_name}-deny-internet"
  network = google_compute_network.main.name

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
  priority      = 1000
}

# Firewall: allow internal traffic
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.project_name}-allow-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "all"
  }

  source_ranges = ["10.0.0.0/8"]
  priority      = 900
}
