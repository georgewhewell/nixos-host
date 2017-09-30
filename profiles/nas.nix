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

  fileSystems."/export/nixos-config" = {
    device = "/etc/nixos";
    options = ["bind"];
  };

  fileSystems."/mnt/timemachine" =
    { device = "bpool/root/timemachine";
      fsType = "zfs";
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

  services.nfs.server = {
    enable = true;
    # statdPort = 4000;
    # lockdPort = 4001;
    # mountdPort = 4002;
    exports = ''
      /export                192.168.23.0/24(rw,fsid=0,no_subtree_check)
      /export/media          192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
      /export/nixos-config   192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    '';
  };

  networking.firewall.allowPing = true;

  networking.firewall.allowedTCPPorts = [
    111  # nfs?
    2049 # nfs
    4000 # nfs/statd
    4001 # nfs/lockd
    4002 # nfs/mountd
    138  # smb
    445  # smb
    548  # netatalk
  ];

  networking.firewall.allowedUDPPorts = [
    111  # nfs?
    2049 # nfs
    4000 # nfs/statd
    4001 # nfs/lockd
    4002 # nfs/mountd
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
