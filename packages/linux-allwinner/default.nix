{
  linux_testing, sources
}:

linux_testing.override {
  pname = "linux-allwinner";
  kernelPatches = linux_testing.kernelPatches ++ [{
    name = "fix realtek config";
    patch = null;
    extraConfig = ''
      WLAN_VENDOR_REALTEK n
    '';
  }
  {
    name = "reverse eink";
    patch = ./eink-reversed.patch;
  }];
  argsOverride = rec {
    src = sources.linux_megous;
    version = "5.8";
    modDirVersion = "5.8.0-rc4";
  };
}
