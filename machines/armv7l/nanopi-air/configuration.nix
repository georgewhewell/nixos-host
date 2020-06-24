{ config, pkgs, lib, ... }:

with pkgs;
let
  entking = (callPackage ../../../packages/entking { });
in
{

  networking.hostName = "nanopi-air";

  hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; lib.mkForce [
    armbian-firmware
    friendlyarm-firmware
  ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_megous;

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
    base =
      pkgs.runCommandNoCC "mydtb"
        { } ''
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
    #git
    #dtc
    #broadcom-bluetooth
    #fswebcam
    #xawtv
    #ffmpeg
    #libva-utils
    #v4l-utils
    #(python3.withPackages (ps: [ ps.luma-oled ]))
    #ffmpeg
    #v4l-utils
  ];

  hardware.opengl = {
    extraPackages = with pkgs; [ libva libva-v4l2-request ];
  };

  systemd.services.entking = {
    description = "run entking";
    script = ''
      ${entking}/bin/entking
    '';
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5";
      StartLimitIntervalSec = "0";
      StartLimitBurst = "0";
    };
  };

  systemd.services.enable-bluetooth = {
    description = "run entking";
    script = ''
      ${pkgs.devmem2}/bin/devmem2 0x1f00060 b 1
      echo 205 > /sys/class/gpio/export
      echo out > /sys/class/gpio/gpio205/direction
      echo 0 > /sys/class/gpio/gpio205/value
      echo 1 > /sys/class/gpio/gpio205/value
      sleep 0.1
      ${pkgs.bluez}/bin/btattach -B /dev/ttyS1 -S 1500000 -P bcm
    '';
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.disable-powersaving = {
    description = "disable powersave";
    script = ''
      ${pkgs.wirelesstools}/bin/iwconfig wlan0 power off
    '';
    wantedBy = [ "multi-user.target" ];
  };

  hardware.bluetooth = {
    enable = true;
  };

  imports = [
    ../common.nix
    ../../../profiles/wireless.nix
    ../../../services/miflora
  ];
}
