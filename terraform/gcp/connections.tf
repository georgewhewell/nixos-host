provider "google-beta" {
  credentials = file("../secrets/domain-owner-terraformer.json")
  project     = "domain-owner"
  region      = "europe-west2-c"
}
