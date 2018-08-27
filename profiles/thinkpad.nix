{ config, pkgs, ... }:

{
  imports  = [
    ../modules/auto-rotate.nix
  ];

  boot.initrd.kernelModules = [ "acpi" "thinkpad-acpi" "acpi-call" ];
  boot.kernelParams = [
    "nopti"
    "nospectre_v2"
    "l1tf=off"
    "nospec_store_bypass_disable"
    "no_stf_barrier"
  ];

  boot.extraModulePackages = [
    config.boot.kernelPackages.acpi_call
    config.boot.kernelPackages.tp_smapi
  ];

  environment.systemPackages = with pkgs; [
    alacritty
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

  hardware.auto-rotate.enable = true;

  hardware.trackpoint = {
    enable = true;
    emulateWheel = true;
    speed = 250;
    sensitivity = 100;
  };

  hardware.pulseaudio.enable = true;
  services.tlp.enable = true;

  services.xserver.libinput = {
    enable = true;
    accelSpeed = "0.1";
    naturalScrolling = true;
  };
  services.xserver.videoDrivers = [ "modesetting" ];
  # services.xserver.videoDrivers = [ "modesetting" "displaylink" ];

  sound.mediaKeys.enable = true;

  # need networkmanager for wifi
  networking.networkmanager = {
    enable = true;
    unmanaged = [
      "interface-name:usb-bridge"
      "interface-name:usb*"
    ];
  };

  # start nm applet too
  services.xserver.windowManager.i3.extraSessionCommands = ''
    ${pkgs.networkmanagerapplet}/bin/nm-applet &
  '';

  systemd.services.ModemManager = {
    wantedBy = [ "multi-user.target" ];
  };

}
