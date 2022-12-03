{ config, pkgs, lib, ... }:

{
  /*
    nixhost: xeon-d microserver
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
  };

  deployment.targetHost = "192.168.23.1";

  imports =
    [
      ../../../containers/radarr.nix
      ../../../containers/sonarr.nix
      ../../../containers/unifi.nix

      ../../../profiles/bridge-interfaces.nix
      ../../../profiles/common.nix
      #    ../../../profiles/development.nix
      ../../../profiles/headless.nix
      ../../../profiles/home.nix
      ../../../profiles/logserver.nix
      ../../../profiles/nas.nix
      ../../../profiles/uefi-boot.nix
      ../../../profiles/router.nix

      ../../../services/buildfarm-slave.nix
      ../../../services/docker.nix
      ../../../services/grafana.nix
      ../../../services/home-assistant/default.nix
      ../../../services/nginx.nix
      ../../../services/transmission.nix
    ];

  # some incompatibility with sata controller and samsung 870 qvo?
  systemd.services.disable-sata-ssd-ncq = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      Restart = "no";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c "echo 1 > /sys/block/sde/device/queue_depth && echo 1 > /sys/block/sdf/device/queue_depth"
      '';
    };
  };

  # boot.kernelPackages = pkgs.linuxPackages_latest_lto_broadwell;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  fileSystems."/var/lib/lighthouse" =
    {
      device = "fpool/root/lighthouse-mainnet";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  services.lighthouse = {
    beacon = {
      enable = true;
      dataDir = "/var/lib/lighthouse";
      execution = {
        address = "127.0.0.1";
        port = 8551;
        jwtPath = "/run/keys/LIGHTHOUSE_JWT";
      };
    };
    extraArgs = ''--checkpoint-sync-url="https://mainnet.checkpoint.sigp.io"'';
  };

  deployment.keys =
    {
      "LIGHTHOUSE_JWT" = {
        keyCommand = [ "pass" "erigon-gpg" ];
        destDir = "/run/keys";
        uploadAt = "pre-activation";
      };
    };

  fileSystems."/var/lib/akula-mainnet" =
    {
      device = "fpool/root/akula-mainnet";
      fsType = "zfs";
      options = [ "nofail" ];
    };

  services.akula = {
    enable = true;
    openFirewall = true;
    jwtPath = "/run/keys/LIGHTHOUSE_JWT";
    dataDir = "/var/lib/akula-mainnet";
  };

  # boot.kernelPackages = pkgs.linuxPackages_latest_lto_broadwell;
  boot.kernelModules = [
    "ipmi_devintf"
    "ipmi_si"
  ];

  boot.supportedFilesystems = [ "zfs" ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" "armv7l-linux" ];
  boot.kernelParams = [

    # optane zil/l2arc
    "zfs.zfs_immediate_write_sz=${toString (128 * 1024 * 1024)}"
    "zfs.l2arc_feed_min_ms=15"
    "zfs.l2arc_nopreFfetch=1"
    "zfs.l2arc_write_boost=${toString (2 * 1024 * 1024 * 1024)}"
    "zfs.l2arc_write_max=${toString (2 * 1024 * 1024 * 1024)}"
    "zfs.zfs_arc_max=12884901888"
  ];

  networking = {
    hostName = "nixhost";
    hostId = lib.mkForce "deadbeef";
    firewall.allowedTCPPorts = [ 30303 ];
  };

  # services.consul.extraConfig = { server = true; bootstrap_expect = 1; };
  # services.consul.interface =
  #   let interface = "br0"; in
  #   {
  #     advertise = interface;
  #     bind = interface;
  #   };

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

  # fileSystems."/mnt/scratch" =
  #   {
  #     device = "/dev/mapper/vg0-scratch";
  #     fsType = "f2fs";
  #   };

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
  # system.activationScripts = {
  #   mnt = {
  #     text = ''
  #       if [ ! -d /mnt/scratch/postgresql/13 ] ; then
  #         mkdir -p /mnt/scratch/postgresql/13
  #         chown -R postgres:postgres /mnt/scratch/postgresql
  #       fi
  #     '';
  #     deps = [ ];
  #   };
  # };
  # services.postgresql = {
  #   # dataDir = "/mnt/scratch/postgresql/14";
  #   enable = true;
  #   enableTCPIP = true;
  #   authentication = ''
  #     local all all trust
  #     host all all 192.168.23.0/24 trust
  #   '';
  #   settings = {
  #     max_wal_size = "4GB";
  #   };
  # };

  networking.firewall = {
    checkReversePath = false;
    # allowedTCPPorts = [ 5432 6789 9001 8080 8085 8880 51413 ];
  };

  nix.settings.build-cores = lib.mkDefault 24;

}
