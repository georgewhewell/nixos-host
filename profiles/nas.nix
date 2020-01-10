{ config, pkgs, ... }:

{

  fileSystems."/mnt/Media" =
    { device = "bpool/root/Media";
      fsType = "zfs";
    };

  fileSystems."/mnt/Home" =
    { device = "bpool/root/Home";
      fsType = "zfs";
    };

  fileSystems."/export/media" = {
    device = "/mnt/Media";
    options = ["bind"];
  };

  fileSystems."/export/home" = {
    device = "/mnt/Home";
    options = ["bind"];
  };

  fileSystems."/export/nixos-config" = {
    device = "/etc/nixos";
    options = ["bind"];
  };

  fileSystems."/mnt/timemachine" =
    { device = "bpool/root/timemachine";
      fsType = "zfs";
    };

  fileSystems."/mnt/cache-cache" =
    { device = "bpool/root/nix-cache";
      fsType = "zfs";
  };

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ "fpool" "bpool" ];
  };

  services.zfs.autoSnapshot = {
    enable = true;
    daily = 7;
    weekly = 4;
    monthly = 6;
  };

  services.zfs.trim = {
    enable = true;
    interval = "weekly";
  };

  services.nixBinaryCacheCache =
    {
      enable = true;
      virtualHost = "cache.satanic.link";
      cacheDir = "/mnt/cache-cache";
      maxSize = "100g";
      resolver = "192.168.23.1";
    };
/*
  services.netatalk = {
    enable = true;
    volumes = {
      timemachine = {
        path = "/mnt/timemachine";
        "time machine" = "yes";
        "hosts allow" = "192.168.23.0/24";
      };
    };
  }; */

  services.nfs.server = {
    enable = true;
    exports = ''
      /export                192.168.23.0/24(rw,fsid=0,no_subtree_check)
      /export/media          192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
      /export/home           192.168.23.0/24(rw,async,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    '';
  };

  networking.firewall.allowPing = true;

  networking.firewall.allowedTCPPorts = [
    111  # nfs?
    2049 # nfs
    4000 4001 4002 4003
    138  # smb
    445  # smb
    548  # netatalk
    10809 # nbd

    # nfs
    20048
    40531
    46675
  ];

  networking.firewall.allowedUDPPorts = [
    111  # nfs?
    2049 # nfs
    138  # smb
    445  # smb

    # nfs
    20048
    37914
    42074
  ];

  systemd.services.nbd-scratch = {
    wantedBy = [ "multi-user.target" ];

    serviceConfig = let
      nbdConfig = pkgs.writeText "nbd-config.conf" ''
        # This is a comment
        [generic]
            # The [generic] section is required, even if nothing is specified
            # there.
            # When either of these options are specified, nbd-server drops
            # privileges to the given user and group after opening ports, but
            # _before_ opening files.
        [scratch]
            exportname = scratch
            timeout = 30
            temporary = true
            filesize = ${toString (16 * 1024 * 1024 * 1024)}
            sparse_cow = true
    ''; in {
      ExecStart = ''
        ${pkgs.nbd}/bin/nbd-server -d -C ${nbdConfig}
      '';
    };
  };

  services.samba = {
    enable = true;
    syncPasswordsByPam = true;
    extraConfig = ''
      guest account = nobody
      map to guest = bad user

      load printers = no
      printing = bsd
      printcap name = /dev/null
      disable spoolss = yes

      dos charset = cp866
      unix charset = UTF8

      server multi channel support = yes
      aio read size = 1
      aio write size = 1
    '';
    shares = {
      Home =
        { path = "/mnt/Home";
          "read only" = "no";
          "valid users" = "grw";
          "max connections" = "20000";
        };
      Media =
        { path = "/mnt/Media";
          "read only" = "yes";
          "writable" = "no";
          "public" = "yes";
          "browsable" = "yes";
          "guest ok" = "yes";
          "max connections" = "20000";
        };
    };
  };

  # todo: downloader user
  systemd.services.fix-media-permissions = {
    serviceConfig = {
      Type = "oneshot";
      Restart = "no";
      ExecStart = ''
        ${pkgs.bash}/bin/bash -c "chmod -R 777 /mnt/Media"
      '';
    };
  };

  systemd.timers.fix-media-permissions = {
      partOf = [ "fix-media-permissions.service" ];
      wantedBy = [ "multi-user.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "3600";
      };
  };

  services.sabnzbd = {
    enable = true;
    user = "transmission";
    group = "transmission";
  };

}
