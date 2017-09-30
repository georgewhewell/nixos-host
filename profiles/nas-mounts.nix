{ config, pkgs, ... }:

{

  fileSystems."/mnt/Home" =
    { device = "nixhost.4a:/home";
      fsType = "nfs";
      options = [ "nofail" ];
    };

}
