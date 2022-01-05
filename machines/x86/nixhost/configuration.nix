{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */

  imports =
    [
      ../../../containers/radarr.nix
      ../../../containers/sonarr.nix
      /* ../../../containers/jupyter.nix */

      ../../../profiles/common.nix
      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/headless.nix
      ../../../profiles/home.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/logserver.nix
      ../../../profiles/crypto.nix
      ../../../profiles/nas.nix
      ../../../profiles/logserver.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/docker.nix
      ../../../services/deconz.nix
      ../../../services/home-assistant/default.nix
      # ../../../services/hydra.nix
      ../../../services/grafana.nix
      ../../../services/nginx.nix
      ../../../services/metabase.nix
      ../../../services/transmission.nix
      ../../../services/virt/host.nix
    ];

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_5_10;
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

  services.consul.extraConfig = { server = true; bootstrap_expect = 1; };
  services.consul.interface =
    let interface = "br0"; in
    {
      advertise = interface;
      bind = interface;
    };

  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/disk/by-label/EFI";
      fsType = "vfat";
    };

  fileSystems."/mnt/scratch" =
    {
      device = "/dev/mapper/vg0-scratch";
      fsType = "f2fs";
    };


  # fileSystems."/var/lib/docker" =
  #   {
  #     device = "fpool/root/docker";
  #     fsType = "zfs";
  #   };

  # fileSystems."/var/lib/postgresql" =
  #   {
  #     device = "/dev/nvme1n1p2";
  #     fsType = "ext4";
  #     options = [ "noatime" "discard" "nobarrier" ];
  #   };

  # virtualisation.docker.storageDriver = "zfs";
  system.activationScripts = {
      mnt = {
        text = ''
          if [ ! -d /mnt/scratch/postgresql/13 ] ; then
            mkdir -p /mnt/scratch/postgresql/13
            chown -R postgres:postgres /mnt/scratch/postgresql
          fi
        '';
        deps = [];
      };
   };

  services.postgresql = {
    dataDir = "/mnt/scratch/postgresql/13";
    package = pkgs.postgresql_13;
    enable = true;
    enableTCPIP = true;
    authentication = ''
      local all all trust
      host all all 192.168.23.0/24 trust
    '';
    extraPlugins = with pkgs; [
      timescaledb
    ];
    settings = {
      max_wal_size = "4GB";
    };
  };

  networking.firewall = {
    checkReversePath = false;
    allowedTCPPorts = [ 5432 6789 9001 8080 8085 8880 51413 ];
  };

  nix.buildCores = lib.mkDefault 24;

}
