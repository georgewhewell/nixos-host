{pkgs, ...}: {
  fileSystems."/mnt/Media" = {
    device = "bpool/root/Media";
    fsType = "zfs";
    neededForBoot = false;
  };

  # fileSystems."/mnt/Home" = {
  #   device = "nvpool/root/Home";
  #   fsType = "zfs";
  #   neededForBoot = false;
  # };

  fileSystems."/export/media" = {
    device = "/mnt/Media";
    options = ["bind"];
  };

  # fileSystems."/export/home" = {
  #   device = "/mnt/Home";
  #   options = ["bind"];
  # };

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = ["bpool"];
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

  services.nfs = {
    settings = {
      nfsd.vers3 = false;
      nfsd.vers4 = true;
      nfsd."vers4.0" = false;
      nfsd."vers4.1" = false;
      nfsd."vers4.2" = true;
      nfsd.threads = 16;
    };
    server = {
      enable = true;
      exports = ''
        /export                192.168.23.1/24(rw,all_squash,fsid=0,no_subtree_check)
        /export/media          192.168.23.1/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
      '';
      #       /export/home           192.168.23.1/24(rw,async,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    };
  };

  networking.firewall.allowedTCPPorts = [
    111 # nfs?
    2049 # nfs
    4000
    4001 # ipfs
    5001 # kubo api
    5080 # kubo gateway
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

    4001 # ipfs

    9999 # tor

    # nfs
    20048
    37914
    42074
  ];

  # Fix systemd timing race condition - ensure tmpfiles runs before Samba services
  systemd.services.samba-smbd.wants = ["systemd-tmpfiles-setup.service"];
  systemd.services.samba-smbd.after = ["systemd-tmpfiles-setup.service"];
  systemd.services.samba-nmbd.wants = ["systemd-tmpfiles-setup.service"];  
  systemd.services.samba-nmbd.after = ["systemd-tmpfiles-setup.service"];

  # Ensure Samba directories exist with correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/samba 0755 root root -"
    "d /var/lib/samba/private 0755 root root -"
    "d /var/lib/samba/private/msg.sock 0700 root root -"  # Samba requires 0700 for messaging
    "d /var/cache/samba 0755 root root -"
    "d /var/log/samba 0755 root root -"
    "d /var/lock/samba 0755 root root -"
  ];

  services.samba = {
    enable = true;
    openFirewall = true;
    winbindd.enable = false; # Disable winbind for now, can enable later for domain auth
    settings = {
      global = {
        "server role" = "standalone server";
        "map to guest" = "bad user";
        security = "user";
        "server string" = "NixOS Media Server";
        "netbios name" = "nixos";
        workgroup = "WORKGROUP";
      };
      # Home = {
      #   path = "/mnt/Home";
      #   "read only" = "no";
      #   "valid users" = "grw";
      #   "max connections" = "20000";
      # };
      Media = {
        path = "/mnt/Media";
        "read only" = "yes";
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
    partOf = ["fix-media-permissions.service"];
    wantedBy = ["multi-user.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "3600";
    };
  };

  # services.sabnzbd = {
  #   enable = true;
  # };

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

  # fileSystems."/var/lib/ipfs" = {
  #   device = "nvpool/root/ipfs";
  #   fsType = "zfs";
  #   neededForBoot = false;
  # };

  # services.kubo = {
  #   enable = true;
  #   dataDir = "/var/lib/ipfs";
  #   localDiscovery = true;
  #   enableGC = true;
  #   extraFlags = [ ];
  #   settings = {
  #     API.HTTPHeaders."Access-Control-Allow-Origin" = [ "http://192.168.23.5:5001" ];
  #     Addresses = {
  #       API = [ "/ip4/192.168.23.5/tcp/5001" ];
  #       Gateway = [ "/ip4/192.168.23.5/tcp/5080" ];
  #     };
  #   };
  # };

  # services.paperless = {
  #   enable = true;
  #   package = pkgs.paperless-ngx;
  #   extraConfig = {
  #     PAPERLESS_URL = "https://paperless.satanic.link";
  #   };
  # };

  # services.nginx.virtualHosts."paperless.satanic.link" = {
  #   forceSSL = true;
  #   enableACME = true;
  #   locations."/" = {
  #     proxyPass = "http://localhost:28981";
  #     proxyWebsockets = true;
  #   };
  # };
}
