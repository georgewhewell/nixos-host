{config, ...}: {
  # cudaSupport and cudaCapabilities are set by the sysCuda builder in machines/default.nix

  services.xserver = {
    enable = false;
    videoDrivers = ["nvidia"];
  };

  hardware.graphics.enable = true;

  # Nixpkgs only adds nvidia_modeset/nvidia_drm to kernelModules when
  # services.xserver.enable is true. We run Wayland with xserver disabled,
  # so without this the boot framebuffer keeps the display at 1024x768.
  boot.kernelModules = ["nvidia_modeset" "nvidia_drm"];
  boot.extraModprobeConfig = ''
    options nvidia_drm modeset=1 fbdev=1
  '';

  hardware.nvidia = {
    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = true;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    open = true;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.latest;
  };

  # enable docker run --device=nvidia.com/gpu=all
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.daemon.settings.features.cdi = true;
}
