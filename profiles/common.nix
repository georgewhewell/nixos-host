{
  config,
  pkgs,
  lib,
  ...
}: let
  network = import ../network.nix lib;
in {
  imports = [
    ./users.nix
    ./watchdog.nix
  ];

  # Expose `network` as a free function arg to every module in the same
  # NixOS evaluation. Set here because every host AND every container imports
  # this profile, so it covers both top-level and nested-container modules
  # (containers don't inherit parent specialArgs).
  _module.args.network = network;

  boot.swraid.mdadmConf = "MAILADDR root";

  networking.hosts =
    {"127.0.0.1" = ["localhost"];}
    // network.toNixosHosts;

  environment.enableAllTerminfo = true;

  environment.systemPackages = with pkgs; [
    rsync
    ethtool
    # iotop
    # ncdu
    # usbutils
    # pciutils
  ];

  hardware.enableAllFirmware = true;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="powercap", MODE="0666"
    ACTION=="add", SUBSYSTEM=="nvme", KERNEL=="nvme[0-9]*", RUN+="${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw /dev/$kernel"
    ACTION=="add"  SUBSYSTEM=="block", KERNEL=="sd[a-z]*", RUN+="${pkgs.acl}/bin/setfacl -m g:smartctl-exporter-access:rw /dev/$kernel"
  '';

  # Smart card support (Yubikey) - lightweight, needed on any machine with a card reader
  services.pcscd.enable = true;

  services.irqbalance.enable = lib.mkDefault true;
  services.fwupd.enable = lib.mkDefault config.boot.kernelPackages.stdenv.isx86_64;

  environment.pathsToLink = ["/share/zsh"];

  programs.zsh = {
    enable = true;
  };

  services.openssh = {
    enable = true;
    settings.AllowTcpForwarding = "yes";
    extraConfig = ''
      MaxStartups 100:30:200
      MaxAuthTries 20
      MaxSessions 100
      StreamLocalBindUnlink yes
    '';
  };

  console = {
    font = lib.mkDefault "Lat2-Terminus16";
    keyMap = "uk";
  };

  i18n.defaultLocale = "en_GB.UTF-8";

  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "262144";
    }
  ];

  # nixpkgs.config is now set in pkgsFor (flake.nix) and read-only via readOnlyPkgs

  # Core nix settings are in modules/nix.nix (auto-imported)
  nix.gc = {
    automatic = true;
    dates = pkgs.lib.mkDefault "weekly";
  };
}
