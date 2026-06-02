{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  npu = inputs.nix-amd-npu.packages.${pkgs.stdenv.hostPlatform.system};

  # xdna-driver 2.21.75 (the only tag AMD leaves published) calls XRT APIs
  # that only exist on later XRT-2.21 branch commits, so the stock xrt
  # release in nix-amd-npu fails to build. Pin xrt and xrt-plugin-amdxdna
  # to the commit that xdna-driver's 1.7 release branch uses as its
  # submodule. See https://github.com/robcohen/nix-amd-npu/issues/2.
  xrtSrc = pkgs.fetchFromGitHub {
    owner = "Xilinx";
    repo = "XRT";
    rev = "89b2f18e7060be7487595b8800f729589b0e83ee";
    hash = "sha256-nQuR8lZufaT4YPrCD7eFqdBTRf/K6Q3NRHlu0hYHHt0=";
    fetchSubmodules = true;
  };

  xrtFixed = npu.xrt.overrideAttrs (_: {src = xrtSrc;});

  xrtPluginFixed =
    (npu.xrt-plugin-amdxdna.override {xrt = xrtFixed;}).overrideAttrs
    (_: {inherit xrtSrc;});

  xrtAmdxdnaFixed = pkgs.symlinkJoin {
    name = "xrt-amdxdna-${xrtFixed.version}";
    paths = [xrtFixed xrtPluginFixed];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      cd $out/opt/xilinx/xrt/lib
      ln -sf "${xrtPluginFixed}/opt/xilinx/xrt/lib/libxrt_driver_xdna.so.2" .
      ln -sf "${xrtPluginFixed}/opt/xilinx/xrt/lib/libxrt_driver_xdna.so.${xrtPluginFixed.pluginVersion}" .

      # The top-level $out/bin/<tool> symlinks land outside the installed
      # tree, which breaks XRT's wrapper — it uses $(dirname $0) to locate
      # the unwrapped loader and that resolves to /run/current-system/sw/bin/
      # when called via PATH. Replace those symlinks with makeWrapper
      # forwarders that exec the real wrapper at its installed path.
      for tool in xrt-smi xclbinutil aiebu-asm aiebu-dump; do
        target="$out/opt/xilinx/xrt/bin/$tool"
        if [ -e "$target" ]; then
          rm -f "$out/bin/$tool"
          makeWrapper "$target" "$out/bin/$tool"
        fi
      done
    '';
  };

  fastflowlmFixed = npu.fastflowlm.override {xrt = xrtFixed;};
in {
  boot.kernelModules = ["amdxdna"];
  boot.extraModulePackages = lib.optional (lib.versionOlder config.boot.kernelPackages.kernel.version "7.0") (
    (npu.amdxdna-driver).override {
      kernel = config.boot.kernelPackages.kernel;
    }
  );
  hardware.firmware = lib.optional (lib.versionOlder config.boot.kernelPackages.kernel.version "7.0") npu.amdxdna-firmware;

  environment.systemPackages = [
    fastflowlmFixed
    xrtAmdxdnaFixed
  ];

  environment.variables.XILINX_XRT = "${xrtAmdxdnaFixed}/opt/xilinx/xrt";

  services.udev.extraRules = ''
    SUBSYSTEM=="accel", KERNEL=="accel[0-9]*", GROUP="video", MODE="0660"
  '';

  security.pam.loginLimits = [
    {
      domain = "@video";
      type = "soft";
      item = "memlock";
      value = "unlimited";
    }
    {
      domain = "@video";
      type = "hard";
      item = "memlock";
      value = "unlimited";
    }
  ];

  assertions = [
    {
      assertion = config.boot.kernelPackages.kernelAtLeast "6.10";
      message = "AMD NPU support requires kernel 6.10 or newer.";
    }
  ];
}
