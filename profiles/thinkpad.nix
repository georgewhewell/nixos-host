{ config, pkgs, ... }:

{

 boot.initrd.kernelModules = ["acpi" "thinkpad-acpi" "acpi-call"];
 boot.extraModulePackages = [
   config.boot.kernelPackages.acpi_call
   config.boot.kernelPackages.tp_smapi
 ];

 environment.systemPackages = with pkgs; [
   alacritty
   auto-rotate
   modemmanager
   msr-tools
   networkmanagerapplet
   powertop
   rfkill
 ];

 hardware.bluetooth = {
   enable = true;
   powerOnBoot = false;
 };

 hardware.sensor.iio.enable = true;

 hardware.trackpoint = {
    enable = true;
    emulateWheel = true;
    speed = 250;
    sensitivity = 140;
  };

  hardware.pulseaudio.enable = true;
  services.tlp.enable = true;

  services.xserver.libinput = {
    enable = true;
    accelSpeed = "0.1";
  };

  sound.mediaKeys.enable = true;

  # need networkmanager for wifi
  networking.networkmanager = {
    enable = true;
    unmanaged = [
      "interface-name:usb-bridge"
      "interface-name:usb*"
    ];
  };

  systemd.services.ModemManager = {
    wantedBy = [ "multi-user.target" ];
  };

}
