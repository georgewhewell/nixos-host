{ config, lib, pkgs, ... }:

{
  # Todo- auth :)
  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /etc/nixos		  192.168.100.0/16(rw,async,no_subtree_check,insecure)
    /storage/workspace    192.168.100.0/16(rw,async,no_subtree_check,insecure)
    /storage/Media        192.168.100.0/16(rw,async,no_subtree_check,insecure)
  '';
}
