{
  config,
  pkgs,
  lib,
  inputs,
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
    "192.168.23.1" = ["gateway"];
    "192.168.23.5" = ["nixhost"];
    "192.168.23.8" = ["trex"];
    "192.168.23.9" = ["mikrotik-100g"];
    "192.168.23.18" = ["rock-5b"];
    "192.168.23.254" = ["router"];
  };

  nixpkgs.config.permittedInsecurePackages = [
    "aspnetcore-runtime-6.0.36"
    "aspnetcore-runtime-wrapped-6.0.36"
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
  ];

  services.dbus.packages = [pkgs.gcr];

  environment.systemPackages = with pkgs; [
    ethtool
    iotop
    rsync
    ncdu
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
    Host *.lan.satanic.link
      # todo..
      StrictHostKeyChecking no

    Match host *.satanic.link !localnetwork 192.168.23.0/24
      controlmaster auto
      controlpath /tmp/ssh-%r@%h:%p
      ProxyCommand ${pkgs.bash}/bin/bash -c "${pkgs.openssh}/bin/ssh -W $(echo %h | cut -d. -f1):%p grw@satanic.link"
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
