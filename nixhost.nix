{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */

  imports =
    [
      ./containers/plex.nix
      ./containers/radarr.nix
      ./containers/sonarr.nix
      ./containers/unifi.nix
      ./profiles/common.nix
      ./profiles/headless.nix
      ./profiles/g_ether.nix
      ./profiles/home.nix
      ./profiles/uefi-boot.nix
      ./profiles/hydra-server.nix
      ./profiles/logserver.nix
      ./profiles/nas.nix
      ./services/buildfarm.nix
      ./services/nginx.nix
      ./services/docker.nix
      ./services/gogs.nix
      ./services/grafana.nix
      ./services/transmission.nix
    ];

  networking = {
    hostName = "nixhost";
    hostId = "deadbeef";
    useDHCP = true;
    useNetworkd = true;
    enableIPv6 = false;

    bridges.br0 = {
      interfaces = [ "eno1" "eno2" "eno3" "eno4" ];
    };
  };

  fileSystems."/" =
    { device = "fpool/root/nixos";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/1A02-B98B";
      fsType = "vfat";
    };

  fileSystems."/var/lib/docker" =
    { device = "fpool/root/docker";
      fsType = "zfs";
    };

  services.avahi.interfaces = [ "br0" ];

  services.sabnzbd = {
    enable = true;
    user = "transmission";
    group = "transmission";
  };

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      host all all 192.168.23.0/24 trust
    '';
  };

  networking.firewall = {
    checkReversePath = false;
    allowedTCPPorts = [ 5432 6789 9001 8080 8085 51413 ];
  };

  nix.buildCores = lib.mkDefault 24;

  virtualisation.libvirtd.enable = true;

}
