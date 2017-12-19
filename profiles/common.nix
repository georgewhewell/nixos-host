{ config, pkgs, ...}:

{
  imports = [
    ./users.nix
    ../modules/custom-packages.nix
    ../modules/bitcoin.nix
  ];

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;
  
  security.rngd.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.forwardX11 = true;
  programs.ssh.extraConfig = ''
    Host *.4a
      # todo..
      StrictHostKeyChecking no
  '';

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
        https://hydra.satanic.link/
        https://cache.nixos.org/
    ];
    binaryCachePublicKeys = [
      "hydra.satanic.link-1:U4ZvldOwA3GWLmFTqdXwUu9oS0Qzh4+H/HSl8O6ew5o="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    extraOptions = ''
      auto-optimise-store = true
    '';
  };

  environment.systemPackages = with pkgs; [
    acpi
    wget
    vim
    rsync
    nox
    unzip
    gitAndTools.gitFull
    htop
    xz
    p7zip
    psmisc
    psutils
    pwgen
    tmux
    nixops

    arp-scan
    ipmitool

    usbutils
    pciutils
    wirelesstools
  ];

}
