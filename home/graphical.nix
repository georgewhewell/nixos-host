{ config, pkgs, lib, ... }:

{

  imports = [
    ./alacritty.nix
    ./sway.nix
  ];


  programs.firefox = {
    enable = true;
    /* package = pkgs.firefox-wayland; */
    #package = pkgs.firefox-bin-unwrapped;
  };

  programs.vscode = {
    package = pkgs.vscodium;
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      bbenoist.Nix
      vscodevim.vim
      matklad.rust-analyzer
      ms-vsliveshare.vsliveshare
      (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
        mktplcRef = {
          publisher = "JuanBlanco";
          name = "solidity";
          version = "0.0.120";
          sha256 = "1ryxr80sk15dbwsh1hxyq9a7im6f8ma2g2ql0vzdmcwrkrhj65if";
        };
        meta = {
          license = lib.licenses.mit;
        };
      })
    ];
  };

  home.packages = with pkgs; [
    wl-clipboard

    corefonts
    dejavu_fonts
    ubuntu_font_family
    hack-font
    roboto
    powerline-fonts
    font-awesome-ttf
    source-code-pro
    source-sans-pro
    source-serif-pro
    font-awesome_5

    spotify
    vlc

    signal-desktop
    whatsapp-for-linux
    torbrowser
    monero-gui
    (steam.override { extraProfile = ''unset VK_ICD_FILENAMES''; })
    steam-run-native
    discord
    wineFull
    zoom-us
    calibre
    slack
  ];

  fonts.fontconfig.enable = pkgs.lib.mkForce true;

  services.redshift = {
    enable = true;
    package = pkgs.redshift-wlr;
    latitude = "51.5";
    longitude = "0";
    /* brightness = {
      day = "1";
      night = "0.6";
    }; */
  };
}
