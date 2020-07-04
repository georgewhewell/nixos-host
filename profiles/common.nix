{ config, pkgs, ... }:

{

  imports = [
    ../modules/cache-cache.nix
    ../modules/usb-gadget.nix
    ../modules/devicetree.nix
    ../modules/sunxi-watchdog.nix
    ../modules/nbd.nix
    ../modules/netboot.nix
    ../modules/miflora.nix
    ../modules/hsphfpd.nix
    ../modules/radeon-profile-daemon.nix
    ../modules/traffic-shaping.nix
    ./users.nix
  ];

  location = {
    latitude = 51.5;
    longitude = 0.0;
  };

  environment.pathsToLink = [ "/share/zsh" ];

  nixpkgs.overlays = [
    (import ../modules/overlay.nix)
  ];

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

  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;
  };

  nix = {
    daemonIONiceLevel = 7;
    daemonNiceLevel = 10;
    trustedUsers = [ "grw" ];
    gc = {
      automatic = true;
      dates = pkgs.lib.mkDefault "weekly";
    };
  };

  environment.systemPackages = with pkgs; [
    /* alacritty.terminfo
    termite.terminfo */
  ];

}
