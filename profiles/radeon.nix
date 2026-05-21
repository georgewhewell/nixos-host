{
  pkgs,
  lib,
  ...
}: let
  # AMDGPU HDMI VRR patches from:
  # https://lore.kernel.org/lkml/20260119011146.62302-1-tomasz.pakula.oficjalny@gmail.com/
  # Requires kernel 6.19+ (patches target linux-next function names)
  amdgpuHdmiVrrPatches = import ../packages/kernel-patches/amdgpu-hdmi-vrr {
    inherit lib;
    inherit (pkgs) fetchurl runCommand writeText;
  };
in {
  # # Use testing kernel (6.19-rc) for HDMI VRR patches compatibility
  # boot.kernelPackages = pkgs.linuxKernel.packages.linux_testing;

  # # AMDGPU HDMI VRR and Gaming Features patches
  # boot.kernelPatches = amdgpuHdmiVrrPatches.kernelPatches;
  hardware.amdgpu = {
    opencl.enable = true;
    overdrive = {
      enable = true;
      ppfeaturemask = "0xffffffff";
    };
  };

  # nixpkgs.config.rocmSupport = true;  # Set in flake.nix instead

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      libvdpau-va-gl
    ];
  };

  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  environment.systemPackages = with pkgs; [
    clinfo
    radeontop
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
    # libva-utils
  ];
}
