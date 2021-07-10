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
      KS8851 n
      CRYPTO_AEGIS128 n
    '';
  }
  {
    name = "reverse eink";
    patch = ./eink-reversed.patch;
  }
  {
    name = "a83t spi";
    patch = ./a83t-spi.patch;
  }
  {
    name = "a83t badopp";
    patch = ./a83t-badopp.patch;
  }
  ];
  argsOverride = rec {
    src = sources.linux_megous;
    version = "5.12";
    modDirVersion = "5.12.12";
  };
}
