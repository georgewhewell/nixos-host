{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */

  imports =
    [
      ./containers/radarr.nix
      ./containers/sonarr.nix
      ./containers/unifi.nix

      ./profiles/automation.nix
      ./profiles/common.nix
      ./profiles/bridge-interfaces.nix
      ./profiles/headless.nix
      ./profiles/home.nix
      ./profiles/uefi-boot.nix
      ./profiles/logserver.nix
      ./profiles/nas.nix

      ./services/buildfarm.nix
      ./services/docker.nix
      ./services/gogs.nix
      ./services/hydra.nix
      ./services/grafana.nix
      ./services/nginx.nix
      ./services/transmission.nix
      ./services/virt/host.nix
      ./services/virt/vfio.nix
    ];

  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  boot.kernelParams = [
    # has ups, can be a bit dirty
    # "zfs.zfs_dirty_data_max_percent=50"
    # "zfs.zfs_txg_timeout=15"

    # optane zil/l2arc
    "zfs.zfs_immediate_write_sz=${toString (128 * 1024 * 1024)}"
    "zfs.l2arc_feed_min_ms=15"
    "zfs.l2arc_noprefetch=1"
    "zfs.l2arc_write_boost=${toString (2 * 1024 * 1024 * 1024)}"
    "zfs.l2arc_write_max=${toString (2 * 1024 * 1024 * 1024)}"
    "zfs.zfs_arc_max=12884901888"
  ];

  networking = {
    hostName = "nixhost";
    hostId = "deadbeef";

    useDHCP = false;
    enableIPv6 = false;

    interfaces.br0 = {
      useDHCP = true;
    };

    bridges.br0 = {
      interfaces = [ "eno1" "eno2" "eno3" "eno4" ];
    };
  };

  services.consul.extraConfig = { server = true; };
  services.consul.interface =
    let interface = "br0"; in {
      advertise = interface;
      bind = interface;
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

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      host all all 192.168.23.0/24 trust
    '';
    extraPlugins = with pkgs; [
      timescaledb
    ];
    extraConfig = ''
      shared_preload_libraries = 'timescaledb'
    '';
  };

  networking.firewall = {
    checkReversePath = false;
    allowedTCPPorts = [ 5432 6789 9001 8080 8085 8880 51413 ];
  };

  nix.buildCores = lib.mkDefault 24;

}
