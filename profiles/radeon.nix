{ config, lib, pkgs, ... }:

let
  sources = (import ../nix/sources.nix);
in {

  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  /*
  nixpkgs.overlays = [
    (import sources.nixos-rocm)
  ];
  */

  nixpkgs.config.rocmTargets = [ "gfx1010" ];
  hardware.opengl.extraPackages = [ pkgs.rocm-opencl-icd ];

  services.radeon-profile-daemon.enable = true;
  # environment.systemPackages = with pkgs; [ radeon-profile rocminfo rocm-opencl-runtime rocm-opencl-icd rocm-smi ];
  environment.systemPackages = with pkgs; [ radeon-profile corectrl ];
}
