{ config, lib, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_4_2;
}
