{ config, lib, pkgs, ... }:

{

  boot.initrd.kernelModules = [ "acpi" "thinkpad-acpi" "acpi-call" ];
  boot.kernelParams = [
    "msr.allow_writes=on"
    "cpuidle.governor=teo"
  ];

  /*
    boot.kernelPatches = [{
    name = "enable-teo";
    patch = null;
    extraConfig = ''
    CPU_IDLE_GOV_TEO y
    '';
    }];
  */

  boot.extraModulePackages = [
    config.boot.kernelPackages.acpi_call
    # config.boot.kernelPackages.tp_smapi
  ];

  environment.systemPackages = with pkgs; [
    modemmanager
    msr-tools
    networkmanagerapplet
    powertop
    libqmi
  ];

  services.geoclue2.enable = true;
  services.localtime.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  hardware.trackpoint = {
    enable = true;
    emulateWheel = true;
    speed = 250;
    sensitivity = 100;
  };

  services.clight = {
    enable = true;
  };

  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "ondemand";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      START_CHARGE_THRESH_BAT0 = 80;
      STOP_CHARGE_THRESH_BAT0 = 85;

      USB_BLACKLIST_PHONE = 1;
    };
  };

  services.xserver.libinput = {
    enable = true;
    touchpad = {
      accelSpeed = "0.1";
      naturalScrolling = true;
    };
  };

  # need networkmanager for wwan
  networking.networkmanager = {
    enable = true;
    enableFccUnlock = true;
    wifi = {
      backend = "iwd";
      powersave = true;
    };
    unmanaged = [
      "docker0"
      "rndis0"
    ];
  };

  systemd.services.modem-manager.enable = true;
  systemd.services.ModemManager = {
    wantedBy = [ "multi-user.target" ];
  };

  services.logind = {
    lidSwitch = "suspend-then-hibernate";
    lidSwitchExternalPower = "lock";
    extraConfig = ''
      # transition from suspend to hibernate after 1h
      HibernateDelaySec=3600
    '';
  };

  nix.settings.binary-caches = lib.mkForce [ "https://cache.nixos.org" ];
  services.upower.enable = true;

}
