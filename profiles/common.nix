{ config, pkgs, ...}:

{
  imports = [
    ./users.nix
    ../modules/custom-packages.nix
    ../modules/bitcoin.nix
    ../services/usbmuxd.nix
  ];

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;

  # Start ssh-agent
  programs.ssh.startAgent = true;
  programs.ssh.forwardX11 = true;

  i18n = {
    consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "uk";
    defaultLocale = "en_GB.UTF-8";
  };

  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = true;
    chromium = {
     enablePepperFlash = true;
     enablePepperPDF = true;
    };
  };

  nix = {
    buildCores = 0;
    daemonIONiceLevel = 7;
    daemonNiceLevel = 10;
    trustedUsers = [ "grw" ];
    nixPath = [
      "nixpkgs=/etc/nixos/nixpkgs"
      "nixos-config=/etc/nixos/configuration.nix"
    ];
    binaryCaches = [
      https://cache.nixos.org
    ];
    binaryCachePublicKeys = [
      "hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
    ];
    extraOptions = ''
      auto-optimise-store = true
    '';
  };

  environment.systemPackages = with pkgs; [
    wget
    atom
    vim
    rsync
    chromium
    nox
    unzip
    gitAndTools.gitFull
    htop
    xz
    psmisc
    pwgen
    tmux
  ];

}
