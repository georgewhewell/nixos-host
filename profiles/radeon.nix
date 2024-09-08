{ config, lib, pkgs, ... }:

{

  # nixpkgs.config.rocmSupport = true;

  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  hardware.amdgpu = {
    initrd.enable = true;
    opencl.enable = true;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      amdvlk
      # amf-amdgpu-pro
    ];
    extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
    ];
  };

  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  environment.systemPackages = with pkgs; [
    radeon-profile
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
  ];
}
