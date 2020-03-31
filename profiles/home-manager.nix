{ config, pkgs, ... }:

{

  imports = [ 
    <home-manager/nixos>
  ];

  home-manager.users.grw = { ... }: {
    hostId = config.networking.hostName;
    imports = [
      ../home/common.nix
      ../home/linux.nix
      ../home/graphical.nix
    ];
  };

}
