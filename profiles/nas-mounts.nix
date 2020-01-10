{ config, pkgs, ... }:


let
  options = [ "nofail" "rsize=32768" "wsize=32768" "nconnect=4" ];
in {

  fileSystems."/mnt/Home" =
    { device = "nixhost.lan:/home";
      fsType = "nfs";
      inherit options;
    };

  fileSystems."/mnt/Media" =
    { device = "nixhost.lan:/media";
      fsType = "nfs";
      inherit options;
    };

}
