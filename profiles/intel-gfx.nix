{
  config,
  pkgs,
  ...
}: {
  boot = {
    extraModprobeConfig = ''
      options kvm_intel nested=1
      options i915 enable_psr=1 enable_fbc=1 enable_gvt=1 enable_guc=3
    '';
    kernelModules = ["kvm_intel"];
    kernelParams = ["intel_iommu=on"];
    initrd.kernelModules = ["i915"];
  };

  environment.systemPackages = with pkgs; [
    libva
    clinfo
    intel-gpu-tools
    sycl-info
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libva
      intel-media-driver
      libva-vdpau-driver
      libvdpau-va-gl
      intel-compute-runtime
      vpl-gpu-rt
      intel-ocl
    ];
  };
}
