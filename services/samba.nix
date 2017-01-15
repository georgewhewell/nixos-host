{ config, lib, pkgs, ... }:

{

  fileSystems."/mnt/Media" =
    { device = "bpool/root/Media";
      fsType = "zfs";
    };

  fileSystems."/mnt/Home" =
    { device = "bpool/root/Home";
      fsType = "zfs";
    };

  networking.firewall.allowPing = true;
  networking.firewall.allowedTCPPorts = [ 445 139 ];
  networking.firewall.allowedUDPPorts = [ 137 138 ];

  services.samba = {
    enable = true;
    syncPasswordsByPam = true;
    nsswins = true;
    extraConfig = ''
    guest account = nobody
    map to guest = bad user
    allow insecure wide links = yes
    '';
    shares = {
      Home =
        { path = "/mnt/Home";
          "read only" = "no";
          "valid users" = "grw";
          "browsable" = "yes";
          "max connections" = "20000";
          "follow symlinks" = "yes";
          "wide links" = "yes";
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
