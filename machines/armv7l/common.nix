{ config, lib, pkgs, ... }:

{
  # takes ages
  security.polkit.enable = lib.mkForce false;
  services.udisks2.enable = lib.mkForce false;

  # sd card image must be <2gb
  # environment.systemPackages = with pkgs; lib.mkForce [ bash nix coreutils systemd zsh ];

  boot.kernelPatches = [
    {
      name = "nanopi-air";
      patch = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/armbian/build/master/patch/kernel/sunxi-dev/board-nanopiair-h3-camera-wifi-bluetooth-otg.patch";
        sha256 = "1sm02p8n5j0jqisvf9lbwp6z52q35j5r4b9kxwqdw1dslh7j5xg0";
      };
    }
  ];

  imports = [
    ../common-arm.nix
  ];
}
