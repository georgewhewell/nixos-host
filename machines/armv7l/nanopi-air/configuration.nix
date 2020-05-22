{ config, pkgs, lib, ... }:

with pkgs;

let
  entking = (callPackage ../../../packages/entking { });
in {

  networking.hostName = "nanopi-air";

  hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; lib.mkForce [
    armbian-firmware
    friendlyarm-firmware
  ];

  system.build.ubootDefconfig = "nanopi_neo_air_defconfig";

  boot.kernelParams = [ "boot.shell_on_fail" "console=ttyS0,115200" "earlycon=uart,mmio32,0x1c28000" ];

  console = {
    earlySetup = true;
    font = lib.mkForce "drdos8x6";
    extraTTYs = [ "ttyS0" ];
  };

  powerManagement.cpuFreqGovernor = lib.mkForce "powersave";

  services.consul.interface = {
    bind = "wlan0";
    advertise = "wlan0";
  };

  networking.firewall.enable = false;

  hardware.devicetree = {
    enable = true;
    dtbName = "sun8i-h3-nanopi-neo-air";
  };

  hardware.deviceTree = {
    enable = true;
    base = pkgs.runCommandNoCC "mydtb" {} ''
      mkdir $out
      cp ${config.boot.kernelPackages.kernel}/dtbs/${config.hardware.devicetree.dtbName}.dtb $out/
    '';
    overlays = [
      "${pkgs.dt-overlays}/sunxi-h3-i2c.dts.dtbo"
      "${pkgs.dt-overlays}/nanopi-air-usbhost.dts.dtbo"
      /* "${pkgs.dt-overlays}/sunxi-uart3-rtscts.dts.dtbo" */
      "${pkgs.dt-overlays}/nanopi-air-bt.dts.dtbo"
      "${pkgs.dt-overlays}/sunxi-i2c0-oled.dts.dtbo"

    #  "${pkgs.dt-overlays}/sunxi-pca9685.dts.dtbo"
    ];
  };

  environment.systemPackages = [
    i2c-tools
    devmem2
    git
    dtc
    broadcom-bluetooth
    fswebcam
    xawtv
    ffmpeg
    libva-utils
    v4l-utils
    #(python3.withPackages (ps: [ ps.luma-oled ]))
    #ffmpeg
    #v4l-utils
  ];

  systemd.services.entking = {
    description = "run entking";
    script = ''
      ${entking}/bin/entking
    '';
    wantedBy = [ "multi-user.target" ];
  };

  hardware.bluetooth = {
    enable = true;
  };

  imports = [
    ../common.nix
    ../../../profiles/wireless.nix
  ];
}
