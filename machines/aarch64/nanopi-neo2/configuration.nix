{ config, pkgs, lib, ... }:

{
  networking.hostName = "nanopi-neo2";

  imports = [
    ../common.nix
  ];

  system.build.dtbName = "sun50i-h5-nanopi-neo2.dtb";
  system.build.ubootDefconfig = "sun50i-h5-ddr3-spl_defconfig";

  environment.systemPackages = [
    pkgs.i2c-tools
  ];

  networking.firewall.allowedTCPPorts = [ 8000 ];
  hardware.deviceTree = {
    enable = true;
    base = pkgs.runCommandNoCC "mydtb" {} ''
      mkdir -p $out/allwinner
      cp ${config.boot.kernelPackages.kernel}/dtbs/allwinner/${config.system.build.dtbName} $out/allwinner
    '';
    overlays = [
      "${pkgs.dt-overlays}/sunxi-h5-i2c.dts.dtbo"
    ];
  };
}
