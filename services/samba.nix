{ config, lib, pkgs, ... }:
{
  services.samba = {
    enable = true;
    syncPasswordsByPam = true;
    extraConfig = ''
    guest account = nobody
    map to guest = bad user
    '';
    shares = {
      nixos =
        { path = "/etc/nixos";
          "read only" = "no";
          "valid_users" = "%S";
        };
      Home =
        { path = "/mnt/Home";
          "read only" = "no";
          "valid_users" = "%S";
        };
      Media =
        { path = "/mnt/Media";
          "read only" = "no";
          "browsable" = "yes";
          "guest_ok" = "yes";
        };
    };
  };
}
