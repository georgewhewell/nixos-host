{config, pkgs, ...}: {
  # DisplayLink / EVDI support for USB displays
  services.xserver.videoDrivers = ["displaylink" "modesetting"];
  boot.extraModulePackages = [config.boot.kernelPackages.evdi];

  # Don't bounce dlm.service on every nixos-rebuild switch — restarting
  # it tears down the EVDI displays, and Hyprland doesn't re-enumerate
  # the new DRM cards without a full session restart. Reboot or
  # explicit `systemctl restart dlm` to pick up an upgrade.
  systemd.services.dlm.restartIfChanged = false;
}
