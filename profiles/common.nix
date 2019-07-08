{ config, pkgs, ...}:

{
  imports = [
    "${builtins.fetchTarball https://github.com/rycee/home-manager/archive/master.tar.gz}/nixos"
    ../modules/cache-cache.nix
    ./users.nix
  ];

  nixpkgs.overlays = [
    (import ../modules/overlay.nix)
  ];

  boot.kernelParams = [
    "nopti"
    "nospectre_v2"
    "l1tf=off"
    "nospec_store_bypass_disable"
    "no_stf_barrier"
    "elevator=noop"
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
    };
  };

  nix = {
    daemonIONiceLevel = 7;
    daemonNiceLevel = 10;
    trustedUsers = [ "grw" ];
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
    iotop
    xz
    p7zip
    unrar
    psmisc
    psutils
    pwgen
    tmux
    jq

    arp-scan
    ipmitool
    vnstat

    usbutils
    pciutils
    wirelesstools
    rxvt_unicode
    (aspellWithDicts (ps: with ps; [ en ]))

    (vim_configurable.customize {
      # Specifies the vim binary name.
      # E.g. set this to "my-vim" and you need to type "my-vim" to open this vim
      # This allows to have multiple vim packages installed (e.g. with a different set of plugins)
      name = "vim";
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
          "surround"
        ]; } ];
    })
  ];

}
