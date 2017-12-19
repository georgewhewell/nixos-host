# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.version = 2;

  # Define on which hard drive you want to install Grub.
  boot.loader.grub.device = "/dev/sda";
  boot.initrd.checkJournalingFS = false;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.hostName = "nixos";
  networking.proxy.default = null;

  # List packages installed in system profile. To search by name, run:
  environment.systemPackages = with pkgs; [
    wget
    git
    vim
    chromium
    atom
    idea.pycharm-community
    pgadmin
  ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/cbed38da-a50a-40e0-8cf8-faf1b4d9256c";
      fsType = "ext4";
    };

  virtualisation.docker.enable = true;

  imports = [
    ./i3.nix
    ./users.nix
    ./nixos/16_03.nix
    ./roles/development.nix
  ];
}
