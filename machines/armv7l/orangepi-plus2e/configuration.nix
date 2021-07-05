{ config, pkgs, lib, ... }:

{

  networking.hostName = "orangepi-plus2e";

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_allwinner;

  environment.systemPackages = with pkgs; [
    i2c-tools
    weather
  ];

  hardware.devicetree = {
    enable = true;
    dtbName = "sun8i-h3-orangepi-plus2e";
  };

  hardware.deviceTree = {
    enable = true;
    base =
      pkgs.runCommandNoCC "mydtb"
        { } ''
        mkdir $out
        cp ${config.boot.kernelPackages.kernel}/dtbs/${config.hardware.devicetree.dtbName}.dtb $out/
      '';
    overlays = [
      "${pkgs.dt-overlays}/sunxi-h3-i2c.dts.dtbo"
      "${pkgs.dt-overlays}/sunxi-i2c-bmp280.dts.dtbo"
    ];
  };

  systemd.services.weather = {
    description = "weather";
    script = ''
      ${pkgs.weather}/bin/weather
    '';
    wantedBy = [ "multi-user.target" ];
  };

  boot.blacklistedKernelModules = [
    "drm" "sun4i_drm" "lima"
  ];

  imports = [
    ../common.nix
  ];

}
