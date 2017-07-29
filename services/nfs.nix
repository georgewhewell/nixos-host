{ config, lib, pkgs, ... }:

{

  fileSystems."/export/media" = {
    device = "/mnt/Media";
    options = ["bind"];
  };

  fileSystems."/export/images" = {
    device = "/mnt/Home/images";
    options = ["bind"];
  };
  
  fileSystems."/export/scratch" = {
    fsType = "tmpfs";
  };

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /export                192.168.23.0/24(rw,fsid=0,no_subtree_check)
    /export/media          192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
    /export/scratch        192.168.23.0/24(rw,async,nohide,all_squash,anonuid=0,anongid=0,no_acl,insecure,no_subtree_check,fsid=1)
    /export/images         192.168.23.0/24(rw,nohide,all_squash,anonuid=1000,anongid=1000,insecure,no_subtree_check)
  '';

  networking.firewall.allowedTCPPorts = [ 111 2049 ];
  networking.firewall.allowedUDPPorts = [ 111 2049 ];

}
