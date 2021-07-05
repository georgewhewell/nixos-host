{ config, pkgs, lib, ... }:

{
  # modprobe: FATAL: Module ahci not found
  boot.initrd.availableKernelModules = lib.mkForce [ "ip_tables" ];
  boot.initrd.includeDefaultModules = false;

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

  services.consul = {
    enable = lib.mkForce false;
    interface = {
      bind = "wlan0";
      advertise = "wlan0";
    };
  };

  networking.firewall.enable = false;
  networking.wireless.interfaces = [ "wlan0" ];

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
    /* farmbot */
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
      ExecStartPre="${pkgs.coreutils}/bin/sleep 30";
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
