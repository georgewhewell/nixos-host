{
  config,
  lib,
  pkgs,
  ...
}: {
  boot = {
    kernelParams = ["amdgpu.gpu_recovery=1" "ixgbe.allow_unsupported_sfp=1,1"];
  };

  # nixpkgs.config is set in pkgsFor (flake.nix) - now read-only
  environment.variables.NIXPKGS_ALLOW_UNFREE = "1";

  security.sudo.extraConfig = "Defaults lecture=never";

  systemd.tmpfiles.rules = ["e /nix/var/log - - - 30d"];

  networking.hostId = builtins.substring 0 8 (builtins.hashString "md5" config.networking.hostName);

  nix = {
    daemonCPUSchedPolicy = "idle";
    extraOptions = ''
      experimental-features = nix-command flakes ca-derivations
    '';
  };

  services = {
    earlyoom = {
      enable = lib.mkDefault true;
      # Bias the OOM killer toward heavy build/compile processes and
      # away from session-critical ones. Without this, earlyoom walks
      # the oom_score list and kills small user-session daemons
      # (dbus-broker, gpg-agent, ...) before it gets to the multi-GB
      # clang invocation that's actually responsible for the pressure.
      extraArgs = [
        "--prefer"
        "^(cc1|cc1plus|clang|clang\\+\\+|ld|ld\\.lld|ld\\.gold|hipcc|hipclang|gcc|g\\+\\+|rustc|cargo|nix-build|nix-daemon|ninja|make|cmake|python3?)$"
        "--avoid"
        "^(systemd|init|sshd|sway|swaylock|swayidle|Hyprland|hypridle|kwin|kwin_wayland|gnome-shell|plasmashell|Xwayland|Xorg|dbus-broker|dbus-broker-lau|pipewire|wireplumber|gpg-agent|ssh-agent|seatd|polkitd|NetworkManager|wpa_supplicant|chronyd|journald|logind|udevd)$"
      ];
    };
  };

  # Only run one OOM killer — earlyoom is the one we're tuning.
  systemd.oomd.enable = lib.mkDefault false;

  # Make nix-daemon (and its build children, which inherit) the
  # preferred OOM victim under memory pressure. Heavy clang/HIP
  # compilations should die before the user session does.
  systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = lib.mkDefault 500;
}
