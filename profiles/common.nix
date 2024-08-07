{ config, pkgs, lib, inputs, ... }:

{

  imports = [
    ./users.nix
  ];

  boot.kernelParams = [
    "pcie=pcie_bus_perf"
  ];

  networking.hosts = {
    "127.0.0.1" = [ "localhost" ];
    "192.168.23.1" = [ "router" "router.satanic.link" ];
    "192.168.23.5" = [ "nixhost" "nixhost.satanic.link" ];
    "192.168.23.7" = [ "fuckup" "fuckup.satanic.link" ];
    "192.168.23.8" = [ "trex" "trex.satanic.link" ];
    "192.168.23.9" = [ "mikrotik-100g" "mikrotik-100.satanic.link" ];
    "192.168.23.11" = [ "rock-5b" "rock-5b.satanic.link" ];
    "192.168.23.206" = [ "jellyfin" ];
  };

  # environment.etc.nixpkgs.source = toString pkgs.nixpkgs_src;

  services.dbus.packages = [ pkgs.gcr ];

  environment.systemPackages = with pkgs; [
    #kitty.terminfo
    #alacritty.terminfo
    ethtool
    iotop
    rsync
  ];

  hardware.enableAllFirmware = true;

  services.irqbalance.enable = lib.mkDefault true;
  services.fwupd.enable = true;
  programs.mosh.enable = true;

  nix.extraOptions = ''
    auto-optimise-store = true
    experimental-features = nix-command flakes
  '';

  location = {
    latitude = 51.5;
    longitude = 0.0;
  };

  environment.pathsToLink = [ "/share/zsh" ];

  programs.zsh = {
    enable = true;
    #   enableGlobalCompInit = false;
  };

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    extraConfig = ''
      StreamLocalBindUnlink yes
    '';
  };

  programs.ssh.extraConfig = ''
    Host *.lan
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

  security.pam.loginLimits = [{
    domain = "*";
    type = "soft";
    item = "nofile";
    value = "262144";
  }];

  systemd.services.nix-daemon.serviceConfig.LimitNOFILE = lib.mkForce 262144;

  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;
  };

  nix = {
    settings = {
      trusted-users = [ "grw" ];
    };
    gc = {
      automatic = true;
      dates = pkgs.lib.mkDefault "weekly";
    };
  };

}
