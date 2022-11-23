pkgs:

with pkgs;

{
  akula = (callPackage ./akula { });
  i2c-ch341-usb = (callPackage ./i2c-ch341-usb { });
  libdvbcsa = callPackage ./libdvbcsa { };
  optimism-dtl = (callPackage ./optimism-dtl { });
  public-ip-sync-google-clouddns = callPackage ./public-ip-sync-google-clouddns { };
  radeon-profile-daemon = libsForQt5.callPackage ./radeon-profile-daemon { };
}
