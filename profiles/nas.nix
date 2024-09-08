{ config, pkgs, ... }:

{

  fileSystems."/mnt/Media" =
    {
      device = "bpool/root/Media";
      fsType = "zfs";
      neededForBoot = false;
    };

  fileSystems."/mnt/Home" =
    {
      device = "nvpool/root/Home";
      fsType = "zfs";
      neededForBoot = false;
    };

  fileSystems."/export/media" = {
    device = "/mnt/Media";
    options = [ "bind" ];
  };

  fileSystems."/export/home" = {
    device = "/mnt/Home";
    options = [ "bind" ];
  };

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ "bpool" ];
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

  services.nfs.server = {
    enable = true;
    exports = ''
      /export                192.168.23.1/24(rw,all_squash,fsid=0,no_subtree_check)
      /export/media          192.168.23.1/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
      /export/home           192.168.23.1/24(rw,async,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    '';
  };

  networking.firewall.allowedTCPPorts = [
    111 # nfs?
    2049 # nfs
    4000
    4001 # ipfs
    5001 # kubo api
    5080 # kubo gateway
    138 # smb
    139 # smb
    445 # smb
    548 # netatalk
    10809 # nbd

    999 # tor
    # nfs
    20048
    40531
    46675

    # kubo
    50882 # webui
  ];

  networking.firewall.allowedUDPPorts = [
    111 # nfs?
    2049 # nfs
    138 # smb
    445 # smb

    4001 # ipfs

    9999 # tor

    # nfs
    20048
    37914
    42074
  ];

  services.samba = {
    enable = true;
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
        {
          path = "/mnt/Home";
          "read only" = "no";
          "valid users" = "grw";
          "max connections" = "20000";
        };
      Media =
        {
          path = "/mnt/Media";
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
  };

  # poll scanimage -d and save to paperless directory
  # systemd.services.scanimage =
  #   let
  #     device = "escl:https://192.168.23.241:443";
  #     feeder = "/var/lib/paperless/consume";
  #   in
  #   {
  #     path = with pkgs; [ sane-airscan sane-backends curl ];
  #     serviceConfig = {
  #       ExecStartPre = ''
  #         ${pkgs.bash}/bin/bash -c "mkdir -p ${feeder}"
  #       '';
  #       User = "paperless";
  #       Group = "paperless";
  #     };
  #     script = ''
  #       while true; do
  #           FILENAME=$(date +%Y-%m-%d_%H-%M-%S).png
  #           if scanimage --resolution 200 -v -d '${device}' -o "/tmp/$FILENAME"; then
  #             mv /tmp/$FILENAME ${feeder}/
  #           else
  #             rm /tmp/$FILENAME || echo "fail 2 delete"
  #             echo "scanimage failed, skipping iteration"
  #           fi
  #           sleep 3
  #       done
  #     '';
  #     wantedBy = [ "multi-user.target" ];
  #   };

  fileSystems."/var/lib/ipfs" =
    {
      device = "nvpool/root/ipfs";
      fsType = "zfs";
      neededForBoot = false;
    };

  services.kubo = {
    enable = true;
    dataDir = "/var/lib/ipfs";
    localDiscovery = true;
    enableGC = true;
    extraFlags = [ ];
    settings = {
      API.HTTPHeaders."Access-Control-Allow-Origin" = [ "http://192.168.23.5:5001" ];
      Addresses = {
        API = [ "/ip4/192.168.23.5/tcp/5001" ];
        Gateway = [ "/ip4/192.168.23.5/tcp/5080" ];
      };
    };
  };

  systemd.services.ipfs.unitConfig.RequiresMountsFor = [ config.services.kubo.dataDir ];

  services.paperless = {
    enable = true;
    package = pkgs.paperless-ngx;
    extraConfig = {
      PAPERLESS_URL = "https://paperless.satanic.link";
    };
  };

  # services.nginx.virtualHosts."paperless.satanic.link" = {
  #   forceSSL = true;
  #   enableACME = true;
  #   locations."/" = {
  #     proxyPass = "http://localhost:28981";
  #     proxyWebsockets = true;
  #   };
  # };

}
