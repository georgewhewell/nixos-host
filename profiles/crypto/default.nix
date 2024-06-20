{ config, lib, pkgs, ... }:

{

  imports = [
    ./bitcoin.nix
    ./geth.nix
    ./monero.nix
  ];
}
