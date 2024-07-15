{ config, lib, pkgs, ... }:

let
  # sources = (import ../nix/sources.nix);
in
{

  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xffffffff"
  ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  /*
    nixpkgs.overlays = [
    (import sources.nixos-rocm)
    ];
  */

  nixpkgs.config.rocmTargets = [ "gfx1010" ];
  hardware.graphics.extraPackages = [ pkgs.rocm-opencl-icd pkgs.amdvlk ];
  # For 32 bit applications 
  hardware.graphics.extraPackages32 = with pkgs; [
    driversi686Linux.amdvlk
  ];

  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  # services.radeon-profile-daemon.enable = true;
  # environment.systemPackages = with pkgs; [ radeon-profile rocminfo rocm-opencl-runtime rocm-opencl-icd rocm-smi ];
  environment.systemPackages = with pkgs; [
    radeon-profile
    # corectrl
    rocmPackages.rocm-smi
  ];
}
