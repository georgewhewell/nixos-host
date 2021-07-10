{
  linux_latest
  , sources
}:

linux_latest.override {
  pname = "linux-amlogic";
  kernelPatches = linux_latest.kernelPatches ++ [{
    name = "enable staging media drivers";
    patch = null;
    extraConfig = ''
      STAGING_MEDIA y
    '';
  }];
  argsOverride = rec {
    src = sources.linux_amlogic;
    version = "5.9";
    modDirVersion = "5.9.0-rc7";
  };
}
