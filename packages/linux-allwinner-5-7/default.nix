{
  linux_latest, sources
}:

linux_latest.override {
  pname = "linux-allwinner";
  kernelPatches = linux_latest.kernelPatches ++ [
  {
    name = "enable RTL uart";
    patch = null;
    extraConfig = ''
      BT_HCIUART_RTL y
    '';
  }
  {
    name = "fix realtek config";
    patch = null;
    extraConfig = ''
      WLAN_VENDOR_REALTEK n
    '';
  }
  {
    name = "reverse eink";
    patch = ./eink-reversed.patch;
  }
  {
    name = "export of_chosen";
    patch = ./v4-1-5-of-Add-EXPORT_SYMBOL-for-of_chosen.diff;
  }];
  argsOverride = rec {
    src = sources.linux_allwinner_5_7;
    version = "5.7";
    modDirVersion = "5.7.10";
  };
}
