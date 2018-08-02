{ config, pkgs, ...}:

{
  imports = [
    ../modules/cache-cache.nix
    ./users.nix
  ];

  nixpkgs.overlays = [
      (import ../modules/overlay.nix)
  ];

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  boot.kernelParams = [ "elevator=noop" ];

  security.rngd.enable = pkgs.lib.mkDefault true;

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    gatewayPorts = "yes"; # needed for pgp forward?
    forwardX11 = true;
    extraConfig = ''
      StreamLocalBindUnlink yes
    '';
  };

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
      https://cache.satanic.link/
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
    rsync
    nox
    unzip
    gitAndTools.gitFull
    htop
    xz
    p7zip
    unrar
    psmisc
    psutils
    pwgen
    tmux
    nixops
    jq

    arp-scan
    ipmitool

    usbutils
    pciutils
    wirelesstools
    rxvt_unicode
    
    (vim_configurable.customize {
      # Specifies the vim binary name.
      # E.g. set this to "my-vim" and you need to type "my-vim" to open this vim
      # This allows to have multiple vim packages installed (e.g. with a different set of plugins)
      name = "myvim";
      vimrcConfig.customRC = ''
        syntax enable
        set number
        set bg=dark
        let g:solarized_termtrans = 1
        colorscheme solarized

        " tabs to spaces
        set smartindent
        set tabstop=2
        set shiftwidth=2
        set expandtab

        " syntastic
        set statusline+=%#warningmsg#
        set statusline+=%{SyntasticStatuslineFlag()}
        set statusline+=%*

        let g:syntastic_always_populate_loc_list = 1
        let g:syntastic_auto_loc_list = 1
        let g:syntastic_check_on_open = 1
        let g:syntastic_check_on_wq = 0
      '';
      vimrcConfig.vam.pluginDictionaries = [ 
        { names = [
          "commentary"
          "vim-elixir"
          "youcompleteme"
          "syntastic"
          "colors-solarized"
        ]; } ];
    })
  ];

}
