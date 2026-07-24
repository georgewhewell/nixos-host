pkgs:
with pkgs; {
  apple-health-ingester = callPackage ./apple-health-ingester {};
  pexctl = callPackage ./pexctl {};
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns {};
}
