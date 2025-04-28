pkgs:
with pkgs; {
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns {};
  my-vpp = callPackage ./vpp {};
}
