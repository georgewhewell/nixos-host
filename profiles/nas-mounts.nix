{ config, pkgs, ... }:

{

  fileSystems."/mnt/Home" =
    { device = "nixhost.4a:/home";
      fsType = "nfs";
      options = [ "nofail" ];
    };

  fileSystems."/mnt/nixhostconfig" =
    { device = "nixhost.4a:/nixos-config";
      fsType = "nfs";
      options = [ "nofail" ];
    };

}
