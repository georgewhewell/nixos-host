{pkgs, ...}: {
  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  hardware.amdgpu = {
    initrd.enable = true;
    opencl.enable = true;
    # crashes gpu?!?!
    # amdvlk.enable = true;
  };

  nixpkgs.config.rocmSupport = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  environment.systemPackages = with pkgs; [
    clinfo
    radeontop
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
  ];
}
