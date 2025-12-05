{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./users.nix
  ];

  networking.hosts = {
    "127.0.0.1" = ["localhost"];
    "192.168.23.1" = ["router"];
    "192.168.23.2" = ["mikrotik-10g"];
    "192.168.23.3" = ["ap"];
    "192.168.23.4" = ["x10-ipmi"];
    "192.168.23.5" = ["nixhost"];
    "192.168.23.6" = ["vacuum"];
    "192.168.23.7" = ["fuckup"];
    "192.168.23.8" = ["trex"];
    "192.168.23.9" = ["mikrotik-100g"];
    "192.168.23.10" = ["trx90bmc"];
    "192.168.23.11" = ["apc-ups"];
    "192.168.23.12" = ["printer"];
    "192.168.23.13" = ["cerberus"];
    "192.168.23.14" = ["n100"];
    "192.168.23.15" = ["arr-servers"];
    "192.168.23.16" = ["zigbee-stick"];
    "192.168.23.17" = ["nanokvm"];
    "192.168.23.18" = ["rock-5b"];
    "192.168.23.23" = ["poe-switch-10g"];
  };

  services.dbus.packages = [pkgs.gcr];
  environment.enableAllTerminfo = true;

  environment.systemPackages = with pkgs; [
    rsync
    # ethtool
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

  services.irqbalance.enable = lib.mkDefault true;
  services.fwupd.enable = config.boot.kernelPackages.stdenv.isx86_64;

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
    font = "Lat2-Terminus16";
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

  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;
  };

  nix = {
    settings = {
      trusted-users = ["grw"];
      trusted-public-keys = [
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "trex.satanic.link:R5wLrsrQGQdkEa9w+E1o3YibQ/VPVoPqQelJEw0yrtQ="
      ];
      experimental-features = ["nix-command" "flakes"];
    };
    gc = {
      automatic = true;
      dates = pkgs.lib.mkDefault "weekly";
    };
    optimise.automatic = true;
  };
}
