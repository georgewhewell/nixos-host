{ config, pkgs, lib, inputs, ... }:

{
  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/graphical.nix
      ../../../services/buildfarm-slave.nix
      inputs.apple-silicon.nixosModules.default
    ];


  fileSystems."/" =
    {
      device = "/dev/disk/by-uuid/12e505b1-6ba5-46e6-b1cb-ae0d42044231";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-uuid/2A39-1614";
      fsType = "vfat";
    };

  services.prometheus.exporters = {
    node = {
      enable = true;
      openFirewall = true;
    };
  };

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
  # high-resolution display
  # hardware.video.hidpi.enable = lib.mkDefault true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;

  hardware = {
    asahi = {
      extractPeripheralFirmware = false;
      useExperimentalGPUDriver = true;
      experimentalGPUInstallMode = "overlay";
      withRust = true;
    };
    opengl = {
      enable = true;
      driSupport32Bit = lib.mkForce false;
    };
  };

  services.hardware.bolt.enable = true;

  sconfig = {
    profile = "server";
    home-manager.enable = true;
    home-manager.enableGraphical = false;
  };

  services.usbmuxd = {
    enable = true;
  };

  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  networking.hostName = "air";

  zramSwap = {
    enable = true;
    priority = 10;
    algorithm = "lz4";
    swapDevices = 4;
    memoryPercent = 30;
    memoryMax = 1024 * 1024 * 1024;
  };

  services.openssh.enable = true;
  system.stateVersion = "23.05"; # Did you read the comment?

}

