pkgs:

with pkgs;

{
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns { };
  radeon-profile-daemon = libsForQt5.callPackage ./radeon-profile-daemon { };
  libmali = callPackage ./libmali { };
  udpxy = callPackage ./udpxy { };

  my-vpp = callPackage ./vpp { };
}
