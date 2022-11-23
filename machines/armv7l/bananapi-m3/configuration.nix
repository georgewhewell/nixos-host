{ config, pkgs, lib, ... }:

{

  networking.hostName = "bananapi-m3";
  nix.buildCores = 4;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_allwinner;

  hardware.deviceTree = {
    enable = true;
    base =
      pkgs.runCommandNoCC "mydtb"
        { } ''
        mkdir $out
        cp ${config.boot.kernelPackages.kernel}/dtbs/sun8i-a83t-bananapi-m3.dtb $out/
      '';
    overlays = [
      /* "${pkgs.dt-overlays}/sunxi-spi-oled.dts.dtbo" */
      "${pkgs.dt-overlays}/sunxi-spi0-spidev.dts.dtbo"
    ];
  };

  systemd.services.sysinfo = {
    description = "sysinfo";
    script = ''
      ${pkgs.sysinfo}/bin/sysinfo
    '';
    wantedBy = [ ];
  };

  environment.systemPackages = [ pkgs.sysinfo ];
  boot.initrd.availableKernelModules = [ "fb_ssd1306" ];
  systemd.services."getty@tty1".enable = false;

  console = {
    font = lib.mkForce "drdos8x8";
    packages = [ pkgs.font-5x5 ];
    earlySetup = true;
  };

  imports = [
    ../common.nix
  ];

  boot.blacklistedKernelModules = [
    "sun4i_drm"
    "sun8i_tcon_top"
    "musb_hdrc"
    "videodev"
    "brcmutil"
    "sun8i_drm_hdmi"
    "brcmfmac"
    "bluetooth"
    "sun8i_codec"
  ];

}
