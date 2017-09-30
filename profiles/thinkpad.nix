{ config, pkgs, ... }:

{

 boot.initrd.kernelModules = ["acpi" "thinkpad-acpi" "acpi-call"];
 boot.extraModulePackages = [
   config.boot.kernelPackages.acpi_call
   config.boot.kernelPackages.tp_smapi
 ];

 hardware.trackpoint = {
    enable = true;
    emulateWheel = true;
    speed = 250;
    sensitivity = 140;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  services.xserver.libinput.enable = true;

  services.tlp.enable = true;
  networking.networkmanager.enable = true;

  systemd.services.ModemManager = {
    wantedBy = [ "multi-user.target" ];
  };

}
