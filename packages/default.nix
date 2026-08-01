pkgs:
with pkgs; {
  apple-health-ingester = callPackage ./apple-health-ingester {};
  llm-quota-exporter = callPackage ./llm-quota-exporter {};
  pexctl = callPackage ./pexctl {};
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns {};
}
