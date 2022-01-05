{ config, pkgs, ... }:

{

  imports = [
    ../modules/cache-cache.nix
    ../modules/usb-gadget.nix
    ../modules/devicetree.nix
    ../modules/besu.nix
    ../modules/geth.nix
    ../modules/ethminer.nix
    ../modules/graph-node.nix
    ../modules/openethereum.nix
    ../modules/nbd.nix
    ../modules/netboot.nix
    ../modules/miflora.nix
    ../modules/hsphfpd.nix
    ../modules/radeon-profile-daemon.nix
    ../modules/traffic-shaping.nix
    ./users.nix
  ];

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # services.fwupd.enable = true;
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

  services.avahi = {
    enable = true;
    nssmdns = true;
    publish.addresses = true;
    publish.domain = true;
    publish.enable = true;
    publish.userServices = true;
    publish.workstation = true;
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
    trustedUsers = [ "grw" ];
    gc = {
      automatic = false;
      dates = pkgs.lib.mkDefault "weekly";
    };
  };

}
