{ config, pkgs, lib, ... }:

{

  imports = [
    ./users.nix
  ];

  environment.systemPackages = with pkgs; [
    kitty.terminfo
    alacritty.terminfo
    ethtool
  ];

  hardware.enableAllFirmware = true;

  services.fwupd.enable = true;
  programs.mosh.enable = true;
  networking.firewall.allowedUDPPorts = [ 5000 ];
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
    enableGlobalCompInit = false;
  };

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    gatewayPorts = "yes"; # needed for pgp forward?
    extraConfig = ''
      StreamLocalBindUnlink yes
    '';
  };

  programs.ssh.extraConfig = ''
    Host *.lan
      # todo..
      StrictHostKeyChecking no
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
