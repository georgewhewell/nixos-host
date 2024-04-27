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
  ];

  networking.localCommands = ''
    ${pkgs.procps}/bin/sysctl -w dev.i915.perf_stream_paranoid=0
  '';

  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      libva
      intel-compute-runtime
      # intel-media-driver # LIBVA_DRIVER_NAME=iHD
      # (vaapiIntel.override { enableHybridCodec = true; })
      # libvdpau-va-gl
      intel-media-driver
      intel-ocl
      onevpl-intel-gpu
    ];
  };
}
