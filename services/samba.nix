{ config, lib, pkgs, ... }:
{
  services.samba = {
    enable = true;
    syncPasswordsByPam = true;
    nsswins = true;
    extraConfig = ''
    guest account = nobody
    map to guest = bad user
    '';
    shares = {
      Home =
        { path = "/mnt/Home";
          "read only" = "no";
          "valid users" = "grw";
          "browsable" = "yes";
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
