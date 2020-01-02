{ config, pkgs, ... }:

{

  imports = [ 
    <home-manager/nixos>
  ];

  home-manager.users.grw = { ... }: {
    imports = [
      ../home/common.nix
    ];
  };

}
