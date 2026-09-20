# Full-fat fleet baseline for workstation/server-class members.
# The shareable identity layer (users, ssh, zsh, hosts, locale, gc)
# lives in fleet-core.nix so memory-constrained members (NanoKVM) can
# import just that; this file adds everything with a hardware or
# closure-size cost.
{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./fleet-core.nix
    ./watchdog.nix
  ];

  boot.swraid.mdadmConf = "MAILADDR root";

  environment.systemPackages =
    (with pkgs; [
      rsync
      ethtool
      # iotop
      # ncdu
      # usbutils
      # pciutils
    ])
    # Mirror nixpkgs' all-terminfo list, minus rxvt-unicode-unwrapped-emoji
    # because it ships the same rxvt terminfo entries as rxvt-unicode-unwrapped.
    ++ (map (pkg: pkg.terminfo) (with pkgs.pkgsBuildBuild; [
      alacritty
      contour
      foot
      ghostty
      kitty
      mtm
      rio
      rxvt-unicode-unwrapped
      st
      tmux
      wezterm
      yaft
    ]));

  hardware.enableAllFirmware = true;

  services.udev.extraRules = ''
    # powercap: MODE sets the device-node perms, but the kernel creates the
    # `energy_uj` attribute as 0400 (Platypus side-channel mitigation), so btop
    # and node_exporter's (default-on) rapl collector can't read CPU package
    # power. chmod the attribute readable. (Local, trusted hosts.)
    ACTION=="add", SUBSYSTEM=="powercap", MODE="0666", RUN+="${pkgs.coreutils}/bin/chmod -R a+r /sys%p"
    ACTION=="add", SUBSYSTEM=="nvme", KERNEL=="nvme[0-9]*", RUN+="${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw /dev/$kernel"
    ACTION=="add"  SUBSYSTEM=="block", KERNEL=="sd[a-z]*", RUN+="${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw /dev/$kernel"
  '';

  # Smart card support (Yubikey) - lightweight, needed on any machine with a card reader
  services.pcscd.enable = true;

  services.irqbalance.enable = lib.mkDefault true;
  services.fwupd.enable = lib.mkDefault config.boot.kernelPackages.stdenv.hostPlatform.isx86_64;

  # fwupd-refresh.service runs `fwupdmgr refresh` as the non-interactive
  # `fwupd-refresh` user; polkit denies the metadata action by default
  # ("Failed to obtain auth"), failing the timer. Allow that user the fwupd
  # actions so the refresh succeeds.
  security.polkit.extraConfig = lib.mkIf config.services.fwupd.enable ''
    polkit.addRule(function(action, subject) {
      if (action.id.indexOf("org.freedesktop.fwupd.") == 0 &&
          subject.user == "fwupd-refresh") {
        return polkit.Result.YES;
      }
    });
  '';

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "262144";
    }
  ];
}
