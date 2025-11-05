{pkgs, ...}: {
  boot.kernelParams = [
    "amdgpu.ppfeaturemask=0xffffffff"
  ];

  hardware.amdgpu = {
    opencl.enable = true;
    overdrive = {
      enable = true;
      ppfeaturemask = "0xffffffff";
    };
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
