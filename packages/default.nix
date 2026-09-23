pkgs:
with pkgs; {
  apple-health-ingester = callPackage ./apple-health-ingester {};
  gpsd-prometheus-exporter = callPackage ./gpsd-prometheus-exporter {};
  inherit (pkgs) llm-quota-exporter;
  vpp-prometheus-exporter = callPackage ./vpp-prometheus-exporter {};
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns {};
}
