{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/development.nix
      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/home.nix
      ../../../profiles/home-manager.nix
      ../../../profiles/nas-mounts.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/g_ether.nix
      ../../../profiles/graphical.nix
      ../../../profiles/radeon.nix
      ../../../profiles/intel-gfx.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/buildfarm-executor.nix
      ../../../services/docker.nix
      ../../../services/jellyfin.nix
      ../../../containers/plex.nix
      ../../../services/virt/host.nix
      #../../../services/virt/vfio.nix
    ];

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

  fileSystems."/mnt/uniswap" = {
      device = "//192.168.25.2/home/uniswap";
      fsType = "cifs";
      options = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in ["${automount_opts},credentials=/etc/nixos/smb-secrets"];
  };

  environment.etc."OpenCL/vendors" = {
    mode = "symlink";
    source = "/run/opengl-driver/etc/OpenCL/vendors";
  };

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  services.consul.interface =
    let interface = "br0"; in
    {
      advertise = interface;
      bind = interface;
    };

  networking = {
    hostName = "fuckup";
    hostId = "deadbeef";
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
    };

    interfaces.br0 = {
      useDHCP = true;
    };

    bridges.br0 = {
      interfaces = [
        "enp0s31f6" # onboard ethernet
        #"enp4s0f0"  # sfp+
        #"enp4s0f1"  # sfp+
      ];
    };
  };

  services.xserver = {
    useGlamor = false; # off is tearing; on is lag
  };

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

  nix = {
    # hydra doesnt like /nix/store in buildfarm-executor so add it here
    buildMachines = [{
      hostName = "/nix/store";
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      maxJobs = 2;
      speedFactor = 2;
      systems = [ "builtin" "x86_64-linux" "i686-linux" ];
    }];
  };
}
