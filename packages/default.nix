pkgs:
with pkgs; {
  apple-health-ingester = callPackage ./apple-health-ingester {};
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns {};
}
