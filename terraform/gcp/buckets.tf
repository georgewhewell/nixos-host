resource "google_storage_bucket" "usercontent" {
  name          = "usercontent-bucket"
  project       = "domain-owner"
  location      = "europe-west2"
  storage_class = "REGIONAL"
}
