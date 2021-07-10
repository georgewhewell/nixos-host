{ config, pkgs, lib, ... }:

{

  networking.hostName = "nanopi-air";

  hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; lib.mkForce [
    armbian-firmware
    friendlyarm-firmware
  ];

  system.build.ubootDefconfig = "nanopi_neo_air_defconfig";

  boot.kernelParams = [
    "boot.shell_on_fail"
    "console=ttyS0,115200"
    "earlycon=uart,mmio32,0x1c28000"
  ];
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_allwinner;

  console = {
    earlySetup = true;
    font = lib.mkForce "drdos8x6";
    extraTTYs = [ "ttyS0" ];
  };


  services.consul = {
    enable = lib.mkForce false;
    interface = {
      bind = "wlan0";
      advertise = "wlan0";
    };
  };

  networking.firewall.enable = false;

  hardware.devicetree = {
    enable = true;
    dtbName = "sun8i-h3-nanopi-neo-air";
  };

  hardware.deviceTree = {
    enable = true;
    filter = "*nanopi-neo-air*";
    overlays = [
      { name = "i2c"; dtsFile = "${pkgs.dt-overlays}/sunxi-h3-i2c.dts"; }
      { name = "bt";  dtsFile = "${pkgs.dt-overlays}/nanopi-air-bt.dts"; }
    ];
  };

  environment.systemPackages =  with pkgs; [
    rfcomm
    farmbot
    i2c-tools
    sysfsutils
    dtc
    htop
  ];

  systemd.services.farmbot = {
    description = "plow the fields and scatter";
    environment = {
      RUST_LOG = "info";
    };
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      Type = "idle";
      ExecStart = "${pkgs.farmbot}/bin/farmbot /home/grw/config.toml";
    };
    after = [ "enable-bluetooth.service" ];
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.enable-bluetooth = {
    description = "enable bluetooth";
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

  hardware.bluetooth = {
    enable = true;
  };

  imports = [
    ./powersave.nix
    ../common.nix
    ../../../profiles/wireless.nix
  ];
}
