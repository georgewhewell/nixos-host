{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */

  imports =
    [
      ./profiles/common.nix
      ./profiles/home.nix
      ./profiles/nas.nix
      ./profiles/uefi-boot.nix
      ./profiles/logserver.nix
      ./profiles/headless.nix
      ./profiles/hydra-server.nix
      ./containers/unifi.nix
      ./containers/sonarr.nix
      ./containers/radarr.nix
      ./containers/plex.nix
      ./services/gogs.nix
      ./services/buildfarm.nix
      ./services/grafana.nix
      ./services/nginx.nix
      ./services/prometheus.nix
      ./services/transmission.nix
      ./services/docker.nix
      ./services/bitcoind.nix
    ];

  networking = {
    hostName = "nixhost";
    hostId = "deadbeef";
    useDHCP = true;
    bridges.br0 = {
      rstp = true;
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

  services.nix-serve = {
    enable = true;
    secretKeyFile = "/etc/nix/signing-key.sec";
  };

  services.avahi.interfaces = [ "br0" ];

  services.sabnzbd = {
    enable = true;
    user = "transmission";
    group = "transmission";
  };

  networking.firewall = {
    checkReversePath = false;
    allowedTCPPorts = [ 6789 9001 8080 51413 ];
  };

  nix.buildCores = lib.mkDefault 24;

  virtualisation.libvirtd.enable = true;

  services.disnix.enable = true;
  services.disnix.useWebServiceInterface = true;

}
