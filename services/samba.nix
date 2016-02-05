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
      nixos =
        { path = "/etc/nixos";
          "read only" = "no";
          /*"valid_users" = "%S";*/
        };
      Home =
        { path = "/mnt/Home";
          "read only" = "no";
          "valid users" = "grw";
          "browsable" = "yes";
        };
      Media =
        { path = "/mnt/Media";
          "writable" = "yes";
          "public" = "yes";
          "browsable" = "yes";
          "guest ok" = "yes";
        };
    };
  };
}
