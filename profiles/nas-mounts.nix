{ config, pkgs, ... }:


let
  options = [ "nofail" "rsize=32768" "wsize=32768" ];
in {

  fileSystems."/mnt/Home" =
    { device = "nixhost.4a:/home";
      fsType = "nfs";
      inherit options;
    };

  fileSystems."/mnt/nixhostconfig" =
    { device = "nixhost.4a:/nixos-config";
      fsType = "nfs";
      inherit options;
    };

}
