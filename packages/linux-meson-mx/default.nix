{
  linux_testing
  , sources
}:

linux_testing.override {
  pname = "linux-meson-mx";
  kernelPatches = linux_testing.kernelPatches ++ [{
     name = "disable broken stuff";
     patch = null;
     extraConfig = ''
        WLAN_VENDOR_REALTEK n
        USB_CONN_EXTCON n
        MESON_MX_AO_ARC_MAILBOX n
        MESON_MX_AO_ARC_FIRMWARE n
        MESON_MX_AO_ARC_REMOTEPROC n
     '';
  }];
  argsOverride = rec {
    src = sources.linux_meson_mx;
    version = "5.8";
    modDirVersion = "5.8.0-rc3";
  };
}
