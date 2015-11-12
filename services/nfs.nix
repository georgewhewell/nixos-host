{ config, lib, pkgs, ... }:

{
  # Todo- auth :)
  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /etc/nixos		        192.168.100.0/16(rw,async,no_subtree_check,insecure)
    /storage/workspace    192.168.200.0/24(rw,async,no_subtree_check,insecure)
    /storage/Media        192.168.100.0/16(rw,async,no_subtree_check,insecure)
  '';

  services.samba = {
    enable = false;
    shares = {
      Media =
        { path = "/storage/Media";
          "read only" = "no";
          browseable = "yes";
          "guest ok" = "yes";
        };
    };
    extraConfig = ''
    guest account = grw
    map to guest = bad user
    '';
  };
}
