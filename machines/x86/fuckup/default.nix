{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */
  sconfig = {
    profile = "desktop";
    home-manager = {
      enable = true;
      enableGraphical = true;
      #      enableVscodeServer = true;
    };
  };

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/development.nix
      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/home.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/graphical.nix
      ../../../profiles/radeon.nix
      ../../../profiles/intel-gfx.nix
      ../../../profiles/fastlan.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/buildfarm-executor.nix
      ../../../services/jellyfin.nix

      ../../../services/virt/host.nix
      # ../../../services/virt/vfio.nix
    ];

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_skylake;
  #boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [
    "libata.force=4.00:noncq"
    "libata.force=4.00:3.0Gbps"
    "libata.force=5.00:noncq"
    "libata.force=5.00:3.0Gbps"
  ];

  system.stateVersion = "22.11";

  # sconfig.optimism =
  #   {
  #     enable = true;
  #     dataDir = "/var/lib/optimism";
  #   };

  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "f2fs";
    };

  fileSystems."/home/grw" =
    {
      device = "/dev/mapper/vg1-home";
      fsType = "f2fs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  environment.etc."OpenCL/vendors" = {
    mode = "symlink";
    source = "/run/opengl-driver/etc/OpenCL/vendors";
  };

  nix.settings.max-jobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  networking = {
    hostName = "fuckup";
    wireless.enable = false;
    useDHCP = false;

    firewall = {
      enable = true;
      allowedTCPPortRanges = [{ from = 5000; to = 5005; } { from = 50000; to = 60000; }];
      allowedUDPPortRanges = [{ from = 6000; to = 6005; } { from = 35000; to = 65535; }];
      allowedUDPPorts = [ 5353 ];
      allowedTCPPorts = [
        9100
        10809
        8880
        8080
        /* shairport */
        3689
        5353

        8096 # jellyfin
      ];
      checkReversePath = false;
      extraCommands = ''
        ${pkgs.iptables}/bin/iptables -I INPUT -p igmp -j ACCEPT
      '';
    };

    interfaces.br0 = {
      useDHCP = true;
    };

    bridges.br0 = {
      interfaces = [
        "enp0s31f6" # onboard ethernet
        # "enp4s0f0np0" # sfp28
        "enp4s0f1np1" # sfp28
      ];
    };
  };

  # boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv7l-linux" ];
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.enableUnstable = true;

  /*
    environment.systemPackages = with pkgs; [ openrgb ];
    services.udev.extraRules = let
    orig = builtins.fetchurl {
    url = "https://gitlab.com/CalcProgrammer1/OpenRGB/-/raw/master/60-openrgb.rules";
    };
    patched = pkgs.runCommandNoCC "remove-chmod" {} ''
    sed '/chmod/d' ${orig} > $out
    '';
    in builtins.readFile patched;
  */

  /*
    virtualisation.kvmgt = {
    enable = false;
    vgpus = {
    "i915-GVTg_V5_4" = {
    uuid = "a297db4a-f4c2-11e6-90f6-d3b88d6c9525";
    };
    };
    };
  */

  # nix = {
  #   # hydra doesnt like /nix/store in buildfarm-executor so add it here
  #   buildMachines = [{
  #     hostName = "/nix/store";
  #     supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
  #     maxJobs = 2;
  #     speedFactor = 2;
  #     systems = [ "builtin" "x86_64-linux" "i686-linux" "aarch64-linux" "armv7l-linux" ];
  #   }];
  # };
}
