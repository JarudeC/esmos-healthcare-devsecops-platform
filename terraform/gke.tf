resource "google_container_cluster" "main" {
  name     = "${var.project_name}-gke"
  location = "${var.region}-a" # Single zone to save costs

  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.gke.name

  # Use separately managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Free tier: no cluster management fee for one zonal cluster
  deletion_protection = false
}

resource "google_container_node_pool" "default" {
  name     = "default-pool"
  location = "${var.region}-a"
  cluster  = google_container_cluster.main.name

  initial_node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  node_config {
    machine_type = "e2-medium" # 2 vCPU, 4GB RAM — similar to Standard_B2s
    disk_size_gb = 30

    tags = ["gke-node"]

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

output "cluster_name" {
  value = google_container_cluster.main.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}
