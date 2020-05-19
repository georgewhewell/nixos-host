resource "google_compute_disk" "default" {
  name    = "postgres-disk"
  project = "domain-owner"
  type    = "pd-ssd"
  zone    = "europe-west2-c"
  size    = 5
}
