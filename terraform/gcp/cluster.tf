resource "google_container_node_pool" "preempt_pool" {
  name     = "preempt-pool"
  project  = "domain-owner"
  cluster  = google_container_cluster.play.name
  location = "europe-west2-c"
  node_count = 3

  node_config {
    preemptible  = true
    machine_type = "e2-small"
    disk_size_gb = 15
    tags         = ["www-node"]
    oauth_scopes = [
      "compute-rw",
      "storage-rw",
      "logging-write",
      "monitoring",
      "https://www.googleapis.com/auth/ndev.clouddns.readwrite",
    ]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

resource "google_container_cluster" "play" {
  name                     = "play"
  project                  = "domain-owner"
  location                 = "europe-west2-c"
  remove_default_node_pool = true
  min_master_version       = "1.15.11"

  addons_config {
    http_load_balancing {
      disabled = true
    }

    horizontal_pod_autoscaling {
      disabled = true
    }
  }

  lifecycle {
    ignore_changes = [node_pool]
  }

  node_pool {
    name = "default-pool"
  }
}
