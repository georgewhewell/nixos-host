{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./users.nix
  ];

  boot.kernelParams = [
    "pcie=pcie_bus_perf"
  ];

  networking.hosts = {
    "127.0.0.1" = ["localhost"];
    "192.168.23.1" = ["router"];
    "192.168.23.5" = ["nixhost"];
    "192.168.23.8" = ["trex"];
    "192.168.23.14" = ["n100"];
    "192.168.23.2" = ["mikrotik-10g"];
    "192.168.23.9" = ["mikrotik-100g"];
    "192.168.23.18" = ["rock-5b"];
  };

  services.dbus.packages = [pkgs.gcr];

  environment.systemPackages = with pkgs; [
    ethtool
    iotop
    rsync
    ncdu
    usbutils
    pciutils
  ];

  hardware.enableAllFirmware = true;

  services.irqbalance.enable = lib.mkDefault true;
  services.fwupd.enable = true;

  nix.optimise.automatic = true;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  location = {
    latitude = 51.5;
    longitude = 0.0;
  };

  environment.pathsToLink = ["/share/zsh"];

  programs.zsh = {
    enable = true;
    # enableGlobalCompInit = false;
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      MaxStartups 100:30:200
      MaxAuthTries 20
      MaxSessions 100
      StreamLocalBindUnlink yes
    '';
  };

  programs.ssh.extraConfig = ''
    Host *.satanic.link !satanic.link
      ProxyJump grw@satanic.link
    Host *.satanic.link !satanic.link
      ProxyJump none
      Match exec "ifconfig | grep -q '192.168.23.' && echo direct"
    Host *
      ControlPath ~/.ssh/control-%r@%h:%p
      ControlMaster auto
      ControlPersist 10m
      ServerAliveInterval 60
  '';

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

  systemd.services.nix-daemon.serviceConfig.LimitNOFILE = lib.mkForce 262144;

  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;
  };

  nix = {
    settings = {
      trusted-users = ["grw"];
      substituters = [
        "https://cuda-maintainers.cachix.org"
      ];
      trusted-public-keys = [
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
      download-buffer-size = 1024 * 1024 * 1024;
    };
    gc = {
      automatic = true;
      dates = pkgs.lib.mkDefault "weekly";
    };
  };
}
