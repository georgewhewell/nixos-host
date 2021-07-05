{ config, pkgs, lib, ... }:

{
  networking.hostName = "nanopi-neo2";

  imports = [
    ../common.nix
  ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  system.build.dtbName = "sun50i-h5-nanopi-neo2.dtb";
  system.build.ubootDefconfig = "sun50i-h5-ddr3-spl_defconfig";

  environment.systemPackages = [
    pkgs.sysinfo
  ];

  networking.firewall.allowedTCPPorts = [ 8000 3030 ];
  hardware.deviceTree = {
    enable = true;
    base = pkgs.runCommandNoCC "mydtb"
      { } ''
      mkdir -p $out/allwinner
      cp ${config.boot.kernelPackages.kernel}/dtbs/allwinner/${config.system.build.dtbName} $out/allwinner
    '';
    overlays = [
      "${pkgs.dt-overlays}/sunxi-h5-i2c.dts.dtbo"
    ];
  };
}
