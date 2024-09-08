{ config, pkgs, ... }:


{

  boot = {
    extraModprobeConfig = ''
      options kvm_intel nested=1
      options i915 enable_psr=1 enable_fbc=1 enable_gvt=1 enable_guc=3 enable_fbc=1 fastboot=1 perf_stream_paranoid=0
    '';
    kernelModules = [ "kvm_intel" ];
    kernelParams = [ "intel_iommu=on" ];
    initrd.kernelModules = [ "i915" ];
  };

  environment.systemPackages = with pkgs; [
    libva
    clinfo
    intel-gpu-tools
    sycl-info
  ];

  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libva
      intel-media-driver
      intel-vaapi-driver # previously vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      vpl-gpu-rt # QSV on 11th gen or newer
      intel-media-sdk # QSV up to 11th gen
    ];
  };
}
