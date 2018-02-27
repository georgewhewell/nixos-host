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

  security.acme.certs."cache.satanic.link" = {
     email = "georgerw@gmail.com";
     postRun = ''systemctl reload nginx.service'';
  };

  services.nixBinaryCacheCache =
    {
      virtualHost = "cache.satanic.link";
      cacheDir = "/mnt/cache-cache";
      maxSize = "100g";
      resolver = "192.168.23.1";
    };

  services.netatalk = {
    enable = true;
    volumes = {
      timemachine = {
        path = "/mnt/timemachine";
        "time machine" = "yes";
        "hosts allow" = "192.168.23.0/24";
      };
    };
  };

  systemd.services.nbd-scratch = {
    wantedBy = [ "multi-user.target" ];

    serviceConfig = let
      gonbdConfig = pkgs.writeText "gonbd-config.yml" ''
    servers:
    - protocol: tcp                  # A first server, using TCP
      address: 0.0.0.0:10809        # on port 6666
      exports:                       # It has two exports
      - name: scratch                    # The first is named 'foo' and
        driver: file                 # Uses the 'file' driver
        path: /tmp/nbd       # This uses /tmp/test as the file
        workers: 4
    ''; in {
      ExecStart = ''
        ${pkgs.gonbdserver}/bin/gonbdserver -f \
          -c ${gonbdConfig} \
          -p string /var/run/gonbdserver.pid
      '';
    };
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      /export                192.168.23.0/24(rw,fsid=0,no_subtree_check)
      /export/media          192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
      /export/home           192.168.23.0/24(rw,async,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
      /export/nixos-config   192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
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
  ];

  networking.firewall.allowedUDPPorts = [
    111  # nfs?
    2049 # nfs
    138  # smb
    445  # smb
  ];

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
          "writable" = "yes";
          "public" = "yes";
          "browsable" = "yes";
          "guest ok" = "yes";
          "max connections" = "20000";
        };
    };
  };
}
