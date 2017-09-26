{ config, pkgs, ... }: 

{

  imports = [
    ../modules/bitcoin.nix
  ];

    fileSystems."/var/lib/bitcoin" =
        { device = "bpool/var/bitcoin";
              fsType = "zfs";
                  };


  services.bitcoin = {
    enable = true;
  };

} 
